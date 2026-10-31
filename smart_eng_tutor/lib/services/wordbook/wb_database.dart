import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_fsrs.dart';
import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'dart:math' as math;
import 'package:smart_eng_tutor/services/lookup/lk_text_utils.dart';
/// 词条复习状态的数据库快照（撤回打分用）
class ReviewSnapshot {
  final int entryId;
  final int progress;
  final double stability;
  final double difficulty;
  final int dueAt;
  final int? lastReviewedAt;
  const ReviewSnapshot({
    required this.entryId,
    required this.progress,
    required this.stability,
    required this.difficulty,
    required this.dueAt,
    this.lastReviewedAt,
  });
}

/// wordbook.db —— 复习信息直接存在 wordbook_words 行内（FSRS-6）。
///
/// ★ 全局单例：唯一入口为 [WordbookDatabase.instance]，
///   不提供公有构造，禁止 `WordbookDatabase()` 直接实例化。
///
/// wordbook_words:
/// id, bookId, dictId, word,
/// progress (0=New 1=Learning 2=Review 3=Relearning),
/// stability (S, 天), difficulty (D, 1~10),
/// dueAt (毫秒), lastReviewedAt (毫秒), contexts (JSON, 可空)
class WordbookDatabase {
  Database? _bookDb;

  // ===== 单例：唯一入口 =====
  WordbookDatabase._internal();
  static final WordbookDatabase instance = WordbookDatabase._internal();

  late final String _docPath;
  FsrsEngine? _fsrs;

  Future<bool>? _initting; // 防重入：并发 init 只执行一次

  Future<bool> init() => _initting ??= _doInit();

  Future<bool> _doInit() async {
    try {
      _docPath = (await getApplicationDocumentsDirectory()).path;
      _fsrs = await FsrsEngine.create();
      return await _initBookDb();
    } catch (e) {
      return false;
    }
  }

