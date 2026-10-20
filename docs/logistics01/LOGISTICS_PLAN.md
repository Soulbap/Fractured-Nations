# LOGISTICS-01 / BASE-02 — implementation plan (written before the code)

Branch `feature/logistics-01-base-02`, worktree `../fractured-nations-logistics01`, created from
`feature/world-integration-03` (21e846a). The generated world (2.3 GB `worlds/`, `ref_20km.tscn`,
`.godot/`) was copied from the integration03 worktree with robocopy (2.277 GB checked), then
`--headless --import` (31 s). `main` and the other worktrees are untouched.

## 1. What already exists (architecture review)

| Area | Finding | Consequence |
|---|---|---|
| `UnitState` | One record for soldiers *and* vehicles (`Kind.VEHICLE`), plain data, `to_dict`/`from_dict`, applied in place on load. Vehicles have speed 0, refuse `issue_move`. | Vehicle data is a sub-record `UnitState.veh` (`VehicleState`), saved in the same dict. No second entity list. |
| `WorldSim` | Per physics tick: abstract step for every unit **without** a body, then squads, war, brain, combat. | Vehicle driving is a step over *every* vehicle record, body or not. The body is only a representation. |
| `VehicleBody` | `StaticBody3D`, placeholder box model, writes `position`/`yaw` into the record. | Becomes an `AnimatableBody3D` presentation (wheels, suspension, LODs) that **reads** the record. |
| `DetailManager` | Promote/demote by distance, `VEHICLE_SCENE`, vehicles carve the navmesh as 2.9 x 6.1 obstacles. | Unchanged tier logic; only *parked* vehicles carve the navmesh. |
| `RoadNetwork` | Authoritative polylines (world roads.json 124 roads / 30 300 vertices, ~10 m apart, widths 4.8-10 m, bridges as index spans, `deck_height()`) + built roads from `ConstructionState`; `changed(rect)` signal. | Routing reads it. A graph *index* over its vertices is a derived cache (like the `StrategicRoutes` grid), not a second road representation. |
| `StrategicRoutes` | 50 m A* grid: water/cliffs impassable, roads cheap, bridges open the river, re-marked when roads change. | Used for off-road connector legs and as the water/cliff authority. |
| `StructureManager` | `blocks_point()` cell lookup (used by the abstract tier), nav obstacles, `water_height()`. | Vehicle sim tests oriented footprints against it, so buildings/walls/fences stop vehicles in both tiers. |
| `SquadControl`, `SquadState` | Squad orders -> per-soldier move orders; routes as waypoint lists. | Phase B boards/disembarks through these records (members keep squad membership). |
| `GameController` | FPS/RTS modes, possession, camera switching. | Adds `Mode.DRIVE` (chase camera) through the same possess/enter_rts path. |
| Save/load | `WorldState.save_file` (units, squads, war) + `ConstructionState` json (F5/F9). | Vehicle, cargo, passenger, convoy, depot inventory state goes into these two files; no third save path. |
| Assets | Truck 6x6 / APC 8x8 GLBs with `WHEEL_*`, `SUSP_*`, `SEAT_*`, `DOOR_*`, `CARGO_*`, `TOW_*`; separate `wheel_truck/apc`. Godot space: forward = -Z, origin on the ground, wheel centre y = 0.625 / 0.60. Body meshes contained their own wheels. | Blender builder flag `BODY_WHEELS = False` (done, re-exported: truck 4104 -> 1128 LOD0 tris, APC 976); wheels instanced at the markers. |

## 2. Ownership (one owner per fact)

