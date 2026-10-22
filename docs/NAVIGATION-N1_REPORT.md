# NAVIGATION N1 — baseline, diagnosis and implementation proposal

Date: 2026-10-22. Branch: `develop`. Godot 4.7.2. World: `ref_20km`.

This milestone stops at measurement and design. The instrumentation and test harness below do not change
route choice, passability, movement, recovery or simulation authority. Navigation implementation requires
explicit product-owner approval.

## 1. Repository finalization

`main` was fast-forwarded without force from `80c494a` to the approved consolidated commit
`4e41aae2bc0eae1d6a36957210fb64b8f55d009b`, which was already the tip of `develop` and
`origin/develop`. The combat-tech and Blender-skills merge commits are ancestors of that commit.

The canonical map manifest and the external consolidation backup both verify 540/540 payload files. The
reference-map PNG in `docs/` is known, intentionally untracked and untouched. The 13 historical worktrees
were audited individually: every branch tip is contained in `develop`; ignored outputs were logs, caches,
raw benchmarks or copied maps. The `unified` checkout's 46 tracked differences were the documented editor
resaves, and its three screenshots matched the external backup byte-for-byte. All 13 worktrees were removed
normally, without `--force`; all local and remote historical branches remain. The authoritative checkout is
the only worktree.

## 2. Current navigation architecture

| Layer | Current owner | Authority and behavior |
|---|---|---|
| World roads and bridge decks | `RoadNetwork` | Canonical road polylines, built roads and inferred deck height. Emits road-change rectangles. A bridge is geometry, not an enabled/disabled entity. |
| Strategic infantry/operation route | `StrategicRoutes` | 400 × 400, 50 m grid over terrain/water/roads. Produces coarse waypoints and does not incorporate structure footprints. |
| Squad movement | `SquadControl` | Converts a route leg or direct order into formation slots. Watches leader progress, retries a coarse route up to three times, then skips a stalled leg. |
| Near infantry | `AreaNavigation` + `SoldierBody` | Camera-centered dynamic navmesh and `NavigationAgent3D`/avoidance. Structure edits trigger rebakes in the detail area. |
| Far infantry | `WorldSim` | Advances records directly. It tests structure footprints and tries fixed-angle wall sliding, but performs no local path search. |
| Tactical reactions | `SquadTactics` + `CombatBrain` | Temporarily replaces a soldier's movement target through `react_target`; the squad route remains the higher-level order. |
| Vehicle route | `VehicleRouter` | AStar3D over `RoadNetwork`, joined to endpoints by a 3 m local terrain/structure grid. Vehicle definitions supply road/off-road cost, speed and grade. |
| Vehicle execution | `VehicleSim` + `VehicleConvoy` | Follows a dense speed-profiled route, probes obstacles, reverses, locally bypasses and replans. Convoys add spacing but no bridge capacity model. |
| Operation state | `OperationState` + `WarSim` | Owns strategic intent and stages; delegates squad/vehicle movement to the same public controllers as the player. |

The duplication is concentrated at the local-obstacle layer. Near infantry uses a navmesh, far infantry uses
fixed-angle footprint sliding, and vehicles use a 3 m A* search. They read much of the same terrain,
water and structure truth but derive different reachability. `StrategicRoutes` remains the correct coarse
owner; `RoadNetwork` remains the correct road owner; neither should be replaced.

## 3. Instrumented baseline

The new command is:

```text
Godot.exe --headless --path . res://scenes/game/world_ref_20km.tscn -- --navigation-n1-test
Godot.exe --headless --path . res://scenes/game/world_ref_20km.tscn -- --navigation-n1-test --only n1_03,n1_04
```

Each case can run alone. Output is `user://navigation_n1/navigation_n1_test.json`; no result, log or
screenshot is written to a tracked project path. Cases are `PASS`, `FAIL`, `KNOWN_FAIL`, `UNSUPPORTED` or
`ERROR`, so an expected baseline defect is not confused with a broken harness.

Added runtime diagnostics:

* `StrategicRoutes`: request count/time plus failed count, reason and last endpoints.
* `VehicleRouter`: successful and failed request timing, including cached failures; reason/endpoints/profile;
  initial graph build and incremental rebuild count/time/reason.
* `VehicleSim`: bypass attempts separately from successful bypasses, alongside recovery/replan outcomes.
* `SquadControl`: route-stall timeouts and the subset that occur while the leader is reacting.
* N1 harness: arrivals, final distances, blocking-footprint samples, tier/body state, maximum no-progress
  duration, route replans/skips, bridge traversal, frame p95/p99/max and simulation tick buckets.

The instrumentation is in-memory only. It is deliberately not saved into `WorldState`.

## 4. Acceptance scenarios and measured result

