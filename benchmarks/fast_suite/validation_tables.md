| Map | Regions | Driver | Scenario | FPS ground ms (p99) | GPU ms | RTS 600 m ms | Strategic ms | Jump max ms | MultiMeshes | VRAM (Godot) MB | Aborted |
|---|---|---|---|---|---|---|---|---|---|---|---|
| real_2km | 4 | d3d12 | full | 4.1 (5.1) | 1.5 | 6.8 | 1.0 | 15.1 | 23276 | 1750 |  |
| real_2km | 4 | d3d12 | particles | 4.2 (4.6) | 1.2 | 7.1 | 1.3 | 14.1 | 19291 | 1515 |  |
| real_2km | 4 | d3d12 | roads | 0.9 (1.0) | 0.8 | 1.4 | 1.0 | 7.8 | 0 | 296 |  |
| real_2km | 4 | d3d12 | terrain | 1.2 (1.4) | 1.0 | 1.4 | 1.0 | 7.7 | 0 | 287 |  |
| real_2km | 4 | vulkan | full | 2.2 (2.6) | 1.2 | 3.8 | 1.4 | 11.6 | 23276 | 303 |  |
| real_2km | 4 | vulkan | particles | 2.3 (2.7) | 1.3 | 3.8 | 1.8 | 11.2 | 19291 | 288 |  |
| real_2km | 4 | vulkan | roads | 1.1 (1.3) | 0.8 | 1.7 | 1.4 | 8.3 | 0 | 270 |  |
| real_2km | 4 | vulkan | terrain | 1.4 (1.6) | 1.0 | 1.7 | 1.4 | 8.2 | 0 | 270 |  |
| tile_4km | 16 | d3d12 | full | - | 0.0 | - | - | 0.0 | 93160 | 6373 | render errors: 11591 |
| tile_4km | 16 | d3d12 | roads | - | 0.0 | - | - | 0.0 | 0 | 6373 | render errors: 206 |
| tile_4km | 16 | d3d12 | terrain | 1.2 (1.5) | 1.1 | 1.4 | 1.0 | 7.9 | 0 | 542 |  |
| tile_4km | 16 | vulkan | full | 4.4 (5.1) | 1.4 | 4.3 | 1.6 | 14.0 | 93160 | 656 |  |
| tile_4km | 16 | vulkan | roads | 1.2 (1.6) | 0.8 | 1.8 | 1.5 | 8.3 | 0 | 525 |  |
| tile_4km | 16 | vulkan | terrain | 1.4 (1.5) | 1.1 | 1.8 | 1.5 | 8.2 | 0 | 525 |  |
| tile_15km | 225 | d3d12 | full | 4.9 (5.4) | 1.5 | 7.2 | 1.7 | 12.3 | 23276 | 4698 |  |
| tile_15km | 225 | d3d12 | particles | 5.0 (5.5) | 1.4 | 7.6 | 2.0 | 11.8 | 19291 | 4462 |  |
| tile_15km | 225 | d3d12 | roads | 1.2 (1.4) | 1.0 | 2.0 | 1.6 | 8.0 | 0 | 3243 |  |
| tile_15km | 225 | d3d12 | terrain | 1.3 (1.3) | 1.2 | 1.4 | 1.7 | 7.8 | 0 | 3234 |  |
| tile_15km | 225 | vulkan | full | 2.2 (2.9) | 1.2 | 3.6 | 1.4 | 9.7 | 23276 | 3250 |  |
| tile_15km | 225 | vulkan | particles | 2.3 (2.5) | 1.3 | 3.8 | 1.8 | 9.7 | 19291 | 3235 |  |
| tile_15km | 225 | vulkan | roads | 1.2 (1.3) | 0.8 | 1.8 | 1.4 | 7.7 | 0 | 3218 |  |
| tile_15km | 225 | vulkan | terrain | 1.4 (1.4) | 1.1 | 1.8 | 1.4 | 7.8 | 0 | 3217 |  |
| tile_19km | 361 | d3d12 | terrain | 1.7 (1.9) | 1.2 | 1.5 | 1.7 | 8.5 | 0 | 5014 |  |
| tile_20km | | d3d12 | (crash at load) | | | | | | | | FATAL |
| tile_20km | 400 | vulkan | full | 2.4 (3.2) | 1.2 | 3.7 | 1.2 | 9.9 | 23276 | 5584 |  |
| tile_20km | 400 | vulkan | particles | 2.3 (2.6) | 1.4 | 3.8 | 1.6 | 9.9 | 19291 | 5569 |  |
| tile_20km | 400 | vulkan | roads | 1.2 (1.6) | 0.9 | 1.9 | 1.2 | 7.8 | 0 | 5551 |  |
| tile_20km | 400 | vulkan | terrain | 1.4 (1.9) | 1.1 | 1.8 | 1.2 | 9.6 | 0 | 5551 |  |
| real_20km | 100 | d3d12 | full | 1.5 (1.7) | 1.1 | 1.9 | 1.5 | 13.3 | 8165 | 2184 |  |
| real_20km | 100 | d3d12 | particles | 1.6 (1.8) | 1.2 | 2.0 | 1.7 | 13.7 | 7017 | 2126 |  |
| real_20km | 100 | d3d12 | roads | 1.1 (1.3) | 1.0 | 1.6 | 1.5 | 12.2 | 0 | 1673 |  |
| real_20km | 100 | d3d12 | terrain | 1.1 (1.5) | 1.0 | 1.6 | 1.4 | 11.6 | 0 | 1577 |  |
| real_20km | 100 | vulkan | full | 1.4 (1.8) | 1.1 | 2.2 | 1.6 | 12.5 | 8165 | 1596 |  |
| real_20km | 100 | vulkan | particles | 1.5 (1.6) | 1.2 | 2.4 | 2.1 | 12.9 | 7017 | 1576 |  |
| real_20km | 100 | vulkan | roads | 1.3 (1.6) | 1.0 | 1.9 | 1.6 | 12.0 | 0 | 1558 |  |
| real_20km | 100 | vulkan | terrain | 1.3 (1.6) | 1.0 | 1.9 | 1.6 | 12.2 | 0 | 1556 |  |

