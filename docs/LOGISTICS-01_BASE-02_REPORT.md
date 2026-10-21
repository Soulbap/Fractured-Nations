# LOGISTICS-01 / BASE-02 — functional vehicles, transport, supplies and bases

Branch `feature/logistics-01-base-02` (worktree `../fractured-nations-logistics01`), created from
`feature/world-integration-03` (21e846a). Not merged into `main`. The plan written before the code
is [docs/logistics01/LOGISTICS_PLAN.md](logistics01/LOGISTICS_PLAN.md); screenshots are in
`docs/logistics01/lg_*.jpg`.

Status tags: **[VERIFIED]** by `--logistics-test` (or another scripted run) in the real game,
**[INSPECTED]** looked at in screenshots, **[LIMIT]** a known limitation.

## 1. What the player can do now

The Section 24 scenario runs through the real controls **[VERIFIED]** (`--logistics-test --only scenario`,
about 7 minutes real time): build a base with the construction tool (HQ, barracks, supply depot,
vehicle depot, fence, yard, road to the world network) → click the barracks, press *Recruit a squad*
→ click the vehicle depot, press *Acquire truck* and *Acquire APC* → select squad + APC, **T** boards
8 soldiers → select truck + supply depot, press *Load the vehicle here* (3 808 kg ammunition) → select
both vehicles, **RMB** at a point 15.8 km away over a bridge = a convoy → follow it on the strategic map
(vehicles, base, route) and jump back with **G** → **P** takes the truck's wheel, **Tab** gives it back and
the convoy resumes → the camera leaves, the convoy arrives in the abstract tier → **U** disembarks the squad,
which secures the area → build a forward supply depot, a guard tower and sandbags with the construction tool
(groundwork on the real slope) → select truck + new depot, *Unload it here* → select the squad + depot,
*Resupply the selected squads here* (720 rounds, 144 kg out of the forward depot) → the infantry leave on another
mission while vehicles and supplies stay → F5 / F9 restores every inventory, base and vehicle.

### Controls added

| Key / action | Effect |
|---|---|
| RMB with vehicles selected | Drive there by road; two or more vehicles farther than 600 m away form a convoy |
| RMB on a friendly vehicle with squads selected | The squads board it |
| Squads + vehicles selected, RMB on the ground | Combined transport order (board, drive, set down) |
| T / U | Selected squads board the selected vehicle / passengers get out (U also cancels a boarding) |
| P, Enter or double-click on a vehicle | Take the wheel (third-person chase camera, **V** bumper view, RMB-drag look, wheel zoom) |
| W / S, A / D, Space | Throttle and brake-reverse, steering, handbrake |
| Tab | Leave the vehicle; its order and route resume |
| Click a building (RTS) | Selects the facility: the logistics panel shows base, inventory, queue and orders |
| H | Stop the selected vehicles (and cancel their job) |
| Map: click / box | Selects vehicles and facilities too; RMB orders vehicles (squads + vehicles = transport); G jumps to them |

## 2. Architecture decisions

### Reused, extended

| Existing system | What was added |
|---|---|
| `UnitState` (one record per soldier or vehicle) | `veh: VehicleState` (vehicles), `vehicle_id` (soldier aboard), `resupply_src` |
| `WorldSim` tick | Vehicles are advanced here for *every* record, body or not; soldiers aboard are skipped by the abstract step, `CombatBrain` and `SquadControl` |
| `VehicleBody` | Now a pure presentation of the record (wheels, suspension, collider, route probe); `UnitProxy` draws the LOD2 hull |
| `RoadNetwork` | Unchanged and still the only road definition; `VehicleRouter` is a derived AStar3D index over its vertices (junction links, bridges are ordinary vertices, built roads added/removed on `changed`) |
| `StrategicRoutes` | Cross-country legs longer than 150 m reuse its grid |
| `StructureManager` | `blocks_point` (collision), `is_wet` (new, public), `area_changed` (router re-enables vertices) |
| `StructureState` / `ConstructionState` | `inventory`, `base_id`, `label`, `facility` on the structure; `bases` in the construction JSON (format 3) |
| `GameController` | `Mode.DRIVE` through the existing possess / camera path |
| Save / load | Vehicles, cargo, jobs, convoys, rules in `world.json`; inventories, queues and bases in `construction.json` (F5 / F9 write both) |

### New classes (and why existing ones could not own them)

