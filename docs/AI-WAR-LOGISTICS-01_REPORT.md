# AI-WAR-LOGISTICS-01 report — autonomous warfare with bases, economy, transport and a verified road network

Branch `feature/ai-war-logistics-01`, built on `feature/ai-combat-strat-01` @ `64cb170`. Godot 4.7.2, one persistent world.
Evidence tags: **[CODE]** read from the implementation, **[TEST]** measured by a scripted scenario in the running game,
**[VISUAL]** seen with the real RTS camera, **[LIMIT]** known gap.

## 1. Summary

The AI factions now run the whole loop in the same persistent 3D world as the player: they own a base, earn income, recruit,
acquire vehicles, load squads into trucks and APCs, drive them as convoys over the road network, unload, attack, resupply
during the operation, counterattack when a base or garrison is threatened, recover afterwards and decide the next step
with a scorer that knows what the logistics can deliver. The player keeps full authority (a player order or a player-driven
vehicle always wins; nothing of the player's is ever seized).

Two defects that blocked this loop were found and fixed on the way:

* **Near/far movement speed** — soldiers in the physics tier stood still where the abstract tier walked (3-4x slower).
* **The road network** — it had 35 disconnected components, vehicles could not leave their own bases, and a vehicle that met
  an obstacle stopped for good. See section 11.

What is *not* finished is listed in section 17 (most importantly: no repeated full-war performance run after the last road
and yard changes, the visual validation of boarding/convoys is partial, and one dock approach clips a neighbouring building).

## 2. The original problems, diagnosed [TEST]

| Problem | Finding |
|---|---|
| Near-tier squads 3-4x slower than far-tier squads | `SoldierBody` lost its direction whenever the navigation agent returned the same next point and its stuck check only ran while reacting. The abstract tier also had no friction, so it was too fast in the other direction. |
| AI could not recruit or supply | No AI faction had a base, barracks or income. |
| Vehicles never used by AI operations | No stage existed between "squad ordered" and "squad walking"; transport was player-only. |
| Trucks stopped at the first obstacle | The router disabled road vertices that structures blocked, which cut the graph; `VehicleSim` only stopped and reversed. |
| Bases unusable | The first AI compound put buildings across each other's yards, parking spots inside buildings and the HQ's HESCO perimeter across the road out. |

## 3. Architecture decisions [CODE]

No second manager or second route graph was added. New pieces plug into the existing owners:

* `WarSim` owns the new `WarEconomy`, `AiBases`, `OpTransport` (mechanised stages) and `WarLogistics` (supply during operations).
* `OperationState.Stage` got negative values for the transport stages (ASSEMBLE, MOUNT, TRANSIT, DISEMBARK) so every existing
  `stage >= APPROACH` test is unchanged; the old stages run after DISEMBARK exactly as before.
* Authority order stays Player > Operation > Squad tactic > Reaction. A squad released to the player leaves its operation and
  the transport planner, a player-driven vehicle is never reassigned.
* Supplies change hands only through `Inventory.transfer`; `add` and `take` are explicit sources/sinks that book into the
  faction ledger. `Inventory.audit` counts them, so "nothing is created" is a test, not a belief.
* Routing stays `VehicleRouter` (AStar3D over `RoadNetwork`); audit, overlay and bypass all read that same graph.

## 4. Movement-speed parity [CODE][TEST]

`SoldierBody` keeps the last distinct direction, re-queries the target when the agent has none and runs the stuck check
whenever a MOVE order is active. `WorldSim._abstract_step` uses `abstract_friction = 0.93`. Scenario M (near vs far over the
same route, saved/loaded in the middle) went from a 3-4x gap to a mean ratio of about 1.4x; the remainder is end-of-leg crowding
where physics bodies block each other, which the abstract tier does not model.

## 5. Bases and economy [CODE][TEST A, B, H]

* `AiBases` builds the starting compound (vehicle depot, supply depot, fuel point, HQ, barracks, ammunition magazine) with
  the normal construction system, so it is real cover, real navigation obstacle and capturable. The rear row of buildings
  stands 60 m behind the front row so each building's dock yard is free; the compound is placed only where no wall or other
  structure crosses it, its yard or the lane to the road (`_walled`).
* Income is explicit and inspectable: `WarEconomy` books every `Inventory.add` in `FactionState.ledger`; the audit identity
  `added - refunded == income ledger` held exactly in scenarios H and O. A faction with no ammunition cannot recruit and says why.
* Later construction (forward depot, second barracks, field defences) is paid from the main base's supplies and queued with a
  build time; it is limited, cooldown-guarded and refused with a reason when there is no site.
* Capturing a base transfers it (`BaseSim.capture_base`); a faction that loses its main base is handled in scenario J.

## 6. Recruitment and vehicle acquisition [TEST B, C]

Barracks recruit squads from the reserve against supplies, at most two at a time; refusals carry a reason ("not a barracks",
"no personnel left", "not enough supplies"). Vehicles are taken from a vehicle depot's stock (a truck or APC leaves the stock
and a unit appears at the depot), never conjured; "No Wheeled APC 8x8 left at this depot" is the checked refusal.

