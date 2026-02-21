return {
  version = 0;
  enabled = true;

  -- Base Transient Fear costs
  Cost_RegularBoon = 3;
  Cost_EnhancedBoon = 6;
  Cost_Hammer = 10;

  -- Greed multiplier
  EnableGreed = true;
  GreedPenalty_PerUse = 1;

  -- Safety limits
  MaxTransientFear = 25;

  -- Control name for the door-adjacent provocation hotkey.
  -- This is looked up in the game's input system; the exact valid name needs
  -- in-game verification. Try "Shout", "Rush", or "Interact" if the default fails.
  ProvokeHotkey = "Shout";
}
