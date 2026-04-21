# Provoking the Fates

A Hades II mod that upgrades minor reward doors into Boons and Daedalus Hammers. The price is temporary Oath of the Unseen difficulty spikes.

## Unlocking the Mechanic

The provocation mechanic doesn't kick in the moment you install the mod. To enable it:

1. Defeat Chronos at least once. This unlocks the Oath of the Unseen in vanilla and makes the incantation visible in the Cauldron.
2. Visit Hecate's cauldron in the Crossroads and cast **Provoke the Fates** (costs 3 Marble + 2 Shaderot).

Until you do, doors behave exactly like vanilla.

Prefer to skip the ritual? Set `RequireIncantation = false` in r2modman's config editor and the mechanic activates from the first run.

## How It Works

When you approach a door offering a minor reward (Bones, Ash, Nectar), a secondary prompt appears:

**Hold Interact to Provoke the Fates**

A short tap uses the door normally. Hold past half a second and a 3-card selection menu opens:

| Option | Result | First-Pick Fear Cost |
|--------|--------|----------------------|
| Olympian Favor | Standard God Boon | +1 |
| Exalted Favor | Enhanced rarity Boon (Rare/Epic/Heroic/Duo) | +2 |
| Artificer's Design | Daedalus Hammer (bypasses run limit) | +3 |

The same prompt also appears on the Mourning Fields pickups (Bones, Ashes, Nectar) that stand in for doors in that biome.

## Transient Fear

The cost is **Transient Fear**: random Oath of the Unseen vows that stick around for the next few fights, then fade.

Each provocation costs more than the last. Regular Boons charge 1, 2, 3, 4… as you keep going; Enhanced Boons 2, 4, 6, 8…; Hammers 3, 6, 9, 12…

If a provocation's cost won't fit what the vows can hold, that option is hidden from the menu. If nothing fits, the Fates turn you away.

## Configuration

All values are configurable via r2modman's config editor:

- `Cost_RegularBoon` / `Cost_EnhancedBoon` / `Cost_Hammer`: extra Fear tacked on top of every provocation of that type (defaults: 0 / 0 / 0)
- `EnableGreed`: when on, each provocation costs more than the last. Turn off to charge only the flat Cost above (default: true)
- `GreedMultiplier_RegularBoon` / `GreedMultiplier_EnhancedBoon` / `GreedMultiplier_Hammer`: how much more each provocation of that type costs than the previous one (defaults: 1 / 2 / 3)
- `GreedExtendsDuration`: when on, later provocations stick around longer — each one after the first adds an extra encounter (default: true)
- `Duration_RegularBoon` / `Duration_EnhancedBoon` / `Duration_Hammer`: how many combat encounters each type's Fear hangs around (defaults: 1 / 2 / 3)
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
