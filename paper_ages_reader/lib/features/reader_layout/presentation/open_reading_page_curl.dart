import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../domain/reader_page_turn_geometry.dart';
import 'reader_transition_work_scope.dart';

part 'src/page_curl/reader_page_curl_api.dart';
part 'src/page_curl/reader_page_curl_internal_types.dart';
part 'src/page_curl/reader_page_curl_painters.dart';
part 'src/page_curl/reader_page_curl_settle.dart';
part 'src/page_curl/reader_page_curl_snapshot_cache.dart';
part 'src/page_curl/reader_page_curl_state.dart';

/// Stable identity for the rendered text leaf captured by the page-turn
/// snapshot cache. Layout and theme changes intentionally invalidate it.
@immutable
class ReaderPageSnapshotKey {
  const ReaderPageSnapshotKey({
    required this.pageIdentity,
    required this.layoutFingerprint,
    required this.themeId,
  });

  final String pageIdentity;
  final String layoutFingerprint;
  final String themeId;

  @override
  bool operator ==(Object other) =>
      other is ReaderPageSnapshotKey &&
      other.pageIdentity == pageIdentity &&
      other.layoutFingerprint == layoutFingerprint &&
      other.themeId == themeId;

  @override
  int get hashCode => Object.hash(pageIdentity, layoutFingerprint, themeId);
}
