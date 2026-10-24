import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';
import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';

/// 只负责 wordbook.db（收藏、词库管理）。
/// 词典数据（stardict.db / lemma.en.db）已移交 lib/dictionary/ 各词典自管。
class WordbookDatabase {
  Database? _bookDb;
  late final String _docPath;

  Future<bool> init() async {
    try {
      _docPath = (await getApplicationDocumentsDirectory()).path;
      return await _initBookDb();
    } catch (e) {
      return false;
    }
  }

  Future<void> _copyFromAssets(String assetPath, String dbPath) async {
    final dbDir = Directory(dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(dbPath).writeAsBytes(bytes);
  }

  /// 打开/创建词库库。
  /// 首次运行时从 assets/wordbook.db 拷贝（含预导入的考纲词库），
  /// 之后 app 端不再覆盖 —— 保证用户的收藏数据不被重置。
  Future<bool> _initBookDb() async {
    try {
      final bookPath = join(_docPath, 'wordbook.db');
      if (!await File(bookPath).exists()) {
        try {
          await _copyFromAssets('assets/wordbook.db', bookPath);
        } catch (e) {
          return false;
        }
      }
      _bookDb = await openDatabase(bookPath, version: 1);
      await _ensureExtraSchema();
      // 幂等兜底：assets 的 db 可能没有默认词库
      await _bookDb!.insert('wordbooks', {'name': '默认词库'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== 词库查询 ====================

  /// 所有词库（含每个词库的词条数）
  Future<List<Wordbook>> queryWordbooks() async {
    if (_bookDb == null) return [];
    final rows = await _bookDb!.rawQuery('''
      SELECT w.id, w.name, COUNT(s.id) AS cnt
      FROM wordbooks w
      LEFT JOIN wordbook_words s ON s.bookId = w.id
      GROUP BY w.id, w.name
      ORDER BY w.id
    ''');
    return rows
        .map((r) => Wordbook(
              id: r['id'] as int,
              name: r['name'] as String,
              wordCount: r['cnt'] as int,
            ))
        .toList();
  }

  /// 某词是否已收藏于指定词库
  Future<bool> isFavorited(String word, {int? bookId}) async {
    if (_bookDb == null) return false;
    final bid = bookId ?? await _defaultBookId();
    final rows = await _bookDb!.query('wordbook_words',
        where: 'bookId = ? AND word = ?', whereArgs: [bid, word], limit: 1);
    return rows.isNotEmpty;
  }

  /// 收藏。返回 'added' 新收藏 / 'exists' 已存在 / 'error' 出错
  /// 默认写入词典 ID 1（与 BuiltinDict.dictId 一致）
  Future<String> addWord(String word, {int? bookId, int? dictId = 1}) async {
    if (_bookDb == null) return 'error';
    try {
      final bid = bookId ?? await _defaultBookId();
      final id = await _bookDb!.insert(
        'wordbook_words',
        {'bookId': bid, 'dictId': dictId, 'word': word},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return id > 0 ? 'added' : 'exists';
    } catch (e) {
      return 'error';
    }
  }

  /// 取消收藏
  Future<bool> removeWord(String word, {int? bookId}) async {
    if (_bookDb == null) return false;
    final bid = bookId ?? await _defaultBookId();
    final n = await _bookDb!.delete('wordbook_words',
        where: 'bookId = ? AND word = ?', whereArgs: [bid, word]);
    return n > 0;
  }

  /// 某词库的全部词条（按收藏时间倒序）
  Future<List<WordbookEntry>> queryEntries(int bookId) async {
    if (_bookDb == null) return [];
    final rows = await _bookDb!.query(
      'wordbook_words',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'id DESC',
    );
    return rows
        .map((r) => WordbookEntry(
              id: r['id'] as int,
              bookId: r['bookId'] as int,
              dictId: r['dictId'] as int?,
              word: r['word'] as String,
            ))
        .toList();
  }

  // ==================== 词库管理（多词库） ====================

  /// 新建词库。成功返回 id，重名返回 null。
  Future<int?> createBook(String name) async {
    if (_bookDb == null || name.trim().isEmpty) return null;
    final id = await _bookDb!.insert('wordbooks', {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id > 0 ? id : null;
  }

  /// 删除词库（先删词条再删词库，默认词库不允许删）。
  Future<bool> deleteBook(int bookId) async {
    if (_bookDb == null) return false;
    if (bookId == await _defaultBookId()) return false;
    final n = await _bookDb!
        .delete('wordbook_words', where: 'bookId = ?', whereArgs: [bookId]);
    final d = await _bookDb!
        .delete('wordbooks', where: 'id = ?', whereArgs: [bookId]);
    return d > 0 || n > 0;
  }

  /// 批量删除词条。
  Future<int> deleteWords(List<int> entryIds) async {
    if (_bookDb == null || entryIds.isEmpty) return 0;
    final ph = List.filled(entryIds.length, '?').join(',');
    return _bookDb!
        .delete('wordbook_words', where: 'id IN ($ph)', whereArgs: entryIds);
  }

  /// 查询其他词库（用于"复制/剪切到..."选择目标）。
  Future<List<Wordbook>> queryOtherBooks(int excludeBookId) async {
    return (await queryWordbooks()).where((b) => b.id != excludeBookId).toList();
  }

  Map<String, Object?> _wordRow(WordbookEntry e, int targetBookId) => {
        'bookId': targetBookId,
        'dictId': e.dictId, // 词典 ID 随词走（多词典功能预留，本词典 = 1）
        'word': e.word,
      };

  Future<int> copyWords(List<WordbookEntry> entries, int targetBookId) async {
    if (_bookDb == null || entries.isEmpty) return 0;
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final e in entries) {
        final id = await txn.insert('wordbook_words', _wordRow(e, targetBookId),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id > 0) n++;
      }
    });
    return n;
  }

  Future<int> moveWords(List<WordbookEntry> entries, int targetBookId) async {
    if (_bookDb == null || entries.isEmpty) return 0;
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final e in entries) {
        final id = await txn.insert('wordbook_words', _wordRow(e, targetBookId),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id > 0) {
          await txn.delete('wordbook_words', where: 'id = ?', whereArgs: [e.id]);
          n++;
        }
      }
    });
    return n;
  }

  /// 复习调度表（assets 的 db 没有它，运行时幂等创建）
  Future<void> _ensureExtraSchema() async {
    await _bookDb!.execute('''
      CREATE TABLE IF NOT EXISTS review_schedule(
        word TEXT NOT NULL,
        bookId INTEGER NOT NULL,
        level INTEGER NOT NULL DEFAULT 0,
        dueAt INTEGER NOT NULL,
        lastReviewedAt INTEGER,
        PRIMARY KEY(word, bookId)
      )
    ''');
  }

  // ==================== 批量导入 ====================

  /// 从词典批量导入 [from, to] 范围的单词到指定词库。
  /// dictId 记为词典自身 id（0=读文章收藏，1=默认词典，2+=导入词典）。
  /// 返回实际新导入数量。
  Future<int> importRange(Dictionary dict, String from, String to,
      {int? bookId}) async {
    if (_bookDb == null) return 0;
    final bid = bookId ?? await _defaultBookId();
    final words = await dict.queryRange(from, to);
    if (words.isEmpty) return 0;
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final w in words) {
        final id = await txn.insert(
          'wordbook_words',
          {'bookId': bid, 'dictId': dict.id, 'word': w},
          conflictAlgorithm: ConflictAlgorithm.ignore, // 已存在跳过
        );
        if (id > 0) n++;
      }
    });
    return n;
  }

  // ==================== 复习调度 ====================

  /// 某词库内到期需复习的词条（bookId 为 null 时跨词库）
  Future<List<WordbookEntry>> queryDueReviews({int? bookId, int? limit}) async {
    if (_bookDb == null) return [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final where = StringBuffer('WHERE r.dueAt <= ?');
    final args = <Object?>[now];
    if (bookId != null) {
      where.write(' AND s.bookId = ?');
      args.add(bookId);
    }
    final sql = '''
      SELECT s.id AS id, s.bookId, s.dictId, s.word
      FROM wordbook_words s
      JOIN review_schedule r ON r.word = s.word AND r.bookId = s.bookId
      $where
      ORDER BY r.dueAt ASC
    ''';
    final rows = await _bookDb!.rawQuery(
      limit != null ? '$sql LIMIT ?' : sql,
      limit != null ? [...args, limit] : args,
    );
    return rows
        .map((r) => WordbookEntry(
              id: r['id'] as int,
              bookId: r['bookId'] as int,
              dictId: r['dictId'] as int?,
              word: r['word'] as String,
            ))
        .toList();
  }

  /// 记录一次复习打分。quality: 2=答对 1=不熟练 0=答错
  Future<void> recordReview(String word, int bookId, int quality) async {
    if (_bookDb == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _bookDb!.query('review_schedule',
        where: 'word = ? AND bookId = ?',
        whereArgs: [word, bookId],
        limit: 1);
    int level = rows.isNotEmpty ? (rows.first['level'] as int) : 0;
    // 等级调整：答对升级，不熟练持平，答错降一级
    if (quality >= 2) level++;
    if (quality == 0 && level > 0) level--;
    final intervals = const [10 / 1440, 1, 3, 7, 14, 30]; // 天：新词10分钟起
    final days = intervals[level.clamp(0, intervals.length - 1)];
    final dueAt = now + (days * 86400000).round();
    await _bookDb!.insert('review_schedule', {
      'word': word,
      'bookId': bookId,
      'level': level,
      'dueAt': dueAt,
      'lastReviewedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 把某词库全部词条登记为待复习（导入后调用，或词库页手动"加入复习"）
  Future<int> enrollReviews(int bookId) async {
    if (_bookDb == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _bookDb!.query('wordbook_words',
        columns: ['word'], where: 'bookId = ?', whereArgs: [bookId]);
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final r in rows) {
        await txn.insert('review_schedule',
            {'word': r['word'], 'bookId': bookId, 'level': 0, 'dueAt': now},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        n++;
      }
    });
    return n;
  }

  void dispose() {
    _bookDb?.close();
  }

  Future<int> _defaultBookId() async {
    final rows = await _bookDb!.query('wordbooks',
        where: 'name = ?', whereArgs: ['默认词库'], limit: 1);
    return rows.first['id'] as int;
  }
}
