return {
  version = 0;
  enabled = true;

  -- Optional flat Fear offsets added on top of the greed ramp. Default 0 so
  -- the full Fear cost is exactly GreedMultiplier_<Type> × n (see below).
  -- Raise these to make a given choice type always charge at least that much
  -- Fear before greed is added.
  Cost_RegularBoon  = 0;
  Cost_EnhancedBoon = 0;
  Cost_Hammer       = 0;
  Cost_Gold         = 0;
  Cost_CentaurHeart = 0;
  Cost_Magick       = 0;
  Cost_Pom          = 0;
  Cost_SeleneBoon   = 0;
  Cost_HermesBoon   = 0;

  -- Per-choice-type linear greed. Fear cost = Cost_<Type> + ceil(n * multiplier),
  -- where n is the 1-indexed position of this provocation in the run (every
  -- provocation shares one counter, so mixing types still advances n). With
  -- Cost_* = 0 the cost is simply multiplier × n. The tiered defaults group
  -- rewards into three power bands:
  --   Tier 1 (mult 1)  Gold, CentaurHeart, Magick                  1, 2, 3, 4, ...
  --   Tier 2 (mult 2)  Pom, RegularBoon, SeleneBoon, HermesBoon    2, 4, 6, 8, ...
  --   Tier 3 (mult 3)  EnhancedBoon, Hammer                        3, 6, 9, 12, ...
  -- Lower a multiplier to flatten that type's ramp; raise it to bite harder
  -- sooner. EnableGreed = false short-circuits greed to 0 for every type
  -- (only the flat Cost_<Type> offset is charged).
  EnableGreed                 = true;
  GreedMultiplier_RegularBoon  = 2;
  GreedMultiplier_EnhancedBoon = 3;
  GreedMultiplier_Hammer       = 3;
  GreedMultiplier_Gold         = 1;
  GreedMultiplier_CentaurHeart = 1;
  GreedMultiplier_Magick       = 1;
  GreedMultiplier_Pom          = 2;
  GreedMultiplier_SeleneBoon   = 2;
  GreedMultiplier_HermesBoon   = 2;

  -- Fear point threshold for "themed" vow selection. At or below this cost,
  -- a provocation concentrates all ranks on a single randomly chosen vow. Above
  -- it, ranks are split evenly across two distinct vows. Raise to make every
  -- provocation feel like a single big curse; lower to spread Fear sooner.
  ThemedSplitThreshold = 6;

  -- Duration (in combat encounters) that each provocation's Fear remains
  -- active before it decays off entirely. Non-combat encounters (shops,
  -- Devotion trials, NPC beats) don't consume a duration tick — the Fear
  -- pauses until the next fight.
  Duration_RegularBoon  = 2;
  Duration_EnhancedBoon = 2;
  Duration_Hammer       = 3;
  Duration_Gold         = 1;
  Duration_CentaurHeart = 1;
  Duration_Magick       = 1;
  Duration_Pom          = 2;
  Duration_SeleneBoon   = 2;
  Duration_HermesBoon   = 2;

  -- Per-type random-sample weighting. Each time the provocation menu opens,
  -- 3 options are drawn (without replacement) from the registered reward
  -- types, weighted by these numbers. All default to 1 — every option is
  -- equally likely. Raise one to make that type appear more often; set to
  -- 0 to exclude it entirely from the roll.
  Weight_RegularBoon  = 1;
  Weight_EnhancedBoon = 1;
  Weight_Hammer       = 1;
  Weight_Gold         = 1;
  Weight_CentaurHeart = 1;
  Weight_Magick       = 1;
  Weight_Pom          = 1;
  Weight_SeleneBoon   = 1;
  Weight_HermesBoon   = 1;

  -- When true, each provocation past the first extends its own stack's
  -- duration by 1 encounter per prior provocation (of any type). The 1st
  -- ever provocation lasts its base duration; the 2nd lasts base+1; the 3rd
  -- lasts base+2; and so on. Greedier runs carry heavier and longer
  -- retaliation, regardless of which options the player picks.
  GreedExtendsDuration = true;

  -- Long-press duration (seconds) on the Interact button to trigger the
  -- provocation screen instead of entering the room. Short taps pass through
  -- to the vanilla door behavior unchanged. 0.4–0.6 feels natural; lower
  -- values risk accidental triggers when the player mashes Interact.
  ProvokeHoldSeconds = 0.5;

  -- When true (default), you'll need to cast the "Provoke the Fates"
  -- incantation at Hecate's cauldron before the provoke prompt appears on
  -- doors. Flip to false to skip the ritual and have the mechanic active
  -- from the first run.
  RequireIncantation = true;

  -- Playtest logging verbosity: TRACE | DEBUG | INFO | WARN | ERROR.
  -- INFO is the quiet default for normal play. Raise to DEBUG/TRACE to watch
  -- door proximity, hold-gate outcomes, and per-stack decay in detail.
  LogLevel = "INFO";
}