## 7. Mechanised operations and convoys [CODE][TEST D, E]

`OpTransport.plan` decides per operation: far enough and vehicles available means mechanised, otherwise a foot march with the
reason recorded. The stages are ASSEMBLE (vehicles drive to an assembly point snapped to a road at least 150 m outside the
compound, departures staggered by `DEPART_GAP_S`), MOUNT (the existing `VehicleTransport` boarding phases), TRANSIT (a convoy
of two or more through `VehicleConvoy`), DISEMBARK at a point chosen against the operation's staging position, then the
normal APPROACH/DEPLOY. Every failure has a fallback: a vehicle that cannot be loaded, cannot route or is lost makes its squads
walk (`_to_foot`), a vehicle that is no longer needed goes home. Scenario D (4.3 km, one operation) and E (3 squads in 3 trucks
over 5.7-7.8 km) pass with all soldiers off the vehicles, the vehicle count unchanged and no transport invariant broken.

Found by the regression run: a follower's stopping place on the leader's route could be undrivable, so no convoy formed and the
trucks drove singly. `VehicleConvoy` now falls back to the destination for that member, and `OpTransport` logs why a convoy was
not formed. A 1-minute test (`r_convoy`) now covers it.

## 8. Readiness and resupply [TEST F, G, H]

`WarLogistics.assess_attack` returns go / delay / reduced / cancel with the numbers. F: undersupplied squads are sent to the
depot, the depot's stock falls by exactly what the soldiers take (conservation checked in rounds), then the attack is "go".
G: a truck takes ammunition from the main depot to garrison squads 3 km away, the squad takes it, the truck brings the rest back;
a save/load in the middle does not change the outcome. H: with no ammunition anywhere nothing is created, the attack is
cancelled with the shortage, recruiting is refused and the faction keeps deciding. Supply routes are pre-checked and delivery
points are road-snapped, with cooldowns so a faction does not retry an impossible restock every tick.

## 9. Defence and counterattack [CODE][TEST I, J]

A threatened base or garrison triggers `OperationState.Type.COUNTER`: nearby squads attack/flank the contact with the existing
`SquadTactics`, with thresholds so a counterattack is not launched against overwhelming force; scenario J covers the loss of a
base and the follow-up.

## 10. Strategic scorer [CODE]

`StrategicDecision` scores attack, counter and economy actions with logistics terms: distance by road, available vehicles,
supply readiness, recovering squads (`recover_site >= 0` counts as recovering) and a transported-force estimate. Notes and the
chosen action are kept per decision for the inspector.

## 11. Road network audit and vehicle navigation [CODE][TEST][VISUAL]

### 11.1 Tool

`RoadAudit` (`scripts/vehicles/road_audit.gd`) reads the router's own graph; nothing in it names a place. It reports nodes,
edges, connected components, isolated roads, near misses between networks, crossings without a junction, geometry (zero-length,
NaN, steep, tight turns), the location list (objectives, bases, docks, settlements from `sites.json`, bridges), per-location
road entry and a sample of routes between all kinds of places with the reason for every failure.

```
Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --road-audit
```

It writes `benchmarks/raw/road_audit.json`. It works for new or edited roads without manual rebuilds because it rebuilds from the
router; `RoadAudit.intentional` maps road/location names to a reason when isolation is deliberate (unexplained entries are the
ones to look at). The overlay (`RoadAuditOverlay`, F8 in the game or `--road-overlay`) draws the main network dim green, other
components orange, repaired gaps cyan, near misses red and unreachable places magenta, and prints the same summary.

