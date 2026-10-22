# NAVIGATION N1-A — infantry pathfinding, obstacle avoidance and near/far parity

Date: 2026-10-22. Branch: `develop`. Baseline: `cf93dab`. Godot: 4.7.2. World: `ref_20km`.

N1-A is complete. It adds bounded local route refinement for abstract infantry, member-level
stall recovery and explicit navigation failure reasons without changing strategic route, command,
tactical, vehicle or simulation-loop ownership. The final N1 suite passes every supported case;
N1-06 remains deliberately `UNSUPPORTED` because dynamic bridge state is outside N1-A.

## A. Root cause

### N1-02, N1-08 and N1-09

The reproduced far-tier failure followed this call chain:

`SquadControl.order_move` -> formation slot orders -> `WorldSim._abstract_step` ->
`WorldSim._free_direction`.

`_free_direction` was collision-aware wall sliding, not pathfinding. It sampled straight, 45, 90
and 135 degree alternatives and remembered a side. It could avoid penetration and get around a
short end, but it could not search for the valid opening in the HESCO/fence perimeter. Six members
found a viable history; two stopped about 47 m from their targets for more than 522 simulated seconds.
The 50 m `StrategicRoutes` grid was not the failure in this direct, short movement, and combat/order
priority was disabled in the reproduction.

The second cause was in `SquadControl._update_route`: route progress and recovery were leader-based.
Once the leader completed the leg, two stranded formation members could not trigger the existing
route watchdog. The baseline therefore recorded zero squad route stalls despite the two permanent
member stalls.

### Why the near result appeared to lose one soldier

The near-tier `NavigationAgent3D` did not lose that member. The old harness counted every soldier
against a 14 m radius around the formation centre. The outer wedge slot is 15.3 m from that centre;
the soldier had completed its assigned slot and was 1.3 m from its own target. The acceptance check
was corrected to require `ARRIVED`, at most 3.1 m from the member's own slot and a 20 m centre guard.
With the same movement code, the near open-gate case is 8/8. `SoldierBody` now also records a reason
when a near path ends genuinely short, so future failures are not hidden by the aggregate count.

The closed-wall near case remains correctly blocked. Its agents end at the navmesh boundary, report
their remaining distance and never enter a blocking footprint.

## B. Implementation

### Changed files

| File | Change |
|---|---|
| `scripts/navigation/local_route_planner.gd` | New bounded, stateless local A* adapter with caller-provided height and blocking rules. |
| `scripts/core/world_sim.gd` | Far-infantry route refinement, squad corridor reuse, planning budget, passability checks, bounded retry and metrics. |
| `scripts/core/squad_control.gd` | Per-member progress watch and one controlled recovery of the authoritative formation-slot order. |
| `scripts/core/unit_state.gd` | Persisted concise `nav_reason`. |
| `scripts/core/world_state.gd` | Clears the reason on a new move and restores it from snapshots. |
| `scripts/units/soldier_body.gd` | Reports why a physical near path ended blocked. |
| `scripts/debug/navigation_n1_selftest.gd` | Correct slot-based acceptance, member diagnostics, transition/save/tactical tests and optional rendered QA shots. |

`VehicleRouter` was inspected and its bounded local-grid pattern informed the adapter. It remains
byte-identical to the N1 baseline: moving its production path onto a new utility was a larger refactor
than N1-A required and introduced avoidable regression risk. The new adapter is profile-neutral, but
N1-A uses it only from the existing `WorldSim` infantry owner.

### Local path refinement

`StrategicRoutes` still owns long routes, `SquadControl` still owns squad/formation movement and
`WorldSim` still owns abstract movement. An abstract soldier follows its existing target directly
until the next step intersects a structure footprint. `WorldSim` then queues a local refinement:

* 5 m cells, at most 60,000 cells and at most a 500 m local leg;
* terrain height and grade, structure footprints with 0.5 m clearance, water and bridge decks;
* centre and near-corner footprint samples, with solid cells impassable rather than merely expensive;
* one A* search per physics tick;
* at most three planner attempts for one move, followed by `BLOCKED` and a stable reason;
* one successful corridor cached per squad/goal and reused by the other formation members;
* cached corridors invalidated on collision, new order, promotion, removal or restore.

The corridor is transient. `UnitState.order_target` remains the authority, so promotion, demotion and
save/load do not replace or mutate the command. No teleport recovery is present.

### Member stall handling

`SquadControl` now tracks each active member's target, last position, last meaningful displacement,
time without progress, retry count and failure state. Movement of more than 1 m resets the timer, even
when a valid detour temporarily increases final-target distance. After 25 simulated seconds without
movement, or an explicit blocked result, the controller grants one recovery attempt at the same slot
and invalidates only that member's transient local route.

The watchdog pauses for player possession, transport, detached members, Hold, and active tactical
reactions. It does not change squad ownership, tactic or order priority. A failed budget leaves the
member blocked with an explanatory `nav_reason`; it cannot enter an endless replan loop.

