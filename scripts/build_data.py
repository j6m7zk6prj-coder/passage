#!/usr/bin/env python3
"""
Télécharge le référentiel open data d'Île-de-France Mobilités et produit deux
fichiers compacts embarqués dans l'appli :

  Passages/Resources/stops.json  -> zones d'arrêt (nom, commune, coordonnées, lignes)
  Passages/Resources/lines.json  -> lignes (nom court, mode, couleurs officielles)

Lancé automatiquement par GitHub Actions avant chaque compilation.
"""
import json
import os
import sys
import urllib.request
from collections import defaultdict

BASE = "https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets/{}/exports/json?lang=fr&timezone=Europe%2FParis"
OUT = os.path.join(os.path.dirname(__file__), "..", "Passages", "Resources")


def fetch(dataset):
    url = BASE.format(dataset)
    print(f"↓ {dataset}", flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "Passages-iOS-build"})
    with urllib.request.urlopen(req, timeout=300) as r:
        data = json.load(r)
    rows = [row.get("fields", row) if isinstance(row, dict) else row for row in data]
    print(f"  {len(rows)} lignes · champs : {sorted(rows[0].keys()) if rows else '—'}", flush=True)
    return rows


def pick(row, *keys, default=None):
    for k in keys:
        v = row.get(k)
        if v not in (None, ""):
            return v
    return default


def last_id(value):
    """'IDFM:C01742' -> 'C01742', 'IDFM:monomodalStopPlace:43135' -> '43135'."""
    return str(value).strip().split(":")[-1]


def to_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    # --- Lignes ---------------------------------------------------------
    lines = {}
    for l in fetch("referentiel-des-lignes"):
        lid = pick(l, "id_line", "id")
        if not lid:
            continue
        lid = last_id(lid)
        mode = str(pick(l, "transportmode", default="bus")).lower()
        short = str(pick(l, "shortname_line", "name_line", default=lid))
        network = str(pick(l, "networkname", default="")).upper()
        if mode == "rail" and ("RER" in network or short in {"A", "B", "C", "D", "E"}):
            mode = "rer"
        status = str(pick(l, "status", default="active")).lower()
        if "inact" in status:
            continue
        bg = pick(l, "colourweb_hexa")
        fg = pick(l, "textcolourweb_hexa")
        lines[lid] = {
            "i": lid,
            "s": short,
            "n": str(pick(l, "name_line", default=short)),
            "m": mode,
            "bg": bg,
            "fg": fg,
        }

    # --- Relations quai (ArR) -> zone d'arrêt (ZdA) ----------------------
    arr_to_zda = {}
    try:
        for r in fetch("relations"):
            arr = pick(r, "arrid")
            zda = pick(r, "zdaid")
            if arr and zda:
                arr_to_zda[last_id(arr)] = last_id(zda)
    except Exception as e:  # noqa: BLE001
        print(f"  ⚠︎ relations indisponibles ({e}), on utilisera les quais.", flush=True)

    # --- Arrêts + lignes associées --------------------------------------
    groups = defaultdict(lambda: {"names": defaultdict(int), "city": "", "lats": [], "lons": [], "lines": set()})
    for a in fetch("arrets-lignes"):
        stop_id = str(pick(a, "stop_id", default=""))
        if not stop_id:
            continue
        if "monomodalStopPlace" in stop_id:
            ref = f"STIF:StopArea:SP:{last_id(stop_id)}:"
        else:
            arr = last_id(stop_id)
            zda = arr_to_zda.get(arr)
            ref = f"STIF:StopArea:SP:{zda}:" if zda else f"STIF:StopPoint:Q:{arr}:"

        lat = to_float(pick(a, "stop_lat"))
        lon = to_float(pick(a, "stop_lon"))
        if lat is None or lon is None:
            pg = a.get("pointgeo") or {}
            lat, lon = to_float(pg.get("lat")), to_float(pg.get("lon"))
        if lat is None or lon is None:
            continue

        g = groups[ref]
        g["names"][str(pick(a, "stop_name", default="Arrêt"))] += 1
        g["city"] = g["city"] or str(pick(a, "nom_commune", default=""))
        g["lats"].append(lat)
        g["lons"].append(lon)
        lid = pick(a, "id", "route_id")
        if lid:
            g["lines"].add(last_id(lid))

    used_lines = set()
    stops = []
    for ref, g in groups.items():
        line_ids = sorted(l for l in g["lines"] if l in lines)
        if not line_ids:
            continue
        used_lines.update(line_ids)
        name = max(g["names"].items(), key=lambda kv: kv[1])[0]
        stops.append({
            "r": ref,
            "n": name,
            "c": g["city"],
            "la": round(sum(g["lats"]) / len(g["lats"]), 6),
            "lo": round(sum(g["lons"]) / len(g["lons"]), 6),
            "l": line_ids,
        })

    stops.sort(key=lambda s: (s["n"], s["c"]))
    line_list = sorted((lines[l] for l in used_lines), key=lambda l: (l["m"], l["s"]))

    if len(stops) < 1000 or len(line_list) < 100:
        print(f"✗ Données incomplètes : {len(stops)} arrêts, {len(line_list)} lignes", file=sys.stderr)
        sys.exit(1)

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "stops.json"), "w", encoding="utf-8") as f:
        json.dump(stops, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(OUT, "lines.json"), "w", encoding="utf-8") as f:
        json.dump(line_list, f, ensure_ascii=False, separators=(",", ":"))
    print(f"✓ {len(stops)} arrêts, {len(line_list)} lignes écrits dans {os.path.abspath(OUT)}")


if __name__ == "__main__":
    main()
