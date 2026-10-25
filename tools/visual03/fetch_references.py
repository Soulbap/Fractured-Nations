"""VISUAL-03 reference collection from Wikimedia Commons (public-domain / free-licensed only).

Searches Commons per topic, keeps files whose licence is public domain, CC0, CC BY or CC BY-SA,
downloads a ~1000 px rendition into docs/visual03/references/<topic>/ and writes
candidates.json (title, page URL, licence, author, description) for the reference index.
    python tools/visual03/fetch_references.py [--topics a,b] [--per 6]
Selection and the written index are done by hand afterwards (docs/visual03/references/INDEX.md).
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "visual03", "references")
API = "https://commons.wikimedia.org/w/api.php"
UA = "FN-visual03-research/1.0 (game reference collection; contact soulbap@gmail.com)"
ANY_LICENCE = False
OK_LICENCES = ("public domain", "pd", "cc0", "cc by", "cc-by")

TOPICS = {
    "01_anatomy": ["Muybridge man standing", "anthropometry photograph man front side",
                   "human skeleton anterior view illustration", "Gray's anatomy skeleton lateral"],
    "02_pelvis_hip_knee": ["Gray pelvis anterior male", "Gray femur anterior", "hip joint anatomy illustration",
                           "knee joint anatomy anterior Gray"],
    "03_uniform_gear": ["soldier plate carrier OCP 2023", "infantry soldier helmet plate carrier exercise 2022",
                        "Norwegian Army soldier exercise", "soldier combat uniform equipment rifle 2024"],
    "04_standing": ["soldier standing with rifle", "soldiers standing formation rifle field", "soldier at ease rifle"],
    "05_walking": ["Muybridge man walking", "soldiers foot patrol walking rifle", "soldiers dismounted patrol"],
    "06_running": ["Muybridge man running", "soldier running with rifle", "soldiers rush rifle training"],
    "07_aiming_firing": ["soldier aiming rifle standing", "soldier fires M4 carbine standing range",
                         "soldier firing rifle standing position"],
    "08_crouching": ["soldier kneeling rifle security", "soldier crouching rifle", "soldier kneeling firing position"],
    "09_turning_stopping": ["Muybridge turning around", "Muybridge man walking turning", "Muybridge stopping"],
}

# Second pass (VISUAL-03, after the first selection): weak topics, any licence (private reference use).
EXTRA = {
    "03_uniform_gear": ["soldier plate carrier full body", "Marines plate carrier helmet rifle training 2023",
                        "soldier Multicam plate carrier helmet exercise", "Bundeswehr soldier Flecktarn exercise rifle"],
    "04_standing": ["soldier stands guard rifle", "soldier stands security rifle full body", "Marine stands with rifle",
                    "Muybridge man standing turning"],
    "05_walking": ["rbm-QP301M8 walking rifle", "soldiers walk patrol rifle side view", "Muybridge man walking side"],
    "06_running": ["rbm-QP301M8 running rifle", "soldier sprints rifle", "soldiers run rifle combat training",
                   "Muybridge man running side"],
    "07_aiming_firing": ["soldier standing firing M4 range side view", "Marine fires rifle standing"],
    "08_crouching": ["soldiers move crouched rifle", "soldier crouch walk rifle"],
    "09_turning_stopping": ["rbm-QP301M8 man turning", "rbm-QP301M8 walking turning around man",
                            "Muybridge man turning around running", "soldier turning rifle"],
}


def get(params, tries=4):
    url = API + "?" + urllib.parse.urlencode(params)
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:      # rate limit / transient
            time.sleep(3 * (i + 1))
            err = e
    raise err


def strip(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html or "")).strip()


def search(q, per):
    d = get({"action": "query", "format": "json", "generator": "search", "gsrnamespace": 6, "gsrlimit": per * 2,
             "gsrsearch": q + " filetype:bitmap", "prop": "imageinfo", "iiprop": "url|size|extmetadata",
             "iiurlwidth": 1000})
    out = []
    for p in d.get("query", {}).get("pages", {}).values():
        ii = p["imageinfo"][0]
        md = ii.get("extmetadata", {})
        lic = md.get("LicenseShortName", {}).get("value", "")
        if not ANY_LICENCE and not any(lic.lower().startswith(k) for k in OK_LICENCES):
            continue
        out.append({"title": p["title"], "page": ii.get("descriptionurl"), "thumb": ii.get("thumburl"),
                    "size": [ii["width"], ii["height"]], "licence": lic,
                    "author": strip(md.get("Artist", {}).get("value", ""))[:160],
                    "description": strip(md.get("ImageDescription", {}).get("value", ""))[:400],
                    "query": q})
    return out[:per]


def main():
    args = sys.argv[1:]
    topics = list(TOPICS)
    per = 6
    global ANY_LICENCE
    table = TOPICS
    if "--extra" in args:
        table, ANY_LICENCE = EXTRA, True
        topics = list(EXTRA)
    for a in args:
        if a.startswith("--topics="):
            topics = a.split("=", 1)[1].split(",")
        if a.startswith("--per="):
            per = int(a.split("=", 1)[1])
    for t in [x for x in topics if x in table]:
        d = os.path.join(ROOT, t)
        os.makedirs(d, exist_ok=True)
        cj = os.path.join(d, "candidates.json")
        cands = json.load(open(cj, encoding="utf-8")) if os.path.exists(cj) else []
        seen = {c["title"] for c in cands}
        for q in table[t]:
            for c in search(q, per):
                if c["title"] in seen:
                    continue
                seen.add(c["title"])
                name = re.sub(r"[^A-Za-z0-9._-]+", "_", c["title"][5:])[:90]
                name = os.path.splitext(name)[0] + ".jpg"
                path = os.path.join(d, name)
                if not os.path.exists(path):
                    req = urllib.request.Request(c["thumb"], headers={"User-Agent": UA})
                    try:
                        with urllib.request.urlopen(req, timeout=60) as r, open(path, "wb") as fh:
                            fh.write(r.read())
                    except Exception as e:
                        print("download failed", c["title"], e)
                        continue
                    time.sleep(1.0)
                c["file"] = name
                cands.append(c)
            time.sleep(1.5)
        with open(cj, "w", encoding="utf-8") as fh:
            json.dump(cands, fh, indent=1, ensure_ascii=False)
        print(t, len(cands))


if __name__ == "__main__":
    main()