### Near/far consistency

Near movement continues to use `AreaNavigation` and `SoldierBody`. Far movement applies the same hard
structure/water premise through the bounded grid. Registering a body clears the transient far route;
demotion simply rebuilds one if the still-authoritative target later needs it. Snapshot application
preserves the order, target, movement state and reason. Transition tests also track maximum per-frame
displacement to reject teleport fixes.

## C. Test results

### N1 before/after

| Scenario | N1 baseline | N1-A final |
|---|---:|---:|
| N1-01 building | PASS (old 7/8 centre metric) | PASS, 8/8, zero footprint samples |
| N1-02 open/closed port | FAIL | PASS; open near 8/8, open far 8/8; closed 0/8 in both tiers |
| N1-03 vehicle bypass | PASS | PASS; one bypass, arrival 1.0 m from goal |
| N1-04 vehicle profiles | PASS | PASS; distinct truck/APC choice retained |
| N1-05 bridge convoy | PASS | PASS; 3/3 arrive and cross |
| N1-06 bridge disabling | UNSUPPORTED | UNSUPPORTED, unchanged |
| N1-07 new base obstruction | PASS | PASS; infantry 8/8 and vehicle bypass retained |
| N1-08 far defence line | KNOWN_FAIL, 6/8 | PASS, 8/8 through the valid opening |
| N1-09 near/far parity | FAIL | PASS, equal reachability and same passage |

The final complete run reports no harness failures. In the open-gate far run the maximum observed
member stall is 0.7 s, all eight target distances are 0.0 m, and 7 members reuse the first member's
local corridor. The closed perimeter produces no blocking-footprint penetration and reports
`blocked: no local passage` rather than crossing the wall.

### New focused checks

* `n1a_10`: near -> far and far -> near both finish 8/8; targets/orders retained; save/load succeeds;
  maximum sampled step is 1.68 m and 1.40 m respectively; zero units end inside obstacles.
* `n1a_11`: a member held in a legitimate cover reaction spends zero recovery attempts, keeps the
  original Move order, then resumes and the squad finishes 8/8.
* Closed/open gate diagnostics distinguish timeout, valid block, missing reroute, penetration and lost
  order. Every member now logs id, position, slot target, state and reason.

Relevant regressions all pass:

* `--ai-squad-test --only j_near_far,k_persist`
* `--ai-strat-test --only j_persist,k_near`
* `--ai-war-test --only m_save,m_move,m_march`

The AI-war parity checks complete near and far movement in open, forest and slope corridors. Near/far
time ratios are 0.97-1.02 for the measured single-squad and three-squad marches. An earlier combined
AI-squad run had one unrelated, known geometry-dependent player Suppress assertion: the command was
correctly refused because that random setup had no in-range line-of-fire post. Its navigation, tier and
persist scenarios passed, and the scoped final regression is green.

### Visual verification

A non-headless Vulkan run at 1600x900 captured and was manually inspected for:

1. a near squad moving around `barracks_block`;
2. a near squad aligned on the valid open fence gate;
3. all eight far-simulated members physically promoted in their wedge without a position jump;
4. one member temporarily held behind the moving squad, then resuming its preserved order.

No soldier was seen clipping through a wall/building, no abrupt jump was observed, and the wedge/slot
layout remained coherent. The temporary images were written below `user://navigation_n1/screenshots/`
and are not tracked project assets.

## D. Performance

The open far-gate run performs one successful local search and seven safe cache hits. Across final runs
that search took about 23-25 ms (23.02-24.92 ms mean, 23.77-24.92 ms maximum). It is scheduled as the
single allowed local search for that physics tick instead of eight simultaneous searches. No recovery
searches are performed once all members make progress.

The closed far perimeter exhausts bounded attempts and terminates blocked; it does not continue planning
for the remaining simulation. The per-member watchdog permits one squad-level recovery per member.

The focused post-change CPU sample records 6.90 ms average frame time, 7.27 ms p95, 7.68 ms p99 and
7.95 ms maximum. `WorldSim`'s abstract bucket averages 182.0 us/tick versus the N1 baseline's 126.1 us;
the total frame average is unchanged at 6.90 ms and the measured maximum is slightly below the 8.07 ms
baseline. The AI-war movement and march regressions also pass. No material CPU regression was observed.

## E. Remaining work

The following belongs to N1-B/N1-C or later and was not started:

* migrate or further harden vehicle endpoint/bypass planning only with dedicated vehicle regression;
* persistent bridge entities, dynamic bridge enable/disable, width, load and convoy capacity;
* vegetation/soft-terrain cost and measured tree/rock collision clearance;
* explicit tracked-vehicle profiles, pivot behavior and tracked assets;
* dirty-region/versioned cache invalidation for world edits beyond collision-time validation;
* service-point and base-yard approach validation.

Godot still emits the pre-existing shutdown RID/ObjectDB leak diagnostics and navmesh voxel-rounding
warnings in automated runs. They did not produce scenario failures and are outside N1-A.
