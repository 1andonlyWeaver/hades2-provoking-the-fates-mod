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

function ProvokeMod.ResetRunState()
	ProvokeMod.RunState = {
		ProvocationCount = 0,
		ActiveTransientVows = {},
		TransientFearActive = false,
		ProvokedDoors = {},
		PendingFearCost = nil,
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

function ProvokeMod.GetFearCost( choiceType, countOffset )
	countOffset = countOffset or 0
	local baseCost = 0
	if choiceType == "RegularBoon" then
		baseCost = config.Cost_RegularBoon
	elseif choiceType == "EnhancedBoon" then
		baseCost = config.Cost_EnhancedBoon
	elseif choiceType == "Hammer" then
		baseCost = config.Cost_Hammer
	end
	local greedBonus = 0
	if config.EnableGreed then
		local effectiveCount = math.max( 0, ProvokeMod.RunState.ProvocationCount + countOffset )
		greedBonus = (2^effectiveCount) * config.GreedPenalty_PerUse
	end
	return baseCost + greedBonus
end

function ProvokeMod.IsMetaProgressDoor( door )
	if door == nil or door.Room == nil then
		return false
	end
	-- Exclude boss encounter rooms: check the current room (not door.Room, which is the destination).
	if CurrentRun and CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.Encounter then
		if CurrentRun.CurrentRoom.Encounter.EncounterType == "Boss" then
			return false
		end
	end
	-- Exclude story/NPC rooms (Arachne, Narcissus, etc.): their ForcedReward propagates
	-- to ChosenRewardType = "Story", but RewardStoreName can still be "MetaProgress".
	if door.Room.ChosenRewardType == "Story" or door.Room.ForcedReward == "Story" then
		return false
	end
	return (door.RewardStoreName or door.Room.RewardStoreName) == "MetaProgress"
end

-- Find the first MetaProgress exit in the current room (provoked or not).
-- Also matches doors that were originally MetaProgress but have been transformed
-- (TransformDoor changes door.RewardStoreName away from "MetaProgress").
-- Returns the door object or nil if none found.
-- Doors are stored in the global MapState.OfferedExitDoors (set by DoUnlockRoomExits).
function ProvokeMod.FindProvokableDoor()
	if MapState == nil or MapState.OfferedExitDoors == nil then
		print("[ProvokeMod] FindProvokableDoor: MapState.OfferedExitDoors is nil")
		return nil
	end
	local count = 0
	for _, door in pairs( MapState.OfferedExitDoors ) do
		count = count + 1
		if door.ReadyToUse then
			if ProvokeMod.IsMetaProgressDoor( door ) then
				print("[ProvokeMod] FindProvokableDoor: found MetaProgress door " .. tostring(door.ObjectId))
				return door
			end
			-- Also match doors that were originally MetaProgress before transformation
			local pd = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
			if pd and pd.Provoked and pd.OriginalRewardStoreName == "MetaProgress" then
				print("[ProvokeMod] FindProvokableDoor: found provoked MetaProgress door " .. tostring(door.ObjectId))
				return door
			end
		end
	end
	print("[ProvokeMod] FindProvokableDoor: checked " .. count .. " doors, none provokable")
	return nil
end

-- Called after DoUnlockRoomExits completes and exits are ready to use.
-- Starts the hotkey listener thread. Hint visibility is managed by OnShowUseButton
-- (fires when the player walks within door interact-range).
function ProvokeMod.OnExitsUnlocked()
	print("[ProvokeMod] OnExitsUnlocked called")
	if ProvokeMod.FindProvokableDoor() == nil then
		return
	end

	ProvokeMod.RunState.HintThreadActive = true

	local notifyName = "ProvokeMod__HotkeyPress"
	thread( function()
		while ProvokeMod.RunState.HintThreadActive do
			NotifyOnInteractOrControlPressed({
				Ids = {},
				Names = { config.ProvokeHotkey or "Shout" },
				Notify = notifyName,
			})
			waitUntil( notifyName )
			if not ProvokeMod.RunState.HintThreadActive then
				break
			end

			local provokableDoor = ProvokeMod.RunState.NearestProvokableDoor or ProvokeMod.FindProvokableDoor()
			if provokableDoor then
				thread( function()
					ProvokeMod.OpenProvocationScreen( provokableDoor )
					if ProvokeMod.FindProvokableDoor() == nil then
						ProvokeMod.DespawnProvokeHint()
					end
				end)
			end
			wait( 0.5 )
		end
	end)
end

-- Called when the game shows a use prompt for an obstacle (player entered interact range).
-- Shows the Provoke hint only when the relevant MetaProgress door is in range,
-- and tracks which door the player is currently nearest to.
function ProvokeMod.OnShowUseButton( objectId )
	if MapState == nil or MapState.OfferedExitDoors == nil then return end
	local door = MapState.OfferedExitDoors[objectId]
	if door == nil then return end
	-- Show hint for MetaProgress doors, or for doors that were originally MetaProgress
	if ProvokeMod.IsMetaProgressDoor( door ) then
		if not ProvokeMod.HasAffordableOptions() then return end
		ProvokeMod.RunState.NearestProvokableDoor = door
		ProvokeMod.SpawnProvokeHint()
		return
	end
	local pd = ProvokeMod.RunState.ProvokedDoors[objectId]
	if pd and pd.Provoked and pd.OriginalRewardStoreName == "MetaProgress" then
		ProvokeMod.RunState.NearestProvokableDoor = door
		ProvokeMod.SpawnProvokeHint()
	end
end

-- Called when the game hides a use prompt (player left interact range).
-- Clears the nearest-door reference so a stale door is not used when the hotkey fires.
function ProvokeMod.OnHideUseButton( objectId )
	local nearest = ProvokeMod.RunState.NearestProvokableDoor
	if nearest and nearest.ObjectId == objectId then
		ProvokeMod.RunState.NearestProvokableDoor = nil
	end
end

-- Show a "second line" hint below the door's {I} Proceed UsePrompt, matching
-- the accept/gift button style used by boon/NPC interaction prompts.
-- UsePrompt text appears at ~Y=1010 (ScreenHeight - BottomOffset(−10) - textOffset(80)).
-- We position ours ~30px below that, so together they read as two stacked options.
function ProvokeMod.SpawnProvokeHint()
	if ProvokeMod.RunState.ProvokeHintId ~= nil then
		return  -- already visible
	end
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
	-- {SH} is the Shout/Call button glyph (confirmed in game localization)
	CreateTextBox({
		Id = hintId,
		Text = "{SH} Provoke the Fates",
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

-- Remove the HUD hint and stop the background listener thread.
function ProvokeMod.DespawnProvokeHint()
	ProvokeMod.RunState.HintThreadActive = false
	if ProvokeMod.RunState.ProvokeHintId then
		Destroy({ Id = ProvokeMod.RunState.ProvokeHintId })
		ProvokeMod.RunState.ProvokeHintId = nil
	end
end

function ProvokeMod.GetVowMaxRank( vowName )
	local data = MetaUpgradeData[vowName]
	if data and data.Ranks then
		return #data.Ranks
	end
	return 0
end

-- Returns true if at least one provocation choice (Boon / Enhanced / Hammer)
-- has a fear cost that fits within MaxTransientFear at the current greed level.
-- When all three costs exceed the cap the provoke hint is suppressed.
function ProvokeMod.HasAffordableOptions()
	return ProvokeMod.GetFearCost( "RegularBoon"  ) <= config.MaxTransientFear
	    or ProvokeMod.GetFearCost( "EnhancedBoon" ) <= config.MaxTransientFear
	    or ProvokeMod.GetFearCost( "Hammer"        ) <= config.MaxTransientFear
end

-- ============================================================================
-- Section 3: Transient Fear Engine
-- ============================================================================

-- Select which vows to bump and by how much.
-- Each fear point = 1 rank increment on a random eligible vow.
-- Returns a map: vowName -> additionalRanks
function ProvokeMod.SelectTransientVows( fearCost )
	local injections = {}
	local remaining = fearCost

	-- Build candidate pool: vows not yet at max rank
	local candidatePool = {}
	for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
		local currentRank = GameState.ShrineUpgrades[vowName] or 0
		local maxRank = ProvokeMod.GetVowMaxRank( vowName )
		if currentRank < maxRank then
			table.insert( candidatePool, vowName )
		end
	end

	-- Spillover: if all vows maxed, look for rank-0 vows
	if #candidatePool == 0 then
		for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
			local currentRank = GameState.ShrineUpgrades[vowName] or 0
			if currentRank == 0 then
				table.insert( candidatePool, vowName )
			end
		end
	end

	-- Final fallback: use all eligible vows
	if #candidatePool == 0 then
		for _, vowName in ipairs( ProvokeMod.EligibleVows ) do
			table.insert( candidatePool, vowName )
		end
	end

	-- Sequential fill: max out one vow before spilling into the next
	while remaining > 0 and #candidatePool > 0 do
		local idx = RandomInt( 1, #candidatePool )
		local vowName = candidatePool[idx]
		table.remove( candidatePool, idx )

		local currentRank = (GameState.ShrineUpgrades[vowName] or 0) + (injections[vowName] or 0)
		local maxRank = ProvokeMod.GetVowMaxRank( vowName )
		local toAdd = math.min( maxRank - currentRank, remaining )

		if toAdd > 0 then
			injections[vowName] = (injections[vowName] or 0) + toAdd
			remaining = remaining - toAdd
		end

		-- If pool emptied and fear remains, refill with still-available vows
		if remaining > 0 and #candidatePool == 0 then
			for _, vName in ipairs( ProvokeMod.EligibleVows ) do
				local cRank = (GameState.ShrineUpgrades[vName] or 0) + (injections[vName] or 0)
				local mRank = ProvokeMod.GetVowMaxRank( vName )
				if cRank < mRank then
					table.insert( candidatePool, vName )
				end
			end
		end
	end

	return injections
end

-- Apply transient vows to GameState.ShrineUpgrades
function ProvokeMod.InjectTransientFear( fearCost )
	-- Safety: remove any existing transient vows first
	if ProvokeMod.RunState.TransientFearActive then
		ProvokeMod.RemoveTransientFear()
	end

	local injections = ProvokeMod.SelectTransientVows( fearCost )

	ProvokeMod.RunState.ActiveTransientVows = {}
	for vowName, addedRanks in pairs( injections ) do
		local originalRank = GameState.ShrineUpgrades[vowName] or 0
		ProvokeMod.RunState.ActiveTransientVows[vowName] = {
			OriginalRank = originalRank,
			AddedRanks = addedRanks,
		}
		GameState.ShrineUpgrades[vowName] = originalRank + addedRanks
		-- Re-extract values so all game systems read the new difficulty
		ShrineUpgradeExtractValues( vowName )
	end
	ProvokeMod.RunState.TransientFearActive = true

	local vowDetails = {}
	for vowName, addedRanks in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
		table.insert( vowDetails, vowName .. " +" .. addedRanks.AddedRanks .. " (was " .. addedRanks.OriginalRank .. ")" )
	end
	print("[ProvokeMod] Injected Transient Fear: " .. fearCost .. " points across " .. ProvokeMod.TableLength( injections ) .. " vows: " .. table.concat( vowDetails, ", " ))
end

-- Remove all transient vows, restoring original ranks. Idempotent.
function ProvokeMod.RemoveTransientFear()
	if not ProvokeMod.RunState.TransientFearActive then
		return
	end

	for vowName, vowData in pairs( ProvokeMod.RunState.ActiveTransientVows ) do
		GameState.ShrineUpgrades[vowName] = vowData.OriginalRank
		ShrineUpgradeExtractValues( vowName )
	end
	ProvokeMod.RunState.ActiveTransientVows = {}
	ProvokeMod.RunState.TransientFearActive = false

	print("[ProvokeMod] Removed Transient Fear, vows restored")
end

-- ============================================================================
-- Section 4: Door Transformation
-- ============================================================================

function ProvokeMod.TransformDoor( door, choiceType )
	local room = door.Room
	local fearCost = ProvokeMod.GetFearCost( choiceType )

	-- Store provocation data
	local provokeData = {
		ChoiceType = choiceType,
		FearCost = fearCost,
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

	-- Track provocation
	ProvokeMod.RunState.ProvocationCount = ProvokeMod.RunState.ProvocationCount + 1
	ProvokeMod.RunState.ProvokedDoors[door.ObjectId] = provokeData

	-- Refresh the door's reward preview icon
	ProvokeMod.RefreshDoorPreview( door )

	print("[ProvokeMod] Transformed door to " .. choiceType .. " (Fear: " .. fearCost .. ")")
end

-- Revert a provoked door back to its original MetaProgress reward.
-- Decrements ProvocationCount and clears the ProvokedDoors entry. Idempotent.
function ProvokeMod.UnTransformDoor( door )
	local provokeData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	if provokeData == nil or not provokeData.Provoked then
		print("[ProvokeMod] UnTransformDoor: door not provoked, skipping")
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

	-- Decrement the greed counter, clamped to 0
	ProvokeMod.RunState.ProvocationCount = math.max( 0, ProvokeMod.RunState.ProvocationCount - 1 )

	-- Clear the provoke entry so the door is treated as fresh
	ProvokeMod.RunState.ProvokedDoors[door.ObjectId] = nil

	-- Refresh the door's reward preview icon back to the original
	ProvokeMod.RefreshDoorPreview( door )

	print("[ProvokeMod] UnTransformDoor: reverted door " .. tostring(door.ObjectId))
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

function ProvokeMod.RefreshDoorPreview( door )
	local newAnimName = ProvokeMod.GetDoorIconAnimName( door )

	-- Prefer in-place update: updating the animation on an existing obstacle preserves
	-- its material/color state set during room init, avoiding the white-silhouette bug.
	if newAnimName and door.RewardPreviewIconIds and #door.RewardPreviewIconIds > 0 then
		for _, iconId in ipairs( door.RewardPreviewIconIds ) do
			SetAnimation({ DestinationId = iconId, Name = newAnimName })
		end
		door.RewardPreviewAnimName = newAnimName
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
end

-- ============================================================================
-- Section 5: Provocation Choice Screen
-- ============================================================================

function ProvokeMod.OpenProvocationScreen( door )
	if IsScreenOpen( "ProvokeFatesScreen" ) then
		return
	end

	-- Detect whether this door has already been transformed.
	local existingData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	local isReprovoke = existingData ~= nil and existingData.Provoked == true
	local currentChoiceType = isReprovoke and existingData.ChoiceType or nil
	-- When re-opening a provoked door, costs should reflect what will be charged
	-- after the current provocation is undone (ProvocationCount - 1).
	local costOffset = isReprovoke and -1 or 0

	local screen = { Components = {}, Name = "ProvokeFatesScreen" }

	OnScreenOpened( screen )

	-- Ornate dialog frame. Scale slightly larger in re-provoke mode to fit 5th button.
	local menuY = ScreenCenterY + 25
	screen.Components.Frame = CreateScreenComponent({
		Name = "BlankObstacle",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = menuY,
	})
	SetAnimation({ Name = "MythmakerBoxDefault", DestinationId = screen.Components.Frame.Id })
	SetScale({ Id = screen.Components.Frame.Id, Fraction = isReprovoke and 0.92 or 0.78 })

	local centerY = menuY

	-- Title
	screen.Components.TitleBacking = CreateScreenComponent({
		Name = "BlankObstacle",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = centerY - 200,
	})
	CreateTextBox({
		Id = screen.Components.TitleBacking.Id,
		Text = "Provoke the Fates",
		FontSize = 28,
		Color = { 0.74, 0.63, 1.0, 1.0 },
		Font = "P22UndergroundSCHeavy",
		ShadowBlur = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 3 },
		Justification = "Center",
	})

	-- Subtitle
	screen.Components.Subtitle = CreateScreenComponent({
		Name = "BlankObstacle",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = centerY - 160,
	})
	CreateTextBox({
		Id = screen.Components.Subtitle.Id,
		Text = isReprovoke
			and "Change your choice, or revert the door."
			or  "Upgrade this reward. The Fates will retaliate.",
		FontSize = 15,
		Color = { 0.75, 0.70, 0.85, 0.9 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})

	-- Calculate costs (offset = -1 in re-provoke mode so the displayed cost
	-- matches what TransformDoor will actually charge after the undo).
	local regularCost  = ProvokeMod.GetFearCost( "RegularBoon",  costOffset )
	local enhancedCost = ProvokeMod.GetFearCost( "EnhancedBoon", costOffset )
	local hammerCost   = ProvokeMod.GetFearCost( "Hammer",       costOffset )

	local canRegular  = regularCost  <= config.MaxTransientFear
	local canEnhanced = enhancedCost <= config.MaxTransientFear
	local canHammer   = hammerCost   <= config.MaxTransientFear

	local buttonY       = centerY - 90
	local buttonSpacing = 74

	-- Option 1: Regular Boon
	local regularLabel = "Boon  (+" .. regularCost .. " Fear)"
	if currentChoiceType == "RegularBoon" then
		regularLabel = regularLabel .. "  [current]"
	end
	screen.Components.RegularBoon = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = buttonY,
	})
	SetScaleX({ Id = screen.Components.RegularBoon.Id, Fraction = 1.25 })
	screen.Components.RegularBoon.OnPressedFunctionName = "ProvokeMod__OnSelectRegularBoon"
	screen.Components.RegularBoon.Door = door
	screen.Components.RegularBoon.Screen = screen
	CreateTextBox({
		Id = screen.Components.RegularBoon.Id,
		Text = regularLabel,
		FontSize = 18,
		Color = canRegular and { 1.0, 1.0, 1.0, 1.0 } or { 0.4, 0.4, 0.4, 0.6 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})
	if not canRegular then
		UseableOff({ Id = screen.Components.RegularBoon.Id })
	end

	-- Option 2: Enhanced Boon
	local enhancedLabel = "Enhanced Boon  (+" .. enhancedCost .. " Fear)"
	if currentChoiceType == "EnhancedBoon" then
		enhancedLabel = enhancedLabel .. "  [current]"
	end
	screen.Components.EnhancedBoon = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = buttonY + buttonSpacing,
	})
	SetScaleX({ Id = screen.Components.EnhancedBoon.Id, Fraction = 1.25 })
	screen.Components.EnhancedBoon.OnPressedFunctionName = "ProvokeMod__OnSelectEnhancedBoon"
	screen.Components.EnhancedBoon.Door = door
	screen.Components.EnhancedBoon.Screen = screen
	CreateTextBox({
		Id = screen.Components.EnhancedBoon.Id,
		Text = enhancedLabel,
		FontSize = 18,
		Color = canEnhanced and { 1.0, 0.85, 0.45, 1.0 } or { 0.4, 0.4, 0.4, 0.6 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})
	if not canEnhanced then
		UseableOff({ Id = screen.Components.EnhancedBoon.Id })
	end

	-- Option 3: Hammer
	local hammerLabel = "Daedalus Hammer  (+" .. hammerCost .. " Fear)"
	if currentChoiceType == "Hammer" then
		hammerLabel = hammerLabel .. "  [current]"
	end
	screen.Components.Hammer = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu_TraitTray",
		X = ScreenCenterX,
		Y = buttonY + buttonSpacing * 2,
	})
	SetScaleX({ Id = screen.Components.Hammer.Id, Fraction = 1.25 })
	screen.Components.Hammer.OnPressedFunctionName = "ProvokeMod__OnSelectHammer"
	screen.Components.Hammer.Door = door
	screen.Components.Hammer.Screen = screen
	CreateTextBox({
		Id = screen.Components.Hammer.Id,
		Text = hammerLabel,
		FontSize = 18,
		Color = canHammer and { 1.0, 0.47, 0.20, 1.0 } or { 0.4, 0.4, 0.4, 0.6 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})
	if not canHammer then
		UseableOff({ Id = screen.Components.Hammer.Id })
	end

	if isReprovoke then
		-- Option 4 (re-provoke only): Revert to Original
		screen.Components.Revert = CreateScreenComponent({
			Name = "ButtonDefault",
			Group = "Combat_Menu_TraitTray",
			X = ScreenCenterX,
			Y = buttonY + buttonSpacing * 3,
		})
		SetScaleX({ Id = screen.Components.Revert.Id, Fraction = 1.25 })
		screen.Components.Revert.OnPressedFunctionName = "ProvokeMod__OnRevert"
		screen.Components.Revert.Door = door
		screen.Components.Revert.Screen = screen
		CreateTextBox({
			Id = screen.Components.Revert.Id,
			Text = "Revert to Original",
			FontSize = 16,
			Color = { 0.85, 0.65, 0.65, 0.9 },
			Font = "P22UndergroundSCMedium",
			Justification = "Center",
		})

		-- Option 5 (re-provoke only): Keep Choice — dismiss without changing
		screen.Components.Cancel = CreateScreenComponent({
			Name = "ButtonDefault",
			Group = "Combat_Menu_TraitTray",
			X = ScreenCenterX,
			Y = buttonY + buttonSpacing * 4,
		})
		SetScaleX({ Id = screen.Components.Cancel.Id, Fraction = 1.25 })
		screen.Components.Cancel.OnPressedFunctionName = "ProvokeMod__OnCancel"
		screen.Components.Cancel.Screen = screen
		screen.Components.Cancel.ControlHotkeys = { "Cancel", "Confirm" }
		CreateTextBox({
			Id = screen.Components.Cancel.Id,
			Text = "Keep Choice",
			FontSize = 16,
			Color = { 0.7, 0.7, 0.7, 0.9 },
			Font = "P22UndergroundSCMedium",
			Justification = "Center",
		})
	else
		-- Enter Room button — bound to both Cancel and Confirm so the player can
		-- dismiss with a single quick press of either back or the interact button.
		screen.Components.Cancel = CreateScreenComponent({
			Name = "ButtonDefault",
			Group = "Combat_Menu_TraitTray",
			X = ScreenCenterX,
			Y = buttonY + buttonSpacing * 3,
		})
		SetScaleX({ Id = screen.Components.Cancel.Id, Fraction = 1.25 })
		screen.Components.Cancel.OnPressedFunctionName = "ProvokeMod__OnCancel"
		screen.Components.Cancel.Screen = screen
		screen.Components.Cancel.ControlHotkeys = { "Cancel", "Confirm" }
		CreateTextBox({
			Id = screen.Components.Cancel.Id,
			Text = "Don't Provoke",
			FontSize = 16,
			Color = { 0.7, 0.7, 0.7, 0.9 },
			Font = "P22UndergroundSCMedium",
			Justification = "Center",
		})
	end

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

game.ProvokeMod__OnSelectRegularBoon = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	local existingData = ProvokeMod.RunState.ProvokedDoors[button.Door.ObjectId]
	if existingData and existingData.Provoked then
		ProvokeMod.UnTransformDoor( button.Door )
	end
	ProvokeMod.TransformDoor( button.Door, "RegularBoon" )
	ProvokeMod.CloseProvocationScreen( screen )
end

game.ProvokeMod__OnSelectEnhancedBoon = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	local existingData = ProvokeMod.RunState.ProvokedDoors[button.Door.ObjectId]
	if existingData and existingData.Provoked then
		ProvokeMod.UnTransformDoor( button.Door )
	end
	ProvokeMod.TransformDoor( button.Door, "EnhancedBoon" )
	ProvokeMod.CloseProvocationScreen( screen )
end

game.ProvokeMod__OnSelectHammer = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	local existingData = ProvokeMod.RunState.ProvokedDoors[button.Door.ObjectId]
	if existingData and existingData.Provoked then
		ProvokeMod.UnTransformDoor( button.Door )
	end
	ProvokeMod.TransformDoor( button.Door, "Hammer" )
	ProvokeMod.CloseProvocationScreen( screen )
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

-- ============================================================================
-- Section 7: Room Entry/Exit Fear Management
-- ============================================================================

-- Called from StartRoom wrap after the room initializes
function ProvokeMod.OnRoomStart( currentRun, currentRoom )
	-- Track how many encounters this room has so OnEncounterEnd only removes fear
	-- after the last one completes (guards against multi-encounter rooms).
	ProvokeMod.RunState.RoomEncounterCount = (currentRoom.Encounters and #currentRoom.Encounters) or 1
	ProvokeMod.RunState.RoomEncountersCompleted = 0

	if ProvokeMod.RunState.PendingFearCost then
		local fearCost = ProvokeMod.RunState.PendingFearCost
		ProvokeMod.RunState.PendingFearCost = nil
		ProvokeMod.RunState.LastFearCost = fearCost

		ProvokeMod.InjectTransientFear( fearCost )

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
			Text = "The Fates are Provoked  (+" .. fearCost .. " Fear)",
			FontSize = 26,
			Color = { 0.74, 0.63, 1.0, 1.0 },
			Font = "P22UndergroundSCHeavy",
			ShadowBlur = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 3 },
			Justification = "Center",
			OutlineThickness = 2,
			OutlineColor = { 0, 0, 0, 1 },
		})

		-- Vow lines are created one-by-one inside the thread so they pop in sequentially
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
			for _, id in ipairs( allIds ) do
				ModifyTextBox({ Id = id, FadeTarget = 0, FadeDuration = 0.5 })
			end
			wait( 0.5 )
			for _, id in ipairs( allIds ) do
				Destroy({ Id = id })
			end
		end)
	end

	-- Hint spawning is handled in OnExitsUnlocked (triggered by DoUnlockRoomExits hook),
	-- which fires after the encounter ends and doors have ReadyToUse = true.
	print("[ProvokeMod] OnRoomStart complete")
