# GRATE (grate_app)

Flutter jewellery shop app: daily rates, purchase/sales, ledgers, reports. Data can run on **local SQLite** or a **remote PostgreSQL API** (`lib/config/api_config.dart`).

## Supported platforms

| Platform | Status | Notes |
|----------|--------|--------|
| **Android** | Primary | Full feature set including Bluetooth thermal print where configured. |
| **Windows / Linux** | Supported | Desktop SQLite path + PDF/share; same UI as mobile. |
| **iPhone / iPad (iOS)** | Supported | Standard Flutter `ios/` project; uses native `sqflite` on device. Build and sign on a **Mac with Xcode**. |
| **Mac (macOS)** | Supported | Standard Flutter `macos/` project; uses `sqflite_common_ffi` + user Application Support DB when not on remote API. Build on **Mac with Xcode**. |

The app is one codebase (`lib/`). Layout is responsive; phone and tablet orientations are enabled on iOS.

### What you need for Apple builds

1. **Mac** with Xcode (from the Mac App Store) and Flutter SDK installed.
2. **Apple Developer Program** membership ($99/year) to install on physical devices and to ship on the **App Store** or **Mac App Store**.
3. **Signing**: replace the default bundle id `com.example.grateApp` in `ios/` and `macos/` with your team’s id (e.g. `com.yourcompany.grate`) in Xcode → Runner → Signing & Capabilities.
4. **HTTPS (recommended for production)**: `ApiConfig.baseUrl` is currently `http://…`. iOS allows this VPS via an ATS exception in `ios/Runner/Info.plist`. For App Store review, Apple prefers **HTTPS** on your domain; switch `baseUrl` to `https://yourdomain.com/api` and remove or narrow ATS exceptions when SSL is live.

### Build commands (on a Mac)

```bash
flutter pub get
flutter build ios --release          # iOS .app / archive via Xcode
flutter build macos --release        # macOS .app in build/macos/Build/Products/Release/
```

Open in Xcode when you need signing or TestFlight:

```bash
open ios/Runner.xcworkspace
open macos/Runner.xcworkspace
```

### Feature differences on Apple

- **Remote API**: enabled when `ApiConfig.useRemoteApi == true` (default in repo). macOS sandbox includes outbound network; iOS uses ATS as configured in `Info.plist`.
- **Thermal receipt printing**: flows that depend on mobile-only hardware may be limited on Mac; PDF export and share still work where implemented in the UI.
- **Local-only mode**: set `useRemoteApi` to `false` to use on-device SQLite (iOS native DB; Mac stores DB under Application Support).

## Getting started (all platforms)

```bash
flutter pub get
flutter run
```

Pick a device: Android emulator, `chrome`, Windows desktop, or on a Mac an iOS simulator / macOS desktop target.
