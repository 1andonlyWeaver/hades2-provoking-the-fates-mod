---@meta _
-- globals we define are private to our plugin!
---@diagnostic disable: lowercase-global

-- this file will be reloaded if it changes during gameplay,
-- 	so only assign to values or define things here.

-- ============================================================================
-- Section 1: Module State & Constants
-- ============================================================================

ProvokeMod = ProvokeMod or {}

-- Incantation unlock gate. The provocation mechanic stays locked until the
-- player casts the "Provoke the Fates" incantation at Hecate's cauldron
-- (registered via RegisterIncantation at the bottom of this file). Until
-- then doors behave exactly like vanilla. Flip config.RequireIncantation =
-- false in r2modman to bypass the ritual.
ProvokeMod.IncantationId = "Weaver_ProvokeTheFates"

function ProvokeMod.IsUnlocked()
	if config and config.RequireIncantation == false then
		return true
	end
	return GameState ~= nil
		and GameState.WorldUpgradesAdded ~= nil
		and GameState.WorldUpgradesAdded[ProvokeMod.IncantationId] == true
end

-- Vows eligible for Transient Fear injection.
-- Only direct combat vows: enemy stat modifiers and spawn mechanics.
-- Excluded vows have no meaningful effect during a single combat room:
--   ShopPrices, MinibossCount, BiomeSpeed, HealingReduction,
--   BoonManaReserve, LimitGrasp, BanUnpickedBoons
ProvokeMod.EligibleVows = {
	"EnemyDamageShrineUpgrade",
	"EnemyHealthShrineUpgrade",
	"EnemyShieldShrineUpgrade",
	"EnemySpeedShrineUpgrade",
	"EnemyCountShrineUpgrade",
	"NextBiomeEnemyShrineUpgrade",
	"EnemyRespawnShrineUpgrade",
	"EnemyEliteShrineUpgrade",
}

-- ----------------------------------------------------------------------------
-- ChoiceTypes registry. Every per-choice-type branch in the mod reads from
-- here: cost / greed / duration config keys, UI styling, and the door / cage
-- transform functions. Adding a new reward type is "add an entry; touch
-- nothing else".
--
--   Transform( room, door )          mutates room + door to produce the
--                                    upgraded reward (ChosenRewardType,
--                                    RewardStoreName, ForceLootName, rarity
--                                    overrides).
--   TransformCage( currentRoom )     parallel for Fields cages: may mutate
--                                    currentRoom.BoonRaritiesOverride and
--                                    returns { RewardOverride, LootName } for
--                                    SpawnRoomReward to consume. nil for
--                                    cage-incompatible types (SupportsCage =
--                                    false).
--   Rarity                           keys into the vanilla
--                                    ScreenData.UpgradeChoice.
--                                    RarityBackingAnimations table that
--                                    buildChoiceRow uses to draw the slot.
-- ----------------------------------------------------------------------------
ProvokeMod.ChoiceTypes = {
	RegularBoon = {
		Title           = "Boon",
		UIColor         = { 1.0, 1.0,  1.0, 1.0 },
		Rarity          = "Rare",
		IconAnim        = "BlindBoxLoot",
		IconOverlayAnim = nil,

		CostKey         = "Cost_RegularBoon",
		CostDefault     = 0,
		GreedKey        = "GreedMultiplier_RegularBoon",
		GreedDefault    = 1,
		DurationKey     = "Duration_RegularBoon",
		DurationDefault = 1,
		WeightKey       = "Weight_RegularBoon",
		WeightDefault   = 1,

		SupportsCage    = true,
		IsEligible      = function( run, room ) return true end,

		Transform = function( room, door )
			room.ChosenRewardType = "Boon"
			room.RewardStoreName  = "RunProgress"
			door.RewardStoreName  = "RunProgress"
			local lootData = ChooseLoot()
			if lootData then room.ForceLootName = lootData.Name end
		end,

		TransformCage = function( currentRoom )
			local lootData = ChooseLoot()
			return {
				RewardOverride = "Boon",
				LootName       = lootData and lootData.Name or nil,
			}
		end,
	},

	EnhancedBoon = {
		Title           = "Enhanced Boon",
		UIColor         = { 1.0, 0.85, 0.45, 1.0 },
		Rarity          = "Epic",
		IconAnim        = "BlindBoxLoot",
		IconOverlayAnim = "BoonUpgradedPreviewSparkles",

		CostKey         = "Cost_EnhancedBoon",
		CostDefault     = 0,
		GreedKey        = "GreedMultiplier_EnhancedBoon",
		GreedDefault    = 2,
		DurationKey     = "Duration_EnhancedBoon",
		DurationDefault = 2,
		WeightKey       = "Weight_EnhancedBoon",
		WeightDefault   = 1,

		SupportsCage    = true,
		IsEligible      = function( run, room ) return true end,

		Transform = function( room, door )
			room.ChosenRewardType = "Boon"
			room.RewardStoreName  = "RunProgress"
			door.RewardStoreName  = "RunProgress"
			local lootData = ChooseLoot()
			if lootData then room.ForceLootName = lootData.Name end
			room.BoonRaritiesOverride = {
				Rare = 0.40, Epic = 0.35, Heroic = 0.20, Legendary = 0.05,
			}
		end,

		TransformCage = function( currentRoom )
			currentRoom.BoonRaritiesOverride = {
				Rare = 0.40, Epic = 0.35, Heroic = 0.20, Legendary = 0.05,
			}
			local lootData = ChooseLoot()
			return {
				RewardOverride = "Boon",
				LootName       = lootData and lootData.Name or nil,
			}
		end,
	},

	Hammer = {
		Title           = "Daedalus Hammer",
		UIColor         = { 1.0, 0.47, 0.20, 1.0 },
		Rarity          = "Legendary",
		IconAnim        = "WeaponUpgradePreview",
		IconOverlayAnim = nil,

		CostKey         = "Cost_Hammer",
		CostDefault     = 0,
		GreedKey        = "GreedMultiplier_Hammer",
		GreedDefault    = 3,
		DurationKey     = "Duration_Hammer",
		DurationDefault = 3,
		WeightKey       = "Weight_Hammer",
		WeightDefault   = 1,

		SupportsCage    = true,
		IsEligible      = function( run, room ) return true end,

		Transform = function( room, door )
			room.ChosenRewardType = "WeaponUpgrade"
			room.RewardStoreName  = "RunProgress"
			door.RewardStoreName  = "RunProgress"
		end,

		TransformCage = function( currentRoom )
			return { RewardOverride = "WeaponUpgrade", LootName = nil }
		end,
	},
}


-- ----------------------------------------------------------------------------
-- Playtest logger. Leveled + categorized. Output is routed through Lua's
-- print(), which Hell2Modding captures into LogOutput.log prefixed with the
-- plugin name. DebugPrint is NOT used here because the engine gates it behind
-- /VerboseScriptLogging=true, which is off in the modded build — every
-- DebugPrint line would be silently dropped. Threshold is re-read per call so
-- editing config.LogLevel and hot-reloading takes effect immediately.
-- ----------------------------------------------------------------------------
ProvokeMod.Log = ProvokeMod.Log or {}
local LOG_LEVELS = { TRACE = 10, DEBUG = 20, INFO = 30, WARN = 40, ERROR = 50 }

local function currentLogThreshold()
	local name = (config and config.LogLevel) or "INFO"
	return LOG_LEVELS[name] or LOG_LEVELS.INFO
end

local function logEmit( level, category, message, kvs )
	if LOG_LEVELS[level] < currentLogThreshold() then return end
	local line = string.format( "[ProvokeMod][%s][%s] %s", level, category, message or "" )
	if kvs then
		for k, v in pairs( kvs ) do
			line = line .. string.format( " %s=%s", k, tostring( v ) )
		end
	end
	print( line )
end

function ProvokeMod.Log.trace( cat, msg, kvs ) logEmit( "TRACE", cat, msg, kvs ) end
function ProvokeMod.Log.debug( cat, msg, kvs ) logEmit( "DEBUG", cat, msg, kvs ) end
function ProvokeMod.Log.info ( cat, msg, kvs ) logEmit( "INFO",  cat, msg, kvs ) end
function ProvokeMod.Log.warn ( cat, msg, kvs ) logEmit( "WARN",  cat, msg, kvs ) end
function ProvokeMod.Log.error( cat, msg, kvs ) logEmit( "ERROR", cat, msg, kvs ) end

function ProvokeMod.ResetRunState()
	local counts = {}
	if ProvokeMod.ChoiceTypes then
		for key, _ in pairs( ProvokeMod.ChoiceTypes ) do counts[key] = 0 end
	end
	ProvokeMod.RunState = {
		ProvocationCount = 0,
		ProvokedCounts = counts,
		ActiveFearStacks = {},          -- list of provocations still decaying across rooms
		ActiveTransientVows = {},       -- merged injection currently applied to ShrineUpgrades
		TransientFearActive = false,
		FearHUDIconIds = nil,           -- HUD cluster showing active vows this room
		ProvokedDoors = {},
		ProvokedCages = {},          -- cageObjectId → { ChoiceType, FearCost, RewardId, Cage }
		LastFearCost = nil,
		ProvokeHintId = nil,
		HintThreadActive = false,
		NearestProvokableDoor = nil,
	}
end

-- Initialize on first load only
if not ProvokeMod.RunState then
	ProvokeMod.ResetRunState()
end

-- ============================================================================
-- Section 2: Utility Functions
-- ============================================================================

-- Per-choice-type greed multiplier used by GetFearCost. The ramp for each
-- choice is linear: greed = effectiveCount * typeMultiplier, so RegularBoon
-- grows +1/+2/+3..., EnhancedBoon +2/+4/+6..., Hammer +3/+6/+9... with the
-- defaults. Reads from config so players can dial each type independently
-- via their .cfg; `or` fallbacks preserve behaviour when a key is missing
-- (e.g. a player upgrading over an older .cfg lacking these keys).
function ProvokeMod.GetGreedMultiplier( choiceType )
	local entry = ProvokeMod.ChoiceTypes and ProvokeMod.ChoiceTypes[choiceType]
	if entry == nil then return 1 end
	return config[entry.GreedKey] or entry.GreedDefault or 1
end

-- Fear cost for a provocation. `effectiveCount` is the 1-indexed position this
-- provocation will occupy among ALL provocations in the run (1 = first
-- provocation ever this run, regardless of type). If nil, defaults to
-- ProvocationCount + 1 (the slot this call would consume if committed now).
-- Formula: Cost_<Type> + ceil(effectiveCount * typeMultiplier). Cost_<Type>
-- defaults to 0 so the greed ramp alone determines cost (1/2/3 for first
-- pick, 2/4/6 for second, ...); raise Cost_<Type> in config.lua to apply a
-- flat offset on top. The linear ramp is per-choice-type — RegularBoon
-- gentler, Hammer steeper — via config.GreedMultiplier_<ChoiceType>.
-- math.ceil keeps fractional multipliers from rounding greed down to 0.
function ProvokeMod.GetFearCost( choiceType, effectiveCount )
	local entry = ProvokeMod.ChoiceTypes and ProvokeMod.ChoiceTypes[choiceType]
	local baseCost = 0
	if entry ~= nil then
		baseCost = config[entry.CostKey] or entry.CostDefault or 0
	end
	if effectiveCount == nil then
		local totalCount = (ProvokeMod.RunState and ProvokeMod.RunState.ProvocationCount) or 0
		effectiveCount = totalCount + 1
	end
	effectiveCount = math.max( 1, effectiveCount )
	local greedBonus = 0
	if config.EnableGreed then
		greedBonus = math.ceil( effectiveCount * ProvokeMod.GetGreedMultiplier( choiceType ) )
	end
	return baseCost + greedBonus
end

-- EncounterType values (see /Content/Scripts/EncounterData*.lua) that should NOT
-- tick Fear-stack duration on end. Anything not listed here — "Default", "Boss",
-- "Miniboss", "ArachneCombat", "EliteChallenge", "PerfectClear", "TimeChallenge"
-- and friends — is treated as combat and decays one room off each active stack.
ProvokeMod.NonCombatEncounterTypes = {
	NonCombat = true,
	Devotion  = true,
}

-- Duration-decay gate: returns true when the ended encounter actually pitted the
-- player against enemies. Nil / unset EncounterType defaults to "combat" so we
-- over-tick rather than over-hold on unfamiliar room shapes.
function ProvokeMod.IsCombatEncounter( encounter )
	if encounter == nil then return true end
	local et = encounter.EncounterType
	if et == nil then return true end
	return not ProvokeMod.NonCombatEncounterTypes[et]
end