| Run | Wall s | Exit | Peak RAM (working set) MB | Peak GPU dedicated MB | Peak GPU shared MB |
|---|---|---|---|---|---|
| d3d12_tile_19km | 14.9 | 0 | 5207 | 5063 | 76 |
| vulkan_real_2km | 14.7 | 0 | 1249 | 631 | 231 |
| vulkan_tile_4km | 17.2 | 0 | 2929 | 874 | 429 |
| vulkan_tile_15km | 19.6 | 0 | 4195 | 3375 | 231 |
| vulkan_tile_20km | 24.4 | 0 | 6527 | 5707 | 231 |
| vulkan_real_20km | 17.2 | 0 | 2373 | 1695 | 213 |
| d3d12_real_2km | 17.1 | 0 | 994 | 1789 | 103 |
| d3d12_tile_4km | 31.8 | 0 | 2873 | 6290 | 239 |
| d3d12_tile_15km | 24.4 | 0 | 3949 | 4728 | 108 |
| d3d12_tile_20km | 17.5 | 0xC000001D (crash) | 6333 | 6985 | 161 |
| d3d12_real_20km | 17.2 | 0 | 2113 | 2229 | 104 |
| vulkan_fps_real_20km | 24.5 | 0 | 2416 | 1725 | 213 |
| vulkan_fps_tile_20km | 31.7 | 0 | 6534 | 5707 | 229 |
| vulkan_real_20km_shots | 12.3 | 0 | 2380 | 1695 | 213 |
| vulkan_tile_20km_shots | 17.1 | 0 | 6528 | 5707 | 229 |

d3d12_tile_19km {"color": {"layers": 361, "mips": 11, "subres": 3971, "MB": 1925}, "control": {"layers": 361, "mips": 1, "subres": 361, "MB": 1444}, "height": {"layers": 361, "mips": 1, "subres": 361, "MB": 1444}}
vulkan_tile_20km {"color": {"layers": 400, "mips": 11, "subres": 4400, "MB": 2133}, "control": {"layers": 400, "mips": 1, "subres": 400, "MB": 1600}, "height": {"layers": 400, "mips": 1, "subres": 400, "MB": 1600}}
vulkan_tile_15km {"color": {"layers": 225, "mips": 11, "subres": 2475, "MB": 1200}, "control": {"layers": 225, "mips": 1, "subres": 225, "MB": 900}, "height": {"layers": 225, "mips": 1, "subres": 225, "MB": 900}}
vulkan_real_20km {"color": {"layers": 100, "mips": 11, "subres": 1100, "MB": 533}, "control": {"layers": 100, "mips": 1, "subres": 100, "MB": 400}, "height": {"layers": 100, "mips": 1, "subres": 100, "MB": 400}}
vulkan_real_2km {"color": {"layers": 4, "mips": 11, "subres": 44, "MB": 21}, "control": {"layers": 4, "mips": 1, "subres": 4, "MB": 16}, "height": {"layers": 4, "mips": 1, "subres": 4, "MB": 16}}
