"""Per-climb profile data for the report page."""
import json, sys
import numpy as np, rasterio
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))
import find_climbs as fc
import terrain_tiles as demmod

LAT, LON = 57.65612, 11.96150
COP = [rasterio.open("cop30.tif"), rasterio.open("cop30_e012.tif")]
z = np.load("dem.npz"); TERR = demmod.DEM(z["grid"], int(z["px0"]), int(z["py0"]), int(z["z"]))
def cop(la, lo):
    return float(list((COP[0] if lo < 12.0 else COP[1]).sample([(lo, la)]))[0][0])

def sample(coords, f, step=10.0):
    d, e, cum = [0.0], [f(*coords[0])], 0.0
    for (la1, lo1), (la2, lo2) in zip(coords, coords[1:]):
        dist = fc.haversine(la1, lo1, la2, lo2)
        n = max(1, int(dist // step))
        for k in range(1, n + 1):
            t = k / n
            d.append(cum + dist * t); e.append(f(la1 + (la2 - la1) * t, lo1 + (lo2 - lo1) * t))
        cum += dist
    return np.array(d), np.array(e)

def smooth(e, win=7):
    k = np.ones(win) / win
    return np.convolve(np.pad(e, (win // 2, win // 2), mode="edge"), k, mode="valid")[: len(e)]

rows = json.load(open("out/final2.json"))
PICKS = [
    (5, "Sisjövägen", "Datavägen/Knapegårdsvägen junction", "crest above Sisjön"),
    (2, "Toltorpsgatan → Södermalmsgatan", "Toltorpsdalen", "Södermalmsbrinken / Konstnärsgatan"),
    (1, "Tunnlandsgatan → Dirigentgatan", "Tvärhandsgatan junction, Högsbo", "Dirigentgatan, Flatås"),
    (3, "Krokslättsgatan", "Fabriksgatan, Krokslätts Fabriker", "Klintegatan / Krokslätts Storgata"),
    (0, "Askims Svedjeväg → Högabergsvägen", "Askims Granstig", "Hällstigen, Hovås"),
]
out = []
for rank, (idx, name, bottom, top) in enumerate(PICKS, 1):
    r = rows[idx]
    coords = [tuple(c) for c in r["coords"]]
    dc, ec = sample(coords, cop); dt, et = sample(coords, lambda la, lo: TERR.at(la, lo))
    ecs, ets = smooth(ec), smooth(et)
    # per-100 m gradient bands, averaged over the two DEMs
    bands = []
    for x in np.arange(0, dc[-1] - 50, 100):
        i = int(np.searchsorted(dc, x)); j = int(np.searchsorted(dc, x + 100))
        j = min(j, len(dc) - 1)
        if j > i:
            gc = (ecs[j] - ecs[i]) / (dc[j] - dc[i])
            k = int(np.searchsorted(dt, x)); l = min(int(np.searchsorted(dt, x + 100)), len(dt) - 1)
            gt = (ets[l] - ets[k]) / (dt[l] - dt[k]) if l > k else gc
            bands.append([round(float(x)), round(float((gc + gt) / 2 * 100), 1)])
    out.append(dict(
        rank=rank, name=name, bottom_label=bottom, top_label=top,
        roads=[[n, d] for n, d in r["roads"]],
        length=round(r["cop"]["length"]), gain=round((r["cop"]["gain"] + r["terr"]["gain"]) / 2, 1),
        grade=round((r["cop"]["grade"] + r["terr"]["grade"]) / 2, 2),
        grade_cop=round(r["cop"]["grade"], 2), grade_terr=round(r["terr"]["grade"], 2),
        steady=round(r["steady"] * 100), dist=r["dist"],
        bottom_m=round(r["cop"]["bottom"]), top_m=round(r["cop"]["top"]),
        start=r["start"], end=r["end"],
        prof_cop=[[round(float(x)), round(float(y), 1)] for x, y in zip(dc[::3], ecs[::3])],
        prof_terr=[[round(float(x)), round(float(y), 1)] for x, y in zip(dt[::3], ets[::3])],
        bands=bands, coords=r["coords"]))
json.dump(dict(centre=[LAT, LON], climbs=out), open("out/report.json", "w"))
for c in out:
    print(f"{c['rank']}. {c['name']:36s} {c['length']:>4} m  {c['grade']:.2f}%  "
          f"{c['gain']:.0f} m  {c['dist']}m away  {len(c['bands'])} bands")
