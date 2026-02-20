# Provoking the Fates

A Hades II mod that lets you upgrade minor reward doors into powerful Boons and Daedalus Hammers — at the cost of temporary Oath of the Unseen difficulty spikes.

## How It Works

When approaching a door offering a minor reward (Bones, Ash, Psyche), a secondary prompt appears:

**[Cast] — Provoke the Fates**

Pressing it opens a 3-card selection menu:

| Option | Result | Base Fear Cost |
|--------|--------|----------------|
| Olympian Favor | Standard God Boon | +3 |
| Exalted Favor | Enhanced rarity Boon (Rare/Epic/Heroic/Duo) | +6 |
| Artificer's Design | Daedalus Hammer (bypasses run limit) | +10 |

## Transient Fear

The cost you pay is **Transient Fear** — random Oath of the Unseen vows injected into the upcoming encounter only. They vanish when the room is cleared.

- **Greed Multiplier**: Each use in a run increases all costs by +1
- **Spillover**: If a randomly selected vow is already maxed, the fear spills into vows you left at Rank 0 — targeting your build's blind spots

## Configuration

All values are configurable via r2modman's config editor:

- `Cost_RegularBoon` — Base fear cost for a standard Boon (default: 3)
- `Cost_EnhancedBoon` — Base fear cost for an enhanced Boon (default: 6)
- `Cost_Hammer` — Base fear cost for a Daedalus Hammer (default: 10)
- `EnableGreed` — Toggle the greed multiplier (default: true)
- `GreedPenalty_PerUse` — Extra fear per previous provocation (default: 1)
- `MaxTransientFear` — Cap on total Transient Fear in one room (default: 25)

## Dependencies

- [Hell2Modding](https://thunderstore.io/c/hades-ii/p/Hell2Modding/Hell2Modding/)
- [ModUtil](https://thunderstore.io/c/hades-ii/p/SGG_Modding/ModUtil/)
- [SJSON](https://thunderstore.io/c/hades-ii/p/SGG_Modding/SJSON/)
- [Chalk](https://thunderstore.io/c/hades-ii/p/SGG_Modding/Chalk/)
- [ReLoad](https://thunderstore.io/c/hades-ii/p/SGG_Modding/ReLoad/)
- [ENVY](https://thunderstore.io/c/hades-ii/p/LuaENVY/ENVY/)
