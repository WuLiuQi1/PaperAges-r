# Delivery status

Last updated: 2026-09-13

| Stage | Status | Evidence / limitation |
| --- | --- | --- |
| G0 engineering audit | Complete | New Flutter Android/iOS project; lockfile, analysis, tests and a structurally validated Android Debug APK. iOS requires macOS. |
| G1 risk spikes | Complete with blocked platform gates | Text, page-curl/menu, source preflight, sync merge/whitelist, audio and PDF contracts have automated evidence. Native rendering, media, WebDAV transport and device validation remain explicitly blocked. |
| G2 reading and state | In progress | TXT normalization, grapheme-safe chunking and text-anchor contracts are implemented and tested; import storage, real layout, theme/font, progress and PDF renderer remain. |
| G3-G6 | Not started | No production online/offline feature, device validation or distribution artifact. |

## G0 evidence

- Flutter 3.47.4 / Dart 3.13.3; Android SDK 36.0.0 and JDK 21.0.12 detected.
- `flutter test --reporter expanded`: passed (one test).
- `dart analyze`: passed with no diagnostics. `flutter analyze` separately
  exposed an analysis-server LSP JSON parse failure in this non-ASCII path.
- Gradle 9.3.1 was downloaded and SHA-256 verified. A cross-volume Kotlin
  incremental-cache failure was fixed by disabling only incremental caching.
  `:app:assembleDebug --no-daemon` produced `build/app/outputs/flutter-apk/app-debug.apk`;
  its ZIP/APK contents were inspected. No physical-device install was run.
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

- `SyncWhitelistPolicy` allows only explicit event metadata, shelf fields,
  safe source locators and anchors into a future upload outbox. It rejects
  local files, bodies, fonts, audio, credentials, unknown fields and private
  locator parameters. Four focused tests pass. R16's network-observation and
  two-device integration evidence remains Not run.

- `ImmutableEventMerger` preserves concurrent branches based on parent event
  IDs, deduplicates repeated events, and does not silently resolve concurrent
  delete/read activity. Four focused tests pass; WebDAV transport and server
  integration remain Not run.
- `AudioSessionStateMachine` verifies offline-voice gating and stale callback
  invalidation. `PdfAnchor`/`PdfInteractionPolicy` verify stable restoration
  fields and zoom-pan priority. Six focused tests pass. Background/lock-screen
  audio and native PDF rendering are Blocked pending Android device access;
  iOS also requires macOS tooling and signed-device conditions.

## G1 blocked gates

| Gate | Status | Needed evidence |
| --- | --- | --- |
| Android APK/native-plugin build | Blocked | Gradle distribution download timed out. Restore Maven/Gradle access, then build debug/profile APK. |
| Android gesture/PDF/audio | Blocked | User-connected device and VS Code run session. |
| Android offline/lock-screen TTS | Blocked | Installed offline voice, flight-mode and media-control device tests. |
| iOS PDF/audio/build | Blocked | macOS/Xcode; unsigned CI build is build-only, physical device needs signing. |
| WebDAV transport/concurrency | Blocked | Controlled WebDAV endpoint and two independently persisted device states. |

## G2 evidence

- `TextNormalizer` preserves empty blocks while removing BOM and normalizing
  line endings. `TextAnchorResolver` snaps offsets to grapheme boundaries and
  stores a context hash. `GraphemeSafeChunker` round-trips Chinese, emoji,
  combining characters and URLs without breaking clusters. Four focused tests
  pass. This is not yet file-picker import, encoding detection or visual layout.
- `FileSelectorTextFilePicker` selects `.txt` files through the maintained
  native cross-platform selector. The import boundary recognizes UTF-8,
  cancellation and malformed bytes; three focused tests pass. It is not yet a
  persisted import and does not claim GBK/GB18030 support.
- `LocalLibraryScreen` wires native TXT selection into the app entry point and
  opens a normalized-text preview. Import success and cancellation have widget
  integration evidence. This remains session-only: no durable book record,
  original-file copy, encoding fallback, real pagination or restore yet.
