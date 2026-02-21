---@meta _
-- globals we define are private to our plugin!
---@diagnostic disable: lowercase-global

-- here is where your mod sets up all the things it will do.
-- this file will not be reloaded if it changes during gameplay
-- 	so you will most likely want to have it reference
--	values and functions later defined in `reload.lua`.

-- ============================================================================
-- Hook 1: Reset per-run state on new run
-- ============================================================================
modutil.mod.Path.Wrap( "StartNewRun", function( base, prevRun, args )
	ProvokeMod.ResetRunState()
	return base( prevRun, args )
end, mod )

-- ============================================================================
-- Hook 2: Safety cleanup on hero death
-- ============================================================================
modutil.mod.Path.Wrap( "KillHero", function( base, victim, triggerArgs )
	ProvokeMod.RemoveTransientFear()
	ProvokeMod.ResetRunState()
	return base( victim, triggerArgs )
end, mod )

-- ============================================================================
-- Hook 3: Prepare transient fear on room exit
-- ============================================================================
modutil.mod.Path.Wrap( "LeaveRoom", function( base, currentRun, door )
	-- If this door was provoked, queue fear for the next room
	local provokeData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	if provokeData and provokeData.Provoked then
		ProvokeMod.RunState.PendingFearCost = provokeData.FearCost
		ProvokeMod.RunState.LastFearCost = provokeData.FearCost
	end

	-- Remove hint and kill background listener before leaving
	ProvokeMod.DespawnProvokeHint()

	-- Safety: always remove any active transient fear when leaving a room
	ProvokeMod.RemoveTransientFear()

	return base( currentRun, door )
end, mod )

-- ============================================================================
-- Hook 4: Inject transient fear on room start
-- ============================================================================
modutil.mod.Path.Wrap( "StartRoom", function( base, currentRun, currentRoom )
	-- Inject fear BEFORE base, because base blocks through the entire encounter
	ProvokeMod.OnRoomStart( currentRun, currentRoom )

	return base( currentRun, currentRoom )
end, mod )

-- ============================================================================
-- Hook 5: Remove transient fear on encounter end
-- ============================================================================
modutil.mod.Path.Wrap( "EndEncounterEffects", function( base, currentRun, currentRoom, currentEncounter )
	-- Remove transient fear BEFORE base processes rewards/unlocks
	-- so vow values don't leak into next-room calculations
	ProvokeMod.OnEncounterEnd( currentRun, currentRoom, currentEncounter )

	return base( currentRun, currentRoom, currentEncounter )
end, mod )

-- ============================================================================
-- Hook 6: Start hotkey listener after exit doors are unlocked and ready
-- ============================================================================
modutil.mod.Path.Wrap( "DoUnlockRoomExits", function( base, ... )
	local result = base( ... )
	-- Doors now have ReadyToUse = true and MapState.OfferedExitDoors is populated
	ProvokeMod.OnExitsUnlocked()
	return result
end, mod )

-- ============================================================================
-- Hook 7: Show/hide provoke hint based on door proximity (UsePrompt visibility)
-- ============================================================================
modutil.mod.Path.Wrap( "ShowUseButton", function( base, objectId, useTarget )
	local result = base( objectId, useTarget )
	ProvokeMod.OnShowUseButton( objectId )
	return result
end, mod )
