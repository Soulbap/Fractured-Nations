# Motion capture sources (VISUAL-03)

`cmu/zip/*.zip` are takes from the **CMU Graphics Lab Motion Capture Database** (http://mocap.cs.cmu.edu/), in the
BVH conversion by Bruce Hahne (cgspeed.com), downloaded from the mirror https://github.com/Shriinivas/cmubvh on
2026-10-25. CMU: "The data in this database may be used in any way you like"; the database asks that publications
cite it: *The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from
NSF EIA-0196217.* The conversion adds no restrictions. Index of the takes: `cmu-mocap-index-text.txt` in the mirror.

The first frame of every take is the T-pose calibration pose (skipped by `v03_mocap.load_bvh`). Unpacked `.bvh`
files are git-ignored; `tools/blender/character/v03_proto.py` unpacks what it needs.

| Take | Content | Used for |
|---|---|---|
| 16_15, 16_16, 16_21, 16_22, 16_31, 16_32, 35_01–03 | walk / brisk walk | Walk |
| 16_33, 16_34, 16_08, 16_57 | slow walk then stop, run/jog sudden stop | Stop (planned) |
| 16_17–20, 16_41–44 | walk / jog 90° left and right turns | Turn (planned) |
| 16_35, 16_36, 16_45, 16_46, 16_55, 35_17–19, 09_01–03, 141_01–03 | run / jog | Jog, Run |
| 77_*, 139_*, 140_* | (mirror labels) careful actions, sneaking, idle | crouch / ready (to be checked: the 77_* and 139_* files of the mirror are identical) |
