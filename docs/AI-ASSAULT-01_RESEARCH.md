# AI-ASSAULT-01 — Research: RTS / FPS combat AI and what FRACTURED NATIONS takes from it

Purpose: decide what to change in the existing chain WarSim / operations → `SquadTactics` → `CombatBrain` so that infantry
attacks work as coordinated units. Short by design. **V** = verified from documentation, source or the developers' own
material; **I** = inferred from observed gameplay or community reverse-engineering.

## 1. Findings per game

### Arma 3 / Arma Reforger (Bohemia Interactive)
- **V** Individual skill is a set of sub-skills (aimingAccuracy, aimingShake, aimingSpeed, spotDistance, spotTime, courage,
  reloadSpeed, commanding), each interpolated through `CfgAISkill`. Accuracy, reaction and spotting are separate knobs, not one
  "difficulty". [CfgAISkill](https://community.bistudio.com/wiki/CfgAISkill), [AI sub-skills](https://arma.fandom.com/zh/wiki/AI_Sub-skills)
- **V** Group *behaviour* (SAFE / AWARE / COMBAT / STEALTH) governs how a group moves, idles and engages; AWARE is the default.
  *Combat mode* (ROE colours) is separate: YELLOW fires at targets in range **while keeping formation**; RED lets members leave
  formation and act individually. Groups go from AWARE to COMBAT on contact. [AI Behaviour](https://community.bistudio.com/wiki/AIBehaviour),
  [Combat Modes](https://community.bistudio.com/wiki/Combat_Modes)
- **V** Reforger's script API has a dedicated suppression behaviour (`SCR_AISuppressBehavior`: a suppression *volume*, a
  duration, a fire rate, a friendly-fire check toggle) — suppression is fire at an *area* that the group believes holds the
  enemy, with a rate, not "shoot until the magazine is empty".
  [SCR_AISuppressBehavior](https://community.bistudio.com/wikidata/external-data/arma-reforger/ArmaReforgerScriptAPIPublic/interfaceSCR__AISuppressBehavior.html)
- **I** (mod authors) Vanilla Arma 3 originally had almost no suppression; LAMBS Danger / TPW EBS added it, with a
  friendly-fire check and group-shared contact suppression. Reforger ships `SCR_AIGetOverwatchMembers` (bounding overwatch) but
  no shipped behaviour tree used it (SilenceAI changelog) — even Bohemia struggled to make fire-and-movement emerge.
  [TPW EBS](https://forums.bohemia.net/forums/topic/152062-tpw-ebs-engine-based-suppression/), [SilenceAI](https://reforger.armaplatform.com/workshop/6A1AA2A95D40BC57-SilenceAI-EnhancedCombat)
- **V** Possession: the player is one unit of a group; the group's waypoints and the other members' FSMs keep running.
  FRACTURED NATIONS already does this (UnitState record, `player_controlled` skipped by `CombatBrain`).

### Company of Heroes (Relic)
- **I** (community measurements, patch notes) Two suppression levels: *suppressed* (slow, lower accuracy) and *pinned* (no
  movement, no fire). Suppression is applied **whether the round hits or not**; cover reduces suppression received (green 0.1,
  yellow 0.5, none 1.0, negative 1.5) and speeds recovery. Cover is directional — a flank bypasses it. Light / heavy cover
  cut the attacker's accuracy by 50 % / 75 %. [CoH2 thread](https://www.coh2.org/topic/97939/title/post/775692),
  [Giant Bomb](https://www.giantbomb.com/wd/3030-18930)
- **V** (CoH3 patch notes) the AI was reworked to pull out early from unwinnable fights and to "prepare wave attacks against
  strongpoints" instead of feeding squads in one by one; it chases retreating units and focuses weakened squads.
  [CoH3 changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/2942790265?p=2)
- Lesson: very simple individual rules (cover modifiers, suppression from near misses) plus *squad-level* timing produce
  convincing fights. Piecemeal attacks are the classic failure.

### Men of War / Call to Arms – Gates of Hell
- **I** (forums) Units engage automatically at near maximum range; stances "hold position / fire at will"; infantry AI quality
  varies by faction file; players micro-manage because squads otherwise walk into fire. Nothing technical published.
  [GoH discussion](https://steamcommunity.com/app/400750/discussions/0/4360121479834121008)
- Lesson for RTS + FPS: per-unit autonomy must keep the player's order (position, stance) authoritative.

### Squad
- **V** The game's AI is limited to seeding bots (SquidBots, now in the base game). Its changelog adds "a target acquisition
  period": bots are less accurate in the first 3 s on a new target. Nothing about squad tactics. Ordinary infantry is human.
  [SquidBots](https://steamcommunity.com/sharedfiles/filedetails/changelog/2891780963?p=2)
- FRACTURED NATIONS already has the same idea (`aim_first_mult`, settle time per weapon).

### F.E.A.R. (Monolith, Jeff Orkin, GDC 2006)
- **V** Three-state FSM + per-agent planner; a **squad manager** groups agents by proximity and hands out squad behaviours
  (get-to-cover, advance-cover, orderly-advance, search): "laying suppression fire as allies advance". Individuals do not know
  their squad mates — coordination lives in the squad layer. [Three States and a Plan](https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf),
  [GDC Vault](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
- Lesson: the coordinator decides *who moves and who fires*; the individual just fights. We keep the planner out.

### Killzone (Guerrilla, GDC Europe 2005)
- **V** Position picking with *position evaluation functions* over waypoints (cover, line of fire, distance to threat, distance
  to self), tactical path-finding that costs exposure to the threat, and **suppression fire at the last known / predicted
  position** of an unseen enemy. Fire-and-maneuver is called out as dependent on good position selection.
  [gdce05_killzone_ai.pdf](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf)

### Crysis / CryEngine Tactical Point System (Matthew Jack)
- **V** Positions are chosen by a query: generate candidates (hide spots around the target), filter by cheap tests first
  (distance), expensive ones last (raycasts, pathfinding), then weight. Example: "hide spots near me with excellent cover I can
  reach before the target". [CryEngine TPS](https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1638401/pages/1605720),
  *Game AI Pro 360: Tactics and Strategy*, ch. 1.

### Halo 2 / 3 (Bungie, Damian Isla)
- **V** Prioritised behaviour lists; AI keep an internal (possibly wrong) model of each target; squads are given *territories*
  and advance as the player expands the safe zone; cover = cells out of the player's line of sight. Readability: the player
  must see why the AI does something. [Gamasutra: eight years of Halo AI](https://gamedeveloper.com/game-platforms/in-depth-bungie-on-eight-years-of-i-halo-i-ai),
  [Halo 3 objectives (slides)](https://web.cs.wpi.edu/~rich/courses/imgd4000-d11/lectures/halo3.pdf)

### Brothers in Arms (Gearbox)
- **V/I** The whole design is "fix and flank": a suppression indicator on each enemy group; suppressed enemies' accuracy drops
  sharply, which opens the flank. [bit-tech review](https://www.bit-tech.net/reviews/gaming/pc/brothers-in-arms-hell-s-highway/1/)

## 2. Answers to the brief's questions (short)
- **Same system for friend and foe?** Yes — every source keeps one combat model; differences come from orders, doctrine
  (profile weights), skill and what the side knows. Knowledge must be *reported* (Halo's "model of the target can be wrong").
- **Target selection:** nearest visible is the baseline everywhere; spread fire across threats (CoH/Arma assign targets per
  member); anyone shooting *at me* outranks; never more shooters on one man than needed.
- **Accuracy:** dispersion from distance, movement, posture, suppression, a settle time on a new target (Squad, Arma
  aimingSpeed). No scripted misses: the existing `CombatBrain._aim_error` already models all of these.
- **Suppression vs hits:** suppression comes from near misses at a *rate*; it buys time for movement, it does not kill.
  Firing faster than needed only empties magazines (Reforger: duration + fire rate per suppression task).
- **Fire and movement:** one element moves while another fires (F.E.A.R. squad manager, BiA fix-and-flank); elements arrive
  together (CoH3 "wave attacks"); short rushes under fire; the final assault only once the defenders are fixed.
- **Cover / positions:** score candidates (Killzone, TPS): protection *and* line of fire from the halt, distance; keep
  cheap filters first; remember used spots to avoid oscillation (already: `_avoid_list`, dwell times).
- **RTS orders + FPS possession:** the order belongs to the squad record; the possessed soldier is skipped by the individual AI
  and nothing else changes (Arma).

## 3. What FRACTURED NATIONS already has
Strategic scorer, operations with stages and roles (`OpCoordination`), squad tactics with fire teams, leapfrog legs, flank
planning with exposure, suppression on the record with decay, fire missions at *reported* positions only, perception with
concealment and acquisition delay, aim model with settle time / posture / movement / suppression, cover search with protection
and line-of-fire tests, behaviour modes after Arma, player > operation > tactic > reaction authority. Architecturally it is
already the Arma / F.E.A.R. shape. The gaps are in **timing and fire control**, measured in §4 of the report.

## 4. Adopt
1. **Synchronised arrival (phase line)** — CoH3 waves / F.E.A.R. orderly-advance: assault squads may not close past the
   rearmost attacking squad by more than a short lead inside the defenders' effective range.
2. **Halted team chooses cover it can fire from** — Killzone / TPS scoring: protection + line of fire, no extra raycasts.
3. **Covering fire at reported enemy positions**, paced by movement — Killzone last-known-position suppression, Reforger
   suppression volume with a rate: full while the other team moves, thin while nobody moves.
4. **Sustained rifle fire rate for fire missions**; machine guns keep their bursts (CoH: suppression is the MG's job).
5. **Short rushes in the last 120 m under fire.**
6. **AWARE → COMBAT on contact** for squads under an operation's command (Arma).
7. **Target spreading** — pass over a target already engaged by three soldiers for the next visible one; never one shooting at me.
8. **No aimed fire on the move at long range** (both sides).

## 5. Reject
- GOAP / HTN / behaviour-tree runtimes (F.E.A.R., Halo, Reforger BTs): the project's layers already carry the decision;
  a planner would duplicate `OpCoordination` / `SquadTactics` (CLAUDE.md forbids it).
- Global squad target-assignment solver: costs per-frame work; the individual crowding rule gives most of the effect.
- CoH-style hard "pinned = no orders": conflicts with player authority and FPS possession.
- Scripted misses or difficulty fudge: the aim model already produces misses from causes.
- New cover systems / a territory system: cover search and `SquadPositions` exist; extend their scoring instead.

## 6. Recommended approach
Fix timing and fire control in the existing owners (`OpCoordination`, `SquadTactics`, `SquadPositions`, `CombatBrain`),
measure with `CombatDiag` (now with a hit log) on `--ai-strat-test a_assault` and the 3-seed `--combat02-test a_haugen,e_haugen`
series, and check defence (combat03) and player continuity (i_player) once. See `docs/AI-ASSAULT-01_REPORT.md`.
