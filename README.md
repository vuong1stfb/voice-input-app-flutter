# voice-input-app-flutter

Windows-first Flutter desktop app for hold-to-talk voice input with:

- system tray
- global hotkeys
- Soniox realtime transcription
- original / translation output
- paste into the currently focused app

## For End Users

### Windows package

Download:

- `release/input_app_flutter-windows-x64.zip`

After extracting, run:

- `input_app_flutter.exe`

### What the app does

- Opens a Windows desktop app with tray support
- Warms up the microphone and Soniox session on startup
- Lets you hold a hotkey to speak
- On release, finalizes transcript and pastes text into the active app

### Default hotkeys

- `F9`: paste original transcript
- `F8`: paste translated transcript

### Basic usage

1. Start the app.
2. Wait until the status shows `Ready`.
3. Focus any app or text field where you want text inserted.
4. Hold `F9` or `F8`.
5. Speak.
6. Release the hotkey.
7. The app pastes the result into the focused app.

### Notes

- On startup, the microphone indicator may appear immediately because the app opens the mic stream in advance to reduce latency.
- If clipboard paste is enabled, the app uses clipboard + `Ctrl+V`.
- If clipboard paste is disabled, the app types text directly.

## For Developers

### Repo scope

This repo has been trimmed so GitNexus focuses on app source instead of full Flutter platform scaffolding.

Main source files:

- `lib/main.dart`
- `lib/soniox_transcriber.dart`
- `windows/runner/flutter_window.cpp`
- `windows/runner/flutter_window.h`
- `windows/runner/main.cpp`

### Current runtime flow

1. App startup loads settings from `SharedPreferences`.
2. Windows tray and native hotkeys are initialized.
3. Microphone stream is opened during warm-up.
4. A Soniox WebSocket session is prepared.
5. Hotkey down starts a recording session.
6. Audio is buffered and sent to Soniox in chunks.
7. Hotkey up sends tail silence and `finalize`.
8. Final transcript is selected and pasted into the focused app.

### Requirements

- Windows
- Flutter SDK installed
- Visual Studio Build Tools with `Desktop development with C++`

### Run in debug

```powershell
cd C:\dev\input_app_flutter
flutter pub get
flutter run -d windows
```

### Build release

```powershell
cd C:\dev\input_app_flutter
flutter build windows --release
```

Release output:

- `build\windows\x64\runner\Release\input_app_flutter.exe`

### Package release zip

Current packaged archive:

- `release/input_app_flutter-windows-x64.zip`

### Soniox settings

Config is editable from the app UI:

- token endpoint
- websocket endpoint
- source language hint
- target language
- paste mode
- launch-to-tray

### Troubleshooting

- If tray menu does not show, right-click the tray icon again after startup finishes.
- If hotkeys do nothing, check the app status text first.
- If transcription is missing text, watch the `Session transcript` section in the UI.
- If paste behavior is wrong, switch between clipboard mode and direct typing mode.

### Logs

Useful local logs:

- `flutter_app.log`
- `soniox_debug.log`
- `windows_runner.log`
