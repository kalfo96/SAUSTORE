# DreamStore Android release

The Android application talks to the public HTTPS PHP API. It must never contain
the MySQL hostname, database name, database username, database password, or the
administrator setup token. Those values belong only in the server-side
`dreamstore-private/config.php` file.

## 1. Verify the live server

Open `https://dreamstore.sauinndream.com/api/health`. Do not build the launch
release until it returns:

```json
{"status":"ok","service":"DreamStore API","schemaVersion":3}
```

The checked-in Android production configuration is
`config/android-production.json`; it contains only the public API URL. Demo data
is disabled. The web deployment uses the same-origin `/api/` value in
`config/cpanel.json`.

## 2. Create and protect the Android upload key

Create an upload key in Android Studio with **Build > Generate Signed
Bundle/APK > Create new**, or follow Flutter's Android release documentation.
Keep the keystore outside the project and back it up securely. It cannot be
reconstructed from the source code.

Copy `android/key.properties.example` to `android/key.properties` and enter the
keystore path, alias, and passwords locally. Both `key.properties` and common
keystore extensions are ignored by source control. Never send their contents in
chat, email, a deployment ZIP, or a support ticket.

The Android application ID is currently `com.sau.stockpilot`. Confirm it before
the first Play Console upload because it cannot be changed for that published
application afterward.

## 3. Validate and build

Accept any outstanding Android SDK licences once:

```powershell
flutter doctor --android-licenses
```

Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_android_release.ps1
```

The script checks the live API, resolves packages, runs analysis and tests, and
creates a signed APK plus a signed Android App Bundle. It prints a SHA-256 hash
for each result. Outputs are:

```text
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/bundle/release/app-release.aab
```

Use the APK for controlled device testing. Use the AAB for Google Play internal
testing and production distribution.

## 4. Release checks

- Install the APK on at least one real phone and test sign-in over mobile data.
- Receive stock, record department usage, record/void a sale, and refresh from
  a second device to verify the shared database and revision conflict handling.
- Confirm the app never treats a failed network save as a completed movement.
- Test large text, dark mode, rotation, back navigation, and a slow connection.
- Export and restore a non-production backup before relying on the system.
- Prepare the Play listing, support contact, privacy policy, data-safety answers,
  screenshots, feature graphic, and an internal-test release before production.

iOS release signing and App Store submission require macOS, Xcode, an Apple
Developer account, and a separate review on Apple hardware.
