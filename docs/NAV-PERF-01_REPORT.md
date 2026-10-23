# NAV-PERF-01 — baseline and investigation (in progress)

Date: 2026-10-23. Baseline: `ea04c49`, branch `develop`, Godot 4.7.2, `ref_20km`.

**NAV-PERF-01 status: incomplete.** The 01A changes below retain synchronous planning; the principal frame-time problem remains. This is not the full NAV-PERF-01 acceptance report.

## Measured baseline

`--headless --navigation-n1c1-perf --tag=navperf_baseline` on the unmodified baseline. The harness reports synchronous wall time for planning and bursts, not rendered frame time or FPS. Small sample sizes make p95/p99 descriptive only. The run exited with Godot resource/RID leak messages after printing its result; its `failures` array was empty. Full output is in the local ignored `navperf-baseline.log`.

| Workload | Average ms | p95 ms | p99 ms | Maximum ms | n |
|---|---:|---:|---:|---:|---:|
| Verket to South Bridge, warm, router caches cleared | 75.93 | 94.60 | 94.60 | 94.60 | 5 |
| Dense woods APC, warm, router caches cleared | 202.53 | 282.65 | 282.65 | 282.65 | 5 |
| 24 objective pairs, warm, router caches cleared | 49.82 | 146.23 | 243.59 | 243.59 | 24 |
| 24 objective pairs, first pass | 37.03 | 146.89 | 168.15 | 168.15 | 24 |
| Three orders in one measured burst | 161.57 | 402.52 | 402.52 | 402.52 | 6 |
| Individual plans in those bursts | 49.09 | 270.24 | 270.24 | 270.24 | 18 |

Verket cold: 67.96 ms; immediate cached repeat: 0.143 ms. Dense woods cold: 465.21 ms, with 51,850 local grid cells across four local calls; local work 330.9 ms, assembly 129.5 ms. These counters are nested and must not be summed blindly. The last warm Verket profile recorded 25 road A* calls (4.8 ms), local planning 10.1 ms, and assembly 20.1 ms. Across 24 warm plans the profile recorded 730 road A* calls (331 ms), local planning 118.6 ms, line checks 224.9 ms and assembly 230 ms. These are aggregate counters, with overlapping categories.

After a structure placement the far-away route remained a cache hit (0.01 ms); six crossing plans took 1.8, 2.3, 19.6, 47.6, 3.5 and 2.0 ms. The harness reports 6/6 infantry at the bridge-crossing goal. This does not establish the other requested acceptance criteria.

## Findings and constraints

* `VehicleSim.order_drive` calls `VehicleRouter.plan` synchronously; bridge replanning and recovery also call it synchronously. A queue of one request per tick does not bound the cost of one request.
* Vehicle planning combines road A*, local-grid preparation and A*, line checks, candidate evaluation and assembly. The local grid can contain up to 60,000 cells; Godot's `get_id_path` is a single synchronous call. Budgeting only between requests or only between candidates cannot guarantee a frame budget.
* Infantry local planning likewise builds a grid synchronously and validates the resulting path against the walker's step test, including repairs. The validation must remain in place and must itself be budgeted if made incremental.
* Convoy formation reads the leader's completed route immediately, while transport, logistics and operations branch on immediate success/failure. Several operation and logistics sites call `router.plan` directly for feasibility. A pending state requires explicit handling at these call sites and persistence/cancellation semantics, not merely a deferred `order_drive`.
* Bridge, road and structure changes invalidate caches and existing paths. In-flight requests need an appropriate world revision and restart/revalidation; a replaced order, removed unit or load must not accept an obsolete result. Existing router fields such as parked circles and bridge context are mutable per-plan state, so concurrent incremental requests cannot safely share them without isolation.

## Outstanding work

