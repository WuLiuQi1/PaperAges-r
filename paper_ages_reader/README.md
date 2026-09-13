# Paper Ages Reader

Flutter scaffold for the Paper Ages iOS and Android reader. The production name,
bundle identifier, icon, signing identity and distribution method are deliberately
temporary until the release inputs are supplied.

## Current stage

G0 (engineering audit) is in progress. The project deliberately contains no
reader, source, TTS, PDF or sync implementation yet: G1 must first validate the
high-risk architecture assumptions. See [docs/DECISIONS.md](docs/DECISIONS.md)
and [quality/STATUS.md](quality/STATUS.md).

## Toolchain

- Flutter 3.47.4
- Dart 3.13.3
- Android SDK 36.0.0
- JDK 21.0.12

Run commands with the SDK installed at `C:\Users\w8852\development\flutter`:

```powershell
& 'C:\Users\w8852\development\flutter\bin\flutter.bat' pub get
& 'C:\Users\w8852\development\flutter\bin\flutter.bat' test
& 'C:\Users\w8852\development\flutter\bin\flutter.bat' build apk --debug
```

On macOS with Xcode, run `flutter build ios --debug --no-codesign` for an
unsigned build validation. It is not an installable IPA.
