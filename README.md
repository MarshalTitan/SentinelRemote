# Sentinel Remote — desktop and rescue preview 0.3.0

An Android companion for privately viewing and manually controlling the PC desktop, followed by a small in-game rescue gamepad. The primary desktop is available with FFXIV closed: open apps/files through touch, operate XIVLauncher, type required login/OTP text and select the intended character yourself. The gamepad remains bound to an enrolled opted-in character, with exactly one FFXIV process.

See [PC setup and field checklist](https://github.com/MarshalTitan/SentinelRelay/blob/feature/sentinel-remote-gamepad-integration/remote/docs/DESKTOP_MIRROR.md). Use Windows **0.3.0**, select this paired control phone and **Allow selected phone desktop**. Gamepad permission is separate and still requires Prepare/Allow on the PC.

Desktop supports tap, double-tap, long-press right-click, pinch zoom/pan, transient Unicode typing and Start/Tab/Enter/Escape/Backspace/scroll keys. The gamepad icon combines the mirrored screen with the existing sticks/D-pad/ABXY/triggers. Portrait places the view above controls; landscape uses side-by-side panes. Input is never retried automatically; view reconnect clears old actions and cannot reacquire gamepad input. Phone backgrounding stops capture/input and clears the typing dialog.

This is a recovery preview at up to 3 FPS/1280×720/320 KiB JPEG. One view per host; at most one capture and one action in flight. Frame IDs, monotonic freshness and socket sequence bind manual actions to a recent displayed frame. No disk recording, clipboard sync, file API, credential database or shell endpoint. Windows must be awake and unlocked; monitor-off/GPU/DPI behavior and the real launcher/login/game handoff still require field acceptance.

The separate **Sentinel Remote Preview** app ID preserves the original status/rescue app. CI debug signing remains temporary: if Android rejects an in-place preview update, uninstall only Preview, install this APK and create a new local pairing. Stable signing and iPhone distribution remain separate work.
