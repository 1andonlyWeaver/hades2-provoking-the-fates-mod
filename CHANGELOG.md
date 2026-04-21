# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Gated behind a new Cauldron incantation, **Provoke the Fates**, unlocked after the player has defeated Chronos (matching when the Oath of the Unseen itself becomes available in vanilla). Skippable via the `RequireIncantation` config option.
- Hold-Interact on any minor meta-reward door (Bones/Ash/Nectar) opens a 3-option provocation menu: upgrade to a standard Boon, an Enhanced (Rare+) Boon, or a Daedalus Hammer that bypasses the per-run limit.
- Same provoke flow works on Mourning Fields reward cages (Bones, Ashes, Nectar) — committing a choice auto-starts the cage combat.
- Transient Fear system injects random Oath of the Unseen vow ranks into upcoming combat encounters, decaying over a configurable duration.
- Per-type linear greed ramp (Regular 1/2/3…, Enhanced 2/4/6…, Hammer 3/6/9…) with optional flat cost offsets.
- Over-capacity filter hides options whose Fear cost won't fit the remaining vow pool; a full-block rejection dialog fires when nothing fits.
- HUD banner on encounter start ("The Fates have been provoked") plus an "N encounters left" duration label.
- r2modman-editable config: greed multipliers, durations, hold-seconds, themed-split threshold, log level.
