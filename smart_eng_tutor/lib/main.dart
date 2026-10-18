import 'package:flutter/material.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;
import 'package:smart_eng_tutor/pages/home_page.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_display_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await DisplaySettings.shared.init();      // ← 新增
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