| Fact | Owner | Representations |
|---|---|---|
| Vehicle identity, faction, position, yaw, health | `UnitState` | `VehicleBody` (near), `UnitProxy` (far, LOD2 mesh), map icon |
| Vehicle type, speed, steer, fuel, route + progress, status/reason, input, (later) occupants, cargo, convoy, job | `UnitState.veh` (`VehicleState`) | HUD, map, selftests |
| Vehicle type numbers (dimensions, wheelbase, steer, speed, accel, fuel, seats, cargo) | `VehicleDefs` (static table) | read only |
| Vehicle movement (both tiers) | `VehicleSim` (owned by `WorldSim`, `sim.vehicles`) | one kinematic bicycle step on the record |
| Road graph for vehicles | `VehicleRouter` index over `RoadNetwork` | route polylines stored in `VehicleState.route` |
| Supplies | `Inventory` (one class) held by depot `StructureState`, `VehicleState.cargo`, faction stockpile; one `Inventory.transfer` | UI, tests |
| Facilities / bases | `StructureState` (+ facility fields) and `ConstructionState.bases` | construction manager unchanged |
| Passengers | `UnitState.vehicle_id` (soldier) + `VehicleState.occupants` (always changed together by `VehicleSim.board/disembark`) | no body, no proxy while aboard |

Why a new class at all: `VehicleSim` (movement + order state machine) and `VehicleRouter`
(graph query) are the two things no existing class can own — `WorldSim` is infantry-only
straight-line travel, `RoadNetwork` is geometry/queries without a search graph, and
`StrategicRoutes` is a 50 m infantry grid. Both are plain objects owned by `WorldSim`/`WorldState`,
not nodes with their own loops.

## 3. Data flow (driving)

1. Order (RTS right-click / map / test): `sim.vehicles.order_drive(id, target)` -> `VehicleRouter.plan()`
   returns one dense polyline (road legs from `RoadNetwork` vertices, off-road legs from a local
   2 m obstacle grid or the 50 m grid) -> smoothed, resampled to ~4 m, per-point speed profile
   (curvature + braking look-ahead) -> `veh.route`, `UnitState.order = MOVE`.
2. Every physics tick `VehicleSim.update()`: for each vehicle record — pure pursuit steering, speed
   control, bicycle-model integration, height from terrain/bridge deck, footprint test against
   structures + other vehicles + (near tier) a physics probe, stuck detection/recovery, fuel use.
3. `VehicleBody` (if any) copies the record into its transform, animates wheels/suspension from
   ground samples. Promotion/demotion changes only the node; the record, route and progress are
   untouched, so the camera never decides whether a journey succeeds.
4. Player driving: `veh.input` (throttle/steer/brake) replaces the route follower while
   `player_controlled`; the order and route stay, and can be resumed or replaced.

## 4. Phases and gates

* **A** vehicle core: assets, `VehicleState/Defs/Sim/Router`, body + wheels, RTS order, driving mode,
  persistence. Gate: Section 9 of the brief (5+ km, bridge, curves, player road, base entrance, take
  control, resume, save/load, near/far, APC).
* **B** `board/disembark`, squad transport order, seats, capacity, UI rows.
* **C** `Inventory`, depots, load/unload jobs, convoys, resupply (ammo -> `UnitState.reserve`, fuel).
* **D** facility mechanics (HQ/Barracks/Supply/Vehicle depot), bases, strategic-map layer, automation, the Section 24 scenario.

## 5. Risks

* Road graph build cost (30 k vertices in GDScript) -> built once lazily on first plan, measured.
* Vehicle through trees off-road: sim knows structures only; near tier adds a physics probe.
* Player-built road junction with world roads: graph links vertices of different roads within 8 m.
* 16x compression: vehicle step is O(vehicles), measured.
* `GameController` `Mode.DRIVE` touches HUD/DetailManager observer: kept to explicit branches.

## 6. Validation sequence

Focused scenarios in `scripts/debug/logistics_selftest.gd` (extends the integration03 chain, reuses its
built base): `veh_assets`, `veh_route`, `veh_drive` (+ player road, bridge, base entrance), `veh_player`,
`veh_persist`, `veh_tiers`; then `transport`, `logistics`, `convoy`, `bases`, `scenario`, `perf`.
Regression by change impact only: `playtest --only nav_base`, `sandbox --only navigation`,
`integration03 --only base_nav` (shared `WorldSim`/construction touched), `characters` if soldiers change.
