# Delivery status

Last updated: 2026-09-13

| Stage | Status | Evidence / limitation |
| --- | --- | --- |
| G0 engineering audit | Complete | New Flutter Android/iOS project; lockfile, `dart analyze` and one G0 test pass. Android build is externally blocked; iOS requires macOS. |
| G1 risk spikes | In progress | Text page-turn and source-script preflight have automated evidence; device/page-curl/PDF/source parsing/audio/WebDAV work remains. |
| G2-G6 | Not started | No production feature, device validation or distribution artifact. |

## G0 evidence

- Flutter 3.47.4 / Dart 3.13.3; Android SDK 36.0.0 and JDK 21.0.12 detected.
- `flutter test --reporter expanded`: passed (one test).
- `dart analyze`: passed with no diagnostics. `flutter analyze` separately
  exposed an analysis-server LSP JSON parse failure in this non-ASCII path.
- `flutter build apk --debug`: attempted, but the Gradle wrapper timed out
  downloading its distribution. No APK was generated; this is not a build pass.
- iOS build/device work is blocked on Windows: no macOS/Xcode or Apple device.
- The supplied reference frames/index were inspected. Full MP4 playback was
  blocked by local-browser policy and no controllable media surface; this is not
  a substitute for full recording inspection.

## Acceptance tracking

The full supplied scenario inventory is at
`F:\Project\PaperAges\Reader-Codex-开发文档包\Reader-Codex-DevKit\quality\acceptance-matrix.csv`.
No scenario is Passed. T001 is In progress; T002-T064 are Not run.

## G1 evidence

- `PageTurnPolicy` has a single completion decision path: a short slow drag
  stays put, threshold drag and fling commit direction once, and unavailable
  geometry never commits. Six focused unit/widget tests pass.
- The harness provides slide, fade and continuous-scroll branches over two
  fixed pages. It is not production pagination and does not persist a position.
- T019 is **Implemented**, not Verified: widget tests cover the cancel/commit
  logic, but no Android/iOS device gesture test exists. T020 remains Not run;
  the current slide transition is explicitly not presented as a page curl.
- First test run found two test-harness defects (missing `Key` import and a
  missing MaterialApp/Directionality ancestor). Both were fixed, then all tests
  were rerun successfully.

- `RuleSafetyPolicy` rejects configuration-level JavaScript directives, script
  markup, expression URLs/eval, dynamic libraries and execution bridges before
  any source parser/network layer exists. Four focused tests pass. This is
  partial H01 evidence only: import wiring and HTML-as-data integration are
  still Not run.
- Android testing is planned for a user-connected device in VS Code. A future
  GitHub macOS workflow can verify an unsigned iOS build, but cannot produce an
  IPA installable on a physical device without valid signing/provisioning.
