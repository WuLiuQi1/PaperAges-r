enum PageTurnOutcome { previous, stay, next }

/// Decides one page transition from the completed drag, never from animation
/// frames. The caller persists a reading anchor only for [previous] or [next].
class PageTurnPolicy {
  const PageTurnPolicy({
    this.distanceThreshold = 0.22,
    this.velocityThreshold = 700,
  }) : assert(distanceThreshold > 0 && distanceThreshold < 1),
       assert(velocityThreshold > 0);

  final double distanceThreshold;
  final double velocityThreshold;

  PageTurnOutcome resolve({
    required double dragDistance,
    required double horizontalVelocity,
    required double viewportWidth,
  }) {
    if (viewportWidth <= 0) {
      return PageTurnOutcome.stay;
    }

    final normalizedDistance = dragDistance / viewportWidth;
    final hasDistanceCommit = normalizedDistance.abs() >= distanceThreshold;
    final hasVelocityCommit = horizontalVelocity.abs() >= velocityThreshold;

    if (!hasDistanceCommit && !hasVelocityCommit) {
      return PageTurnOutcome.stay;
    }

    // A leftward drag advances in left-to-right app chrome. Content direction
    // will become a reading-direction setting rather than being duplicated in
    // each page-mode widget.
    final direction = hasDistanceCommit
        ? normalizedDistance
        : horizontalVelocity;
    return direction < 0 ? PageTurnOutcome.next : PageTurnOutcome.previous;
  }
}
