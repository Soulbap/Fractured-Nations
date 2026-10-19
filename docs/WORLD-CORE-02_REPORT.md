# WORLD-CORE-02 — Large World Simulation

**Branch:** `feature/world-core-02` (from `feature/world-core-01`, not merged into `main`)
**Engine:** Godot 4.7.2, Forward+, Vulkan, Terrain3D 1.0.2, Jolt. **Machine:** i7-12700F, RTX 3070, 16 GB, 1600 × 900, VSync off.
Status tags: **[VERIFIED]** executed in Godot by `scripts/debug/large_world_selftest.gd`.

## 1. Summary

The CORE-01 FPS/RTS game now runs on the real 20 × 20 km world (`scenes/game/world_core_02.tscn`, 2 m terrain, vegetation over the whole map). 26 soldiers and 3 vehicles stand at the three base sites, 7.6, 11.0 and 11.3 km apart. One `WorldState`, one continuous scene, no separate maps. Only units near the active camera have physics bodies; all others are advanced by the existing abstract `WorldSim` step and shown as light proxies. The scripted run passes (0 failures, last three runs) **[VERIFIED]**, and the CORE-01 2 km test still passes.

## 2. What was implemented

| File | Role |
|---|---|
| `scripts/core/detail_manager.gd` | `DetailManager`: per unit, body if within 120 m of the observer, abstract beyond 150 m (hysteresis). Keeps one navmesh area, terrain collision and tree colliders around the observer. `activate_at(pos)` builds detail anywhere on demand. |
| `scripts/units/unit_proxy.gd` | `UnitProxy`: marker + selection ring for units without a body, driven only by the `UnitState`. |
| `scripts/core/world_sim.gd` | proxy registry, `view_of(id)`, `view_added` signal |
| `scripts/core/game_controller.gd` | possessing an abstract unit builds detail around it first; `N` possess next soldier anywhere; `1/2/3` jump to site (RTS: camera, FPS: nearest soldier); P/double-click possession now actually connected (it was not wired in CORE-01) |
| `scripts/rts/rts_controller.gd` | selection and box-select read `UnitState`, so units in either tier can be selected; selection survives tier swaps |
| `scripts/units/soldier_body.gd` | an order whose target lies outside the navmesh area keeps walking toward it instead of ending as BLOCKED |
| `scripts/game/core_demo.gd`, HUD | large-world spawn/orders, detail counters |
| `scripts/debug/large_world_selftest.gd`, `benchmarks/wc02/` | checks, logs, JSON |

Design points:
- **Identity/state across detail changes:** the `UnitState` object is the unit. Demotion removes the body (its last tick already wrote position/yaw into the record) and creates a proxy; promotion does the reverse and the body re-applies the order from the record. Nothing is copied.
- **Collision:** Terrain3D `DYNAMIC_GAME` (radius 208 m) follows the terrain camera: the possessed soldier's camera in FPS, an invisible anchor camera on the tactical focus in RTS (the RTS camera hovers up to hundreds of metres from what it looks at). No full-map collision.
- **Navigation:** one runtime-baked area (440 m, 0.75 m cells) re-centred on the observer when it drifts 45 m, or on demand at a jump. 96,800 terrain faces → ~1,000 polygons in 245 ms. No full-map baking, nothing stored. Detail changes wait while the tactical camera pans faster than 20 m/s.
- No custom streaming system added; vegetation, grass and terrain LOD already follow the current camera.

## 3. Validation (20 km, real input actions, ~2.5 min) **[VERIFIED]**

| Check | Result |
|---|---|
| Layout | 26 soldiers (10/8/8), 3 vehicles; start: 11 bodies at site A, 18 proxies; all 10 soldiers on the floor |
| Orders where nobody looks | 7 abstract soldiers at B and C all progressed > 10 m in 4 s with no body |
| RTS order at A | box-selected 4, right-click ground error 0.0 m |
| Key 2 in RTS (7.6 km) | camera on site B, bodies built for B's 9 units, terrain ray hit and navmesh both under the focus |
| Click-select + P at B | the clicked soldier possessed, camera current, on floor; walked 8.6 m on the terrain; 502 vegetation MultiMeshes (24.8 k instances) and grass active |
| Site A group during that | all 4 ordered soldiers kept executing (abstract) |
| Key 3 in FPS (11 km) | player on a soldier at C, on floor; a 45 m order there arrived (1.3 m error) |
| `N` cycling | 26 of 26 soldiers visited, 3 jumps over 1 km, bodies + proxies always = 29 units |
| Return to A (key 1) | identities identical for all 29 units; idle units drifted 0.000 m; all 7 ordered units had finished their walk (abstractly) |
| Tier change in transit | outbound: body → abstract at 150.5 m, finished its order with 0.0 m error; inbound: abstract → body at 119.9 m, arrived 1.3 m off; same record, no position jump |

Screenshots (`docs/screenshots/core02_*.jpg`): `fps_site_b`, `rts_site_a`, `rts_site_b`, `rts_site_c`, `rts_overview_2800m`, `fps_site_a_return`.

## 4. Performance

| Item | Result |
|---|---|
| Frame time FPS at A / RTS 160 m / RTS 1500 m | 1.33 / 1.94 / 1.76 ms avg; p99 1.7 / 2.5 / 2.1 ms; 520 / 248 / 100 draw calls |
| Far possession (8–11 km) | 640–770 ms call (navmesh bake ~245 ms + collision build + bodies), single hitch |
| Memory | ~1.5 GB static, same as WORLD-TECH-02 20 km |
| Physics + navigation per frame | 0.5 ms / 0.06 ms with 9–11 bodies |

## 5. Limitations

- A far jump costs about 0.7 s. It is one hitch, not a stream, but not "instant" to the frame. Async baking or a smaller first area would reduce it.
- Abstract units walk straight lines (terrain height only, no trees or water); a unit can be promoted standing inside a tree and is pushed out by physics.
- Abstract arrival snaps to the target (< 1 m); bodies arrive within ~1.3 m.
- One observer only: two groups kilometres apart cannot both be in detail (e.g. watching two sites at once).
- Tree colliders were not exercised: no trees stood within 40 m of the test positions, so `Instance colliders` read 0. Tree-aware navmesh obstructions exist but showed 25 at site A.
- One earlier run of the inbound transition check failed ("[false, true, false]": the unit lost its body again after promotion) and I could not reproduce it in the next four runs. Cause not found.
- Vehicles are still parked; both factions commandable; the 5 s old `physics_ms` reading of 19 ms in the 1500 m RTS case was not investigated (frame time was 1.76 ms).
- Not played by a human in this session; only scripted.

## 6. Next steps

1. Async navmesh bake and pre-warm around the RTS camera so far possession is smooth.
2. Multiple observers (e.g. two detail zones) and tree-aware abstract paths.
3. Long-route orders via roads (cheap road graph) instead of straight lines.
4. Save/load from `WorldState.snapshot()`.
5. Investigate the one-off inbound transition failure with a repeat-run harness.

Run: `benchmarks/wc02/run_large_test.sh --shots` (20 km), CORE-01 check unchanged (`--core-test` on `core_demo.tscn`).
