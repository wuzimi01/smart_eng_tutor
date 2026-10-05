import 'package:flutter/material.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;
import 'pages/home_page.dart';
import 'dictionary/registry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();   // async 里用插件前必须初始化绑定

  // 桌面端：sqflite 需要 FFI 实现（Windows / Linux / macOS）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 词典只在这里 init 一次（拷贝/打开 stardict.db、lemma.en.db）
  await DictionaryRegistry.shared.initAll();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}
