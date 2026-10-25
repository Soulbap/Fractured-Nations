# VEH-04 Scania military truck — reference notes

## Variant selection
* Norway's own Scania fleet (Scania 3-series 93 / 113 / 143, 4x4 / 6x6, hook-lift prototypes 1993; bought 1986–1997) is being
  replaced by Rheinmetall MAN HX / TGS trucks (2014 framework with Sweden; TG3 MIL 8x8 from 2026). No current Norwegian Scania
  military contract was found.
* The modern Scania military truck documented in the Nordic / NATO neighbourhood is the **Scania XT** (New Truck Generation cab on
  the XT off-road chassis): Danish Army (DALO framework, ~1,000 Scania trucks incl. 6x6 / 8x8 cargo), Dutch Army (Gryphus / XT),
  Finnish Defence Forces (G / R series).
* **Modelled:** Scania XT 6x6 with a G-cab (day cab), dropside cargo body and canvas cover — the generic Nordic military cargo
  configuration. No model code is invented: the asset is called "Scania XT 6x6 military truck".

## Sources
| Source | What it gives |
|---|---|
| https://milforum.no/node/15441, https://offroad.no/forum/topic/50352-militcre-scania/ | Norwegian Scania fleet 1986–1997 (forum recollections: P92, 93, 113 tipper, 143 6x6, 6x6 hook-lift) |
| https://www.rheinmetall.com/en/media/news-watch/news/2022/2022-08-31_nato-customer-norway-officially-commissions-new-high-performance-rheinmetall-man-logistic-vehicles | Norway's current RMMV fleet |
| https://www.fmi.dk/da/nyheder/2020/milepal-naet-i-anskaffelsen-af-lastbiler-til-beredskabsstyrelsen/, https://www.forsvaret.dk/da/nyheder/2021/nye-lastbiler/ | Danish Scania procurement (~1,000 trucks) |
| https://www.fmv.se/aktuellt--press/aktuella-handelser/fmv-bestaller-lastbilar-fran-scania-och-volvo/ | Swedish FMV Scania 6x6 order |
| manifest.json (Wikimedia Commons) | Danish Army Scania XT R500 8x8 (front, side), Scania G410 8x8 hook-lift, Finnish G480, Dutch Scania XT with container, Dutch truck with shelter |

## Dimensions used (estimates from the photos and Scania XT 6x6 data)
| Item | Value | Status |
|---|---|---|
| Length | 8.90 m | estimated |
| Width | 2.55 m (cargo body 2.50 m) | road-legal maximum, published for Scania XT |
| Cab roof | 3.25 m | estimated from photos (G-cab on raised XT chassis) |
| Wheelbase | 4.50 m to the tandem centre, tandem 1.40 m | estimated |
| Tyres | 395/85 R20, Ø 1.20 m | Danish XT photos (Michelin XZL type) |
| Cargo bed | 2.50 × 6.55 m, floor at 1.42 m | estimated |

## Recognition features modelled
Scania NTG front: upper grille band with the lettering bar, hexagonal corner grilles, lower grille; headlights low in the bumper
corners (XT layout), protruding steel XT bumper with tow pin and skid plate, large windscreen with sun visor, doors with
three steps, rear quarter windows, big main + wide-angle mirrors, beacon; ladder frame with cross members, fuel tank (left), battery
box (right), air tanks, spare wheel behind the cab, leaf springs, axles; dropside body with stake pockets, rope hooks and canvas
cover over bows; mudguards, mud flaps, rear lamp bar, underrun bar, tow pintle.

## Movable parts
Wheel_L1..R3 (spin; axle 1 steers), Door_L / R, SteeringWheel, CargoBody (separable component); SpareWheel is static.

## Uncertainties
All dimensions are estimates (no Scania XT 6x6 drawing in the sources found). The modelled vehicle is a Nordic military Scania
configuration, not a Norwegian one (none currently exists).
