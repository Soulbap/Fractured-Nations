# COMBAT-01 — Combat visibility, gunplay, tactical AI and combat postures

Branch `develop`, commits `c7a8402` … (this report). Research basis: [COMBAT-01_RESEARCH.md](COMBAT-01_RESEARCH.md).
Tests: `--combat01-test` (`scripts/debug/combat01_selftest.gd`), results `benchmarks/raw/combat01_test.json`,
screenshots `docs/combat01/`. Every number below comes from a run named in §12; nothing is claimed that was not run.

## 1. Summary

| Area | What changed | Verified by |
|---|---|---|
| 120 m "no detection" (VISUAL-03) | Not a perception bug and not grass: a terrain rise 1.0–1.3 m above eye level between the two teams blocked all 32 sight lines. On a clear line at the same site all eight soldiers acquired a target in 0.5–1.25 s. | `v_detect` |
| Hidden-target leak (found on the way) | While vegetation data along a sight line was still loading, a soldier kept "visible" **and refreshed the target's position to its true location**, so a hidden enemy could be followed and fired at. Fixed: without a real check the position is not refreshed; aimed fire and grenades need a sighting within 1.2 s. | `r_markers` |
| Grass concealment | Mild acquisition delay from the grass actually drawn at the target, against its posture, distance, movement and fire. | `g_grass` |
| Posture | Stand / crouch / prone as one saved state on the soldier record, used by hits, sight, eye, speed, aim, animation, proxies, FPS, AI, saves. | `p_posture`, `p_ai_posture`, `--sandbox-test persist` |
| Prone animation | Six new clips on the VISUAL-03 rig (prone idle / aim / fire / crawl, stand↔prone), built in the Blender pipeline. | Blender build log, `p_posture` shots |
| Gunplay | Original combat sound set, distance layers with sound travel time, cracks / whizzes past the player, material impacts, new flashes, smoke, recoil with recovery, sight zoom per weapon, **Arma-style first person** (own arms and gloves on the weapon). | `f_gunplay` + screenshots |
| Accuracy | New AI aim profile `c01`: credible 200–300 m rifle fire, DMR clearly better, carbine falls off. | `a_accuracy` |
| Squad tactics | Local withdrawal (short, out of sight, with the reason), never against a player's hold; stalled assault → flank once → break off; covering fire before a leg under fire; status reasons in the HUD. | `t_withdraw`, `--ai-squad-test a_engagement,d_assault,f_withdraw,g_player` |
| RTS markers | Seen / last-seen / fired-from markers of the selected squad, from its soldiers' perception only. | `r_markers` |
| Visibility | Subtle rim light on cloth (backlit soldiers no longer black cut-outs), flashes that grow with distance, distant flickers to 1.3 km, DMR optic. | `s_visibility` before/after |

## 2. Files and systems changed

| System | Files |
|---|---|
| Posture (new) | `scripts/combat/posture.gd` (table + helpers), `scripts/core/unit_state.gd` (posture, posture_from, posture_at, posture_hold_until; saved) |
| Concealment (new) | `scripts/combat/concealment.gd` |
| Perception / AI | `scripts/combat/combat_brain.gd` (posture-aware sight and aim points, concealment, AI posture choice, aim profile c01, leak fix) |
| Hits / shots | `scripts/combat/line_of_fire.gd` (`segment_capsule`, posture hit volumes), `scripts/combat/combat_sim.gd` (posture eye, steadiness, prone bipod, no fire while getting down/up, prone blast exposure) |
| Movement | `scripts/core/world_sim.gd` (posture speed in both tiers), `scripts/core/world_state.gd` (moves stand up through `Posture.for_move`) |
| Bodies / FPS | `scripts/units/soldier_body.gd` (C / Z keys, eye height, recoil with recovery, sight zoom), `scripts/player/fps_controller.gd` (speed scale, no sprint/jump when low) |
| Character | `scripts/characters/infantry_character.gd` (prone branch seeked to the record, flinch), `infantry_proxy_mesh.gd` (mesh per posture), `infantry_materials.gd` (rim), `scripts/units/unit_proxy.gd` |
| First person | `scripts/combat/viewmodel.gd` (arms character, hip / aim placement, optic glass) |
| Effects / audio | `scripts/combat/combat_fx.gd`, `tools/audio/make_combat_sounds.py`, `assets/audio/combat/*.wav` (34 files) |
| Weapons | `scripts/combat/weapon_def.gd` (recoil_recover*, recoil_yaw_bias, viewmodel_kick, ads_fov), `assets/combat/*.tres` |
| Tactics | `scripts/core/squad_tactics.gd` |
| RTS | `scripts/rts/contact_markers.gd` (new), `scripts/game/core_demo.gd` |
| HUD | `scripts/ui/fps_hud.gd` (restrained vignette, posture by the name) |
| Blender | `tools/blender/character/char_prone.py` (new), `char_anim.py`; exported `assets/characters/infantry/rig/infantry_rig.glb`, `animation_meta.json`, `build_log.json`, `blender/infantry.blend` |
| Docs | `docs/CHARACTER_STANDARD.md` §3.1 (first-person muzzle, sight line, optics) and §7 (prone clips) |

