import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../data/network_shelf_repository.dart';

/// Read-only network shelf inventory. Opening still depends on a usable stored
/// source; unavailable sources are shown rather than silently falling back.
class NetworkShelfScreen extends StatelessWidget {
  const NetworkShelfScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('网络书架')),
    body: FutureBuilder<AppDatabase>(
      future: AppDatabase.defaults(),
      builder: (context, ready) {
        if (!ready.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<List<NetworkShelfBook>>(
          stream: NetworkShelfRepository(ready.data!).watchBooks(),
          builder: (context, snapshot) {
            final books = snapshot.data ?? const <NetworkShelfBook>[];
            if (books.isEmpty) {
              return const Center(child: Text('从书源搜索结果加入网络书架'));
            }
            return ListView.separated(
              itemCount: books.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final book = books[index];
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(book.title),
                  subtitle: Text(book.author ?? book.sourceUrl),
                  trailing: const Icon(Icons.cloud_done_outlined),
                );
              },
            );
          },
        );
      },
    ),
  );
}
