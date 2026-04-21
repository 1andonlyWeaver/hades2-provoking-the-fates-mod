# Provoking the Fates

A Hades II mod that upgrades minor reward doors into Boons, Hammers, Hexes, Centaur Hearts, and more. The price is temporary Oath of the Unseen difficulty spikes.

## Unlocking the Mechanic

The provocation mechanic doesn't kick in the moment you install the mod. To enable it:

1. Defeat Chronos at least once. This unlocks the Oath of the Unseen in vanilla and makes the incantation visible in the Cauldron.
2. Visit Hecate's cauldron in the Crossroads and cast **Provoke the Fates** (costs 3 Marble + 2 Shaderot).

Until you do, doors behave exactly like vanilla.

Prefer to skip the ritual? Set `RequireIncantation = false` in r2modman's config editor and the mechanic activates from the first run.

## How It Works

When you approach a door offering a minor reward (Bones, Ash, Nectar), a secondary prompt appears:

**Hold Interact to Provoke the Fates**

A short tap uses the door normally. Hold past half a second and a selection menu opens with **three random options** drawn from the reward pool. Close and reopen the menu to reroll.

The pool holds eight reward types, grouped into three Fear tiers:

| Tier | Fear mult | Options | What it delivers |
|------|-----------|---------|------------------|
| 1 | ×1 | Gold | 200 drachmas |
| 1 | ×1 | Centaur Heart | +50 Max Health |
| 1 | ×1 | Magick | +60 Max Magick |
| 2 | ×2 | Pomegranate | Level up one existing boon |
| 2 | ×2 | Boon | Standard God Boon |
| 2 | ×2 | Hex | Selene Hex / Night Boon |
| 3 | ×3 | Enhanced Boon | Rarity-boosted God Boon (Rare+/Epic/Heroic/Duo) |
| 3 | ×3 | Daedalus Hammer | Hammer upgrade (bypasses the vanilla run limit) |

Options that require an unlock are hidden until you meet the vanilla prerequisite. Hex needs Selene unlocked; Pomegranate needs at least one upgradeable boon. Anything whose Fear cost exceeds your remaining vow room is hidden too — when *nothing* fits, the Fates turn you away.

The same prompt also appears on the Mourning Fields pickups (Bones, Ashes, Nectar) that stand in for doors in that biome. Fields pickups only offer Boon / Enhanced Boon / Hammer (the minor-resource rewards don't fit the cage flow).

## Transient Fear

The cost is **Transient Fear**: random Oath of the Unseen vows that stick around for the next few fights, then fade.

Each provocation costs more than the last — every pick, of any type, advances a shared greed counter. At the tier multipliers above, the first provocation in a run charges 1 / 2 / 3 Fear (Tier 1 / 2 / 3), the second charges 2 / 4 / 6, the third 3 / 6 / 9, and so on. You can steer between cheap and steep by mixing tiers.

## Configuration

All values are configurable via r2modman's config editor. Each reward type has four knobs — `Cost_<Type>`, `GreedMultiplier_<Type>`, `Duration_<Type>`, `Weight_<Type>` — for the eight types: `RegularBoon`, `EnhancedBoon`, `Hammer`, `Gold`, `CentaurHeart`, `Magick`, `Pom`, `SeleneBoon`.

- `Cost_<Type>`: flat Fear tacked on top of every provocation of that type before greed (default: 0 for all)
- `GreedMultiplier_<Type>`: how much more each provocation of that type costs than the previous one. Defaults match the tiers: 1 for Gold / CentaurHeart / Magick; 2 for RegularBoon / Pom / SeleneBoon; 3 for EnhancedBoon / Hammer.
- `Duration_<Type>`: how many combat encounters each type's Fear hangs around. Defaults: 1 for Tier 1, 2 for RegularBoon/Pom/SeleneBoon/EnhancedBoon, 3 for Hammer.
- `Weight_<Type>`: how likely this type is to appear in any given 3-option roll (default: 1 for all — equal weighting). Set one to 0 to exclude that type entirely.
- `EnableGreed`: when on, each provocation costs more than the last. Turn off to charge only the flat `Cost_<Type>` above (default: true)
- `GreedExtendsDuration`: when on, later provocations stick around longer — each one after the first adds an extra encounter (default: true)
- `ThemedSplitThreshold`: at or below this Fear cost, all ranks go onto one vow; above it they split across two (default: 6)
- `ProvokeHoldSeconds`: how long to hold Interact before the provocation menu opens (default: 0.5)
- `RequireIncantation`: when off, skip the cauldron unlock and activate the provocation mechanic from the first run (default: true)
- `LogLevel`: log verbosity — TRACE / DEBUG / INFO / WARN / ERROR (default: INFO)

## Installation

1. Install [r2modman](https://thunderstore.io/package/ebkr/r2modmanPlus/) and select **Hades II** from the game list.
2. Search for **ProvokingTheFates** in the Online tab and install. r2modman pulls the dependencies automatically.
3. Launch Hades II through r2modman.
4. (Optional) Open the mod's Config in r2modman to tune costs, durations, or hold-time.

## Dependencies

- [Hell2Modding](https://thunderstore.io/c/hades-ii/p/Hell2Modding/Hell2Modding/)
- [ModUtil](https://thunderstore.io/c/hades-ii/p/SGG_Modding/ModUtil/)
- [SJSON](https://thunderstore.io/c/hades-ii/p/SGG_Modding/SJSON/)
- [Chalk](https://thunderstore.io/c/hades-ii/p/SGG_Modding/Chalk/)
- [ReLoad](https://thunderstore.io/c/hades-ii/p/SGG_Modding/ReLoad/)
- [ENVY](https://thunderstore.io/c/hades-ii/p/LuaENVY/ENVY/)
- [IncantationsAPI](https://thunderstore.io/c/hades-ii/p/BlueRaja/IncantationsAPI/)

## Feedback

Bug reports and feature requests go on the [GitHub issues tracker](https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/issues).
