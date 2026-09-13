# Delivery status

Last updated: 2026-09-13

| Stage | Status | Evidence / limitation |
| --- | --- | --- |
| G0 engineering audit | Complete | New Flutter Android/iOS project; lockfile, analysis, tests and a structurally validated Android Debug APK. iOS requires macOS. |
| G1 risk spikes | Complete with blocked platform gates | Text, page-curl/menu, source preflight, sync merge/whitelist, audio and PDF contracts have automated evidence. Native rendering, media, WebDAV transport and device validation remain explicitly blocked. |
| G2 reading and state | In progress | Persistent TXT/PDF import, encoding fallback, local state, text restore, appearance controls and a native PDF viewer are implemented. Real-book four-mode pagination/curl and device acceptance remain. |
| G3 online and offline | In progress — implementation assembled; acceptance gates open | Safe static sources support search/detail/catalogue/reading, network-shelf persistence, bounded pagination, durable cache-backed downloads and verified source switching. A compatible live source plus Android device validation are still required before this stage can be accepted. |
| G4 | In progress — foundations implemented; platform/service gates open | Offline TTS queue primitives, local reading-union accounting, versioned sync events and a durable whitelist-enforced outbox are covered by automated tests. Native TTS/media service, WebDAV transport/settings and all device/two-device acceptance remain. |
| G5 | In progress — device defects reopened | User iPhone screenshots show import-picker failure and substantial visual gaps. See 2026-09-13 correction below. Final visual acceptance is not passed. |
| G6 | In progress | GitHub iOS packaging workflow exists; build success and device acceptance must be tracked separately. |

## 2026-09-13 iPhone import and shell correction (build 1.0.0+2)

- Root cause: all four file-selector type groups specified extensions only. The locked iOS adapter rejects these before native picker presentation. Added shared UTIs for TXT/PDF, JSON, and TTF/OTF, retaining extension filters for other platforms.
- Regression: real `FileSelectorIOS` Dart adapter with mocked native transport reproduces the old error and verifies each corrected group reaches transport; cancel returns null. This is not native Files/iCloud end-to-end validation.
- UI: neutral light/black dark surfaces, large leading titles, rounded three-tab navigation, compact library overflow menu, no production spike shortcut, separate working local/online search entry points, home settings and semicircular reading goal. Existing repositories and stored books are preserved.
- Validation: `dart analyze` clean; `flutter test --no-pub` 85 passed. Phone-sized shell test covers tabs/menu and absence of layout exceptions. Review renders in ignored `build/ui-review/`; substitute Windows/test fonts do not prove iOS typography fidelity.
- Remaining R02 differences: U01-U12 are not fully reference-aligned; populated shelf cover/progress/menu presentation, search inline layout, reader transitions and native safe-area/blur/font behavior still require work and device review. Light appearance is a design inference from the supplied dark reference frames.
- Native TXT/PDF/JSON/font selection, iCloud providers, Android device import, and iOS build+install of this revision: not yet verified. Do not mark G5 complete based on these unit/widget results.

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
| Android APK/native-plugin build | Build passed | Debug APK assembled after Gradle recovery; physical install and plugin behavior are still pending. |
| Android gesture/PDF/audio | Blocked | User-connected device and VS Code run session. |
| Android offline/lock-screen TTS | Blocked | Installed offline voice, flight-mode and media-control device tests. |
| iOS PDF/audio/build | Blocked | macOS/Xcode; unsigned CI build is build-only, physical device needs signing. |
| WebDAV transport/concurrency | Blocked | Controlled WebDAV endpoint and two independently persisted device states. |

## G2 evidence

- The library now accepts TXT and PDF through the native file picker. It writes
  an imported copy to the application documents directory via a `.part` file
  and atomic rename, then writes the book index through the versioned local
  state store. A failed index write deletes the copied import; cache cleanup
  does not target the imports/font folders.
- TXT uses strict UTF-8 first, then explicit GB18030, GBK and Big5 platform
  codecs. Successful legacy imports are normalized to UTF-8 once and keep their
  detected source encoding as metadata. This avoids different decoder guesses
  on a later open.
- Opening a TXT restores its saved block anchor and persists a new anchor only
  after a page change. Size, line-height and a copied TTF/OTF font are saved as
  reader preferences; a bad font keeps the last usable font and shows feedback.
