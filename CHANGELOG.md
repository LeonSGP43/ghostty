# Changelog

All notable changes to GhoDex will be documented in this file.

The format is based on Keep a Changelog, with AI-oriented notes for future maintainers.

## [Unreleased]

### Added

- Connection center, learning settings, and task queue settings now persist in
  `config.ghodex` and round-trip with the macOS control panel.

What changed
- Moved AI terminal manager settings from a sidecar JSON source of truth into
  managed `ghodex-*` entries inside the main `config.ghodex` file.
- Added config reload back-propagation so store and panel state refresh when
  Ghostty reloads the main config.
- Added managed block persistence that preserves unrelated user config lines.
- Added regression coverage for managed-block load, save, reload, and inbox
  directory behavior.

Why
- The project now requires command-style config and control-panel settings to
  be two-way synced instead of diverging into separate storage systems.
- Reloading the main config must remain authoritative so panel state always
  reflects the real app configuration.

Impact
- Users can edit `config.ghodex` directly and see matching values return to the
  control panel after reload.
- Control-panel changes now update the same app-owned config file.
- Existing legacy `ai-terminal-manager.json` data can migrate into the main
  config path instead of being stranded as a hidden source of truth.

Verification
- `zig build`
- `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AITerminalManagerTests/storeLoadsConfigurationFromManagedGhoDexConfigBlock -only-testing:GhosttyTests/AITerminalManagerTests/storePersistsConfigurationIntoManagedGhoDexConfigBlock -only-testing:GhosttyTests/AITerminalManagerTests/storeReloadsPersistedConfigurationFromGhoDexConfig -only-testing:GhosttyTests/AITerminalManagerTests/storeUsesConfigDirectoryForHeartbeatInbox -only-testing:GhosttyTests/AITerminalManagerTests/storeSavesLearningSettings test`

Files
- `include/ghostty.h`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`
- `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`
- `macos/Sources/Ghostty/Ghostty.App.swift`
- `macos/Sources/Ghostty/Ghostty.Config.swift`
- `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`
- `src/cli/edit_config.zig`
- `src/config/Config.zig`
- `src/config/file_load.zig`

## [0.1.0] - 2026-03-15

### Added

- Bootstrapped project versioning metadata for GhoDex.

What changed
- Added `CHANGELOG.md` and initialized project version tracking.

Why
- Future feature changes must carry their own change history and rationale.

Impact
- Subsequent feature commits can record user-visible behavior and reasoning in a stable place.

Verification
- Confirmed `CHANGELOG.md` exists with `Unreleased` and an initial release heading.

Files
- `CHANGELOG.md`