No second combat simulation, planner or perception system was added; every change is inside the existing owners.

## 3. Visibility

* **Readability at range** (`s_visibility`, FPS eye 1.62 m, standing soldier in meadow grass; `docs/combat01/vis_before`,
  `vis_after`): at 50 m a recognisable armed figure; 100 m a small figure; 200 m a few pixels — readable against sky or
  open grass, lost against a forest edge (camouflage working); through the DMR optic (15°) clearly a soldier at 300 m.
  The automatic pixel-count metric was too noisy (wind-blown grass, temporal smoothing) and is not used; judged from the
  images.
* **Backlight:** cloth and helmets got a subtle rim term (`InfantryMaterials.RIM` = 0.08; 0.3 was tried and rejected — it
  read as glow). Backlit soldiers now show their uniform tone instead of a black cut-out (before/after in `vis_*`).
* **Combat activity at range:** muzzle flashes are star-shaped, grow with camera distance (a few pixels at 300 m) and are
  drawn as flickers to 1300 m without tracers, impacts or lights (`f_gunplay`: 4 flickers recorded at 700 m); tracers
  thicken with distance (existing), machine guns show a bright tracer every third round. No outlines, no enlargement.
* **Optics:** `WeaponDef.ads_fov` per weapon (red dot 42°, LMG 40°, GPMG 38°, DMR 15°), mouse slowed with the zoom.
* **RTS:** see §9.

## 4. Grass concealment

* **Data:** `Concealment.grass_height` reproduces the grass particle placement on the CPU from the same inputs
  (`grass_particles.gdshader`: noise patches and clods, forest tint of the colour map, exclusion mask, painted no-grass
  texture, slope) — mean tuft height × density, cached per 2 m cell. No ray, no node; asked only for a candidate already in
  sight, at the staggered 3 Hz perception.
* **Rule** (`CombatBrain.acquire_delay`): hidden share = smoothstep(grass height / the target's top (stand 1.78, crouch
  1.24, prone 0.50 m)); delay = hidden × (1 + 4.5 × distance/150 m) + a small posture term (crouch 0.25, prone 0.8 s per
  100 m); none within 15 m; ×0.45 when the target moves, ×0.15 when it fired in the last 2.5 s, ×0.6 when the observer was
  told / heard where to look; an enemy seen in the last 12 s is picked up again at once. Glimpses add up (in view time is
  accumulated, forgotten after 6 s out of view), so a sweeping gaze still notices. Grass never blocks sight or bullets.
* **Measured** (`g_grass`, observer 100 m away looking that way, 0.2 m grass at the target): standing noticed after 0.9 s
  (bare ground 0.5 s), crouched 0.5 s, **prone 1.8 s**, prone and firing 0.8 s, prone on bare ground 0.8 s. Untold, in the
  densest grass, the model gives ~4 s for a prone soldier at 100 m. Mild by design; nobody becomes invisible.

## 5. Weapon handling and accuracy

AI aim profile `c01` (default; `--aim=g05b` / `--aim=g04` for comparisons): base error 0.16° (was 0.26°), growth 0.035° per
100 m (0.05°), a fresh aim 1.6× (2×) the settled error, DMR aim factor 0.55. Hit rate per shot against a standing soldier's
real hit volumes (`a_accuracy`, 600 deterministic shots of the real aim error + weapon spread per case; first aimed shot
after the reaction time / settled):

| Shooter (trained) | 50 m | 100 m | 200 m | 300 m | 500 m |
|---|---|---|---|---|---|
| rifle standing | 87 / 95 % | 50 / 60 % | 18 / 20 % | 7 / 7 % | 2 % |
| rifle prone | 98 / 100 % | 75 / 81 % | 36 / 38 % | 16 % | 3 % |
| rifle veteran crouched | 100 % | 83 % | 42 % | 18 % | 4 % |
| carbine standing | 90 % | 51 % | 15 % | 4 % | 2 % |
| DMR standing | 100 % | 79 / 95 % | 36 / 56 % | 18 / 28 % | 6 / 8 % |
| DMR prone | 100 % | 96 / 100 % | 61 / 78 % | 33 / 47 % | 12 / 18 % |
| LMG standing (per round) | 85 / 97 % | 47 / 64 % | 15 / 23 % | 6 / 8 % | 2 % |
| LMG prone (per round) | 98 / 100 % | 71 / 83 % | 31 / 41 % | 14 / 18 % | 5 % |

