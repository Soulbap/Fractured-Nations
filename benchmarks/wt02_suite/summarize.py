"""Prints a markdown table from fast-suite bench JSON files (WORLD-TECH-02)."""
import json, sys, glob, os
rows = []
for path in sys.argv[1:]:
    d = json.load(open(path, encoding="utf-8"))
    for sc, r in d["scenarios"].items():
        st = r["stations"]
        def f(k):
            v = st.get(k)
            return "%.1f (%.1f)" % (v["avg"], v["p99"]) if v and "avg" in v else "-"
        def g(k):
            v = st.get(k)
            return "%.1f" % v["gpu_ms"]["avg"] if v and "avg" in v else "-"
        veg = st.get("rts_600m", {}).get("vegetation", {})
        vegf = st.get("fps_center", {}).get("vegetation", {})
        jump = r.get("jumps", {}).get("max_ms", float("nan"))
        sw = r.get("switch", {})
        rows.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            d["tag"], d["machine"]["driver"], sc, f("fps_center"), g("fps_center"), f("fps_far_corner"), f("rts_150m"), f("rts_600m"), f("strategic"),
            "%.1f" % jump, "%.1f / %s" % (sw.get("worst_ms", float("nan")), sw.get("worst_settle_frames", "-")) if "worst_ms" in sw else "-",
            vegf.get("active_mmis", "-"), veg.get("active_mmis", "-"),
            r["resources"]["multimesh_instance_nodes"], "%.0f" % r["resources"]["video_mem_mb"]))
print("| Run | Driver | Scenario | FPS center ms (p99) | GPU ms | FPS far corner | RTS 150 m | RTS 600 m | Strategic | Jump max ms | Switch max ms / settle frames | Active MMIs at FPS | Active MMIs at RTS 600 | MMIs total | VRAM MB |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
print("\n".join(rows))
