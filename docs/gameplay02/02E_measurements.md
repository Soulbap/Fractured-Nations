# GAMEPLAY-02E measurements: the assault series with the new weapons

Same seven scenarios and world seeds (1, 2, 3) as `02A_measurements.md`, camera far away. `e_*` = both sides in the
standard composition (six riflemen, a machine gunner, a grenadier with grenades and two rockets; everybody one grenade);
`a_*` = riflemen only (each with one grenade - the role table gives every rifleman one). Each cell: left -> right.

## Rifle squads against standard squads, both on the final code

| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |
|---|---|---|---|---|---|---|---|---|
| a_haugen | 3 -> 3 | 0 -> 0 | 0 -> 0 | 21% -> 36% | 100% -> 100% | 100 -> 90 | 0.030 -> 0.047 | 2.0% -> 1.5% |
| a_cover | 3 -> 2 | 0 -> 1 | 0 -> 0 | 33% -> 36% | 100% -> 100% | 90 -> 100 | 0.050 -> 0.077 | 1.2% -> 1.4% |
| a_two | 1 -> 2 | 2 -> 1 | 0 -> 0 | 35% -> 27% | 62% -> 67% | 160 -> 80 | 0.007 -> 0.040 | 1.0% -> 1.3% |
| a_three | 1 -> 2 | 1 -> 1 | 1 -> 0 | 35% -> 25% | 54% -> 67% | 160 -> 149 | 0.023 -> 0.023 | 8.3% -> 17.3% |
| a_limited | 2 -> 2 | 1 -> 1 | 0 -> 0 | 25% -> 24% | 54% -> 79% | 100 -> 150 | 0.033 -> 0.030 | 2.0% -> 4.0% |
| a_unfavourable | 0 -> 0 | 3 -> 3 | 0 -> 0 | 25% -> 33% | 2% -> 4% | 70 -> 80 | 0.003 -> 0.030 | 0.2% -> 0.3% |
| a_fortified | 3 -> 3 | 0 -> 0 | 0 -> 0 | 12% -> 10% | 50% -> 100% | 30 -> 60 | 0.110 -> 0.097 | 0.7% -> 1.1% |
| **all** | 13 -> 14 | 7 -> 7 | 1 -> 0 | 27% -> 27% | 60% -> 74% | 160 -> 150 | 0.037 -> 0.049 | 2.2% -> 3.8% |

## The whole milestone: before GAMEPLAY-02 (rifles, old coordination) against standard squads on the final code

| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |
|---|---|---|---|---|---|---|---|---|
| a_cover | 0 -> 2 | 3 -> 1 | 0 -> 0 | 46% -> 36% | 12% -> 100% | 210 -> 100 | 0.007 -> 0.077 | 0.2% -> 1.4% |
| a_fortified | 3 -> 3 | 0 -> 0 | 0 -> 0 | 14% -> 10% | 100% -> 100% | 69 -> 60 | 0.117 -> 0.097 | 1.6% -> 1.1% |
| a_haugen | 1 -> 3 | 2 -> 0 | 0 -> 0 | 44% -> 36% | 58% -> 100% | 190 -> 90 | 0.023 -> 0.047 | 0.8% -> 1.5% |
| a_limited | 2 -> 2 | 0 -> 1 | 1 -> 0 | 39% -> 24% | 75% -> 79% | 110 -> 150 | 0.023 -> 0.030 | 3.0% -> 4.0% |
| a_three | 3 -> 2 | 0 -> 1 | 0 -> 0 | 31% -> 25% | 100% -> 67% | 110 -> 149 | 0.017 -> 0.023 | 18.1% -> 17.3% |
| a_two | 0 -> 2 | 3 -> 1 | 0 -> 0 | 48% -> 27% | 0% -> 67% | 180 -> 80 | 0.000 -> 0.040 | 0.0% -> 1.3% |
| a_unfavourable | 1 -> 0 | 1 -> 3 | 1 -> 0 | 38% -> 33% | 52% -> 4% | 251 -> 80 | 0.040 -> 0.030 | 2.5% -> 0.3% |
| **all** | 10 -> 14 | 9 -> 7 | 2 -> 0 | 37% -> 27% | 57% -> 74% | 251 -> 150 | 0.032 -> 0.049 | 3.7% -> 3.8% |

## Rifles at 02A (iteration 4, 2bb1ab5) against rifles on the final code (now with one grenade each, grenade reactions and the 02B-02D behaviour)

| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |
|---|---|---|---|---|---|---|---|---|
| a_haugen | 2 -> 3 | 1 -> 0 | 0 -> 0 | 33% -> 21% | 79% -> 100% | 160 -> 100 | 0.013 -> 0.030 | 1.3% -> 2.0% |
| a_cover | 0 -> 3 | 3 -> 0 | 0 -> 0 | 51% -> 33% | 12% -> 100% | 170 -> 90 | 0.010 -> 0.050 | 0.2% -> 1.2% |
| a_two | 0 -> 1 | 3 -> 2 | 0 -> 0 | 40% -> 35% | 21% -> 62% | 150 -> 160 | 0.003 -> 0.007 | 0.4% -> 1.0% |
| a_three | 2 -> 1 | 1 -> 1 | 0 -> 1 | 28% -> 35% | 71% -> 54% | 160 -> 160 | 0.017 -> 0.023 | 16.5% -> 8.3% |
| a_limited | 3 -> 2 | 0 -> 1 | 0 -> 0 | 18% -> 25% | 100% -> 54% | 100 -> 100 | 0.063 -> 0.033 | 2.9% -> 2.0% |
| a_unfavourable | 1 -> 0 | 2 -> 3 | 0 -> 0 | 29% -> 25% | 33% -> 2% | 80 -> 70 | 0.023 -> 0.003 | 1.1% -> 0.2% |
| a_fortified | 3 -> 3 | 0 -> 0 | 0 -> 0 | 21% -> 12% | 100% -> 50% | 20 -> 30 | 0.090 -> 0.110 | 1.2% -> 0.7% |
| **all** | 11 -> 13 | 10 -> 7 | 0 -> 1 | 31% -> 27% | 60% -> 60% | 170 -> 160 | 0.031 -> 0.037 | 3.4% -> 2.2% |
