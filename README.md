# fotbal_matchmaker (SIMF)

Aplicație Flutter pentru matchmaking și rating fotbal (vezi `specification.md`).

## Mediu de dezvoltare pe macOS

`flutter doctor` trebuie să poată folosi **Xcode** (inclusiv pentru ținta **macOS desktop**): fără `xcodebuild`, comenzi precum `flutter run -d macos` eșuează cu *unable to find utility "xcodebuild"*.

1. Instalează **Xcode** din App Store (instalare completă, nu doar Command Line Tools).
2. Deschide Xcode o dată, acceptă licența.
3. În terminal:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

4. Pentru plugin-uri pe iOS/macOS: instalează **CocoaPods** (`sudo gem install cocoapods` sau Homebrew).
5. **Android:** instalează Android Studio și SDK dacă vrei `flutter run` pe Android.
6. **Web:** instalează Chrome sau setează `CHROME_EXECUTABLE` către executabilul Chromium.

## Supabase

Copiază `simf_defines.example.json` → `simf_defines.json` și completează URL + cheia **anon**. În VS Code/Cursor rulează configurația **SIMF + Supabase**, sau:

```bash
flutter run -d macos --dart-define-from-file=simf_defines.json
```

Migrarea SQL este în `supabase/migrations/`.

## Resurse Flutter

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Documentație Flutter](https://docs.flutter.dev/)
