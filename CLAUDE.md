# CLAUDE.md

## Project Overview

**Provoking the Fates** is a Hades 2 gameplay mod written in Lua. It lets players upgrade minor reward doors (Bones, Ash, Psyche) into Boons or Daedalus Hammers at the cost of temporary Oath of the Unseen difficulty spikes ("Transient Fear"). The mod runs on the Hell2Modding plugin framework and is published to Thunderstore.

**Author:** 1andonlyWeaver
**Version:** 0.0.1 (unreleased)
**License:** MIT

## Repository Structure

```
├── src/                         # All Lua source (deployed to plugins/)
│   ├── main.lua                 # Entry point: dependency loading, lifecycle registration
│   ├── config.lua               # User-tunable settings (costs, greed, limits)
│   ├── ready.lua                # One-time hooks: 8 game function wraps via ModUtil
│   ├── reload.lua               # Core logic (~1000 lines): fear engine, door transforms, UI
│   ├── ready_late.lua           # Late one-time init (minimal)
│   └── reload_late.lua          # Late reload init (minimal)
├── .github/workflows/
│   └── release.yaml             # CI: validate, build, publish to Thunderstore, tag release
├── thunderstore.toml            # Package metadata, dependencies, build config
├── plan.md                      # Design document (mechanics spec, philosophy)
├── README.md                    # User-facing documentation
├── CHANGELOG.md                 # Keep a Changelog format
├── icon.png                     # Mod icon (Thunderstore listing)
└── LICENSE                      # MIT
```

## Architecture

### Module Lifecycle

The mod uses a four-stage plugin lifecycle managed by `main.lua`:

1. **`ready.lua`** — Runs once on mod load. Registers 8 `modutil.mod.Path.Wrap` hooks into game functions (`StartNewRun`, `KillHero`, `LeaveRoom`, `StartRoom`, `EndEncounterEffects`, `DoUnlockRoomExits`, `ShowUseButton`, `HideUseButton`).
2. **`reload.lua`** — Runs on every game reload. Defines all mod logic. Safe to re-execute repeatedly (hot-reload via ReLoad).
3. **`ready_late.lua`** / **`reload_late.lua`** — Late-stage hooks (currently minimal placeholders).

### Key Subsystems in `reload.lua`

