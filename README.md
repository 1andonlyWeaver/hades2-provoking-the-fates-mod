# Provoking the Fates

Tired of getting ashes for an altar that's already fully upgraded?  Got more bones than all of Tartarus?  Tell the Fates that you don't want their scraps anymore!  Upgrade your room rewards with the Provoking the Fates mod!  A Hades II mod that upgrades minor reward doors into Boons, Hammers, Centaur Hearts, and more!  But be warned.  The Fates don't take kindly to rejection.

## Unlocking the Mechanic

The provocation mechanic doesn't kick in the moment you install the mod. To enable it:

1. Defeat Chronos at least once. This unlocks the Oath of the Unseen in vanilla and makes the incantation visible in the Cauldron.
2. Visit Hecate's cauldron in the Crossroads and cast **Provoke the Fates** (costs 3 Marble + 2 Shaderot).

Until you do, doors behave exactly like vanilla.

Prefer to skip the ritual? Set `RequireIncantation = false` in r2modman's config editor and the mechanic activates from the first run.

## How It Works

When you approach a door offering a minor reward (Bones, Ash, Nectar), a secondary prompt appears:

**Hold Interact to Provoke the Fates**

A short tap uses the door normally. Hold for `ProvokeHoldSeconds` seconds (default 0.5) and a selection menu opens with **three random options** drawn from the reward pool. Close and reopen the menu to reroll.

The pool holds nine reward types, grouped into three Fear tiers:

| Tier | Greed | Options | What it delivers |
|------|-------|---------|------------------|
| 1 | ×1 | Gold | 200 drachmas |
| 1 | ×1 | Centaur Heart | +50 Max Health |
| 1 | ×1 | Magick | +60 Max Magick |
| 2 | ×2 | Pomegranate | Level up one existing boon |
| 2 | ×2 | Boon | Standard God Boon |
| 2 | ×2 | Hex | Selene Hex / Night Boon |
| 2 | ×2 | Hermes Boon | Boon of Hermes |
| 3 | ×3 | Enhanced Boon | Rarity-boosted God Boon (Rare+/Epic/Heroic/Duo) |
| 3 | ×3 | Daedalus Hammer | Hammer upgrade (bypasses the vanilla run limit) |

Options that require an unlock are hidden until you meet the vanilla prerequisite. Hex needs Selene unlocked; Hermes Boon needs you to have picked up a Hermes boon at least once in a prior run; Pomegranate needs at least one upgradeable boon. Anything whose Fear cost exceeds your remaining vow room is hidden too. When *nothing* fits, the Fates turn you away.

