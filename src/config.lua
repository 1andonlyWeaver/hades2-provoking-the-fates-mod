return {
  version = 0;
  enabled = true;

  -- Base Transient Fear costs (before greed). First-pick totals are
  -- base + the type's GreedMultiplier_* value (see below). With the defaults
  -- below, a first-picked Regular Boon costs 1 + 1 = 2 Fear; first-picked
  -- Enhanced Boon costs 2 + 2 = 4; first-picked Hammer costs 3 + 3 = 6.
  Cost_RegularBoon = 1;
  Cost_EnhancedBoon = 2;
  Cost_Hammer = 3;

  -- Per-choice-type linear greed. Fear cost = base + ceil(n * multiplier),
  -- where n is the 1-indexed position of this provocation in the run (all
  -- three choices share one counter, so cross-type spam ramps at each type's
  -- own rate). Each multiplier is the greed step added per provocation slot:
  --   RegularBoon  1 → series +1, +2, +3, +4, +5, +6, ...
  --   EnhancedBoon 2 → series +2, +4, +6, +8, +10, +12, ...
  --   Hammer       3 → series +3, +6, +9, +12, +15, +18, ...
  -- Lower to flatten a type's ramp; raise to make it bite harder sooner.
  -- EnableGreed = false short-circuits greed to 0 for every type.
  EnableGreed = true;
  GreedMultiplier_RegularBoon  = 1;
  GreedMultiplier_EnhancedBoon = 2;
  GreedMultiplier_Hammer       = 3;

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
