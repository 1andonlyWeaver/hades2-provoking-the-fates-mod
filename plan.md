# **Hades 2 Mod Design Document: Provoking the Fates**

## **1\. Overview & Philosophy**

**"Provoking the Fates"** is a back-end logic mod designed to enhance the player's power fantasy in *Hades 2* while strictly adhering to the philosophy of "earned power."

The mod allows players to bypass the game's intentional scarcity of Boons and Daedalus Hammers by forcefully upgrading minor reward doors. In exchange, the game retaliates by injecting temporary "Transient Fear" (Oath of the Unseen vow ranks) that persists across the upcoming combat rooms. Players can become unstoppably powerful, but only if they have the mechanical skill to survive the difficulty spikes they bring upon themselves.

## **2\. Core Mechanics: The Player Flow**

### **Step 1: The Trigger**

When Melinoë approaches a door offering a minor, meta-progression reward (e.g., Bones, Ash, Psyche), the vanilla `{!I} Proceed` prompt appears as normal. A second line reading `Hold {!I} to Provoke the Fates` is drawn directly beneath it.

* Short tap of Interact — vanilla Proceed behavior (enter the room unchanged).
* Hold Interact ≥ `ProvokeHoldSeconds` (default 0.5s) — opens the provocation menu instead.

### **Step 2: The Choice**

Holding Interact opens a custom screen that pauses the game and presents the three provocation options, each labeled with its current Fear cost and a live preview of the specific vow effects that will land if chosen:

* **Boon (Regular)** — Base Fear cost. Upgrades the door to a standard God Boon.
* **Enhanced Boon** — Higher cost. Upgrades to a Boon with a rarity-boosted roll table (Rare / Epic / Heroic / Legendary weighted toward the upper tiers).
* **Daedalus Hammer** — Highest cost. Upgrades to a Hammer, bypassing the vanilla run limit.

The preview line beneath each button shows what the Fear will resolve to — e.g. *"+12% foe damage, 2 perk(s) on elites"* — so the player commits with full information. Closing and reopening the screen rerolls the preview.

If every eligible vow is already at its native max rank, the screen is replaced by a minimal **"The Fates are Satisfied"** rejection dialog. No cost is charged; the player can continue normally.

### **Step 3: The Transformation**

Upon selection, the screen closes. The door's reward icon is swapped to the upgraded reward's art and tinted purple to mark it as provoked. The player is locked in (re-holding Interact reopens the screen with Revert and Keep options).

## **3\. The Economy of Fear**

### **Transient Fear**

Transient Fear adds ranks to a randomly-chosen subset of "Oath of the Unseen" combat vows. Ranks are applied on top of the player's baseline Oath when a provoked room begins and restored to baseline when each encounter in the room ends. The vow entries eligible for injection are:

* `EnemyDamageShrineUpgrade` (Vow of Pain)
* `EnemyHealthShrineUpgrade` (Vow of Grit)
* `EnemyShieldShrineUpgrade` (Vow of Wards)
* `EnemySpeedShrineUpgrade` (Vow of Frenzy)
* `EnemyCountShrineUpgrade` (Vow of Hordes)
* `NextBiomeEnemyShrineUpgrade` (Vow of Menace — spawns next-biome foes into the current room)
* `EnemyRespawnShrineUpgrade` (Vow of Return)
* `EnemyEliteShrineUpgrade` (Vow of Fangs)

### **Themed Vow Selection**

To keep Fear memorable, each provocation concentrates its ranks on 1–2 named vows rather than sprinkling +1s across everything:

* At or below `ThemedSplitThreshold` Fear (default 6): one vow absorbs the entire cost.
* Above the threshold: two distinct vows split the cost evenly (the extra rank goes to the second pick when the cost is odd).

### **Per-Vow Hard Cap**

Every eligible vow is capped at its native max rank. If a pick would push a vow over max, the overflow is redistributed to the other pick; anything left beyond both picks' caps is dropped. If *all* seven vows are already at max at provoke time, the provocation screen is replaced by the **"Fates Satisfied"** rejection dialog.

### **The Greed Multiplier (Per-Type, Quadratic)**

To prevent spam, the mod tracks how many times the player has provoked *each reward type* independently. Fear cost scales quadratically with the same-type count:

```
cost = base + penalty * n²
```

where `n` is the 1-indexed position of this provocation among same-type provocations. The series for Daedalus Hammer (base 9, penalty 1) runs 10 → 13 → 18 → 25 → 34 → 45 … Cross-type spam (Regular Boon sprinkled between Hammers) stays cheap; repeatedly provoking the same type ramps up fast.

### **Multi-Room Duration**

Each provocation's Fear persists across several combat rooms, not just the one you enter through the provoked door:

| Choice          | Base duration |
| --------------- | ------------- |
| Regular Boon    | 1 room        |
| Enhanced Boon   | 2 rooms       |
| Daedalus Hammer | 3 rooms       |

When `GreedExtendsDuration = true`, the duration grows by +1 room per prior same-type provocation. The second Hammer lasts 4 rooms; the third lasts 5; and so on.

