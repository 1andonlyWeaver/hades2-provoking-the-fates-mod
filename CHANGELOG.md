# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.3] - 2026-05-01

### Fixed

- Nightmare Fear's Panic, Naivety, Taxes, and Secrets vows now actually fire on transient Fear ranks. These four vows are checked at lifecycle points outside the StartEncounter→EndEncounterEffects window where Provoking the Fates writes to ShrineUpgrades, so they previously read baseline ranks and silently ignored a provocation's contribution.
- Successive Pom (Pomegranate) provocations in the same run no longer offer the same three upgrade choices. Vanilla bakes a Pom's upgrade options at loot-spawn time and `CreateBoonLootButtons` reuses that cache when the hero already owns every option (always true for Poms), so the seed advancement on pickup never reached the visible choices. The mod now flags provoked Pom exits and clears the cached options on the next `OpenUpgradeChoiceMenu`, letting vanilla re-roll under the freshly incremented `LootTypeHistory["StackUpgrade"]` seed.

## [1.0.2] - 2026-04-25

### Added

- **Nightmare Fear compatibility** — when [ReadEmAndWeep-Nightmare_Fear](https://thunderstore.io/c/hades-ii/p/ReadEmAndWeep/Nightmare_Fear/) is installed, the eligible-vow pool extends with Vows of Naivety, Riposte, Arrogance, Secrets, Taxes, and Panic. Selene-boon provocations are skipped while Nightmare Fear's Eclipse vow is active.

## [1.0.1] - 2026-04-25

### Added

- **Helm-wheel provocation in the Rift of Thessaly** — hold-Interact on a `ShipsSteeringWheel` spoke whose reward is Bones, Ashes, or Nectar (small or big variants) to open the Provoke the Fates menu. Picking a choice transforms the spoke and immediately starts the wheel encounter with the chosen Fear applied. The unified meta-resource whitelist also now covers the `Big` variants of Bones / Ashes wherever they appear.

### Changed

- Doors leading into Rift of Thessaly rooms (biome `O`) no longer prompt for provocation; the wheel inside the room is the provocation point.
- Trimmed the em dash from the package description for consistency.

## [1.0.0] - 2026-04-24

### Added

- Hold-Interact on minor reward doors (Bones / Ash / Nectar) to open a **Provoke the Fates** menu offering richer rewards — Boon, Enhanced Boon, Daedalus Hammer, Selene Hex, Boon of Hermes, Pomegranate, Gold, Centaur Heart, or Magick — at the cost of temporary Oath of the Unseen Fear.
- Same flow on Mourning Fields reward cages (Bones, Ashes, Nectar). Cages support Boon, Enhanced Boon, and Hammer only; committing a choice auto-starts the cage combat.
- **Transient Fear** — each provocation injects extra ranks into a randomly chosen subset of Oath of the Unseen vows that decay over the next few combat encounters. Non-combat encounters (shops, NPCs, Devotion trials) pause the decay.
- **Themed vow split** — each provocation concentrates its Fear on one vow at low cost, splitting onto two vows above the `ThemedSplitThreshold`. Over-cap overflow redistributes to other eligible vows.
- **Greed counter** — every provocation, of any type, costs more than the last. Cost formula is `Cost_<Type> + ceil(n × GreedMultiplier_<Type>)` with a shared counter `n`. Defaults map rewards to ×1 / ×2 / ×3 multipliers.
- **Cauldron unlock** — gated behind a new **Provoke the Fates** incantation (3 Marble + 2 Shaderot), unlocked once Chronos has been defeated. Bypassable via `RequireIncantation = false`.
- **Re-provoke and revert** — re-holding Interact on a provoked door reopens the menu with Keep / Revert options.
- **Over-capacity filtering** — options whose Fear cost exceeds remaining vow capacity are hidden. If no option fits, a "Fates Satisfied" rejection dialog replaces the menu and no Fear is charged.
- **HUD** — encounter-start "The Fates have been provoked" banner with a per-vow effect summary, plus a persistent top-right cluster showing active vows and remaining encounter count.
- **Per-type config knobs** for all nine reward types: `Cost_<Type>`, `GreedMultiplier_<Type>`, `Duration_<Type>`, `Weight_<Type>` (`RegularBoon`, `EnhancedBoon`, `Hammer`, `Gold`, `CentaurHeart`, `Magick`, `Pom`, `SeleneBoon`, `HermesBoon`). Set `Weight_<Type> = 0` to exclude a type from the menu entirely.
- **Global config knobs**: `EnableGreed`, `GreedExtendsDuration`, `ThemedSplitThreshold`, `ProvokeHoldSeconds`, `RequireIncantation`, `LogLevel` (TRACE / DEBUG / INFO / WARN / ERROR).

[unreleased]: https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/compare/1.0.3...HEAD
[1.0.3]: https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/compare/1.0.2...1.0.3
[1.0.2]: https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/compare/987b54d0b458a535e4d59bbe13a88fb59f19ab77...1.0.0
