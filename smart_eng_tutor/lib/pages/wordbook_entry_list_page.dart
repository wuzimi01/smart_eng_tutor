import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/models.dart';
import 'wordbook_entry_detail_page.dart';

/// 词条列表页（点击词条 → 释义详情）
class WordbookEntryListPage extends StatelessWidget {
  final DatabaseHelper dbHelper;
  final int bookId;
  final String bookName;
  const WordbookEntryListPage({
    super.key,
    required this.dbHelper,
    required this.bookId,
    required this.bookName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(bookName)),
      body: FutureBuilder<List<WordbookEntry>>(
        future: dbHelper.queryEntries(bookId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data ?? [];
          if (entries.isEmpty) {
            return const Center(child: Text('词库为空，去主页收藏单词吧'));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              return ListTile(
                leading: const Icon(Icons.star_outline),
                title: Text(e.word, style: const TextStyle(fontSize: 18)),
                subtitle: e.translation == null
                    ? null
                    : Text(
                        e.translation!.replaceAll('\n', ' ').trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WordbookEntryDetailPage(
                      dbHelper: dbHelper,
                      word: e.word,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
