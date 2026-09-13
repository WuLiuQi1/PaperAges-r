enum LibraryBookKind { text, pdf }

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.kind,
    required this.title,
    required this.filePath,
    required this.fingerprint,
    required this.createdAt,
    this.encoding,
  });

  final String id;
  final LibraryBookKind kind;
  final String title;
  final String filePath;
  final String fingerprint;
  final DateTime createdAt;
  final String? encoding;
}
