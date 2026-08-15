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
    return const MaterialApp(
      home: HomePage(),
    );
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
  Database? _database;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    try {
      // 🔥 修复点 1：在桌面端不再使用 getDatabasesPath()，改用应用文档目录
      final appDocDir = await getApplicationDocumentsDirectory();
      // 路径例如：C:\Users\你的用户名\AppData\Roaming\com.example.你的项目名\lemma.en.db
      final dbPath = join(appDocDir.path, 'lemma.en.db');
      
      debugPrint('📁 数据库实际存储路径: $dbPath');

      // 检查文件是否已存在
      if (!await File(dbPath).exists()) {
        debugPrint('📦 首次启动，从 assets 复制数据库...');
        
        // 🔥 修复点 2：先确保存放数据库的文件夹存在！
        final dbDir = Directory(dirname(dbPath));
        if (!await dbDir.exists()) {
          await dbDir.create(recursive: true); // 递归创建父目录
        }

        try {
          // 从 assets 加载并写入
          final data = await rootBundle.load('assets/lemma.en.db');
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await File(dbPath).writeAsBytes(bytes);
          debugPrint('✅ 数据库写入成功');
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/lemma.en.db，请在 pubspec.yaml 中声明';
            _isLoading = false;
          });
          return;
        }
      }

      // 打开数据库
      try {
        _database = await openDatabase(dbPath);
        debugPrint('✅ 数据库连接成功');
      } catch (e) {
        setState(() {
          _displayText = '❌ 数据库打开失败: $e';
          _isLoading = false;
        });
        return;
      }

      // 加载完成
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _displayText = '❌ 初始化异常: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _searchStem(String word) async {
    if (_database == null) {
      setState(() => _displayText = '数据库未就绪...');
      return;
    }
    if (word.isEmpty) {
      setState(() => _displayText = '请输入内容...');
      return;
    }

    try {
      final results = await _database!.query(
        'word_stem',
        columns: ['stem'],
        where: 'word = ?',
        whereArgs: [word],
        orderBy: 'weight DESC',
      );

      if (results.isEmpty) {
        setState(() => _displayText = '未找到原型');
      } else {
        final stems = results.map((row) => row['stem'] as String).toList();
        setState(() => _displayText = stems.join('\n'));
      }
    } catch (e) {
      setState(() => _displayText = '查询出错: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _database?.close();
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
                onChanged: (value) => _searchStem(value.trim()),
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
                          color: _displayText == '请输入内容...' ? Colors.grey : Colors.black87,
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