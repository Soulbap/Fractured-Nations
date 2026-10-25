"""VISUAL-03 staging: mirrors the shipped equipment and loadout resources into assets/characters/infantry_v03/.

An equipment .tres is mirrored when its glTF was rebuilt under the staging root (same relative path); its scene then
points at the staged glTF. Every loadout is mirrored with each item pointing at the staged equipment where there is
one, else at the shipped one (weapons, which live in weapon space and are shared).
    python tools/visual03/stage_loadouts.py
"""
import os
import re

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = "assets/characters/infantry/"
DST = "assets/characters/infantry_v03/"


def res_to_path(res):
    return os.path.join(REPO, res[len("res://"):].replace("/", os.sep))


def staged(res):
    """The staged counterpart of a res:// path under the shipped root, or None."""
    if not res.startswith("res://" + SRC):
        return None
    alt = "res://" + DST + res[len("res://" + SRC):]
    return alt if os.path.exists(res_to_path(alt)) else None


def main():
    n_eq = n_lo = 0
    for root, _, files in os.walk(os.path.normpath(os.path.join(REPO, SRC))):
        for f in files:
            if not f.endswith(".tres") or os.sep + "equipment" not in root:
                continue
            src = os.path.join(root, f)
            txt = open(src, encoding="utf-8").read()
            m = re.search(r'path="(res://[^"]+\.glb)"', txt)
            if not m:
                continue
            alt = staged(m.group(1))
            if alt is None:
                continue
            rel = os.path.relpath(src, os.path.normpath(os.path.join(REPO, SRC)))
            dst = os.path.join(REPO, DST, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(txt.replace(m.group(1), alt))
            n_eq += 1
    lo_dir = os.path.join(REPO, SRC, "loadouts")
    out_dir = os.path.join(REPO, DST, "loadouts")
    os.makedirs(out_dir, exist_ok=True)
    for f in sorted(os.listdir(lo_dir)):
        if not f.endswith(".tres"):
            continue
        txt = open(os.path.join(lo_dir, f), encoding="utf-8").read()

        def sub(m):
            alt = staged(m.group(1))
            return 'path="%s"' % (alt or m.group(1))
        txt = re.sub(r'path="(res://[^"]+/equipment/[^"]+\.tres)"', sub, txt)
        with open(os.path.join(out_dir, f), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(txt)
        n_lo += 1
    print("staged equipment", n_eq, "loadouts", n_lo)


if __name__ == "__main__":
    main()
