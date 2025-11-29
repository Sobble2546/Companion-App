# Nano Companion (Flutter)

This Flutter app is an Android-only companion for an Arduino Nano timer that broadcasts break reminders over an HC-05 Bluetooth module. It pairs with the HC-05 (classic Bluetooth SPP), listens to the serial stream, and raises an immersive "Look Away for 20 Seconds" overlay with vibration feedback whenever it sees trigger messages like `BREAK_TIME` or `START_BREAK`.

## Key features
- Request and show runtime Bluetooth + Location permission status directly in the UI.
- Scan for nearby/Bonded HC-05 modules, select one, and connect/disconnect on demand.
- Live log of every Bluetooth event and message for easy troubleshooting.
- Full-screen overlay with vibration to block the display during enforced breaks, even when granted draw-over permission.
- Dedicated control to request the **Draw over other apps** and **Ignore battery optimizations** permissions required for background alerts.

## Running inside Codespaces
```bash
cd companion_app
flutter pub get
flutter run -d <android-device-id>
```
Pair your HC-05 with the Android device via Android Settings first. The in-app scan will then list the bonded device so you can connect.

## Building a release APK
```bash
cd companion_app
flutter clean
flutter pub get
flutter build apk --release
ls build/app/outputs/flutter-apk/app-release.apk
```

## Serial message contract
- Send ASCII strings ending with a newline (`\n`) from the Arduino/HC-05.
- Messages containing `BREAK_TIME`, `START_BREAK`, or `LOOK_AWAY` (case-insensitive) trigger the overlay and vibration pattern.
- Any other text is appended to the on-screen log for diagnostics.

## Overlay & background behavior
1. Android will only allow screen-blocking overlays from apps that have the **Display over other apps** capability. Tap **Allow Draw-Over & Background** in the app, then approve the permission prompt (it opens the system settings screen on Android 10+).
2. The same button also requests **Ignore battery optimizations** so the Bluetooth listener can keep running when the screen is off. If the OS still suspends the app, open Settings → Apps → Nano Companion → Battery and set it to “Unrestricted”.
3. Without these permissions the app falls back to showing the break overlay only while it is in the foreground, and a log entry will remind you to enable them.

## Customizing
- Update trigger keywords in `lib/main.dart` (`_breakTriggers` list) to support additional cues.
- Adjust the overlay visuals or vibration pattern in `_showOverlay`.
- Add more automation (e.g., auto-reconnect) by extending `_connectOrDisconnect`.
