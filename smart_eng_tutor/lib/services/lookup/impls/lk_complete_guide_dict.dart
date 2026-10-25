import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join;
import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';

/// 全攻略词典（id=2）：Complete_Guide.db
/// 表 words(id, word) + items(id, headId, level, type, eng, zh, optional, sort)
/// level: 0=head，1~5 下挂；type: head/phonetic/chunk/example/proverb/
///        form/synonym/nearsyn/antonym/note
///
/// 支持三类查询目标：
/// 1. 单词（head）→ head 释义 + 全部下挂词块
/// 2. 词组（head 就是词组，如 "look forward to"）→ 同上
/// 3. 词块英文（items.eng 精确匹配）→ 该词块 + 其下级内容
class CompleteGuideDict extends Dictionary {
  static const int dictId = 2;
  static const String assetPath = 'assets/Complete_Guide.db';

  Database? _db;

  @override
  int get id => dictId;
  @override
  String get name => '全攻略';

  /// 词块级导入：每个含 eng+zh 的词块各作为一条词条
  @override
  DictGranularity get granularity => DictGranularity.chunk;

  @override
  List<SectionType> getCapabilities() => const [
        SectionType.translation,
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

  // ==================== 查询 ====================

  @override
  Future<List<ResultSection>> query(String word) async {
    if (_db == null) return const [];
    final w = word.trim();
    if (w.isEmpty) return const [];
    try {
      // ① head（单词或词组 head）精确匹配
      final head = await _db!.query('words',
          where: 'word = ?', whereArgs: [w], limit: 1);
      if (head.isNotEmpty) {
        final rows = await _db!.query('items',
            where: 'headId = ?', whereArgs: [head.first['id']],
            orderBy: 'id');
        return _buildSections(w, rows);
      }
      // ② 词块英文精确匹配（items.eng）→ 该词块 + 其下级
      final item = await _db!.query('items',
          where: 'eng = ?', whereArgs: [w], limit: 1);
      if (item.isNotEmpty) {
        final rows = await _db!.query('items',
            where: 'headId = ?', whereArgs: [item.first['headId']],
            orderBy: 'id');
        final idx = rows.indexWhere((r) => r['id'] == item.first['id']);
        if (idx >= 0) return _buildChunkSections(w, rows, idx);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// head 词条整体（原逻辑保留：head 释义 + 各类型行）
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
    // ---- 其余类型行 ----
    _appendLabeledRows(sections, rows, fromIdx: 0, baseLevel: 0);
    return sections;
  }

  /// 词块词条：词块自身 + 其下级（level 更大的连续区段）
  List<ResultSection> _buildChunkSections(
      String word, List<Map<String, Object?>> rows, int idx) {
    final sections = <ResultSection>[];
    final target = rows[idx];
    final lv = target['level'] as int;
    // 词块自身
    _appendOne(sections, target, 0);
    // 下级：idx 之后 level > lv 的连续行
    final sub = <Map<String, Object?>>[];
    for (var i = idx + 1; i < rows.length; i++) {
      if ((rows[i]['level'] as int) <= lv) break;
      sub.add(rows[i]);
    }
    _appendLabeledRows(sections, sub, fromIdx: 0, baseLevel: lv);
    return sections;
  }

  void _appendLabeledRows(List<ResultSection> sections,
      List<Map<String, Object?>> rows,
      {required int fromIdx, required int baseLevel}) {
    for (var i = fromIdx; i < rows.length; i++) {
      _appendOne(sections, rows[i], (rows[i]['level'] as int) - baseLevel);
    }
  }

  void _appendOne(List<ResultSection> sections, Map<String, Object?> r,
      int depthBelowBase) {
    const labeledTypes = {
      'chunk': '词块',
      'example': '例句',
      'proverb': '谚语',
      'form': '词形',
      'synonym': '同义',
      'nearsyn': '近义',
      'antonym': '反义',
      'note': '注',
    };
    final type = r['type'] as String;
    final label = labeledTypes[type];
    if (label == null) return; // head/phonetic 已由上层处理
    final eng = ((r['eng'] as String?) ?? '').trim();
    final zh = ((r['zh'] as String?) ?? '').trim();
    if (eng.isEmpty && zh.isEmpty) return;
    final indent = ' ' * max(0, depthBelowBase - 1).clamp(0, 4);
    final text = StringBuffer(indent);
    if (eng.isNotEmpty) text.write(eng);
    if (zh.isNotEmpty) text.write(eng.isNotEmpty ? ' $zh' : zh);
    sections.add(ResultSection(
      type: const SectionType('translation'),
      dictId: dictId,
      title: label,
      data: TranslationData([text.toString().trim()]),
      sortHint: 10,
    ));
  }

  // ==================== 导入 ====================

  /// word 粒度（本词典不用，但保留能力）
  @override
  Future<List<String>> queryRange(String from, String to) async {
    if (_db == null) return const [];
    final rows = await _db!.query('words',
        where: 'word >= ? AND word <= ?',
        whereArgs: [from.toLowerCase(), to.toLowerCase()],
        columns: ['word'], orderBy: 'word');
    return rows.map((r) => r['word'] as String).toList();
  }

  /// chunk 粒度：headword 范围内所有含 eng+zh 的词块
  @override
  Future<List<DictChunk>> queryChunkRange(String from, String to) async {
    if (_db == null) return const [];
    final rows = await _db!.rawQuery('''
      SELECT w.word AS head, i.eng, i.zh, i.type
      FROM items i JOIN words w ON w.id = i.headId
      WHERE i.eng != '' AND i.zh != ''
        AND lower(w.word) >= ? AND lower(w.word) <= ?
      ORDER BY w.word, i.id
    ''', [from.toLowerCase(), to.toLowerCase()]);
    final seen = <String>{};
    final out = <DictChunk>[];
    for (final r in rows) {
      final eng = (r['eng'] as String).trim();
      if (eng.isEmpty || !seen.add(eng)) continue; // 去重（词块英文唯一）
      out.add(DictChunk(
        headWord: r['head'] as String,
        eng: eng,
        zh: (r['zh'] as String).trim(),
        type: r['type'] as String,
      ));
    }
    return out;
  }

  // ==================== 复习卡片 ====================

  // ==================== 复习卡片 ====================

  /// 重要度（impl 内声明，复习程序按此排序/取舍）：
  /// 5 = head 主体释义；3 = 词块；2 = 例句；1 = 谚语
  static const _impHead = 5;
  static const _impChunk = 3;
  static const _impExample = 2;
  static const _impProverb = 1;

  @override
  Future<List<ReviewCard>> queryCards(String word) async {
    if (_db == null) return const [];
    final w = word.trim();
    final cards = <ReviewCard>[];
    try {
      // ① head 匹配（单词或词组 head）
      final head = await _db!.query('words',
          where: 'word = ?', whereArgs: [w], limit: 1);
      List<Map<String, Object?>> rows = const [];
      if (head.isNotEmpty) {
        rows = await _db!.query('items',
            where: 'headId = ?', whereArgs: [head.first['id']],
            orderBy: 'id');
      } else {
        // ② 词块匹配
        final item = await _db!.query('items',
            where: 'eng = ?', whereArgs: [w], limit: 1);
        if (item.isEmpty) return const [];
        rows = await _db!.query('items',
            where: 'headId = ?', whereArgs: [item.first['headId']],
            orderBy: 'id');
        final idx = rows.indexWhere((r) => r['id'] == item.first['id']);
        final it = rows[idx];
        final eng = ((it['eng'] as String?) ?? '').trim();
        final zh = ((it['zh'] as String?) ?? '').trim();
        if (eng.isEmpty || zh.isEmpty) return const [];
        cards.add(ReviewCard(eng: eng, zh: zh, importance: _impChunk));
        // 词块的下级内容也做卡
        final lv = it['level'] as int;
        final sub = <Map<String, Object?>>[];
        for (var i = idx + 1; i < rows.length; i++) {
          if ((rows[i]['level'] as int) <= lv) break;
          sub.add(rows[i]);
        }
        _cardsFromRows(cards, sub);
        return cards;
      }
      // head 路径
      final meanings = <String>[];
      for (final r in rows) {
        if ((r['level'] as int) != 0) continue;
        final zh = (r['zh'] as String?)?.trim() ?? '';
        if (zh.isNotEmpty) meanings.add(zh);
      }
      if (meanings.isNotEmpty) {
        cards.add(ReviewCard(
            eng: w, zh: meanings.join('\n'), importance: _impHead));
      }
      _cardsFromRows(cards, rows);
    } catch (_) {}
    return cards;
  }

  void _cardsFromRows(List<ReviewCard> cards, List<Map<String, Object?>> rows) {
    const cardTypes = {
      'chunk': _impChunk,
      'example': _impExample,
      'proverb': _impProverb,
    };
    for (final r in rows) {
      final imp = cardTypes[r['type'] as String];
      if (imp == null) continue;
      final eng = ((r['eng'] as String?) ?? '').trim();
      final zh = ((r['zh'] as String?) ?? '').trim();
      if (eng.isEmpty || zh.isEmpty) continue;
      cards.add(ReviewCard(eng: eng, zh: zh, importance: imp));
    }
  }

  @override
  Future<List<String>> relatedHeads(String word) async {
    if (_db == null) return const [];
    final w = word.trim();
    try {
      // ① 找到该词对应的 headId（可能是 head 本身，也可能是词块）
      Map<String, Object?>? item;
      final byEng = await _db!.query('items',
          columns: ['headId'], where: 'eng = ?', whereArgs: [w], limit: 1);
      if (byEng.isNotEmpty) {
        item = byEng.first;
      } else {
        final head = await _db!.query('words',
            columns: ['id'], where: 'word = ?', whereArgs: [w], limit: 1);
        if (head.isEmpty) return const [];
        item = {'headId': head.first['id']};
      }
      final headId = item['headId'] as int;

      // ② 同 head 下所有词块 + head 本身
      final rows = await _db!.rawQuery('''
        SELECT DISTINCT i.eng AS eng
        FROM items i
        WHERE i.headId = ? AND i.eng != ? AND TRIM(i.eng) != ''
        UNION
        SELECT hd.word AS eng FROM words hd WHERE hd.id = ? AND hd.word != ?
      ''', [headId, w, headId, w]);
      return [for (final r in rows) (r['eng'] as String).trim()]
        ..removeWhere((e) => e.isEmpty);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
  }
}