function ProvokeMod.IsMetaProgressDoor( door )
	if door == nil or door.Room == nil then
		return false
	end
	-- Exclude provoking FROM a boss room (the door's source is the current room).
	if CurrentRun and CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.Encounter then
		if CurrentRun.CurrentRoom.Encounter.EncounterType == "Boss" then
			return false
		end
	end
	-- Exclude provoking INTO a boss room: the biome boss reward slot shouldn't
	-- be swappable for a Hammer / Boon, and the UX of provoking a boss fight
	-- on top of the existing boss-room vow stack is too much. `door.Room.Encounter`
	-- is always nil at door-time — vanilla's CreateRoom for a door passes
	-- `SkipChooseEncounter = true` (RoomLogic.lua:3915) — so key off the target
	-- room's name. Every biome's boss room is `<Biome>_Boss<NN>` (C_Boss01,
	-- G_Boss01/02, H_Boss01/02, I_Boss01, F_Boss01/02, N_Boss01/02, O_Boss01/02,
	-- P_Boss01, Q_Boss01/02); PreBoss / PostBoss / MiniBoss rooms intentionally
	-- stay provokable.
	local targetName = door.Room.Name
	if targetName and string.match( targetName, "^[A-Z]_Boss%d+$" ) then
		return false
	end
	-- Exclude story/NPC rooms (Arachne, Narcissus, etc.): their ForcedReward propagates
	-- to ChosenRewardType = "Story", but RewardStoreName can still be "MetaProgress".
	if door.Room.ChosenRewardType == "Story" or door.Room.ForcedReward == "Story" then
		return false
	end
	return (door.RewardStoreName or door.Room.RewardStoreName) == "MetaProgress"
end

-- Check if a door is provokable: either it's currently a MetaProgress door,
-- or it was originally MetaProgress before being transformed by a provocation.
function ProvokeMod.IsProvokableDoor( door )
	if not ProvokeMod.IsUnlocked() then
		return false
	end
	if ProvokeMod.IsMetaProgressDoor( door ) then
		return true
	end
	local pd = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	return pd ~= nil and pd.Provoked and pd.OriginalRewardStoreName == "MetaProgress"
end

-- Fix 4b: Mourning Fields (biome H) doesn't gate minor rewards behind exit
-- doors. Ash / Bones / Psyche ship as free-floating MetaCurrencyDrop
-- consumables that fire through UseConsumableItem instead of LeaveRoom. The
-- mod treats these as provokable targets too, but downstream code that reads
-- door.Room or auto-proceeds via LeaveRoom must gate on target type.
-- Fields-biome consumable pickups that correspond to the "minor meta-reward"
-- doors we already accept in other biomes. Vanilla mapping from
-- HelpText.en.sjson + ConsumableData.lua:
--   MetaCurrencyDrop         → Bones (MetaCurrency = 50)
--   MetaCardPointsCommonDrop → Ashes (MetaCardPointsCommon = 5)
--   GiftDrop                 → Nectar
--   MemPointsCommonDrop      → Psyche  -- intentionally NOT provokable
--   PlantFMolyDrop           → Moly    -- intentionally NOT provokable
-- In-run loot (MaxManaDrop, ArmorBoost, RoomMoneyDrop, RoomRewardHealDrop) is
-- also excluded — those aren't cross-run meta-progression rewards.
ProvokeMod.ProvokableFieldsPickupNames = {
	MetaCurrencyDrop         = true,  -- Bones
	MetaCardPointsCommonDrop = true,  -- Ashes
	GiftDrop                 = true,  -- Nectar
}

function ProvokeMod.IsProvokableFieldsPickup( useTarget )
	if not ProvokeMod.IsUnlocked() then return false end
	if useTarget == nil or useTarget.Name == nil then return false end
	local room = CurrentRun and CurrentRun.CurrentRoom
	if room == nil or room.RoomSetName ~= "H" then return false end
	return ProvokeMod.ProvokableFieldsPickupNames[useTarget.Name] == true
end

-- True for any target the provocation flow should accept — door or Fields
-- pickup. Callers that need to branch on shape should switch on the specific
-- predicate (IsProvokableDoor vs IsProvokableFieldsPickup).
function ProvokeMod.IsProvokableTarget( target )
	if target == nil then return false end
	if ProvokeMod.IsProvokableFieldsPickup( target ) then return true end
	return ProvokeMod.IsProvokableDoor( target )
end

-- Find the first MetaProgress exit in the current room (provoked or not).
-- Also matches doors that were originally MetaProgress but have been transformed
-- (TransformDoor changes door.RewardStoreName away from "MetaProgress").
-- Returns the door object or nil if none found.
-- Doors are stored in the global MapState.OfferedExitDoors (set by DoUnlockRoomExits).
function ProvokeMod.FindProvokableDoor()
	if MapState == nil or MapState.OfferedExitDoors == nil then
		ProvokeMod.Log.warn( "door", "FindProvokableDoor: MapState.OfferedExitDoors is nil" )
		return nil
	end
	local count = 0
	for _, door in pairs( MapState.OfferedExitDoors ) do
		count = count + 1
		if door.ReadyToUse and ProvokeMod.IsProvokableDoor( door ) then
			ProvokeMod.Log.debug( "door", "detected provokable door", { objectId = door.ObjectId, checked = count } )
			return door
		end
	end
	ProvokeMod.Log.debug( "door", "no provokable door in offered exits", { checked = count } )
	return nil
end

-- Notification name used by the long-press gate inside the LeaveRoom wrap.
ProvokeMod.HoldReleaseNotifyName = "ProvokeMod__HoldRelease"

-- Called after DoUnlockRoomExits completes and exits are ready to use.
-- With long-press Interact, no hotkey-listener thread is needed — the hold vs
-- tap detection runs inside the LeaveRoom wrap itself. This function exists
-- only to track whether a provokable door is present so SpawnProvokeHint is
-- driven by OnShowUseButton (proximity) without an external listener.
function ProvokeMod.OnExitsUnlocked()
	ProvokeMod.Log.debug( "room", "exits unlocked" )
	-- Mark the hint thread as active so DespawnProvokeHint can clear proximity
	-- state on room exit; the flag is legacy but still guards the hint lifecycle.
	if ProvokeMod.FindProvokableDoor() ~= nil then
		ProvokeMod.RunState.HintThreadActive = true
	end
end

-- Fix 4a instrumentation: while the player is in Mourning Fields (RoomSetName
-- == "H"), log the shape of every interactable whose use-prompt shows. Fields
-- routes main rewards through FieldsRewardCage obstacles whose underlying
-- reward lives at ActiveObstacles[cage.RewardId]; the minor pickups (Ash /
-- Bones / Psyche) appear to be normal uncaged consumables. We don't know the
-- exact Lua-side field names either type exposes, so this pass dumps a
-- handful of likely fields on both the outer obstacle and its linked reward
-- so the next pass can write a real provokable-in-Fields predicate and a
-- transform that re-wraps the pickup as a cage-gated boon.
function ProvokeMod.LogFieldsInteractableShape( objectId, useTarget )
	local room = CurrentRun and CurrentRun.CurrentRoom
	if room == nil or room.RoomSetName ~= "H" then return end

	-- Vanilla ShowUseButton receives the useTarget object directly (see
	-- UILogic.lua:229 — triggerArgs.AttachedTable). It's also mirrored at
	-- SessionMapState.ActiveUseTarget for other consumers.
	local t = useTarget
	if t == nil and SessionMapState and SessionMapState.ActiveUseTarget then
		t = SessionMapState.ActiveUseTarget
	end

	local kvs = {
		objectId    = objectId,
		roomSetName = room.RoomSetName,
		hasTarget   = t ~= nil,
	}
	if t ~= nil then
		kvs.t_Name             = t.Name
		kvs.t_ObjectType       = t.ObjectType
		kvs.t_ObjectId         = t.ObjectId
		kvs.t_RewardId         = t.RewardId
		kvs.t_ConsumableType   = t.ConsumableType
		kvs.t_ConsumableName   = t.ConsumableName
		kvs.t_UseFunctionName  = t.UseFunctionName
		kvs.t_OnUsedFunctionName = t.OnUsedFunctionName
		kvs.t_RewardType       = t.RewardType
		kvs.t_RewardStoreName  = t.RewardStoreName
		kvs.t_ChosenRewardType = t.ChosenRewardType
		kvs.t_ForceLootName    = t.ForceLootName
		kvs.t_ResourceName     = t.ResourceName
		kvs.t_ResourceAmount   = t.ResourceAmount
		kvs.t_MetaDrop         = t.MetaDrop
		kvs.t_LootName         = t.LootName
		kvs.t_UseText          = t.UseText
		kvs.t_UnlockedUseText  = t.UnlockedUseText
		kvs.t_hasRoom          = t.Room ~= nil
	end

	-- Also log room.CageRewards / room.SpawnPoints briefly so we can see the
	-- overall structure of a Fields room from a single log.
	kvs.room_hasCageRewards = room.CageRewards ~= nil
	if room.CageRewards then
		kvs.room_cageRewards_count = #room.CageRewards
	end
	kvs.room_chosenRewardType = room.ChosenRewardType
	kvs.room_rewardStoreName  = room.RewardStoreName

	ProvokeMod.Log.info( "fields", "show_use_button_shape", kvs )
end

-- Called when the game shows a use prompt for an obstacle (player entered interact range).
-- Shows the Provoke hint only when the relevant MetaProgress door is in range,
-- and tracks which door the player is currently nearest to.
function ProvokeMod.OnShowUseButton( objectId, useTarget )
	ProvokeMod.LogFieldsInteractableShape( objectId, useTarget )

	-- Exit-door path (every biome, including Fields' own FieldsExitDoor).
	if MapState ~= nil and MapState.OfferedExitDoors ~= nil then
		local door = MapState.OfferedExitDoors[objectId]
		if door ~= nil and ProvokeMod.IsProvokableDoor( door ) then
			ProvokeMod.RunState.NearestProvokableDoor = door
			ProvokeMod.Log.debug( "door", "show (provokable)", { objectId = objectId } )
			ProvokeMod.SpawnProvokeHint()
			return
		end
	end

	-- Fields pickup path: MetaCurrencyDrop in biome H routes through
	-- UseConsumableItem, not LeaveRoom, so we need a separate provoke entry
	-- point. We still park the target in NearestProvokableDoor for the long-
	-- press gate to pick up (the field name is legacy — covers both shapes).
	if ProvokeMod.IsProvokableFieldsPickup( useTarget ) then
		ProvokeMod.RunState.NearestProvokableDoor = useTarget
		ProvokeMod.Log.debug( "fields", "show (provokable pickup)", {
			objectId = objectId,
			name     = useTarget.Name,
		} )
		ProvokeMod.SpawnProvokeHint()
		return
	end

	ProvokeMod.Log.trace( "door", "show (non-provokable)", { objectId = objectId } )
end

-- Called when the game hides a use prompt (player left interact range).
-- Clears the nearest-target reference so a stale target is not used when the
-- hotkey fires, and despawns the provoke hint so it doesn't linger after the
-- player walks away from a pickup or door.
function ProvokeMod.OnHideUseButton( objectId )
	local nearest = ProvokeMod.RunState.NearestProvokableDoor
	if nearest and nearest.ObjectId == objectId then
		ProvokeMod.RunState.NearestProvokableDoor = nil
		ProvokeMod.DespawnProvokeHint()
		ProvokeMod.Log.debug( "door", "hide (cleared nearest)", { objectId = objectId } )
	else
		ProvokeMod.Log.trace( "door", "hide (not nearest)", { objectId = objectId } )
	end
end

-- Show a "second line" hint below the door's {I} Proceed UsePrompt, matching
-- the accept/gift button style used by boon/NPC interaction prompts.
-- UsePrompt text appears at ~Y=1010 (ScreenHeight - BottomOffset(−10) - textOffset(80)).
-- We position ours ~30px below that, so together they read as two stacked options.
function ProvokeMod.SpawnProvokeHint()
	if not ProvokeMod.IsUnlocked() then
		return
	end
	if ProvokeMod.RunState.ProvokeHintId ~= nil then
		ProvokeMod.Log.trace( "door", "hint_spawn skipped: already visible" )
		return
	end
	ProvokeMod.Log.debug( "door", "hint_spawn" )
	-- NOTE: CreateScreenObstacle returns the obstacle ID directly (a number), not a table.
	local textY = ScreenHeight - 38  -- ≈1042; just below the door's {I} Proceed at ≈1010
	-- No separate InteractBacking — the game's existing backing for "Proceed" covers
	-- this region so both prompts share one unified dark background.
	local hintId = CreateScreenObstacle({
		Name = "BlankObstacle",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = textY,
	})
	-- {I} is the engine macro for the current Interact-button glyph (KBM or gamepad).
	CreateTextBox({
		Id = hintId,
		Text = "Hold {I} to Provoke the Fates",
		Font = "P22UndergroundSCHeavy",
		FontSize = 22,
		Color = { 1, 1, 1, 1 },
		TextSymbolScale = 0.8,
		ShadowBlur = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 5 },
		OutlineThickness = 3, OutlineColor = { 0, 0, 0, 1 },
		Justification = "Center",
	})
	ProvokeMod.RunState.ProvokeHintId = hintId
end

-- Remove the HUD hint. No listener thread to wake — long-press detection now
-- lives in the LeaveRoom wrap, not a parallel thread.
function ProvokeMod.DespawnProvokeHint()
	ProvokeMod.RunState.HintThreadActive = false
	if ProvokeMod.RunState.ProvokeHintId then
		Destroy({ Id = ProvokeMod.RunState.ProvokeHintId })
		ProvokeMod.RunState.ProvokeHintId = nil
		ProvokeMod.Log.debug( "door", "hint_despawn" )
	else
		ProvokeMod.Log.trace( "door", "hint_despawn (nothing to destroy)" )
	end
end


-- ============================================================================
-- Section 3: Transient Fear Engine
-- ============================================================================

function ProvokeMod.GetVowMaxRank( vowName )
	local data = MetaUpgradeData[vowName]
	if data and data.Ranks then
		return #data.Ranks
	end
	return 0
end

-- Returns true when every eligible vow is already at its native max rank.
-- The caller uses this to block a provocation with a "Fates are satisfied"
-- rejection instead of charging Fear that cannot land anywhere.
function ProvokeMod.AllVowsFull()
	for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
		local current = GameState.ShrineUpgrades[vowName] or 0
		if current < ProvokeMod.GetVowMaxRank( vowName ) then
			return false
		end
	end
	return true
end

-- Pick 1–2 "themed" vows for a provocation and concentrate the Fear on them.
-- At or below ThemedSplitThreshold Fear, pick 1 vow and give it all the ranks.
-- Above the threshold, pick 2 distinct vows and split ranks evenly (the extra
-- rank goes to the second pick when fearCost is odd).
-- Every vow is hard-capped at its native max rank; if the initial picks can't
-- absorb the full Fear cost, overflow pulls more vows in from the remaining
-- pool (random order) so every paid Fear point lands as a visible rank.
-- Returns { [vowName] = ranks }, or nil if no vow has any remaining room.
function ProvokeMod.SelectThemedVows( fearCost )
	local pool = {}
	for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
		local current = GameState.ShrineUpgrades[vowName] or 0
		if current < ProvokeMod.GetVowMaxRank( vowName ) then
			table.insert( pool, vowName )
		end
	end
	if #pool == 0 then return nil end

	local threshold = config.ThemedSplitThreshold or 6
	local targetCount = (fearCost <= threshold) and 1 or 2
	targetCount = math.min( targetCount, #pool )

	-- Initial themed picks are drawn from the pool; remainingPool keeps the
	-- rest so the overflow spill has more vows to fall through to.
	local remainingPool = {}
	for i, v in ipairs( pool ) do remainingPool[i] = v end
	local picks = {}
	for i = 1, targetCount do
		local idx = RandomInt( 1, #remainingPool )
		table.insert( picks, remainingPool[idx] )
		table.remove( remainingPool, idx )
	end

	local allocations = {}
	if targetCount == 1 then
		allocations[picks[1]] = fearCost
	else
		allocations[picks[1]] = math.floor( fearCost / 2 )
		allocations[picks[2]] = math.ceil( fearCost / 2 )
	end

	local injections = {}
	local function roomFor( vowName )
		local current = GameState.ShrineUpgrades[vowName] or 0
		local maxRank = ProvokeMod.GetVowMaxRank( vowName )
		local already = injections[vowName] or 0
		return math.max( 0, maxRank - current - already )
	end
	local function allocate( vowName, want )
		local take = math.min( want, roomFor( vowName ) )
		if take > 0 then
			injections[vowName] = (injections[vowName] or 0) + take
		end
		return want - take  -- leftover
	end

	-- First pass: themed picks get the split allocation.
	local overflow = 0
	for _, vowName in ipairs( picks ) do
		overflow = overflow + allocate( vowName, allocations[vowName] )
	end

	-- Second pass: if one pick capped out while the other still has room
	-- (single-pick mode, uneven splits), let the other pick absorb the spill
	-- before dragging more vows in.
	if overflow > 0 then
		for _, vowName in ipairs( picks ) do
			if overflow <= 0 then break end
			overflow = allocate( vowName, overflow )
		end
	end

	-- Third pass: pull additional vows from the rest of the pool (random
	-- order) until every Fear point has landed or the pool is exhausted.
	while overflow > 0 and #remainingPool > 0 do
		local idx = RandomInt( 1, #remainingPool )
		local vowName = remainingPool[idx]
		table.remove( remainingPool, idx )
		overflow = allocate( vowName, overflow )
	end

	for vowName, ranks in pairs( injections ) do
		ProvokeMod.Log.debug( "fear", "themed_pick", {
			vow      = vowName,
			ranks    = ranks,
			fearCost = fearCost,
			splits   = targetCount,
			poolSize = #pool,
			overflowDropped = overflow,
		} )
	end

	return injections
end

-- Queue a new Fear stack at provocation time. The stack persists for a
-- duration of rooms; each room it's active applies its injection ranks on top
-- of any other active stacks. Greedier same-type provocations get longer
-- durations (+1 room per prior same-type provocation, capped by config).
function ProvokeMod.QueueFearStack( choiceType, injection, fearCost )
	if injection == nil then
		-- All vows full at provoke time — the player's "Fear" cannot land.
		-- Queue nothing; let AllVowsFull block future provocations too.
		ProvokeMod.Log.warn( "fear", "QueueFearStack skipped: nil injection (all vows full)", { choiceType = choiceType, fearCost = fearCost } )
		return
	end
	local baseDuration = 1
	local entry = ProvokeMod.ChoiceTypes and ProvokeMod.ChoiceTypes[choiceType]
	if entry ~= nil then
		baseDuration = config[entry.DurationKey] or entry.DurationDefault or 1
	end

	local extension = 0
	if config.GreedExtendsDuration then
		-- Greed is global: extension = prior provocation count across all types.
		-- TransformDoor already incremented ProvocationCount for this pick, so
		-- subtract 1 to count only the provocations that came before it.
		local count = (ProvokeMod.RunState and ProvokeMod.RunState.ProvocationCount) or 1
		extension = math.max( 0, count - 1 )
	end

	local duration = baseDuration + extension

	table.insert( ProvokeMod.RunState.ActiveFearStacks, {
		Injection      = injection,
		RoomsRemaining = duration,
		ChoiceType     = choiceType,
		FearCost       = fearCost or 0,
	})

	ProvokeMod.Log.info( "fear", "queue stack", {
		choiceType  = choiceType,
		duration    = duration,
		baseDur     = baseDuration,
		extension   = extension,
		fearCost    = fearCost or 0,
		liveStacks  = #ProvokeMod.RunState.ActiveFearStacks,
	} )
end

-- Persistent HUD icon cluster showing each active vow while Fear is applied.
-- Uses the vanilla MetaUpgradeData[vow].Icon animations on small BlankObstacles
-- arranged horizontally near the top-right of the screen, with a rooms-
-- remaining label centered beneath the icons.
function ProvokeMod.UpdateFearHUD()
	ProvokeMod.ClearFearHUD()
	if not ProvokeMod.RunState.TransientFearActive then return end
	if ProvokeMod.RunState.ActiveTransientVows == nil then return end

	local vows = {}
	for vowName, _ in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
		table.insert( vows, vowName )
	end
	table.sort( vows )

	local iconSpacing = 52
	-- Right margin 120: the encounters-left label is centered under the icon
	-- midpoint, and its text is wider than the icon cluster — especially with a
	-- single vow, where the label would otherwise extend past the screen edge.
	local startX = ScreenWidth - 120 - (#vows - 1) * iconSpacing
	local iconY = 128
	local ids = {}
	for i, vowName in ipairs( vows ) do
		local iconAnim = MetaUpgradeData and MetaUpgradeData[vowName] and MetaUpgradeData[vowName].Icon
		if iconAnim then
			local component = CreateScreenComponent({
				Name  = "BlankObstacle",
				Group = "Combat_Menu_TraitTray_Overlay",
				X     = startX + (i - 1) * iconSpacing,
				Y     = iconY,
				Scale = 0.6,
			})
			SetAnimation({ Name = iconAnim, DestinationId = component.Id })
			table.insert( ids, component.Id )
		end
	end

	-- Encounters-remaining label: max RoomsRemaining across every live stack
	-- — the number of combat encounters (including this one) the player is
	-- still under Fear. Door-fear and cage-fear both live in ActiveFearStacks
	-- now (ApplyCageFear queues via QueueFearStack), so this one read covers
	-- both cases.
	local maxRemaining = 0
	for _, stack in ipairs( ProvokeMod.RunState.ActiveFearStacks or {} ) do
		local rr = stack.RoomsRemaining or 0
		if rr > maxRemaining then maxRemaining = rr end
	end
	if maxRemaining > 0 then
		local labelX = startX + ((#vows - 1) * iconSpacing) / 2
		local label = CreateScreenComponent({
			Name  = "BlankObstacle",
			Group = "Combat_Menu_TraitTray_Overlay",
			X     = labelX,
			Y     = iconY + 62,
		})
		CreateTextBox({
			Id            = label.Id,
			Text          = (maxRemaining == 1) and "1 encounter left" or (tostring( maxRemaining ) .. " encounters left"),
			FontSize      = 15,
			Color         = { 0.82, 0.75, 1.0, 1.0 },
			Font          = "P22UndergroundSCMedium",
			ShadowBlur    = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
			Justification = "Center",
		})
		table.insert( ids, label.Id )
	end

	ProvokeMod.RunState.FearHUDIconIds = ids
end

function ProvokeMod.ClearFearHUD()
	local ids = ProvokeMod.RunState.FearHUDIconIds
	if ids and #ids > 0 then
		Destroy({ Ids = ids })
	end
	ProvokeMod.RunState.FearHUDIconIds = nil
end

-- Restore ShrineUpgrades to their pre-injection ranks from ActiveTransientVows.
-- Idempotent — no-op when TransientFearActive is already false.
-- Does NOT touch stack bookkeeping — use RestoreVowsAndDecayStacks for that.
function ProvokeMod.RestoreVowsOnly()
	if not ProvokeMod.RunState.TransientFearActive then
		ProvokeMod.Log.trace( "fear", "RestoreVowsOnly: no-op (TransientFearActive was false)" )
		return
	end

	local restored = 0
	for vowName, vowData in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
		GameState.ShrineUpgrades[vowName] = vowData.OriginalRank
		ShrineUpgradeExtractValues( vowName )
		restored = restored + 1
	end
	ProvokeMod.RunState.ActiveTransientVows = {}
	ProvokeMod.RunState.TransientFearActive = false
	ProvokeMod.ClearFearHUD()
	ProvokeMod.Log.trace( "fear", "RestoreVowsOnly complete", { vowsRestored = restored } )
end

-- Restore vows AND advance stack bookkeeping — drops each active stack's
-- RoomsRemaining by 1 and removes stacks that have expired. Called from
-- OnEncounterEnd on the last encounter of the room.
function ProvokeMod.RestoreVowsAndDecayStacks()
	ProvokeMod.RestoreVowsOnly()

	local stacks = ProvokeMod.RunState.ActiveFearStacks
	if stacks == nil then return end
	local before = #stacks
	local kept = {}
	local expired = 0
	for _, stack in ipairs( stacks ) do
		local was = stack.RoomsRemaining
		stack.RoomsRemaining = was - 1
		ProvokeMod.Log.debug( "fear", "stack_decay_tick", {
			choiceType = stack.ChoiceType,
			before     = was,
			after      = stack.RoomsRemaining,
		} )
		if stack.RoomsRemaining > 0 then
			table.insert( kept, stack )
		else
			expired = expired + 1
			ProvokeMod.Log.info( "fear", "stack_expired", {
				choiceType   = stack.ChoiceType,
				fearCostPaid = stack.FearCost or 0,
			} )
		end
	end
	ProvokeMod.RunState.ActiveFearStacks = kept
	ProvokeMod.Log.info( "fear", "restore + decay complete", {
		stacksBefore = before,
		stacksAfter  = #kept,
		expired      = expired,
	} )
end

-- Legacy alias: older call sites (KillHero, LeaveRoom safety) invoke
-- RemoveTransientFear. Keep it as a synonym for RestoreVowsOnly so those sites
-- don't accidentally decay stacks on every safety call.
function ProvokeMod.RemoveTransientFear()
	ProvokeMod.RestoreVowsOnly()
end

-- Dump the currently-active fear stacks so the developer can see what Provocations
-- are still carrying across rooms. `phase` is a short label ("room_start",
-- "encounter_end", etc.) so lines can be correlated in the log.
function ProvokeMod.LogFearStackState( phase )
	local stacks = ProvokeMod.RunState.ActiveFearStacks or {}
	local totalRanks = 0
	for _, stack in ipairs( stacks ) do
		local vowCount, stackRanks = 0, 0
		for _, ranks in pairs( stack.Injection or {} ) do
			vowCount   = vowCount + 1
			stackRanks = stackRanks + ranks
		end
		totalRanks = totalRanks + stackRanks
		ProvokeMod.Log.info( "fear", "stack_state", {
			phase          = phase,
			choiceType     = stack.ChoiceType,
			roomsRemaining = stack.RoomsRemaining,
			fearCost       = stack.FearCost or 0,
			vowCount       = vowCount,
			ranks          = stackRanks,
		} )
	end
	ProvokeMod.Log.info( "fear", "stack_state summary", {
		phase      = phase,
		liveStacks = #stacks,
		totalRanks = totalRanks,
	} )
end

-- ============================================================================
-- Section 4: Door Transformation
-- ============================================================================

-- `previewedInjection` (optional): a pre-resolved { [vow] = ranks } map from
-- the provocation screen's preview. When present, the exact ranks shown to the
-- player are the ones that will be applied. When nil, the room-start injection
-- rolls fresh.
function ProvokeMod.TransformDoor( door, choiceType, previewedInjection )
	local room = door.Room
	local fearCost = ProvokeMod.GetFearCost( choiceType )

	-- Store provocation data
	local provokeData = {
		ChoiceType = choiceType,
		FearCost = fearCost,
		PreviewedInjection = previewedInjection,
		OriginalRewardType = room.ChosenRewardType,
		OriginalForceLootName = room.ForceLootName,
		OriginalRewardStoreName = room.RewardStoreName or door.RewardStoreName,
		Provoked = true,
	}

	-- Clear existing loot specifics
	room.ForceLootName = nil
	room.RewardOverrides = nil

	-- Per-type mutations (ChosenRewardType, RewardStoreName, ForceLootName,
	-- optional BoonRaritiesOverride) are owned by the registry entry.
	local entry = ProvokeMod.ChoiceTypes and ProvokeMod.ChoiceTypes[choiceType]
	if entry and entry.Transform then
		entry.Transform( room, door )
	else
		ProvokeMod.Log.error( "provoke", "TransformDoor: unknown choiceType", { choiceType = choiceType } )
	end

	-- Mark the room object so DoUnlockRoomExits and LeaveRoom can restore
	-- RewardStoreName for CalcMetaProgressRatio without affecting reward delivery.
	room._OriginalRewardStoreName = provokeData.OriginalRewardStoreName

	-- Track provocation
	ProvokeMod.RunState.ProvocationCount = ProvokeMod.RunState.ProvocationCount + 1
	ProvokeMod.RunState.ProvokedCounts[choiceType] = (ProvokeMod.RunState.ProvokedCounts[choiceType] or 0) + 1
	ProvokeMod.RunState.ProvokedDoors[door.ObjectId] = provokeData

	-- Refresh the door's reward preview icon
	ProvokeMod.RefreshDoorPreview( door )

	ProvokeMod.Log.info( "provoke", "transform door", {
		choiceType        = choiceType,
		fearCost          = fearCost,
		objectId          = door.ObjectId,
		provocationCount  = ProvokeMod.RunState.ProvocationCount,
		sameTypeCount     = ProvokeMod.RunState.ProvokedCounts[choiceType],
	} )
end

-- Revert a provoked door back to its original MetaProgress reward.
-- Decrements ProvocationCount and clears the ProvokedDoors entry. Idempotent.
function ProvokeMod.UnTransformDoor( door )
	local provokeData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	if provokeData == nil or not provokeData.Provoked then
		ProvokeMod.Log.warn( "provoke", "UnTransformDoor called on un-provoked door", { objectId = door and door.ObjectId } )
		return
	end

	local room = door.Room

	-- Restore original room and door reward state
	room.ChosenRewardType = provokeData.OriginalRewardType
	room.ForceLootName    = provokeData.OriginalForceLootName
	room.RewardStoreName  = provokeData.OriginalRewardStoreName
	door.RewardStoreName  = provokeData.OriginalRewardStoreName

	-- Clear the boon rarity override (set by EnhancedBoon; nil for other types)
	room.BoonRaritiesOverride = nil
	room._OriginalRewardStoreName = nil

	-- Decrement the greed counter, clamped to 0
	ProvokeMod.RunState.ProvocationCount = math.max( 0, ProvokeMod.RunState.ProvocationCount - 1 )
	local typeKey = provokeData.ChoiceType
	ProvokeMod.RunState.ProvokedCounts[typeKey] = math.max( 0, (ProvokeMod.RunState.ProvokedCounts[typeKey] or 0) - 1 )

	-- Clear the provoke entry so the door is treated as fresh
	ProvokeMod.RunState.ProvokedDoors[door.ObjectId] = nil

	-- Refresh the door's reward preview icon back to the original
	ProvokeMod.RefreshDoorPreview( door )

	ProvokeMod.Log.debug( "provoke", "revert door", {
		objectId         = door.ObjectId,
		choiceType       = typeKey,
		provocationCount = ProvokeMod.RunState.ProvocationCount,
		sameTypeCount    = ProvokeMod.RunState.ProvokedCounts[typeKey],
	} )
end

-- Apply a single { [vowName] = ranks } injection on top of whatever is
-- already in ActiveTransientVows. Per-vow ranks clamp at the vow's max
-- rank minus any ranks already added this encounter. Returns the total
-- new ranks actually applied so callers can log / banner off it.
function ProvokeMod.ApplyInjectionAdditively( injection )
	if injection == nil then return 0 end
	ProvokeMod.RunState.ActiveTransientVows = ProvokeMod.RunState.ActiveTransientVows or {}

	local appliedRanks = 0
	for vowName, ranksToAdd in pairs( injection ) do
		local baseline = GameState.ShrineUpgrades[vowName] or 0
		local maxRank  = ProvokeMod.GetVowMaxRank( vowName )
		local existing = ProvokeMod.RunState.ActiveTransientVows[vowName]
		local already  = existing and existing.AddedRanks or 0
		local room     = math.max( 0, maxRank - baseline - already )
		local take     = math.min( ranksToAdd, room )
		if take > 0 then
			if existing then
				existing.AddedRanks = already + take
			else
				ProvokeMod.RunState.ActiveTransientVows[vowName] = {
					OriginalRank = baseline,
					AddedRanks   = take,
				}
			end
			GameState.ShrineUpgrades[vowName] = baseline + already + take
			ShrineUpgradeExtractValues( vowName )
			appliedRanks = appliedRanks + take
		end
	end

	if appliedRanks > 0 then
		ProvokeMod.RunState.TransientFearActive = true
	end
	return appliedRanks
end

-- Apply all active fear stacks additively to the current encounter's
-- ShrineUpgrades state, then refresh the HUD + banner off the combined ATV.
-- Called from the StartEncounter wrap so every combat encounter re-applies
-- the accumulated stacks' ranks.
--
-- Safe to call repeatedly within one encounter: ApplyInjectionAdditively
-- checks per-vow `already` (AddedRanks in ActiveTransientVows) and clamps
-- `take` against remaining room, so re-applying the same merged injection
-- becomes a no-op. That matters in Fields rooms where a passive/background
-- Default encounter starts at room entry and stays live through cage
-- combats nested inside it — each cage's StartEncounter re-fires this
-- function with the full stack list, and the additive clamp keeps the
-- passive's earlier apply from double-counting.
function ProvokeMod.ApplyActiveStacksForEncounter()
	local stacks = ProvokeMod.RunState.ActiveFearStacks
	if stacks ~= nil and #stacks > 0 then
		local merged = {}
		for _, stack in ipairs( stacks ) do
			for vow, r in pairs( stack.Injection or {} ) do
				merged[vow] = (merged[vow] or 0) + r
			end
		end
		local applied = ProvokeMod.ApplyInjectionAdditively( merged )
		if applied > 0 then
			ProvokeMod.Log.info( "fear", "active stacks applied for encounter", {
				stacks       = #stacks,
				appliedRanks = applied,
			} )
		end
	end

	-- Refresh HUD + banner off whatever ended up in ActiveTransientVows
	-- (covers door-fear, cage-fear just queued by StartFieldsEncounter, or
	-- both combined).
	local totalRanks = 0
	for _, vowData in pairs( ProvokeMod.RunState.ActiveTransientVows or {} ) do
		totalRanks = totalRanks + (vowData.AddedRanks or 0)
	end
	if totalRanks > 0 then
		ProvokeMod.UpdateFearHUD()
		local vowLines = ProvokeMod.GetVowListText( ProvokeMod.RunState.ActiveTransientVows )
		ProvokeMod.ShowFearBanner( totalRanks, vowLines, CurrentRun and CurrentRun.CurrentRoom )
	end
end

-- Fix 4b stage 3: promote a provoked Fields cage's pre-rolled injection into
-- a real ActiveFearStacks stack when the cage's combat starts. Routing
-- through QueueFearStack gives the cage-fear the same RoomsRemaining decay
-- loop door-fear uses, so a Hammer-provoked cage lasts its full
-- Duration_Hammer encounters instead of evaporating on first combat end.
-- StartEncounter's wrap fires immediately after this and injects the newly-
-- queued stack into ShrineUpgrades — no direct ATV writes here. Applied
-- exactly once per cage via FearApplied.
function ProvokeMod.ApplyCageFear( cageData )
	if cageData == nil or cageData.FearApplied then return end
	ProvokeMod.QueueFearStack( cageData.ChoiceType, cageData.Injection, cageData.FearCost )
	cageData.FearApplied = true

	ProvokeMod.Log.info( "fields", "cage_fear_queued", {
		choiceType = cageData.ChoiceType,
		fearCost   = cageData.FearCost,
	} )
end

-- Fix 4b stage 2: destroy a MetaCurrencyDrop in Mourning Fields and replace
-- it in-place with a cage-gated Boon/Hammer reward. Mirrors the vanilla
-- SpawnRewardCages sequence (RoomLogic.lua:5682-5709): copy ObstacleData,
-- SpawnObstacle with DestinationId = pickup.ObjectId so the cage inherits the
-- pickup's position, SetupObstacle, SpawnRoomReward with a matching override,
-- wire cage.RewardId, UseableOff the reward, then destroy the pickup. Runtime-
-- spawning means we can't lean on room.CageRewards wiring so we store our own
-- provocation metadata on RunState.ProvokedCages for cleanup on death.
function ProvokeMod.TransformFieldsPickup( pickup, choiceType )
	if pickup == nil or pickup.ObjectId == nil then
		ProvokeMod.Log.error( "fields", "TransformFieldsPickup: nil pickup" )
		return nil
	end

	local pickupId = pickup.ObjectId
	local pickupName = pickup.Name
	local currentRoom = CurrentRun and CurrentRun.CurrentRoom
	if currentRoom == nil then
		ProvokeMod.Log.error( "fields", "TransformFieldsPickup: no current room" )
		return nil
	end

	local fearCost = ProvokeMod.GetFearCost( choiceType )
	ProvokeMod.Log.info( "fields", "transform begin", {
		pickupId   = pickupId,
		pickupName = pickupName,
		choiceType = choiceType,
		fearCost   = fearCost,
	} )

	-- 1. Spawn the cage at the pickup's location. DestinationId = pickupId
	-- copies the pickup's current position; destroying the pickup afterwards
	-- does not affect the cage's anchoring.
	local cage = DeepCopyTable( ObstacleData["FieldsRewardCage"] )
	cage.ObjectId = SpawnObstacle({
		Name          = "FieldsRewardCage",
		DestinationId = pickupId,
		Group         = "Standing",
		TriggerOnSpawn = false,
	})
	cage.SpawnPointId = pickupId
	SetupObstacle( cage )
	ProvokeMod.Log.debug( "fields", "cage spawned", { cageId = cage.ObjectId } )

	-- 2. Spawn the reward. Mirror TransformDoor's room-state toggles so the
	-- vanilla reward pipeline lands the right shape (Boon rarity override for
	-- Enhanced, WeaponUpgrade for Hammer). Save + restore each field so the
	-- rest of the Fields room isn't contaminated.
	local savedRarities  = currentRoom.BoonRaritiesOverride
	local savedLootName  = currentRoom.ForceLootName
	local savedOverrides = currentRoom.RewardOverrides

	currentRoom.ForceLootName   = nil
	currentRoom.RewardOverrides = nil

	-- Per-type cage spec (RewardOverride, LootName, optional BoonRaritiesOverride
	-- side effect) is owned by the registry entry. Cage-incompatible types never
	-- reach here because the sampler filters them out; the fallback is defensive.
	local entry = ProvokeMod.ChoiceTypes and ProvokeMod.ChoiceTypes[choiceType]
	local spec = (entry and entry.TransformCage and entry.TransformCage( currentRoom ))
		or { RewardOverride = "Boon", LootName = nil }
	local rewardOverride = spec.RewardOverride
	local lootName       = spec.LootName

	local reward = SpawnRoomReward( currentRoom, {
		RewardOverride   = rewardOverride,
		LootName         = lootName,
		SpawnRewardOnId  = pickupId,
		AutoLoadPackages = true,
	})

	-- Restore room-level fields immediately so no other spawn path inherits them.
	currentRoom.BoonRaritiesOverride = savedRarities
	currentRoom.ForceLootName        = savedLootName
	currentRoom.RewardOverrides      = savedOverrides

	if reward == nil or reward.ObjectId == nil then
		ProvokeMod.Log.error( "fields", "SpawnRoomReward returned nil", {
			choiceType = choiceType,
			rewardOverride = rewardOverride,
		} )
		-- Best-effort cleanup: drop the orphaned cage so we don't strand it.
		Destroy({ Id = cage.ObjectId })
		return nil
	end

	-- 3. Wire the cage to the reward, lock the reward until combat clears.
	cage.RewardId = reward.ObjectId
	UseableOff({ Id = cage.RewardId })
	ProvokeMod.Log.debug( "fields", "reward spawned + locked", {
		rewardId = reward.ObjectId,
		override = rewardOverride,
		lootName = lootName,
	} )

	-- 4. Destroy the original pickup now that the cage is anchored.
	Destroy({ Id = pickupId })

	-- 5. Pre-roll the fear injection now (so the over-capacity filter can see
	-- the committed Fear cost and the StartFieldsEncounter wrap has a concrete
	-- injection to apply when the player triggers the cage).
	local injection = ProvokeMod.SelectThemedVows( fearCost )

	-- 6. Bookkeeping: track the provocation and advance the greed counter so
	-- subsequent provocations in this run cost the escalating amount.
	ProvokeMod.RunState.ProvokedCages = ProvokeMod.RunState.ProvokedCages or {}
	ProvokeMod.RunState.ProvokedCages[cage.ObjectId] = {
		ChoiceType  = choiceType,
		FearCost    = fearCost,
		Injection   = injection,
		RewardId    = reward.ObjectId,
		Cage        = cage,
		FearApplied = false,
	}
	ProvokeMod.RunState.ProvocationCount = (ProvokeMod.RunState.ProvocationCount or 0) + 1
	ProvokeMod.RunState.ProvokedCounts[choiceType] =
		(ProvokeMod.RunState.ProvokedCounts[choiceType] or 0) + 1

	ProvokeMod.Log.info( "fields", "transform complete", {
		cageId           = cage.ObjectId,
		rewardId         = reward.ObjectId,
		choiceType       = choiceType,
		fearCost         = fearCost,
		provocationCount = ProvokeMod.RunState.ProvocationCount,
	} )

	return cage
end

-- Compute the animation name for a door's new reward icon from LootData.
function ProvokeMod.GetDoorIconAnimName( door )
	local room = door.Room
	if room.ChosenRewardType == "Boon" and room.ForceLootName then
		local lootData = LootData[room.ForceLootName]
		if lootData then
			if room.BoonRaritiesOverride and lootData.DoorUpgradedIcon then
				return lootData.DoorUpgradedIcon
			end
			return lootData.DoorIcon or lootData.Icon
		end
	elseif room.ChosenRewardType == "WeaponUpgrade" then
		local lootData = LootData["WeaponUpgrade"]
		if lootData then
			return lootData.DoorIcon or lootData.Icon
		end
	end
	return nil
end

-- Apply the "cursed" purple tint to a door's reward preview icons when it has
-- been provoked, or reset to neutral white when reverted. Uses the canonical
-- SetColor-on-icon-ids pattern from base RoomPresentation.
function ProvokeMod.UpdateDoorTint( door )
	if door.RewardPreviewIconIds == nil or #door.RewardPreviewIconIds == 0 then
		return
	end
	local isProvoked = ProvokeMod.RunState.ProvokedDoors[door.ObjectId] ~= nil
	local color = isProvoked and { 0.74, 0.63, 1.0, 1.0 } or { 1.0, 1.0, 1.0, 1.0 }
	SetColor({
		Ids      = door.RewardPreviewIconIds,
		Color    = color,
		Duration = 0.2,
	})
end

function ProvokeMod.RefreshDoorPreview( door )
	local newAnimName = ProvokeMod.GetDoorIconAnimName( door )

	-- Prefer in-place update: updating the animation on an existing obstacle preserves
	-- its material/color state set during room init, avoiding the white-silhouette bug.
	if newAnimName and door.RewardPreviewIconIds and #door.RewardPreviewIconIds > 0 then
		for _, iconId in ipairs( door.RewardPreviewIconIds ) do
			SetAnimation({ DestinationId = iconId, Name = newAnimName })
		end
		door.RewardPreviewAnimName = newAnimName
		ProvokeMod.UpdateDoorTint( door )
		return
	end

	-- Fallback: destroy and recreate (handles case where no icons exist yet).
	if door.RewardPreviewIconIds then
		for _, iconId in ipairs( door.RewardPreviewIconIds ) do
			Destroy({ Id = iconId })
		end
		door.RewardPreviewIconIds = nil
	end
	if door.RewardPreviewBackingIds then
		for _, backingId in ipairs( door.RewardPreviewBackingIds ) do
			Destroy({ Id = backingId })
		end
		door.RewardPreviewBackingIds = nil
	end
	if door.AdditionalIcons then
		local iconIds = {}
		for _, iconId in pairs( door.AdditionalIcons ) do
			table.insert( iconIds, iconId )
		end
		if #iconIds > 0 then
			Destroy({ Ids = iconIds })
		end
		door.AdditionalIcons = nil
	end
	-- Pass explicit params so the Boon branch condition (chosenLootName ~= nil) is satisfied.
	CreateDoorRewardPreview( door, door.Room.ChosenRewardType, door.Room.ForceLootName )
	ProvokeMod.UpdateDoorTint( door )
end

-- ============================================================================
-- Section 5: Provocation Choice Screen
-- ============================================================================

-- Shared palette so the two provocation screens read as siblings and match
-- the vanilla Mythmaker-family prompts (ElementalPromptScreenData.lua,
-- StoryResetData.lua, MetaUpgradeCardPromptScreenData.lua) which all use
-- MythmakerBoxDefault + plain ButtonDefault buttons, not BoonSlot assets.
ProvokeMod.UI = {
	Violet         = { 0.74, 0.63, 1.0, 1.0 },  -- title / cost / theme accent
	PaleLavender   = { 0.82, 0.75, 1.0, 0.9 },  -- preview line
	MutedLavender  = { 0.75, 0.70, 0.85, 0.9 }, -- subtitle / body
	CurrentAmber   = { 1.0,  0.88, 0.55, 1.0 }, -- "CURRENT" badge on re-provoke
	GreyText       = { 0.7,  0.7,  0.7,  0.9 }, -- dismissive secondary button
	DustyRose      = { 0.85, 0.65, 0.65, 0.9 }, -- "Revert to Original" button
	-- Mythmaker-prompt title styling: heavy black outline + deep-black shadow.
	-- Matches ElementalPromptScreenData.lua:44-49.
	MythmakerTitleShadow  = { 0.05, 0.04, 0.04, 1.0 },
	MythmakerTitleOutline = { 0.11, 0.10, 0.09, 1.0 },
	-- Per-choice-type colors (title accent) live in ProvokeMod.ChoiceTypes[*].UIColor
	-- so the registry is the single source of truth. Rarity-tier backing
	-- animations (BoonSlotRare / BoonSlotEpic / BoonSlotLegendary) are keyed
	-- off each entry's Rarity field via screen.RarityBackingAnimations.
}

-- Shown in place of the choice menu when every eligible vow is already at its
-- native max rank. Minimal dialog: header + dismiss. No cost, no state change.
function ProvokeMod.OpenFatesSatisfiedScreen()
	if IsScreenOpen( "FatesSatisfiedScreen" ) then return end

	local screen = { Components = {}, Name = "FatesSatisfiedScreen" }
	OnScreenOpened( screen )

	local menuY = ScreenCenterY + 25

	-- Same full-screen dim as the main provocation screen — the two dialogs
	-- stay siblings by sharing the backdrop rather than a shared frame asset.
	screen.Components.BackgroundTint = CreateScreenComponent({
		Name  = "rectangle01",
		Group = "Combat_Menu_TraitTray_Backing",
		X     = ScreenCenterX,
		Y     = ScreenCenterY,
	})
	SetScale({ Id = screen.Components.BackgroundTint.Id, Fraction = 10 })
	SetColor({ Id = screen.Components.BackgroundTint.Id, Color = { 0, 0, 0, 0.72 } })

	-- Header: title + body as offset text boxes on one component, same
	-- typography as the main provocation screen.
	screen.Components.Header = CreateScreenComponent({
		Name  = "BlankObstacle",
		Group = "Combat_Menu_TraitTray",
		X     = ScreenCenterX,
		Y     = menuY - 60,
	})
	CreateTextBox({
		Id               = screen.Components.Header.Id,
		Text             = "Your Resolve Falters",
		FontSize         = 28,
		Color            = ProvokeMod.UI.Violet,
		Font             = "P22UndergroundSCMedium",
		ShadowBlur       = 0,
		ShadowColor      = ProvokeMod.UI.MythmakerTitleShadow,
		ShadowOffset     = { 0, 4 },
		OutlineThickness = 4,
		OutlineColor     = ProvokeMod.UI.MythmakerTitleOutline,
		Justification    = "Center",
	})
	CreateTextBox({
		Id               = screen.Components.Header.Id,
		Text             = "You have not the power to compel the Fates further.",
		OffsetY          = 40,
		FontSize         = 16,
		Color            = ProvokeMod.UI.MutedLavender,
		Font             = "P22UndergroundSCMedium",
		ShadowBlur       = 0,
		ShadowColor      = ProvokeMod.UI.MythmakerTitleShadow,
		ShadowOffset     = { 0, 3 },
		OutlineThickness = 2,
		OutlineColor     = ProvokeMod.UI.MythmakerTitleOutline,
		Justification    = "Center",
	})

	screen.Components.Dismiss = CreateScreenComponent({
		Name  = "ButtonDefault",
		Group = "Combat_Menu_TraitTray",
		X     = ScreenCenterX,
		Y     = menuY + 60,
	})
	SetScaleX({ Id = screen.Components.Dismiss.Id, Fraction = 1.0 })
	screen.Components.Dismiss.OnPressedFunctionName = "ProvokeMod__OnFatesSatisfiedDismiss"
	screen.Components.Dismiss.Screen        = screen
	screen.Components.Dismiss.ControlHotkeys = { "Cancel", "Confirm" }
	CreateTextBox({
		Id               = screen.Components.Dismiss.Id,
		Text             = "Dismiss",
		FontSize         = 18,
		Color            = ProvokeMod.UI.GreyText,
		Font             = "P22UndergroundSCMedium",
		ShadowBlur       = 0,
		ShadowColor      = ProvokeMod.UI.MythmakerTitleShadow,
		ShadowOffset     = { 0, 3 },
		OutlineThickness = 2,
		OutlineColor     = ProvokeMod.UI.MythmakerTitleOutline,
		Justification    = "Center",
	})

	TeleportCursor({ DestinationId = screen.Components.Dismiss.Id, ForceUseCheck = true })

	HandleScreenInput( screen )
end

game.ProvokeMod__OnFatesSatisfiedDismiss = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuBack" })
	OnScreenCloseStarted( screen )
	CloseScreen( GetAllIds( screen.Components ), 0.1, screen )
	OnScreenCloseFinished( screen )
end

-- Collect every registered ChoiceType that could legally appear on this
-- provoke: skip cage-incompatible types when provoking a Fields pickup, skip
-- anything whose Fear cost exceeds the remaining pool, and skip anything
-- whose IsEligible gate fails (e.g. Selene locked, no upgradable boon for
-- Pom). Returns a list of { key, choiceType, entry, cost, weight } records.
function ProvokeMod.BuildChoicePool( run, room, isPickup, poolCapacity, nextPosition )
	local pool    = {}
	local skipped = {}
	for key, entry in pairs( ProvokeMod.ChoiceTypes ) do
		local cost   = ProvokeMod.GetFearCost( key, nextPosition )
		local reason = nil
		if isPickup and not entry.SupportsCage then
			reason = "no_cage_support"
		elseif cost > poolCapacity then
			reason = "over_capacity"
		elseif entry.IsEligible and not entry.IsEligible( run, room ) then
			reason = "ineligible"
		end
		if reason == nil then
			local weight = config[entry.WeightKey] or entry.WeightDefault or 1
			table.insert( pool, {
				key        = key,
				choiceType = key,
				entry      = entry,
				cost       = cost,
				weight     = weight,
			})
		else
			skipped[key] = reason
		end
	end
	if next( skipped ) ~= nil then
		ProvokeMod.Log.debug( "provoke", "pool_skipped_entries", skipped )
	end
	return pool
end

-- Weighted random sample without replacement, via Efraimidis–Spirakis:
-- each item gets a key = random^(1 / weight), and the top-n items by key
-- are the unbiased weighted sample. Zero / negative weights are dropped.
-- When n >= #pool, all surviving items are returned in randomized order
-- (so menu layout is shuffled across reopens even when the pool is full).
function ProvokeMod.SampleChoices( pool, n )
	if pool == nil or #pool == 0 or n <= 0 then return {} end
	local keyed = {}
	for _, item in ipairs( pool ) do
		local w = item.weight or 1
		if w > 0 then
			local u = RandomFloat( 0.0, 1.0 )
			if u <= 0 then u = 1e-9 end
			local key = u ^ (1.0 / w)
			table.insert( keyed, { item = item, key = key } )
		end
	end
	table.sort( keyed, function( a, b ) return a.key > b.key end )
	local out = {}
	local k = math.min( n, #keyed )
	for i = 1, k do out[i] = keyed[i].item end
	return out
end

-- Build one choice row. Matches vanilla boon-pickup structure: a BoonSlotBase
-- button with rarity-tier backing, a Highlight overlay layered on top so it
-- reads as an edge-glow rather than an occluded backdrop, an Icon on the
-- far-left, and attached title / cost / duration / penalty-description text
-- boxes. AttachLua on both slot and highlight is critical — without it the
-- engine's mouseover dispatch can't find the Lua table.
local function buildChoiceRow( screen, key, params )
	local itemLocationX = ScreenCenterX - 355 + screen.ButtonOffsetX
	local itemLocationY = (ScreenCenterY - 190) + screen.ButtonSpacingY * ( params.Index - 1 )

	-- Slot first so the highlight we spawn next renders on top of it instead
	-- of behind (components spawned later layer above earlier ones in the
	-- same Group).
	local slot = CreateScreenComponent({
		Name  = "BoonSlotBase",
		Group = screen.ComponentData.DefaultGroup,
		X     = itemLocationX,
		Y     = itemLocationY,
	})
	SetAnimation({ Name = screen.RarityBackingAnimations[params.Rarity], DestinationId = slot.Id })
	AttachLua({ Id = slot.Id, Table = slot })
	slot.OnPressedFunctionName   = "ProvokeMod__OnSelectChoice"
	slot.OnMouseOverFunctionName = "ProvokeMod__OnCardMouseOver"
	slot.OnMouseOffFunctionName  = "ProvokeMod__OnCardMouseOff"
	slot.Door           = params.Door
	slot.IsFieldsPickup = params.IsFieldsPickup or false
	slot.Screen         = screen
	slot.ChoiceType     = params.ChoiceType
	screen.Components[key] = slot

	-- Highlight overlay — match ShrineLogic.lua:81-88: pre-load the highlight
	-- animation on a BlankObstacle at Alpha 0, then toggle alpha on hover.
	-- Pre-loading matters — creating an empty BlankObstacle and calling
	-- SetAnimation after-the-fact doesn't bind the animation properly.
	local highlight = CreateScreenComponent({
		Name      = "BlankObstacle",
		Group     = screen.ComponentData.DefaultGroup,
		X         = itemLocationX,
		Y         = itemLocationY,
		Animation = "BoonSlotHighlight",
		Alpha     = 0.0,
	})
	AttachLua({ Id = highlight.Id, Table = highlight })
	highlight.Screen = screen
	screen.Components[key .. "Highlight"] = highlight
	slot.Highlight = highlight

	-- Icon on the far-left of the slot. Vanilla places boon icons here via
	-- screen.IconOffsetX / IconOffsetY (UpgradeChoiceData.lua:39-40). Optional
	-- IconOverlayAnim spawns a second BlankObstacle at the same coordinates
	-- so we can layer effects like BoonUpgradedPreviewSparkles on top of the
	-- base drop — the same way vanilla composes BoonDropZeusUpgradedPreview
	-- (Items_General_VFX.sjson defines it as BoonDropZeusPreview +
	-- ChildAnimation = "BoonUpgradedPreviewSparkles").
	if params.IconAnim then
		local icon = CreateScreenComponent({
			Name  = "BlankObstacle",
			Group = screen.ComponentData.DefaultGroup,
			X     = itemLocationX + screen.IconOffsetX,
			Y     = itemLocationY + screen.IconOffsetY,
			Scale = 0.6,
		})
		SetAnimation({ Name = params.IconAnim, DestinationId = icon.Id })
		screen.Components[key .. "Icon"] = icon

		if params.IconOverlayAnim then
			local overlay = CreateScreenComponent({
				Name  = "BlankObstacle",
				Group = screen.ComponentData.DefaultGroup,
				X     = itemLocationX + screen.IconOffsetX,
				Y     = itemLocationY + screen.IconOffsetY,
				Scale = 0.6,
			})
			SetAnimation({ Name = params.IconOverlayAnim, DestinationId = overlay.Id })
			screen.Components[key .. "IconOverlay"] = overlay
		end
	end

	-- Title (upper-left area of slot, matching vanilla TitleText offset).
	CreateTextBox({
		Id            = slot.Id,
		Text          = params.Title,
		OffsetX       = -420,
		OffsetY       = -60,
		FontSize      = 27,
		Color         = params.TitleColor,
		Font          = "P22UndergroundSCMedium",
		ShadowBlur    = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
		Justification = "Left",
	})

	-- Cost (upper-right area, matching vanilla RarityText / CostText offset).
	CreateTextBox({
		Id            = slot.Id,
		Text          = "+" .. tostring( params.Cost ) .. " Fear",
		OffsetX       = 410,
		OffsetY       = -60,
		FontSize      = 28,
		Color         = ProvokeMod.UI.Violet,
		Font          = "P22UndergroundSCMedium",
		ShadowBlur    = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
		Justification = "Right",
	})

	-- Duration directly under the cost badge so the price tag reads as
	-- "+N Fear / M rooms" — the two numbers that define the trade.
	if params.Duration then
		local encountersText = params.Duration == 1 and "1 encounter" or (tostring( params.Duration ) .. " encounters")
		CreateTextBox({
			Id            = slot.Id,
			Text          = "Lasts " .. encountersText,
			OffsetX       = 410,
			OffsetY       = -28,
			FontSize      = 17,
			Color         = ProvokeMod.UI.MutedLavender,
			Font          = "LatoMedium",
			ShadowBlur    = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
			Justification = "Right",
		})
	end

	-- Penalty description. Width 830 wraps long injections onto two lines.
	-- Intro "Fates demand: " prefixes the vow list so the player immediately
	-- reads this as the cost-side copy, not the reward copy.
	CreateTextBox({
		Id                    = slot.Id,
		Text                  = "Fates demand: " .. params.Preview,
		OffsetX               = -420,
		OffsetY               = -20,
		Width                 = 830,
		LineSpacingBottom     = 5,
		FontSize              = 20,
		Color                 = { 0.92, 0.86, 1.0, 1.0 },
		Font                  = "LatoMedium",
		ShadowBlur            = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
		Justification         = "Left",
		VerticalJustification = "Top",
	})

	-- CURRENT badge — bottom-right on re-provoke to flag the active choice.
	if params.IsCurrent then
		CreateTextBox({
			Id            = slot.Id,
			Text          = "CURRENT",
			OffsetX       = 410,
			OffsetY       = 65,
			FontSize      = 17,
			Color         = ProvokeMod.UI.CurrentAmber,
			Font          = "P22UndergroundSCHeavy",
			ShadowBlur    = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
			Justification = "Right",
		})
	end

	return slot
end

function ProvokeMod.OpenProvocationScreen( door )
	if IsScreenOpen( "ProvokeFatesScreen" ) or IsScreenOpen( "FatesSatisfiedScreen" ) then
		return
	end

	-- Fix 4b: distinguish door-style targets (which support re-provoke via the
	-- ProvokedDoors table) from Fields pickups (one-shot: pickup destroyed and
	-- replaced with a cage on commit, no re-approach possible).
	local isFieldsPickup = ProvokeMod.IsProvokableFieldsPickup( door )

	local existingData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	local isReprovoke = (not isFieldsPickup) and existingData ~= nil and existingData.Provoked == true
	local currentChoiceType = isReprovoke and existingData.ChoiceType or nil

	-- Total ranks the eligible-vow pool can still absorb. Any option whose
	-- cost exceeds this would silently leak Fear, so we filter those out of
	-- the menu entirely below.
	local poolCapacity = 0
	for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
		local current = GameState.ShrineUpgrades[vowName] or 0
		local maxRank = ProvokeMod.GetVowMaxRank( vowName )
		poolCapacity = poolCapacity + math.max( 0, maxRank - current )
	end

	-- Subtract Fear already reserved by active stacks (from prior rooms) and
	-- by provoked Fields cages that haven't fired yet (current room). At door-
	-- interaction time, GameState.ShrineUpgrades is back to baseline
	-- (RestoreVowsOnly ran at the previous combat's end) but those pending
	-- Fear costs will re-apply in the upcoming combat rooms / cage encounters
	-- on top of any new provocation. Without this subtraction the filter
	-- would happily let a second provocation stack past pool capacity and
	-- silently leak the overflow.
	local activeFearTotal = 0
	for _, stack in ipairs( ProvokeMod.RunState.ActiveFearStacks or {} ) do
		activeFearTotal = activeFearTotal + (stack.FearCost or 0)
	end
	for _, cageData in pairs( ProvokeMod.RunState.ProvokedCages or {} ) do
		if not cageData.FearApplied then
			activeFearTotal = activeFearTotal + (cageData.FearCost or 0)
		end
	end
	if activeFearTotal > 0 then
		local rawCapacity = poolCapacity
		poolCapacity = math.max( 0, poolCapacity - activeFearTotal )
		ProvokeMod.Log.info( "provoke", "capacity_adjusted", {
			rawCapacity     = rawCapacity,
			activeFearTotal = activeFearTotal,
			poolCapacity    = poolCapacity,
		} )
	end

	-- Greed tracks total provocations in the run, so every choice shares the
	-- same next-slot position. On re-provoke the selection reverts-then-adds
	-- (ProvocationCount unchanged) so the new choice occupies the same slot.
	local totalCount = ProvokeMod.RunState.ProvocationCount or 0
	local nextPosition = isReprovoke and math.max( 1, totalCount ) or (totalCount + 1)

	-- Build the filtered pool of eligible choices — per-type cost, cage
	-- compatibility, and IsEligible predicates all apply here. The pool is
	-- then sampled (weighted, no replacement) to populate the menu rows.
	local pool = ProvokeMod.BuildChoicePool(
		CurrentRun, door.Room, isFieldsPickup, poolCapacity, nextPosition
	)

	-- Early gate: if a fresh provoke produced no viable choices, short-circuit
	-- to the Fates-Satisfied rejection BEFORE spawning any screen scaffolding.
	-- Re-provoke always renders (so the player can Revert / Keep Choice even
	-- when nothing else fits).
	if #pool == 0 and not isReprovoke then
		ProvokeMod.Log.info( "provoke", "blocked: no choice fits pool", {
			objectId     = door.ObjectId,
			poolCapacity = poolCapacity,
		} )
		ProvokeMod.OpenFatesSatisfiedScreen()
		return
	end

	-- Sample up to 3 rows from the pool, weighted without replacement.
	-- Reopening the screen builds fresh pool + sample, so every reopen rerolls.
	local sampleSize = 3
	local sampled    = ProvokeMod.SampleChoices( pool, sampleSize )

	-- On re-provoke, guarantee the current choice stays in the sample so
	-- Revert / Keep Choice has a reliable home even if sampling displaced it.
	-- Inject it at position 1 (displacing the first sampled entry) when
	-- missing. When the sample already contains it, leave position as-is so
	-- the CURRENT badge can appear wherever sampling placed it.
	if isReprovoke and currentChoiceType ~= nil then
		local present = false
		for _, item in ipairs( sampled ) do
			if item.choiceType == currentChoiceType then present = true; break end
		end
		if not present then
			local entry = ProvokeMod.ChoiceTypes[currentChoiceType]
			if entry ~= nil then
				local pinned = {
					key        = currentChoiceType,
					choiceType = currentChoiceType,
					entry      = entry,
					cost       = ProvokeMod.GetFearCost( currentChoiceType, nextPosition ),
					weight     = config[entry.WeightKey] or entry.WeightDefault or 1,
				}
				if #sampled > 0 then table.remove( sampled, 1 ) end
				table.insert( sampled, 1, pinned )
			end
		end
	end

	-- Clone the vanilla boon-pickup screen definition and keep every backdrop
	-- component vanilla uses (OlympusBackground, ShopBackgroundDim, Shop-
	-- BackgroundGradient, ShopBackground with the Melinoe silhouette, Shop-
	-- Lighting, SourceIcon, ActionBarBackground, TitleText, FlavorText) so the
	-- screen reads 1:1 with how a boon pickup looks. Only strip the
	-- interaction-only components we can't drive without a real loot flow
	-- (RerollIcon, the side action bars) and supply a generic BackgroundAnimation
	-- + violet lighting tint for the source-dependent bits vanilla would
	-- normally get from the god's LootData entry.
	local screen = DeepCopyTable( ScreenData.UpgradeChoice )
	screen.Name = "ProvokeFatesScreen"
	-- Generic god backdrop. "DialogueBackground_Olympus_BoonScreen" is the
	-- fallback the base LootData entry ships with (LootData.lua:38), so every
	-- god's boon menu inherits it if nothing more specific is set.
	screen.ComponentData.OlympusBackground.AnimationName = "DialogueBackground_Olympus_BoonScreen"
	-- Drop the interaction widgets we don't use — no reroll pane, no vanilla
	-- action-bar buttons (we build our own Cancel / Revert below).
	screen.ComponentData.RerollIcon    = nil
	screen.ComponentData.ActionBarLeft = nil
	screen.ComponentData.ActionBar     = nil

	-- Resolve the vow injection each sampled button will commit to, so the
	-- preview text shown matches what actually lands. Keyed by choiceType.
	screen.PreviewedInjections = {}
	for _, item in ipairs( sampled ) do
		screen.PreviewedInjections[item.choiceType] = ProvokeMod.SelectThemedVows( item.cost )
	end

	OnScreenOpened( screen )
	CreateScreenFromData( screen, screen.ComponentData )

	-- Post-spawn color tints exactly the way vanilla OpenUpgradeChoiceMenu
	-- applies source.LightingColor after CreateScreenFromData. Violet here
	-- matches the Fates/Oath theme the mod is built around.
	local lightingColor = ProvokeMod.UI.Violet
	if screen.Components.ShopLighting then
		SetColor({ Id = screen.Components.ShopLighting.Id, Color = lightingColor })
	end
	if screen.Components.ShopLightingMelFace then
		SetColor({ Id = screen.Components.ShopLightingMelFace.Id, Color = lightingColor })
	end
	if screen.Components.ShopBackgroundGradient then
		SetColor({ Id = screen.Components.ShopBackgroundGradient.Id, Color = lightingColor })
	end

	-- SourceIcon is the symbol "Melinoe is holding" in the ShopBackground
	-- sprite. Vanilla sets it to the offering god's Icon; we don't have a
	-- god, so we use MetaFabricDrop — the 60-frame Fate Fabric animation
	-- (Items_General_VFX.sjson, backed by Items\Resources\Common\MetaFabric).
	-- The fabric is literally what the Fates weave, so it reads as "this is
	-- the Fates' offering" in a way no single god's icon can.
	if screen.Components.SourceIcon then
		SetAnimation({ Name = "MetaFabricDrop", DestinationId = screen.Components.SourceIcon.Id })
	end

	-- Replace vanilla placeholder text with our ritual copy.
	ModifyTextBox({ Id = screen.Components.TitleText.Id, Text = "Provoke the Fates" })
	ModifyTextBox({
		Id = screen.Components.FlavorText.Id,
		Text = isReprovoke
			and "Change your choice, or revert the door."
			or  "Upgrade this reward. The Fates will retaliate.",
	})

	local sampledKeys = {}
	for _, item in ipairs( sampled ) do
		table.insert( sampledKeys, item.key .. "=" .. tostring( item.cost ) )
	end
	ProvokeMod.Log.info( "provoke", "open screen", {
		objectId      = door.ObjectId,
		isReprovoke   = isReprovoke,
		currentChoice = currentChoiceType or "none",
		poolSize      = #pool,
		sampled       = table.concat( sampledKeys, "," ),
		poolCapacity  = poolCapacity,
	} )

	local function buildPreviewLine( injection )
		if injection == nil then return "(no vow can absorb)" end
		local parts = {}
		for vowName, ranks in pairs( injection ) do
			local baseline = GameState.ShrineUpgrades[vowName] or 0
			table.insert( parts, ProvokeMod.GetVowValueText( vowName, {
				OriginalRank = baseline,
				AddedRanks   = ranks,
			}) )
		end
		if #parts == 0 then return "(no effect)" end
		table.sort( parts )
		return table.concat( parts, ",  " )
	end

	-- Up to 3 BoonSlotBase rows at vanilla positions. Entries come from the
	-- sampler; title / rarity / icon all source from the registry.
	screen.KeepOpen = true
	screen.UpgradeButtons = {}

	-- Duration matches QueueFearStack's formula: base from config.Duration_*,
	-- plus one extra room per prior provocation when GreedExtendsDuration is
	-- on. nextPosition is the 1-indexed slot this provocation will occupy, so
	-- the extension is (nextPosition - 1) — identical to what the stack will
	-- actually queue with if the player commits to that option.
	local greedExtension = config.GreedExtendsDuration and math.max( 0, nextPosition - 1 ) or 0

	-- Build the per-row config list from the sampled pool entries.
	local visibleConfigs = {}
	for _, item in ipairs( sampled ) do
		local entry    = item.entry
		local duration = (config[entry.DurationKey] or entry.DurationDefault or 1) + greedExtension
		table.insert( visibleConfigs, {
			key             = item.key,
			choiceType      = item.choiceType,
			title           = entry.Title,
			cost            = item.cost,
			duration        = duration,
			rarity          = entry.Rarity,
			iconAnim        = entry.IconAnim,
			iconOverlayAnim = entry.IconOverlayAnim,
		})
	end

	for i, choice in ipairs( visibleConfigs ) do
		screen.UpgradeButtons[i] = buildChoiceRow( screen, choice.key, {
			Index           = i,
			Door            = door,
			IsFieldsPickup  = isFieldsPickup,
			ChoiceType      = choice.choiceType,
			Title           = choice.title,
			TitleColor      = ProvokeMod.ChoiceTypes[choice.choiceType].UIColor,
			Cost            = choice.cost,
			Duration        = choice.duration,
			Preview         = buildPreviewLine( screen.PreviewedInjections[choice.choiceType] ),
			IsCurrent       = (currentChoiceType == choice.choiceType),
			Rarity          = choice.rarity,
			IconAnim        = choice.iconAnim,
			IconOverlayAnim = choice.iconOverlayAnim,
		})
	end

	-- Secondary buttons below the last boon row. Place absolutely near screen
	-- bottom so they stay on-screen regardless of how many slots spawned
	-- (vanilla's stride of 256 x 3 slots drops the third row at Y ≈ 862, so
	-- Y = 1010 clears it with ~100px of margin on 1080p).
	local secondaryY = 1010

	if isReprovoke then
		screen.Components.Revert = CreateScreenComponent({
			Name  = "ButtonDefault",
			Group = "Combat_Menu_TraitTray",
			X     = ScreenCenterX,
			Y     = secondaryY,
		})
		SetScaleX({ Id = screen.Components.Revert.Id, Fraction = 1.0 })
		screen.Components.Revert.OnPressedFunctionName = "ProvokeMod__OnRevert"
		screen.Components.Revert.Door   = door
		screen.Components.Revert.Screen = screen
		AttachLua({ Id = screen.Components.Revert.Id, Table = screen.Components.Revert })
		CreateTextBox({
			Id               = screen.Components.Revert.Id,
			Text             = "Revert to Original",
			FontSize         = 17,
			Color            = ProvokeMod.UI.DustyRose,
			Font             = "P22UndergroundSCMedium",
			ShadowBlur       = 0,
			ShadowColor      = ProvokeMod.UI.MythmakerTitleShadow,
			ShadowOffset     = { 0, 3 },
			OutlineThickness = 2,
			OutlineColor     = ProvokeMod.UI.MythmakerTitleOutline,
			Justification    = "Center",
		})
		secondaryY = secondaryY + 54
	end

	screen.Components.Cancel = CreateScreenComponent({
		Name  = "ButtonDefault",
		Group = "Combat_Menu_TraitTray",
		X     = ScreenCenterX,
		Y     = secondaryY,
	})
	SetScaleX({ Id = screen.Components.Cancel.Id, Fraction = 1.1 })
	screen.Components.Cancel.OnPressedFunctionName = "ProvokeMod__OnCancel"
	screen.Components.Cancel.Screen        = screen
	screen.Components.Cancel.ControlHotkeys = { "Cancel", "Confirm" }
	AttachLua({ Id = screen.Components.Cancel.Id, Table = screen.Components.Cancel })
	CreateTextBox({
		Id               = screen.Components.Cancel.Id,
		Text             = isReprovoke and "Keep Choice" or "Don't Provoke",
		FontSize         = 19,
		Color            = ProvokeMod.UI.GreyText,
		Font             = "P22UndergroundSCMedium",
		ShadowBlur       = 0,
		ShadowColor      = ProvokeMod.UI.MythmakerTitleShadow,
		ShadowOffset     = { 0, 3 },
		OutlineThickness = 2,
		OutlineColor     = ProvokeMod.UI.MythmakerTitleOutline,
		Justification    = "Center",
	})

	-- Vanilla "back button" widget below the Cancel button — same graphic
	-- the Mythmaker prompts (ElementalPromptScreenData.lua:77) use as their
	-- close affordance. Drawn as a BlankObstacle with the ShellButtonBack
	-- animation so it reads as an actual button icon, not text.
	screen.Components.CancelGlyph = CreateScreenComponent({
		Name  = "BlankObstacle",
		Group = "Combat_Menu_TraitTray",
		X     = ScreenCenterX,
		Y     = secondaryY + 48,
	})
	SetAnimation({ Name = "ShellButtonBack", DestinationId = screen.Components.CancelGlyph.Id })
	SetScale({ Id = screen.Components.CancelGlyph.Id, Fraction = 0.75 })

	-- Park the cursor on the safe-dismiss button so an accidental Confirm on
	-- screen-open doesn't spend Fear. Pattern from BoonInfoLogic.lua:27.
	TeleportCursor({ DestinationId = screen.Components.Cancel.Id, ForceUseCheck = true })

	HandleScreenInput( screen )
end

function ProvokeMod.CloseProvocationScreen( screen )
	OnScreenCloseStarted( screen )
	CloseScreen( GetAllIds( screen.Components ), 0.1, screen )
	OnScreenCloseFinished( screen )
end

-- ============================================================================
-- Section 6: Global Button Handlers
-- ============================================================================
-- These must be accessible via CallFunctionName (game global scope).
-- Since ENVY scopes our globals to the plugin, we register them on the game table.

game.ProvokeMod__OnSelectChoice = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	local target = button.Door
	ProvokeMod.Log.info( "provoke", "select choice", {
		choiceType = button.ChoiceType,
		objectId   = target and target.ObjectId,
		isPickup   = button.IsFieldsPickup or false,
	} )

	-- Fields pickup commit: destroy the consumable in place, spawn a
	-- FieldsRewardCage wrapping the upgraded reward, then immediately fire
	-- StartFieldsEncounter on the new cage so combat starts now — matching
	-- the door-provoke flow where picking a choice auto-proceeds into the
	-- fight instead of leaving the player to walk back to the interactable.
	-- Threaded so the menu fade-out doesn't overlap with enemy spawning.
	if button.IsFieldsPickup then
		ProvokeMod.CloseProvocationScreen( screen )
		local cage = ProvokeMod.TransformFieldsPickup( target, button.ChoiceType )
		if cage ~= nil then
			thread( StartFieldsEncounter, cage )
		end
		return
	end

	local existingData = ProvokeMod.RunState.ProvokedDoors[target.ObjectId]
	if existingData and existingData.Provoked then
		ProvokeMod.UnTransformDoor( target )
	end
	local injection = screen.PreviewedInjections and screen.PreviewedInjections[button.ChoiceType]
	ProvokeMod.TransformDoor( target, button.ChoiceType, injection )
	ProvokeMod.CloseProvocationScreen( screen )
	-- Auto-proceed: skip AttemptUseDoor (its pre-LeaveRoom setup already ran on
	-- the initial press), call LeaveRoom directly. Our LeaveRoom wrap re-enters
	-- but IsControlDown is false (Confirm was pressed, not Use/Interact), so the
	-- hold-gate branch is skipped and we fall through to the provoked-door path.
	thread( LeaveRoom, CurrentRun, target )
end

game.ProvokeMod__OnCancel = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuBack" })
	ProvokeMod.CloseProvocationScreen( screen )
end

game.ProvokeMod__OnRevert = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuBack" })
	ProvokeMod.UnTransformDoor( button.Door )
	ProvokeMod.CloseProvocationScreen( screen )
end

-- Hover highlight for the boon-style choice rows. The MouseOver callback
-- signature is `function(component)` (UpgradeChoiceLogic.lua:1345). We match
-- ShrinePresentation.lua:143 exactly: SetAlpha the pre-loaded highlight to
-- 1 on hover, 0 on exit, with a brief tween so it fades smoothly.
game.ProvokeMod__OnCardMouseOver = function( component )
	if component == nil then return end
	PlaySound({ Name = "/SFX/Menu Sounds/GodBoonMenuToggle", Id = component.Id })
	if component.Highlight and component.Highlight.Id then
		SetAlpha({ Id = component.Highlight.Id, Fraction = 1.0, Duration = 0.1 })
	end
end

game.ProvokeMod__OnCardMouseOff = function( component )
	if component == nil then return end
	if component.Highlight and component.Highlight.Id then
		SetAlpha({ Id = component.Highlight.Id, Fraction = 0.0, Duration = 0.1 })
	end
end

-- ============================================================================
-- Section 7: Room Entry/Exit Fear Management
-- ============================================================================

-- Centered banner: "The Fates are Provoked  (+N Fear)" with the list of vow
-- effects cascading below it, fading out after a few seconds. Shared between
-- OnRoomStart (door-fear landing on room entry) and ApplyCageFear (cage-fear
-- landing mid-room when the player triggers a provoked cage). `roomRef` is
-- captured so the cleanup thread can bail if the player left the room early.
function ProvokeMod.ShowFearBanner( totalRanks, vowLines, roomRef )
	if totalRanks == nil or totalRanks <= 0 then return end

	local banner = CreateScreenComponent({
		Name = "BlankObstacle",
		Group = "Combat_Menu_TraitTray_Overlay",
		X = ScreenCenterX,
		Y = 128,
	})
	CreateTextBox({
		Id = banner.Id,
		Text = "The Fates are Provoked  (+" .. totalRanks .. " Fear)",
		FontSize = 26,
		Color = { 0.74, 0.63, 1.0, 1.0 },
		Font = "P22UndergroundSCHeavy",
		ShadowBlur = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 3 },
		Justification = "Center",
		OutlineThickness = 2,
		OutlineColor = { 0, 0, 0, 1 },
	})

	local bannerRoom = roomRef
	thread( function()
		local allIds = { banner.Id }
		local lineY = 160

		wait( 0.6 )
		for _, lineText in ipairs( vowLines or {} ) do
			local line = CreateScreenComponent({
				Name = "BlankObstacle",
				Group = "Combat_Menu_TraitTray_Overlay",
				X = ScreenCenterX,
				Y = lineY,
			})
			CreateTextBox({
				Id = line.Id,
				Text = lineText,
				FontSize = 18,
				Color = { 0.85, 0.78, 1.0, 0.9 },
				Font = "P22UndergroundSCMedium",
				ShadowBlur = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 2 },
				Justification = "Center",
				OutlineThickness = 1,
				OutlineColor = { 0, 0, 0, 1 },
			})
			table.insert( allIds, line.Id )
			lineY = lineY + 24
			wait( 0.15 )
		end

		wait( 3.0 )
		-- If the room changed during the wait, the IDs are already destroyed by
		-- the room transition. Skip cleanup to avoid operating on stale/reused IDs.
		if CurrentRun and CurrentRun.CurrentRoom ~= bannerRoom then
			return
		end
		for _, id in ipairs( allIds ) do
			ModifyTextBox({ Id = id, FadeTarget = 0, FadeDuration = 0.5 })
		end
		wait( 0.5 )
		if CurrentRun and CurrentRun.CurrentRoom ~= bannerRoom then
			return
		end
		for _, id in ipairs( allIds ) do
			Destroy({ Id = id })
		end
	end)
end

-- Called from StartRoom wrap after the room initializes.
-- Fear application has moved to the StartEncounter wrap so that each combat
-- encounter — single-wave, multi-wave, Fields cage — re-injects the
-- accumulated stacks' ranks. OnRoomStart just logs room state and leaves the
-- ShrineUpgrades baseline untouched while the player walks to the fight.
function ProvokeMod.OnRoomStart( currentRun, currentRoom )
	ProvokeMod.LogFearStackState( "room_start" )
	ProvokeMod.Log.info( "room", "start complete", {
		stacks = (ProvokeMod.RunState.ActiveFearStacks and #ProvokeMod.RunState.ActiveFearStacks) or 0,
	} )
end

-- Called from EndEncounterEffects wrap before the base function.
-- Vanilla sets encounter.Completed = true exactly once per real combat
-- encounter (RoomLogic.lua:1921), and EndEncounterEffects fires at that
-- moment — so every combat encounter's end ticks decay once. No room-level
-- "last encounter" gate: Fields rooms with multiple cage combats decrement
-- once per cage, multi-wave rooms decrement once per wave, single-combat
-- rooms decrement once.
function ProvokeMod.OnEncounterEnd( currentRun, currentRoom, currentEncounter )
	local isCombat = ProvokeMod.IsCombatEncounter( currentEncounter )
	ProvokeMod.Log.info( "room", "encounter_end", {
		isCombat      = isCombat,
		encounterType = currentEncounter and currentEncounter.EncounterType,
	} )
	if isCombat then
		-- Combat encounter ended: restore baseline ranks and decay stacks.
		ProvokeMod.RestoreVowsAndDecayStacks()
		ProvokeMod.LogFearStackState( "encounter_end" )
	else
		-- Non-combat encounter (Devotion trial, NPC beat, etc.): scrub any
		-- injected ranks but leave RoomsRemaining untouched so Fear rides
		-- over the filler.
		ProvokeMod.RestoreVowsOnly()
		ProvokeMod.Log.info( "room", "encounter_end_skip_decay", {
			encounterType = currentEncounter and currentEncounter.EncounterType,
			stacks        = (ProvokeMod.RunState.ActiveFearStacks and #ProvokeMod.RunState.ActiveFearStacks) or 0,
		} )
	end
	-- LeaveRoom calls RestoreVowsOnly unconditionally as a final safety net.
end

-- Helper for TableLength since the game may not provide one
function ProvokeMod.TableLength( t )
	local count = 0
	for _ in pairs( t ) do
		count = count + 1
	end
	return count
end

-- Display names for each eligible vow (from English localization)
ProvokeMod.VowDisplayNames = {
	EnemyDamageShrineUpgrade      = "Vow of Pain",
	EnemyHealthShrineUpgrade      = "Vow of Grit",
	EnemyShieldShrineUpgrade      = "Vow of Wards",
	EnemySpeedShrineUpgrade       = "Vow of Frenzy",
	EnemyCountShrineUpgrade       = "Vow of Hordes",
	NextBiomeEnemyShrineUpgrade   = "Vow of Menace",
	EnemyRespawnShrineUpgrade     = "Vow of Return",
	EnemyEliteShrineUpgrade       = "Vow of Fangs",
}

-- printf-style format strings for the numerical effect at the applied rank.
ProvokeMod.VowValueFormats = {
	EnemyDamageShrineUpgrade      = "+%d%% foe damage",
	EnemyHealthShrineUpgrade      = "+%d%% foe health",
	EnemyShieldShrineUpgrade      = "%d shield per foe",
	EnemySpeedShrineUpgrade       = "+%d%% foe speed",
	EnemyCountShrineUpgrade       = "+%d%% more foes",
	NextBiomeEnemyShrineUpgrade   = "%d%% next-biome foes",
	EnemyRespawnShrineUpgrade     = "%d%% respawn chance",
	EnemyEliteShrineUpgrade       = "%d perk(s) on elites",
}

-- Compute the display value for a vow at newRank using its SimpleExtractValues rules.
-- Returns nil if the data is unavailable.
function ProvokeMod.ComputeVowDisplayValue( vowName, newRank )
	local metaData = MetaUpgradeData and MetaUpgradeData[vowName]
	if not metaData or not metaData.Ranks then return nil end

	local maxRank = #metaData.Ranks
	local changeValue

	if newRank <= maxRank then
		local rankData = metaData.Ranks[newRank]
		if not rankData then return nil end
		changeValue = rankData.ChangeValue
	else
		-- Extrapolate linearly above max using the per-rank delta
		local lastData = metaData.Ranks[maxRank]
		if not lastData then return nil end
		local prevData = metaData.Ranks[maxRank - 1]
		local deltaPerRank = prevData and (lastData.ChangeValue - prevData.ChangeValue) or lastData.ChangeValue
		changeValue = lastData.ChangeValue + (newRank - maxRank) * deltaPerRank
	end

	-- Apply SimpleExtractValues arithmetic (Multiply then Add)
	local display = changeValue
	if metaData.SimpleExtractValues then
		local rule = metaData.SimpleExtractValues[1]
		if rule and not rule.UseTimeString then
			if rule.Multiply then display = display * rule.Multiply end
			if rule.Add     then display = display + rule.Add end
		end
	end
	return math.floor( display + 0.5 )
end

-- Return "+Y% description" for one active transient vow entry (no vow title).
function ProvokeMod.GetVowValueText( vowName, vowData )
	local newRank = ( vowData.OriginalRank or 0 ) + ( vowData.AddedRanks or 0 )
	local displayValue = ProvokeMod.ComputeVowDisplayValue( vowName, newRank )

	if displayValue == nil then
		return ProvokeMod.VowDisplayNames[vowName] or vowName
	end

	local fmt = ProvokeMod.VowValueFormats[vowName]
	if fmt then
		return string.format( fmt, displayValue )
	end
	return ProvokeMod.VowDisplayNames[vowName] or vowName
end

-- Build a sorted array of vow effect description strings.
function ProvokeMod.GetVowListText( activeVows )
	local entries = {}
	for vowName, vowData in pairs( activeVows ) do
		table.insert( entries, ProvokeMod.GetVowValueText( vowName, vowData ) )
	end
	table.sort( entries )
	return entries
end

-- ============================================================================
-- Section 8: Cauldron incantation registration (BlueRaja-IncantationsAPI)
-- ============================================================================
-- ENVY isolates each plugin's globals, so we can't reach IncantationsAPI's
-- `Incantations` directly — have to pull it out of Hell2Modding's cross-plugin
-- registry at `rom.mods`. The `mods` local in main.lua doesn't propagate here;
-- each file that wants cross-mod access reads `rom.mods` itself.
-- Registration guard protects against hot-reload: ProvokeMod persists across
-- reloads via the `ProvokeMod = ProvokeMod or {}` pattern, so the flag sticks.
function ProvokeMod.RegisterIncantation()
	local modsRegistry = rom and rom.mods
	local Incantations = modsRegistry and modsRegistry['BlueRaja-IncantationsAPI']
	if Incantations == nil or Incantations.addIncantation == nil then
		ProvokeMod.Log.warn( "incantation", "IncantationsAPI not found; mechanic will stay locked unless config.RequireIncantation is false" )
		return false
	end
	Incantations.addIncantation({
		Id          = ProvokeMod.IncantationId,
		Name        = "Provoke the Fates",
		Description = "Petition the Moirai to bend your threadwork. Minor rewards can be woven into greater ones, at the price of transient Fear.",
		FlavorText  = "Dare you pluck a thread before its time?",
		WorldUpgradeData = {
			Icon = "GUI\\Screens\\CriticalItemShop\\Icons\\cauldron_fatescroll",
			-- Critical category caps reveals at 3 per run (GhostAdminData.lua:171);
			-- with many mods adding incantations, ours would otherwise get crowded
			-- out indefinitely. AlwaysRevealImmediately bypasses that cap so the
			-- tile appears the moment GameStateRequirements are satisfied.
			AlwaysRevealImmediately = true,
			Cost = { OreIMarble = 3, PlantIShaderot = 2 },
			GameStateRequirements = {
				-- Matches the canonical vanilla signal for "Oath of the Unseen is
				-- unlocked" — the Oath-reroll incantation WorldUpgradeChangeNextRunRNG
				-- (WorldUpgradeData.lua:1421) reads the same path.
				{ Path = { "GameState", "EnemyKills", "Chronos" }, Comparison = ">=", Value = 1 },
			},
			IncantationVoiceLines = {
				{
					PreLineWait = 0.3,
					{ Cue = "/VO/Melinoe_1072", Text = "{#Emph}As the Three Fates would have it, so shall I...!" },
				},
			},
		},
		OnEnabled = function( source )
			ProvokeMod.Log.info( "incantation", "enabled", { source = source } )
		end,
	})
	ProvokeMod.Log.info( "incantation", "registered", { id = ProvokeMod.IncantationId } )
	return true
end

if not ProvokeMod._IncantationRegistered then
	if ProvokeMod.RegisterIncantation() then
		ProvokeMod._IncantationRegistered = true
	end
end