  Future<void> _copyFromAssets(String assetPath, String dbPath) async {
    final dbDir = Directory(dirname(dbPath));
    if (!await dbDir.exists()) dbDir.create(recursive: true);
    final data = await rootBundle.load(assetPath);
    await File(dbPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

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
      await _bookDb!.insert('wordbooks', {'name': '默认词库'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 幂等迁移：老库（无 FSRS 列 / 有 review_schedule）→ 新结构
  Future<void> _ensureExtraSchema() async {
    final db = _bookDb!;

    // 新库完整建表（已存在则跳过）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wordbook_words(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL,
        dictId INTEGER,
        word TEXT NOT NULL,
        progress INTEGER NOT NULL DEFAULT 0,
        stability REAL NOT NULL DEFAULT 0,
        difficulty REAL NOT NULL DEFAULT 0,
        dueAt INTEGER NOT NULL DEFAULT 0,
        lastReviewedAt INTEGER,
        contexts TEXT,
        UNIQUE(bookId, word)
      )
    ''');

    // 老库补列
    const cols = {
      'progress': 'INTEGER NOT NULL DEFAULT 0',
      'stability': 'REAL NOT NULL DEFAULT 0',
      'difficulty': 'REAL NOT NULL DEFAULT 0',
      'dueAt': 'INTEGER NOT NULL DEFAULT 0',
      'lastReviewedAt': 'INTEGER',
      'contexts': 'TEXT',
    };
    for (final e in cols.entries) {
      try {
        await db.execute(
            'ALTER TABLE wordbook_words ADD COLUMN ${e.key} ${e.value}');
      } catch (_) {}
    }

    // 旧调度表退役（数据已并入词条行）
    await db.execute('DROP TABLE IF EXISTS review_schedule');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_words_book_due ON wordbook_words(bookId, dueAt)');
  }

  // ==================== 词库查询 ====================

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
            id: r['id'] as int, name: r['name'] as String, wordCount: r['cnt'] as int))
        .toList();
  }

  Future<bool> isFavorited(String word, {int? bookId}) async {
    if (_bookDb == null) return false;
    final bid = bookId ?? await _defaultBookId();
    final rows = await _bookDb!.query('wordbook_words',
        where: 'bookId = ? AND word = ?',
        whereArgs: [bid, word],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// 收藏（progress=New，dueAt=now 立即到期）
  Future<String> addWord(String word, {int? bookId, int? dictId = 1}) async {
    if (_bookDb == null) return 'error';
    try {
      final bid = bookId ?? await _defaultBookId();
      final id = await _bookDb!.insert('wordbook_words', {
        'bookId': bid,
        'dictId': dictId,
        'word': LkTextUtils.strip(word),
        'progress': 0,
        'stability': 0,
        'difficulty': 0,
        'dueAt': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return id > 0 ? 'added' : 'exists';
    } catch (e) {
      return 'error';
    }
  }

  Future<bool> removeWord(String word, {int? bookId}) async {
    if (_bookDb == null) return false;
    final bid = bookId ?? await _defaultBookId();
    final n = await _bookDb!.delete('wordbook_words',
        where: 'bookId = ? AND word = ?', whereArgs: [bid, word]);
    return n > 0;
  }

  Future<List<WordbookEntry>> queryEntries(int bookId) async {
    if (_bookDb == null) return [];
    final rows = await _bookDb!.query('wordbook_words',
        where: 'bookId = ?', whereArgs: [bookId], orderBy: 'id DESC');
    return rows.map(_entryFromRow).toList();
  }

  WordbookEntry _entryFromRow(Map<String, Object?> r) => WordbookEntry(
        id: r['id'] as int,
        bookId: r['bookId'] as int,
        dictId: r['dictId'] as int?,
        word: r['word'] as String,
        progress: (r['progress'] as int?) ?? 0,
        dueAt: (r['dueAt'] as int?) ?? 0,
        contexts: r['contexts'] as String?,
      );

  // ==================== 词库管理 ====================

  Future<int?> createBook(String name) async {
    if (_bookDb == null || name.trim().isEmpty) return null;
    final id = await _bookDb!.insert('wordbooks', {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id > 0 ? id : null;
  }

  Future<bool> deleteBook(int bookId) async {
    if (_bookDb == null) return false;
    if (bookId == await _defaultBookId()) return false;
    await _bookDb!
        .delete('wordbook_words', where: 'bookId = ?', whereArgs: [bookId]);
    final d = await _bookDb!
        .delete('wordbooks', where: 'id = ?', whereArgs: [bookId]);
    return d > 0;
  }

  Future<int> deleteWords(List<int> entryIds) async {
    if (_bookDb == null || entryIds.isEmpty) return 0;
    final ph = List.filled(entryIds.length, '?').join(',');
    return _bookDb!
        .delete('wordbook_words', where: 'id IN ($ph)', whereArgs: entryIds);
  }

  Future<List<Wordbook>> queryOtherBooks(int excludeBookId) async =>
      (await queryWordbooks()).where((b) => b.id != excludeBookId).toList();

  /// 复制/移动的公共实现：整行覆盖（含复习记录 FSRS 状态）。
  /// UNIQUE(bookId, word) 冲突时 replace 覆盖目标词条。
  Future<int> _copyRows(List<int> ids, int targetBookId,
      {bool deleteSource = false}) async {
    if (_bookDb == null || ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await _bookDb!
        .query('wordbook_words', where: 'id IN ($ph)', whereArgs: ids);
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final r in rows) {
        final row = Map<String, Object?>.from(r)
          ..['bookId'] = targetBookId
          ..remove('id'); // 让目标库重新分配主键
        final id = await txn.insert('wordbook_words', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (id > 0) n++;
      }
      if (deleteSource) {
        await txn
            .delete('wordbook_words', where: 'id IN ($ph)', whereArgs: ids);
      }
    });
    return n;
  }

  /// 复制到目标词库：目标已有同词 → 连同复习记录一起覆盖
  Future<int> copyWords(List<WordbookEntry> entries, int targetBookId) =>
      _copyRows(entries.map((e) => e.id).toList(), targetBookId);

  /// 剪切到目标词库：覆盖后删除源词条
  Future<int> moveWords(List<WordbookEntry> entries, int targetBookId) =>
      _copyRows(entries.map((e) => e.id).toList(), targetBookId,
          deleteSource: true);


  // ==================== 批量导入 ====================

  /// 按词典声明的粒度导入：
  /// - word：按单词（queryRange）
  /// - chunk：每个含 eng+zh 的词块一条（queryChunkRange）
  Future<int> importRange(Dictionary dict, String from, String to,
      {int? bookId}) async {
    if (_bookDb == null) return 0;
    final bid = bookId ?? await _defaultBookId();
    final now = DateTime.now().millisecondsSinceEpoch;
    int n = 0;
    await _bookDb!.transaction((txn) async {
      if (dict.granularity == DictGranularity.chunk) {
        final chunks = await dict.queryChunkRange(from, to);
        for (final c in chunks) {
          final id = await txn.insert(
              'wordbook_words',
              {
                'bookId': bid,
                'dictId': dict.id,
                'word': LkTextUtils.strip(c.eng),
                'progress': 0,
                'stability': 0,
                'difficulty': 0,
                'dueAt': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          if (id > 0) n++;
        }
      } else {
        final words = await dict.queryRange(from, to);
        for (final w in words) {
          final id = await txn.insert(
              'wordbook_words',
              {
                'bookId': bid,
                'dictId': dict.id,
                'word': LkTextUtils.strip(w),
                'progress': 0,
                'stability': 0,
                'difficulty': 0,
                'dueAt': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          if (id > 0) n++;
        }
      }
    });
    return n;
  }

  // ==================== 复习（FSRS-6） ====================

  /// 到期词条
  Future<List<WordbookEntry>> queryDueReviews({int? bookId, int? limit}) async {
    if (_bookDb == null) return [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _bookDb!.query('wordbook_words',
        where: 'bookId = ? AND dueAt <= ?',
        whereArgs: [bookId, now],
        orderBy: 'dueAt ASC',
        limit: limit);
    return rows.map(_entryFromRow).toList();
  }

  /// 打分。rating: 0=答错 1=不熟练 2=答对（映射 Again/Hard/Good）
  Future<void> recordReview(int entryId, int rating) async {
    if (_bookDb == null || _fsrs == null) return;
    final rows = await _bookDb!.query('wordbook_words',
        where: 'id = ?', whereArgs: [entryId], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;

    final s = (row['stability'] as num?)?.toDouble() ?? 0;
    final d = (row['difficulty'] as num?)?.toDouble() ?? 0;
    final last = row['lastReviewedAt'] as int?;
    final isNew = s <= 0; // 从未复习过
    final daysElapsed = last == null
        ? 0.0
        : (DateTime.now().millisecondsSinceEpoch - last) / 86400000.0;

    final out = await _fsrs!.review(
      isNew: isNew,
      stability: s,
      difficulty: d,
      rating: rating,
      daysElapsed: daysElapsed,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    // progress 直接用 FSRS 状态：答对 → Review；答错 → Learning/Relearning
    final prevProgress = (row['progress'] as int?) ?? 0;
    final progress = rating == 0 ? (prevProgress == 2 ? 3 : 1) : 2;

    // 到期：Review → interval；Learning/Relearning → 10 分钟
    final dueAt = progress == 2
        ? now + (math.max(out.intervalDays, 10 / 1440) * 86400000).round()
        : now + 10 * 60 * 1000;

    await _bookDb!.update(
      'wordbook_words',
      {
        'progress': progress,
        'stability': out.stability,
        'difficulty': out.difficulty,
        'dueAt': dueAt,
        'lastReviewedAt': now,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }
    /// ★ 复习状态快照（撤回打分用）
  Future<ReviewSnapshot?> getReviewSnapshot(int entryId) async {
    if (_bookDb == null) return null;
    final rows = await _bookDb!.query('wordbook_words',
        where: 'id = ?', whereArgs: [entryId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ReviewSnapshot(
      entryId: entryId,
      progress: (r['progress'] as int?) ?? 0,
      stability: (r['stability'] as num?)?.toDouble() ?? 0,
      difficulty: (r['difficulty'] as num?)?.toDouble() ?? 0,
      dueAt: (r['dueAt'] as int?) ?? 0,
      lastReviewedAt: r['lastReviewedAt'] as int?,
    );
  }

  /// ★ 恢复复习状态（撤销打分）
  Future<void> restoreReviewSnapshot(ReviewSnapshot snap) async {
    if (_bookDb == null) return;
    await _bookDb!.update(
      'wordbook_words',
      {
        'progress': snap.progress,
        'stability': snap.stability,
        'difficulty': snap.difficulty,
        'dueAt': snap.dueAt,
        'lastReviewedAt': snap.lastReviewedAt,
      },
      where: 'id = ?',
      whereArgs: [snap.entryId],
    );
  }

  /// ★ 撤销打分：把词条的复习状态恢复到打分前的快照
  Future<void> restoreReviewState({
    required int entryId,
    required int progress,
    required double stability,
    required double difficulty,
    required int dueAt,
    int? lastReviewedAt,
  }) async {
    if (_bookDb == null) return;
    await _bookDb!.update(
      'wordbook_words',
      {
        'progress': progress,
        'stability': stability,
        'difficulty': difficulty,
        'dueAt': dueAt,
        'lastReviewedAt': lastReviewedAt,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  /// 按词库+词查词条（详情页显示复习情况）
  Future<WordbookEntry?> findEntry(int bookId, String word) async {
    if (_bookDb == null) return null;
    final rows = await _bookDb!.query('wordbook_words',
        where: 'bookId = ? AND word = ?',
        whereArgs: [bookId, word],
        limit: 1);
    return rows.isEmpty ? null : _entryFromRow(rows.first);
  }
  /// 按主键查词条（详情页显示复习情况）
  Future<WordbookEntry?> getEntry(int entryId) async {
    if (_bookDb == null) return null;
    final rows = await _bookDb!.query('wordbook_words',
        where: 'id = ?', whereArgs: [entryId], limit: 1);
    return rows.isEmpty ? null : _entryFromRow(rows.first);
  }

  /// 仅供 app 退出时调用；页面/服务不要调用（单例生命周期 = app 生命周期）
  void dispose() {
    _bookDb?.close();
  }

  Future<int> _defaultBookId() async {
    final rows = await _bookDb!.query('wordbooks',
        where: 'name = ?', whereArgs: ['默认词库'], limit: 1);
    return rows.first['id'] as int;
  }
}