- PDF is displayed as its original fixed layout with the `pdfrx` native viewer;
  its Android native PDFium libraries were found in the Debug APK. Password,
  damaged-file and real-device pan/zoom recovery have not yet been accepted.
- `dart analyze` passed with no diagnostics and `flutter test --reporter
  expanded` passed 37 tests. `:app:assembleDebug --no-daemon` completed and
  produced a 220,849,788-byte APK containing `classes.dex`, Flutter assets and
  PDFium libraries. None of these are a physical-device test.

- `TextNormalizer` preserves empty blocks while removing BOM and normalizing
  line endings. `TextAnchorResolver` snaps offsets to grapheme boundaries and
  stores a context hash. `GraphemeSafeChunker` round-trips Chinese, emoji,
  combining characters and URLs without breaking clusters. Four focused tests
  pass. This is not yet file-picker import, encoding detection or visual layout.
- `FileSelectorTextFilePicker` selects `.txt` files through the maintained
  native cross-platform selector. The import boundary recognizes UTF-8,
  cancellation and malformed bytes; three focused tests pass. It is not yet a
  persisted import and does not claim GBK/GB18030 support.
- `LocalLibraryScreen` is no longer a session-only preview: it presents the
  persistent book grid and opens the durable TXT/PDF routes. The old widget
  integration test was removed because it exercised the replaced session-only
  screen; the surviving text-import contract tests still cover cancel, malformed
  data and UTF-8 normalization.

## G3 evidence

- `SourceManagementScreen` accepts a Legado JSON file through the native file
  selector and persists valid entries in the local versioned store. Reimporting
  the same URL replaces its prior entry instead of creating duplicates.
- The provided source is a supported import specimen, not a supported runtime
  source: its `@js:` cover rules are retained for transparent reporting and its
  entry is disabled. No code path executes JavaScript or sends source data to
  the network. Seven source-engine tests and static analysis pass.
- `StaticSourceEngine` now has a deliberately limited, non-WebView execution
  path for CSS selectors and text/attribute extraction: search → details →
  catalogue → content. It enforces request cancellation, a response-size cap,
  a timeout, relative-link resolution and pre-request rejection of dynamic
  rules. Its mocked HTTP fixture covers the full static path plus script
  rejection and cancellation. It does not claim XPath/JSONPath, rule
  expressions or live source compatibility. Catalogue and content pagination
  stop at a strict page cap and de-duplicate visited URLs, so cyclic static
  sources cannot loop indefinitely.
- Ready static sources now open a search UI, then a detail/catalogue route and
  a readable chapter route. Each chapter checks a source/version/locator-bound
  cache first, writes new content through a `.part` file and keeps imported
  books/fonts outside its cleanup scope. The cache's source binding and cleanup
  isolation have focused automated coverage. Search UI has not been exercised
  on a physical Android device or against a live compatible source.
- `SourceSwitchService` has an explicit verified-target / compare-and-swap
  contract: an empty or stale candidate cannot overwrite the current readable
  binding. Focused tests cover stale and unverified switch rejection. The
  durable binding UI requires an explicit source, target URL and stable chapter
  key, reads the target body first, then commits a revision-checked atomic
  replacement. It never guesses a mapping by title or ordinal.
- Search detail pages can persist a network book and create a download-all
  task. Tasks retain only URL/key metadata, save progress after each
  cache-verified chapter, preserve completed chapters on cancellation and
  resume unfinished work on retry. A source-revision mismatch cancels the old
  task rather than mixing content from different sources. The library exposes
  separate network-shelf and download-task routes.
- `dart analyze` and the complete Flutter test suite pass after these changes.
  Mocked coverage now includes paged catalogue de-duplication and loop exit,
  task payload durability, source-rule rejection, cancellation, cache
  isolation and source-switch stale/empty rejection. This is not a live-source
  or physical-device verification.
- The latest G3 code was assembled with
  `./gradlew.bat :app:assembleDebug --no-daemon --stacktrace` from `android/` on
  2026-09-13. It produced
  `build/app/outputs/apk/debug/app-debug.apk` (221,663,582 bytes; SHA-256
  `13BF9C50B0119F88ED624349DB894D7A97705A27FF864240DE56ACBEB7D13036`).
  The APK contains `classes.dex`, Flutter assets, ARM64 Flutter/PDFium
  libraries. Gradle emitted SDK-XML and AGP/Kotlin deprecation warnings but
  exited `BUILD SUCCESSFUL`; no Android device was attached for installation.
