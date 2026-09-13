import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_document/domain/pdf_interaction_policy.dart';

void main() {
  const policy = PdfInteractionPolicy();

  test(
    'uses zero-based pages and normalized in-page position for restoration',
    () {
      const anchor = PdfAnchor(
        documentFingerprint: 'sha256:fixture',
        pageIndex: 0,
        normalizedViewportX: .4,
        normalizedViewportY: .7,
      );

      expect(anchor.pageIndex, 0);
      expect(anchor.normalizedViewportY, .7);
    },
  );

  test('gives pan or zoom priority to a zoomed or two-finger PDF gesture', () {
    expect(
      policy.priority(scale: 1, pointerCount: 1),
      PdfGesturePriority.pageSwipe,
    );
    expect(
      policy.priority(scale: 1.1, pointerCount: 1),
      PdfGesturePriority.panOrZoom,
    );
    expect(
      policy.priority(scale: 1, pointerCount: 2),
      PdfGesturePriority.panOrZoom,
    );
  });
}
