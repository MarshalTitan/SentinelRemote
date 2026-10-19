# Sentinel Remote

Android-first companion for the privately paired Sentinel Relay PCs. This candidate provides secure pairing, a PC/client selector, status, screenshot requests and existing SRank rescue operations with explicit reset confirmation. All game operations require the matching optional PC host and an opted-in Relay plugin bridge. Manual sticks/buttons, live video and launcher recovery are later stages.

## Build

The CI workflow pins Flutter 3.47.2 and generates the standard Android platform shell into `.platform`, then applies the reviewed application source and minimal platform configuration. This keeps generated Gradle wrappers/assets reproducible without committing binaries. Requires Flutter, Python 3, Java 17 and an Android SDK.

```sh
flutter create --platforms=android --org dev.marshaltitan --project-name sentinel_remote .platform
python3 tool/prepare_android.py
cd .platform
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

`Android proving build` uploads a signed **debug** APK, dependency lock and SHA-256 checksum. This is a supervised installation candidate, not a store/production release. CI's temporary debug signing identity can change between runs; a later candidate may need uninstall/reinstall and fresh pairing until a stable private release signing key is configured. Never commit a signing key or key.properties. Android minimum API is 24. iOS packaging remains deferred.

## Security

- HTTPS tailnet origins ending `.ts.net` only, normal certificate validation, no redirects or URL credentials.
- PC device credential stored using pinned `flutter_secure_storage` 10.3.4 (BSD-3-Clause). Session tokens and reset confirmation values remain in memory.
- Android backup and cleartext traffic disabled; secure-window flag prevents screenshots/task-switcher previews of the app.
- Per-PC HostId binding, monotonic per-session sequences and serialized requests; no automatic retry of skip/reset after an uncertain response.
- Backgrounding closes network connections, drops sessions and clears displayed screenshot/status. Returning refreshes status; it does not reissue a game command.
- Removing a PC erases the phone's saved credential; also revoke that device locally on the PC. Pairing invitations expire after two minutes and are never saved by the app.
- The app has no arbitrary chat, process, shell, filesystem, mouse/keyboard or desktop-control feature.

## First proving session

Use the matching SentinelRelay bridge/host candidate and follow its setup checklist. Pair using the PC's private HTTPS address and local invitation; confirm both client labels map to the correct characters, then test status, screenshots, skip and reset confirmation. Test revocation, local disable, game logout/switch and network interruption. Unknown status fields stay unknown. The application must not be treated as an unattended recovery tool before supervised acceptance.

The full [Milestone A installation and test checklist](https://github.com/MarshalTitan/SentinelRelay/blob/main/remote/docs/MILESTONE_A.md) includes the matched plugin/host downloads, per-character opt-ins, local process binding and one consolidated set of checks.

Flutter and platform dependency licenses are available in the framework/package notices; app dependency versions are retained in CI's pubspec.lock. No source from AGPL remote-desktop/controller tools is copied. App source is MIT licensed.
