"""QA gate for the static asset pipeline, built on the blender-agent-skills scripts.

BLENDER-SKILLS-01. The skills live project-scoped in .claude/skills/ (MIT, EL4CTEO/blender-skills);
this module is the one place the pipeline imports them, so the rest of the build never depends
on their layout:

  * blender-asset-qa/scripts/qa_check.py      z-fighting, detached parts, normals, degenerate
                                              faces, duplicate verts, n-gons, scale, UVs
  * blender-game-optimization/scripts/mesh_stats.py   tris / materials / textures vs a budget
  * blender-asset-qa/scripts/review_shots.py  Workbench contact sheets (random colour per part)

Runs inside the build (the asset objects exist in the scene), on LOD0 of ONE asset at a time -
the collision boxes (COL_*) and markers are never included, they overlap on purpose. Each
check returns one plain dict the build stores in the asset's JSON sidecar ("qa") and in the
run's qa_report.json. Library-wide tolerances live in CHECK and may be adjusted per asset by
the builder (Asset.qa = {"eps": ..., "tol": ..., "accept": [...]}).
"""
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SKILLS = os.path.join(REPO, ".claude", "skills")
SCRIPTS = {
    "qa_check": os.path.join(SKILLS, "blender-asset-qa", "scripts"),
    "review_shots": os.path.join(SKILLS, "blender-asset-qa", "scripts"),
    "mesh_stats": os.path.join(SKILLS, "blender-game-optimization", "scripts"),
}

# Library-wide numbers. eps: coplanar distance that counts as z-fighting (the kit snaps parts
# to 1 cm, flat-coloured faces 2-5 mm apart are intended); tol: contact tolerance for detached
# parts (mounted parts - AC units on brackets, mirrors, lamps - sit up to 3 cm off their
# mount by design). Budget: the "pc" table of mesh_stats (tris, materials per asset, texture
# sizes) - LOD0 of a building is 2-5 k. uv: off - our UVs are world-scale box projections
# (overlap intended) and palette parts have point UVs (zero area) by design.
CHECK = {"profile": "game", "eps": 0.002, "tol": 0.03, "budget": "pc", "max_tris": 300000, "uv": False}

# Findings that are true of this library by design, reported as "accepted" instead of
# failing every asset: box-kit geometry has n-gons on flat faces (triangulated on export),
# kit boxes touch back to back (cheap, no bakes here).
ACCEPT_WARNING_PREFIXES = ("ngons", "n-gons", "hidden back-to-back faces")

_loaded = {}


def _skill(name):
    if name in _loaded:
        return _loaded[name]
    path = SCRIPTS[name]
    if not os.path.isdir(path):
        raise FileNotFoundError("blender-skills not installed: %s (run install/ or copy .claude/skills)" % path)
    if path not in sys.path:
        sys.path.insert(0, path)
    mod = importlib.import_module(name)
    importlib.reload(mod)
    _loaded[name] = mod
    return mod


def check_asset(asset, sheets_dir=None):
    """QA of one built ap_lib.Asset: {pass, errors, warnings, accepted, stats, sheet}."""
    lod0 = asset.objs[0] if asset.objs and asset.objs[0] is not None else None
    if lod0 is None:
        return {"pass": False, "errors": ["no LOD0 mesh"], "warnings": [], "accepted": [], "stats": {}}
    opts = dict(CHECK)
    opts.update(getattr(asset, "qa", None) or {})
    accept = tuple(ACCEPT_WARNING_PREFIXES) + tuple(opts.get("accept", ()))
    qa = _skill("qa_check").run(objects=[lod0.name], profile=opts["profile"], eps=opts["eps"], tol=opts["tol"],
                                no_modifiers=False, max_tris=opts["max_tris"], uv=opts["uv"])
    errors = list(qa.get("errors", []))
    warnings, accepted = [], []
    for w in qa.get("warnings", []):
        (accepted if w.startswith(accept) else warnings).append(w)
    # Vehicles and road sections sit with their wheels / undersides at z = 0 and the kit puts
    # foundations below ground on purpose: the ground warning is informational for us.
    warnings = [w for w in warnings if not w.startswith("asset lowest point")]
    st = _skill("mesh_stats").run(objects=[o.name for o in asset.objs if o is not None], budget=opts["budget"])
    per = st.get("objects", {})
    stats = {"tris": {n: p.get("tris") for n, p in per.items()}, "verts": {n: p.get("verts") for n, p in per.items()},
             "materials_per_lod": {n: p.get("materials") for n, p in per.items()},
             "draw_calls_est": st.get("draw_calls_est"), "texture_vram_mb_uncompressed": st.get("texture_vram_mb_uncompressed"),
             "budget": st.get("budget", {}).get("name"), "over_budget": st.get("budget", {}).get("over", [])}
    out = {"pass": not errors, "errors": errors, "warnings": warnings, "accepted": accepted,
           "ground_z": qa.get("ground_z"), "zfighting": qa.get("zfighting", []), "floating": qa.get("floating", []),
           "stats": stats, "eps": opts["eps"], "tol": opts["tol"]}
    if sheets_dir:
        sheets_dir = os.path.abspath(sheets_dir)  # review_shots resolves paths against the .blend (none here)
        os.makedirs(sheets_dir, exist_ok=True)
        sheet = _skill("review_shots").run(objects=[lod0.name], out=os.path.join(sheets_dir, asset.id + "_qa.png"),
                                           views=["front", "right", "top", "three_quarter"], mode="random", res=384)
        out["sheet"] = sheet.get("sheet")
        for v in sheet.get("views", []):  # the per-view PNGs are stitched into the sheet; keep one file per asset
            if v and os.path.exists(v) and v != sheet.get("sheet"):
                os.remove(v)
    return out


def _kinds(errors):
    """Error strings without their counts / coordinates: the same defect reported twice (a
    count that moved from 230 to 228 pairs) is still the same baseline finding."""
    import re
    return {re.sub(r"[-\d.]+", "#", e) for e in errors}


def new_findings(qa, baseline_entry):
    """Errors of this run that the recorded baseline for the asset does not already contain."""
    known = _kinds(baseline_entry.get("errors", [])) if baseline_entry else set()
    return [e for e in qa.get("errors", []) if re.sub(r"[-\d.]+", "#", e) not in known]


import re  # noqa: E402  (used by new_findings; kept at the end so the module reads top-down)
