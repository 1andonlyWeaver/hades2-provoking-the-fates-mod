return {
  version = 0;
  enabled = true;

  -- Base Transient Fear costs (before greed). The very first provocation of a
  -- run adds GreedPenalty_PerUse * 1² = GreedPenalty_PerUse on top of the base,
  -- so set these 1 below the desired first-provocation total (e.g. 2 + 1 = 3
  -- fear on a first-picked Regular Boon).
  Cost_RegularBoon = 2;
  Cost_EnhancedBoon = 5;
  Cost_Hammer = 9;

  -- Greed multiplier. Fear cost = base + ceil(n² * GreedPenalty_PerUse),
  -- where n is the 1-indexed position of this provocation in the run (all
  -- three choices share one counter, so cross-type spam ramps just as fast
  -- as same-type). With the default 0.5, the greed series is +1, +2, +5,
  -- +8, +13, +18, +25... on top of the base cost — a bit gentler than a
  -- pure square so Fear doesn't outgrow the eligible-vow pool's capacity
  -- within the first few provocations.
  EnableGreed = true;
  GreedPenalty_PerUse = 0.5;

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

  -- When true, each provocation past the first extends its own stack's
  -- duration by 1 room per prior provocation (of any type). The 1st ever
  -- provocation lasts its base duration; the 2nd lasts base+1; the 3rd
  -- lasts base+2; and so on. Greedier runs carry heavier and longer
  -- retaliation, regardless of which options the player picks.
  GreedExtendsDuration = true;

  -- Long-press duration (seconds) on the Interact button to trigger the
  -- provocation screen instead of entering the room. Short taps pass through
  -- to the vanilla door behavior unchanged. 0.4–0.6 feels natural; lower
  -- values risk accidental triggers when the player mashes Interact.
  ProvokeHoldSeconds = 0.5;

  -- Playtest logging verbosity: TRACE | DEBUG | INFO | WARN | ERROR.
  -- INFO is the quiet default for normal play. Raise to DEBUG/TRACE to watch
  -- door proximity, hold-gate outcomes, and per-stack decay in detail.
  LogLevel = "INFO";
}