`VehicleState` / `VehicleDefs` (data), `VehicleSim` (movement + orders; `WorldSim` is infantry-only straight-line
travel), `VehicleRouter` (graph search; `RoadNetwork` has no search structure), `VehicleTransport`, `VehicleConvoy`,
`VehicleVisual`, `DriveCamera`, `Inventory` (the one supply model), `FacilityDefs` (table of what buildings do, so the
structure catalog stays pure construction data), `LogisticsState`, `LogisticsSim` (jobs, resupply), `BaseSim`
(bases, recruiting, acquisition, rules), `LogisticsPanel`. All are plain objects owned by `WorldSim` / `WorldState`;
none has a loop of its own. No second road graph, vehicle simulation or inventory exists.

### Authoritative data

| Fact | Owner |
|---|---|
| Vehicle position, yaw, health, faction, order | `UnitState` |
| Type, speed, steer, fuel, odometer, route + progress, status / reason, occupants, pending boarders, cargo, convoy, job | `UnitState.veh` |
| Soldier aboard | `UnitState.vehicle_id` + `VehicleState.occupants` (changed together only by `VehicleTransport`) |
| Supplies | `Inventory` on depots (`StructureState.inventory`) and vehicles (`VehicleState.cargo`); `Inventory.transfer` is the only way supplies change hands |
| Facility queues / vehicle stock | `StructureState.facility` |
| Bases | `ConstructionState.bases` + `StructureState.base_id` |
| Convoys, automation rules | `WorldState.logistics` |

## 3. Vehicles

### Assets
The Blender builder (`tools/blender/asset_production/fam_vehicles.py`, `BODY_WHEELS = False`) exports the truck and
APC without their integrated wheels (truck LOD0 4 104 → 1 128 triangles, APC 976). `VehicleVisual` instances
`wheel_truck` / `wheel_apc` at the `WHEEL_*` markers, spins them from speed, steers the front axle(s) (truck axle 1,
APC axles 1 and 2 at 55 %), takes LOD ranges 0–40 / 40–160 / 160–1 500 m, paints the hull per faction
(`Paint_Green` / `Tan` / `Grey`) and rides the ground: body pitch and roll from four wheel samples (terrain or bridge deck),
wheel travel ±0.22 m **[INSPECTED]** (`lg_03*`, `lg_04`). Measured: wheel centres 0.55–0.72 m over the ground
(radius 0.60 / 0.625 m), hull offset 0.0 m.

### Movement model
One kinematic bicycle model for both tiers (`VehicleSim._integrate`): wheelbase 4.4 m (truck) / 3.65 m (APC), steering rate
0.9 rad/s, max steer 0.55 / 0.50 rad, 22–25 m/s on roads, 7 m/s cross-country, acceleration 1.6–1.9 m/s², braking 4.5–5 m/s².
Height from terrain or bridge deck. Hard stops, no teleporting: a footprint (three collision circles) may not enter a
structure, the water, the map edge, and for the player's vehicle or when reversing, another vehicle.

### AI driving
* **Router.** 30 303 graph vertices (132 ms once, on first use), plans in 20–35 ms (max 156 ms). Candidates: cross-country
  all the way, or up to three road vertices at each end; road cost uses class weights, grade penalty (steeper than 10 %)
  and a width penalty; vertices inside structures are switched off (a wall across a road closes it) and re-enabled when
  structures change. Cross-country legs are straight if `line_ok` (slope ≤ 40 %, no water, no structure, no parked vehicle),
  else A* on a local 3 m grid, else the 50 m grid. Destinations in structures or water are refused with a reason.
* **Route → speed profile.** Catmull-Rom resample to 3 m, speed ceiling per point from the road class
  (primary 22 … track 8 m/s; built roads 9), curvature limit `sqrt(lat_acc · R)` (2.2–2.6 m/s²) and a backward braking pass
  (2 m/s²) including the end of the route.
* **Local driving.** Pure pursuit (look-ahead 6–22 m), cross-track slow-down, gap logic (route points ahead against
  structures, vehicles in the lane and a near-field circle test), a physics probe of the body (trees, soldiers) while near the
  camera. Stuck detection: 5 s without 1.5 m of progress → reverse 3.5 s ×2 → re-plan ×2 → "Path blocked: could not get free",
  or counted as arrived when it is within 45 m of the end behind a stopped vehicle. Out of fuel, blocked, unreachable and
  insufficient-fuel orders all end with a message (HUD, map, war log).
* **Tiers.** Camera far = no body, the same record and the same code; promotion / demotion never touch route, destination,
  cargo or passengers. `probe_ahead` is reset when there is no body.

## 4. Infantry transport

