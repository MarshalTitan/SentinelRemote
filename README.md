# Sentinel Remote Android gamepad preview

Private Android status/rescue companion with an experimental gamepad screen. This branch requires the matched Sentinel Remote Windows 0.2.3 candidate.

See the [PC setup and supervised field checklist](https://github.com/MarshalTitan/SentinelRelay/blob/feature/sentinel-remote-gamepad-integration/remote/docs/GAMEPAD_PREVIEW.md).

The preview installs as **Sentinel Remote Preview** alongside the existing app and requires its own local pairing invitation. No existing Android pairing is deleted. Keep the original app installed. CI debug signing is not stable across rebuilds; production update signing remains outstanding.

Input replies only to fresh server challenges. Complete state, one active socket, no automatic reacquisition, and neutral local touch state on interruption/page exit are mandatory. The PC host enforces live authorization, a separate local per-phone opt-in, exactly one FFXIV process, matching identity/epoch, an active unlocked Windows desktop and independent release watchdogs.

**Open XIVLauncher** is a separate fixed action available while the game is closed. Select the installed XIVLauncher.exe once in the PC GUI and allow the selected phone recovery. The phone cannot provide a path or arguments. **Restore game window** targets the selected saved process with lifetime/window ownership checks. Both require a control grant and live authenticated session; they do not require an active gamepad lease. Windows must remain awake and unlocked; the monitor can be off.

The new PC host also permits minimized/background in-game control. Enable **Keep gamepad enabled when client is inactive** in FFXIV's Gamepad Settings. This does not authorize unidentified lobby control.

This is not yet end-to-end login recovery: launcher/lobby viewing, manual authentication/MFA interaction, character-selection controls and confirmed logout remain unimplemented. Sentinel does not store or submit login credentials. XIVLauncher retains its own configured login behavior. Stable preview signing is still outstanding: if Android rejects an in-place preview APK update, uninstall only **Sentinel Remote Preview**, install this APK and create a new pairing invitation. The original status/rescue app can remain installed.
