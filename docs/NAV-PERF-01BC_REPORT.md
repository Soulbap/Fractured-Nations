# NAV-PERF-01B+C — incremental route planning, road connectivity and AI movement integration

Date: 2026-10-23. Branch `develop`, baseline `f8f596e` (EDITOR-WORLD-02B+C, which contains NAV-INF-01, N1-C1 and NAV-PERF-01A).
Godot 4.7.2, world `ref_20km` (not regenerated; no world data, road, terrain or bridge was changed; manifest verified, see §10).

**Status: implemented and verified headless; visual (GUI) validation not done.** Incremental planning, the job queue, integration
with infantry, operations, vehicles and convoys, and the road diagnostics are done and tested (§3-§10). Not done: the GUI run with
screenshots (`--nav-perf-bc-test --only z_visual --shots` exists but was not run, so §11 has no pictures), and one older logistics
scenario still differs from the baseline (§12). Nothing is pushed.

## 1. Navigation architecture before this milestone (measured on `f8f596e`)

Who asks for a route, who computes it, and what happens to it:

| Route | Asked for by | Computed by | Cost on the baseline | Cached | Invalidated by |
|---|---|---|---|---|---|
| Infantry march (strategic, 50 m grid) | `SquadControl._routed_move` (every Move > 150 m or across water/cliffs), `_replan` (stalled leg), `_reroute_around` (closed bridge); `WarSim._plan_route` for every squad of `start_operation`, `_send`, `join_operation` | `StrategicRoutes.route` (native `AStarGrid2D` over 400 x 400 cells + waypoint reduction) | 0.4-2.5 ms per 3-27 km route (native A* 0.05-1.5 ms); 50 squads ordered at once: 92 ms in one call | no | bridge closed -> `_reroute_for_bridge` (only squads whose remaining route crosses it) |
| Abstract-infantry refinement round an obstacle (far tier) | `WorldSim._abstract_step` when a step is refused | `LocalRoutePlanner.plan` (5 m grid round the leg, walker check, repairs) | **avg 187 ms, max 454 ms per search** (30 random 120-480 m legs); one search per physics tick | per squad (shared route) + failure memory | bridge change (all dropped), order change |
| Vehicle route | `VehicleSim.order_drive` (player group orders, convoys, transport, logistics jobs, operations' vehicle tasks, release of the wheel), bridge replans (`_process_replans`, one per tick), stuck replans; feasibility checks in `OpTransport` (assembly -> unloading) and `WarLogistics.request_supply` | `VehicleRouter.plan` (road A*, candidate combinations, cross-country legs on a 3 m local grid, assembly) | 26-143 ms per plan (12 trips), dense woods 108 ms; NAV-PERF-01A: bursts of 3 orders 150-400 ms in one frame | plan, leg, failure caches (64 m cells) | road / structure / bridge events (targeted, N1-C1) |
| Near-tier body path | `SoldierBody` (NavigationAgent3D) | Godot navmesh (`AreaNavigation`, threaded bake) | not part of this milestone | - | `DetailManager` rebakes |

Every search ran to its end inside the call that asked for it. Every consumer assumed the answer in the same frame: `start_operation`
returned `null` when no squad had a route, `order_drive` returned the plan, convoys read the leader's finished route, `OpTransport`
read `route_remaining_m()` right after ordering.

## 2. Bottlenecks found

Measured with `--nav-perf-bc-test --only b_strat,b_local,b_burst,b_op,b_vehicle` on the baseline (`--tag=baseline`), headless:

* **The abstract-infantry refinement was the worst stall**: 100-450 ms per search, run inside a physics tick. With 50 squads
  marching the frames averaged 345 ms (max 609 ms) at 4x; at 10/25 squads single frames of 156/196 ms. Its cost is the grid
  build: up to 30 000 cells, each tested by five obstacle callbacks (structure footprint, deck, water) and two height reads.
* **Vehicle plans**: 26-143 ms each, synchronous in the order call; a group order of three trucks puts three of them in one frame.
* **Strategic infantry routes are cheap** (max 2.5 ms for 27 km), but every Move order and every squad of an operation planned one
  synchronously: 50 orders in one call = 92 ms, an 8-squad attack 4.8 ms.
* Nothing could be split, cancelled, prioritised or shared; there was no measure of route work per frame.

## 3. Incremental route planning (DEL A)

**One service.** `RouteService` (`scripts/navigation/route_service.gd`, owned by `WorldSim` as `sim.routing`) is the only place a
route search of normal play runs. It is stepped once per rendered frame from `WorldSim._process` with a work budget
(`frame_budget_ms`, default 2.0 ms). Under time compression a frame carries several simulation steps; the budget is per step
(`max_steps` = 64), so a route takes the same *simulated* time to arrive at 1x and at 8x and `TimeCompression` keeps the frame
within its own budget by running fewer steps. No threads: every search runs on the main thread between checkpoints, which keeps
the world data (Terrain3D, structure caches, the router's graph) single-threaded and the results identical to the synchronous ones.

**Runners keep the search state.** A job owns a runner with `step(deadline_us) -> bool`, `result` and `reset()`:

| Runner | Kind | Incremental state | Unit of work between checkpoints |
|---|---|---|---|
| `LocalRoutePlanner.Search` (+ `EndCell`, `Walk`) | `infantry_local` (via `WorldSim.LocalJob`) | grid heights, blocked cells (48 cells per check), entry cells (4 walker checks), the native A*, the walker's check along the route (24 samples), the steep-ground repair (one neighbour cell) | one native A* on the finished grid |
| `VehicleRouter.PlanRunner` | `vehicle` | memo of the plan: candidate lists, every road A* path, every pair's combination, road gaps, legs, the local 3 m grids (heights 96 / cells 48 / trunks 64 per check), each grid search, the assembly (lanes, spline, heights 256 per check) | one road A*, one grid search, the spline |
| `StrategicRoutes.Runner` | `infantry` | none (measured 0.4-2.5 ms for 3-27 km) | one route |

`LocalRoutePlanner.plan()` is now the same `Search` run without a deadline, and `VehicleRouter.plan()` without a slice is the old
synchronous plan: one implementation, two ways to run it. Equality is tested: 30 local searches (sliced at 2 ms vs at once: 0
route mismatches; the resumable entry-cell search against the original on the same grids: see §9) and 12 vehicle trips (0 route
mismatches between `plan()` and `PlanRunner` at 2 ms).

A vehicle plan resumes by calling `plan()` again with the memo: every finished piece is found there, so a step costs the new
piece plus a short replay (the memo makes the replay cheap: resumable plans take 71.9 ms of work in total against 63.6 ms at
once, average of 12 trips). The router's mutable per-plan fields are set per step (parked vehicles are captured when the job is
made). A world change restarts the runner (`reset()`).

**Area-aware obstacle tests.** The infantry grid build asks per search area once whether any footprint, bridge deck or water
surface can be there (`WorldSim._infantry_area`) and skips the tests that cannot answer "blocked" (same answers, half the work:
avg 186 -> 93 ms of work per local search, the same 30 routes).

**States** (`RouteService.State`): PENDING, RUNNING (started, possibly suspended), COMPLETED, FAILED, CANCELLED, INVALIDATED (a
running search the world changed under: counted, reset, queued again). Consumers get a callback on COMPLETED / FAILED and check
their own token (the job id they stored); an answer for a replaced order is never applied.

## 4. Queue, priority and cancellation

* **Priority**: PLAYER (player squads and vehicles), COMBAT (squads running a tactic, reacting walkers), OPERATION (operation
  squads, transport and supply checks), CONVOY (convoys, logistics jobs, bridge replans), STRATEGIC (everything else). A job gains
  one class every `aging_s` (1.5 s) it waits; a started search goes on before a new one of the same class.
* **Supersede**: a new request of the same owner (`squad:12`, `unit:40`, `vehicle:7`) cancels the old one, unless it asks the same
  thing (same key): then the search under way is kept (no cancel-and-restart loop).
* **Dedupe**: requests with the same key (infantry: same 50 m start and goal cells; vehicles: same ends to 1 m, type and parked
  vehicles) follow the first and share its answer. If the first is cancelled, a follower takes the search over.
* **Reuse**: completed infantry routes are kept until the world changes (revision); a cache hit answers at once.
* **Invalidation**: road, bridge, structure and terrain-edit events bump the revision; a running search whose area is touched (local
  searches carry their grid rectangle; strategic and vehicle searches are treated as touched) restarts.
* **Measurements** (overlay **F6**, `RouteService.report()`): work per frame (last, p95, max), the longest single step overall and
  per kind, overruns, queue now / max / by kind and state, wait before start, time to result, search work, and counters (submitted,
  completed, failed, cancelled, superseded, invalidated, shared, cached, same-again, synchronous runs).

## 5. Integration with infantry and AI (DEL C)

* **SquadControl** asks instead of planning: `request_route(sq, goal, kind)` with kinds `move` (an order: the squad stands, status
  MOVING, until the route comes; no route: the old straight walk to the slots), `replan` (a stalled leg: the old route is walked on
  meanwhile; no route: the leg is skipped as before), `bridge` (round a closed bridge: walks on, its walkers refuse the deck; no
  route: stops with the reason) and `op` (WarSim takes the answer). The request is saved on the squad (`route_wait_*`), so a squad
  loaded while waiting asks again; any squad order (`order_move/hold/follow/regroup`, `follow_route`, `clear_route`, a tactic)
  drops it. `marching(sq)` (route or pending) replaces "route not empty" where code asked whether a squad is on the march
  (SquadTactics autonomy, OpCoordination roles, OpTransport, WarLogistics, WarSim).
* **WorldSim local refinements** are `infantry_local` jobs (`LocalJob`): the shared squad route and the failure memory are looked
  at when the job starts; the retry budget (NAV-INF-01) is unchanged. A walker waiting for its job is not a stalled member for
  SquadControl.
* **WarSim operations**: `start_operation` adds the squads and asks for their routes (`op.starting`, "planning routes"); the
  operation *begins* (transport plan, the march) with the first route that arrives. A squad that gets no route leaves it; if none
  gets one it is CANCELLED with "no route (...)" (before, `start_operation` returned null - no failure counted, no recovery delay).
  Re-sends (`_send`, `join_operation`, OpTransport's late foot squads) are requests; a failed answer sets the old retry
  (`ROUTE_RETRY_S`), `wait_reason = "route blocked: ..."` and the `ROUTE_BLOCKED_TIMEOUT_S` failure. Pending counts as marching.
* **Authority** is unchanged (player > operation > squad tactic > reaction): requests are owned by the squad, and every order path
  that changed the squad's order before still does; the late answer of a replaced order is dropped by the token.
* **C4, no planning loops**: a request for the same thing keeps the running search; a stalled leg does not ask again while its
  replan is pending; a walker or vehicle waiting for a route is not counted as stuck; failures are remembered (WarSim retry
  interval, router failure cache, walker failure memory) and an unreachable goal ends in a reason, not in a loop.

## 6. Vehicles and convoys

What exists and is integrated (LOGISTICS-01, N1-B, N1-C1):

* `VehicleSim.request_drive` is the order of normal play: the vehicle takes the order (MOVE, target), stops and waits (status
  WAITING, "planning route"), and drives the route when the job answers. No route or not enough fuel: `Path blocked: ...`, status
  BLOCKED - the same failure path transport, logistics, convoys and operations already handled after N1-C1. Switched to it: the RTS
  group order, `release_control`, VehicleTransport (approach, transit), LogisticsSim jobs (to depot, parking, retries), OpTransport
  (assembly, unloading, home), WarLogistics supply runs. `order_drive` stays as the at-once API (tests, tools).
* **Convoys** form from the leader's route: the leader is asked first (CONVOY priority), the others get their stopping places in
  column behind its end when it arrives; a leader without a route hands the lead to the next vehicle.
* **Bridge replans** (closed deck ahead) and **stuck replans** are jobs; the vehicle keeps braking short of the deck meanwhile and
  no recovery runs while it waits.
* **Feasibility checks** that planned at once inside a decision are jobs: OpTransport's assembly -> unloading check (the vehicles keep
  assembling while it runs) and WarLogistics' truck route check (the request answers "pending" and is asked again 2 s later).
* **Identical requests** (same ends, type and parked vehicles) share one search.

Not integrated (stays synchronous, documented): `VehicleRouter.bypass_leg` (the local detour of a stuck vehicle, one local grid
<= 500 m, part of stuck recovery), `RoadAudit` (a diagnostic tool), and the at-once `order_drive` used by tests. No new vehicle
physics or logistics framework was built.

## 7. Road network diagnostics (DEL B1)

Two read-only tools; nothing in `roads.json`, the Road Generator scene, the terrain or the bridges was changed.

**Static** (`python tools/terrain_ref/road_connectivity.py`, output `benchmarks/raw/road_connectivity_static.json`):

| Check | Result |
|---|---|
| roads.json | 124 roads, 30 300 points; 0 zero-length segments, 0 duplicate roads, 0 duplicate junction entries; all 10 junction entries have two or more roads meeting |
| Road ends (248) | 87 joined, 18 at the map edge, 51 at a settlement/plateau (access roads), 16 street dead ends in villages, **75 near misses** (an end 10.5-45 m from another road: 54 within 32 m, which VehicleRouter repairs as a graph link; 21 at 32-45 m, which it plans per vehicle as a soft link), **1 unexplained dead end**: `Lv fjellfoten nord` ends at (6000, -9000), 2 km from Fjellmoen and 3.5 km from Nordre, not at the map edge |
| Components (joined as the router joins, 10.5 m) | 35; 29 of the near misses are between different components (village streets: Haugen, Sentrum, Vestli, Kvernes, Nordvik, Bruvoll, Elvetun, Østby, Nordre ...) |
| Road Generator scene | 4 545 RoadPoints, 113 containers, 10 intersections, 4 558 edges, **one component**; 0 dangling NodePaths, 0 one-way container edges, 0 duplicate edges, 10 open ends (the mesh roads' ends); every RoadPoint lies on a roads.json road and every mesh road (primary/secondary) is covered; every junction entry has an intersection |
| Representations | The scene holds only the 10 mesh roads (primary, secondary); the 114 streets, local roads and tracks exist only in roads.json (decals / terrain), so "connected in one representation, missing in the other" is by design for them, and both representations agree for the mesh roads |
| Bridges | 4 spans (98-110 m), each with its bridge structure (`RoadStructures/Bridge_00..03`) |

**In the running game** (`RoadAudit.connectivity`, case `b_roads`):

| Check | Result |
|---|---|
| Router graph after repairs | 30 300 vertices, 49 repaired gaps, 14 soft links, **18 components**: the main network (30 048 vertices) and 17 village streets that no repair joins (Sentrum gate 21, Verket gate 2 and 3, Elvetun gate 1, Grensen gate 2, Ødegård gate 3, Kvernes gate 1, Nordre gate 2, Moen gate 2, Vestli gate 3, Haugen gate 1, ...) - reachable by vehicles only through soft links or cross-country legs |
| Places far from the main network | **Flyslette øst** (the eastern airfield plateau): 1 351 m to the nearest main-network road. Trucks cannot plan to or from it ("No drivable route"); infantry can (11.9-18.4 km routes) |
| Strategic (infantry) grid | 150 167 passable cells in 271 areas; the largest holds 99.3 %; **no named place lies outside it** |
| Bridges | all 4 traversable: span vertices present and on, a graph path across through them, the deck known along its whole length (0 gaps in 50-56 samples), the strategic cells under the span open, an infantry route across laid on the deck (5 deck waypoints), 0 walker refusals along the deck, truck and APC fit |

Map-data findings (not changed; proposals for the product owner):

1. **Flyslette øst has no road access** (1.35 km to the network). Proposal: an access road from the nearest main road, or accept it as foot/air only.
2. **17 village streets are separate road components** (ends 33-45 m from the next road). The router drives them through soft links; the road decals do not meet. Proposal: extend the street ends in `layout_ref03.json` so the generator joins them (a world regeneration: needs approval).
3. **`Lv fjellfoten nord` ends in the open** at (6000, -9000). Probably an intended forest road; to confirm.
4. **Terrain steps under truck routes**: 1-7 places per long truck route where the terrain under the road rises 0.47-0.70 over 6 m (village centres and junctions: Haugen (-1590, -4390), Sentrum (-914, -1811), the junction at (-395, 1727), Østby (3242, 1896), Vestli (-8521, -4961), Elvetun (-2990, -7489), Østmark (7542, 6024)). The routes are the roads themselves; whether these are real kerbs/steps or the Terrain3D height bands NAV-INF-01 found needs a visual check.

## 8. Bridges and dynamic blocking (DEL B3)

| Test | Result |
|---|---|
| `c_bridge` infantry: Centre Bridge closes while a squad is 180 m before its deck | 1 route request (a `bridge` job), rerouted round the river, the new route does not cross the deck, 0 samples on the closed deck in 2 simulated minutes; a squad marching elsewhere got **no new request** and kept its route; reopening left the march in progress alone; a new order uses the bridge again - PASS |
| `c_bridge` truck: the same bridge closes 260 m before the deck | the bridge replan ran as one service job, the truck took another route, never entered the closed deck, no jump - PASS |
| `b_roads` bridges | all four traversable when open (see §7) |
| N1C1-01..05, 08, 09, 12 (regression) | PASS |
| N1C1-06 convoy round a closed bridge | PASS after a test fix: the check of "the convoy is dissolved" ran in the frame the last vehicle stopped, before VehicleConvoy's 2 s update; a diagnostic run showed all three members parked and the convoy gone 3 s later (the members arrived over the other bridge in both runs) |
| N1C1-07 infantry far tier | FAIL in the first run (4/6 of a squad on the deck when the bridge closes arrived), PASS in the second (5/6). The same signature (two soldiers beside the deck, "no local passage") was recorded as flaky in NAV-INF-01 before this milestone |

## 9. Movement tests (DEL C, D)

All in `--nav-perf-bc-test` on `ref_20km`, results in `user://nav_perf_bc/nav_perf_bc_<tag>.json`.

| Case | What | Result |
|---|---|---|
| `a_service` | states, callback, failure, supersede, same request again, shared search, heir after cancel, priority, aging, invalidation (and none from a change elsewhere), result cache, cancel all, 60 jobs at 2 ms per frame | all PASS; 60 jobs: frame max 2.3 ms, all done in 86 frames |
| `c_pending` | order -> pending (squad MOVING, no failure) -> route; a newer order wins (route ends at the new goal); Hold while pending drops it; an operation waits for its routes and stays MOVING | PASS (routes in 1 frame) |
| `c_vehicle` | request -> pending (order MOVE, vehicle WAITING) -> route after 18 frames -> driving; newer order wins; halt drops the answer; a convoy forms from the leader's route (all routed in 41 frames) | PASS |
| `c_ops` | three factions start operations in one frame (8 squads routed in 3 frames, none failed); an operation cancelled while pending gets nothing; a changed target ends at the new goal; reinforcements join | PASS |
| `c_loop` | a squad and an operation with goals across the river, every bridge closed, 120 simulated seconds | 3 route requests in total; the operation is cancelled "no route (disconnected passable cells)" at once; the control squad on the same bank got its route |
| `e_persist` | saved in the frame the routes were asked for (squad, truck, starting operation), loaded after they arrived | after the load all three wait again and get their routes (69 frames) - PASS |
| `d_long` far | 6 soldiers Haugen -> Sentrum, 3.2 km route, abstract tier | 6/6 arrived in 728 s, 0 stalls, 0 replans, 0 jumps, 0 water samples, 1 local search (40 ms of work) |
| `d_long` near | 6 soldiers, 1.2 km with the camera on them (bodies, navmesh) | 6/6 arrived in 433 s, 0 jumps (max step 0.3 m), 4 leg stalls, 3 squad replans, 22 member recoveries (13 members used up their recovery budget on the way and recovered later): the near-tier body behaviour NAV-INF-01 documented, not route planning |
| `d_haugen` | 4 South squads attack Haugen (held by 2 North squads, combat on) from 2 km | all 4 routed 0.08-0.2 s (simulated) after the order, none lost its operation, 0 losses, the force reached the approach end (three squads 223 m, one 75 m from Haugen) and the operation moved on to ENGAGING; navigation PASS |
| `d_load` | 10 / 25 / 50 squads ordered at once (see §10) | every squad routed within 0.05 / 0.07 / 0.12 simulated seconds |

## 10. Performance before and after

Same harness on `f8f596e` (temporary baseline harness, same workloads) and on this code, headless, this machine. Frames are wall-clock
frame times; "route work" is RouteService's own time per frame.

| Workload | Before | After |
|---|---:|---:|
| 10 squads ordered at once: order call / frame max next 8 s (1x) / p99 | 24.5 ms / **160 ms** / 12.1 | 10.2 ms / **10.2 ms** / 9.1 |
| 25 squads: order call / frame max / p99 | 47.0 / **161** / 13.9 | 19.7 / **12.3** / 11.0 |
| 50 squads: order call / frame max / p99 | 91.7 / **164** / 22.3 | 40.9 / **19.7** / 13.9 |
| Route work per frame, 10 / 25 / 50 squads (1x, max) | (synchronous) | 3.0 / 4.1 / 8.1 ms (8.1 = the 4x budget) |
| Time from order to route (simulated) | same frame | 0.05 / 0.07 / 0.12 s |
| 4 trucks: group order + 2 single orders, call time | 96.5 + 40.4 ms | 0.1 + 0.1 ms |
| same, frame max next 10 s | **148.5 ms** | **9.0 ms** (route work max 5.9 ms) |
| 8-squad attack, `start_operation` | 4.8 ms | 0.2 ms |
| Abstract-infantry local search (30 legs) | avg 186 / max 466 ms in one tick | avg 92 / max 222 ms of work, in steps of max 2.6 ms |
| Vehicle plan (12 trips) | avg 63 / max 146 ms at once | 66 ms of work, longest step 7.8 ms, same routes |
| Strategic infantry route | 0.4-2.5 ms | unchanged (one step) |

Remaining order-call cost (10-41 ms for 10-50 squads) is not routing: it is formation choice per squad (`choose_formation` counts
trees). Frames at 4x with 50 squads (300 soldiers) average ~290 ms before and after: the abstract simulation step, not route
planning. Longest atomic pieces: vehicle spline 7.8 ms, local grid search 5 ms, road A* 3.5 ms, strategic route 2.5 ms.

## 11. Visual documentation

Not done in this milestone (see Status). The F6 overlay (`RouteServiceOverlay`) shows the queue and budget live.

## 12. Open problems and next steps

* **Visual validation**: run `--nav-perf-bc-test --only z_visual --shots` in the GUI build and inspect.
* **Logistics convoy scenario** (`--logistics-test --only convoy`): baseline has 2 failing checks (deterministic); this code has 1-2
  more that vary between runs. Mechanism found: after the player drives truck 2 and hands it back, the convoy leader waits for it and
  drops it as a straggler (`VehicleConvoy` deferred `leave`); it then drives alone, arrives before the leader and blocks the dock.
  Not fixed.
* **Determinism**: routes now arrive after a wall-clock budget, so simulations that depend on exact arrival ticks (old logistics
  checks) are no longer bit-for-bit repeatable.
* Pre-existing, unchanged: AI-WAR D->E fails identically on the baseline; N1C1-07 is flaky (as recorded in NAV-INF-01).
* Still synchronous: `VehicleRouter.bypass_leg` (stuck-vehicle detour), `RoadAudit`, the test-only `order_drive`.
* Vehicle jobs restart on any structure change (they have no search area); the order-call formation cost; the abstract step at 300 soldiers.
* Map findings in §7 (Flyslette øst access road, 17 street components, one dead end, terrain steps) need product-owner decisions.

Tests run (targeted): `--nav-perf-bc-test` (all cases, PASS), `--nav-inf-test` 01/04/09/11/12/ai_ops PASS, `--navigation-n1c1-test`
01-09, 12 PASS (06 after test fix, 07 flaky), `--navigation-n1b-test` 04/06/08 PASS, `--ai-strat-test` a_assault/c_reinforce/e_withdraw
PASS, `--ai-war-test` d_mech/e_convoy/f_preop/g_delivery/r_convoy (E fails as on baseline), `--logistics-test` convoy/transport/logistics
(see above). World manifest: `VERIFY ref_20km OK: 535 files checked, 0 changed`.

