import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join;
import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';

/// 全攻略词典（id=2）：Complete_Guide.db
/// 表 items(id, word, level, type, eng, zh, optional, sort)
/// level: 0=head，1~5 下挂；type: head/phonetic/chunk/example/proverb/
///        form/synonym/nearsyn/antonym/note
/// 本期不做板块细分：一个词条整体输出，按 level 缩进。
/// ^…^ 加粗、*…* 下划线的渲染交给 UI 层（WordContentView 的富文本）。
class CompleteGuideDict extends Dictionary {
  static const int dictId = 2;
  static const String assetPath = 'assets/Complete_Guide.db';

  Database? _db;

  @override
  int get id => dictId;

  @override
  String get name => '全攻略';

  @override
  List<SectionType> getCapabilities() => const [
        SectionType.translation, // 暂时都塞进 translation 一揽子显示
      ];

  @override
  Future<bool> init() async {
    try {
      final dir = (await getApplicationDocumentsDirectory()).path;
      final dbPath = join(dir, 'Complete_Guide.db');
      if (!await File(dbPath).exists()) {
        if (!await _copyFromAssets(assetPath, dbPath)) return false;
      }
      _db = await openDatabase(dbPath, readOnly: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _copyFromAssets(String src, String dst) async {
    try {
      final data = await rootBundle.load(src);
      await File(dst).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把 items 表的行转成 ResultSection 列表
  /// rows: items 表中 headId 匹配的全部行（按 id 排序，第一行是 head）
  List<ResultSection> _buildSections(String word, List<Map<String, Object?>> rows) {
    final sections = <ResultSection>[];

    // ---- head 行 → 释义 ----
    final zhLines = <String>[];
    String? phonetic;
    for (final r in rows) {
      if ((r['level'] as int) != 0) continue;
      final zh = (r['zh'] as String?)?.trim() ?? '';
      if (zh.isNotEmpty) zhLines.add(zh);
    }
    for (final r in rows) {
      if (r['type'] == 'phonetic') {
        phonetic = ((r['zh'] as String?) ?? (r['eng'] as String?) ?? '').trim();
        if (phonetic.isNotEmpty) break;
      }
    }
    if (zhLines.isNotEmpty) {
      final lines = [
          ?phonetic,
          ...zhLines,
        ];
      sections.add(ResultSection(
        type: const SectionType('translation'),
        dictId: dictId,
        data: TranslationData(lines),
        sortHint: 0,
      ));
    }

    // ---- 词块 / 例句 / 谚语 / 词形 / 同反义词 / 注释 → 每行一个 translation 板块 ----
    const labeledTypes = {
      'chunk': '词块', 'example': '例句', 'proverb': '谚语',
      'form': '词形', 'synonym': '同义', 'nearsyn': '近义',
      'antonym': '反义', 'note': '注',
    };
    for (final r in rows) {
      final type = r['type'] as String;
      final label = labeledTypes[type];
      if (label == null) continue; // head/phonetic 已处理
      final level = r['level'] as int;
      final eng = ((r['eng'] as String?) ?? '').trim();
      final zh = ((r['zh'] as String?) ?? '').trim();
      final indent = '  ' * (level - 1).clamp(0, 4); // 二级行缩进归属上一行
      final text = StringBuffer(indent);
      if (eng.isNotEmpty) text.write(eng);
      if (zh.isNotEmpty) text.write(eng.isNotEmpty ? '  $zh' : zh);
      if (text.toString().trim().isEmpty) continue;
      sections.add(ResultSection(
        type: const SectionType('translation'),
        dictId: dictId,
        title: label, // 标题交给 UI 层显示，如「词块」「例句」
        data: TranslationData([text.toString().trim()]),
        sortHint: 10, // 全攻略排在默认词典释义之后
      ));
    }
    return sections;
  }


  @override
  Future<List<ResultSection>> query(String word) async {
    if (_db == null) return const [];
    final head = await _db!.query('words',
        where: 'word = ?', whereArgs: [word], limit: 1);
    if (head.isEmpty) return const [];
    final headId = head.first['id'] as int;
    final rows = await _db!.query('items',
        where: 'headId = ?', whereArgs: [headId], orderBy: 'id');
    return _buildSections(word, rows); // ← 两个参数，word 在前
  }


  /// 批量导入词库用：按字母序取范围内的单词
  @override
  Future<List<String>> queryRange(String from, String to) async {
    if (_db == null) return const [];
    final rows = await _db!.query('words',
        where: 'word >= ? AND word <= ?',
        whereArgs: [from.toLowerCase(), to.toLowerCase()],
        columns: ['word'], orderBy: 'word');
    return rows.map((r) => r['word'] as String).toList();
  }

  @override
  Future<List<ReviewCard>> queryCards(String word) async {
    if (_db == null) return const [];
    final head = await _db!.query('words', where: 'word = ?',
        whereArgs: [word], limit: 1);
    if (head.isEmpty) return const [];
    final headId = head.first['id'] as int;
    final rows = await _db!.query('items',
        where: 'headId = ?', whereArgs: [headId], orderBy: 'id');

    final cards = <ReviewCard>[];
    // 主卡：正面 = 词块less的释义（zh），背面 = 单词
    final meanings = <String>[];
    for (final r in rows) {
      if ((r['level'] as int) != 0) continue;
      final zh = (r['zh'] as String?)?.trim() ?? '';
      if (zh.isNotEmpty) meanings.add(zh);
    }
    if (meanings.isNotEmpty) {
      cards.add(ReviewCard(front: meanings.join('\n'), back: word, isMain: true));
    }
    // 词块卡：有英文有中文的行 → 中→英 与 英→中 两张
    const cardTypes = {'chunk', 'example', 'proverb'};
    for (final r in rows) {
      final t = r['type'] as String;
      if (!cardTypes.contains(t)) continue;
      final eng = ((r['eng'] as String?) ?? '').trim();
      final zh = ((r['zh'] as String?) ?? '').trim();
      if (eng.isEmpty || zh.isEmpty) continue;
      cards.add(ReviewCard(front: zh, back: eng)); // 见中文想英文
      cards.add(ReviewCard(front: eng, back: zh)); // 见英文想中文
    }
    return cards;
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
  }
}
