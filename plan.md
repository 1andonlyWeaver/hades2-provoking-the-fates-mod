# **Hades 2 Mod Design Document: Provoking the Fates**

## **1\. Overview & Philosophy**

**"Provoking the Fates"** is a back-end logic mod designed to enhance the player's power fantasy in *Hades 2* while strictly adhering to the philosophy of "earned power."

The mod allows players to bypass the game's intentional scarcity of Boons and Daedalus Hammers by forcefully upgrading minor reward doors. In exchange, the game aggressively retaliates by injecting temporary, localized "Fear" (Oath of the Unseen modifiers) strictly into that upcoming encounter. Players can become unstoppably powerful, but only if they have the mechanical skill to survive the extreme difficulty spikes they bring upon themselves.

## **2\. Core Mechanics: The Player Flow**

### **Step 1: The Trigger**

When Melinoë approaches a door offering a minor, meta-progression reward (e.g., Bones, Ash, Psyche), a secondary interaction prompt appears beneath the standard entry prompt:

* \[Cast Button\] \- Provoke the Fates (Text is tinted Oath Purple).

### **Step 2: The Choice (UI Hijack)**

Pressing the prompt pauses the game and opens a custom 3-card selection menu, repurposing the vanilla Boon Selection UI. The player must choose their upgrade, paying with "Transient Fear" (temporary difficulty modifiers added to the next room).

* **Option A: Olympian Favor (Regular Boon)**  
  * *Cost:* Base \+3 Transient Fear  
  * *Result:* Upgrades the door to a standard God Boon.  
* **Option B: Exalted Favor (Enhanced Boon)**  
  * *Cost:* Base \+6 Transient Fear  
  * *Result:* Upgrades the door to a Boon with significantly boosted rarity chances (Rare/Epic/Heroic/Duo).  
* **Option C: Artificer's Design (Daedalus Hammer)**  
  * *Cost:* Base \+10 Transient Fear  
  * *Result:* Upgrades the door to a Daedalus Hammer, bypassing the vanilla run limit.

### **Step 3: The Transformation**

Upon selection, the 3-card menu closes. A heavy anvil sound effect plays, and the door's original reward icon burns away, replaced by the newly selected reward icon. The player is now locked in and must enter the room.

## **3\. The Economy of Fear**

### **Transient Fear**

Transient Fear consists of random Vows from the Oath of the Unseen temporarily added to the CurrentRun.ActiveVows array when the room loads, and instantly removed upon the room's OnRoomClear event.

### **The Greed Multiplier**

To prevent players from spamming the mod in every room, the mod tracks how many times the player has Provoked the Fates during the current run. Each subsequent use increases the Fear cost of all options by a flat amount (default: \+1).

* *Example:* The first Hammer costs 10 Fear. The second Hammer costs 11 Fear. The third costs 12\.

### **The Spillover Mechanic (Fear Overlap)**

If the mod randomly selects a Vow to inject that the player has *already* maxed out in their baseline Oath settings, the script triggers the "Spillover" function:

* The script actively searches for Vows the player has at **Rank 0**.  
* It applies the Transient Fear to those empty slots instead.  
* *Design Intent:* This prevents players from absorbing the penalty into stats they are already comfortable with, forcing them to face mechanics they intentionally avoided (targeting the build's blind spots).

## **4\. Visual & UI Implementation (Zero Custom Assets)**

The mod relies entirely on manipulating existing *Hades 2* assets via Lua.

* **The Door Icon:** The upgraded reward icon is tinted with a pulsating purple/black hex code. A small purple "Fear Skull" badge is overlaid in the bottom-right corner of the reward bubble.  
* **Environmental VFX:** Once provoked, the base of the doorway emits the creeping purple fog particles used in Chaos gates or Erebus traps.  
* **The Warning Tooltip:** The standard UI info-box (right side of the screen) overrides its usual flavor text to read **"TRANSIENT VOWS ACTIVE"** and displays the exact 2D icons of the Vows waiting inside.  
* **Room Entry:** Upon spawning into the provoked room, the top-screen UI banner drops down reading: *"The Fates are Provoked (+X Fear)."* A global red/purple color flash briefly hits the screen.

## **5\. Back-End Logic & Overrides**

To function, the mod's Lua scripts must hook into several core game loops:

1. **EncounterData Hot-Swap:** Intercepts the LeaveRoom or LoadMap function to overwrite the RewardType and inject the temporary Fear array.  
2. **MaxLoot Bypass:** Actively ignores the vanilla global variable that hard-caps Daedalus Hammers at 2-3 per run, allowing infinite Hammers if the player can survive the cost.  
3. **Cleanup Protocol:** Hooks into the OnRoomClear event to reliably subtract the exact Transient Vows added, ensuring the baseline run Fear is never permanently altered.

## **6\. Player Configuration (config.lua)**

The mod includes a highly accessible configuration file, allowing players to tailor the difficulty to their exact preferences:

ProvokeConfig \= {  
    \-- BASE TRANSIENT FEAR COSTS  
    Cost\_RegularBoon \= 3,  
    Cost\_EnhancedBoon \= 6,  
    Cost\_Hammer \= 10,

    \-- THE GREED MULTIPLIER  
    EnableGreed \= true,            
    GreedPenalty\_PerUse \= 1,       
      
    \-- SAFETY LIMITS  
    MaxTransientFear \= 25,         
}  
