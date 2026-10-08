# RECON — Aspect-ratio / resolution misalignment

Read-only investigation. **No code was changed.** Scope: `hud.gd`, `weapon.gd`,
`player.gd`, `player.tscn`, `project.godot`, plus the `camera360` addon and the
Maaack options menu for context.

Symptom as reported: **gun misaligned at 1920×1080 but fine at 1280×720; in-game
HUD misaligned the same way.**

---

## 0. The one fact that reframes everything

**1280×720 and 1920×1080 are both 16:9.** The aspect ratio is *identical*.

So whatever breaks between those two resolutions is **not** aspect ratio — it is
**absolute pixel values baked into scenes and scripts**. The project has no
stretch mode and no runtime resize handling, so when the window grows, hardcoded
pixel boxes and offsets stay where they were tuned.

True aspect-ratio sensitivity (what the project name "nullwide" implies —
ultrawide support) is a *separate*, second problem that only appears once the
above is fixed.

Two distinct problems:

| # | Problem | Breaks between |
|---|---|---|
| A | Fixed-pixel layout (gun view box + HUD offsets) | any two different window sizes |
| B | 3D gun offset math assumes one aspect | 16:9 vs ultrawide |

---

## 1. How the gun actually renders (pipeline)

```
Weapon meshes (player.gd:279-280  →  child.layers = 2)
        │  rendered by cull layer 2
        ▼
HUD/SubViewportContainer/SubViewport/CameraItem   (cull_mask = 2)
        │  SubViewport 1024×1024, transparent bg
        ▼
HUD/SubViewportContainer                          ← displayed here
   offset (0,0)–(1283,1283), NO anchors           ← fixed-pixel box
        ▼
Screen, composited over the Camera360 world view
```

Separately, the **world** view goes through `addons/godot360`:

```
Camera360 (player.tscn:41-48, fovx=359.9, lens=2)
  → SubViewport fixed Vector2i(1920,1920)          (player.tscn:53)
  → 6 duplicated cube subcameras                   (camera360.gd:83-100)
  → camera360.gdshader reprojects using LIVE VIEWPORT_SIZE
```

The **shader side is aspect-aware** (`camera360.gdshader:205-212` normalises by
`min(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y)` and handles `view_ratio > 1`). The
**gun overlay side is not.**

---

## 2. Pain point A1 — the gun lives in a fixed-pixel box (main suspect)

**File:** `src/objects/player.tscn:130-142`

```
[node name="SubViewportContainer" type="SubViewportContainer" parent="HUD"]
offset_right = 1283.0
offset_bottom = 1283.0
# no anchors — default anchor (0,0,0,0), top-left anchored, fixed size
```

- `CameraItem.cull_mask = 2` (`player.tscn:141-142`) matches
  `child.layers = 2` set in `player.gd:279-280` → this is the camera that
  draws the weapon viewmodel.
- The container displays that camera's output in a **1283×1283 px box pinned to
  the top-left corner**, with no anchors and no stretch.

Resolution math:

| Window | Box covers | Result |
|---|---|---|
| 1280×720 | 1283 ≥ 1280 wide, 1283 > 720 tall → covers whole screen | looks correct |
| 1920×1080 | 1283/1920 ≈ 67% of width | gun output confined to top-left region → visibly off-position |

This alone explains *"works at 720p, broken at 1080p."*

---

## 3. Pain point A2 — weapon position is a constant from project settings

**File:** `src/objects/player.gd:32-34`

```gdscript
var base_width  = ProjectSettings.get_setting("display/window/size/viewport_width")   # always 1280
var base_height = ProjectSettings.get_setting("display/window/size/viewport_height")   # always 720
var container_offset = Vector3(base_width*0.0035/2, -base_height*0.0035/2, -7.7)
#   = Vector3(2.24, -1.26, -7.7)   ← fixed forever, magic 0.0035 fudge factor
```

- Reads **project settings constants**, never the actual viewport size →
  never adapts at runtime, never adapts per resolution.
- Fed into `container.position` every physics frame (`player.gd:79`).
- `player.gd:195` adds a second hardcoded fudge for the muzzle:
  `+ Vector3(0.25, 0.75, 1)`.
- `weapon.gd:6-8` (`position`, `rotation`, `muzzle_position`) are per-weapon
  magic `Vector3`s inside each `.tres`.

**There is no single source of truth for "where the gun sits on screen."**
It is four independent magic constants that only agree at the resolution they
were hand-tuned on (720p).

Also: `weapon.gd` itself is only a data Resource — it contains **no layout
logic**. All misalignment originates in `player.gd` / `player.tscn`.

---

## 4. Pain point A3 — HUD labels are absolute pixel offsets

**File:** `src/objects/player.tscn:108-128` — **not** in `hud.gd`.

`hud.gd` only writes text (`$Score.text`, `$Health.text`). All positioning is
baked in the scene, invisible to code review:

| Element | Offsets | Anchors | At 1080p |
|---|---|---|---|
| `Health` | (440,627)–(531,675) | default top-left | sits mid-screen instead of bottom |
| `Score` | (833,628)–(978,676) | default top-left | same |
| `Crosshair` | ±128, `scale 0.66` | `anchors_preset = 8` (center) | ✅ only survivor |
| `SubViewportContainer` | (0,0)–(1283,1283) | none | see A1 |

---

## 5. Pain point A4 — no stretch mode, no runtime reaction

**File:** `project.godot` `[display]`

```
window/size/viewport_width=1280
window/size/viewport_height=720
# no window/stretch/mode  → Godot default "disabled"
# no window/stretch/aspect
```

- Canvas size == window size. Nothing scales when the window grows.
- **Grep across `src/`:** zero matches for `size_changed`, `content_scale`,
  `stretch/mode`, `window_set_size` handling. Nothing reacts to a resolution
  change at runtime.
- The Maaack video options menu *can* change the window size at runtime
  (`video_options_menu.gd:34` → `AppSettings.set_resolution`), which is the
  likely trigger for seeing the bug without restarting.

---

## 6. Pain point B — true aspect-ratio sensitivity (ultrawide, later)

Once A is fixed, these remain for actual 21:9+ support:

1. **`container_offset` is a world-space Vector3** (`player.gd:34`). Its
   on-screen position derives from camera FOV × viewport aspect. A constant
   world offset moves horizontally on screen when aspect changes. This is the
   only part that needs real aspect math.
2. **Mixed fixed/dynamic resolution in the 360 pipeline:**
   - cube `SubViewport` locked to `Vector2i(1920,1920)` (`player.tscn:53`),
   - shader uses live `VIEWPORT_SIZE` (`camera360.gdshader:205-212`).
   Works, but the model is inconsistent — aspect-correct output fed by a
   fixed-size source.
3. **Dead uniform:** `camera360.gd:80` sets `mat.set_shader_parameter("resolution", ...)`
   but the shader declares `camera_resolution` (never used). No-op /
   misleading — cleanup candidate, not a bug.

---

## 7. Evidence index

| Claim | Where |
|---|---|
| No stretch mode | `project.godot:39-42` (`[display]`, no `stretch/*`) |
| Fixed gun box | `src/objects/player.tscn:130-133` |
| Camera on cull layer 2 | `src/objects/player.tscn:141-142` |
| Weapon forced to layer 2 | `src/objects/player.gd:279-280` |
| Constant weapon offset | `src/objects/player.gd:32-34` |
| Offset applied per-frame | `src/objects/player.gd:79` |
| Muzzle fudge vector | `src/objects/player.gd:195` |
| Per-weapon magic positions | `src/scripts/weapon.gd:6-8` |
| HUD labels absolute | `src/objects/player.tscn:108-128` |
| Crosshair anchored center | `src/objects/player.tscn:89-107` |
| hud.gd does no layout | `src/scripts/hud.gd` (text writes only) |
| Shader IS aspect-aware | `addons/godot360/src/camera360.gdshader:205-212` |
| Dead `resolution` uniform | `addons/godot360/src/camera360.gd:80` vs `.gdshader:8` |
| No runtime resize handling | grep `src/`: no `size_changed` / `content_scale` |
| Runtime resolution change exists | `addons/.../video_options_menu.gd:34` |

---

## 8. Recommended fix order (proposal only — not executed)

1. **Give `SubViewportContainer` proper anchors or enable stretch mode**
   → fixes the gun at 1080p. (`player.tscn:130`)
2. **Set `window/stretch/mode` + `window/stretch/aspect`** in project
   settings → everything scales from the 1280×720 design baseline.
3. **Anchor `Health` / `Score` labels** (bottom-left / bottom-center presets).
4. **Then** tackle the gun's world-space `container_offset` with real aspect
   math — the only item that requires algorithmic change rather than layout
   correction. Ultrawide support starts here.

Steps 1–3 are layout corrections with no design decisions. Step 4 touches
gameplay feel and should be agreed before implementation.

### Implementation status (updated after playtest)

| Step | Status | Notes |
|---|---|---|
| 1+2 | **Done** | `stretch/mode="canvas_items"` (+ default aspect `keep`) in `project.godot` |
| 3 | **Done** | `Health`/`Score` bottom-left anchored in `player.tscn` |
| 1–3 rework | **Done (baseline decision)** | Commit `76cf541` flipped the base to **1920×1080** + `mode=3` fullscreen (deliberate — base stays 1920×1080). Under `canvas_items` the layout equals the base at every window size, so the 720-tuned values were re-expressed ×1.5: gun box `(2,0)-(1285,1283)` → `(3,0)-(1927,1924)` (+ `stretch=true` so the gun viewport renders at box resolution), `Health`/`Score`/`Crosshair` offsets and label font ×1.5, and `container_offset` decoupled from `ProjectSettings` to the tuned constant `(2.24, -1.26, -7.7)` (A2). Runtime-verified: layout rect pinned to base at both 1080p fullscreen and 720p windowed. |
| 4 | Not started | Ultrawide (`aspect=expand` + container aspect math) — needs design agreement |

---

*Recon only. No files outside this document were modified.*