Non-combat rooms (shops, NPC encounters) do not consume a duration tick — Fear pauses until the next fight. Active stacks merge: if two stacks are overlapping, their ranks sum per vow (still clamped at each vow's cap).

## **4\. Visual & UI**

The mod reuses existing *Hades 2* assets exclusively. No custom art or VFX.

* **Provocation prompt** — a second text line reading `Hold {!I} to Provoke the Fates` is drawn just beneath the vanilla `{!I} Proceed` prompt when the player is in range of a provokable MetaProgress door.
* **Provocation screen** — a `MythmakerBoxDefault` frame with buttons for each choice; each button shows its cost and a live preview of the vow effects that will apply.
* **Door tint** — a provoked door's reward preview icons are tinted purple (via `SetColor`) to mark the door as cursed. Reverting restores neutral white.
* **Room-entry banner** — when a provoked room begins, a centered top-screen banner drops down reading `The Fates are Provoked (+N Fear)` followed by a sorted list of vow-effect descriptions. Fades after ~3 seconds.
* **Persistent HUD cluster** — while Fear is active, a small cluster of shrine-upgrade icons (one per active vow, reusing `MetaUpgradeData[vow].Icon`) is pinned near the top-right so the player can see at a glance which vows are cursing the current room.
* **Fates satisfied dialog** — a minimal `MythmakerBoxDefault` pop-up with "The Fates are Satisfied / They hear no more. / Dismiss." Shown in place of the choice menu when every vow is already at its native max.

## **5\. Back-End Logic & Overrides**

The mod hooks eight vanilla functions via `modutil.mod.Path.Wrap`:

1. **`StartNewRun`** — resets the mod's per-run state.
2. **`KillHero`** — safety cleanup on death; restores vow ranks and clears run state.
3. **`LeaveRoom`** — long-press gate (hold vs tap detection via `NotifyOnControlReleased` with timeout); pushes a Fear stack when a provoked door is used; safety-restores vow ranks; restores `RewardStoreName` so `CalcMetaProgressRatio` counts the provoked room correctly.
4. **`StartRoom`** — applies any active Fear stacks to `GameState.ShrineUpgrades` for the new room; creates the entry banner and HUD cluster.
5. **`EndEncounterEffects`** — on the last encounter of the current room, restores baseline vow ranks and decays each active stack's `RoomsRemaining` by 1.
6. **`DoUnlockRoomExits`** — after exit doors are ready, temporarily restores `RewardStoreName` so `ChooseNextRewardStore` computes the correct ratio; activates the proximity-driven hint lifecycle.
7. **`ShowUseButton`** — spawns the Provoke hint when the player enters interact range of a provokable door.
8. **`HideUseButton`** — clears the nearest-door reference when the player leaves range.

Key implementation notes:

* **Long-press**: inside the `LeaveRoom` wrap, a provokable door triggers `NotifyOnControlReleased({ Names = {"Interact"}, Timeout = ProvokeHoldSeconds })` followed by `waitUntil(...)`. If `_eventTimeoutRecord[name]` is true (held past threshold), the provocation screen opens and the base `LeaveRoom` is skipped. Otherwise the short-tap falls through to base Proceed.
* **Stack bookkeeping**: `RestoreVowsOnly` (ranks-only) is called as a safety net from `LeaveRoom` and `KillHero`; `RestoreVowsAndDecayStacks` (ranks + decrement) is called only from `EndEncounterEffects` on the last encounter, so a stack is never double-decremented.
* **Hammer cap bypass**: the vanilla single-run Hammer cap is bypassed by setting `RewardStoreName = "RunProgress"` at provocation time; the original store name is stashed in `room._OriginalRewardStoreName` and restored around `DoUnlockRoomExits` / `LeaveRoom` so MetaProgress ratio math is unaffected.

## **6\. Player Configuration (config.lua)**

```lua
{
  -- Base fear costs (before the quadratic greed bonus)
  Cost_RegularBoon  = 2;
  Cost_EnhancedBoon = 5;
  Cost_Hammer       = 9;

  -- Greed: cost = base + penalty * n², tracked per reward type
  EnableGreed          = true;
  GreedPenalty_PerUse  = 1;

  -- Themed vow selection: 1 vow at/below this Fear cost, 2 vows above
  ThemedSplitThreshold = 6;

  -- Multi-room Fear duration (combat rooms only; shops/NPCs don't tick)
  Duration_RegularBoon  = 1;
  Duration_EnhancedBoon = 2;
  Duration_Hammer       = 3;
  GreedExtendsDuration  = true;  -- +1 room per prior same-type provocation

  -- Long-press threshold on Interact to open the provocation screen
  ProvokeHoldSeconds = 0.5;
}
```

## **7\. Open Questions & Out of Scope**

* **Linear magnitude decay within a stack's duration.** Current model keeps each stack at full strength until it drops off entirely. A linear fade (room 1 full, room 2 two-thirds, room 3 one-third) would feel more thematic but requires fractional-rank accounting; deferred.
* **Boss-room behavior while a stack is active.** Boss rooms are excluded from provocation but can be traversed under Fear. Current behavior: the stack applies and a single "room" of duration is spent if the encounter registers. Playtest and decide whether to pause stacks during bosses.
* **Hold-threshold visual feedback.** A ring charging around the hint text would aid discoverability. Needs a reusable base-game charging animation; deferred.
