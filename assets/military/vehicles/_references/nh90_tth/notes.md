# VEH-06 NH90 TTH — reference notes

**Variant modelled:** NHIndustries NH90 TTH (Tactical Transport Helicopter) in the NATO army configuration (German Army,
Finnish, Belgian, French "Caïman" TTH): sliding cabin doors both sides, rear ramp, twin nose wheels, main wheels in sponsons,
four-blade main rotor, four-blade tail rotor on the left side of the fin, horizontal stabiliser on the right.
A NATO reference vehicle — not a representation of Norway's helicopter fleet.

## Sources
| Source | What it gives |
|---|---|
| https://helicopters.leonardo.com/-/nh90 | rotor diameter 16.30 m, length 19.56 m rotors turning, height 5.31 m (tail rotor) |
| https://www.helis.com/database/model/NH90/ | fuselage 16.13 m, height 5.23 m |
| https://www.globalsecurity.org/military/world/europe/nh90-specs.htm | specification table |
| https://skybrary.aero/aircraft/nh90 | four-blade tail rotor |
| manifest.json (Wikimedia Commons) | French TTH front (nose, FLIR, windscreen), tail rotor detail, German TTH static (3/4), German TTH hovering (left side: tail rotor on the left), Finnish TTH, cabin door detail |

## Dimensions used
| Item | Value | Status |
|---|---|---|
| Fuselage length | 16.13 m | published |
| Main rotor diameter | 16.30 m | published |
| Tail rotor diameter | 3.20 m | estimated (not in the sources found) |
| Height to the tail rotor top | 5.23 m (tail rotor centre 3.63 m) | published / derived |
| Rotor hub | y = 2.05 m, z = 4.12 m | derived from the 19.56 m rotors-turning length and photos |
| Cabin | 2.50 m wide, floor 0.72 m, roof 3.0 m | estimated from photos |
| Main gear track | ~3.2 m | estimated |

## Recognition features modelled
Bulbous radome nose with chin FLIR turret, large wraparound cockpit glazing (windscreen, side, chin and roof windows following
the curved skin), cockpit doors, tall flat-sided cabin with sliding doors and square windows, low sponsons with the main gear,
twin nose wheels, upper deck with two engine cowlings, intakes and angled exhausts, mast fairing, thick rising tail boom, swept fin
with the tail rotor on the left and the horizontal stabiliser on the right, tail bumper; main rotor hub with arms, dampers, pitch
links and swashplate; four separate blades with swept, tapered tips; rear ramp.

## Movable parts
MainRotor (spin about Z, pivot at the hub) → Blade_1..4 (pitch about their span), TailRotor (spin about X, pivot at its hub),
Door_Pilot / Door_CoPilot (hinged), Door_Slide_L / R (slide aft), Ramp (hinge at the lower front edge).

## Uncertainties
Tail rotor diameter, gear track, cabin window count and positions are photo estimates; the NH90 blade planform tip is simplified.
