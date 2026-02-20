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
-- Excludes BossDifficultyShrineUpgrade (swaps entire boss encounters mid-room)
-- and BoonSkipShrineUpgrade (removes boon invulnerability frames).
ProvokeMod.EligibleVows = {
	"EnemyDamageShrineUpgrade",
	"EnemyHealthShrineUpgrade",
	"EnemyShieldShrineUpgrade",
	"EnemySpeedShrineUpgrade",
	"EnemyCountShrineUpgrade",
	"NextBiomeEnemyShrineUpgrade",
	"EnemyRespawnShrineUpgrade",
	"EnemyEliteShrineUpgrade",
	"HealingReductionShrineUpgrade",
	"ShopPricesShrineUpgrade",
	"MinibossCountShrineUpgrade",
	"BiomeSpeedShrineUpgrade",
	"LimitGraspShrineUpgrade",
	"BoonManaReserveShrineUpgrade",
	"BanUnpickedBoonsShrineUpgrade",
}

function ProvokeMod.ResetRunState()
	ProvokeMod.RunState = {
		ProvocationCount = 0,
		ActiveTransientVows = {},
		TransientFearActive = false,
		ProvokedDoors = {},
		PendingFearCost = nil,
		LastFearCost = nil,
	}
end

-- Initialize on first load only
if not ProvokeMod.RunState then
	ProvokeMod.ResetRunState()
end

-- ============================================================================
-- Section 2: Utility Functions
-- ============================================================================

function ProvokeMod.GetFearCost( choiceType )
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
		greedBonus = ProvokeMod.RunState.ProvocationCount * config.GreedPenalty_PerUse
	end
	return baseCost + greedBonus
end

function ProvokeMod.IsMetaProgressDoor( door )
	if door == nil or door.Room == nil then
		return false
	end
	return (door.RewardStoreName or door.Room.RewardStoreName) == "MetaProgress"
end

