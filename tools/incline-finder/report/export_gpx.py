"""GPX + GeoJSON for the shortlisted climbs, elevations from Copernicus GLO-30."""
import json, os, sys
import rasterio
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))
import find_climbs as fc

COP = [rasterio.open("cop30.tif"), rasterio.open("cop30_e012.tif")]
def cop(la, lo):
    return float(list((COP[0] if lo < 12.0 else COP[1]).sample([(lo, la)]))[0][0])

rows = json.load(open("out/final2.json"))
PICKS = [(5, "sisjovagen"), (2, "toltorpsgatan-sodermalmsgatan"), (1, "tunnlandsgatan-dirigentgatan"),
         (3, "krokslattsgatan"), (0, "askims-svedjevag")]
os.makedirs("climbs", exist_ok=True)
features = []
for rank, (idx, slug) in enumerate(PICKS, 1):
    r = rows[idx]
    coords = [tuple(c) for c in r["coords"]]
    label = " → ".join(n for n, _ in r["roads"][:4])
    grade = (r["cop"]["grade"] + r["terr"]["grade"]) / 2
    with open(f"climbs/{rank}_{slug}.gpx", "w") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="incline-finder" '
                 'xmlns="http://www.topografix.com/GPX/1/1">\n<trk>\n'
                 f'<name>{label} — {r["cop"]["length"]:.0f} m @ {grade:.1f}%</name>\n<trkseg>\n')
        for la, lo in coords:
            fh.write(f'<trkpt lat="{la:.6f}" lon="{lo:.6f}"><ele>{cop(la, lo):.1f}</ele></trkpt>\n')
        fh.write("</trkseg>\n</trk>\n</gpx>\n")
    features.append({"type": "Feature", "properties": {
        "rank": rank, "roads": label, "length_m": round(r["cop"]["length"]),
        "gain_m": round(r["cop"]["gain"], 1), "grade_pct": round(grade, 2),
        "steady_pct": round(r["steady"] * 100), "from_eklanda_m": r["dist"]},
        "geometry": {"type": "LineString",
                     "coordinates": [[lo, la, round(cop(la, lo), 1)] for la, lo in coords]}})
json.dump({"type": "FeatureCollection", "features": features}, open("climbs/climbs.geojson", "w"))
print("\n".join(sorted(os.listdir("climbs"))))
