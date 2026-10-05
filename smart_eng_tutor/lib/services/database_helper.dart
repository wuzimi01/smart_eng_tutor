import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import 'models.dart';

/// 只负责 wordbook.db（收藏、词库管理）。
/// 词典数据（stardict.db / lemma.en.db）已移交 lib/dictionary/ 各词典自管。
class DatabaseHelper {
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
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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
        where: 'bookId = ? AND word = ?',
        whereArgs: [bid, word],
        limit: 1);
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
    final d = await _bookDb!.delete('wordbooks', where: 'id = ?', whereArgs: [bookId]);
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

  void dispose() {
    _bookDb?.close();
  }

  Future<int> _defaultBookId() async {
    final rows = await _bookDb!.query('wordbooks',
        where: 'name = ?', whereArgs: ['默认词库'], limit: 1);
    return rows.first['id'] as int;
  }
}
