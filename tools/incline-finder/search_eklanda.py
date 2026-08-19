"""Climbs near Eklanda Hage, ranked by how steadily they climb - not just by average grade."""
import sys, math, json
import numpy as np
import pyarrow.parquet as pq
from shapely import wkb

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import find_climbs as fc
import terrain_tiles as demmod

LAT, LON = 57.65612, 11.96150
RADIUS_M = 4000
SPACING = 25.0
ROAD = {"primary", "secondary", "tertiary", "residential", "living_street",
        "unclassified", "service", "cycleway"}          # ridable tarmac only

class Args:
    lat, lon = LAT, LON
    target_length, target_grade = 1000.0, 0.05
    min_length, max_length = 700.0, 1800.0
    min_grade, max_drop = 0.035, 6.0
    smooth_m = 80.0
    top, max_walks, max_walks_per_start = 400, 30000, 300
    max_steps_per_start, max_total_steps = 3000, 40000000

z = np.load("dem.npz")
DEM = demmod.DEM(z["grid"], int(z["px0"]), int(z["py0"]), int(z["z"]))

def profile(graph, nodes, step=20.0):
    """Distance/elevation profile resampled every `step` metres, read from the DEM."""
    pts = [graph.coord[n] for n in nodes]
    dist, elev, cum = [0.0], [DEM.at(*pts[0])], 0.0
    for (la1, lo1), (la2, lo2) in zip(pts, pts[1:]):
        d = fc.haversine(la1, lo1, la2, lo2)
        n = max(1, int(d // step))
        for k in range(1, n + 1):
            f = k / n
            la, lo = la1 + (la2 - la1) * f, lo1 + (lo2 - lo1) * f
            dist.append(cum + d * f); elev.append(DEM.at(la, lo))
        cum += d
    return np.array(dist), np.array(elev)

def steadiness(dist, elev, window=200.0):
    """(fraction of the climb pulling >=3%, worst 200 m stretch) - exposes false flats."""
    grades = []
    for i in range(len(dist)):
        j = int(np.searchsorted(dist, dist[i] + window))
        if j < len(dist):
            grades.append((elev[j] - elev[i]) / (dist[j] - dist[i]))
    if not grades:
        return 0.0, 0.0
    g = np.array(grades)
    return float((g >= 0.03).mean()), float(g.min())

def main():
    args = Args()
    t = pq.read_table("molndal_segments.parquet")
    subs = t.column("subtype").to_pylist(); classes = t.column("class").to_pylist()
    names = t.column("names").combine_chunks().field("primary").to_pylist()
    geoms = t.column("geometry").to_pylist()

    graph, ways, node_id, kept = fc.Graph(), {}, {}, 0
    def node_for(la, lo):
        k = (round(la * 1e6), round(lo * 1e6))
        if k not in node_id:
            node_id[k] = len(node_id) + 1
            graph.coord[node_id[k]] = (la, lo)
        return node_id[k]

    for i, (sub, cls, name, g) in enumerate(zip(subs, classes, names, geoms)):
        if sub != "road" or cls not in ROAD:
            continue
        pts = list(wkb.loads(g).coords)
        if len(pts) < 2 or fc.haversine(LAT, LON, pts[0][1], pts[0][0]) > RADIUS_M + 600:
            continue
        chain, acc = [pts[0]], 0.0
        for a, b in zip(pts, pts[1:]):
            acc += fc.haversine(a[1], a[0], b[1], b[0])
            if acc >= SPACING or b is pts[-1]:
                chain.append(b); acc = 0.0
        ids = [node_for(p[1], p[0]) for p in chain]
        for a, b in zip(ids, ids[1:]):
            if a != b:
                graph.add_edge(a, b, fc.haversine(*graph.coord[a], *graph.coord[b]), name or cls)
        ways[i] = ids; kept += 1

    print(f"[graph] {kept:,} tarmac segments -> {len(graph.coord):,} nodes")
    for nid, (la, lo) in graph.coord.items():
        e = DEM.at(la, lo)
        if not math.isnan(e):
            graph.elev[nid] = e
    fc.smooth_elevations(graph, ways, args.smooth_m)

    raw = fc.find_climbs(graph, args)
    climbs = fc.dedupe(raw, limit=args.top, overlap=0.35)
    climbs = [c for c in climbs if fc.haversine(LAT, LON, *graph.coord[c.nodes[0]]) <= RADIUS_M]
    print(f"[search] {len(raw):,} candidates -> {len(climbs)} distinct routes")

    rows = []
    for c in climbs:
        d, e = profile(graph, c.nodes)
        frac, worst = steadiness(d, e)
        # a climb that is 1 km at 5 % but flat for 300 m of it is not the climb we want
        rank = c.score * (0.4 + 0.6 * frac)
        rows.append((rank, frac, worst, c))
    rows.sort(key=lambda r: -r[0])

    print(f"\n{'#':>2} {'rank':>5} {'len':>5} {'gain':>5} {'avg%':>5} {'steady':>6} {'worst200':>8} "
          f"{'dist_EH':>7}  roads")
    for i, (rank, frac, worst, c) in enumerate(rows[:25], 1):
        s = graph.coord[c.nodes[0]]
        print(f"{i:>2} {rank:>5.1f} {c.length:>5.0f} {c.gain:>5.1f} {c.grade*100:>5.2f} "
              f"{frac*100:>5.0f}% {worst*100:>7.1f}% {fc.haversine(LAT,LON,*s):>6.0f}m  "
              f"{', '.join(c.names[:4])}")
    json.dump([{ "rank": i, "score": round(rank,1), "length_m": round(c.length),
                 "gain_m": round(c.gain,1), "avg_grade_pct": round(c.grade*100,2),
                 "steady_pct": round(frac*100), "worst_200m_pct": round(worst*100,1),
                 "roads": c.names, "start": graph.coord[c.nodes[0]], "end": graph.coord[c.nodes[-1]],
                 "dist_from_eklanda_m": round(fc.haversine(LAT,LON,*graph.coord[c.nodes[0]])),
                 "coords": [[round(graph.coord[n][0],6), round(graph.coord[n][1],6)] for n in c.nodes]}
               for i,(rank,frac,worst,c) in enumerate(rows[:25],1)],
              open("out/ranked.json","w"), indent=1)
    fc.write_outputs(graph, [r[3] for r in rows[:15]], "out2")

main()
