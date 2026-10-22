"""Checksum manifest for a reference world (PROJECT-CONSOLIDATION-01).

The generated world data (worlds/ref_*/ except world_config.tres, scenes/world/ref_*.tscn)
is git-ignored (about 2.4 GB). This tool records every file of a world with its size,
SHA-256 and role, so a copy can be checked against the canonical version and an
unintended change is noticed. The manifest itself is small and committed.

    python tools/terrain_ref/world_manifest.py create [--world ref_20km] [--root .] [--out PATH]
    python tools/terrain_ref/world_manifest.py verify [--world ref_20km] [--root .] [--manifest PATH]
                                                      [--ignore-editor-metadata]

`verify` exits 0 when every file matches, 1 otherwise (missing, changed or extra files are
listed). Godot rewrites *.import files when it imports (role "editor_metadata");
--ignore-editor-metadata leaves them out of the comparison.

Roles:
  config           worlds/<id>/world_config.tres (tracked in git; tools/build_world.gd re-saves it)
  source           generator output, tools/terrain_ref/generate.py (geography: heights, control
                   and colour maps, roads, water, sites, vegetation and info maps, stats)
  preview          generator previews (not read by the game)
  analysis         tools/terrain_ref/analyze.py output (playability)
  generated        tools/build_world.gd + ReferenceWorldBuilder (Terrain3D regions, vegetation
                   chunks, water meshes, terrain assets/material, the world scene); the scene is
                   also edited by tools/terrain_ref/rebuild_structures.gd (bridges, culverts)
  editor_metadata  *.import files written by the Godot importer
Standard library only (runs with any Python 3, e.g. Blender's bundled one).
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

SOURCE = {"height.r32", "control.r32", "color.rgba8", "roads.json", "water.json", "sites.json",
          "vegetation.png", "info.png", "generation_stats.json", "macro_height.npy"}
PREVIEW = {"preview_macro.png", "preview_height.png"}
ANALYSIS = {"playability.json", "playability_map.png", "playability_regions.png"}
GENERATOR_FILES = ["tools/terrain_ref", "tools/build_world.gd", "scripts/world/reference_world_builder.gd",
                   "scripts/world/reference_terrain_generator.gd", "scripts/world/reference_world_config.gd"]


def role_of(rel, world):
    name = rel.rsplit("/", 1)[-1]
    if name.endswith(".import"):
        return "editor_metadata"
    if rel == "worlds/%s/world_config.tres" % world:
        return "config"
    if rel.startswith("worlds/%s/source/" % world):
        if name in SOURCE:
            return "source"
        if name in PREVIEW:
            return "preview"
        if name in ANALYSIS:
            return "analysis"
        return "source"
    return "generated"


def world_files(root, world):
    out = []
    base = os.path.join(root, "worlds", world)
    for d, _dirs, files in os.walk(base):
        for f in files:
            out.append(os.path.relpath(os.path.join(d, f), root).replace("\\", "/"))
    scene = "scenes/world/%s.tscn" % world
    if os.path.exists(os.path.join(root, scene)):
        out.append(scene)
    return sorted(out)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 22), b""):
            h.update(block)
    return h.hexdigest()


def read_config(root, world):
    cfg = {}
    path = os.path.join(root, "worlds", world, "world_config.tres")
    if os.path.exists(path):
        text = open(path, encoding="utf-8").read()
        for key in ("world_name", "world_size_m", "vertex_spacing", "region_size", "world_seed", "base_height",
                    "source_directory"):
            m = re.search(r"^%s = (.+)$" % key, text, re.M)
            if m:
                v = m.group(1).strip().strip('"')
                try:
                    v = float(v) if "." in v else int(v)
                except ValueError:
                    pass
                cfg[key] = v
    return cfg


def git(root, *args):
    try:
        return subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def create(a):
    files = world_files(a.root, a.world)
    if not files:
        sys.exit("no files for world %s under %s" % (a.world, a.root))
    cfg = read_config(a.root, a.world)
    entries = []
    for rel in files:
        p = os.path.join(a.root, rel)
        entries.append({"path": rel, "size": os.path.getsize(p), "sha256": sha256(p), "role": role_of(rel, a.world)})
    roles = {}
    for e in entries:
        r = roles.setdefault(e["role"], {"files": 0, "bytes": 0})
        r["files"] += 1
        r["bytes"] += e["size"]
    size = cfg.get("world_size_m")
    man = {
        "manifest_version": 1,
        "world_id": a.world,
        "created_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "created_from": os.path.abspath(a.root).replace("\\", "/"),
        "repository_commit": git(a.root, "rev-parse", "HEAD"),
        "generator_last_change": git(a.root, "log", "-1", "--format=%H %s", "--", *GENERATOR_FILES),
        "dimensions_m": [size, size] if size else None,
        "config": cfg,
        "provenance": a.note or "",
        "roles": roles,
        "totals": {"files": len(entries), "bytes": sum(e["size"] for e in entries)},
        "files": entries,
    }
    out = a.out or os.path.join(a.root, "worlds", "%s.manifest.json" % a.world)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(man, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("MANIFEST %s: %d files, %d bytes -> %s" % (a.world, len(entries), man["totals"]["bytes"], out))


def verify(a):
    path = a.manifest or os.path.join(a.root, "worlds", "%s.manifest.json" % a.world)
    man = json.load(open(path, encoding="utf-8"))
    skip = {"editor_metadata"} if a.ignore_editor_metadata else set()
    want = {e["path"]: e for e in man["files"] if e["role"] not in skip}
    have = {rel for rel in world_files(a.root, man["world_id"]) if role_of(rel, man["world_id"]) not in skip}
    missing = sorted(set(want) - have)
    extra = sorted(have - set(want))
    changed = []
    for rel in sorted(set(want) & have):
        p = os.path.join(a.root, rel)
        e = want[rel]
        if os.path.getsize(p) != e["size"] or sha256(p) != e["sha256"]:
            changed.append(rel)
    for label, items in (("MISSING", missing), ("CHANGED", changed), ("EXTRA", extra)):
        for rel in items:
            print("%s %s" % (label, rel))
    ok = not (missing or changed or extra)
    print("VERIFY %s %s: %d files checked, %d missing, %d changed, %d extra" % (
        man["world_id"], "OK" if ok else "FAILED", len(want), len(missing), len(changed), len(extra)))
    sys.exit(0 if ok else 1)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("create", "verify"):
        s = sub.add_parser(name)
        s.add_argument("--world", default="ref_20km")
        s.add_argument("--root", default=".")
        if name == "create":
            s.add_argument("--out")
            s.add_argument("--note", help="provenance text stored in the manifest")
        else:
            s.add_argument("--manifest")
            s.add_argument("--ignore-editor-metadata", action="store_true")
    a = p.parse_args()
    create(a) if a.cmd == "create" else verify(a)


if __name__ == "__main__":
    main()