- [source-compatibility.csv](source-compatibility.csv) distinguishes the
  mocked static CSS fixture from the supplied script-bearing JSON. It records
  no unverified source as compatible and contains no user path, credential or
  raw source configuration.
- Database v3→v4 migration now has an on-disk fixture proving existing book,
  position, source and network-shelf rows survive while binding/task stores
  are added. Competing source switches are serialized and verified across a
  reopen; cache cleanup resets durable offline claims before deleting bodies.
- Static HTTP decoding now treats declared UTF-8 strictly and routes other
  declared charsets through the app's native charset converter. A malformed
  UTF-8 fixture is reported as a parse failure rather than silently producing
  corrupted chapter text; a live GBK/GB18030 source remains unverified.
- Download-manager integration fixtures now perform mocked request → parser →
  cache → durable task transitions. They prove a binding-revision mismatch
  makes zero requests, and cancellation both during the first persistence
  window and during an active response leaves no completed key or cache body.
- Source management now exposes a bounded three-at-a-time all-safe-source
  search. Each source emits results or its own error independently, while a
  new query or screen disposal cancels prior generations so stale results do
  not enter the current list. Live multi-source timeout behavior is still a
  device/source acceptance gate.
- Reimporting a source URL now preserves the currently bound configuration
  rather than silently changing rules under a live binding. The import report
  and UI identify retained entries; a user must use the verified source-switch
  flow to change that source for an active book.
- Adding a network book now creates its initial source/chapter binding in the
  same local transaction as shelf metadata. Re-adding it cannot reverse a
  later switch, and the network shelf opens the persisted binding first rather
  than implicitly returning to its original source.

## G4 evidence

- `VoiceDescriptor` now carries locale and an availability reason alongside
  its offline eligibility. `SpeechTextNormalizer` turns normalized chapter
  text into bounded, stable chapter/sentence anchors; it never refers to a
  rendered page, so font or layout changes do not invalidate a queued
  narration position. The existing generation gate still prevents a stopped
  session's stale native callback from changing a newer session.
- `ReadingActivityTracker` receives a monotonic elapsed-time function and
  records the union of active reading and listening intervals. It cannot
  double-count concurrent visual reading/audio and rejects negative elapsed
  spans. Daily keys are supplied by the app boundary, so a future app lifecycle
  adapter can checkpoint exactly at a local-day boundary. It does not yet have
  a reader-screen lifecycle binding or a statistics screen.
- Local state schema v5 adds separate reading-statistics and sync stores;
  v1-v4 data migrates without discarding existing library/source/download data.
  `SyncEventCodec` encodes the protocol's schema/device sequence/parents/type
  and validates a canonical SHA-256 payload hash before application. The
  durable outbox uses the same atomic database transaction and refuses fields
  outside the strict whitelist before they are stored. Credentials, bodies,
  imported files, audio, fonts, paths, reading statistics and preferences have
  no permitted route into these events.
- iOS declares the audio background mode. This is configuration only: there is
  no native AVSpeech/Android media-service adapter yet, therefore no claim is
  made for background, lock-screen, interruption or headset behavior.
- `WebDavEventTransport` uses per-device immutable paths, conditional `PUT`,
  authenticated readback and payload-hash decoding before an outbox event can
  be considered uploaded. `PROPFIND` accepts namespace-prefixed DAV `href`
  entries but filters strictly to this app's JSON event directory. HTTP 412,
  malformed remote data and unsafe path components are returned as failures;
  the outbox is consequently retained for retry. Credentials are an ephemeral
  injected value only, not database state; platform secure-storage wiring and
  a user-supplied endpoint are still pending.
- On 2026-09-13, `dart analyze` completed with no diagnostics and `flutter
  test` passed 73 tests, including G4 speech anchoring, interval-union,
  payload-tampering, persisted-outbox and mocked WebDAV protocol cases. No
  real WebDAV endpoint, Android device, iOS/macOS build or two-device conflict
  recovery has been run.
- `:app:assembleDebug --no-daemon` also completed successfully after the G4
  changes. It is a compile/package check only; Gradle emitted existing AGP /
  Kotlin deprecation and SDK-XML compatibility warnings, and no physical
  Android installation was performed.
