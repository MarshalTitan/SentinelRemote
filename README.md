# Sentinel Remote Android gamepad preview

Private Android status/rescue companion with an experimental gamepad screen. This branch requires the matched Sentinel Remote Windows 0.2.0 candidate.

See the [PC setup and supervised field checklist](https://github.com/MarshalTitan/SentinelRelay/blob/feature/sentinel-remote-gamepad-integration/remote/docs/GAMEPAD_PREVIEW.md).

The preview installs as **Sentinel Remote Preview** alongside the existing app and requires its own local pairing invitation. No existing Android pairing is deleted. Keep the original app installed. CI debug signing is not stable across rebuilds; production update signing remains outstanding.

Input replies only to fresh server challenges. Complete state, one active socket, no automatic reacquisition, and neutral local touch state on interruption/page exit are mandatory. The PC host enforces live authorization, a separate local per-phone opt-in, exactly one FFXIV process, matching identity/epoch, foreground FFXIV and independent release watchdogs.

Launcher opening, game logout and live game view are later recovery/view work; this candidate does not implement them.
