# Provoking the Fates

A Hades II mod that lets you upgrade minor reward doors into powerful Boons and Daedalus Hammers — at the cost of temporary Oath of the Unseen difficulty spikes.

## How It Works

When approaching a door offering a minor reward (Bones, Ash, Nectar), a secondary prompt appears:

**[Cast] — Provoke the Fates**

Pressing it opens a 3-card selection menu:

| Option | Result | First-Pick Fear Cost |
|--------|--------|----------------------|
| Olympian Favor | Standard God Boon | +1 |
| Exalted Favor | Enhanced rarity Boon (Rare/Epic/Heroic/Duo) | +2 |
| Artificer's Design | Daedalus Hammer (bypasses run limit) | +3 |

## Transient Fear

The cost you pay is **Transient Fear** — random Oath of the Unseen vows injected into the upcoming combat encounter. They vanish once the fear's duration (in combat encounters) runs out.

- **Linear greed**: Fear cost = `multiplier × n`, where n is the 1-indexed slot of this provocation in the run. Hammer series: 3, 6, 9, 12…; Enhanced series: 2, 4, 6, 8…; Regular series: 1, 2, 3, 4…
- **Capped pool**: If a provocation's cost would exceed the remaining vow-pool capacity, that option is hidden from the menu. When every option is over-capacity, a rejection dialog appears instead of charging Fear that cannot land.

## Configuration

All values are configurable via r2modman's config editor:

- `Cost_RegularBoon` — Optional flat Fear offset added on top of the Regular Boon greed ramp (default: 0)
- `Cost_EnhancedBoon` — Optional flat Fear offset added on top of the Enhanced Boon greed ramp (default: 0)
- `Cost_Hammer` — Optional flat Fear offset added on top of the Hammer greed ramp (default: 0)
- `EnableGreed` — Toggle the per-provocation greed ramp (default: true)
- `GreedMultiplier_RegularBoon` — Greed step added each slot when picking Regular Boon (default: 1)
- `GreedMultiplier_EnhancedBoon` — Greed step added each slot when picking Enhanced Boon (default: 2)
- `GreedMultiplier_Hammer` — Greed step added each slot when picking Daedalus Hammer (default: 3)
- `GreedExtendsDuration` — Each provocation after the first lasts 1 extra encounter per prior provocation (default: true)
- `Duration_RegularBoon` / `Duration_EnhancedBoon` / `Duration_Hammer` — Base Fear-stack duration per choice type, in combat encounters (defaults: 1 / 2 / 3)
- `ThemedSplitThreshold` — At or below this Fear cost a provocation concentrates on a single vow; above it the ranks split across two (default: 6)
- `ProvokeHoldSeconds` — Hold-duration on Interact to open the provocation menu (default: 0.5)
- `LogLevel` — Playtest log verbosity: TRACE / DEBUG / INFO / WARN / ERROR (default: INFO)

## Installation

1. Install [r2modman](https://thunderstore.io/package/ebkr/r2modmanPlus/) and select **Hades II** from the game list.
2. Search for **ProvokingTheFates** in the Online tab and install — r2modman pulls the dependencies automatically.
3. Launch Hades II through r2modman.
4. (Optional) Open the mod's Config in r2modman to tune greed ramps, durations, or hold-time.

## Dependencies

- [Hell2Modding](https://thunderstore.io/c/hades-ii/p/Hell2Modding/Hell2Modding/)
- [ModUtil](https://thunderstore.io/c/hades-ii/p/SGG_Modding/ModUtil/)
- [SJSON](https://thunderstore.io/c/hades-ii/p/SGG_Modding/SJSON/)
- [Chalk](https://thunderstore.io/c/hades-ii/p/SGG_Modding/Chalk/)
- [ReLoad](https://thunderstore.io/c/hades-ii/p/SGG_Modding/ReLoad/)
- [ENVY](https://thunderstore.io/c/hades-ii/p/LuaENVY/ENVY/)

## Feedback

Bug reports and feature requests are welcome at the [GitHub issues tracker](https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/issues).
