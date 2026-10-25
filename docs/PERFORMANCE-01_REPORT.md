# PERFORMANCE-01 — Vegetation Streaming Stutter & Frame-Time Stability

Branch `develop`, not pushed. World: the adopted VISUAL-02 `ref_20km`. Measured with `--gameplay05-test --only p_veg` (1920×1080
fullscreen, vsync off); "before" is the same build with `--veg-immediate-free` (the old behaviour, every budget off), "after" the
default. The clean before/after pair was run with **no other Godot process** on the machine (checked before each run; two other
sessions were taking turns on the GPU).

## 1. Confirmed cause

GAMEPLAY-05B saw 4 of 5 spikes (40–48 ms) coincide with a vegetation chunk being released and suspected the release. Controlled
measurements show the release is **not** expensive on its own, and where the spikes really come from:

| controlled event (camera still) | call | worst frame after |
|---|---|---|
| unload a chunk (20–247 active cells freed with it) | 0.5–2.0 ms | 3.9–9.2 ms |
| free 60 cells in one frame | 0.6 ms | 5.1 ms |

| camera event | before |
|---|---|
| **jump 3 km** (×6) | 12 frames > 33 ms, max **87 ms**; in the worst frames **11–13 finished chunk loads stored in one frame** (34 ms), **12–15 chunks unloaded** (8.6 ms) and **772–1296 cells freed** (4.7–8.0 ms) — about 50 ms of streamer work in one frame |
| drive at 25 m/s | no frame > 33 ms |
| RTS pan at 300 m/s | 4 frames > 33 ms (5 chunks stored in one frame: 7.7 ms), one 179 ms frame with no vegetation work |

[CODE] `VegetationStreamer`: activations were budgeted (24 per frame), but three things were not: (a) every chunk the background
loader had finished was taken into use in the same frame (`_store_chunk`: `RoadShoulders.fix_chunk` puts the instances on the eased
terrain and the overrides layer hashes the chunk, ~2–3 ms each); (b) every chunk that drifted out was unloaded in the same frame;
(c) every cell leaving the range was freed (`MultiMeshInstance3D.free()`) in the frame the camera crossed the update threshold. A
camera jump (the GAMEPLAY-05B spikes were all around camera jumps: framing the fight, entering first person) lands all three at
once. The release itself is cheap per item; the bunching made the spike.

## 2. Implementation (inside the existing streamer)

`scripts/vegetation/vegetation_streamer.gd`, no new system:
- **Release queue.** A leaving cell is hidden at once (visually the same as freed) and queued; `_drain_release` frees
  `releases_per_frame` (8) per frame, more when the queue would not empty within `release_frames` (30) frames — the queue is
  bounded by construction (peak 1049 entries after a 3 km jump, empty again within 30 frames).
- **Reuse.** A cell that left by camera movement (data unchanged) and is wanted again before it is freed is shown again instead of
  rebuilt (`_reusable`). Cells released because their data changed (clearings, override edits, chunk unload) are never reused.
  Queue entries for a reused or already freed instance are skipped: no double free.
- **Store budget.** At most `stores_per_frame` (2) finished chunks are taken into use per frame; the rest stay loaded in the loader
  until the next frame.
- **Unload queue.** Far chunks are unloaded at most `unloads_per_frame` (2) per frame; a chunk wanted again before its turn is taken
  off the list (`unloads_cancelled`).
- Disabling the streamer (`enabled = false`) still frees everything at once. Vegetation collision is unchanged (colliders are built
  from the chunk data, not from these nodes).
- **Counters** (`VegetationStreamer.counters`): chunk loads / unloads, cells activated / freed / reused, time freeing, unloading and
  storing, release-queue peak; `get_stats()` adds release queue, reusable cells, pending unloads, chunks waiting to be stored.
- `--veg-immediate-free` keeps the old behaviour for comparisons.

## 3. Before / after (same build, no other GPU user)

| phase | frames | avg ms | p95 | p99 | max | > 16.7 ms | > 33 ms |
|---|---|---|---|---|---|---|---|
| still camera | 240 | 3.19 → 3.18 | 3.92 → 3.84 | 4.28 → 4.53 | 10.6 → 9.9 | 0 → 0 | 0 → 0 |
| jump 3 km ×6 | 1440 | 5.26 → 5.38 | 7.29 → 7.59 | 25.3 → 28.7 | **87.0 → 63.3** | 16 → 33 | **12 → 10** |
| drive 25 m/s, 30 s | 1200 | 3.59 → 3.55 | 5.03 → 4.91 | 11.04 → 11.06 | **21.2 → 14.6** | 1 → 0 | 0 → 0 |
| RTS pan 300 m/s, 10 s | 1200 | 5.05 → 5.02 | 12.7 → 12.8 | 14.8 → 15.0 | 179 → 173 | 8 → 7 | **4 → 2** |

Streamer work inside the worst jump frames: **~50 ms → ~5 ms** (store 34 ms → ≤5 ms, unload 8.6 → 0.3 ms, freeing 8.0 → 0.3 ms).
Totals over the jumps are the same (6324 cells freed, 84 chunks loaded, 81 unloaded in both): the work is spread, not skipped —
which is why frames over 16.7 ms rose (16 → 33) while the frames over 33 ms and the maximum fell. Freeing 60 cells: 0.63 → 0.16 ms;
unloading a chunk: roughly halved. Memory: static 2181 → 2177 MB, video 1864 → 1864 MB; at the end of every run the release queue,
the reusable set and the pending unloads are empty.

**What remains** of the jump and pan spikes is not vegetation: the remaining > 33 ms frames contain ≤ 5 ms of streamer work (≤ 2
stores, ≤ 2 unloads, ~25–40 cells freed). Their cost is in other systems that react to a teleport of the observer (script process
time up to 41 ms in those frames — the near-tier recentre, colliders — and engine work outside scripts). The 173–179 ms frame
during the 300 m/s pan has no vegetation work at all in either version.

## 4. Tests

| check | result |
|---|---|
| `p_veg` before / after (still, controlled unload, 60-cell free, jumps, 25 m/s drive, 300 m/s pan) | §3 |
| flick: out 600 m and back after 6 frames | 125 cells shown again (reused); afterwards exactly the same active cells as before, none left hidden |
| view switch: first person → map → tactical | the same active cells afterwards; one 217 ms frame with 0.3 ms vegetation work (the possession switch, not the streamer) |
| end state of every run | release queue 0, reusable 0, pending unloads 0, chunks waiting 0 |
| `tools/check_scripts.gd` | 179 scripts, 0 failures |

The flick / view-switch run had another session's Godot process running (its frame times are not used; the counts are).

## 5. Remaining limitations

1. **Teleport hitches outside vegetation** (jump: up to 63 ms; RTS pan: one 173 ms frame; possession switch: 217 ms) — other
   systems; the next profiling target (instrument the near-tier recentre `DetailManager`, `InstanceColliderStreamer`, Terrain3D
   dynamic collision on a jump).
2. Spreading raised the number of 17–33 ms frames right after a jump (16 → 33 over six jumps): a deliberate trade, a short ramp of
   mild frames instead of one hard stall.
3. Hidden cells keep their GPU buffers for up to 30 frames (bounded; no growth measured).
4. Budgets are per frame, not per millisecond: on a much slower machine one store (~3 ms) may still be noticeable.

## 6. Commits

| commit | what |
|---|---|
| (this milestone) | bounded vegetation release, store and unload budgets, reuse, counters; `p_veg` measurement; this report |

Earlier on the way: `4464517` (`--shoulders-g04`, since replaced by the road session's rewrite of `road_shoulders.gd`).
