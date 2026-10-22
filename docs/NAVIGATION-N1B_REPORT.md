# NAVIGATION N1-B — vehicle routing, off-road traversal and road connectivity

Date: 2026-10-23. Branch: `develop`. Baseline: `53617b9` (N1-A). Godot 4.7.2. World: `ref_20km` (not regenerated).

N1-B is complete. It hardens the existing `VehicleRouter` / `VehicleSim` / `VehicleConvoy` stack; no new navigation engine,
no new assets, no bridge destruction or tracked vehicles (N1-C). `VehicleRouter` was **not** migrated onto
`LocalRoutePlanner`: the vehicle search needs clearance tiers, trunk stamping and parked-vehicle circles that the infantry
adapter does not have, and the migration would only have moved risk, not removed a defect.

## A. Before-baseline

Measured on the unchanged `53617b9` code (`--ai-war-test --only r_exit,r_obstacles,r_yard`, `--road-audit`).

| Item | Baseline |
|---|---|
| `r_exit` (24 docks/parking spots out and back) | 1 failure: East base 1, Fuel point dock — the truck stops 43 m from the dock |
| `r_obstacles` | parked vehicle and building both arrive; the building case took 789 s, two bypasses, three recoveries |
| `r_yard` | failed in the combined run (route 9.3 km for a point 400 m away); passes alone in 40 s |
| Road audit | 30 300 nodes, 18 components (largest 99.2 %), 294 / 2 604 routes failed, 180 unexplained, 17 isolated roads |
| Vehicle plan time (audit workload, 254 plans) | avg 127 ms, p95 292 ms, p99 326 ms, max 351 ms; 20 s of the 63 s was cross-country legs |

Classification of the 294 audit failures (all `No drivable route`): Kvernes 51 as destination, Elvetun 98, Haugen 6, and
3 per destination for the rest, i.e. one source each from Elvetun/Kvernes/Haugen. No failure was a graph defect in the main
network: all were *places whose own streets are isolated components* or whose short legs are cut by terrain.

## B. Root causes

1. **East fuel dock (`r_exit`).** Not the dock. The final 70 m is a straight cross-country leg. `line_ok` accepted it at the bare
   planning radius sampled every 2.5 m, and the Catmull-Rom spline through a 73 m segment then bowed it to 1.9 m from a depot
   corner; the truck's front circle (2.9 m ahead, 1.2 m radius) clipped it while turning. The stuck handler then declared
   the truck *arrived* 43 m from the goal (`_check_stuck` near-destination shortcut), so the failure looked like a timeout.
2. **Other tight docks.** Road lane shifts (up to 1.9 m) moved road points into structures; the string-pulled grid path only
   guaranteed free *cells*, not clearance, and the join between a blocked end point and the first free grid cell was never
   checked.
3. **`r_yard`.** A test precondition: `r_obstacles` leaves the faction's truck elsewhere, so the scenario picked a far target.
   Alone it passes.
4. **Dead ends.** A vehicle facing a wall with the route behind it steered full lock *forwards* into the wall; the stuck
   recovery's reverse used full lock too and swung the tail into the walls.
5. **Convoys.** Members never took a bypass (`convoy_id < 0` guard), even when a *structure* and not the vehicle ahead was the
   obstacle. A failed bypass search was also repeated every physics tick (6 490 attempts in one 284 s run).
6. **Bridge decks.** `line_ok` skipped all checks on a deck, so a building placed on a bridge was driven through.
7. **Isolated streets (Elvetun, Verket, Kvernes…).** The village centres sit on banks the truck (max grade 0.40) cannot leave,
   while the village's own street is a separate 16-node component 33–38 m from the main road — just beyond the 32 m gap
   repair — and only the three nearest roads were ever tried as entry points.
8. **Trees.** Trunks/rocks/settlement colliders were never read by the vehicle planner. Near the camera they are real
   colliders, in the abstract tier they are ignored — the planner has to keep clear, because the kinematic mover will not.
9. **CPU.** 76 % of plan time was `_road_path`: an A* **and** a per-vertex structure scan for *every* start×end candidate
   pair (up to 49 per plan), and the whole cross-country "direct" candidate (strategic route + refinement) was evaluated
   before the road candidates even when it could not win.

## C. Implementation