Before (`g05b`): rifle standing 100 m 10 / 36 %, 200 m 2 / 9 %, 300 m 1 / 3 % — standard rifles were ineffective beyond
100 m and first shots were poor. A prone target at 200 m is now hit 5 % of the time (standing target 20 %). Movement,
bloom, suppression (×up to 5 aim error), proficiency and posture steadiness (crouch 0.85, prone 0.65; a machine gun's
bipod settles 0.6 s after getting down) still apply; damage was not changed; hitscan kept.

**First-person recoil** (`f_gunplay`): rifle kick 0.52°, 0.18° left after 0.5 s; a 0.6 s burst climbs 1.3°, settles back
to ~1.0°; DMR kick 1.1°; LMG 0.33° per round, a burst climbs 1.4°. Deterministic sideways drift with a weapon bias
(`recoil_yaw_bias`), recovery share and speed per weapon, steadied by posture and aiming. No camera shake.

## 6. FPS feedback

* **Sound** — an original set, synthesised offline by `tools/audio/make_combat_sounds.py` (Python standard library;
  project-owned, no third-party material, no download): per weapon (rifle, DMR, LMG, GPMG) close reports with muzzle
  blast, pressure thump, the action's clack, ground slap, discrete outdoor echoes and a diffuse tail; distant "pop and roll"
  (light / heavy, low-passed); supersonic crack (N-wave); whiz; impacts dirt / wood / metal / stone / flesh; explosions near
  / far. Three or four variants each, checked by spectrogram (numpy, installed for this). `CombatFX` plays the close report
  near, the distant one far, both in between, **delayed by the distance / 343 m/s** (you see the flash before you hear
  it), with air absorption of the 3D players. The COMBAT-01a synthesiser stays only as a fallback.
* **Incoming fire** — a round passing within 6 m of the first-person camera cracks at the point where it passed (the
  direction it came from; shooters beyond 25 m), within 1.4 m it also whizzes; impacts within 12 m of the camera are drawn
  1.7× larger. Audiovisual only: `f_gunplay` measured 15–28 cracks in 6 s of incoming fire and **0.000°** of view movement.
  The suppression vignette is restrained (edges only, max 0.45; was 0.75). Hits on the player himself draw nothing at the
  camera (a blood puff there darkened the whole screen in the first run).
* **Hit reactions** — an AI soldier hit (not killed) flinches away from the shot (a second spine modifier, ~0.3 s).
* **First person (Arma / Gray Zone references from the product owner)** — the soldier's own arms hold the weapon: an
  `InfantryCharacter` of the loadout with only sleeves, gloves, hands and weapon shown, in the `Aim` pose. Aiming lays the
  weapon's sight line (z = 0.172 m in weapon space) on the camera axis 0.24 m in front of the eye; at the hip the same
  hold sits lower right with the muzzle turned in. `Fire` and the magazine-change `Reload` play in first person. The
  optic glass is dark reflecting glass at the hip and clear only when aiming; the own muzzle flash forms 0.12 m in front of
  the muzzle and is unlit (its light glared inside the optic). Rules for new weapons: `CHARACTER_STANDARD.md` §3.1.

## 7. Crouch and prone

**Checkpoint (written before prone was built, as the brief asked):** one state on the soldier record; a table
(`Posture`) of eye, look/aim points, hit volumes, top height, speed and steadiness per posture; changes take time
(stand↔crouch 0.35 s, stand→prone 1.0 s, prone→stand 1.1 s, crouch↔prone 0.8 / 0.9 s), geometry blends over the change;
during a change to or from prone the soldier neither walks nor fires; collision capsule unchanged (bullets use the
analytic volumes); prone only where the ground suits it (grade, water, bridge deck, structures under the head or legs).