The same prompt also appears on the Mourning Fields pickups (Bones, Ashes, Nectar) that stand in for doors in that biome. Fields pickups only offer Boon / Enhanced Boon / Hammer (the minor-resource rewards don't fit the cage flow).

## Transient Fear

Provocations are never free. Their price is **Transient Fear**: random Oath of the Unseen vow ranks that hang over the next few fights before fading.

Each provocation's Fear cost is `Cost_<Type> + ceil(n × GreedMultiplier_<Type>)`, where `n` is a shared counter that advances on every pick of any type. With default settings (`Cost_<Type> = 0`), the first three provocations at Tier 1 / 2 / 3 charge 1 / 2 / 3, then 2 / 4 / 6, then 3 / 6 / 9 Fear. Mixing tiers lets you steer between cheap and steep.

## Provoke vs The Enchantress

If you've equipped **The Enchantress** Arcana card (Circe), you already know the trick of swapping a door's reward: spend a Reroll token and the door's icon shuffles to a different reward of roughly the same tier. That's a *sideways* shuffle. A Bones door might become Ash, an Ash door might become Nectar.

Provoking the Fates pushes in a different direction. Instead of trading a Reroll token for a same-tier swap, you trade **Transient Fear** to *upgrade* the door. A minor reward door becomes a Boon, Hammer, Hex, Hermes Boon, or any of the nine richer rewards in the pool.

The two stack and don't interfere. Re-roll a door first and provoke the result, or provoke first and re-roll the result. Provoking never consumes a Reroll token; re-rolling never consumes Fear.

## Configuration

All values are configurable via r2modman's config editor. Each reward type has four knobs (`Cost_<Type>`, `GreedMultiplier_<Type>`, `Duration_<Type>`, `Weight_<Type>`) for the nine types: `RegularBoon`, `EnhancedBoon`, `Hammer`, `Gold`, `CentaurHeart`, `Magick`, `Pom`, `SeleneBoon`, `HermesBoon`.

- `Cost_<Type>`: flat Fear tacked on top of every provocation of that type before greed (default: 0 for all)
- `GreedMultiplier_<Type>`: how much more each provocation of that type costs than the previous one. Defaults match the tiers: 1 for Gold / CentaurHeart / Magick; 2 for RegularBoon / Pom / SeleneBoon; 3 for EnhancedBoon / Hammer.
- `Duration_<Type>`: how many combat encounters each type's Fear hangs around. Defaults: 1 for Tier 1, 2 for RegularBoon/Pom/SeleneBoon/EnhancedBoon, 3 for Hammer.
- `Weight_<Type>`: how likely this type is to appear in any given 3-option roll (default: 1 for all, equal weighting). Set one to 0 to exclude that type entirely.
- `EnableGreed`: when on, each provocation costs more than the last. Turn off to charge only the flat `Cost_<Type>` above (default: true)
- `GreedExtendsDuration`: when on, later provocations stick around longer. Each one after the first adds an extra encounter (default: true)
- `ThemedSplitThreshold`: at or below this Fear cost, all ranks go onto one vow; above it they split across two (default: 6)
- `ProvokeHoldSeconds`: how long to hold Interact before the provocation menu opens (default: 0.5)
- `RequireIncantation`: when off, skip the cauldron unlock and activate the provocation mechanic from the first run (default: true)
- `LogLevel`: log verbosity. TRACE / DEBUG / INFO / WARN / ERROR (default: INFO)

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

## Troubleshooting

**The "Hold to Provoke" prompt doesn't appear at doors.**
Cast the **Provoke the Fates** incantation at Hecate's cauldron first. It only becomes visible after defeating Chronos at least once. To skip the ritual entirely, set `RequireIncantation = false` in r2modman's config editor.

**The Hex option never shows up.**
Hex requires Selene's vanilla unlock. Pick up a Selene Hex at least once in a regular run; the option appears after that.

**The Hermes Boon option never shows up.**
Same as Hex but for Hermes. Pick up a Hermes boon at least once in a regular run, then Hermes provocations become available.

**Pomegranate options never show up.**
Pomegranate hides until you have at least one upgradeable boon in the current run.

**The provocation menu won't open even when I hold Interact.**
Either every eligible vow is already at its native max rank (the "Fates Satisfied" rejection screen will appear instead), or the hold duration is shorter than `ProvokeHoldSeconds`.

**Where is my config file?**
r2modman's config editor manages `1andonlyWeaver-ProvokingTheFates.cfg` directly. Changes apply on the next run start (or immediately for hot-reloadable values like `LogLevel`).

**I want more verbose logs for bug reports.**
Set `LogLevel = "DEBUG"` (or `"TRACE"`) in the config. Logs go to Hell2Modding's standard log output.

## Compatibility

**Nightmare Fear** ([ReadEmAndWeep-Nightmare_Fear](https://thunderstore.io/c/hades-ii/p/ReadEmAndWeep/Nightmare_Fear/)). When both mods are installed, Provoking the Fates extends its eligible-vow pool with Nightmare Fear's Vows of Naivety, Riposte, Arrogance, Secrets, Taxes, and Panic, and skips Selene-boon provocations while the player holds Nightmare Fear's Eclipse vow. No configuration is required; detection is automatic.

## Feedback

Bug reports and feature requests go on the [GitHub issues tracker](https://github.com/1andonlyWeaver/hades2-provoking-the-fates-mod/issues).
