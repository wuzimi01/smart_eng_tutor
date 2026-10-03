import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';

void main() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  String _displayText = '请输入内容...';
  Database? _lemmaDb;
  Database? _dictDb;
  bool _isLoading = true;

  // 🔥 新增：候选词列表 & 当前选中词
  List<String> _chips = [];
  String? _selectedWord;

  @override
  void initState() {
    super.initState();
    _initDatabases();
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

  Future<void> _initDatabases() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();

      // ---- 词根库 ----
      final lemmaPath = join(appDocDir.path, 'lemma.en.db');
      if (!await File(lemmaPath).exists()) {
        try {
          await _copyFromAssets('assets/lemma.en.db', lemmaPath);
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/lemma.en.db';
            _isLoading = false;
          });
          return;
        }
      }
      try {
        _lemmaDb = await openDatabase(lemmaPath);
      } catch (e) {
        setState(() {
          _displayText = '❌ 词根库打开失败: $e';
          _isLoading = false;
        });
        return;
      }

      // ---- 释义库 ----
      final dictPath = join(appDocDir.path, 'stardict.db');
      if (!await File(dictPath).exists()) {
        try {
          await _copyFromAssets('assets/stardict.db', dictPath);
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/stardict.db';
            _isLoading = false;
          });
          return;
        }
      }
      try {
        _dictDb = await openDatabase(dictPath, readOnly: true);
      } catch (e) {
        setState(() {
          _displayText = '❌ 释义库打开失败: $e';
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _displayText = '❌ 初始化异常: $e';
        _isLoading = false;
      });
    }
  }

  /// 查某词的释义；查不到返回 null
  Future<List<Map<String, Object?>>?> _queryTranslation(String word) async {
    if (_dictDb == null) return null;
    final results = await _dictDb!.query(
      'stardict',
      columns: ['word', 'translation'],
      where: 'word = ?',
      whereArgs: [word],
    );
    return results.isEmpty ? null : results;
  }

  Future<void> _search(String word) async {
    if (_lemmaDb == null || _dictDb == null) {
      setState(() => _displayText = '数据库未就绪...');
      return;
    }
    if (word.isEmpty) {
      setState(() {
        _displayText = '请输入内容...';
        _chips = [];
        _selectedWord = null;
      });
      return;
    }

    try {
      // ① 取所有原型（weight 降序）
      final stemRows = await _lemmaDb!.query(
        'word_stem',
        columns: ['stem'],
        where: 'word = ?',
        whereArgs: [word],
        orderBy: 'weight DESC',
      );
      final stems = stemRows.map((row) => row['stem'] as String).toList();

      // ② 候选 = 原词 + 所有原型（去重）
      final candidates = <String>[word, ...stems];
      final unique = <String>[];
      for (final c in candidates) {
        if (!unique.contains(c)) unique.add(c);
      }

      setState(() {
        _chips = unique;
        _selectedWord = null;
      });

      // ③ 默认选中第一个【有释义】的候选（优先原词）
      for (final c in unique) {
        final trans = await _queryTranslation(c);
        if (trans != null) {
          await _selectChip(c);
          return;
        }
      }

      // 全部都没有释义
      setState(() {
        _selectedWord = null;
        _displayText = '未找到释义';
      });
    } catch (e) {
      setState(() => _displayText = '查询出错: $e');
    }
  }

  /// 🔥 选中某个候选词，显示它的释义
  Future<void> _selectChip(String word) async {
    setState(() => _selectedWord = word);
    try {
      final trans = await _queryTranslation(word);
      if (trans == null) {
        setState(() => _displayText = '「$word」没有释义');
        return;
      }
      final buffer = StringBuffer();
      for (final row in trans) {
        buffer.writeln(row['word']); // 词在上
        buffer.writeln(row['translation']); // 释义在下
      }
      setState(() => _displayText = buffer.toString().trim());
    } catch (e) {
      setState(() => _displayText = '查询出错: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _lemmaDb?.close();
    _dictDb?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ---- 搜索框 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _controller,
                onChanged: (value) => _search(value.trim()),
                decoration: InputDecoration(
                  hintText: '输入你想搜索的内容…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),

            // ---- 🔥 新增：候选词圆角矩形横排 ----
            if (_chips.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _chips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final word = _chips[index];
                    final selected = word == _selectedWord;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _selectChip(word),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.blue
                              : Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          word,
                          style: TextStyle(
                            fontSize: 16,
                            color: selected ? Colors.white : Colors.blue,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ---- 释义显示区（可滚动）----
            Expanded(
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _displayText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            color: _displayText == '请输入内容...'
                                ? Colors.grey
                                : Colors.black87,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
