"""Final table: both DEMs, smoothed like a bike feels the road, plus road composition."""
import json, sys
import numpy as np, rasterio, pyarrow.parquet as pq
from shapely import wkb
from shapely.geometry import Point
from shapely import STRtree
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import find_climbs as fc
import terrain_tiles as demmod

LAT, LON = 57.65612, 11.96150
COP = [rasterio.open("cop30.tif"), rasterio.open("cop30_e012.tif")]
z = np.load("dem.npz"); TERR = demmod.DEM(z["grid"], int(z["px0"]), int(z["py0"]), int(z["z"]))

def cop(la, lo):
    v = float(list((COP[0] if lo < 12.0 else COP[1]).sample([(lo, la)]))[0][0])
    return float("nan") if v < -1000 else v

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

def smooth(e, win=7):                      # ~60 m at 10 m sampling
    k = np.ones(win) / win
    return np.convolve(np.pad(e, (win // 2, win // 2), mode="edge"), k, mode="valid")[: len(e)]

def stats(d, e):
    e = smooth(e)
    g = lambda w: np.array([(e[j] - e[i]) / (d[j] - d[i]) for i in range(len(d))
                            for j in [int(np.searchsorted(d, d[i] + w))] if j < len(d)] or [0.0])
    g200, g100 = g(200), g(100)
    return dict(length=float(d[-1]), gain=float(e[-1] - e[0]),
                grade=float((e[-1] - e[0]) / d[-1] * 100),
                steady=float((g200 >= 0.03).mean()), worst200=float(g200.min() * 100),
                max100=float(g100.max() * 100), bottom=float(e[0]), top=float(e[-1]))

# road composition
t = pq.read_table("molndal_segments.parquet")
segs = [(wkb.loads(g), n, c) for s, c, n, g in zip(
    t.column("subtype").to_pylist(), t.column("class").to_pylist(),
    t.column("names").combine_chunks().field("primary").to_pylist(),
    t.column("geometry").to_pylist()) if s == "road"]

TREE = STRtree([s[0] for s in segs])

def compose(coords):
    runs, total = [], 0.0
    for (la1, lo1), (la2, lo2) in zip(coords, coords[1:]):
        p = Point((lo1 + lo2) / 2, (la1 + la2) / 2)
        best = segs[int(TREE.nearest(p))]
        d = fc.haversine(la1, lo1, la2, lo2); total += d
        name = best[1] or f"({best[2]})"
        if runs and runs[-1][0] == name:
            runs[-1][1] += d
        else:
            runs.append([name, d])
    return runs, total

rows = json.load(open("out/final.json"))
out = []
for r in rows:
    coords = [tuple(c) for c in r["coords"]]
    dc, ec = sample(coords, cop)
    dt, et = sample(coords, lambda la, lo: TERR.at(la, lo))
    sc, st = stats(dc, ec), stats(dt, et)
    runs, total = compose(coords)
    named = sum(d for n, d in runs if not n.startswith("("))
    out.append(dict(cop=sc, terr=st, roads=[[n, round(d)] for n, d in runs if d > 20],
                    named_pct=round(named / total * 100), dist=r["dist"],
                    start=r["start"], end=r["end"], coords=r["coords"],
                    mean_grade=(sc["grade"] + st["grade"]) / 2,
                    agree=abs(sc["grade"] - st["grade"]),
                    steady=min(sc["steady"], st["steady"]),
                    real_step=min(sc["max100"], st["max100"])))

for r in out:
    match = fc.score_climb(r["cop"]["length"], r["mean_grade"] / 100, 1000.0, 0.05)
    penalty_step = 1.0 if r["real_step"] < 12 else 0.55       # both DEMs see a wall
    r["score"] = match * (0.35 + 0.65 * r["steady"]) * max(0.4, 1 - r["agree"] / 3) * penalty_step
out.sort(key=lambda r: -r["score"])
json.dump(out, open("out/final2.json", "w"), indent=1)

print(f"{'#':>2} {'score':>5} {'len':>5} {'gain':>5} {'cop%':>5} {'terr%':>5} {'steady':>6} "
      f"{'wrst200':>7} {'max100':>6} {'named':>5} {'fromEH':>6}")
for i, r in enumerate(out[:10], 1):
    c = r["cop"]
    print(f"{i:>2} {r['score']:>5.1f} {c['length']:>5.0f} {c['gain']:>5.1f} {c['grade']:>5.2f} "
          f"{r['terr']['grade']:>5.2f} {r['steady']*100:>5.0f}% {c['worst200']:>6.1f}% "
          f"{r['real_step']:>5.1f}% {r['named_pct']:>4}% {r['dist']:>5}m")
    print(f"    {'  '.join(f'{n} {d}m' for n, d in r['roads'][:5])}")
    print(f"    {c['bottom']:.0f}→{c['top']:.0f} m | start {r['start'][0]:.5f},{r['start'][1]:.5f}"
          f" | end {r['end'][0]:.5f},{r['end'][1]:.5f}")