function ProvokeMod.GetVowMaxRank( vowName )
	local data = MetaUpgradeData[vowName]
	if data and data.Ranks then
		return #data.Ranks
	end
	return 0
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

	while remaining > 0 and #candidatePool > 0 do
		local idx = RandomInt( 1, #candidatePool )
		local vowName = candidatePool[idx]

		injections[vowName] = (injections[vowName] or 0) + 1
		remaining = remaining - 1

		-- Check if this vow has now reached its max injectable rank
		local projectedRank = (GameState.ShrineUpgrades[vowName] or 0) + injections[vowName]
		local maxRank = ProvokeMod.GetVowMaxRank( vowName )
		if projectedRank >= maxRank then
			table.remove( candidatePool, idx )

			-- If pool emptied, try to refill with still-available vows
			if #candidatePool == 0 then
				for _, vName in ipairs( ProvokeMod.EligibleVows ) do
					local cRank = (GameState.ShrineUpgrades[vName] or 0) + (injections[vName] or 0)
					local mRank = ProvokeMod.GetVowMaxRank( vName )
					if cRank < mRank then
						table.insert( candidatePool, vName )
					end
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

	print("[ProvokeMod] Injected Transient Fear: " .. fearCost .. " points across " .. ProvokeMod.TableLength( injections ) .. " vows")
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

function ProvokeMod.RefreshDoorPreview( door )
	-- Destroy existing preview icons
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
	-- Recreate using the game's own function
	CreateDoorRewardPreview( door )
end

-- ============================================================================
-- Section 5: Provocation Choice Screen
-- ============================================================================

function ProvokeMod.OpenProvocationScreen( door )
	if IsScreenOpen( "ProvokeFatesScreen" ) then
		return
	end

	local screen = { Components = {}, Name = "ProvokeFatesScreen" }

	OnScreenOpened( screen )
	HideCombatUI( screen.Name )

	-- Background overlay
	screen.Components.Background = CreateScreenComponent({
		Name = "rectangle01",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = ScreenCenterY,
	})
	SetScale({ Id = screen.Components.Background.Id, Fraction = 10 })
	SetColor({ Id = screen.Components.Background.Id, Color = { 0.090, 0.055, 0.157, 0.85 } })

	-- Title
	screen.Components.TitleBacking = CreateScreenComponent({
		Name = "BlankObstacle",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = 200,
	})
	CreateTextBox({
		Id = screen.Components.TitleBacking.Id,
		Text = "Provoke the Fates",
		FontSize = 34,
		Color = { 0.74, 0.63, 1.0, 1.0 },
		Font = "P22UndergroundSCHeavy",
		ShadowBlur = 0, ShadowColor = { 0, 0, 0, 1 }, ShadowOffset = { 0, 3 },
		Justification = "Center",
	})

	-- Subtitle
	screen.Components.Subtitle = CreateScreenComponent({
		Name = "BlankObstacle",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = 250,
	})
	CreateTextBox({
		Id = screen.Components.Subtitle.Id,
		Text = "Upgrade this reward. The Fates will retaliate.",
		FontSize = 18,
		Color = { 0.75, 0.70, 0.85, 0.9 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})

	-- Calculate costs
	local regularCost = ProvokeMod.GetFearCost( "RegularBoon" )
	local enhancedCost = ProvokeMod.GetFearCost( "EnhancedBoon" )
	local hammerCost = ProvokeMod.GetFearCost( "Hammer" )

	local canRegular = regularCost <= config.MaxTransientFear
	local canEnhanced = enhancedCost <= config.MaxTransientFear
	local canHammer = hammerCost <= config.MaxTransientFear

	local buttonY = 360
	local buttonSpacing = 100

	-- Option 1: Regular Boon
	screen.Components.RegularBoon = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = buttonY,
	})
	screen.Components.RegularBoon.OnPressedFunctionName = "ProvokeMod__OnSelectRegularBoon"
	screen.Components.RegularBoon.Door = door
	screen.Components.RegularBoon.Screen = screen
	CreateTextBox({
		Id = screen.Components.RegularBoon.Id,
		Text = "Olympian Favor  (+" .. regularCost .. " Fear)",
		FontSize = 22,
		Color = canRegular and { 1.0, 1.0, 1.0, 1.0 } or { 0.4, 0.4, 0.4, 0.6 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})
	if not canRegular then
		UseableOff({ Id = screen.Components.RegularBoon.Id })
	end

	-- Option 2: Enhanced Boon
	screen.Components.EnhancedBoon = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = buttonY + buttonSpacing,
	})
	screen.Components.EnhancedBoon.OnPressedFunctionName = "ProvokeMod__OnSelectEnhancedBoon"
	screen.Components.EnhancedBoon.Door = door
	screen.Components.EnhancedBoon.Screen = screen
	CreateTextBox({
		Id = screen.Components.EnhancedBoon.Id,
		Text = "Exalted Favor  (+" .. enhancedCost .. " Fear)",
		FontSize = 22,
		Color = canEnhanced and { 1.0, 0.85, 0.45, 1.0 } or { 0.4, 0.4, 0.4, 0.6 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})
	if not canEnhanced then
		UseableOff({ Id = screen.Components.EnhancedBoon.Id })
	end

	-- Option 3: Hammer
	screen.Components.Hammer = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = buttonY + buttonSpacing * 2,
	})
	screen.Components.Hammer.OnPressedFunctionName = "ProvokeMod__OnSelectHammer"
	screen.Components.Hammer.Door = door
	screen.Components.Hammer.Screen = screen
	CreateTextBox({
		Id = screen.Components.Hammer.Id,
		Text = "Artificer's Design  (+" .. hammerCost .. " Fear)",
		FontSize = 22,
		Color = canHammer and { 1.0, 0.47, 0.20, 1.0 } or { 0.4, 0.4, 0.4, 0.6 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})
	if not canHammer then
		UseableOff({ Id = screen.Components.Hammer.Id })
	end

	-- Cancel button
	screen.Components.Cancel = CreateScreenComponent({
		Name = "ButtonDefault",
		Group = "Combat_Menu",
		X = ScreenCenterX,
		Y = buttonY + buttonSpacing * 3 + 30,
	})
	screen.Components.Cancel.OnPressedFunctionName = "ProvokeMod__OnCancel"
	screen.Components.Cancel.Screen = screen
	screen.Components.Cancel.ControlHotkey = "Cancel"
	CreateTextBox({
		Id = screen.Components.Cancel.Id,
		Text = "Keep Original Reward",
		FontSize = 18,
		Color = { 0.7, 0.7, 0.7, 0.9 },
		Font = "P22UndergroundSCMedium",
		Justification = "Center",
	})

	HandleScreenInput( screen )
end

function ProvokeMod.CloseProvocationScreen( screen )
	OnScreenCloseStarted( screen )
	CloseScreen( GetAllIds( screen.Components ), 0.1, screen )
	OnScreenCloseFinished( screen )
	ShowCombatUI( screen.Name )
end

-- ============================================================================
-- Section 6: Global Button Handlers
-- ============================================================================
-- These must be accessible via CallFunctionName (game global scope).
-- Since ENVY scopes our globals to the plugin, we register them on the game table.

game.ProvokeMod__OnSelectRegularBoon = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	ProvokeMod.TransformDoor( button.Door, "RegularBoon" )
	ProvokeMod.CloseProvocationScreen( screen )
end

game.ProvokeMod__OnSelectEnhancedBoon = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	ProvokeMod.TransformDoor( button.Door, "EnhancedBoon" )
	ProvokeMod.CloseProvocationScreen( screen )
end

game.ProvokeMod__OnSelectHammer = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuConfirm" })
	ProvokeMod.TransformDoor( button.Door, "Hammer" )
	ProvokeMod.CloseProvocationScreen( screen )
end

game.ProvokeMod__OnCancel = function( screen, button )
	PlaySound({ Name = "/SFX/Menu Sounds/IrisMenuBack" })
	ProvokeMod.CloseProvocationScreen( screen )
end

-- ============================================================================
-- Section 7: Room Entry/Exit Fear Management
-- ============================================================================

-- Called from StartRoom wrap after the room initializes
function ProvokeMod.OnRoomStart( currentRun, currentRoom )
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
end

-- Called from EndEncounterEffects wrap before the base function
function ProvokeMod.OnEncounterEnd( currentRun, currentRoom, currentEncounter )
	ProvokeMod.RemoveTransientFear()
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
