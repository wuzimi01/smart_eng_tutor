import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import 'models.dart';

class DatabaseHelper {
  /// 本词典在多词典体系中的 ID（多词典功能预留）
  /// 与 assets 词典、生成考纲词库.py 中 DICT_ID 保持一致
  static const int dictId = 1;
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
  
  /// 查某词的考纲标签（tag 列，空格分隔的代码），如 ['cet4', 'gk']
  Future<List<String>> queryTags(String word) async {
    if (_dictDb == null) return [];
    final rows = await _dictDb!.query(
      'stardict',
      columns: ['tag'],
      where: 'word = ?',
      whereArgs: [word],
      limit: 1,
    );
    final tag = rows.firstOrNull?['tag'] as String? ?? '';
    return tag.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  }

    // ==================== 词库（单词本） ====================

    /// 打开/创建词库库。
    /// 首次运行时从 assets/wordbook.db 拷贝（含预导入的考纲词库），
    /// 之后 app 端不再覆盖 —— 保证用户的收藏数据不被重置。
    Future<bool> _initBookDb() async {
      try {
        final bookPath = join(_docPath, 'wordbook.db');

        // 首次运行：从 assets 拷贝初始词库（8 个考纲词库 + 默认词库）
        if (!await File(bookPath).exists()) {
          try {
            await _copyFromAssets('assets/wordbook.db', bookPath);
          } catch (e) {
            return false; // assets 里没有或读取失败
          }
        }

        _bookDb = await openDatabase(bookPath, version: 1);
        // 幂等兜底：assets 的 db 可能没有默认词库（如纯脚本导出的）
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
  Future<String> addWord(String word, {int? bookId, int? dictId}) async {
    if (_bookDb == null) return 'error';
    try {
      final bid = bookId ?? await _defaultBookId();
      final id = await _bookDb!.insert(
        'wordbook_words',
        {
          'bookId': bid,
          'dictId': dictId ?? dictId, // ← 未显式指定时写本词典 ID（1）
          'word': word,
        },
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
      orderBy: 'id DESC', // 插入顺序倒序（createdAt 已移除）
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