| ID | Scenario | Result | Baseline evidence |
|---|---|---|---|
| N1-01 | Near-tier squad routes around a building | PASS | 7/8 within 14 m, zero footprint penetrations, maximum stall 1.3 s. |
| N1-02 | Closed perimeter and the same perimeter with a 16.1 m gate, near/far | FAIL | Closed: 0/8 arrive in both tiers. Open: near 7/8 with 0.3 s maximum stall; far 6/8 with two units ~47 m away and 522.2 s maximum stall. |
| N1-03 | Road blocked after a truck route is issued | PASS | 6.84 km trip arrives; one bypass attempted and succeeded, no full replan or recovery. |
| N1-04 | Truck versus wheeled APC profile/route choice | PASS | Distinct costs produce a materially different route to Verket: truck 6.84 km/147 m off-road; APC 3.59 km/all off-road. A tracked profile does not exist. |
| N1-05 | Three-vehicle convoy across a bridge | PASS | 3/3 arrive and all are observed on the bridge; no sustained stall. Bridge width/load/capacity is absent. |
| N1-06 | Disable a bridge while traffic is en route | UNSUPPORTED | No persistent bridge route entity or selective invalidation API exists. This is diagnosed, not emulated. |
| N1-07 | Place a structure after infantry/vehicle movement begins | PASS | Near infantry 7/8, zero footprint penetrations; vehicle uses one successful bypass. Near navmesh rebakes and vehicle failure cache clears; the strategic grid does not update for structures. |
| N1-08 | Far-tier squad finds a distant defence-line opening | KNOWN_FAIL | 6/8 reach; two remain ~47 m away for the rest of a 600 s run. Reproduces the earlier `base_nav` class of failure. |
| N1-09 | Equivalent near/far reachability | FAIL | Both tiers use the opening, but only near movement is reliable under the 25 s no-progress criterion. Far/near simulated-time ratio is 2.5 because the far run exhausts its timeout. |

No case sampled an infantry unit inside a blocking footprint. N1-02's `crossed_wall` diagnostic is not an
acceptance condition for the closed case; it samples the gate corridor plane and can be true while a unit
remains outside. Reachability, final distance and penetration are the authority.

### Targeted legacy checks

`--ai-war-test --only r_yard,r_exit,r_obstacles` confirms the mixed baseline rather than contradicting it:

* `r_obstacles`: parked-vehicle and building-on-route journeys arrive; the latter needs two bypasses and
  three recoveries over 789 simulated seconds.
* `r_exit`: 3 of 24 dock/parking round trips fail, including two blocked South-base service approaches.
* `r_yard`: the truck is still driving after 500 simulated seconds, 1.04 km from its goal on a 9.33 km
  route. This is a timeout/acceptance failure, not a planner refusal.
* The old test's optional screenshot call cannot read a rendered texture under the dummy headless renderer;
  the scenarios continue and report their data. N1 itself never requests screenshots.

The current road audit reports 124 roads, 30,300 nodes, 31,239 edges and 18 components; the largest has
99.2% of nodes. All 56 locations have a road entry, but only 2,310 of 2,604 location/profile requests plan;
294 fail and 180 are not tagged intentional. There are 17 isolated roads, 16 network near-misses, no
crossings without junctions, no steep listed road segments and one 7.2 m-radius turn. Kvernes's main-network
approach includes a 0.66 grade; Elvetun's short entry legs remain a dominant repeated failure.

## 5. Diagnosis

### Primary defect: far-tier local navigation is not pathfinding

`WorldSim._free_direction` samples straight, 45°, 90° and 135° directions and remembers a wall-following
side. That prevents most penetration and can slide around a short obstacle, but it cannot reason about a
distant opening or know when following the chosen side cannot reach the goal. Formation members solve this
independently, so six select a viable local history while two settle roughly 47 m from the valid goal.

The short gate test does not create a strategic route. Even where a route exists, `SquadControl` observes
leader progress only. A leader that reaches the goal makes the squad route complete; stranded non-leaders
do not increment route-stall/replan counters. This explains the observed zero route stalls/replans alongside
a 522.2 s member stall. Combat reactions did not contribute in the isolated run (`stalls_while_reacting = 0`).

### Dynamic-world inconsistency

Structure edits reach the camera-area navmesh and clear `VehicleRouter`'s failure/disabled-node caches.
They do not modify the 50 m strategic grid. Vehicle local legs and runtime bypasses therefore see a new
building, while a coarse infantry/operation route can remain valid on paper. This is a versioning/invalidation
gap, not evidence that the strategic grid should model every wall at 50 m resolution.

### Vehicle and road limitations