`VehicleTransport`: `order_transport` (squad + vehicle + optional destination), phases APPROACH → BOARDING → TRANSIT →
UNLOADING. Soldiers walk to the rear door with ordinary Move orders and board within 5 m; the vehicle waits ("boarding 6/8").
Capacity: truck 12, APC 8 (seats reserved when ordered; a second squad gets the rest, the others are reported as left behind).
Aboard: no body, no proxy, not in the combat brain's grid, position follows the vehicle. Disembark: spots behind the vehicle
checked against structures, water and other vehicles (min. 0.8 m apart), the squad regroups there. Cancel, redirect (a Move order
on a vehicle in transit changes the destination, one while boarding departs at once), disassign (U) and vehicle destruction
(passengers get out, cargo stays in the wreck) are supported.

## 5. Supplies, depots, convoys

* **Types:** ammunition (kg; 1 kg = 5 spare rounds), fuel (l), general supplies (kg). Truck cargo 10 000, APC 800.
* **Depots** (`FacilityDefs`): HQ 6 000, barracks 1 500, supply depot 60 000, vehicle depot 8 000, ammunition magazine (ammo only),
  fuel point and bladder (fuel only), container yard, storage. The first supply depot of the player's faction starts with the
  scenario stockpile (4 000 kg ammunition, 6 000 l fuel, 9 000 kg supplies); every other depot starts empty.
* **Jobs** (`LogisticsSim`): load, unload, delivery (load → drive → unload, optional repeat), refuel, repair. The vehicle drives to the
  depot's dock (in front of the building, sideways slots, retries while the dock is occupied), works for `4 s + qty / 250`, transfers,
  then clears the dock. Cancelling leaves the cargo aboard. Refusals: no stock, cargo full ("Cargo full (10000/10000)"), unknown depot,
  unreachable dock, insufficient fuel for the route ("the route needs 20 l, the tank has 3 l").
* **Resupply:** soldiers ordered to a depot or truck refill spare rounds from its inventory when they arrive (26 m / 14 m).
* **Convoys:** `order_convoy` plans every member's own route (the same router), stacks the stopped column 18 m apart, staggers departures,
  matches a follower's speed to the vehicle ahead inside 55 m, slows the leader when the rear is 150 m behind and stops it at 300 m
  (a straggler is given up after 60 s and drives on alone). A member given another order leaves the convoy; the player can drive any member.

## 6. Bases and facilities

A base is a name for facilities within 220 m (`ConstructionState.bases`, `StructureState.base_id`); "Main base" = has an HQ, "Outpost" = fewer
than three kinds of facility. No tiers, no required buildings, no layout. Functions:

| Facility | Function |
|---|---|
| Barracks | *Recruit squad*: 320 kg supplies + 192 kg ammunition from the base's stores, 8 reserve personnel, 60 s → `WarSim.spawn_squad` (faction loadout, rifle, 120 rounds) |
| Vehicle depot | *Acquire* truck (600 kg supplies + 150 l fuel, 30 s, stock 3) or APC (1 500 + 200, 45 s, stock 2); repair (0.5 kg supplies per condition point) |
| Supply depot, magazine, fuel point, storage | Store, receive deliveries, load, refuel, resupply |
| HQ | Names and anchors the main base, holds a small inventory |
| Optional automation | Restock rule (keep depot X above N by sending truck T from depot Y) and refuel rule; visible, switchable, and paused for 3 minutes when the player gives the vehicle an order |

Expansions (ranges, repair bays, fuel points, mast) remain free-standing placeable structures; only the ones with a real effect (fuel point / magazine
storage, repair bay) have mechanics. [LIMIT] Training installations have none yet.

## 7. Validation (`--logistics-test`, results in `benchmarks/raw/logistics_test.json`)

Change-impact testing; the full suite was not run. Real route used throughout: base → 15.7 km of world road (Gravel road #45 → Lv nordvik …
Fv sentrum-øst) with one bridge, the first 203 m on the player-built gravel road to the world network. All scenarios below PASS **[VERIFIED]**.