* **State:** `UnitState.posture / posture_from / posture_at / posture_hold_until`, saved with the other combat fields.
  `p_posture`: prone survives a save / load (`apply_snapshot`, the game's load path) settled.
* **Hits:** head sphere and torso capsule per posture, plus a legs capsule when prone (`LineOfFire.segment_capsule`, any
  axis). `p_posture`: a crouched soldier is not hit by a ray at standing head height; a prone soldier is not hit at standing
  chest height and is hit in the head at the prone head; standing head shots still land.
* **Sight and fire:** the eye (`CombatSim.eye_of` → `Posture.eye`) and the points the AI looks at / aims for follow the
  posture, so cover blocks a crouched soldier consistently and the AI never fires through cover at an assumed standing
  target. Near misses and friend-in-line checks use the posture's body axis. A prone soldier is reached lower by blasts.
* **Movement:** speed × 0.55 crouched (2.5 m/s), × 0.18 prone (0.8 m/s), 0 while getting down / up, both tiers and the
  possessed body (no sprint or jump below standing). A move order stands the soldier up first (short shifts keep a crouch
  ≤ 8 m or a prone crawl ≤ 3 m): `p_posture` — moved 0.0 m while getting up, 8.6 m 3 s after the order.
* **Player:** C crouch / stand, Z prone / crouch, sprint stands up; prone is refused without room; the first-person eye
  follows (0.38 m prone, 1.12 crouched); the HUD shows the posture by the name.
* **AI** (`CombatBrain._choose_posture`, at the perception cadence): standing when idle or in a fortification slot;
  crouched when alert or in cover; prone when pinned in the open, or with a machine gun / marksman rifle against a target
  ≥ 120 m, never while moving or just before its squad moves on, never on unsuitable ground; hysteresis (prone kept while
  suppression > 0.3) and holds of 3 s (prone 6 s). `p_ai_posture` (4 v 4 at 150 m, 30 s): standing 7 %, crouched 41 %,
  prone 52 % of the time; MG and DMR down for the long shot, riflemen down only when fully pinned (suppression 0.97–1.0);
  at most 7 changes per soldier in 30 s; nobody moved faster than its posture allows.
* **Animation:** `char_prone.py` (procedural; the CMU takes used have no prone capture) on the same rig and weapon tools:
  prone idle / aim / fire, low crawl (0.81 m/s), stand→prone and prone→stand through a kneel and a hands-down pose. Hands on
  the grips 0.0 mm in the loops, ≤ 50 mm in the transitions; butt 60 mm from the shoulder pocket in prone aim. The game seeks
  the transition clip to the record's progress, so the animation is exactly where the authoritative change is. Measured
  prone layout (head 0.65 m forward at 0.40 m, feet 0.86 m back) is what `Posture` uses for hits and the eye. Far proxies
  get a mesh per posture.

## 8. AI tactical improvements

* **Local withdrawal** (`t_withdraw`): a hopeless squad first moves 45–100 m to ground out of the believed enemy's sight
  ("local withdrawal 45 m - heavy casualties"), farther only when there is no such ground. New trigger: most of the squad
  pinned with nobody firing back for 8 s ("pinned, no firing position"). After it, REGROUP and the previous order resumes;
  the autonomous choice continues if contact remains. A squad holding where **the player** ordered never withdraws on its
  own — neither through the squad's choice nor through a failing defence (that path withdrew 107 m in the first run of the
  check; fixed) — and the HUD says "holding by your order (would withdraw)". Player orders still end any tactic at once.
  In the check the hurt AI squad survived with 2 of 4 (the old behaviour: wiped out in place).
* **Support before movement:** an assault's support phase no longer waits when nobody sees or shoots at the squad; under
  fire, the moving team waits up to 6 s until its covering team is actually firing.
