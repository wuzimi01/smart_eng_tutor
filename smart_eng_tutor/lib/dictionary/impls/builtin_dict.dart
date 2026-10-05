import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import '../dictionary.dart';
import '../section.dart';

/// 本词典（id=1）：stardict.db（释义+tag）+ lemma.en.db（词根）
class BuiltinDict extends Dictionary {
  static const int dictId = 1;

  Database? _dictDb;
  Database? _lemmaDb;

  @override
  int get id => dictId;
  @override
  String get name => '内置词典';

  @override
  List<SectionType> getCapabilities() => const [
        SectionType.translation,
        SectionType.tag,
      ];

  @override
  Future<bool> init() async {
    try {
      final dir = (await getApplicationDocumentsDirectory()).path;
      final dictPath = join(dir, 'stardict.db');
      final lemmaPath = join(dir, 'lemma.en.db');

      if (!await File(dictPath).exists()) {
        if (!await _copyFromAssets('assets/stardict.db', dictPath)) return false;
      }
      if (!await File(lemmaPath).exists()) {
        if (!await _copyFromAssets('assets/lemma.en.db', lemmaPath)) return false;
      }
      _dictDb = await openDatabase(dictPath, readOnly: true);
      _lemmaDb = await openDatabase(lemmaPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _copyFromAssets(String assetPath, String dbPath) async {
    try {
      final d = Directory(dirname(dbPath));
      if (!await d.exists()) await d.create(recursive: true);
      final data = await rootBundle.load(assetPath);
      await File(dbPath).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<ResultSection>> query(String word) async {
    final sections = <ResultSection>[];
    try {
      // 考纲标签
      final tagRows = await _dictDb?.query('stardict',
          columns: ['tag'], where: 'word = ?', whereArgs: [word], limit: 1);
      final tag = tagRows?.firstOrNull?['tag'] as String? ?? '';
      final codes =
          tag.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (codes.isNotEmpty) {
        sections.add(ResultSection(
          type: SectionType.tag,
          dictId: dictId,
          data: TagData(codes),
          sortHint: -10, // 徽章希望靠前
        ));
      }
      // 释义
      final rows = await _dictDb?.query('stardict',
          columns: ['translation'],
          where: 'word = ?',
          whereArgs: [word]);
      final lines = <String>[];
      for (final r in rows ?? const []) {
        final t = r['translation'] as String? ?? '';
        if (t.trim().isNotEmpty) lines.addAll(t.split('\n'));
      }
      if (lines.isNotEmpty) {
        sections.add(ResultSection(
          type: SectionType.translation,
          dictId: dictId,
          data: TranslationData(lines),
          sortHint: 0,
        ));
      }
    } catch (e) {
      // 内部兜底，返回已有部分
    }
    return sections;
  }

  @override
  Future<List<String>> queryStems(String word) async {
    try {
      final rows = await _lemmaDb?.query('word_stem',
          columns: ['stem'],
          where: 'word = ?',
          whereArgs: [word],
          orderBy: 'weight DESC');
      return rows?.map((r) => r['stem'] as String).toList() ?? [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    await _dictDb?.close();
    await _lemmaDb?.close();
  }
}
