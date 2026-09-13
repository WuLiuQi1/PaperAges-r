class PdfAnchor {
  const PdfAnchor({
    required this.documentFingerprint,
    required this.pageIndex,
    required this.normalizedViewportX,
    required this.normalizedViewportY,
  }) : assert(pageIndex >= 0),
       assert(normalizedViewportX >= 0 && normalizedViewportX <= 1),
       assert(normalizedViewportY >= 0 && normalizedViewportY <= 1);

  final String documentFingerprint;
  final int pageIndex;
  final double normalizedViewportX;
  final double normalizedViewportY;
}

enum PdfGesturePriority { pageSwipe, panOrZoom }

/// Keeps a zoomed PDF from accidentally changing page while the user pans it.
class PdfInteractionPolicy {
  const PdfInteractionPolicy({this.zoomPanThreshold = 1.01});

  final double zoomPanThreshold;

  PdfGesturePriority priority({
    required double scale,
    required int pointerCount,
  }) => scale > zoomPanThreshold || pointerCount >= 2
      ? PdfGesturePriority.panOrZoom
      : PdfGesturePriority.pageSwipe;
}
