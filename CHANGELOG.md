# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Five new reward types in the provocation menu: **Gold** (200 drachmas), **Centaur Heart** (+50 Max Health), **Magick** (+60 Max Magick), **Pomegranate** (level up an existing boon), and **Hex** (Selene Night Boon). Pomegranate hides when you have no upgradeable boons; Hex hides until Selene is unlocked — matching the vanilla gates.
- New tier-2 reward type in the provocation menu: **Boon of Hermes** (greed ×2, 2-encounter Fear duration). Gated behind the vanilla `HermesFirstPickUp` unlock — the option appears once you've picked up a Hermes boon at least once in a prior run, matching how the Selene Hex option is gated on `SeleneFirstPickUp`. Per-type `Cost_HermesBoon`, `GreedMultiplier_HermesBoon`, `Duration_HermesBoon`, and `Weight_HermesBoon` knobs added.
- Menu now draws **three random options** from the pool of eight each time it opens, weighted by per-type `Weight_<Type>` config knobs. Closing and reopening the menu rerolls the selection.
- Per-type cost, greed, duration, and weight knobs for the new types (`Cost_Gold`, `GreedMultiplier_CentaurHeart`, `Duration_Magick`, `Weight_Pom`, `Cost_SeleneBoon`, and so on).

### Changed

- **Fear cost rebalance.** Regular Boon's greed multiplier moves 1 → 2 (series now 2, 4, 6, 8… instead of 1, 2, 3, 4…) and Enhanced Boon 2 → 3 (3, 6, 9, 12… instead of 2, 4, 6, 8…). Hammer multiplier is unchanged at 3. The change groups every reward into one of three clean Fear tiers (×1 / ×2 / ×3) alongside the new types. Existing `.cfg` files keep their stored values unless you reset them.

### Initial release

- Gated behind a new Cauldron incantation, **Provoke the Fates**, unlocked after the player has defeated Chronos (matching when the Oath of the Unseen itself becomes available in vanilla). Skippable via the `RequireIncantation` config option.
- Hold-Interact on any minor meta-reward door (Bones/Ash/Nectar) opens a provocation menu that upgrades the door to a richer reward.
- Same provoke flow works on Mourning Fields reward cages (Bones, Ashes, Nectar) — committing a choice auto-starts the cage combat.
- Transient Fear system injects random Oath of the Unseen vow ranks into upcoming combat encounters, decaying over a configurable duration.
- Over-capacity filter hides options whose Fear cost won't fit the remaining vow pool; a full-block rejection dialog fires when nothing fits.
- HUD banner on encounter start ("The Fates have been provoked") plus an "N encounters left" duration label.
- r2modman-editable config: greed multipliers, durations, weights, hold-seconds, themed-split threshold, log level.
