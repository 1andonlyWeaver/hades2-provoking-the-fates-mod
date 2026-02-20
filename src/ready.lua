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
mod.Path.Wrap( "StartNewRun", function( base, prevRun, args )
	ProvokeMod.ResetRunState()
	return base( prevRun, args )
end, mod )

-- ============================================================================
-- Hook 2: Safety cleanup on hero death
-- ============================================================================
mod.Path.Wrap( "KillHero", function( base, victim, triggerArgs )
	ProvokeMod.RemoveTransientFear()
	ProvokeMod.ResetRunState()
	return base( victim, triggerArgs )
end, mod )

-- ============================================================================
-- Hook 3: Intercept door interaction for MetaProgress doors
-- ============================================================================
mod.Path.Wrap( "AttemptUseDoor", function( base, door, args )
	-- Only intercept MetaProgress doors that haven't been handled yet
	if ProvokeMod.IsMetaProgressDoor( door )
		and not ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
		and door.ReadyToUse
		and CheckRoomExitsReady( CurrentRun.CurrentRoom )
		and CheckSpecialDoorRequirement( door ) == nil
		and not door.InUse
		and not door.EncounterCost
	then
		-- Open the provocation screen in a thread (it blocks until closed)
		thread( function()
			ProvokeMod.OpenProvocationScreen( door )

			-- After screen closes: if the player didn't provoke, mark declined
			-- so we don't prompt again on the same door
			if not ProvokeMod.RunState.ProvokedDoors[door.ObjectId] then
				ProvokeMod.RunState.ProvokedDoors[door.ObjectId] = { Declined = true }
			end
		end)
		return -- Don't call base; player hasn't chosen to enter yet
	end

	-- Normal door use (already provoked, declined, or non-MetaProgress)
	return base( door, args )
end, mod )

-- ============================================================================
-- Hook 4: Prepare transient fear on room exit
-- ============================================================================
mod.Path.Wrap( "LeaveRoom", function( base, currentRun, door )
	-- If this door was provoked, queue fear for the next room
	local provokeData = ProvokeMod.RunState.ProvokedDoors[door.ObjectId]
	if provokeData and provokeData.Provoked then
		ProvokeMod.RunState.PendingFearCost = provokeData.FearCost
		ProvokeMod.RunState.LastFearCost = provokeData.FearCost
	end

	-- Safety: always remove any active transient fear when leaving a room
	ProvokeMod.RemoveTransientFear()

	return base( currentRun, door )
end, mod )

-- ============================================================================
-- Hook 5: Inject transient fear on room start
-- ============================================================================
mod.Path.Wrap( "StartRoom", function( base, currentRun, currentRoom )
	-- Let the room initialize fully first
	local result = base( currentRun, currentRoom )

	-- Then inject fear if we have a pending provocation
	ProvokeMod.OnRoomStart( currentRun, currentRoom )

	return result
end, mod )

-- ============================================================================
-- Hook 6: Remove transient fear on encounter end
-- ============================================================================
mod.Path.Wrap( "EndEncounterEffects", function( base, currentRun, currentRoom, currentEncounter )
	-- Remove transient fear BEFORE base processes rewards/unlocks
	-- so vow values don't leak into next-room calculations
	ProvokeMod.OnEncounterEnd( currentRun, currentRoom, currentEncounter )

	return base( currentRun, currentRoom, currentEncounter )
end, mod )
