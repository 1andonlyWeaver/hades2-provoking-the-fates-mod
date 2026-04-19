---@meta _
-- globals we define are private to our plugin!
---@diagnostic disable: lowercase-global

-- this file will be reloaded if it changes during gameplay,
-- 	so only assign to values or define things here.

-- ============================================================================
-- Section 1: Module State & Constants
-- ============================================================================

ProvokeMod = ProvokeMod or {}

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
	ProvokeMod.RunState = {
		ProvocationCount = 0,
		ProvokedCounts = { RegularBoon = 0, EnhancedBoon = 0, Hammer = 0 },
		ActiveFearStacks = {},          -- list of provocations still decaying across rooms
		ActiveTransientVows = {},       -- merged injection currently applied to ShrineUpgrades
		TransientFearActive = false,
		FearHUDIconIds = nil,           -- HUD cluster showing active vows this room
		ProvokedDoors = {},
		LastFearCost = nil,
		ProvokeHintId = nil,
		HintThreadActive = false,
		NearestProvokableDoor = nil,
		RoomEncounterCount = 0,
		RoomEncountersCompleted = 0,
	}
end

-- Initialize on first load only
if not ProvokeMod.RunState then
	ProvokeMod.ResetRunState()
end

-- ============================================================================
-- Section 2: Utility Functions
-- ============================================================================

-- Fear cost for a provocation. `effectiveCount` is the 1-indexed position this
-- provocation will occupy among ALL provocations in the run (1 = first
-- provocation ever this run, regardless of type). If nil, defaults to
-- ProvocationCount + 1 (the slot this call would consume if committed now).
-- Formula: base + ceil(effectiveCount² * penalty). Greed is global, so
-- cross-type spam ramps as fast as same-type spam. math.ceil keeps fractional
-- penalties (e.g. 0.5) from rounding the first provocation's greed down to 0.
function ProvokeMod.GetFearCost( choiceType, effectiveCount )
	local baseCost = 0
	if choiceType == "RegularBoon" then
		baseCost = config.Cost_RegularBoon
	elseif choiceType == "EnhancedBoon" then
		baseCost = config.Cost_EnhancedBoon
	elseif choiceType == "Hammer" then
		baseCost = config.Cost_Hammer
	end
	if effectiveCount == nil then
		local totalCount = (ProvokeMod.RunState and ProvokeMod.RunState.ProvocationCount) or 0
		effectiveCount = totalCount + 1
	end
	effectiveCount = math.max( 1, effectiveCount )
	local greedBonus = 0
	if config.EnableGreed then
		greedBonus = math.ceil( effectiveCount * effectiveCount * config.GreedPenalty_PerUse )
	end
	return baseCost + greedBonus
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
	-- on top of the existing boss-room vow stack is too much.
	if door.Room.Encounter and door.Room.Encounter.EncounterType == "Boss" then
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
	if ProvokeMod.IsMetaProgressDoor( door ) then
		return true
	end
	local pd = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	return pd ~= nil and pd.Provoked and pd.OriginalRewardStoreName == "MetaProgress"
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

-- Called when the game shows a use prompt for an obstacle (player entered interact range).
-- Shows the Provoke hint only when the relevant MetaProgress door is in range,
-- and tracks which door the player is currently nearest to.
function ProvokeMod.OnShowUseButton( objectId )
	if MapState == nil or MapState.OfferedExitDoors == nil then return end
	local door = MapState.OfferedExitDoors[objectId]
	if door == nil then
		ProvokeMod.Log.trace( "door", "show: object not in OfferedExitDoors", { objectId = objectId } )
		return
	end
	if ProvokeMod.IsProvokableDoor( door ) then
		ProvokeMod.RunState.NearestProvokableDoor = door
		ProvokeMod.Log.debug( "door", "show (provokable)", { objectId = objectId } )
		ProvokeMod.SpawnProvokeHint()
	else
		ProvokeMod.Log.trace( "door", "show (non-provokable door)", { objectId = objectId } )
	end
end

-- Called when the game hides a use prompt (player left interact range).
-- Clears the nearest-door reference so a stale door is not used when the hotkey fires.
function ProvokeMod.OnHideUseButton( objectId )
	local nearest = ProvokeMod.RunState.NearestProvokableDoor
	if nearest and nearest.ObjectId == objectId then
		ProvokeMod.RunState.NearestProvokableDoor = nil
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
	if choiceType == "RegularBoon" then
		baseDuration = config.Duration_RegularBoon or 1
	elseif choiceType == "EnhancedBoon" then
		baseDuration = config.Duration_EnhancedBoon or 2
	elseif choiceType == "Hammer" then
		baseDuration = config.Duration_Hammer or 3
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