end

-- Called from EndEncounterEffects wrap before the base function
function ProvokeMod.OnEncounterEnd( currentRun, currentRoom, currentEncounter )
	ProvokeMod.RunState.RoomEncountersCompleted = (ProvokeMod.RunState.RoomEncountersCompleted or 0) + 1
	local expected = ProvokeMod.RunState.RoomEncounterCount or 1
	if ProvokeMod.RunState.RoomEncountersCompleted >= expected then
		ProvokeMod.RemoveTransientFear()
	end
	-- LeaveRoom calls RemoveTransientFear unconditionally as a final safety net.
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
	HealingReductionShrineUpgrade = "Vow of Scars",
	ShopPricesShrineUpgrade       = "Vow of Debt",
	MinibossCountShrineUpgrade    = "Vow of Shadow",
	BiomeSpeedShrineUpgrade       = "Vow of Time",
	LimitGraspShrineUpgrade       = "Vow of Void",
	BoonManaReserveShrineUpgrade  = "Vow of Hubris",
	BanUnpickedBoonsShrineUpgrade = "Vow of Denial",
}

-- printf-style format strings for the numerical effect at the applied rank.
-- BiomeSpeedShrineUpgrade is handled separately (UseTimeString).
ProvokeMod.VowValueFormats = {
	EnemyDamageShrineUpgrade      = "+%d%% foe damage",
	EnemyHealthShrineUpgrade      = "+%d%% foe health",
	EnemyShieldShrineUpgrade      = "%d shield per foe",
	EnemySpeedShrineUpgrade       = "+%d%% foe speed",
	EnemyCountShrineUpgrade       = "+%d%% more foes",
	NextBiomeEnemyShrineUpgrade   = "%d%% next-biome foes",
	EnemyRespawnShrineUpgrade     = "%d%% respawn chance",
	EnemyEliteShrineUpgrade       = "%d perk(s) on elites",
	HealingReductionShrineUpgrade = "healing reduced to %d%%",
	ShopPricesShrineUpgrade       = "+%d%% shop prices",
	MinibossCountShrineUpgrade    = "+%d mini-boss",
	LimitGraspShrineUpgrade       = "%d%% grasp available",
	BoonManaReserveShrineUpgrade  = "reserves %d mana/rarity",
	BanUnpickedBoonsShrineUpgrade = "%d unpicked boons banned",
}

