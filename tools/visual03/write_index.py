"""Writes docs/visual03/references/INDEX.md from index_header.md + every topic's candidates.json."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "docs", "visual03", "references")
lines = [open(os.path.join(HERE, "index_header.md"), encoding="utf-8").read()]
for t in sorted(os.listdir(ROOT)):
    cj = os.path.join(ROOT, t, "candidates.json")
    if not os.path.exists(cj):
        continue
    lines.append(f"\n### {t}\n\n| File | Source | Licence | Author | Shows |\n|---|---|---|---|---|")
    for c in json.load(open(cj, encoding="utf-8")):
        desc = c["description"].replace("|", "/")[:180] or c["title"][5:]
        lines.append(f"| [{c['file'][:60]}]({t}/{c['file']}) | [Commons]({c['page']}) | {c['licence']} | "
                     f"{c['author'].replace('|', '/')[:60]} | {desc} |")
with open(os.path.join(ROOT, "INDEX.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("ok")