| File | Change |
|---|---|
| `scripts/vehicles/vehicle_router.gd` | Candidate stages (A* first, blocked-stretch scan and legs only for the cheapest combinations); direct candidate only when `distance × offroad_factor` can beat the best road; clearance tiers (wide `LEG_MARGIN` 0.9 m first, tight fallback), continuous line-of-sight check on string-pulled lines, join validation, straight line only with 0.6 m spare; road vertices within `circle_r + 0.6` of a structure are blocked stretches; `LEG_DENSIFY_M` control points keep the spline on straight legs; lane shift shortened near structures; trunk stamping into the grid; strategic cross-country routes refined piece by piece on the local grid (max 3 pieces when a road route exists); soft links; plan and leg caches; per-stage profile counters |
| `scripts/construction/structure_manager.gd` | `blocks_trunk`, `trunks_in_rect`, `blocking_boxes`: spatial index over the existing solid-vegetation list (`_trees_in`) — no new vegetation data |
| `scripts/vehicles/vehicle_sim.gd` | Reverse-follow mode when the route is behind and the way ahead is closed; reverse steering limited to a swept-clear lock; arrival shortcut only when a *vehicle* (not a structure) holds the vehicle; convoy members may bypass a structure; 6 s retry delay after a failed bypass; stale block cause cleared on movement |
| `scripts/vehicles/road_audit.gd` | uses the router's road clearance |
| `scripts/debug/navigation_n1b_selftest.gd`, `scripts/game/core_demo.gd` | `--navigation-n1b-test` (N1B-01…10 and diagnostics), output only below `user://navigation_n1b/` |
| `scripts/debug/ai_war_selftest.gd` | `r_yard` puts its truck in its own yard first; candidate log |

### Base access
Vehicle footprint: planning uses `circle_r` 1.6 (three circles ±2.9 m), driving `collide_r` 1.2. The 0.4 m between them is the
tracking-error allowance; N1-B adds the wide tier, the straight-line margin and the continuous check so the allowance is
real. No dock or parking position had to be moved: all 24 are valid once the approach keeps its clearance.

### Off-road
Hard: structure footprints (0.5 m grid test plus 1.5 m continuous), water, grade beyond the profile, trunks/rocks/settlement
colliders (radius + 0.4 m + the vehicle circle), parked vehicles. Soft: the truck/APC `offroad_factor`, unchanged. Dense
woods (≈150 trees/100 m) are planned through gaps when a path exists (one 376 m plan, one sample within 1.2 m of a trunk),
otherwise the leg fails and the planner falls back to roads.

### Road connectivity
`_soft` links: a dangling road end within 70 m (and 6 m height) of another component is *not* a graph edge; it is planned as a
cross-country leg **for the actual vehicle** when a route needs it. Nothing was connected by XZ proximity; a bridge never joins
the road under it (height test, unchanged `GAP_FIX_DY`).

### Performance
Caches: whole plans (1 m ends, vehicle type, parked-vehicle hash) and legs (0.5 m ends, not near parked vehicles), dropped on
any road or structure change. The old 90 s failure cache stays.

## D. Tests

Command: `Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/game/world_ref_20km.tscn -- --navigation-n1b-test [--only n1b_01,…] [--spot-filter=text] [--pairs=N]`

| ID | Scenario | Result |
|---|---|---|
| N1B-01 | All 24 docks/parking spots of both AI bases driven out to a road point ~600 m away and back (end ≤ 16 m, and ≤ 3 m unless a parked vehicle stands on the dock) | **PASS 24/24** (baseline 23/24) |
| N1B-02 | Truck at the closed end of a 7 m dead-end alley between three depots, nose to the wall | **PASS**: reverses out, 92 m, 37 s, 0 recoveries, longest stop 1 s |
| N1B-03 | Truck outside the base refuels, loads and unloads through the real job system | **PASS** all three jobs, longest stop ≤ 6 s |
| N1B-04 | APC through a 42 trees/100 m corridor (straight line hits 23 trunks) | **PASS**: 496 m route, 0 trunk/structure/water samples, 0 of 3 618 driven ticks touching a trunk |
| N1B-05 | Truck vs APC | **PASS**: APC takes 3.8 km off-road to Verket where the truck takes 6.9 km; of 1 200 random 60 m lines 7 are APC-only, 0 truck-only |
| N1B-06 | Building on a bridge deck | **PASS**: blocked route is reported (stable reason, cached repeat), route restored after removal. Before the fix the plan drove through the building |
| N1B-07 | 17 isolated roads from North HQ | **PASS**: APC reaches 17/17, truck 12/17; the other 5 are classified (straight-leg grade 0.41–1.15 to the main network) |
| N1B-08 | Three-truck convoy, building on the route in open ground | **PASS**: all three arrive (bypass by the structure rule), no longest stop above the limit |
| N1B-09 | Burst of route requests | **PASS** (warm): 18 plans avg 30 ms, max 61 ms; whole-fleet burst max 141 ms; convoy order max 110 ms |
| N1B-10 | Road audit | **PASS**: 104 failures (baseline 294), 2 unexplained (baseline 180) |

