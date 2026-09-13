# Engineering decisions

## D01: Baseline and project identity

- Date: 2026-09-13; requirements: R01, H02.
- Flutter + Dart, feature modules with MVVM and Repository boundaries; native
  Swift/Kotlin adapters only where a platform capability requires them.
- Initial scaffold: Flutter 3.47.4, Dart 3.13.3, Android SDK 36.0.0, JDK
  21.0.12. `com.example.paperages.paper_ages_reader` is a temporary technical
  identifier, not a user-approved release identity.
- Flutter generated iOS deployment target 15.0. Android SDK floors remain
  Flutter-template defaults until Q03 is settled.

## D02: G1 is isolated risk work

Before production screens, validate text layout/anchors and all four modes, PDF
rendering/zoom, a white-listed non-JavaScript source-rule compiler, platform
offline TTS/media sessions, and WebDAV immutable-event merge/whitelist behavior.
No storage, PDF, parser, TTS or WebDAV dependency is selected before its
relevant spike records maintenance, license and platform evidence.

### G1 page-turn result (2026-09-13)

The first harness keeps the transition decision in `PageTurnPolicy`, outside
the animation widgets. A small drag returns `stay`; threshold distance or fling
velocity determines one previous/next outcome; unavailable geometry remains
`stay`. Slide, fade and continuous scroll have separate visual branches but
share that decision policy where pagination applies. The harness uses fixed
pages and does not claim real pagination, anchors, device gesture validation or
the required page-curl effect.

### G1 rule-safety result (2026-09-13)

`RuleSafetyPolicy` is a conservative importer preflight. It recursively checks
configuration keys and values for JavaScript directives, script markup,
expressions, dynamic libraries and execution bridges, returning paths and
machine-readable reasons. It performs no parsing, HTTP or WebView work. This
is intentionally a security boundary, not a claim of Legado rule compatibility.

### G1 sync-whitelist result (2026-09-13)

`SyncWhitelistPolicy` is deny-by-default before an event can enter an upload
outbox. It permits only explicit immutable-event headers, shelf metadata, safe
source locators and anchors. It rejects document paths/bodies, fonts, audio,
credentials, unknown fields and token-bearing locators. It does not yet make an
HTTP/WebDAV request, merge events or handle server failures.

## Device and distribution plan

Android device validation will use the user's Windows 11 + VS Code setup when a
physical device is connected. The project will supply exact debug/profile build
and test steps at that gate. A future public GitHub repository can use a macOS
workflow to validate an unsigned iOS build, but an unsigned IPA cannot install
on a physical iPhone. Physical iOS tests require a valid signing/provisioning
route or TestFlight; no credentials or repository are created by this project.

## Dependency review for native risk tests

The review on 2026-09-13 retained two candidates without adding either to the
lockfile yet: `pdfrx 2.6.1` (MIT; Android/iOS support; its Windows native build
requires Developer Mode) and `audio_service 0.18.19` plus `flutter_tts 4.2.5`
(MIT; Android/iOS background-media and system-TTS candidates). Their public
documentation requires platform configuration and device validation; package
availability is not treated as proof of PDF rendering or locked-screen TTS.
They will be selected only in the subsequent native implementation step after
the Android build network path and connected-device test route are available.

### G1 audio and PDF contract result (2026-09-13)

`AudioSessionStateMachine` admits only installed offline voices and uses a
monotonic playback generation, so obsolete callbacks cannot restart playback
after stop, interruption or a newer session. `PdfAnchor` stores document
identity, a zero-based page and normalized viewport coordinates; the gesture
policy gives zoom/pan priority while enlarged or multi-touch. These are tested
domain contracts, not claims that a platform synthesizer ran in the background
or that a native PDF page rendered.

## G2 text-position baseline

`characters 1.4.1` is now a direct dependency, promoted from Flutter's existing
transitive lock entry solely to use its grapheme-cluster contract. Text import
normalizes BOM and line endings but does not collapse or strip content.
`TextAnchor` stores a normalized block identifier, UTF-16 offset, context hash
and normalization version. Chunking may prepare work units but never decides
visual pages, which still require actual font/viewport layout.

`file_selector 1.1.0` (Flutter.dev, BSD-3-Clause) is selected for the native
Android/iOS file-selection UI. The first adapter is TXT-only and explicitly
accepts UTF-8: cancellation and malformed data stay distinguishable from a
successful import. Common Chinese legacy encoding detection, sandbox copy and
transactional book persistence remain separate, unimplemented work.

## D03: Data authority

A Book UUID is independent of source and local path. One ReadingPosition
(TextAnchor or PDFAnchor) is the authoritative book progress. SourceBinding,
cache, layout and playback revisions prevent stale work from overwriting newer
state. WebDAV may contain only book metadata, safe locators, bindings, anchors,
shelf state and event metadata; it must exclude local documents, bodies, fonts,
audio, credentials, source JSON, paths, themes and statistics.

## Open inputs

Q02 release identity/signing, Q03 target devices/OS floor, Q04 representative
Legado JSON, Q05 WebDAV test service, Q06 missing visual references, and Q07
distribution remain open and do not block G0.

## Tooling verification note

`flutter analyze` triggered an analysis-server LSP JSON parser failure in this
non-ASCII workspace path. Direct `dart analyze` on the same source passed with
no diagnostics, so source analysis has a reproducible passing command. Keep the
Flutter-wrapper failure recorded; do not upgrade Flutter solely to mask it.
