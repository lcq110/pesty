# Changelog

All notable changes to Pesty are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Text, rich-text, and link cards can be edited from the context menu or with
  `Command+E`; saving creates a new history card and leaves the original intact.
- `Return` pastes rich text with formatting, while `Shift+Return` pastes its
  plain-text representation; other clip types keep their existing behavior.
- A local-only release driver builds, signs, validates, notarizes, and optionally
  publishes the CloudKit-enabled DMG from a clean `codex/ios-companion` checkout.
- An ignored local configuration template keeps signing identity and credential
  paths out of the repository.

### Changed
- GitHub Actions now has read-only repository access and only builds and tests
  unsigned development artifacts. Developer ID and CloudKit signing are blocked
  explicitly in GitHub Actions.
- CloudKit Developer ID profiles, certificate private keys, and notarization keys
  are used only on the local release Mac.

### Fixed
- Clipboard cards now select immediately, load cached image thumbnails off the
  main actor, and reserve animated centering for keyboard navigation.
- Direct paste now waits for Shift to be released before sending `Command+V`,
  so `Shift+Return` reaches the previously active app instead of stopping at copy.
- Release builds with CloudKit now require a matching Developer ID provisioning
  profile, extract their signing entitlements from that profile, and verify the
  final application and team identifiers before publication.
- Local publication refuses dirty or unpushed source trees and never overwrites
  an existing release tag.

## [1.2.0] - 2026-08-07

> Retracted for CloudKit testing: the downloadable artifact was ad-hoc signed
> and did not contain a Developer ID provisioning profile.

### Added
- iOS companion app, custom keyboard, share extension, and CloudKit-backed
  snapshot synchronization from the `codex/ios-companion` branch.

### Fixed
- The macOS global shortcut now opens Pesty on the currently active Space
  without switching back to the Space where Pesty was previously shown.
- Shortcut toggling no longer treats a panel visible only on another Space as
  visible on the current Space.

## [1.1.0] - 2026-06-26

Visual overhaul to match Paste, plus iCloud sync.

### Added
- iCloud Drive sync (opt-in) for history and pinboards across your Macs.
- Live Accessibility permission status in Settings, with a Restart button.

### Changed
- Redesigned cards: per-source-app colored header band, app-icon tile, type
  label, verbose relative time, and a footer with character count + quick-paste
  number — a faithful match to Paste.
- Spring animations for selection, hover, and scrolling; taller default strip.
- Top bar now has a sync toggle, search indicator, a "Clipboard" tab, and a
  "…" overflow menu.

### Fixed
- Search input and keyboard navigation reliability.
- Removed the unnecessary Apple Events entitlement.

[1.1.0]: https://github.com/momenbasel/pesty/releases/tag/v1.1.0
[1.2.0]: https://github.com/lcq110/pesty/releases/tag/v1.2.0

## [1.0.0] - 2026-06-26

Initial public release.

### Added
- Slide-up clipboard strip with a global hotkey (default `⌘⇧V`).
- Color-coded cards for text, rich text, links, images, files, and colors, each
  showing source app, editable title, copy time, preview, and character count.
- Pinboards: named, color-tagged collections of saved clips.
- Instant search across the full history.
- Keyboard navigation: arrows to move, `return` to paste, `⌘1`–`⌘9` quick-paste,
  `⌘⌫` to delete, `esc` to close.
- Direct paste into the previously active app via synthesized `⌘V`.
- Privacy: ignores concealed (password-manager) clips.
- Menu-bar item, preferences window, configurable hotkey, launch at login.
- Universal binary (Apple Silicon + Intel), signed with Developer ID and
  notarized by Apple.

[1.0.0]: https://github.com/momenbasel/pesty/releases/tag/v1.0.0