### 11.2 Findings on the 20 km world [TEST]

| | Before | After |
|---|---|---|
| Connected components | 35 | 18 (main network = 99.2 % of the 30 300 nodes, 299.7 km) |
| Isolated roads (a component of one road) | 34 | 17 (village streets, e.g. Sentrum gate 21, Verket gate 2, Elvetun gate 1) |
| Near misses between networks | 55 | 16 |
| Routes that failed in the audit sample | 922 of 2564 | 102 of 2564 (2462 planned) |
| Locations with no road entry | many | 0 of 56 |
| Tight turns (< 9 m radius) | | 1 (Fv øst nord-sør, 7.2 m) |
| Steep segments, NaN points, zero-length segments | | 0 / 0 / 0 |

The 102 remaining failures are all to **Kvernes** (steep bank, the end leg cannot be driven) and the unenterable village streets of
**Elvetun**; they are tagged isolated by terrain and make the autonomous operations fall back to a foot march. North HQ to East HQ
(26.8 km, bridges and junctions) plans and drives.

### 11.3 Corrections [CODE]

* **Gap repair** (graph only, meshes unchanged): road ends within 32 m (4 m height) of another road are linked, 49 repairs.
* **Blocked road vertices are bridged, not disabled**: a stretch of road that a structure blocks becomes a short cross-country
  leg in the route (`_road_path` returns `{ids, gaps}`), so a building on a road no longer splits the graph.
* **Entry candidates are component-aware**, with a fail cache (90 s) so a hopeless destination is not re-planned every call.
* **Right-hand lane**: roads at least 6 m wide are driven 1.9 m right of the centre line (oncoming traffic).
* **Off-road is allowed**: `offroad_factor` per vehicle (truck 3.0, APC 1.7), APC off-road speed 9 m/s and grade limit 0.55; the
  planner picks the cross-country way when it is cheaper for the vehicle.
* **Obstacle bypass at run time**: a vehicle held up by a building, wall or parked vehicle plans a local detour (3 m grid that knows
  footprints, slopes, water and parked vehicles), splices it into its route and rejoins at least 35 m ahead. Each failed detour
  clears the obstacle by 1.6 m more. Recovery alternates: reverse straight back, then turn towards the route (a three-point turn
  when the nose points into a wall), then a detour from the freed position, then reverse again, then replan.
* **Yards**: AI compounds are spread so docks have clear approaches; `LogisticsSim.parking_world` returns the first validated free
  spot (outside every structure footprint, on drivable ground); the sandbox's HQ HESCO perimeters (the baseline's 56 m squares)
  are now open where a road crosses them, otherwise the roads out of the East HQ led into a wall.

### 11.4 Real-vehicle verification [TEST][VISUAL]

Not only the graph: trucks and APCs were driven in the running sim, with the physical body where the camera was close.

| Test | What it drives | Result |
|---|---|---|
| `r_yard` | truck from its depot parking spot out of the yard to a road point ~400 m away, physical body, camera on it | arrives, 40 s |
| `r_drive` | truck from the depot to South Bridge (8.4 km), Sentrum (7.8 km) and the East depot (20 km), then back to its own depot | the three outbound trips arrive; the return stops 47 m short because the dock is occupied by the two parked trucks (the stop-behind-another-vehicle rule) |
| `r_obstacles` | a parked truck in the lane, a building built on the route | goes round both and rejoins |
| `r_exit` | a truck teleported onto each of the 24 docks and parking spots of both AI bases, driven ~600 m out and back | 23 of 24; the remaining one (East fuel point dock) clips the corner of a neighbouring building on the way back |
| `r_gaps` | across repaired gaps | passes |
| `r_lanes`, `r_offroad` | lane offset, APC vs truck routes | pass |
| `r_convoy` | three trucks as a convoy to 2.5, 4.0 and 5.5 km | forms, all drive (about 1 minute) |
| `r_overlay` | the overlay on the real world | builds in 0.65 s: 124 roads, 18 components, 49 gaps, 16 near misses, 1 place not on the main network (Haugen village) |

Screenshots of the stuck vehicles drove three of the fixes: trucks stopped at a HESCO wall that crossed the road (nobody had
placed a gate), trucks standing nose-on to a building face between two parked trucks (reversing on full lock does not move
them, so the first reverse is now straight), and trucks cutting the corner of a building they were routed round (so the detour
clearance grows and the rejoin point is at least 35 m on).

