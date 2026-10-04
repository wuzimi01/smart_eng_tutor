import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;

class DatabaseHelper {
  Database? _lemmaDb;
  Database? _dictDb;

  Database? get lemmaDb => _lemmaDb;
  Database? get dictDb => _dictDb;

  /// 初始化两个数据库，成功返回 true
  Future<bool> init() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();

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

  void dispose() {
    _lemmaDb?.close();
    _dictDb?.close();
  }
}