* **Stalled assault:** an advance that loses 2+ soldiers while gaining < 15 m in 25 s tries a flank once, else breaks off
  (squad: withdraw; player's order: hold; operation: reported back).
* **Status for the player:** `SquadTactics.short_text` / `status_tag` add the reason ("Withdraw · leg 1 · heavy
  casualties", "Assault · advance · waiting: the covering team is not firing yet", "pinned", "taking cover", "engaging").

## 9. RTS contact markers

`ContactMarkers` (tactical view, selected squads and loose soldiers): solid red diamond = an enemy a soldier of the squad
sees now (at the position its perception wrote); hollow diamond = last seen there, fading over 20 s; small orange triangle
= fired on from there (the blurred threat position), fading over 8 s. No enemy record is read. Markers keep their screen
size, merge when they overlap (more at distance) and are capped at 40. `r_markers`: a visible enemy is marked where it is;
moved behind cover, the marker stays at the last seen place and does not follow; after the memory it is gone.

## 10. Visual and audio

See §3 and §6. Screenshots: `docs/combat01/f_hip.png`, `f_ads_rifle.png`, `f_ads_dmr.png`, `f_own_flash.png`,
`f_fight_350m.png`, `f_fight_700m.png`, `p_*` (postures: stand / crouch / prone side, front, without grass, mid-change,
first person prone / crouched), `p_ai_posture.png`, `g_prone_in_grass_18m.png`, `r_markers_*.png`, `s_*` / `vis_before`,
`vis_after`, `v_detect_*.png`.

## 11. Performance

* Perception: concealment is a cached map lookup on candidates already in sight; posture hit volumes add one capsule
  test per soldier near a shot. `--ai-squad-test l_perf` (48 soldiers): CombatBrain 2.57 ms per frame with tactics off —
  AI-SQUAD-01 measured 2.56 ms; frame average 8.8 ms (tactics off) / 14.3 ms (on), under the 16.7 ms check.
* **Pre-existing:** `l_perf`'s "squad tactic update < 2000 µs per step" fails: 3230 µs with COMBAT-01, **3070 µs with the
  pre-COMBAT-01 `squad_tactics.gd`** (same run setup) — the limit was already exceeded (the judged defence posts of
  GAMEPLAY-03/04G); COMBAT-01's tactics changes are within noise.
* Effects: pooled as before; lights only within 80 m and never for the player's own flash; distant flickers have no light,
  tracer or impact; the first-person arms are one extra character while possessed.

## 12. Tests performed

All one deterministic run each (no series):

| Run | Result |
|---|---|
| `--combat01-test --only v_detect` | PASS (VISUAL-03 placement: 0 / 32 lines clear, terrain; clear placement: 8 / 8 acquired in 0.5–1.25 s) — rerun after the leak fix: PASS |
| `--only p_posture --shots` | PASS |
| `--only g_grass --shots` | PASS (after the accumulation fix and 4.5 s / 150 m; two earlier runs exposed a reset-on-glimpse bug and an observer sweep artefact) |
| `--only a_accuracy` | numbers in §5 (`g05b` and `c01`) |
| `--only f_gunplay --shots` | PASS (several runs while the first-person view, flash and glass were fixed) |
| `--only t_withdraw` | PASS (the first runs exposed a missing precondition, an overwritten reason and the player-hold withdrawal) |
| `--only r_markers --shots` | PASS (first runs exposed the hidden-target leak) |
| `--only s_visibility --shots` | images in `vis_before` / `vis_after` |
| `--only p_ai_posture --shots` | PASS |
| `--sandbox-test --only characters` | PASS |
| `--sandbox-test --only persist` | PASS |
| `--ai-squad-test --only base_fight,k_persist` | base_fight PASS; k_persist fails K(suppress) / K(flank) — **identical with the pre-COMBAT-01 code** (stash run): site terrain, pre-existing |
| `--ai-squad-test --only a_engagement,d_assault,f_withdraw,g_player` | PASS |
| `--combat03-test --only p_posts` | PASS |
| `--ai-squad-test --only l_perf` | fails the tactics step limit, pre-existing (§11) |
| Blender `build_infantry.py --export` | clips built, checks in `build_log.json` (`anim_check.prone`) |
| `tools/check_scripts.gd` | 185 scripts, 0 failed |

No full suite was run.

## 13. Known remaining limitations

* Prone reload shows the rifle lowered (no prone reload clip); the transitions keep both hands near the rifle within
  ≤ 50 mm (not 0 mm); the feet in prone rest on the toes (no flat-foot variant); the physical capsule stays standing
  (bullets and sight use the posture volumes; a player can still turn the prone body's legs into a wall).
* The prone animations are procedural, not captured: readable, not mocap quality.
* First person: the jacket's shoulder shows at the lower left at the hip (as Arma's body does); weapon models are the
  existing ones — the product owner will revisit them with the new weapons (`CHARACTER_STANDARD.md` §3.1 lists the rules).
* Sound is synthesised (original) rather than recorded; recorded CC0 libraries would need an approved download.
* RTS: there is no posture command for squads (AI chooses; the player controls posture in first person).
* `l_perf` tactics limit and `k_persist` failures are pre-existing (§11, §12).
* Readability numbers in §3 are judged from images; the pixel metric was abandoned as unreliable.

## 14. Screenshots and videos

Screenshots listed in §10 (1920×1080 captures, crops where noted). No videos were recorded this milestone.

## 15. Deferred work requiring approval

* Recorded weapon sounds from a CC0 library (download).
* A posture order for RTS squads (crouch / prone on command).
* A prone reload clip and captured prone motion.
* Raising the `l_perf` tactics budget or optimising the judged defence posts (pre-existing).