Vehicle routing already has the strongest local solver and handles the N1 dynamic obstruction. Its inputs
remain incomplete: trees/rocks are absent; width is mostly a graph penalty rather than swept-volume
feasibility; turn radius is applied to the driving profile after a largely point-based path; no tracked
profile exists; bridge width/load/capacity and bridge enabled state do not exist. Service-point geometry and
short endpoint legs account for practical failures even when the main road graph is connected.

### Performance baseline

The isolated gate run, with strategic AI paused, measured 6.90 ms average frame time, 7.34 ms p95,
7.85 ms p99 and 8.07 ms maximum over 580 frames. Average simulation buckets were: abstract 126.1 µs,
combat 21.3 µs, tactics 19.4 µs, war 13.7 µs, vehicles 11.7 µs, squads 1.3 µs and brain 0.5 µs.
The initial 30,300-node vehicle graph build measured 148–152 ms. Twelve N1-04 truck/APC plans averaged
304 ms with a 574 ms maximum on the cold run; a warmed repeat averaged 124.0 ms with a 204.3 ms maximum.
These are diagnostic baselines, not full-war performance claims; route planning is synchronous and is
already the principal spike risk.

## 6. Proposed implementation sequence — pending approval

### Step 1 — one shared local-search service, no new navigation engine

Extract the existing bounded 3 m A* leg search from `VehicleRouter` behind a small, stateless interface.
Inputs are start/end, a movement profile, dirty-region/version snapshot and a passability callback. Outputs
remain a dense local polyline or `{ok:false, reason}` plus cost/timing. `VehicleRouter` continues to own the
road graph and calls this service for endpoint and bypass legs. `StrategicRoutes` continues to own coarse
world corridors. This removes duplicated local truth without replacing Godot near-tier navigation.

### Step 2 — squad-level far-tier corridor

When an abstract squad's current coarse/direct leg intersects a blocking footprint or fails progress, plan
one bounded local corridor for the squad, not one search per soldier. Store the transient corridor and
version on `SquadState` only if save/load continuity requires it; otherwise rebuild it deterministically on
restore. Formation slots follow the corridor with clearance offsets. Completion and stall checks use all
active members (or an explicit quorum plus straggler handling), so leader arrival cannot hide two stuck
members. Near-tier bodies keep `NavigationAgent3D` and consume the same corridor endpoints.

### Step 3 — consistent passability and invalidation

Define movement-profile queries over the existing authoritative sources: terrain slope/water, structure
footprints, road class/width and bridge deck. Add monotonic versions and dirty rectangles for roads and
structures; cached local corridors carry the versions they were planned against. Replan only when an
intersecting dirty region invalidates the remaining corridor. Do not stamp walls into the 50 m strategic
grid; refine affected legs locally.

### Step 4 — vehicle profiles and physical constraints

Make profile differences explicit: width/length clearance, maximum grade, road/off-road cost and speed,
minimum turn radius for wheeled vehicles, pivot allowance and lower soft-ground cost for tracked vehicles.
Add a tracked definition only with an actual tracked vehicle/tank asset or a clearly labelled test profile.
Vegetation enters the same profile query after tree/rock collision radii are measured; do not add blanket
costs that disagree with rendered collision.

### Step 5 — service points, convoys and bridges

Validate each dock/parking approach as a swept entry-and-exit corridor and reject or relocate invalid
service points during base setup. Convoys reserve spacing through narrow segments. Model bridge width/load
only after those constraints have gameplay consumers. A destructible/disabled bridge requires a persistent
bridge identifier, enabled state, save/load and graph-edge ownership; keep it outside N1 rather than infer
destruction from deck geometry.

### Step 6 — acceptance and performance gate

Re-run N1-01…N1-09 independently, `r_yard,r_exit,r_obstacles`, the road audit and the directly affected
squad/vehicle/convoy suites. Required N1 exit criteria:

1. N1-01, N1-02, N1-03, N1-04, N1-05, N1-07 and N1-09 pass; N1-08 changes from `KNOWN_FAIL` to `PASS`.
2. Closed barriers have zero arrivals and zero penetration; every valid opening is reliable in both tiers,
   with no active member stalled for 25 s.
3. Dynamic edits invalidate only affected local work; every failure has a stable reason and endpoint/profile.
4. N1-06 remains explicitly unsupported unless bridge entities are separately approved and implemented.
5. No navigation frame exceeds the existing 33 ms 1× budget after warm-up; synchronous graph/local-search
   spikes are measured separately, and any search over budget is queued round-robin before broader scaling.
6. Save/load and camera-driven tier changes preserve the same order, reachable goal and passability result.

HPA*, flow fields and a second global navigation framework are rejected for N1 unless the measured shared
local solver cannot meet these criteria within budget.
