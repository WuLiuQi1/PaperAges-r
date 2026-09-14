# Paper Ages Reader

> SPDX-License-Identifier: AGPL-3.0-only

Flutter reader for Android and iOS. The release name, bundle identifier, signing identity and store distribution remain intentionally unconfigured.

## Current delivery state

The project has local TXT/PDF reading, an Open Reading-derived Legado rule runtime, cache-backed downloads, system TTS/share integration, local statistics, WebDAV event foundations, and a three-tab home shell. Detailed evidence and limits are in [quality/STATUS.md](quality/STATUS.md).

This is **not an accepted release**: real Android device tests, iOS/macOS validation, background/lock-screen TTS, live-source compatibility, and two-device WebDAV recovery remain required.

## License and attribution

Paper Ages Reader is licensed under AGPL-3.0-only. Its book-source management
and aggregated-search design is adapted from the AGPL-licensed
[Open Reading](https://github.com/miloquinn/open-reading) project, using commit
`b92c850a7e5758e7734bd757c1dc23139ca33276` as the reviewed reference. See
[LICENSE](LICENSE) and [NOTICE](NOTICE). The source subsystem keeps Paper Ages'
storage and screens while using the reviewed Open Reading runtime
implementation. Live-source/device compatibility still depends on the
individual source and platform capabilities.

## Windows development

The verified SDK location on this workstation is `C:\Users\w8852\development\flutter`.

```powershell
$flutter = 'C:\Users\w8852\development\flutter\bin\flutter.bat'
$dart = 'C:\Users\w8852\development\flutter\bin\dart.bat'
& $flutter pub get
& $dart analyze
& $flutter test
Push-Location android
.\gradlew.bat :app:assembleDebug --no-daemon
Pop-Location
```

The debug APK is generated at `build\app\outputs\apk\debug\app-debug.apk`. Connect an Android device, confirm it appears in `adb devices -l`, then use VS Code or:

```powershell
& $flutter run
```

Do not treat a successful build as a device or performance result.

## iOS build-only validation

On macOS with Xcode and CocoaPods:

```bash
flutter pub get
dart analyze
flutter test
flutter build ios --release --no-codesign
```

This validates an unsigned release iOS build. CI additionally packages
`Payload/Runner.app` as `PaperAges-unsigned.ipa` for inspection/download. It is
not installable on a physical iPhone: a device install needs an Apple
signing/provisioning route.

## WebDAV safety

Only a credential-free HTTPS directory URL is stored in app settings. Username/password use platform secure storage. Sync events exclude books, chapter bodies, fonts, audio, local paths, themes, statistics, source JSON and credentials. Use a disposable test endpoint before connecting personal storage.

## Known gates

- Android: attach a physical device for reader gestures, PDF, offline voice, lock screen, profile-frame and long-run tests.
- iOS: macOS/Xcode is required; unsigned CI output is build evidence only.
- Sources: HTML/CSS, JSONPath, XPath, request expressions, cookies, login, QuickJS and Android WebView/verification paths are implemented; validate the supplied source and failure boundaries end to end on a device. Interactive WebView verification is Android-only in the reviewed upstream implementation.
- WebDAV: validate 401/403, timeout, quota, partial upload and concurrent devices against a user-controlled endpoint.

## Licensing

Third-party package versions are locked in `pubspec.lock`. Review each dependency license before distribution; no third-party font or brand asset is bundled as a product identity.
