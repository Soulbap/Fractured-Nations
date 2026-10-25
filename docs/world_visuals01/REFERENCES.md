# WORLD-VISUALS-01 — references and observations

Studied for appearance only. Nothing from these pages was copied into the game; the only third-party content in the build is the
CC0 material listed under "Source assets" (licence record: `assets/environment/source/polyhaven/sources.json`, written by
`tools/blender/env/fetch_polyhaven.py`).

## Ecology and species

| Source | Used for |
|---|---|
| Store norske leksikon: [blåbærskog](https://snl.no/bl%C3%A5b%C3%A6rskog), [bærlyngskog](https://snl.no/b%C3%A6rlyngskog), [granskog](https://snl.no/granskog), [furuskog](https://snl.no/furuskog), [barskog](https://snl.no/barskog) | Forest floor composition: bilberry forest is the most common Norwegian forest type (dense feather-moss layer, bilberry dominant, wavy hair-grass on clear-cuts); lingonberry/heath pine forest on dry, poor ground (lingonberry, heather, crowberry, lichen); spruce on richer, moister sites, pine on dry sites, birch / rowan / willow on wet ground. Drove the ground-cover rules in `grass_particles.gdshader` and the composited forest-floor texture (moss carpet + needle litter). |
| [Crown architecture of young Norway spruce (BioResources)](https://bioresources.cnr.ncsu.edu/resources/crown-architecture-and-structural-development-of-young-norway-spruce-trees-picea-abies-karst-a-basis-for-more-realistic-growth-modelling/), [Picea abies (van den Berk)](https://www.vdberk.co.uk/trees/picea-abies/), [Silva Fennica](https://silvafennica.fi/export/refer/5459) | Norway spruce: narrow pyramidal to columnar crown, near-horizontal primary branches turning up at the tips, branchlets hanging from them (comb / brush types), lower branches stay green when open-grown, self-pruned dead twigs in dense stands. → `make_spruce`: whorls of 5-7 branches that sag and turn up, hanging branchlet cards, forest-grown variants with dead lower stems, open-grown variants green to the ground. |
| [Scots pine bark (RBGE)](https://stories.rbge.org.uk/archives/10267), [Virginia Tech dendrology](https://dendro.cnre.vt.edu/dendrology/carddetail.cfm?ID=112), [Utah State tree browser](https://extension.usu.edu/treebrowser/catalog/pine-scotch-scots) | Scots pine: grey-brown thick plates at the base, thin orange flaking bark on the upper stem and limbs; rounded crown when young, flat irregular crown on a long clear stem when old, needle tufts at the branch ends. → two-zone pine bark (`bark.gdshader` upper bark), `make_pine` (pine_a rounded, pine_b flat-topped). |
| [Mountain birch dynamics, SE Norway (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10168091/), [NINA mountain birch](https://www.nina.no/Portals/NINA/Bilder%20og%20dokumenter/Mountain%20birch%20%28Betula%20pubescens%20tortuosa%29.pdf) | Birch: multi-stemmed forms from sprouting (edges, wet ground, near the tree line), weeping twigs of silver birch. → birch_b multi-stem variants, hanging twig cards. |

## Game environments

| Source | Observation |
|---|---|
| Arma Reforger (Everon) — [workshop](https://reforger.armaplatform.com/workshop/6916B679272BC1A8), [Kolguyev status report](https://reforger.armaplatform.com/news/kolguyev-status-report), environment artist portfolio [ArtStation](https://skywalger.artstation.com/projects/038rnw) | What makes it convincing: dense, varied understorey under every tree; trees of several ages in one stand; ground textures at 2-3 m scale (not stretched); the ground clutter carries the colour of the soil, not a separate green; light under the canopy stays readable; atmospheric haze grows over kilometres. Vegetation there is a custom pipeline of species-specific trees, bushes, clutter and ground surfaces. |
| [Unigine forest devlog](https://developer.unigine.com/devlog/20121230-forests-dof), [Candussi et al. 2005, Eurographics](https://sites.cs.ucsb.edu/~holl/pubs/Candussi-2005-EG.pdf), [Bruneton & Neyret, real-time forests](https://diglib.eg.org/items/9de7c594-877a-4d97-a2e0-bcab5acb10bf/full) | Forest rendering practice: billboarded foliage clusters on simplified branch geometry, discrete LODs with an impostor far LOD, impostors that keep the same positions as the meshes, lighting of leaves and the ground under them as a major part of realism. → spray / tuft cards on modelled branches, near / mid / impostor LODs from the same instance data, eye adaptation and sky light for the forest floor. |

## Source assets (CC0, Poly Haven)

Downloaded to `assets/environment/source/polyhaven/` (git-ignored; `python tools/blender/env/fetch_polyhaven.py` fetches
them again). Processed into the game by `make_cards_v3.py`, `make_surfaces_v3.py`, `make_props_v3.py`.

- Ground scans: leafy_grass, sparse_grass, mossy_rock, forest_ground_04, rocky_trail, rocky_terrain_02, mud_forest (plus
  forest_floor, forrest_ground_01, leaves_forest_ground, brown_mud_leaves_01, withered_grass, grass_path_2, rock_face,
  lichen_rock, rock_pitted_mossy, aerial_rocks_02, brown_mud, dirt, gravel_road, gravelly_sand, rocky_gravel - evaluated,
  partly unused).
- Bark scans: pine_bark (Scots pine bark; also the basis of the spruce bark), bark_brown_02 (birch base, deadwood).
- Twig atlases: fir_tree_01 (fir sprigs -> Norway spruce sprays), pine_tree_01 (pine sprig -> Scots pine tufts).
- Models: rock_moss_set_01 / 02, rock_07, rock_09, stone_01, tree_stump_01 / 02, dead_tree_trunk / _02,
  dry_branches_medium_01 (and fern_02, moss_01, nettle_plant, boulder_01, namaqualand_boulder_02, bark_debris_01,
  root_cluster_01, pine_roots - evaluated; fern_02 has opaque fronds, boulder_01 would not decimate cleanly: not used).

Authors are in `sources.json`; CC0 requires no attribution.
