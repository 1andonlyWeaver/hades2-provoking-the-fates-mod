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
	if ProvokeMod.Log then ProvokeMod.Log.info( "run", "start" ) end
	return base( prevRun, args )
end, mod )

-- ============================================================================
-- Hook 2: Safety cleanup on hero death
-- ============================================================================
modutil.mod.Path.Wrap( "KillHero", function( base, victim, triggerArgs )
	if ProvokeMod.Log then
		local stacks = ProvokeMod.RunState and ProvokeMod.RunState.ActiveFearStacks or {}
		ProvokeMod.Log.info( "run", "death", {
			liveStacks       = #stacks,
			fearWasActive    = (ProvokeMod.RunState and ProvokeMod.RunState.TransientFearActive) or false,
			provocationCount = (ProvokeMod.RunState and ProvokeMod.RunState.ProvocationCount) or 0,
		} )
	end
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
		-- If Interact was already released before this wrap ran, the press was
		-- a quick tap whose release we can't retroactively catch. Pass through
		-- to base Proceed. Only arm the release listener when the button is
		-- still held at this point.
		if IsControlDown({ Name = "Use" }) or IsControlDown({ Name = "Interact" }) then
			local notifyName = ProvokeMod.HoldReleaseNotifyName or "ProvokeMod__HoldRelease"
			local threshold  = (config and config.ProvokeHoldSeconds) or 0.5
			ProvokeMod.Log.debug( "gate", "armed", { threshold = threshold, objectId = door.ObjectId } )
			NotifyOnControlReleased({
				Names   = { "Use", "Interact" },
				Notify  = notifyName,
				Timeout = threshold,
			})
			waitUntil( notifyName )
			local timedOut = _eventTimeoutRecord and _eventTimeoutRecord[ notifyName ]
			if _eventTimeoutRecord then _eventTimeoutRecord[ notifyName ] = nil end
			if timedOut then
				-- Held past threshold: open provocation screen, suppress Proceed.
				-- AttemptUseDoor set door.InUse = true before calling us; clear it
				-- so the player can re-interact with this door after the menu closes
				-- (AttemptUseDoor early-returns at RoomLogic.lua:751 when InUse).
				door.InUse = false
				ProvokeMod.Log.debug( "gate", "hold (open menu)", { objectId = door.ObjectId } )
				ProvokeMod.OpenProvocationScreen( door )
				return
			end
			-- Released before threshold: short tap, continue with normal Proceed.
			ProvokeMod.Log.debug( "gate", "tap (proceed)", { objectId = door.ObjectId } )
		end
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

	-- Drop any abandoned Fields cage provocations too — if the player left
	-- without triggering a provoked cage, its ObjectId is gone and the
	-- FearCost shouldn't keep counting against the next room's capacity.
	ProvokeMod.RunState.ProvokedCages = {}

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
	ProvokeMod.OnShowUseButton( objectId, useTarget )
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

-- ============================================================================
-- Hook 9: Apply active door-fear stacks at every combat encounter start
-- ============================================================================
-- Vanilla calls StartEncounter(currentRun, currentRoom, encounter) at the top
-- of every encounter — the first wave of a single-combat room, each wave in a
-- multi-wave room, and the combat that StartFieldsEncounter kicks off inside
-- a Fields cage. ApplyActiveStacksForEncounter is idempotent (the additive
-- `already` clamp inside ApplyInjectionAdditively zeroes out duplicate
-- ranks), so firing it here gets every encounter's ShrineUpgrades injection
-- regardless of whether a parallel Fields passive encounter already fired
-- it first. OnEncounterEnd then restores + decays per-encounter — matching
-- the "N encounters left" label the player reads.
modutil.mod.Path.Wrap( "StartEncounter", function( base, currentRun, currentRoom, encounter )
	ProvokeMod.ApplyActiveStacksForEncounter()
	return base( currentRun, currentRoom, encounter )
end, mod )

-- ============================================================================
-- Hook 10: Apply provoked-cage Fear when the player triggers the combat
-- ============================================================================
-- StartFieldsEncounter (EncounterLogic.lua:2884) runs when the player uses a
-- FieldsRewardCage. If the cage was produced by TransformFieldsPickup, its
-- pre-rolled injection lives at RunState.ProvokedCages[cage.ObjectId]; apply
-- it to ShrineUpgrades just before the base call so the spawning enemies see
-- the boosted vow ranks. Restore is handled by OnEncounterEnd's existing
-- RestoreVowsAndDecayStacks → RestoreVowsOnly pipeline.
modutil.mod.Path.Wrap( "StartFieldsEncounter", function( base, rewardCage, args )
	if rewardCage ~= nil and rewardCage.ObjectId ~= nil
		and ProvokeMod.RunState.ProvokedCages ~= nil
	then
		local cageData = ProvokeMod.RunState.ProvokedCages[rewardCage.ObjectId]
		if cageData ~= nil and not cageData.FearApplied then
			ProvokeMod.Log.info( "fields", "applying cage fear on encounter start", {
				cageId     = rewardCage.ObjectId,
				choiceType = cageData.ChoiceType,
				fearCost   = cageData.FearCost,
			} )
			ProvokeMod.ApplyCageFear( cageData )
		end
	end
	return base( rewardCage, args )
end, mod )

-- ============================================================================
-- Hook 11: Long-press gate on Fields pickups
-- ============================================================================
-- UseConsumableItem fires when the player interacts with a free-floating
-- consumable (MetaCurrencyDrop = Ash/Bones/Psyche in Mourning Fields). For
-- provokable pickups we arm the same hold-vs-tap gate we use on doors: a short
-- tap passes through to normal consumption; a hold past ProvokeHoldSeconds
-- opens the provocation menu and suppresses the base call.
modutil.mod.Path.Wrap( "UseConsumableItem", function( base, consumableItem, args, user )
	if consumableItem ~= nil and ProvokeMod.IsProvokableFieldsPickup( consumableItem ) then
		if IsControlDown({ Name = "Use" }) or IsControlDown({ Name = "Interact" }) then
			local notifyName = "ProvokeMod__HoldReleasePickup"
			local threshold  = (config and config.ProvokeHoldSeconds) or 0.5
			ProvokeMod.Log.debug( "gate", "armed (pickup)", {
				threshold = threshold,
				objectId  = consumableItem.ObjectId,
				name      = consumableItem.Name,
			} )
			NotifyOnControlReleased({
				Names   = { "Use", "Interact" },
				Notify  = notifyName,
				Timeout = threshold,
			})
			waitUntil( notifyName )
			local timedOut = _eventTimeoutRecord and _eventTimeoutRecord[ notifyName ]
			if _eventTimeoutRecord then _eventTimeoutRecord[ notifyName ] = nil end
			if timedOut then
				ProvokeMod.Log.debug( "gate", "hold (open pickup menu)", {
					objectId = consumableItem.ObjectId,
				} )
				ProvokeMod.OpenProvocationScreen( consumableItem )
				return
			end
			ProvokeMod.Log.debug( "gate", "tap (consume pickup)", {
				objectId = consumableItem.ObjectId,
			} )
		end
	end
	return base( consumableItem, args, user )
end, mod )
