"""GAMEPLAY-02A: before / after table of the --combat02-test assault series (benchmarks/raw/gameplay02/*.json).

    python tools/combat02_compare.py benchmarks/raw/gameplay02/combat02_before.json benchmarks/raw/gameplay02/combat02_after.json
    python tools/combat02_compare.py rifles.json standard.json --map a_=e_   (02E: the same scenarios, a_* against e_*)

Per scenario and in total over all seeds: objectives taken, clean withdrawals (decided by the operation with >= 40 % of the
attackers left), other outcomes (wiped out, stalled), mean attacker and defender losses, the longest assault without
progress, the mean suppression the attackers put on the defenders and the attackers' hit rate (CombatDiag).
"""
import json
import sys


def load(path, prefix="a_"):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    return {"a_" + k[len(prefix):]: v for k, v in d.items() if k.startswith(prefix) and isinstance(v, dict) and "detail" in v}


def stats(series):
    runs = series["detail"]
    n = max(len(runs), 1)
    won = sum(1 for r in runs if r["won"])
    clean = sum(1 for r in runs if not r["won"] and "withdraw" in r["stages"] and r["attackers_left"] / r["attackers"] >= 0.4)
    att_loss = sum(1 - r["attackers_left"] / r["attackers"] for r in runs) / n
    def_loss = sum(1 - r["defenders_left"] / r["defenders"] for r in runs) / n
    stall = max((r["max_stall_s"] for r in runs), default=0)
    supp = sum(r["diag"].get("def_supp_avg", 0) for r in runs) / n
    acc = sum(r["diag"].get("att_accuracy", 0) for r in runs) / n
    t = sum(r["diag"].get("duration_s", 0) for r in runs if r["won"]) / max(won, 1)
    return {"n": len(runs), "won": won, "clean": clean, "other": len(runs) - won - clean, "att_loss": att_loss, "def_loss": def_loss,
            "stall": stall, "supp": supp, "acc": acc, "t_win": t}


def main():
    prefix = "a_"
    if "--map" in sys.argv:
        prefix = sys.argv[sys.argv.index("--map") + 1].split("=")[1]
    a, b = load(sys.argv[1]), load(sys.argv[2], prefix)
    keys = [k for k in a if k in b]
    print("| scenario | taken | clean withdrawal | other | attacker losses | defender losses | longest stall s | defender supp. | hit rate |")
    print("|---|---|---|---|---|---|---|---|---|")
    tot = {"before": [], "after": []}
    for k in keys:
        sa, sb = stats(a[k]), stats(b[k])
        tot["before"].append(sa)
        tot["after"].append(sb)
        print("| %s | %d -> %d | %d -> %d | %d -> %d | %.0f%% -> %.0f%% | %.0f%% -> %.0f%% | %d -> %d | %.3f -> %.3f | %.1f%% -> %.1f%% |" % (
            k, sa["won"], sb["won"], sa["clean"], sb["clean"], sa["other"], sb["other"], sa["att_loss"] * 100, sb["att_loss"] * 100,
            sa["def_loss"] * 100, sb["def_loss"] * 100, sa["stall"], sb["stall"], sa["supp"], sb["supp"], sa["acc"] * 100, sb["acc"] * 100))
    def agg(lst):
        n = len(lst)
        return {"won": sum(s["won"] for s in lst), "clean": sum(s["clean"] for s in lst), "other": sum(s["other"] for s in lst),
                "att_loss": sum(s["att_loss"] for s in lst) / n, "def_loss": sum(s["def_loss"] for s in lst) / n,
                "stall": max(s["stall"] for s in lst), "supp": sum(s["supp"] for s in lst) / n, "acc": sum(s["acc"] for s in lst) / n}
    x, y = agg(tot["before"]), agg(tot["after"])
    print("| **all** | %d -> %d | %d -> %d | %d -> %d | %.0f%% -> %.0f%% | %.0f%% -> %.0f%% | %d -> %d | %.3f -> %.3f | %.1f%% -> %.1f%% |" % (
        x["won"], y["won"], x["clean"], y["clean"], x["other"], y["other"], x["att_loss"] * 100, y["att_loss"] * 100, x["def_loss"] * 100,
        y["def_loss"] * 100, x["stall"], y["stall"], x["supp"], y["supp"], x["acc"] * 100, y["acc"] * 100))


if __name__ == "__main__":
    main()
