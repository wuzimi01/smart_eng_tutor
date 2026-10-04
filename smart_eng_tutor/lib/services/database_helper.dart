import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import 'models.dart';

class DatabaseHelper {
  Database? _lemmaDb;
  Database? _dictDb;

  Database? get lemmaDb => _lemmaDb;
  Database? get dictDb => _dictDb;
  Database? _bookDb; // 词库数据库（新建，可读写）
  late final String _docPath; // 应用文档目录（init 时赋值）
  /// 初始化两个数据库，成功返回 true
  Future<bool> init() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _docPath = appDocDir.path;
      // ---- 词根库 ----
      final lemmaPath = join(appDocDir.path, 'lemma.en.db');
      if (!await File(lemmaPath).exists()) {
        try {
          await _copyFromAssets('assets/lemma.en.db', lemmaPath);
        } catch (e) {
          return false;
        }
      }
      _lemmaDb = await openDatabase(lemmaPath);

      // ---- 释义库 ----
      final dictPath = join(appDocDir.path, 'stardict.db');
      if (!await File(dictPath).exists()) {
        try {
          await _copyFromAssets('assets/stardict.db', dictPath);
        } catch (e) {
          return false;
        }
      }
      _dictDb = await openDatabase(dictPath, readOnly: true);
      if (!await _initBookDb()) return false;
      return true;
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

  /// 查某词的释义；查不到返回 null
  Future<List<Map<String, Object?>>?> queryTranslation(String word) async {
    if (_dictDb == null) return null;
    final results = await _dictDb!.query(
      'stardict',
      columns: ['word', 'translation'],
      where: 'word = ?',
      whereArgs: [word],
    );
    return results.isEmpty ? null : results;
  }

  /// 查所有原型（weight 降序）
  Future<List<String>> queryStems(String word) async {
    if (_lemmaDb == null) return [];
    final rows = await _lemmaDb!.query(
      'word_stem',
      columns: ['stem'],
      where: 'word = ?',
      whereArgs: [word],
      orderBy: 'weight DESC',
    );
    return rows.map((row) => row['stem'] as String).toList();
  }

    // ==================== 词库（单词本） ====================

  /// 打开/创建词库库，并确保默认词库存在。在 init() 末尾调用。
  Future<bool> _initBookDb() async {
    try {
      final bookPath = join(_docPath, 'wordbook.db');
      _bookDb = await openDatabase(bookPath, version: 1, onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE wordbooks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');
        await db.execute('''
          CREATE TABLE wordbook_words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL,
            word TEXT NOT NULL,
            translation TEXT,
            createdAt TEXT NOT NULL,
            UNIQUE(bookId, word),
            FOREIGN KEY(bookId) REFERENCES wordbooks(id)
          )
        ''');
      });
      // 确保默认词库存在（幂等）
      await _bookDb!.insert('wordbooks', {'name': '默认词库'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    } catch (e) {
      return false;
    }
  }
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
  Future<String> addWord(String word, String? translation, {int? bookId}) async {
    if (_bookDb == null) return 'error';
    try {
      final bid = bookId ?? await _defaultBookId();
      final id = await _bookDb!.insert(
        'wordbook_words',
        {
          'bookId': bid,
          'word': word,
          'translation': translation,
          'createdAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return id > 0 ? 'added' : 'exists'; // 0 = 冲突被忽略 = 已经收藏过
    } catch (e) {
      return 'error'; // 真正的数据库错误（如表不存在）
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
      orderBy: 'createdAt DESC',
    );
    return rows
        .map((r) => WordbookEntry(
              id: r['id'] as int,
              bookId: r['bookId'] as int,
              word: r['word'] as String,
              translation: r['translation'] as String?,
              createdAt: r['createdAt'] as String,
            ))
        .toList();
  }

    // ==================== 词库管理（多词库） ====================

  /// 新建词库。成功返回 id，重名返回 null。
  Future<int?> createBook(String name) async {
    if (_bookDb == null || name.trim().isEmpty) return null;
    final id = await _bookDb!.insert('wordbooks', {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore); // UNIQUE 拦重名
    return id > 0 ? id : null;
  }

  /// 删除词库（先删词条再删词库，默认词库不允许删）。
  Future<bool> deleteBook(int bookId) async {
    if (_bookDb == null) return false;
    if (bookId == await _defaultBookId()) return false; // 保护默认词库
    final n = await _bookDb!.delete('wordbook_words',
        where: 'bookId = ?', whereArgs: [bookId]);
    final d = await _bookDb!
        .delete('wordbooks', where: 'id = ?', whereArgs: [bookId]);
    return d > 0 || n > 0;
  }

  /// 批量删除词条。
  Future<int> deleteWords(List<int> entryIds) async {
    if (_bookDb == null || entryIds.isEmpty) return 0;
    final ph = List.filled(entryIds.length, '?').join(',');
    return _bookDb!.delete('wordbook_words',
        where: 'id IN ($ph)', whereArgs: entryIds);
  }

  /// 查询所有词库（用于"复制/剪切到..."选择目标）。
  Future<List<Wordbook>> queryOtherBooks(int excludeBookId) async {
    return (await queryWordbooks()).where((b) => b.id != excludeBookId).toList();
  }

  /// 复制词条到目标词库（目标已存在的词静默跳过）。返回成功条数。
  Future<int> copyWords(List<WordbookEntry> entries, int targetBookId) async {
    if (_bookDb == null || entries.isEmpty) return 0;
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final e in entries) {
        final id = await txn.insert(
          'wordbook_words',
          {
            'bookId': targetBookId,
            'word': e.word,
            'translation': e.translation,
            'createdAt': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) n++;
      }
    });
    return n;
  }

  /// 剪切 = 复制成功后删除原词条。返回实际移动条数。
  Future<int> moveWords(List<WordbookEntry> entries, int targetBookId) async {
    if (_bookDb == null || entries.isEmpty) return 0;
    int n = 0;
    await _bookDb!.transaction((txn) async {
      for (final e in entries) {
        final id = await txn.insert(
          'wordbook_words',
          {
            'bookId': targetBookId,
            'word': e.word,
            'translation': e.translation,
            'createdAt': e.createdAt, // 保留原收藏时间
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) {
          await txn
              .delete('wordbook_words', where: 'id = ?', whereArgs: [e.id]);
          n++;
        }
      }
    });
    return n;
  }


  void dispose() {
    _lemmaDb?.close();
    _dictDb?.close();
    _bookDb?.close();
  }
  Future<int> _defaultBookId() async {
    final rows = await _bookDb!.query('wordbooks',
        where: 'name = ?', whereArgs: ['默认词库'], limit: 1);
    return rows.first['id'] as int;
  }
}
