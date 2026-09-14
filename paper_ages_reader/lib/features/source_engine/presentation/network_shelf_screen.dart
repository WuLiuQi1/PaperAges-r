import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../data/local_source_repository.dart';
import '../data/network_shelf_repository.dart';
import '../data/persistent_source_binding_store.dart';
import '../domain/source_engine.dart';
import 'source_search_screen.dart';
import 'source_switch_screen.dart';

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
                final bookId = NetworkShelfRepository.bookIdFor(
                  sourceUrl: book.sourceUrl,
                  locator: book.locator,
                );
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(book.title),
                  subtitle: Text(book.author ?? book.sourceUrl),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '换源',
                        icon: const Icon(Icons.swap_horiz_outlined),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SourceSwitchScreen(bookId: bookId),
                          ),
                        ),
                      ),
                      const Icon(Icons.cloud_done_outlined),
                    ],
                  ),
                  onTap: () async {
                    final sources = LocalSourceRepository(ready.data!);
                    final binding = PersistentSourceBindingStore(ready.data!)
                        .bindingFor(bookId);
                    final source = await sources.findByUrl(
                      binding?.sourceUrl ?? book.sourceUrl,
                    );
                    if (!context.mounted) return;
                    if (source == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('此书源未配置，无法打开网络书籍。')),
                      );
                      return;
                    }
                    if (binding != null) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NetworkChapterScreen(
                            source: source,
                            chapter: SourceChapter(
                              key: binding.chapterKey,
                              title: book.title,
                              locator: binding.locator,
                              ordinal: 0,
                              bookLocator: book.locator,
                            ),
                          ),
                        ),
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NetworkBookScreen(
                            source: source,
                            book: NetworkBook(
                              sourceUrl: book.sourceUrl,
                              title: book.title,
                              author: book.author,
                              locator: book.locator,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    ),
  );
}
