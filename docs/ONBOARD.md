# ONBOARD.md — NULLWIDE `src/` reference

Companion document to `AGENTS.md`. Scope of the scan: **`/src` only**.
Everything outside `/src` (`archive/`, `addons/`, `project.godot`) is mentioned
only where `/src` files depend on it.

Read `AGENTS.md` → `addons/fennara/ai/guidelines.md` first for any Godot file
work. This document answers *"what is in this project and how does it fit
together"*, not *"which tool do I call"*.

---

## 1. Snapshot

| Fact | Value |
| --- | --- |
| Game | NULLWIDE (tag: `starterkit`) |
| Engine | Godot **4.7**, renderer **Forward Plus** |
| Main scene | `res://src/scenes/opening/opening.tscn` |
| Source root | `res://src/` (was `res://_src/` — rename in progress, see §8) |
| Scripts | 17 `.gd` files, ~1055 lines total (no C#) |
| Scenes | 33 `.tscn` files, 1679 lines total |
| Language | GDScript only; no tests, no CI |

---

## 2. Directory map of `/src`

```
src/
├── ATTRIBUTION.md        only existing documentation inside src (template, mostly unfilled)
├── assets/               fonts, OST (.ogg), .glb models, logos, opening placards
├── objects/              gameplay entities: player, enemies, arena, spawner
├── resources/themes/     6 UI themes (.tres): expedition, grow, lab, lore, gravity, steal_this_theme
├── scenes/               shell around gameplay: menus, windows, credits, loading, opening, level
├── scripts/              game_manager.gd (stub, empty)
├── shaders/              4 .gdshader files (2 grid, 1 sine-roll, 1 wireframe)
├── sprites/              crosshairs, muzzle flashes, skybox, hit/burst, blob shadow
└── weapons/              Weapon data (.tres) + weapon view models (.tscn)
```

Naming split to internalise: **`objects/` = live gameplay nodes,
`archive/` (outside src) = legacy content that is still referenced** (§8).

---

## 3. Boot and scene flow

```
project.godot  run/main_scene
	  └─> src/scenes/opening/opening.tscn          (logo placards, Maaack Opening)
			 └─> AppConfig.main_menu_scene_path    (autoload, addons/maaacks_menus_template)
					└─> src/scenes/menus/main_menu/main_menu_with_animations.tscn
						   ├─ Options -> src/scenes/windows/main_menu_options_window.tscn
						   ├─ Credits -> src/scenes/windows/main_menu_credits_window.tscn
						   └─ New Game -> AppConfig.game_scene_path  (currently EMPTY)
```

**Not reachable from any menu today:** `src/scenes/level.tscn` (the actual
gameplay scene) and `src/scenes/end_credits/end_credits.tscn` — both are
referenced by zero other scenes (verified by reference scan). `level.tscn` is
what you run manually to test gameplay.

### Autoloads (from `project.godot`, not `/src`)

| Autoload | Source | Used by `/src` as |
| --- | --- | --- |
| `Audio` | `archive/scripts/audio.gd` | `Audio.play("sounds/x.ogg")` in `player.gd` |
| `AppConfig` | Maaack template | `AppConfig.main_menu_scene_path` in `pause_menu.gd`, `end_credits.gd` |
| `SceneLoader` | Maaack template | `SceneLoader.load_scene(...)` in menus/credits |
| `ProjectMusicController`, `ProjectUISoundController` | Maaack template | menu music/UI sounds |

---

## 4. Gameplay systems (`src/objects/`)

### `player.gd` — `CharacterBody3D` (290 lines, largest script)

- Adds itself to group **`player`**; exposes `damage(amount)` and
  `signal health_updated(health)`.
- Exports: `movement_speed`, `number_of_jumps` (double jump), `jump_strength`,
  `weapons: Array[Weapon]`, `crosshair: TextureRect`.
- Shooting is hitscan: `$Head/Camera360/RayCast` + `weapon.shot_count` loops with
  `weapon.spread` jitter; damage is applied by duck-typing —
  `if target.has_method("damage"): target.damage(...)` (walks up one parent level
  if needed). **Enemies are hit purely by this duck-typed `damage()` contract.**
- Camera: `addons/godot360` `camera360.gd` on `Head/Camera360`, weapon view model
  lives in a `SubViewport` rendered on **cull layer 2** (`change_weapon()` forces
  `child.layers = 2`).
- Death / fall: `position.y < -10` or `health < 0` → `get_tree().reload_current_scene()`.
- Input actions consumed: `move_*`, `camera_*`, `jump`, `shoot`, `weapon_toggle`,
  `mouse_capture`, `mouse_capture_exit` (all defined in `project.godot`).

### Enemies

| | `chaser.gd` | `scout.gd` |
| --- | --- | --- |
| Base | `Node3D` | `Node3D` |
| States | `IDLE → CHARGING` | `IDLE → REPOSITION → TELEGRAPH → FIRE` |
| Attack | Area3D `HitBox.body_entered` during charge, 5 dmg, once per charge | `RayCast3D` line check after 1 s telegraph, 8 dmg, predicts player velocity ×2 s |
| Health / score | 3 HP, `kill_score = 2` | 3 HP, `kill_score = 3` |
| Player lookup | `get_first_node_in_group("player")` | same |
| Score payout | `get_first_node_in_group("hud").add_score(...)` if present | same |

Both expose duck-typed `damage(amount)` → `queue_free()` on death. Neither
plays hit/destroy sounds (the `Audio.play("sounds/enemy_*")` calls only exist in
`archive/objects/enemy.gd`).

### `spawner.gd` — wave spawner

- Exports: `arena_radius`, `initial_interval`, `min_interval`, `ramp_rate`
  (interval ×0.95 per wave), `spawn_height`.
- Each wave spawns 1–3 enemies, 60 % Chaser / 40 % Scout, at a random angle
  within `arena_radius`. **Two `preload()` calls at the top of `_ready()` —
  these are parse-time dependencies (§8).**

### `arena_kill_zone.gd` — `Area3D`

Damage ring: while the player is farther than `inner_radius` (15 m) it deals
1 damage per second; inside the radius the timer resets. Arena floor radius is
16 m (`arena.tscn`), so the outer lip is the danger zone.

### `arena.tscn`

Cylinder floor + walls using `src/shaders/3dgrid_team_ldm*.gdshader`
(`ShaderMaterial` parameters are embedded in the scene — grid size, gutter,
fresnel). Instance of it is placed by `level.tscn`.

---

## 5. Scene shell (`src/scenes/`)

| Path | Role |
| --- | --- |
| `opening/opening.tscn` | main scene; Maaack Opening placards + `Necron-Opening.ogg`, theme `gravity.tres` |
| `menus/main_menu/main_menu_with_animations.tscn` (352 lines, biggest scene) | animated intro menu, `MenuAnimationTree` state machine |
| `menus/main_menu/main_menu.tscn` | non-animated variant, `extends MainMenu` |
| `menus/options_menu/**` | audio / input / video tabs (Maaack `ListOptionControl` based) |
| `windows/pause_menu*.tscn` + `pause_menu.gd` | `@tool`, extends `OverlaidWindow`; restart / main menu / exit with confirmations |
| `credits/*` | `scrolling_credits.gd` (auto-scroll + `end_reached` signal) and `scrollable_credits.gd` (RichTextLabel line scroll) |
| `end_credits/end_credits.gd` | `extends "res://_src/scenes/credits/scrolling_credits.gd"` — **stale path, §8** |
| `loading_screen/*` | Maaack `LoadingScreen` + optional shader pre-caching variant |
| `level.tscn` | the gameplay scene: `WorldEnvironment` + `Arena` + `Player` + `Spawner` (with one hand-placed Chaser and Scout) |

`pause_menu_layer.tscn`, `main_menu.tscn`, `level.tscn`, `pause_menu.tscn`,
`end_credits.tscn`, `enemy.tscn`, `temp.tscn` are referenced by **zero** other
scenes — they are entry points or leftovers, not parts of a loaded tree.

---

## 6. Data-driven content

### `Weapon` (`archive/scripts/weapon.gd`, `class_name Weapon`) — the shared data type

```
model: PackedScene   position/rotation: Vector3   muzzle_position: Vector3
cooldown, max_distance, damage, spread, shot_count, knockback
sound_shoot: String  (path passed to Audio.play)
crosshair: Texture2D
```

Instances in `/src/weapons/`:

| Resource | Model | Notes |
| --- | --- | --- |
| `blaster.tres` | `double_barrel_vinrax.tscn` | cooldown 0.25, 5 shots, spread 1.0 |
| `blaster-repeater.tres` | `repeater_lonesomedukcy.tscn` | damage 10, knockback 10, spread 0.5 |

Both `.tres` files carry `script = res://archive/scripts/weapon.gd`. Adding a
weapon = new `.tscn` view model + new `.tres` + append to `Player.weapons` array
in `player.tscn`.

### Other `.tres`

- `src/resources/themes/*.tres` — UI themes; `gravity.tres` is used by the
  opening scene and the addon main menu.
- `src/sprites/burst_animation.tres` — `SpriteFrames` for muzzle flash
  (`Muzzle` in `player.tscn`).

### Shaders (`src/shaders/`)

| File | Used by |
| --- | --- |
| `3dgrid_team_ldm.gdshader` | `arena.tscn`, `temp.tscn` |
| `3dgrid_team_ldm_larger.gdshader` | `arena.tscn` |
| `LayeredSineRoll_GerardoLCDF.gdshader` | addon `main_menu.tscn` background |
| `wireframe_SuperDoomKing.gdshader` | `chaser.tscn`, `scout.tscn`, `double_barrel_vinrax.tscn`, `repeater_lonesomedukcy.tscn` |

---

## 7. Conventions and invariants

1. **Groups are the integration points.** `player` (set by `player.gd`),
   `enemy` (declared in `project.godot` global groups but never added to),
   `hud` (set by `archive/scripts/hud.gd`, which is the `HUD` CanvasLayer
   *inside* `player.tscn`). All cross-entity calls go through
   `get_first_node_in_group(...)` + `has_method(...)` duck typing.
2. **Two contracts everything depends on:** `damage(amount)` on anything
   shootable, `add_score(amount)` on the HUD. Keep both duck-typed.
3. **HUD is a child of the Player**, not of the level. Relocating it breaks
   score/health wiring for every enemy.
4. **`.gd.uid` sidecar files** exist for every script — preserve them when
   moving/renaming files, they are what `ext_resource uid=` entries bind to.
5. **`@export` is the tuning surface.** Enemy timings, spawner ramp, weapon
   stats and player movement are all inspector-tunable; avoid hardcoding.
6. **`@tool` scripts** (`pause_menu.gd`, `end_credits.gd`, `scrolling_credits.gd`,
   `scrollable_credits.gd`, `audio_input_option_control.gd`,
   `main_menu_credits_window.gd`) run in the editor — guard editor-unsafe work
   with `Engine.is_editor_hint()`.
7. **Forward+ only.** `project.godot` sets Forward Plus; the shaders use
   screen/depth-free features but the guideline's renderer check still applies.
8. **Documentation inside `src/` is only `ATTRIBUTION.md`** (and it is a
   template: "Person 1 / Person 2", "Asset Type / Use Case" are unfilled, and
   its image links still point at `/_src/...`). `docs/` was empty before this
   file. There is no README, no architecture doc, no changelog in scope.

---

## 8. Known gaps in `/src` (verified by reference scan, 2026-10-05)

The working tree is mid-rename: `_src/ → src/` and root asset folders →
`archive/` (248 files deleted from git index, `src/` and `archive/` still
untracked). `project.godot` and the addon `main_menu.tscn` were migrated;
several references were not.

**Every `res://...` string under `/src` that does not resolve on disk:**

| Broken reference | Where | Suggested target |
| --- | --- | --- |
| `res://objects/impact.tscn` | `objects/player.gd:219` (`preload`) | `res://archive/objects/impact.tscn` |
| `res://_src/objects/chaser.tscn` | `objects/spawner.gd:16` (`preload`) | `res://src/objects/chaser.tscn` |
| `res://_src/objects/scout.tscn` | `objects/spawner.gd:17` (`preload`) | `res://src/objects/scout.tscn` |
| `res://_src/objects/enemy.gd` | `objects/enemy.tscn:3` (ext_resource) | `res://archive/objects/enemy.gd` |
| `res://_src/scenes/credits/scrolling_credits.gd` | `scenes/end_credits/end_credits.gd:2` (extends) | `res://src/scenes/credits/scrolling_credits.gd` |
| `res://_src/ATTRIBUTION.md` | `scenes/credits/credits_label.tscn` | `res://src/ATTRIBUTION.md` |
| `res://_src/scenes/game_scene/game_ui.tscn` | `scenes/loading_screen/loading_screen_with_shader_caching.tscn` | never existed — Maaack template leftover, clear it |
| `res://_src/assets/...` (3 image URLs) | `scenes/credits/credits_label.tscn` BBCode `[img]` | `res://src/assets/...` |

**Runtime-only path assumptions (no `res://` literal to grep):**

- `Audio.play("sounds/land.ogg")`, `jump_a/b/c`, `weapon_change` in
  `objects/player.gd` resolve to `res://sounds/...` via the `Audio` autoload.
  Root `sounds/` was moved to `archive/sounds/`, so these resolve to nothing
  unless the Audio autoload is re-pointed or the paths gain `archive/`.
  Same class of issue for `weapon.sound_shoot` values
  (`"sounds/blaster_repeater.ogg"`).
- `src/objects/impact.tscn` and `src/objects/enemy.gd` do not exist anywhere
  under `src/` — `enemy.tscn` and the impact effect are archive-only content.

**Structural gaps (not path bugs):**

- `AppConfig.game_scene_path` is empty and no `/src` scene sets
  `game_scene_path` → the main menu's *New Game* button is hidden; `level.tscn`
  has no way to be reached from the UI.
- `pause_menu_layer.tscn` / `pause_menu.tscn` are never instanced by `level.tscn`
  → there is no in-game pause.
- `src/scripts/game_manager.gd` is an empty stub (`_ready`/`_process` → `pass`).
- `src/objects/temp.tscn` is scratch content (`CSGBox3D` with grid shader).
- `src/objects/enemy.tscn` + `archive/objects/enemy.gd` are the pre-`chaser/scout`
  enemy and are not spawned anywhere.

**Do not "fix" these silently.** They are uncommitted-rename fallout; confirm
the intended direction (`src/` vs `_src/`) before repointing anything, and
prefer `run_asset_import_script`/`run_scene_edit_script` over text edits for
`.tscn`/`.tres`.

---

## 9. How to verify claims in this document

Godot was **not** connected to Fennara MCP when this was written
(`fennara_status` → daemon not connected), so nothing here is validated by
runtime diagnostics. Before trusting §8 in a live session:

1. `fennara_status` — confirm daemon + Godot plugin connection.
2. `script_diagnostics` with `scan_project: true` — will surface the
   `preload()` failures in `spawner.gd` / `player.gd` and the `extends`
   path failure in `end_credits.gd`.
3. `validate_scene` on `src/scenes/level.tscn`, `src/objects/player.tscn`,
   `src/objects/enemy.tscn`, `src/scenes/menus/main_menu/main_menu_with_animations.tscn`
   (1–10 paths per call).
4. `runtime_session.start` on `src/scenes/opening/opening.tscn` to confirm
   whether the opening → main-menu handoff still resolves.

---

## 10. Suggested `AGENTS.md` addition

```markdown
## Project documentation

- `docs/ONBOARD.md` — map of `src/`: scene flow, gameplay systems, shared
  contracts (`damage()` / `add_score()` / `player`+`hud` groups), data-driven
  weapons and themes, plus the known stale `_src/` and `sounds/` references
  from the in-progress directory rename. Read it before changing `src/`.
- `src/ATTRIBUTION.md` — asset credits (template; partly unfilled).
- For any Godot file work, still follow `addons/fennara/ai/guidelines.md`.
```
