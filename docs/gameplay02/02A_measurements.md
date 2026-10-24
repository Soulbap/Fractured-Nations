# GAMEPLAY-02A measurements: assault scenarios before / after

`--combat02-test --only a_haugen,a_cover,a_two,a_three,a_limited,a_unfavourable,a_fortified`, world seeds 1, 2, 3 (every aim
error, spread and scatter depends on the seed), rifle squads only (`squad_composition` = riflemen), camera far away (abstract
tier), up to 900 simulated seconds per attack at x12. Table: `python tools/combat02_compare.py before.json after.json`.
"Clean withdrawal": the operation broke off by its own decision with at least 40 % of the attackers left. "Defender supp.":
mean suppression of the defenders over the run (CombatDiag). Each cell: before -> after.

## Committed version (iteration 4)

| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |
|---|---|---|---|---|---|---|---|---|
| a_cover | 0 -> 0 | 3 -> 3 | 0 -> 0 | 46% -> 51% | 12% -> 12% | 210 -> 170 | 0.007 -> 0.010 | 0.2% -> 0.2% |
| a_fortified | 3 -> 3 | 0 -> 0 | 0 -> 0 | 14% -> 21% | 100% -> 100% | 69 -> 20 | 0.117 -> 0.090 | 1.6% -> 1.2% |
| a_haugen | 1 -> 2 | 2 -> 1 | 0 -> 0 | 44% -> 33% | 58% -> 79% | 190 -> 160 | 0.023 -> 0.013 | 0.8% -> 1.3% |
| a_limited | 2 -> 3 | 0 -> 0 | 1 -> 0 | 39% -> 18% | 75% -> 100% | 110 -> 100 | 0.023 -> 0.063 | 3.0% -> 2.9% |
| a_three | 3 -> 2 | 0 -> 1 | 0 -> 0 | 31% -> 28% | 100% -> 71% | 110 -> 160 | 0.017 -> 0.017 | 18.1% -> 16.5% |
| a_two | 0 -> 0 | 3 -> 3 | 0 -> 0 | 48% -> 40% | 0% -> 21% | 180 -> 150 | 0.000 -> 0.003 | 0.0% -> 0.4% |
| a_unfavourable | 1 -> 1 | 1 -> 2 | 1 -> 0 | 38% -> 29% | 52% -> 33% | 251 -> 80 | 0.040 -> 0.023 | 2.5% -> 1.1% |
| **all** | 10 -> 11 | 9 -> 10 | 2 -> 0 | 37% -> 31% | 57% -> 60% | 251 -> 170 | 0.032 -> 0.031 | 3.7% -> 3.4% |

## Iterations (same seeds) - the spread between them is the noise of three seeds

Iteration 3 (before the support spread was narrowed):

| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |
|---|---|---|---|---|---|---|---|---|
| a_cover | 0 -> 1 | 3 -> 0 | 0 -> 2 | 46% -> 64% | 12% -> 50% | 210 -> 110 | 0.007 -> 0.033 | 0.2% -> 0.6% |
| a_fortified | 3 -> 3 | 0 -> 0 | 0 -> 0 | 14% -> 11% | 100% -> 100% | 69 -> 30 | 0.117 -> 0.083 | 1.6% -> 1.3% |
| a_haugen | 1 -> 3 | 2 -> 0 | 0 -> 0 | 44% -> 19% | 58% -> 100% | 190 -> 91 | 0.023 -> 0.023 | 0.8% -> 1.5% |
| a_limited | 2 -> 0 | 0 -> 3 | 1 -> 0 | 39% -> 47% | 75% -> 12% | 110 -> 160 | 0.023 -> 0.000 | 3.0% -> 0.7% |
| a_three | 3 -> 3 | 0 -> 0 | 0 -> 0 | 31% -> 15% | 100% -> 100% | 110 -> 110 | 0.017 -> 0.020 | 18.1% -> 24.9% |
| a_two | 0 -> 1 | 3 -> 2 | 0 -> 0 | 48% -> 25% | 0% -> 33% | 180 -> 70 | 0.000 -> 0.017 | 0.0% -> 0.8% |
| a_unfavourable | 1 -> 0 | 1 -> 3 | 1 -> 0 | 38% -> 29% | 52% -> 46% | 251 -> 100 | 0.040 -> 0.017 | 2.5% -> 1.6% |
| **all** | 10 -> 11 | 9 -> 8 | 2 -> 2 | 37% -> 30% | 57% -> 63% | 251 -> 160 | 0.032 -> 0.028 | 3.7% -> 4.5% |

Iteration 5 (assault aimed at the reported enemy instead of an objective spot - rejected, reverted):

| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |
|---|---|---|---|---|---|---|---|---|
| a_cover | 0 -> 3 | 3 -> 0 | 0 -> 0 | 46% -> 31% | 12% -> 100% | 210 -> 31 | 0.007 -> 0.027 | 0.2% -> 1.4% |
| a_fortified | 3 -> 2 | 0 -> 1 | 0 -> 0 | 14% -> 12% | 100% -> 96% | 69 -> 69 | 0.117 -> 0.100 | 1.6% -> 1.1% |
| a_haugen | 1 -> 2 | 2 -> 0 | 0 -> 1 | 44% -> 49% | 58% -> 100% | 190 -> 110 | 0.023 -> 0.023 | 0.8% -> 1.5% |
| a_limited | 2 -> 0 | 0 -> 3 | 1 -> 0 | 39% -> 50% | 75% -> 12% | 110 -> 100 | 0.023 -> 0.003 | 3.0% -> 0.6% |
| a_three | 3 -> 1 | 0 -> 0 | 0 -> 2 | 31% -> 43% | 100% -> 58% | 110 -> 90 | 0.017 -> 0.017 | 18.1% -> 4.4% |
| a_two | 0 -> 0 | 3 -> 3 | 0 -> 0 | 48% -> 38% | 0% -> 0% | 180 -> 70 | 0.000 -> 0.000 | 0.0% -> 0.0% |
| a_unfavourable | 1 -> 0 | 1 -> 3 | 1 -> 0 | 38% -> 38% | 52% -> 15% | 251 -> 80 | 0.040 -> 0.023 | 2.5% -> 0.5% |
| **all** | 10 -> 8 | 9 -> 10 | 2 -> 3 | 37% -> 37% | 57% -> 54% | 251 -> 110 | 0.032 -> 0.028 | 3.7% -> 1.4% |