-- Merge all active Fear stacks into a single { [vow] = ranks } injection, then
-- apply it on top of baseline GameState.ShrineUpgrades. Every vow clamps at
-- its native max rank. If two stacks both picked the same vow and the merged
-- sum would exceed its cap, the excess spills to additional eligible vows
-- with remaining room so paid Fear still lands as visible ranks. Saves the
-- pre-application ranks in ActiveTransientVows so they can be restored later.
function ProvokeMod.ApplyFearStacksToRoom()
	-- Safety: remove any lingering transient injection from a prior room that
	-- did not clean up correctly.
	if ProvokeMod.RunState.TransientFearActive then
		ProvokeMod.Log.warn( "fear", "idempotent safety: TransientFearActive still set at room entry" )
		ProvokeMod.RestoreVowsOnly()
	end

	local stacks = ProvokeMod.RunState.ActiveFearStacks
	if stacks == nil or #stacks == 0 then return end

	-- Sum ranks per vow across all active stacks.
	local merged = {}
	for _, stack in ipairs( stacks ) do
		for vowName, ranks in pairs( stack.Injection ) do
			merged[vowName] = (merged[vowName] or 0) + ranks
		end
	end

	-- Apply each merged total, clamping at the vow's remaining room. Any
	-- excess accumulates in `overflow` and gets redistributed below.
	ProvokeMod.RunState.ActiveTransientVows = {}
	local overflow = 0
	for vowName, ranksToAdd in pairs( merged ) do
		local baseline = GameState.ShrineUpgrades[vowName] or 0
		local maxRank = ProvokeMod.GetVowMaxRank( vowName )
		local room = math.max( 0, maxRank - baseline )
		local take = math.min( ranksToAdd, room )
		if take > 0 then
			ProvokeMod.RunState.ActiveTransientVows[vowName] = {
				OriginalRank = baseline,
				AddedRanks   = take,
			}
			GameState.ShrineUpgrades[vowName] = baseline + take
			ShrineUpgradeExtractValues( vowName )
		end
		overflow = overflow + (ranksToAdd - take)
	end

	-- Spill merge overflow to other eligible vows with remaining room — same
	-- "add more vows" principle as SelectThemedVows. Random order keeps runs
	-- from always spilling onto the same leftovers.
	if overflow > 0 then
		local candidates = {}
		for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
			local baseline = GameState.ShrineUpgrades[vowName] or 0
			local maxRank = ProvokeMod.GetVowMaxRank( vowName )
			local existing = ProvokeMod.RunState.ActiveTransientVows[vowName]
			local already = existing and existing.AddedRanks or 0
			if baseline + already < maxRank then
				table.insert( candidates, vowName )
			end
		end
		while overflow > 0 and #candidates > 0 do
			local idx = RandomInt( 1, #candidates )
			local vowName = candidates[idx]
			table.remove( candidates, idx )
			local baseline = GameState.ShrineUpgrades[vowName] or 0
			local maxRank = ProvokeMod.GetVowMaxRank( vowName )
			local existing = ProvokeMod.RunState.ActiveTransientVows[vowName]
			local already = existing and existing.AddedRanks or 0
			local room = math.max( 0, maxRank - baseline - already )
			local take = math.min( overflow, room )
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
				overflow = overflow - take
			end
		end
		if overflow > 0 then
			ProvokeMod.Log.warn( "fear", "merge overflow dropped: pool exhausted", { overflow = overflow } )
		end
	end

	ProvokeMod.RunState.TransientFearActive = true

	local vowDetails = {}
	local totalAdded = 0
	for vowName, v in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
		table.insert( vowDetails, vowName .. " +" .. v.AddedRanks .. " (was " .. v.OriginalRank .. ")" )
		totalAdded = totalAdded + (v.AddedRanks or 0)
	end
	ProvokeMod.Log.info( "fear", "inject stacks into room", {
		stacks     = #stacks,
		totalRanks = totalAdded,
		vowCount   = #vowDetails,
	} )
	for vowName, v in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
		ProvokeMod.Log.debug( "fear", "inject per-vow", {
			vow      = vowName,
			baseline = v.OriginalRank,
			added    = v.AddedRanks,
			newRank  = v.OriginalRank + v.AddedRanks,
		} )
	end

	ProvokeMod.UpdateFearHUD()
end

-- Persistent HUD icon cluster showing each active vow while Fear is applied.
-- Uses the vanilla MetaUpgradeData[vow].Icon animations on small BlankObstacles
-- arranged horizontally near the top-right of the screen.
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
	local startX = ScreenWidth - 40 - (#vows - 1) * iconSpacing
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
	ProvokeMod.RunState.FearHUDIconIds = ids
end

function ProvokeMod.ClearFearHUD()
	local ids = ProvokeMod.RunState.FearHUDIconIds
	if ids and #ids > 0 then
		Destroy({ Ids = ids })
	end
	ProvokeMod.RunState.FearHUDIconIds = nil
end

-- Restore ShrineUpgrades to their pre-ApplyFearStacksToRoom ranks. Idempotent.
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

	if choiceType == "RegularBoon" then
		room.ChosenRewardType = "Boon"
		room.RewardStoreName = "RunProgress"
		door.RewardStoreName = "RunProgress"
		-- Pick a random god for the boon
		local lootData = ChooseLoot()
		if lootData then
			room.ForceLootName = lootData.Name
		end

	elseif choiceType == "EnhancedBoon" then
		room.ChosenRewardType = "Boon"
		room.RewardStoreName = "RunProgress"
		door.RewardStoreName = "RunProgress"
		-- Pick a random god
		local lootData = ChooseLoot()
		if lootData then
			room.ForceLootName = lootData.Name
		end
		-- Boost rarity chances
		room.BoonRaritiesOverride = {
			Rare = 0.40,
			Epic = 0.35,
			Heroic = 0.20,
			Legendary = 0.05,
		}

	elseif choiceType == "Hammer" then
		room.ChosenRewardType = "WeaponUpgrade"
		room.RewardStoreName = "RunProgress"
		door.RewardStoreName = "RunProgress"
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
	ChoiceColor    = {
		RegularBoon  = { 1.0, 1.0,  1.0,  1.0 },
		EnhancedBoon = { 1.0, 0.85, 0.45, 1.0 },
		Hammer       = { 1.0, 0.47, 0.20, 1.0 },
	},
	-- Mythmaker-prompt title styling: heavy black outline + deep-black shadow.
	-- Matches ElementalPromptScreenData.lua:44-49.
	MythmakerTitleShadow  = { 0.05, 0.04, 0.04, 1.0 },
	MythmakerTitleOutline = { 0.11, 0.10, 0.09, 1.0 },
	-- Rarity-tier backing animations for the BoonSlotBase rows — same pipeline
	-- UpgradeChoiceData.lua:27-32 uses for boon pickup. The tier we assign per
	-- choice climbs with the cost: Regular -> Rare, Enhanced -> Epic, Hammer ->
	-- Legendary, so the visual weight of each scroll matches what it charges.
	RarityAnim = {
		RegularBoon  = "BoonSlotRare",
		EnhancedBoon = "BoonSlotEpic",
		Hammer       = "BoonSlotLegendary",
	},
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
	slot.Door       = params.Door
	slot.Screen     = screen
	slot.ChoiceType = params.ChoiceType
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
		local roomsText = params.Duration == 1 and "1 room" or (tostring( params.Duration ) .. " rooms")
		CreateTextBox({
			Id            = slot.Id,
			Text          = "Lasts " .. roomsText,
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

	local existingData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	local isReprovoke = existingData ~= nil and existingData.Provoked == true
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

	-- Greed tracks total provocations in the run, so every choice shares the
	-- same next-slot position. On re-provoke the selection reverts-then-adds
	-- (ProvocationCount unchanged) so the new choice occupies the same slot.
	local totalCount = ProvokeMod.RunState.ProvocationCount or 0
	local nextPosition = isReprovoke and math.max( 1, totalCount ) or (totalCount + 1)

	-- Early affordability gate: if this is a fresh provoke and none of the
	-- three options fit inside the remaining pool, short-circuit straight to
	-- the Fates-Satisfied rejection BEFORE spawning any provocation-screen
	-- scaffolding. Otherwise the dim + title + flavor components would get
	-- created, the rejection screen would open on top, and dismissing the
	-- rejection would leave orphan backdrop components with no interaction
	-- target — stranding the player on an empty "menu".
	if not isReprovoke then
		local minCost = math.min(
			ProvokeMod.GetFearCost( "RegularBoon",  nextPosition ),
			ProvokeMod.GetFearCost( "EnhancedBoon", nextPosition ),
			ProvokeMod.GetFearCost( "Hammer",       nextPosition )
		)
		if minCost > poolCapacity then
			ProvokeMod.Log.info( "provoke", "blocked: no choice fits pool", {
				objectId     = door.ObjectId,
				poolCapacity = poolCapacity,
				minCost      = minCost,
			} )
			ProvokeMod.OpenFatesSatisfiedScreen()
			return
		end
	end

	local regularCost  = ProvokeMod.GetFearCost( "RegularBoon",  nextPosition )
	local enhancedCost = ProvokeMod.GetFearCost( "EnhancedBoon", nextPosition )
	local hammerCost   = ProvokeMod.GetFearCost( "Hammer",       nextPosition )

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

	-- Resolve the vow injection each button will commit to, so the preview
	-- text shown matches what actually lands.
	screen.PreviewedInjections = {
		RegularBoon  = ProvokeMod.SelectThemedVows( regularCost ),
		EnhancedBoon = ProvokeMod.SelectThemedVows( enhancedCost ),
		Hammer       = ProvokeMod.SelectThemedVows( hammerCost ),
	}

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

	ProvokeMod.Log.info( "provoke", "open screen", {
		objectId         = door.ObjectId,
		isReprovoke      = isReprovoke,
		currentChoice    = currentChoiceType or "none",
		regularCost      = regularCost,
		enhancedCost     = enhancedCost,
		hammerCost       = hammerCost,
		poolCapacity     = poolCapacity,
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

	-- Three BoonSlotBase rows at vanilla positions. Rarity rises with cost.
	screen.KeepOpen = true
	screen.UpgradeButtons = {}

	-- Duration matches QueueFearStack's formula: base from config.Duration_*,
	-- plus one extra room per prior provocation when GreedExtendsDuration is
	-- on. nextPosition is the 1-indexed slot this provocation will occupy, so
	-- the extension is (nextPosition - 1) — identical to what the stack will
	-- actually queue with if the player commits to that option.
	local greedExtension = config.GreedExtendsDuration and math.max( 0, nextPosition - 1 ) or 0
	local regularDuration  = (config.Duration_RegularBoon  or 1) + greedExtension
	local enhancedDuration = (config.Duration_EnhancedBoon or 2) + greedExtension
	local hammerDuration   = (config.Duration_Hammer       or 3) + greedExtension

	-- Icons: BlindBoxLoot is vanilla's wrapped-boon animation (defined in
	-- Items_General_VFX.sjson, backed by Items\Loot\WrappedBoon — the gift-
	-- wrapped mystery-boon present). For Enhanced Boon, layer
	-- BoonUpgradedPreviewSparkles on top via IconOverlayAnim — the same
	-- sparkle overlay vanilla composes with its BoonDrop*UpgradedPreview
	-- animations.
	local choiceConfigs = {
		{ key = "RegularBoon",  choiceType = "RegularBoon",  title = "Boon",            cost = regularCost,  duration = regularDuration,  rarity = "Rare",      iconAnim = "BlindBoxLoot"                                        },
		{ key = "EnhancedBoon", choiceType = "EnhancedBoon", title = "Enhanced Boon",   cost = enhancedCost, duration = enhancedDuration, rarity = "Epic",      iconAnim = "BlindBoxLoot", iconOverlayAnim = "BoonUpgradedPreviewSparkles" },
		{ key = "Hammer",       choiceType = "Hammer",       title = "Daedalus Hammer", cost = hammerCost,   duration = hammerDuration,   rarity = "Legendary", iconAnim = "WeaponUpgradePreview"                                },
	}

	-- Hide options whose Fear cost exceeds the pool capacity — those would
	-- silently leak Fear on commit. The "all options filtered on a fresh
	-- provoke" case is already handled by the early gate above; this block
	-- only prunes partially-affordable menus and re-provoke screens (where
	-- Revert / Keep Choice still need to render even with zero viable
	-- choices).
	local visibleConfigs = {}
	local hiddenKeys = {}
	for _, c in ipairs( choiceConfigs ) do
		if c.cost <= poolCapacity then
			table.insert( visibleConfigs, c )
		else
			table.insert( hiddenKeys, c.key )
		end
	end
	if #hiddenKeys > 0 then
		ProvokeMod.Log.info( "provoke", "hid over-capacity choices", {
			poolCapacity = poolCapacity,
			hidden       = table.concat( hiddenKeys, "," ),
		} )
	end

	for i, choice in ipairs( visibleConfigs ) do
		screen.UpgradeButtons[i] = buildChoiceRow( screen, choice.key, {
			Index           = i,
			Door            = door,
			ChoiceType      = choice.choiceType,
			Title           = choice.title,
			TitleColor      = ProvokeMod.UI.ChoiceColor[choice.choiceType],
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
	local door = button.Door
	ProvokeMod.Log.info( "provoke", "select choice", {
		choiceType = button.ChoiceType,
		objectId   = door and door.ObjectId,
	} )
	local existingData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	if existingData and existingData.Provoked then
		ProvokeMod.UnTransformDoor( door )
	end
	local injection = screen.PreviewedInjections and screen.PreviewedInjections[button.ChoiceType]
	ProvokeMod.TransformDoor( door, button.ChoiceType, injection )
	ProvokeMod.CloseProvocationScreen( screen )
	-- Auto-proceed: skip AttemptUseDoor (its pre-LeaveRoom setup already ran on
	-- the initial press), call LeaveRoom directly. Our LeaveRoom wrap re-enters
	-- but IsControlDown is false (Confirm was pressed, not Use/Interact), so the
	-- hold-gate branch is skipped and we fall through to the provoked-door path.
	thread( LeaveRoom, CurrentRun, door )
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

-- Called from StartRoom wrap after the room initializes
function ProvokeMod.OnRoomStart( currentRun, currentRoom )
	-- Track how many encounters this room has so OnEncounterEnd only removes fear
	-- after the last one completes (guards against multi-encounter rooms).
	ProvokeMod.RunState.RoomEncounterCount = (currentRoom.Encounters and #currentRoom.Encounters) or 1
	ProvokeMod.RunState.RoomEncountersCompleted = 0

	ProvokeMod.LogFearStackState( "room_start" )

	local stacks = ProvokeMod.RunState.ActiveFearStacks
	if stacks ~= nil and #stacks > 0 then
		ProvokeMod.ApplyFearStacksToRoom()

		-- Banner number: sum of ranks actually applied this room (post-clamp).
		local totalRanks = 0
		for _, vowData in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
			totalRanks = totalRanks + (vowData.AddedRanks or 0)
		end
		ProvokeMod.RunState.LastFearCost = totalRanks

		-- Collect sorted vow effect strings now that ActiveTransientVows is populated
		local vowLines = ProvokeMod.GetVowListText( ProvokeMod.RunState.ActiveTransientVows )

		-- Title line: "The Fates are Provoked  (+N Fear)"
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

		-- Vow lines are created one-by-one inside the thread so they pop in sequentially.
		-- Capture the room reference so cleanup can bail out if the player leaves early.
		local bannerRoom = currentRoom
		thread( function()
			local allIds = { banner.Id }
			local lineY = 160

			wait( 0.6 )
			for _, lineText in ipairs( vowLines ) do
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
			-- If the room changed during the wait, the IDs are already destroyed by the
			-- room transition. Skip cleanup to avoid operating on stale/reused IDs.
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

	-- Hint spawning is handled in OnExitsUnlocked (triggered by DoUnlockRoomExits hook),
	-- which fires after the encounter ends and doors have ReadyToUse = true.
	ProvokeMod.Log.info( "room", "start complete", {
		encounters = ProvokeMod.RunState.RoomEncounterCount,
		stacks     = (ProvokeMod.RunState.ActiveFearStacks and #ProvokeMod.RunState.ActiveFearStacks) or 0,
		totalRanks = ProvokeMod.RunState.LastFearCost or 0,
	} )
end

-- Called from EndEncounterEffects wrap before the base function
function ProvokeMod.OnEncounterEnd( currentRun, currentRoom, currentEncounter )
	ProvokeMod.RunState.RoomEncountersCompleted = (ProvokeMod.RunState.RoomEncountersCompleted or 0) + 1
	local expected = ProvokeMod.RunState.RoomEncounterCount or 1
	local isLast   = ProvokeMod.RunState.RoomEncountersCompleted >= expected
	ProvokeMod.Log.info( "room", "encounter_end", {
		completed = ProvokeMod.RunState.RoomEncountersCompleted,
		expected  = expected,
		isLast    = isLast,
	} )
	if isLast then
		-- Last encounter of this room: restore baseline ranks and decay stacks.
		ProvokeMod.RestoreVowsAndDecayStacks()
		ProvokeMod.LogFearStackState( "encounter_end" )
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
