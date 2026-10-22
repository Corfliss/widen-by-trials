# Recon: Audio Variations — 2026-10-21

Cross-reference of Kanban tasks vs. repetitive/orphaned audio in `src/sounds/`.

Key fact: `src/scripts/audio.gd` already supports variation (comma-separated pools + random `pitch_scale` 0.9–1.1). Only jumps use it (`jump_a/b/c`). Everything else is a single file — that's the repetition.

## Variation table

| Sound | State | Kanban task | What to add |
|---|---|---|---|
| `blaster_repeater.ogg` | **Shared by all 3 weapons** (`blood_shotgun.tres`, `sweat_carbine.tres`, `tears_machine_gun.tres`) — #1 repetition | "Find Weapon sound" (Todo) | 3 distinct shoot sounds × 2–3 variants each, e.g. `Blood_Shotgun.wav` (low pitch), `Sweat_Carbine.wav` (mid), `Tears_HMG.wav` (high/fast). Wire via existing `sound_shoot` comma-list |
| `player_get_hit.wav`, `enemy_hit.wav` | **Orphaned** — chaser/bomber/sniper scripts play no audio at all | "Enemy variation" (Done: bomber/sniper/chaser) | Per-type destroy variants: `enemy_hit.wav` (Pitch: sniper=low, bomber=medium, chaser=high), `player_get_hit.wav` (mid). 1 attack sound per type + 1 shared hurt |
| *(none exists)* | **No hit-confirm sound** — hit feedback is silent (hitmarker is visual only) | "Find target hit sound" (Todo) + "Hit not satisfying enough" (Automating) | `hit_confirm.wav` — short click/tick, pitch-boosted on kill. Pairs with the particle burst from the Automating task |
| `land.ogg`, `weapon_change.ogg` | Single variant each | (feeds "Color matching" weapon-cycle work) | No variants |
| `walking.ogg` | Scene bug: `player.tscn` loads **`archive/sounds/walking.ogg`**, `src/sounds/walking.ogg` unused | — | Repoint to `src/` copy (archive is dead storage); |
