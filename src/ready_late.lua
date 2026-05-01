---@meta _
-- globals we define are private to our plugin!
---@diagnostic disable: lowercase-global

-- Cross-mod compatibility hooks that must run after every plugin's on_ready
-- has registered itself in rom.mods. Anything in this file runs exactly once
-- per game session — never on hot-reload — so wrap registration here is safe
-- from accumulating across reloads.

local modsRegistry = rom and rom.mods
local nightmareFearLoaded = modsRegistry ~= nil
	and modsRegistry["ReadEmAndWeep-Nightmare_Fear"] ~= nil

ProvokeMod.NightmareFearLoaded = nightmareFearLoaded

if nightmareFearLoaded then
	-- Nightmare Fear queries GetNumShrineUpgrades for four of its vows at
	-- lifecycle points outside our StartEncounter→EndEncounterEffects injection
	-- window (room start before StartEncounter, LeaveRoom, post-combat reward
	-- presentation, ValidateMaxMana on trait add). At those points
	-- GameState.ShrineUpgrades only holds baseline ranks, so the transient
	-- Fear stack would be ignored. Top the value up here with active stacks,
	-- clamped to the vow's max rank to mirror what ApplyInjectionAdditively
	-- would have written during an encounter.
	modutil.mod.Path.Wrap( "GetNumShrineUpgrades", function( base, upgradeName )
		local value = base( upgradeName )

		local outOfBand = ProvokeMod.NightmareFearOutOfBandVows
		if outOfBand == nil or not outOfBand[upgradeName] then
			return value
		end

		-- Inside the injection window, base() already includes the boost.
		-- Skip to avoid double-count if any caller queries during combat
		-- (e.g., ValidateMaxMana fired by a mid-combat trait acquisition).
		local runState = ProvokeMod.RunState
		if runState ~= nil and runState.TransientFearActive then
			return value
		end

		local stacks = runState and runState.ActiveFearStacks
		if stacks == nil or #stacks == 0 then return value end

		local ranksToAdd = 0
		for _, stack in ipairs( stacks ) do
			local r = stack.Injection and stack.Injection[upgradeName]
			if r then ranksToAdd = ranksToAdd + r end
		end
		if ranksToAdd == 0 then return value end

		-- Clamp at the vow's max rank: NF's NoMana formula goes negative past
		-- rank 4, BlindReward saturates at rank 4 (100% chance), and vanilla
		-- ApplyInjectionAdditively already enforces this cap on the live-
		-- encounter path. Tax and LowManaStart are inside their max ranks (3
		-- and 1) for any single provocation.
		--
		-- GetVowMaxRank returns 0 if the vow is missing from MetaUpgradeData
		-- (e.g., NF renamed it under us). headroom collapses to 0 →
		-- applied = 0 → return base unchanged. Safe silent fallback rather
		-- than a hard error.
		local maxRank = ProvokeMod.GetVowMaxRank( upgradeName )
		local headroom = math.max( 0, maxRank - value )
		local applied = math.min( ranksToAdd, headroom )
		return value + applied
	end, mod )

	if ProvokeMod.Log then
		ProvokeMod.Log.info( "compat", "Nightmare Fear detected; GetNumShrineUpgrades wrap installed" )
	end
end

-- =============================================================================
-- Pom-of-Power option-cache fix.
--
-- Vanilla CreateLoot (RoomLogic.lua:2265) calls SetTraitsOnLoot at LOOT-SPAWN
-- time, populating lootData.UpgradeOptions before the player ever picks up the
-- StackUpgrade. By the time HandleLootPickup increments
-- CurrentRun.LootTypeHistory["StackUpgrade"] and OpenUpgradeChoiceMenu calls
-- RandomSynchronize on it (UpgradeChoiceLogic.lua:93), the options are already
-- baked. CreateBoonLootButtons (UpgradeChoiceLogic.lua:113-134) then takes the
-- StackOnly cached-reuse branch — because the hero owns every cached option,
-- which is necessarily true for a Pom — and skips regeneration. Two
-- consecutive provoked Poms therefore present identical option lists despite
-- LootTypeHistory advancing correctly.
--
-- Vanilla Poms still bake at spawn the same way, but they're rare enough per
-- run and surrounded by enough other RNG-consuming work that the
-- spawn-cursor coincidence rarely surfaces. Provoked Poms appear far more
-- often and on a more deterministic cursor, exposing the quirk.
--
-- Fix: when the door we just left through was a Pom provocation
-- (RunState.NextRewardIsProvokedPom, set in src/ready.lua's LeaveRoom hook),
-- null out source.UpgradeOptions before delegating so CreateBoonLootButtons
-- re-enters the `nil → SetTraitsOnLoot` branch under the just-incremented
-- LootTypeHistory["StackUpgrade"] seed. The flag is consumed on first use so a
-- back-out + reopen reuses the (now freshly rolled) options instead of
-- offering the player a free reroll. Vanilla Pom doors are untouched.
modutil.mod.Path.Wrap( "OpenUpgradeChoiceMenu", function( base, source, args )
	if source ~= nil
		and source.Name == "StackUpgrade"
		and ProvokeMod.RunState
		and ProvokeMod.RunState.NextRewardIsProvokedPom
	then
		source.UpgradeOptions = nil
		ProvokeMod.RunState.NextRewardIsProvokedPom = false
		if ProvokeMod.Log then
			ProvokeMod.Log.info( "provoke_pom",
				"cleared cached UpgradeOptions for provoked StackUpgrade",
				{ objectId = source.ObjectId } )
		end
	end
	return base( source, args )
end, mod )