N1B-06 and N1B-08 used placement checks (open ground, no trunk within 30 m, ≥ 40 m from other structures) so the scenario tests a
detour that exists; a building in woods or inside a base has none and would only prove the way is closed.

### Regressions
* `--navigation-n1-test` (N1-01…09, N1-A 10/11): all PASS, N1-06 UNSUPPORTED as before.
* `--ai-war-test`: `r_exit` 0/24 failed, `r_yard`, `r_obstacles`, `r_gaps`, `r_lanes`, `r_offroad`, `r_convoy` pass.
* `e_convoy` passes alone; `--logistics-test --only convoy` only fails "supplies not conserved", which also fails on the unchanged code.

**Order dependence (documented, not fixed):** `r_convoy` reported "a member has no route" when run after `r_offroad` in one
process and passes alone. The `--logistics-test` and `--ai-war-test` subsets `c_vehicle,d_mech,e_convoy,g_delivery,m_save` and
`veh_drive,transport,logistics,convoy,bases,persist_logistics,scenario` fail many checks on the **unchanged** `53617b9` too (29 failed
checks there, 18 with N1-B, different ones in each run: `G`'s "never reached serving", base recruit/stock checks, APC `veh_drive`).
They depend on stock and vehicles left by earlier scenarios; they do not show an N1-B regression, but they also do not
prove the absence of one — the full 115-minute regression was deliberately not run.

### Visual verification
A rendered run (1600×900, Vulkan) of N1B-02 and N1B-04 was inspected: the truck backs out of the alley mouth without touching
the depots, and the APC drives through the woods without visibly clipping; no pops or reversals in the frames.
**Not covered visually:** the convoy passing the obstacle, a vehicle leaving a road to an off-road goal, and the East-dock
approach. They are covered by the numeric tests only.

## E. Performance (audit-location pairs × truck and APC, cold caches; the before run used 254 pairs, the after run a 123-pair subset of the same stride, so the samples differ slightly)

| | Before | After |
|---|---:|---:|
| avg plan | 127 ms | 57 ms |
| p95 | 292 ms | 105 ms |
| p99 | 326 ms | 162 ms |
| max | 351 ms | 162 ms |
| A* calls per plan | ≈ 49 | ≈ 26 |

Yard starts (parked vehicles, 3-truck burst, 18 plans): before avg 191 ms / max 427 ms; after avg 30 ms / max 61 ms
(cross-country candidate skipped when a cheaper road route exists: leg time 4.3 s → 0.26 s).

**Remaining bottlenecks / negative effects**
* A plan that starts in a village in dense woods (Verket → South Bridge) still takes ~290 ms warm, ~430 ms cold: the direct
  candidate's 3 allowed local refinements plus trunk stamping (~12 µs per grid cell).
* The first plan after any structure placement rebuilds the vegetation collider caches (`_apply_clearings` clears all
  cells): a one-off 50–300 ms. Finer invalidation would fix it.
* A plan through dense woods can take 400+ ms (N1B-04 first plan 435 ms).
* Truck plans through woods are longer than before (trunks are now hard); long cross-country trips through forest may be refused
  and use roads instead.
* A 3 m local grid and string-pulling with 0.9 m margin make off-road routes slightly longer than the old straight ones.
* The planner does no work in a background thread; nothing was needed to meet the measured budgets.

## F. Further work

* N1-C: dynamic bridges (persistent bridge entity, width/load), tracked profiles and pivot turns.
* Kvernes (51 failing destinations), Grensen, Nordre gate 2 and Fjellfoten gate 2 are blocked by genuinely steep ground; the
  map data would have to change or a connecting track be generated.
* Cache invalidation per vegetation cell; incremental trunk index.
* Convoy members still never reverse (they keep the old forward behaviour so the column cannot back into itself).
* Near-tier physics check of the kinematic-vs-body difference for trunks (the far tier ignores trunks by design; the planner is
  the only guard).
* The order-dependent suites above should reset their own stock/vehicles.
