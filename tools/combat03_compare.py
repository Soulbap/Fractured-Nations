"""GAMEPLAY-03: before / after table of the --combat03-test defence series (benchmarks/raw/gameplay03/*.json).

    python tools/combat03_compare.py benchmarks/raw/gameplay03/combat03_before.json benchmarks/raw/gameplay03/combat03_b.json

Per scenario (averages over the seeds, from the summary the suite writes): bases taken, attacker and defender losses, when
and at what distance the attackers first saw a defender, defender soldier-seconds seen by an attacker, defender
soldier-seconds inside the capture radius, post changes, fortification slots given up, deepest defence line, seconds the
objective was contested.
"""
import json
import sys

COLS = [("taken", "taken", "%d"), ("att_loss", "attacker losses", "%.0f%%"), ("def_loss", "defender losses", "%.0f%%"),
        ("att_seen_d", "first seen at m", "%.0f"), ("att_seen_t", "first seen at s", "%.0f"), ("def_exposed_s", "defenders seen s", "%.0f"),
        ("def_inside_s", "inside radius s", "%.0f"), ("def_post_changes", "post changes", "%.0f"), ("def_slots_left", "slots given up", "%.1f"),
        ("def_line_max", "deepest line", "%.1f"), ("contested_s", "contested s", "%.0f")]


def load(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    return {k: v["summary"] for k, v in d.items() if k.startswith("d_") and isinstance(v, dict) and "summary" in v}


def fmt(c, v):
    if v is None:
        return "-"
    if c[2].endswith("%%"):
        return c[2] % (v * 100.0)
    return c[2] % v


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    print("| scenario | " + " | ".join(c[1] for c in COLS) + " |")
    print("|---|" + "---|" * len(COLS))
    for k in a:
        if k not in b:
            continue
        cells = ["%s -> %s" % (fmt(c, a[k].get(c[0])), fmt(c, b[k].get(c[0]))) for c in COLS]
        print("| %s (%d runs) | %s |" % (k, b[k].get("runs", 0), " | ".join(cells)))


if __name__ == "__main__":
    main()
