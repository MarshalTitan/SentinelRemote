# Sentinel Remote — remembered setup preview 0.4.0

Android companion for private PC desktop access and a small rescue gamepad. Keep Tailscale installed and connected on both devices; no separate Sentinel account is introduced.

Use Windows **0.4.0** and [current setup instructions](https://github.com/MarshalTitan/SentinelRelay/blob/feature/sentinel-remote-gamepad-integration/remote/docs/DESKTOP_MIRROR.md). Existing control phones need **Trust selected phone** once. New phones paste one PC setup code; a visible local trust approval is saved across PC restarts. Controller support prepares automatically. The signed USBip driver remains a one-time PC prerequisite.

The app remembers the last selected PC and renews read-only sessions after host restarts. Desktop works before FFXIV opens: touch opens ordinary apps/files, keyboard typing operates launcher login and character selection. Desktop checks for approved characters and enables its gamepad icon once Relay connects, without returning Home. Gamepad acquisition always needs a tap. Portrait and landscape combine screen and controls.

Returning from background resumes viewing; explicit Stop stays stopped. Network/view recovery uses bounded backoff and clears old actions. No mouse/key/text/rescue action is automatically replayed, and gamepad never reacquires automatically. PC Pause removes remembered full-PC trust; Revoke removes the phone credential; Disable all access prevents automatic host resume.

The preview uses the primary monitor, at most 3 FPS/1280×720/320 KiB JPEG, with recent displayed-frame IDs, socket sequences and complete input batches. No disk recording, clipboard sync, generic remote shell/filesystem API or stored typed credentials. Windows must be awake/unlocked. Real launcher login, full view+pad handoff, restart/pause behavior and monitor-off rendering still require field acceptance. Basic monitor viewing/touch positioning and earlier native movement/camera were user-confirmed.

**Sentinel Remote Preview** remains a separate Android application ID. CI debug signing is temporary: if Android rejects an update, uninstall only Preview, install the new APK and re-pair. Stable signing and iPhone distribution remain separate work.
