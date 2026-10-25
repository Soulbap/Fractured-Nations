"""WORLD-VISUALS-01: downloads the CC0 source material of the Nordic environment from Poly Haven (polyhaven.com,
CC0 - no attribution required; authors are listed in the report anyway).

  python tools/blender/env/fetch_polyhaven.py [--only id,id] [--res 2k]

Everything lands in assets/environment/source/polyhaven/<id>/ (git-ignored, .gdignore: the raw scans are inputs of the
Blender builders, never loaded by the game). The builders (make_terrain_v3.py, make_trees_v3.py, make_props_v3.py) turn
them into the game textures and meshes that are committed.
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "assets", "environment", "source", "polyhaven")
UA = {"User-Agent": "FracturedNations-dev/1.0 (asset pipeline)"}

# Surface textures: diffuse, OpenGL normal, AO/rough/metal and displacement (height for Terrain3D blending).
TEXTURES = [
    "forest_floor", "forrest_ground_01", "forest_ground_04", "leaves_forest_ground", "mud_forest", "brown_mud_leaves_01",
    "sparse_grass", "leafy_grass", "withered_grass", "grass_path_2",
    "rock_face", "lichen_rock", "mossy_rock", "rock_pitted_mossy", "rocky_terrain_02", "aerial_rocks_02",
    "brown_mud", "dirt", "rocky_trail", "gravel_road", "gravelly_sand", "rocky_gravel",
    "pine_bark", "knotted_pine_bark", "bark_brown_02", "tree_bark_03",
]
TEX_MAPS = ("Diffuse", "nor_gl", "arm", "Displacement")
# Models whose textures only are needed (twig / needle atlases, bark): the meshes are millions of triangles.
MODEL_TEXTURES = {
    "fir_tree_01": ("twig_diff", "twig_alpha", "twig_nor_gl", "twig_arm", "bark_diff", "bark_nor_gl", "bark_arm"),
    "pine_tree_01": None,  # keys discovered at run time (twig / bark maps)
    "fir_sapling": None,
    "pine_sapling_small": None,
    "grass_medium_01": None,
    "shrub_01": None, "shrub_02": None, "shrub_03": None, "shrub_04": None,
}
# Models downloaded whole (glTF + textures): rocks, deadwood, small plants.
MODELS = [
    "rock_moss_set_01", "rock_moss_set_02", "boulder_01", "rock_07", "rock_09", "stone_01", "namaqualand_boulder_02",
    "tree_stump_01", "tree_stump_02", "dead_tree_trunk", "dead_tree_trunk_02", "dry_branches_medium_01", "bark_debris_01",
    "fern_02", "moss_01", "nettle_plant", "root_cluster_01", "pine_roots",
]


def get(url, path=None, tries=4):
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            if path:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(data)
            return data
        except Exception as e:  # noqa: BLE001 - network: retry with back-off
            print("retry", url, e)
            time.sleep(2 + 3 * k)
    raise RuntimeError("download failed: " + url)


def files_of(aid):
    return json.loads(get("https://api.polyhaven.com/files/" + aid).decode("utf-8"))


def pick(entry, res):
    """entry: {res: {fmt: {url, size}}} -> url (jpg preferred, png next) at res or the nearest lower one."""
    order = [res] + [r for r in ("4k", "2k", "1k") if r != res]
    for r in order:
        if r in entry:
            for fmt in ("jpg", "png"):
                if fmt in entry[r]:
                    return entry[r][fmt]["url"]
    return None


def fetch_texture(aid, res):
    files = files_of(aid)
    for m in TEX_MAPS:
        if m not in files:
            continue
        url = pick(files[m], res)
        dst = os.path.join(OUT, aid, os.path.basename(url))
        if not os.path.exists(dst):
            get(url, dst)
            print("got", dst)


def fetch_model_textures(aid, keys, res):
    files = files_of(aid)
    if keys is None:
        keys = [k for k in files if any(w in k for w in ("twig", "bark", "leaf", "leaves", "branch", "needle", "grass", "blade"))
                and any(k.endswith(s) for s in ("_diff", "_alpha", "_nor_gl", "_arm", "_opacity", "_mask"))]
    for k in keys:
        if k not in files:
            continue
        url = pick(files[k], res)
        dst = os.path.join(OUT, aid, os.path.basename(url))
        if not os.path.exists(dst):
            get(url, dst)
            print("got", dst)


def fetch_model(aid, res):
    files = files_of(aid)
    g = files["gltf"].get(res) or files["gltf"]["2k"] if "gltf" in files else None
    if g is None:
        print("no gltf", aid)
        return
    g = g["gltf"]
    base = os.path.join(OUT, aid)
    dst = os.path.join(base, os.path.basename(g["url"]))
    if not os.path.exists(dst):
        get(g["url"], dst)
    for rel, inc in g.get("include", {}).items():
        p = os.path.join(base, rel)
        if not os.path.exists(p):
            get(inc["url"], p)
    print("got model", aid)


def main():
    argv = sys.argv[1:]
    res = "2k"
    only = None
    for i, a in enumerate(argv):
        if a == "--res":
            res = argv[i + 1]
        elif a == "--only":
            only = set(argv[i + 1].split(","))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, ".gdignore"), "w", encoding="utf-8") as f:
        f.write("")
    for aid in TEXTURES:
        if not only or aid in only:
            fetch_texture(aid, res)
    for aid, keys in MODEL_TEXTURES.items():
        if not only or aid in only:
            fetch_model_textures(aid, keys, res)
    for aid in MODELS:
        if not only or aid in only:
            fetch_model(aid, res)
    # Licence / authors record for the report.
    info = {}
    for aid in TEXTURES + list(MODEL_TEXTURES) + MODELS:
        if only and aid not in only:
            continue
        d = json.loads(get("https://api.polyhaven.com/info/" + aid).decode("utf-8"))
        info[aid] = {"name": d.get("name"), "authors": d.get("authors"), "licence": "CC0"}
    with open(os.path.join(OUT, "sources.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
