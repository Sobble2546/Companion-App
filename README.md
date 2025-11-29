# Companion-App

Flutter Android companion app for an Arduino Nano + HC-05 eye-break reminder. The complete Flutter project lives in `companion_app/` and is intentionally tailored for Android-only builds that can be produced entirely inside GitHub Codespaces.

## Repository layout
- `companion_app/` – Flutter project with Bluetooth UI, overlay logic, and Android config.
- `README.md` (this file) – step-by-step environment setup, build, and export notes.

## Set up Flutter & Android SDK in Codespaces
All commands run inside the Codespace terminal. Stop any running tasks (e.g., `npm start`) before proceeding so the install steps have enough memory.

### 1. System dependencies
```bash
sudo apt-get update
sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa ninja-build clang cmake pkg-config openjdk-17-jdk
```

### 2. Install Flutter SDK (stable channel)
```bash
cd $HOME
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
flutter config --no-analytics
flutter doctor
```
> If your Codespace cannot reach `storage.googleapis.com`, configure the proxy that your organization requires or temporarily allowlisted domains so Flutter can download its Dart SDK/cache.

### 3. Install Android SDK command-line tools
```bash
export ANDROID_SDK_ROOT=$HOME/android-sdk
mkdir -p $ANDROID_SDK_ROOT/cmdline-tools
cd /tmp
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-11076708_latest.zip
mv cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest
echo 'export ANDROID_SDK_ROOT=$HOME/android-sdk' >> ~/.bashrc
echo 'export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"' >> ~/.bashrc
source ~/.bashrc
sdkmanager --sdk_root=$ANDROID_SDK_ROOT "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```
Need to replace only line. Wait patch wrong? we inserted closing code block extra? I need to patch properly. We'll patch snippet to proper line. Need to re-open file? We'll patch from start. Use apply_patch to replace line with correct. Need patch with proper context.
```

### 4. Accept Android licenses
```bash
yes | sdkmanager --sdk_root=$ANDROID_SDK_ROOT --licenses
flutter config --android-sdk $ANDROID_SDK_ROOT
flutter doctor --android-licenses
flutter doctor
```

## Build & export the APK
```bash
cd /workspaces/Companion-App/companion_app
flutter pub get
flutter build apk --release
ls build/app/outputs/flutter-apk/app-release.apk
```
The resulting `app-release.apk` can be downloaded from the Codespace or sideloaded with `adb install`.

## App workflow summary
1. Pair your phone/tablet with the HC-05 module in Android system Bluetooth settings (PIN is usually `1234`).
2. Launch the app and tap **Request Permissions** to grant Bluetooth + Location access (required for scans on Android 12+).
3. Tap **Allow Draw-Over & Background** and approve the system dialogs so the reminder overlay can appear on top of other apps and the process isn’t dozed.
4. Tap **Scan For Devices**; pick the bonded HC-05 entry and press **Connect**.
5. Keep the app running; it listens for newline-delimited serial messages from the Arduino timer.
6. When the HC-05 sends `BREAK_TIME`, `START_BREAK`, or `LOOK_AWAY`, the app vibrates and blocks the UI with a full-screen \"Look Away for 20 Seconds\" overlay until you acknowledge it.

## Bluetooth plugin choice
HC-05 is a Bluetooth Classic (SPP) module, so `flutter_bluetooth_serial` is used instead of `flutter_blue_plus` (BLE focused). This satisfies the requirement for a proven Bluetooth plugin while ensuring compatibility with serial profiles.

## Troubleshooting
- **`flutter doctor` cannot download artifacts** – ensure outbound access to `storage.googleapis.com` and `dl.google.com`. Re-run `flutter doctor`.
- **Device not listed** – confirm it is paired in Android settings and powered, then tap **Scan For Devices** again.
- **Permissions denied** – open Android Settings → Apps → Nano Companion → Permissions and re-enable Bluetooth/Location.
- **Overlay not showing while in background** – revisit **Allow Draw-Over & Background**, then in Android Settings grant “Display over other apps” and set Battery → “Unrestricted”.
- **APK build fails about Java** – confirm OpenJDK 17 is installed and `JAVA_HOME` points to `/usr/lib/jvm/java-17-openjdk-amd64`.
