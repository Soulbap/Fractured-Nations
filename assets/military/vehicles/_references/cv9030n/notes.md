# VEH-03 CV9030N — reference notes

**Variant modelled:** CV9030N Mk IIIb, Norwegian Army infantry fighting vehicle (BAE Systems Hägglunds; Norway's 2012 programme,
144 vehicles incl. Mk IIIb hulls/turrets): 30 mm Bushmaster II, Soucy composite rubber tracks (Norway was first to field them),
Kongsberg Protector RWS on the turret, bolted add-on armour modules on the sides.

## Sources
| Source | What it gives |
|---|---|
| https://en.wikipedia.org/wiki/CV90 | Norway: 104 CV9030N (1994), CV9030NF1 upgrade (rubber tracks, mine protection), 2012 Mk IIIb programme, Protector RWS on Norwegian IFV/C2/recce variants, crew 3 + 7–8 |
| https://forum.warthunder.com/t/topic/9205 | compiled Mk IIIb figures: 6.55 m long, 3.1 m wide, 2.7 m high, 35 t (secondary source) |
| https://www.upi.com/Defense-News/2011/02/11/Armored-vehicles-using-rubber-tracks/63011297422530/ | rubber tracks on Norwegian CV9030 in Afghanistan (−1 t, −10 dB) |
| https://esut.de/en/2020/11/meldungen/23863/niederlaendische-armee-modernisiert-ihre-panzer-cv90-ifv/ | Soucy rubber track system |
| manifest.json (Wikimedia Commons) | Norwegian Mk IIIb IFV / recce / C2 line-ups, CV9030N in snow (side 3/4), Afghanistan; some files failed to download (rate limit) and are listed with their URLs |

## Dimensions used
| Item | Value | Status |
|---|---|---|
| Hull length | 6.55 m | compiled Mk III figure |
| Width over add-on armour | 3.24 m | 3.1–3.2 m in sources; armour modules estimated |
| Turret roof | 2.62 m (2.7 m published, ~2.8 m incl. sights) | published / estimated |
| Road wheels | 7 per side, Ø 0.62 m, 0.68 m spacing | layout from photos, diameter estimated |
| Track | 0.533 m wide, rubber, pitch ~0.125 m | width from CV90 data, pitch estimated |
| Sprocket / idler | front drive sprocket, rear idler | CV90 layout |
| Return rollers | 2 per side (hidden by the skirts) | estimated |

## Recognition features modelled
Low hull with front engine (louvre deck on the right), driver's hatch and periscopes front left, nose wedge armour, five bolted
add-on armour modules per side, rear troop door with vision block, roof hatches, rear stowage bins; angular turret with side armour,
smoke dischargers, commander's panoramic sight (right) and gunner's sight (left), cupola with vision blocks, bustle basket with
canvas stowage, Protector RWS on the turret roof, 30 mm barrel with sleeve and muzzle device, coax.

## Movable parts
Turret (yaw) → Gun (elevation), RWS / RWS_Gun, Hatch_Commander, Hatch_Driver, Hatch_L / R, Door_Rear; RoadWheel_L1..R7,
Sprocket_L/R, Idler_L/R, Roller_L1..R2 (each spins about X); Track_L / Track_R (separate loops: individual links on LOD0).

## Uncertainties
No official BAE dimension sheet for the Mk IIIb was found; turret details of the Norwegian Mk IIIb (sight positions, RWS
location) follow the Norwegian photos at small size. Return roller count is not visible in the photos (skirts).
