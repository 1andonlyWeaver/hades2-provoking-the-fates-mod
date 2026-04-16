return {
  version = 0;
  enabled = true;

  -- Base Transient Fear costs (before greed). The first provocation of a given
  -- type adds GreedPenalty_PerUse * 1² = GreedPenalty_PerUse on top of the base,
  -- so set these 1 below the desired first-provocation total (e.g. 2 + 1 = 3 fear
  -- on the first Regular Boon).
  Cost_RegularBoon = 2;
  Cost_EnhancedBoon = 5;
  Cost_Hammer = 9;

  -- Greed multiplier. Fear cost = base + GreedPenalty_PerUse * n², where n is the
  -- 1-indexed count of same-type provocations (Regular Boon / Enhanced Boon /
  -- Hammer tracked independently). With the default of 1, the same-type series
  -- is 1, 4, 9, 16, 25... added fear. Cross-type spam stays cheap; same-type
  -- spam ramps to meaningful costs.
  EnableGreed = true;
  GreedPenalty_PerUse = 1;

  -- Fear point threshold for "themed" vow selection. At or below this cost,
  -- a provocation concentrates all ranks on a single randomly chosen vow. Above
  -- it, ranks are split evenly across two distinct vows. Raise to make every
  -- provocation feel like a single big curse; lower to spread Fear sooner.
  ThemedSplitThreshold = 6;

  -- Duration (in combat rooms) that each provocation's Fear remains active
  -- before it decays off entirely. Non-combat rooms (shops, NPCs) don't consume
  -- a duration tick — the Fear pauses until the next fight.
  Duration_RegularBoon  = 1;
  Duration_EnhancedBoon = 2;
  Duration_Hammer       = 3;

  -- When true, each additional same-type provocation extends that type's
  -- duration by 1 room. The 1st Hammer lasts 3 rooms; the 2nd lasts 4; the 3rd
  -- lasts 5; and so on. Greedier runs carry heavier and longer retaliation.
  GreedExtendsDuration = true;

  -- Long-press duration (seconds) on the Interact button to trigger the
  -- provocation screen instead of entering the room. Short taps pass through
  -- to the vanilla door behavior unchanged. 0.4–0.6 feels natural; lower
  -- values risk accidental triggers when the player mashes Interact.
  ProvokeHoldSeconds = 0.5;
}