| Check | Result |
|---|---|
| `veh_route` | graph 30 303 nodes, 135 ms; 18.6 km truck and APC routes, 1 bridge, 20 ms; a destination in the river refused |
| `veh_drive` (truck and APC) | out through the base entrance, 15.7 km, back into the yard; 0 teleports, 0 samples in a structure, 0 in water, ≤ 0.83 rad/s yaw rate, ≤ 22 m/s, 397 samples on the bridge deck |
| `veh_player` | take the wheel mid-route, 16.2 m/s after 8 s, handbrake stop, reverse; order and route kept; Tab resumes it and it arrives (0 teleports) |
| `veh_tiers` | body → proxy → body, 3 tier changes, 0 teleports, arrives |
| `veh_persist` | position, yaw, speed, fuel, route (6 297 points), progress, order identical after load; the journey finishes |
| `transport` | 16 soldiers, truck 12 / APC 8, boarded in 2.7 s, 15.7 km over the bridge, redirect, tier change and save / load with soldiers aboard (0 duplicates, 0 with a view, 0 link mismatches), disembark 0 bad spots, min. 0.8 m apart, 14 of 16 reach a 60 m order, soldier records unchanged |
| `transport_cancel` | cancel while boarding, reassign to the APC (8 seats), a ninth soldier refused, passengers out in transit |
| `logistics` | conservation: max error 0.00 kg ammunition / supplies / fuel over 71 470 samples, no negative or over-capacity inventory; short stock (9 000 of 50 000 asked), cargo full, dry depot, insufficient fuel, unreachable depot, cancel on the road, refuel, resupply (800 rounds = 160 kg) |
| `convoy` | three vehicles, speeds matched (50 km/h), leader waited for a dry rear vehicle, takeover and resume inside the convoy, column stopped 14–16 m apart, cargo unloaded, supplies conserved |
| `bases` | grouping (main base + outpost), recruit with cost, refund, 8 equipped soldiers, no supplies refused, acquire truck / APC, stock limit, repair, destroyed vehicle (passengers out, cargo kept), automation rule sends the truck, override pauses it |
| `persist_logistics` | stores, vehicles (cargo, job, route, occupants, convoy), bases, rules, queues identical after F5 / F9; the operation continues |
| `scenario` | Section 24 end to end (above) |

Regression of shared systems: `--large-test` PASS, `--squad-test` PASS, `--sandbox-test --only persist,characters,navigation` PASS,
`--integration03-test --only base,base_nav,persist` PASS (base layout adjusted, §9), `--playtest-test --only nav_base` PASS, `--base-test` PASS.
`--combat-ai-test` fails its precondition ("no open meadow far from the default soldiers", a site search tied to the old terrain,
not touched by this work).

## 8. Performance (RTX 3070, 1600 x 900, vsync off, 120 soldiers, war AI paused unless stated)

| Situation | avg / p99 / max (ms) | draw calls |
|---|---|---|
| Player driving the truck (chase camera, forest) | 6.51 / 9.7 / 12.3 | 1 962 |
| 6 AI vehicles on the road, RTS | 3.46 / 4.3 / 7.6 | 421 |
| Convoy of 3, RTS | 2.64 / 3.5 / 7.1 | 460 |
| 3 vehicles + 2 squads in the populated base, RTS | 2.18 / 3.3 / 7.8 | 530 |

Vehicle step: 0.33–0.38 ms per physics tick for 20 vehicles (10 driving), 4 % of the tick (0.48–0.54 ms total). Distant vehicles at 1 / 4 / 8 / 16 x:
the requested speed was reached each time. War running with 10 vehicles: 8 x reached, **16 x reached 12.6 x** (CPU limited, as before). No frame over 33 ms
in any case. Router: build 132 ms once, 22 plans averaged 28.5 ms.

## 9. Deviations, limitations

* Test base layout (`integration03_selftest._base`): the east fence ends 14 m from the gate (12 m vehicle entrance: a 3.3 m truck cannot use the 4 m gate), both
  depots face south onto the yard, the sandbag position moved out of the vehicle corridor.
* AI vehicles do not negotiate with each other: in a crowded yard two AI vehicles can clip corners (up to 2.3 m², tolerated by the test at 3 m²) and a
  vehicle behind a stopped one reports "stopped behind another vehicle". Parked vehicles are avoided only by cross-country legs, not on roads. Convoys stagger
  their departure to limit this.
* Trees / rocks are avoided on road routes (cleared) and by the near-tier probe, but the planner does not know them cross-country.
* Infantry weapons cannot damage vehicles yet (no hit volumes); `VehicleSim.apply_damage` is the hook, repair and destruction behaviour are tested through it.
  The APC's remote weapon station is not implemented.
* Soldiers aboard cannot fire; no vehicle interiors, no boarding animation (they walk to the ramp and disappear), disembarked soldiers appear at once.
* Fuel / ammunition rates are configurable game rates, not simulations. Faction stockpile = the first depot; there is no income or production.
* Training installations, shooting ranges and similar expansions are placeable but have no mechanic.
* Strategic map: facilities appear from the operational zoom, built roads from 0.05 px / m; no separate base-management screen (the tactical panel and map text are used).
* Two ways to see a vehicle's order: HUD / panel / map text; there is no on-screen route preview in the tactical view.

## 10. Running

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file lg.log res://scenes/game/world_ref_20km.tscn -- --logistics-test --shots [--only veh_route,veh_drive,veh_player,veh_persist,veh_tiers,veh_shots,veh_look,transport,transport_cancel,logistics,convoy,bases,persist_logistics,scenario,perf_logistics,depot_exit]
```