| Section | Lines | Purpose |
|---------|-------|---------|
| Module State & Constants | 1–49 | `ProvokeMod` table, `EligibleVows` list, `RunState` initialization |
| Utility Functions | 51–246 | Cost calculation, door eligibility checks, hotkey listener, HUD hints |
| Transient Fear Engine | 248–359 | Vow selection with spillover, `InjectTransientFear`, `RemoveTransientFear` |
| Door Transformation | 361–516 | `TransformDoor`, `UnTransformDoor`, icon refresh |
| Provocation Choice Screen | 518–745 | 3-card UI menu with re-provoke support |
| Global Button Handlers | 753–798 | `game.ProvokeMod__On*` callbacks (required by game's `CallFunctionName`) |
| Room Entry/Exit Fear Mgmt | 800–893 | Fear injection on room start, removal on encounter end |
| Vow Display | 895–1001 | Human-readable vow names, value formatting, banner text |

### State Management

All per-run state lives in `ProvokeMod.RunState` (reset on `StartNewRun` and `KillHero`):
- `ProvocationCount` — greed multiplier tracker
- `ActiveTransientVows` — map of currently injected vow data
- `ProvokedDoors` — map of door ObjectId to provocation data
- `PendingFearCost` — fear queued for next room entry
- `NearestProvokableDoor` — proximity-tracked door reference

### Global Scope Convention

ENVY scopes all mod globals privately. Functions that must be callable by the game engine (e.g., button handlers) are registered on the `game` table with the `ProvokeMod__` prefix:
```lua
game.ProvokeMod__OnSelectRegularBoon = function(screen, button) ... end
```

## Dependencies

| Mod | Purpose |
|-----|---------|
| Hell2Modding | Core mod infrastructure / Lua runtime |
| ModUtil | Game function wrapping (`Path.Wrap`) and mod registration |
| SJSON | JSON serialization for game data |
| Chalk | Auto-generates config files in r2modman config folder |
| ReLoad | Hot-reload support during gameplay |
| ENVY | Plugin-scoped globals (prevents namespace pollution) |

Versions are pinned in `thunderstore.toml` under `[package.dependencies]`.

## Configuration

`src/config.lua` defines user-tunable values loaded via Chalk (hot-reloadable without game restart):

| Key | Default | Description |
|-----|---------|-------------|
| `Cost_RegularBoon` | 2 | Base fear cost for standard Boon |
| `Cost_EnhancedBoon` | 5 | Base fear cost for enhanced rarity Boon |
| `Cost_Hammer` | 9 | Base fear cost for Daedalus Hammer |
| `EnableGreed` | true | Toggle exponential greed multiplier |
| `GreedPenalty_PerUse` | 1 | Greed scaling factor (series: 1, 2, 4, 8...) |
| `MaxTransientFear` | 19 | Maximum fear injectable per room |
| `ProvokeHotkey` | "Shout" | Input control name for the provoke action |

Note: Base costs are set 1 below the desired first-use total because greed adds `2^0 * GreedPenalty_PerUse = 1` on the first provocation.

## Build & Release

### Build Tool

Thunderstore CLI (`tcli`). Configured in `thunderstore.toml`.

```bash
# Install tcli (requires .NET)
dotnet tool install -g tcli

# Build package locally
tcli build
# Output goes to ./build/
```

### Release Process

Triggered via GitHub Actions manual workflow dispatch (`.github/workflows/release.yaml`):

1. Input: semantic version tag (e.g., `1.0.0`), optional dry-run flag
2. Validates tag format (`X.Y.Z`)
3. Rotates `CHANGELOG.md` unreleased section to versioned section
4. Updates `versionNumber` in `thunderstore.toml`
5. Replaces relative image paths in README with absolute GitHub URLs
6. Builds with `tcli build`
7. Publishes to Thunderstore (requires `TCLI_AUTH_TOKEN` secret)
8. Creates git tag and GitHub release

### Local Testing

Manual testing via r2modman (Hades 2 mod manager). No automated test suite exists. Debug output uses `print("[ProvokeMod] ...")` throughout the codebase.

## Code Conventions

### Naming
- **PascalCase** for module name (`ProvokeMod`), function names, and state fields
- **camelCase** for local variables and parameters
- **SCREAMING_SNAKE** not used; config keys use `PascalCase_With_Underscores`
- Global button handlers: `ProvokeMod__` prefix (double underscore)

### Lua Style
- Semicolons in config table definitions, commas in runtime tables
- Tabs for indentation
- Spaces inside parentheses for function calls: `func( arg1, arg2 )`
- Section dividers: `-- ====...====` comment blocks
- `---@diagnostic disable` directives for VS Code Lua language server warnings
- `---@meta _` at top of module files
- `---@module 'name'` annotations for dependency imports

### Patterns
- **Idempotent cleanup**: `RemoveTransientFear()` and `UnTransformDoor()` are safe to call multiple times
- **Wrapper hooks**: All game integration uses `modutil.mod.Path.Wrap` (never overwrites original functions)
- **Threaded async**: Hotkey listening and UI animations use `thread()` / `wait()` / `waitUntil()`
- **Defensive nil checks**: Functions guard against nil door/room/encounter data

### What NOT to Do
- Do not define globals without going through the `game` table (ENVY will scope them privately)
- Do not modify `GameState.ShrineUpgrades` without storing originals for restoration
- Do not assume door `ObjectId` values persist across rooms (they can be reused)
- Do not add non-combat vows to `EligibleVows` (vows like ShopPrices or BiomeSpeed have no meaningful single-room effect)

## Key Design Decisions

- **Fear is transient**: Injected vows are always removed on encounter end or room exit. Multiple safety nets ensure no permanent game state corruption.
- **Greed is exponential**: Cost formula is `baseCost + 2^count * GreedPenalty_PerUse` to prevent spamming.
- **Spillover targets blind spots**: When maxed vows are selected, fear redirects to Rank-0 vows the player intentionally avoided.
- **Re-provoke support**: Players can change or revert their door choice before entering. Undo decrements greed counter.
- **Multi-encounter safety**: `RoomEncounterCount` / `RoomEncountersCompleted` tracking ensures fear removal only after the last encounter in a room.

## Changelog Convention

Follows [Keep a Changelog v1.1.0](https://keepachangelog.com/en/1.1.0/) with [Semantic Versioning](https://semver.org/). The release workflow automatically rotates the `[Unreleased]` section.
