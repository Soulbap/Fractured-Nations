# VEH-01 Iveco LMV — reference notes

**Variant modelled:** Iveco LMV (Light Multirole Vehicle) in Norwegian Army service ("LAV" in Forsvaret: LAV 2 / LAV 3 / LAV 4,
170 ordered 2007–2018), four-door crew cab with a rear door, Kongsberg Protector RWS on the roof hatch ring.

## Sources
| Source | What it gives |
|---|---|
| https://en.wikipedia.org/wiki/Iveco_LMV | width 2.20 m (LMV2), heights 2.05 m (LMV crew cab) / 2.17 m (LMV2), wheelbase 3.2 / 3.5 m, ground clearance 473–493 mm, Norway: 170 vehicles |
| https://www.defenseindustrydaily.com/norway-rushorders-mineresistant-iveco-mlvs-02089/ | Norwegian order history (Afghanistan, 2006 onwards) |
| https://www.kongsberg.com/news/news-archive/2008/contracts-for-weapon-control-systems-valued-at-a-total-of-mnok-102/ | Protector (Lite) RWS ordered for the Norwegian LMVs |
| https://www.tu.no/artikler/denne-panserbilen-er-resultatet-av-hva-forsvaret-laerte-i-afghanistan/223609 | Norwegian designation LAV, background |
| manifest.json (Wikimedia Commons, 7 photos) | Norwegian LMVs in Afghanistan (front, 3/4, convoy), Norway winter 202x with Protector RS4 and light bar, Austrian rear 3/4 |

## Dimensions used
| Item | Value | Status |
|---|---|---|
| Length | 4.87 m | published (LMV short wheelbase; some sources give 5.50 m for LMV2 / spare wheel) |
| Body width | 2.00 m (2.05 m over the flares) | published 2.05 m (LMV); 2.20 m is LMV2 |
| Roof | 2.05 m | published |
| Wheelbase | 3.20 m | published |
| Track | 1.72 m | estimated from the front photo |
| Tyres | 335/80 R20, Ø 1.04 m | Iveco data (Michelin XZL) |
| Front / rear overhang | 0.75 / 0.92 m | estimated from side photos |

## Recognition features modelled
Short high bonnet with central raised panel, louvred grille in two blocks with the badge plate between, round headlights in the
front corners, steel bumper with winch, snorkel up the right A-pillar, raked armoured windscreen, four doors with armoured windows
(rear doors cut around the rear wheel arch), black wheel-arch flares, tubular side steps, rear door, rear lamp clusters in the
bumper, roof light bar (Norwegian photo 01), roof rails and antennas, Protector RS4 with M2.

## Paint / materials
Norwegian LMVs are seen in ISAF sand and in green. The asset uses Paint_Green (faction paint swaps Paint_Green → tan / grey
in VehicleVisual). Armoured glass is see-through on LOD0 (Glass_Vehicle), opaque on LOD1/2.

## Movable parts
Wheel_L1/R1 (spin + steer), Wheel_L2/R2 (spin), Door_FL / FR / RL / RR (hinge at the front edge), Door_Rear, SteeringWheel,
RWS (yaw) + RWS_Gun (elevation).

## Uncertainties
Exact LAV 4 roof equipment (radio fit, light bar) varies per vehicle; the Protector variant on the LMV (Lite vs RS4) is not
confirmed per batch — a generic RS4-type station is used. Track width and overhangs are photo estimates.