-- Compute the display value for a vow at newRank using its SimpleExtractValues rules.
-- Returns nil if the data is unavailable.
function ProvokeMod.ComputeVowDisplayValue( vowName, newRank )
	local metaData = MetaUpgradeData and MetaUpgradeData[vowName]
	if not metaData or not metaData.Ranks then return nil end

	local rankData = metaData.Ranks[newRank]
	if not rankData then return nil end

	local changeValue = rankData.ChangeValue

	-- BiomeSpeedShrineUpgrade: seconds → "M:SS"
	if vowName == "BiomeSpeedShrineUpgrade" then
		local secs = math.floor( changeValue )
		return string.format( "%d:%02d", math.floor( secs / 60 ), secs % 60 )
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

-- Return "Vow of X: +Y% description" for one active transient vow entry.
function ProvokeMod.GetVowValueText( vowName, vowData )
	local displayName = ProvokeMod.VowDisplayNames[vowName] or vowName
	local newRank = ( vowData.OriginalRank or 0 ) + ( vowData.AddedRanks or 0 )
	local displayValue = ProvokeMod.ComputeVowDisplayValue( vowName, newRank )

	if displayValue == nil then
		return displayName
	end

	-- BiomeSpeedShrineUpgrade display value is already a formatted string
	if vowName == "BiomeSpeedShrineUpgrade" then
		return displayName .. ": " .. displayValue .. " biome limit"
	end

	local fmt = ProvokeMod.VowValueFormats[vowName]
	if fmt then
		return displayName .. ": " .. string.format( fmt, displayValue )
	end
	return displayName
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
