# Recon: Audio Variations — 2026-10-21

Cross-reference of Kanban tasks vs. repetitive/orphaned audio in `src/sounds/`.

Key fact: `src/scripts/audio.gd` already supports variation (comma-separated pools + random `pitch_scale` 0.9–1.1). Only jumps use it (`jump_a/b/c`). Everything else is a single file — that's the repetition.

## Variation table

| Sound | State | Kanban task | What to add |
|---|---|---|---|
| `blaster_repeater.ogg` | **Shared by all 3 weapons** (`blood_shotgun.tres`, `sweat_carbine.tres`, `tears_machine_gun.tres`) — #1 repetition | "Find Weapon sound" (Todo) | 3 distinct shoot sounds × 2–3 variants each, e.g. `blaster_shotgun_a/b.ogg` (low pitch), `blaster_carbine_a/b.ogg` (mid), `blaster_mg_a/b.ogg` (high/fast). Wire via existing `sound_shoot` comma-list |
| `enemy_attack.ogg`, `enemy_destroy.ogg`, `enemy_hurt.ogg` | **Orphaned** — chaser/bomber/sniper scripts play no audio at all | "Enemy variation" (Done: bomber/sniper/chaser) | Per-type destroy variants: `enemy_destroy_chaser_a/b.ogg` (high), `_bomber_a/b.ogg` (low/heavy), `_sniper_a/b.ogg` (mid). 1 attack sound per type + 1 shared hurt |
| *(none exists)* | **No hit-confirm sound** — hit feedback is silent (hitmarker is visual only) | "Find target hit sound" (Todo) + "Hit not satisfying enough" (Automating) | `hit_confirm_a/b/c.ogg` — short click/tick, pitch-boosted on kill. Pairs with the particle burst from the Automating task |
| `land.ogg`, `weapon_change.ogg` | Single variant each | (feeds "Color matching" weapon-cycle work) | 2 variants each (`_a/_b`); for weapon_change, 1 variant per weapon (red/black/white identity) |
| `walking.ogg` | Scene bug: `player.tscn` loads **`archive/sounds/walking.ogg`**, `src/sounds/walking.ogg` unused | — | Repoint to `src/` copy (archive is dead storage); later add 2 step variants |
| `blaster.ogg` | Orphaned (nothing references it) | — | Delete or repurpose as one weapon's base |
| OST (2 tracks) | Opening + Core only | "Wave-based randomizer" (Done) | Later: second, higher-intensity combat loop layer for late waves |

## Visual side note

Matches "Find Weapon spray muzzle veriations" (Todo): enemy muzzle flashes use a single `burst_animation.tres` spriteframes for both MuzzleA/B — 2–3 flash frame variants would break that repetition too.

## Priority

1. **Per-weapon shoot sounds** — most audible repetition (3 weapons, 1 sound)
2. **Hit-confirm sound** — silent feedback is a bigger feel issue than repetition
3. **Wire the orphaned enemy sounds** — assets exist, just connect them + add per-type variants
4. land/weapon_change/walking variants — polish tier

## Conventions & audit status

- Naming: follow existing `jump_a/b/c` scheme (`name_a.ogg`, `name_b.ogg`) — do NOT rename to `sfx_*` pattern
- All files OGG, 5–54 KB — no size or format violations anywhere
- Risk: `player.tscn` depending on `archive/` means an archive cleanup would silently break footsteps
