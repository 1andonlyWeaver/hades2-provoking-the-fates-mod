return {
  version = 0;
  enabled = true;

  -- Base Transient Fear costs (before greed). With greed enabled, the first provocation
  -- adds GreedPenalty_PerUse * 2^0 = GreedPenalty_PerUse, so set these 1 below the
  -- desired first-provocation total (e.g. 2 + 1 = 3 fear on the first use).
  Cost_RegularBoon = 2;
  Cost_EnhancedBoon = 5;
  Cost_Hammer = 9;

  -- Greed multiplier. The greed bonus doubles each provocation: 2^count * GreedPenalty_PerUse.
  -- With the default of 1, the series is 1, 2, 4, 8, 16... added fear per provocation.
  EnableGreed = true;
  GreedPenalty_PerUse = 1;

  -- Safety limits
  MaxTransientFear = 19;

  -- Control name for the door-adjacent provocation hotkey.
  -- This is looked up in the game's input system; the exact valid name needs
  -- in-game verification. Try "Shout", "Rush", or "Interact" if the default fails.
  ProvokeHotkey = "Shout";
}