The full requested baseline (including ten/25 vehicles, mixed troops, concurrent operations, latency and actual rendered frames), incremental implementation, NAVPERF-01–14, wider regressions, and visual terrain inspection have not been completed. The next bounded implementation step is a cancellable, revision-aware planning state with incremental expensive stages and explicit pending handling at every production caller; measure every stage, including validation and assembly. Native synchronous searches and world-data access must be individually bounded or replaced safely before claiming a hard per-frame budget.

The world manifest verification returned `OK: 535 files checked, 0 missing, 0 changed, 0 extra`. No terrain or reference-map edit was made.

## NAV-PERF-01A — local planning optimisation

The synchronous API and existing collision, clearance, water, bridge and infantry walkability checks remain. The vegetation index now visits occupied sub-buckets instead of scanning the whole search rectangle once per vegetation cell. Road candidates in a single synchronous plan share footprint results for identical graph vertices. Candidate construction no longer builds an unused road-point array. No long-lived cache or new order state was introduced. Native road, vehicle-local, strategic and infantry-local A* calls now record their maximum individual wall time.

The same headless N1-C1 performance harness was run before and after. These are small samples, subject to substantial machine-load variation, and are not rendered frame times. The before run adds road and vehicle-local A* timing only; the final run also instruments strategic and infantry-local searches.

| Workload | Instrumented before avg / p95 / p99 / max ms | Final avg / p95 / p99 / max ms |
|---|---|---|
| Verket, warm (5) | 26.93 / 27.79 / 27.79 / 27.79 | 78.22 / 142.16 / 142.16 / 142.16 |
| Woods, APC warm (5) | 127.18 / 129.54 / 129.54 / 129.54 | 221.52 / 238.50 / 238.50 / 238.50 |
| 24 pairs, warm | 44.66 / 176.41 / 209.87 / 209.87 | 40.57 / 163.88 / 175.25 / 175.25 |
| 24 pairs, first pass | 40.05 / 165.67 / 179.63 / 179.63 | 41.50 / 166.82 / 172.13 / 172.13 |
| Burst of three (6) | 163.33 / 400.66 / 400.66 / 400.66 | 151.75 / 369.53 / 369.53 / 369.53 |
| Individual burst plans (18) | 49.19 / 265.97 / 265.97 / 265.97 | 45.90 / 249.47 / 249.47 / 249.47 |

Woods cold was 139.81 ms before and 243.50 ms final; the earlier baseline recorded 465.21 ms. The same 51,850 local cells were examined. An intermediate after run recorded 291.66 ms cold and 272.95 ms warm average; its burst maximum was 1,135.27 ms. These large variations preclude a reliable end-to-end speedup claim. In a paired comparison within the final run, the old and new vegetation-index traversals returned the same collider triples; five warm repetitions averaged 12.49 ms versus 2.49 ms (max 20.74 versus 3.93 ms). This demonstrates a reduction in that isolated workload, not a guarantee for all routes.

Maximum individual native A* calls observed before: road 4.471 ms, local vehicle 0.878 ms. Final: road 40.024 ms, local vehicle 0.786 ms, strategic 0.181 ms. No infantry-local A* call was observed in that final workload; zero is not an upper bound. The intermediate after run saw 46.93 ms in one road call. These timings include scheduling interruptions and are observed maxima, not proven worst-case bounds. Plans remain synchronous, and native searches, local grid construction, line validation and route assembly can still exceed a frame budget; splitting those stages and changing pending-order semantics remain future work.

Targeted headless tests: N1B-04 PASS (APC follows forest route, zero trunk ticks); N1B-06 PASS (blocked route and restoration); N1B-08 PASS (three convoy vehicles arrive); N1C1-02 PASS (closed bridge avoided); N1C1-09 PASS (structure changes and cache invalidation). The performance harness's infantry bridge march reported 6/6 arrivals. Test runs emitted the existing shutdown resource/RID leak diagnostics; no rendered-frame test or visual terrain inspection was performed. These tests do not complete NAV-PERF-01 or prove a 2–4 ms budget.