## 12. Observability [CODE]

`WarSim.explain_faction` and `summary` list per faction: bases, stocks, income and spending, queued orders, recruitment,
vehicles by state, transport plans and the reason a plan was foot or vehicle; the operation text shows stage, vehicles,
readiness and supply reasons; `OpTransport` writes failure diagnostics (`diag`, structures near) into the task. The road
overlay is the debug visualisation for routing. A dedicated faction logistics panel and per-operation route/convoy overlays
were **not** built (section 17).

## 13. Scenarios [TEST]

`--ai-war-test [--shots] [--only a_init,...]`: A init, B recruit, C vehicle, D mechanised, E convoy, F pre-operation supply,
G delivery, H shortage, I counterattack, J base loss, L player authority, M move parity, N long operation, O full war (with
audit identity), plus the road scenarios of section 11.4. A to O passed in the runs made while building the milestone; after the
last road/yard changes A to E and the road scenarios above were repeated, F to O were not (see 14).

## 14. Regression tests chosen by change impact [TEST]

The last commits changed `VehicleSim`/`VehicleRouter` recovery, `VehicleConvoy`, base layout, sandbox HQ perimeters and
`OpTransport` logging, so the checks repeated after them were:

* `--ai-war-test --only a_init,b_recruit,c_vehicle,d_mech,e_convoy` (found the convoy fallback defect, fixed, then D+E re-run green)
* `--ai-war-test --only r_yard,r_obstacles,r_convoy,r_overlay` and `r_exit` (section 11.4)
* `--logistics-test --only transport,convoy` (existing vehicle/convoy owners) — see the result in the final message.

Not re-run: the AI-strat, AI-squad and sandbox suites (no change to their owners except the sandbox HQ perimeters, which only
open a gap where a road crosses; the next full-suite run should be the milestone's single justified one).

## 15. Performance [TEST][LIMIT]

* Road audit plan time: the worst single plan measured 1257 ms before the fail cache existed (`plan_ms_max` in
  `benchmarks/raw/road_audit.json`); it was not re-measured afterwards.
* `VehicleRouter` graph rebuild after construction: about 130 ms spike (seen as `mech_orders` in the profile). Not fixed.
* Overlay build 0.65 s, only when toggled.
* A full-war frame-time run (scenario O's perf section) was made before the road changes; it was not repeated after them.

## 16. Visual validation [VISUAL][LIMIT]

With the real RTS camera: trucks at the base docks and in the yard (before and after the wall, parking and layout fixes), a truck
stuck against the HESCO perimeter, a truck wedged against a building in a forest, the overlay (`docs/ai_war01/aw01_road_overlay.jpg`).
The boarding/disembark sequence and a convoy on a long road were checked through the scenario logs and invariants, not yet with a
sequence of screenshots.

## 17. Limitations [LIMIT]

* The cross-country planner ignores trees and rocks; a physical body can stop on them (R1 on a route that was 55 % cross-country
  ended 37 m short).
* The generated road meshes still show some visual gaps; the repairs are graph-level only.
* Kvernes (steep bank) and Elvetun are not enterable by a truck; operations there fall back to foot.
* One of 24 dock/parking spots (East fuel point dock) clips a neighbouring building on the way back; the return to a dock that
  other trucks occupy ends at the stop-behind-another-vehicle rule 47 m short.
* The graph rebuild after construction costs ~130 ms.
* No dedicated logistics inspector panel, route/convoy debug overlays or visual sequence of boarding; no new Blender assets.
* `RoadAudit.intentional` is not populated from world data; 17 village streets are reported as unexplained isolated roads.
* No repeated full performance run after the final road changes.

## 18. Next milestone and how to run

Next: AI-AIR-01 or a pass on the faction logistics inspector, route overlays and a final full-war performance run.

```
--ai-war-test [--shots] [--only a_init,b_recruit,c_vehicle,d_mech,e_convoy,f_preop,g_delivery,h_shortage,i_counter,j_base_loss,l_player,m_move,n_long,o_war]
--ai-war-test --only r_yard,r_obstacles,r_convoy,r_overlay,r_exit,r_drive,r_gaps,r_lanes,r_offroad
--road-audit            # writes benchmarks/raw/road_audit.json
--road-overlay          # or F8 in the game
```
