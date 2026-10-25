"""VEHICLE-ASSETS-01: downloads the reference photographs of the vehicle pack from
Wikimedia Commons (freely licensed files only) into
assets/military/vehicles/_references/<vehicle>/ and writes a manifest per vehicle with
source page, licence, author and description. Photos are study material for modelling
only; nothing from them is copied into an asset.

    python tools/vehicle_assets/fetch_references.py [--only iveco_lmv,cv9030n]

Observations per vehicle (dimensions, variant decisions) live in the hand-written
`notes.md` next to each manifest; this script never touches them.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "assets", "military", "vehicles", "_references")
UA = {"User-Agent": "FracturedNationsRefFetch/1.0 (private game project reference research)"}
API = "https://commons.wikimedia.org/w/api.php"
WIDTH = 1280      # one of Wikimedia's standard thumbnail steps (others are rate limited)

REFS = {
    "iveco_lmv": [
        "Iveco LMV Norway Army.webp",
        "Norwegian Iveco LMV 02.jpg",
        "Norwegian Iveco LMV.jpg",
        "Norwegian soldiers in Faryab Province.jpg",
        "Norway Army - Iveco LMV . Norwegian Army Soldiers prepare to enter the vehicle mounted portion of the IED training course on Camp Griffin.webp",
        "DSC04918 Husar, PsyOps, Bundesheer, Rear Right, 2023-10.jpg",
        "Italian Army - VTLM2-NEC armored vehicle of the Pinerolo Brigade.jpg",
    ],
    "patria_6x6": [
        "Patria 6x6 APC.jpg",
        "Patria 6x6 MSPO23 IMG133345590 HDR.jpg",
        "Lippujuhlan päivän 2022 paraati 046 Patria 6x6 XA-300.JPG",
        "Lippujuhlan päivän 2022 paraati 047 Patria 6x6 XA-300.JPG",
        "Lippujuhlan päivän 2022 paraati 049 Patria 6x6 XA-300.JPG",
        "Kołowy transporter opancerzony Patria 6x6 łotewskich Narodowych Sił Zbrojnych (NBS)..jpg",
        "Kongsberg Protector RWS on M1126.jpg",
    ],
    "cv9030n": [
        "CV90 Mk IIIb IFV Norway.png",
        "CV90 Mk IIIb IFV Norway 2.png",
        "CV90 Mk IIIb Infantry Fighting Vehicle Norway.png",
        "CV90 Mk IIIb Infantry Fighting Vehicle Norway 2.png",
        "Norwegian CV9030N in snow.jpg",
        "Cv90afghanistan.jpg",
        "Norsk CV90.jpg",
        "Exercise Noble Jump 23 Tank, Engineer, Infantry, Medic Training - CV90 in Norwegian Army.webp",
    ],
    "scania_military": [
        "Scania XT R500 8x8 transport truck - Danish Army.png",
        "Scania XT R500 8x8 transport truck - Danish Army (2).png",
        "Scania XT R500 8x8 transport truck - Danish Army (3).png",
        "Scania G410 8x8 Hooklift Truck.jpg",
        "Scania G480 drawbar truck Finnish Defence Forces.jpg",
        "Militaire Scania XT onder de loep-6.jpg",
        "Netherlands - Scania truck with command A1 shelter.jpg",
    ],
    "leopard_2a8_nor": [
        "Leopard 2A8.jpg",
        "LEOPARD 2A8.jpg",
        "Leopard 2A8 with Trophy system.jpg",
        "Leopard 2A8 prototype.jpg",
        "Leopard 2A7 Trophy APS at NATO Days 2023.JPG",
        "Tank Leopard 2A7 NATO Days 2022.jpg",
    ],
    "nh90_tth": [
        "NHIndustries NH90 TTH French Army Air Corps EAD PAS 2013 01.jpg",
        "NHIndustries NH90 TTH French Army Air Corps EAD PAS 2013 04 tail rotor detail.jpg",
        "NH90 TTH German Army 79+36 at-ILA-2024.JPG",
        "NH90-TTH 79+15 static display ILA-2022.jpg",
        "78+31 German Army NHIndustries NH90 TTH ILA Berlin 2016 03.jpg",
        "78+31 German Army NHIndustries NH90 TTH ILA Berlin 2016 04.jpg",
        "78+31 German Army NHIndustries NH90 TTH ILA Berlin 2016 11.jpg",
        "NH90 NTH GNY 79+55 left side Rostock 2025.JPG",
        "Army of Finland NH90 helicopter NH-205 (4897964231).jpg",
        "NH90 (NH-211) Kokonaisturvallisuus 2015 06 door.JPG",
    ],
}


def _get(url, tries=5):
    for k in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except Exception as e:  # rate limits: back off
            if k == tries - 1:
                raise
            time.sleep(30 * (k + 1))


def _strip(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html or "")).strip()


def fetch(vehicle, titles):
    d = os.path.join(OUT, vehicle)
    os.makedirs(d, exist_ok=True)
    entries = []
    for i, t in enumerate(titles, 1):
        q = urllib.parse.urlencode({"action": "query", "titles": "File:" + t, "prop": "imageinfo", "format": "json",
                                    "iiprop": "url|extmetadata|size", "iiurlwidth": WIDTH})
        try:
            info = json.loads(_get(API + "?" + q))
        except Exception as e:
            entries.append({"title": t, "error": str(e)[:120]})
            print("FAILED", vehicle, t, e, flush=True)
            continue
        page = next(iter(info["query"]["pages"].values()))
        if "imageinfo" not in page:
            entries.append({"title": t, "error": "not found"})
            print("MISSING", vehicle, t, flush=True)
            continue
        ii = page["imageinfo"][0]
        md = ii.get("extmetadata", {})
        src = ii.get("thumburl") or ii["url"]
        ext = os.path.splitext(urllib.parse.urlparse(src).path)[1].lower() or ".jpg"
        name = "%02d_%s%s" % (i, re.sub(r"[^A-Za-z0-9]+", "_", os.path.splitext(t)[0])[:60].strip("_"), ext)
        path = os.path.join(d, name)
        if not os.path.exists(path):
            try:
                data = _get(src)
            except Exception as e:
                entries.append({"title": t, "error": str(e)[:120]})
                print("FAILED", vehicle, t, e, flush=True)
                continue
            with open(path, "wb") as f:
                f.write(data)
            time.sleep(8.0)
        entries.append({
            "file": name, "title": t, "source_page": ii.get("descriptionurl"), "original": ii["url"],
            "size": [ii.get("width"), ii.get("height")],
            "license": _strip(md.get("LicenseShortName", {}).get("value")),
            "author": _strip(md.get("Artist", {}).get("value"))[:200],
            "description": _strip(md.get("ImageDescription", {}).get("value"))[:400],
        })
        print("OK", vehicle, name, flush=True)
        time.sleep(1.0)
    with open(os.path.join(d, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"vehicle": vehicle, "source": "Wikimedia Commons", "images": entries}, f, indent=1, ensure_ascii=False)


def main():
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    for v, titles in REFS.items():
        if only is None or v in only:
            fetch(v, titles)


if __name__ == "__main__":
    main()
