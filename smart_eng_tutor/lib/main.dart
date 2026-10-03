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
  Database? _lemmaDb;      // 词根库
  Database? _dictDb;       // 释义库 stardict.db
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDatabases();
  }

  /// 从 assets 拷贝数据库文件到文档目录（若不存在）
  Future<void> _copyFromAssets(String assetPath, String dbPath) async {
    final dbDir = Directory(dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(dbPath).writeAsBytes(bytes);
  }

  Future<void> _initDatabases() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();

      // ---- 词根库 lemma.en.db ----
      final lemmaPath = join(appDocDir.path, 'lemma.en.db');
      debugPrint('📁 词根库路径: $lemmaPath');
      if (!await File(lemmaPath).exists()) {
        try {
          await _copyFromAssets('assets/lemma.en.db', lemmaPath);
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/lemma.en.db，请在 pubspec.yaml 中声明';
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

      // ---- 释义库 stardict.db（同目录）----
      final dictPath = join(appDocDir.path, 'stardict.db');
      debugPrint('📁 释义库路径: $dictPath');
      if (!await File(dictPath).exists()) {
        try {
          await _copyFromAssets('assets/stardict.db', dictPath);
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/stardict.db，请在 pubspec.yaml 中声明';
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

  /// 在释义库中查询单词释义；查到返回记录列表，查不到返回 null
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
      setState(() => _displayText = '请输入内容...');
      return;
    }

    try {
      final buffer = StringBuffer();

      // ① 先直接查原词的释义
      final direct = await _queryTranslation(word);
      if (direct != null) {
        for (final row in direct) {
          buffer.writeln(row['word']); // 词在上
          buffer.writeln(row['translation']); // 释义在下
        }
        setState(() => _displayText = buffer.toString().trim());
        return;
      }

      // ② 原词无释义 → 查所有原型（weight 降序）
      final stemRows = await _lemmaDb!.query(
        'word_stem',
        columns: ['stem'],
        where: 'word = ?',
        whereArgs: [word],
        orderBy: 'weight DESC',
      );

      if (stemRows.isEmpty) {
        setState(() => _displayText = '未找到释义或原型');
        return;
      }

      final stems = stemRows.map((row) => row['stem'] as String).toList();

      // ③ 依次用原型查释义，查到即输出（原型在上，释义在下）
      bool found = false;
      for (final stem in stems) {
        final trans = await _queryTranslation(stem);
        if (trans != null) {
          for (final row in trans) {
            buffer.writeln(row['word']); // 释义对应的单词（这里是原型）
            buffer.writeln(row['translation']);
          }
          found = true;
        }
      }

      setState(() {
        _displayText = found ? buffer.toString().trim() : '未找到原型对应的释义';
      });
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
            Padding(
              padding: const EdgeInsets.all(16),
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
            Expanded(
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(
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
          ],
        ),
      ),
    );
  }
}
