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
-- Hook 3: Long-press gate + transient fear on room exit
-- ============================================================================
-- LeaveRoom is called when the player presses Interact on a door. If the door
-- is provokable, we gate the call behind a release-or-timeout check: short tap
-- = pass through to base (normal Proceed); held past ProvokeHoldSeconds = open
-- the provocation screen and skip base entirely.
modutil.mod.Path.Wrap( "LeaveRoom", function( base, currentRun, door )
	if door ~= nil and ProvokeMod.IsProvokableDoor( door ) then
		local notifyName = ProvokeMod.HoldReleaseNotifyName or "ProvokeMod__HoldRelease"
		local threshold  = (config and config.ProvokeHoldSeconds) or 0.5
		NotifyOnControlReleased({
			Names   = { "Interact" },
			Notify  = notifyName,
			Timeout = threshold,
		})
		waitUntil( notifyName )
		if _eventTimeoutRecord and _eventTimeoutRecord[ notifyName ] then
			-- Held past threshold: open provocation screen, suppress Proceed.
			ProvokeMod.OpenProvocationScreen( door )
			return
		end
		-- Released before threshold: short tap, continue with normal Proceed.
	end

	-- If this door was provoked, push a Fear stack for the upcoming room(s).
	-- The stack persists for multiple rooms depending on type and greed count.
	local doorId = door and door.ObjectId
	local provokeData = ProvokeMod.RunState.ProvokedDoors[doorId]
	if provokeData and provokeData.Provoked then
		local injection = provokeData.PreviewedInjection
			or ProvokeMod.SelectThemedVows( provokeData.FearCost )
		ProvokeMod.QueueFearStack( provokeData.ChoiceType, injection, provokeData.FearCost )
		ProvokeMod.RunState.LastFearCost = provokeData.FearCost
	end

	-- Remove hint and kill background listener before leaving
	ProvokeMod.DespawnProvokeHint()

	-- Safety: always restore baseline ranks when leaving a room. Stack decay is
	-- handled by RestoreVowsAndDecayStacks at end-of-last-encounter.
	ProvokeMod.RestoreVowsOnly()

	-- Clear provoked door state for the room being left. Door ObjectIds can be
	-- reused by subsequent rooms; stale entries would cause natural Boon doors
	-- to be misidentified as previously-provoked MetaProgress doors.
	ProvokeMod.RunState.ProvokedDoors = {}

	-- Restore RewardStoreName before base pushes CurrentRoom into RoomHistory,
	-- so CalcMetaProgressRatio counts this provoked room as MetaProgress in
	-- all future ratio calculations.
	local currentRoom = currentRun and currentRun.CurrentRoom
	if currentRoom and currentRoom._OriginalRewardStoreName ~= nil then
		currentRoom.RewardStoreName = currentRoom._OriginalRewardStoreName
		currentRoom._OriginalRewardStoreName = nil
	end

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
modutil.mod.Path.Wrap( "DoUnlockRoomExits", function( base, run, room )
	-- Temporarily restore RewardStoreName so ChooseNextRewardStore (called inside
	-- base) computes the correct MetaProgress ratio for the next room's doors.
	local savedStoreName = nil
	if room ~= nil and room._OriginalRewardStoreName ~= nil then
		savedStoreName = room.RewardStoreName
		room.RewardStoreName = room._OriginalRewardStoreName
	end
	local result = base( run, room )
	if savedStoreName ~= nil then
		room.RewardStoreName = savedStoreName
	end
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

-- ============================================================================
-- Hook 8: Clear nearest-door tracking when player leaves door proximity
-- ============================================================================
modutil.mod.Path.Wrap( "HideUseButton", function( base, objectId, useTarget, fadeDuration )
	local result = base( objectId, useTarget, fadeDuration )
	ProvokeMod.OnHideUseButton( objectId )
	return result
end, mod )
