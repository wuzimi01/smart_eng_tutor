import 'package:flutter/material.dart';

import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_display_settings.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';   // SectionType



class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = DisplaySettings.shared;

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('词典内容显示',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final dict in DictionaryRegistry.shared.all)
              for (final type in dict.getCapabilities())
                SwitchListTile(
                  title: Text(_label(type)),
                  subtitle: Text(dict.name),
                  value: settings.isVisible(dict.id, type),
                  onChanged: (v) => settings.setVisible(dict.id, type, v),
                ),
          ],
        ),
      ),
    );
  }

  String _label(SectionType t) => switch (t.name) {
        'translation' => '释义',
        'tag' => '徽章（词性/考纲标签）',
        _ => t.name,
      };
}
