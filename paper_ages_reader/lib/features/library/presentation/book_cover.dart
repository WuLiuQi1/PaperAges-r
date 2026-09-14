import 'package:flutter/material.dart';

import '../domain/library_book.dart';

/// Local TXT has no embedded artwork: use a stable book-shaped title cover,
/// never unrelated sample artwork or an invented author.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});
  final LibraryBook book;

  @override
  Widget build(BuildContext context) => ShelfBookCover(
    title: book.title,
    identity: book.fingerprint,
    badge: book.kind == LibraryBookKind.pdf ? 'PDF' : 'TXT',
  );
}

class ShelfBookCover extends StatelessWidget {
  const ShelfBookCover({
    super.key,
    required this.title,
    required this.identity,
    required this.badge,
  });

  final String title;
  final String identity;
  final String badge;

  Color get color {
    const palette = [
      Color(0xFF254D5D),
      Color(0xFF795543),
      Color(0xFF596547),
      Color(0xFF484B69),
    ];
    return palette[identity.codeUnits.fold<int>(0, (a, b) => a + b) %
        palette.length];
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: .70,
    child: Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 12,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 3,
            top: 0,
            bottom: 0,
            width: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: .25),
                    Colors.black.withValues(alpha: .18),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 14, 16),
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFFFF8E7),
                          fontSize: (constraints.maxWidth * .17).clamp(10, 25),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (constraints.maxHeight > 90)
                      Text(
                        badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          letterSpacing: .3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showBookActions(
  BuildContext context,
  LibraryBook book,
  VoidCallback onRead, [
  Future<void> Function()? onDelete,
]) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: false,
  useSafeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (sheetContext) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            tileColor: Theme.of(context).colorScheme.surface,
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('继续阅读'),
            onTap: () {
              Navigator.pop(sheetContext);
              onRead();
            },
          ),
          if (onDelete != null) ...[
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              tileColor: Theme.of(context).colorScheme.surface,
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除此书',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await onDelete();
              },
            ),
          ],
          const SizedBox(height: 12),
          Text(
            book.kind == LibraryBookKind.pdf ? 'PDF · 本地导入' : 'TXT · 本地导入',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  ),
);
