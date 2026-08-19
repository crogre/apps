#!/usr/bin/env python3
"""Find the best sustained climb near a point, using OpenStreetMap + a DEM.

Defaults are tuned for the question "where is a ~1 km / ~5 % incline near
Eklanda Hage, Mölndal?" but every knob is a flag.

Data sources (both free, no API key):
  * road/path network : Overpass API (OpenStreetMap)
  * elevations        : OpenTopoData (default dataset EU-DEM 25 m, covers Sweden)

Pure standard library. Network results are cached under --cache-dir, so a second
run costs nothing.

    python3 find_climbs.py                    # Eklanda Hage, 4 km radius
    python3 find_climbs.py --radius-km 6 --profile road
    python3 find_climbs.py --self-test        # offline check of the algorithm
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

# Eklanda Hage, Mölndal (residential area west of Mölndal centrum).
DEFAULT_LAT = 57.6605
DEFAULT_LON = 11.9740

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
OPENTOPODATA_URL = "https://api.opentopodata.org/v1/{dataset}"
OPENTOPODATA_BATCH = 100          # locations per request (public API limit)
OPENTOPODATA_SLEEP = 1.05         # public API allows 1 call/second

# Which highway values each profile is willing to ride.
PROFILES = {
    "road": (
        "primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|"
        "unclassified|residential|living_street|service"
    ),
    "bike": (
        "primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|"
        "unclassified|residential|living_street|service|cycleway|path|track"
    ),
    "all": (
        "primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|"
        "unclassified|residential|living_street|service|cycleway|path|track|"
        "footway|pedestrian|bridleway"
    ),
}

R_EARTH = 6371008.8


# --------------------------------------------------------------------------- #
# geometry helpers
# --------------------------------------------------------------------------- #
def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R_EARTH * math.asin(math.sqrt(a))


# --------------------------------------------------------------------------- #
# data acquisition
# --------------------------------------------------------------------------- #
def http_post(url: str, data: bytes, timeout: int) -> bytes:
    req = urllib.request.Request(
        url, data=data, headers={"User-Agent": "incline-finder/1.0 (OSM climb search)"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def http_get(url: str, timeout: int) -> bytes:
    req = urllib.request.Request(
        url, headers={"User-Agent": "incline-finder/1.0 (OSM climb search)"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def fetch_osm(lat: float, lon: float, radius_m: int, profile: str, cache: str) -> dict:
    """Download the highway network around (lat, lon)."""
    path = os.path.join(cache, f"osm_{lat:.5f}_{lon:.5f}_{radius_m}_{profile}.json")
    if os.path.exists(path):
        with open(path) as fh:
            return json.load(fh)

    query = (
        "[out:json][timeout:180];"
        f'way(around:{radius_m},{lat},{lon})["highway"~"^({PROFILES[profile]})$"]'
        '["area"!~"yes"]["access"!~"^(private|no)$"];'
        "(._;>;);out body;"
    )
    body = urllib.parse.urlencode({"data": query}).encode()

    last_err: Exception | None = None
    for endpoint in OVERPASS_ENDPOINTS:
        try:
            print(f"[osm] querying {endpoint} ...", file=sys.stderr)
            raw = http_post(endpoint, body, timeout=240)
            data = json.loads(raw)
            os.makedirs(cache, exist_ok=True)
            with open(path, "w") as fh:
                json.dump(data, fh)
            return data
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as err:
            last_err = err
            print(f"[osm] {endpoint} failed: {err}", file=sys.stderr)
    raise SystemExit(f"all Overpass endpoints failed: {last_err}")


def fetch_elevations(
    points: list[tuple[float, float]], dataset: str, cache: str
) -> dict[tuple[float, float], float]:
    """Elevation (m) for each (lat, lon), cached on disk between runs."""
    path = os.path.join(cache, f"dem_{dataset}.json")
    store: dict[str, float] = {}
    if os.path.exists(path):
        with open(path) as fh:
            store = json.load(fh)

    def key(pt: tuple[float, float]) -> str:
        return f"{pt[0]:.6f},{pt[1]:.6f}"

    missing = [p for p in points if key(p) not in store]
    if missing:
        calls = math.ceil(len(missing) / OPENTOPODATA_BATCH)
        print(
            f"[dem] {len(missing)} new points -> {calls} API calls "
            f"(~{calls * OPENTOPODATA_SLEEP / 60:.1f} min; free quota is 1000 calls/day)",
            file=sys.stderr,
        )
        for i in range(0, len(missing), OPENTOPODATA_BATCH):
            batch = missing[i : i + OPENTOPODATA_BATCH]
            locs = "|".join(f"{la:.6f},{lo:.6f}" for la, lo in batch)
            url = OPENTOPODATA_URL.format(dataset=dataset) + "?" + urllib.parse.urlencode(
                {"locations": locs, "interpolation": "bilinear"}
            )
            for attempt in range(4):
                try:
                    payload = json.loads(http_get(url, timeout=120))
                    if payload.get("status") != "OK":
                        raise RuntimeError(payload.get("error", payload))
                    for pt, res in zip(batch, payload["results"]):
                        elev = res.get("elevation")
                        if elev is not None:
                            store[key(pt)] = float(elev)
                    break
                except Exception as err:  # noqa: BLE001 - retry any transport error
                    wait = 2 ** attempt
                    print(f"[dem] batch failed ({err}); retry in {wait}s", file=sys.stderr)
                    time.sleep(wait)
            else:
                raise SystemExit("elevation lookups kept failing; try again later")
            time.sleep(OPENTOPODATA_SLEEP)
            done = min(i + OPENTOPODATA_BATCH, len(missing))
            print(f"[dem] {done}/{len(missing)}", end="\r", file=sys.stderr)
        os.makedirs(cache, exist_ok=True)
        with open(path, "w") as fh:
            json.dump(store, fh)
        print(file=sys.stderr)

    return {p: store[key(p)] for p in points if key(p) in store}


# --------------------------------------------------------------------------- #
# graph construction
# --------------------------------------------------------------------------- #
@dataclass
class Graph:
    coord: dict[int, tuple[float, float]] = field(default_factory=dict)
    elev: dict[int, float] = field(default_factory=dict)
    # node -> list of (neighbour, distance_m, way_name)
    adj: dict[int, list[tuple[int, float, str]]] = field(default_factory=dict)

    def add_edge(self, a: int, b: int, dist: float, name: str) -> None:
        self.adj.setdefault(a, []).append((b, dist, name))
        self.adj.setdefault(b, []).append((a, dist, name))


def thin_way(nodes: list[int], coord: dict[int, tuple[float, float]], spacing: float) -> list[int]:
    """Drop intermediate nodes closer together than `spacing` metres."""
    if len(nodes) <= 2:
        return nodes
    kept = [nodes[0]]
    acc = 0.0
    for prev, cur in zip(nodes, nodes[1:]):
        acc += haversine(*coord[prev], *coord[cur])
        if acc >= spacing:
            kept.append(cur)
            acc = 0.0
    if kept[-1] != nodes[-1]:
        kept.append(nodes[-1])
    return kept


def build_graph(osm: dict, spacing: float, keep_nodes: set[int] | None = None) -> tuple[Graph, dict[int, list[int]]]:
    """Turn an Overpass response into a graph; also return way -> node list."""
    coord = {
        el["id"]: (el["lat"], el["lon"]) for el in osm["elements"] if el["type"] == "node"
    }
    graph = Graph(coord={})
    ways: dict[int, list[int]] = {}

    # Junctions must survive thinning, so count node usage across ways first.
    usage: dict[int, int] = {}
    raw_ways = [el for el in osm["elements"] if el["type"] == "way" and len(el.get("nodes", [])) > 1]
    for way in raw_ways:
        for nid in way["nodes"]:
            usage[nid] = usage.get(nid, 0) + 1

    for way in raw_ways:
        nodes = [n for n in way["nodes"] if n in coord]
        if len(nodes) < 2:
            continue
        junctions = {n for n in nodes if usage.get(n, 0) > 1}
        # Thin, but never drop a junction or an endpoint.
        thinned, acc = [nodes[0]], 0.0
        for prev, cur in zip(nodes, nodes[1:]):
            acc += haversine(*coord[prev], *coord[cur])
            if acc >= spacing or cur in junctions or cur == nodes[-1]:
                thinned.append(cur)
                acc = 0.0
        name = way.get("tags", {}).get("name") or way.get("tags", {}).get("highway", "way")
        ways[way["id"]] = thinned
        for nid in thinned:
            graph.coord[nid] = coord[nid]
        for a, b in zip(thinned, thinned[1:]):
            graph.add_edge(a, b, haversine(*coord[a], *coord[b]), name)
    return graph, ways


def smooth_elevations(graph: Graph, ways: dict[int, list[int]], window_m: float) -> None:
    """Moving average along each way: DEM noise otherwise invents fake ramps."""
    if window_m <= 0:
        return
    sums: dict[int, list[float]] = {}
    for nodes in ways.values():
        nodes = [n for n in nodes if n in graph.elev]
        if len(nodes) < 3:
            continue
        cum = [0.0]
        for a, b in zip(nodes, nodes[1:]):
            cum.append(cum[-1] + haversine(*graph.coord[a], *graph.coord[b]))
        for i, nid in enumerate(nodes):
            lo = hi = i
            while lo > 0 and cum[i] - cum[lo - 1] <= window_m / 2:
                lo -= 1
            while hi < len(nodes) - 1 and cum[hi + 1] - cum[i] <= window_m / 2:
                hi += 1
            avg = sum(graph.elev[nodes[j]] for j in range(lo, hi + 1)) / (hi - lo + 1)
            sums.setdefault(nid, []).append(avg)
    for nid, vals in sums.items():
        graph.elev[nid] = sum(vals) / len(vals)


# --------------------------------------------------------------------------- #
# climb search
# --------------------------------------------------------------------------- #
@dataclass
class Climb:
    nodes: list[int]
    length: float
    gain: float          # net gain, end minus start
    ascent: float        # summed positive deltas
    names: list[str]
    score: float = 0.0

    @property
    def grade(self) -> float:
        return self.gain / self.length if self.length else 0.0


def contract(graph: Graph) -> dict[int, list[tuple[int, list[int], float]]]:
    """Collapse degree-2 chains: search over junctions, not every vertex."""
    deg = {n: len(set(nb for nb, _, _ in adj)) for n, adj in graph.adj.items()}
    junctions = {n for n, d in deg.items() if d != 2}
    if not junctions:                       # a lone ring road
        junctions = {next(iter(graph.adj))}
    chains: dict[int, list[tuple[int, list[int], float]]] = {j: [] for j in junctions}
    for j in junctions:
        for first, dist, _ in graph.adj[j]:
            path, total, prev, cur = [j, first], dist, j, first
            while cur not in junctions:
                nxt = [(n, d) for n, d, _ in graph.adj[cur] if n != prev]
                if not nxt:
                    break
                n, d = nxt[0]
                path.append(n)
                total += d
                prev, cur = cur, n
            chains[j].append((path[-1], path, total))
    return chains


def score_climb(length: float, grade: float, t_len: float, t_grade: float) -> float:
    """0-100 similarity to the target climb; tolerant on length, strict on grade."""
    if length <= 0 or grade <= 0:
        return 0.0
    len_term = math.exp(-(((length - t_len) / (0.60 * t_len)) ** 2))
    grade_term = math.exp(-(((grade - t_grade) / (0.45 * t_grade)) ** 2))
    return 100.0 * len_term * grade_term


def best_window(graph: Graph, nodes: list[int], args) -> Climb | None:
    """Best-scoring sub-stretch of a walked path.

    A climb rarely starts and ends exactly at a junction, so the walk gives us a
    corridor and this picks the stretch inside it that best matches the target.
    """
    pts = [n for n in nodes if n in graph.elev]
    if len(pts) < 2:
        return None
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + haversine(*graph.coord[a], *graph.coord[b]))
    if cum[-1] < args.min_length:
        return None

    best: Climb | None = None
    j = 0
    for i in range(len(pts) - 1):
        j = max(j, i + 1)
        while j < len(pts) and cum[j] - cum[i] < args.min_length:
            j += 1
        k = j
        while k < len(pts) and cum[k] - cum[i] <= args.max_length:
            length = cum[k] - cum[i]
            gain = graph.elev[pts[k]] - graph.elev[pts[i]]
            grade = gain / length if length else 0.0
            if grade >= args.min_grade:
                s = score_climb(length, grade, args.target_length, args.target_grade)
                if best is None or s > best.score:
                    seg = pts[i:k + 1]
                    best = Climb(nodes=seg, length=length, gain=gain,
                                 ascent=total_ascent(graph, seg), names=[], score=s)
            k += 1
    return best


def find_climbs(graph: Graph, args) -> list[Climb]:
    """Walk uphill corridors over the contracted graph, then trim each to its best window."""
    chains = contract(graph)
    # Work outward from the point of interest, so a capped sweep spends its budget
    # on the neighbourhood that was actually asked about.
    starts = sorted(chains, key=lambda n: haversine(args.lat, args.lon, *graph.coord[n]))
    # One corridor per (start, end) pair - a grid of streets otherwise yields
    # exponentially many zig-zags that all trim to the same climb.
    walks: dict[tuple[int, int], tuple[float, list[int], list[str]]] = {}
    total_steps = 0

    for start in starts:
        if start not in graph.elev:
            continue
        # stack items: (node, path nodes, length, highest elevation so far, road names)
        stack = [(start, [start], 0.0, graph.elev[start], [])]
        from_start = steps = 0
        while stack:
            steps += 1
            total_steps += 1
            if steps >= args.max_steps_per_start or from_start >= args.max_walks_per_start:
                break
            if total_steps >= args.max_total_steps:
                print("[search] step budget exhausted; raise --max-total-steps for a wider sweep",
                      file=sys.stderr)
                break
            node, path, length, peak, names = stack.pop()
            for nxt, seg_nodes, seg_len in chains.get(node, []):
                if nxt in path or nxt not in graph.elev:
                    continue
                new_len = length + seg_len
                if new_len > args.max_length:
                    continue
                z = graph.elev[nxt]
                new_peak = max(peak, z)
                if z < new_peak - args.max_drop:      # a real descent: that is two climbs
                    continue
                body = seg_nodes[1:] if seg_nodes[0] == node else list(reversed(seg_nodes))[1:]
                new_path = path + body
                name = chain_name(graph, seg_nodes)
                new_names = names + [name] if name and name not in names else names
                gain = z - graph.elev[new_path[0]]
                if new_len >= args.min_length and gain > 0:
                    key = (new_path[0], nxt)
                    if gain > walks.get(key, (0.0,))[0]:
                        walks[key] = (gain, new_path, new_names)
                        from_start += 1
                stack.append((nxt, new_path, new_len, new_peak, new_names))

        if total_steps >= args.max_total_steps:
            break

    ranked = sorted(walks.values(), key=lambda w: w[0], reverse=True)
    out: list[Climb] = []
    for gain, path, names in ranked[: args.max_walks]:
        climb = best_window(graph, path, args)
        if climb:
            climb.names = names
            out.append(climb)
    out.sort(key=lambda c: c.score, reverse=True)
    return out


def chain_name(graph: Graph, seg_nodes: list[int]) -> str:
    for a, b in zip(seg_nodes, seg_nodes[1:]):
        for nb, _, name in graph.adj.get(a, []):
            if nb == b:
                return name
    return ""


def total_ascent(graph: Graph, nodes: list[int]) -> float:
    asc = 0.0
    for a, b in zip(nodes, nodes[1:]):
        if a in graph.elev and b in graph.elev:
            asc += max(0.0, graph.elev[b] - graph.elev[a])
    return asc


def dedupe(climbs: list[Climb], limit: int, overlap: float = 0.5) -> list[Climb]:
    """Keep the best climb of each family of near-identical routes."""
    chosen: list[Climb] = []
    seen: list[set[int]] = []
    for climb in climbs:
        nodes = set(climb.nodes)
        if any(len(nodes & prev) / min(len(nodes), len(prev)) > overlap for prev in seen):
            continue
        chosen.append(climb)
        seen.append(nodes)
        if len(chosen) >= limit:
            break
    return chosen


# --------------------------------------------------------------------------- #
# output
# --------------------------------------------------------------------------- #
def steepest_window(graph: Graph, nodes: list[int], window_m: float) -> float:
    """Steepest average grade over any `window_m` stretch of the climb."""
    pts = [(graph.coord[n], graph.elev[n]) for n in nodes if n in graph.elev]
    if len(pts) < 2:
        return 0.0
    cum = [0.0]
    for (c1, _), (c2, _) in zip(pts, pts[1:]):
        cum.append(cum[-1] + haversine(*c1, *c2))
    if cum[-1] < window_m:
        return (pts[-1][1] - pts[0][1]) / cum[-1] if cum[-1] else 0.0
    best, j = 0.0, 0
    for i in range(len(pts)):
        while j < len(pts) - 1 and cum[j] - cum[i] < window_m:
            j += 1
        span = cum[j] - cum[i]
        if span >= window_m * 0.9:
            best = max(best, (pts[j][1] - pts[i][1]) / span)
    return best


def report(graph: Graph, climbs: list[Climb], args) -> None:
    print()
    print(f"Top {len(climbs)} climbs near {args.lat:.5f},{args.lon:.5f} "
          f"(target {args.target_length:.0f} m @ {args.target_grade * 100:.1f} %)")
    print("-" * 108)
    print(f"{'#':>2}  {'score':>5}  {'len_m':>6}  {'gain_m':>6}  {'avg%':>5}  "
          f"{'max%/300m':>9}  {'start (lat,lon)':<22}  roads")
    for i, c in enumerate(climbs, 1):
        s_lat, s_lon = graph.coord[c.nodes[0]]
        print(
            f"{i:>2}  {c.score:>5.1f}  {c.length:>6.0f}  {c.gain:>6.1f}  "
            f"{c.grade * 100:>5.2f}  {steepest_window(graph, c.nodes, 300) * 100:>9.2f}  "
            f"{s_lat:.5f},{s_lon:.5f}      {', '.join(c.names[:4])}"
        )
    print()
    for i, c in enumerate(climbs[:5], 1):
        s_lat, s_lon = graph.coord[c.nodes[0]]
        e_lat, e_lon = graph.coord[c.nodes[-1]]
        print(f"  #{i} route: https://www.google.com/maps/dir/{s_lat:.5f},{s_lon:.5f}/{e_lat:.5f},{e_lon:.5f}/data=!4m2!4m1!3e1")


def write_outputs(graph: Graph, climbs: list[Climb], out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)

    features = []
    for i, c in enumerate(climbs, 1):
        features.append({
            "type": "Feature",
            "properties": {
                "rank": i, "score": round(c.score, 1), "length_m": round(c.length),
                "gain_m": round(c.gain, 1), "avg_grade_pct": round(c.grade * 100, 2),
                "total_ascent_m": round(c.ascent, 1), "roads": ", ".join(c.names),
            },
            "geometry": {
                "type": "LineString",
                "coordinates": [[graph.coord[n][1], graph.coord[n][0],
                                 round(graph.elev.get(n, 0), 1)] for n in c.nodes],
            },
        })
    geo_path = os.path.join(out_dir, "climbs.geojson")
    with open(geo_path, "w") as fh:
        json.dump({"type": "FeatureCollection", "features": features}, fh)

    csv_path = os.path.join(out_dir, "climbs.csv")
    with open(csv_path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rank", "score", "length_m", "gain_m", "avg_grade_pct",
                    "start_lat", "start_lon", "end_lat", "end_lon", "roads"])
        for i, c in enumerate(climbs, 1):
            s, e = graph.coord[c.nodes[0]], graph.coord[c.nodes[-1]]
            w.writerow([i, f"{c.score:.1f}", f"{c.length:.0f}", f"{c.gain:.1f}",
                        f"{c.grade * 100:.2f}", f"{s[0]:.6f}", f"{s[1]:.6f}",
                        f"{e[0]:.6f}", f"{e[1]:.6f}", ", ".join(c.names)])

    for i, c in enumerate(climbs[:10], 1):
        gpx_path = os.path.join(out_dir, f"climb_{i:02d}.gpx")
        with open(gpx_path, "w") as fh:
            fh.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                     '<gpx version="1.1" creator="incline-finder" '
                     'xmlns="http://www.topografix.com/GPX/1/1">\n<trk>\n'
                     f'<name>climb {i}: {c.length:.0f} m @ {c.grade * 100:.1f}%</name>\n<trkseg>\n')
            for n in c.nodes:
                lat, lon = graph.coord[n]
                fh.write(f'<trkpt lat="{lat:.6f}" lon="{lon:.6f}">'
                         f'<ele>{graph.elev.get(n, 0):.1f}</ele></trkpt>\n')
            fh.write("</trkseg>\n</trk>\n</gpx>\n")
    print(f"wrote {geo_path}, {csv_path} and {min(len(climbs), 10)} GPX files in {out_dir}")


# --------------------------------------------------------------------------- #
# offline self-test
# --------------------------------------------------------------------------- #
def self_test(args) -> int:
    """Synthetic terrain: verifies the search without touching the network."""
    ok = True

    def approx(a, b, tol):
        return abs(a - b) <= tol

    # A 2 km straight road: 1 km at 5 %, then 1 km flat, plus a decoy 400 m at 12 %.
    elements = []
    lat0, lon0 = 57.66, 11.97
    dlat = 20.0 / 111320.0                      # 20 m steps
    main_nodes = []
    for i in range(101):                        # 0..2000 m
        nid = 1000 + i
        elements.append({"type": "node", "id": nid, "lat": lat0 + i * dlat, "lon": lon0})
        main_nodes.append(nid)
    decoy_nodes = []
    for i in range(21):                         # 0..400 m branching east
        nid = 2000 + i
        elements.append({"type": "node", "id": nid, "lat": lat0,
                         "lon": lon0 + i * 20.0 / (111320.0 * math.cos(math.radians(lat0)))})
        decoy_nodes.append(nid)
    elements.append({"type": "way", "id": 1, "nodes": main_nodes, "tags": {"highway": "residential", "name": "Testbacken"}})
    elements.append({"type": "way", "id": 2, "nodes": decoy_nodes, "tags": {"highway": "residential", "name": "Brantvagen"}})

    graph, ways = build_graph({"elements": elements}, spacing=args.node_spacing)
    for i, nid in enumerate(main_nodes):
        graph.elev[nid] = min(i * 20.0, 1000.0) * 0.05          # 5 % for 1 km, then flat
    for i, nid in enumerate(decoy_nodes):
        graph.elev[nid] = i * 20.0 * 0.12                        # 12 % for 400 m
    smooth_elevations(graph, ways, window_m=0)

    climbs = dedupe(find_climbs(graph, args), limit=5)
    if not climbs:
        print("FAIL: no climbs found on synthetic terrain")
        return 1
    best = climbs[0]
    checks = [
        ("best climb ~1000 m", approx(best.length, 1000, 60)),
        ("best climb ~50 m gain", approx(best.gain, 50, 4)),
        ("best climb ~5 %", approx(best.grade * 100, 5.0, 0.4)),
        ("steeper decoy scores lower", all(c.score <= best.score for c in climbs)),
        ("no candidate exceeds max_length", all(c.length <= args.max_length + 1 for c in climbs)),
        ("all candidates gain height", all(c.gain > 0 for c in climbs)),
    ]
    # Scoring sanity: exactly on target beats both a short-steep and a long-shallow climb.
    on_target = score_climb(1000, 0.05, args.target_length, args.target_grade)
    checks += [
        ("on-target scores ~100", approx(on_target, 100, 0.1)),
        ("400 m @ 12 % scores lower", score_climb(400, 0.12, args.target_length, args.target_grade) < on_target),
        ("3 km @ 2 % scores lower", score_climb(3000, 0.02, args.target_length, args.target_grade) < on_target),
    ]
    # Window helper: the steepest 300 m of the test hill is the 5 % part.
    checks.append(("steepest 300 m window ~5 %",
                   approx(steepest_window(graph, best.nodes, 300) * 100, 5.0, 0.5)))

    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok &= passed
    print(f"\nbest synthetic climb: {best.length:.0f} m, {best.gain:.1f} m, "
          f"{best.grade * 100:.2f} %, score {best.score:.1f}")
    return 0 if ok else 1


# --------------------------------------------------------------------------- #
def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--lat", type=float, default=DEFAULT_LAT)
    p.add_argument("--lon", type=float, default=DEFAULT_LON)
    p.add_argument("--radius-km", type=float, default=4.0, help="search radius (default 4)")
    p.add_argument("--profile", choices=sorted(PROFILES), default="bike")
    p.add_argument("--target-length", type=float, default=1000.0, help="ideal climb length, m")
    p.add_argument("--target-grade", type=float, default=0.05, help="ideal grade as a fraction")
    p.add_argument("--min-length", type=float, default=500.0)
    p.add_argument("--max-length", type=float, default=2500.0)
    p.add_argument("--min-grade", type=float, default=0.03)
    p.add_argument("--max-drop", type=float, default=8.0,
                   help="metres a climb may give back before it counts as two climbs")
    p.add_argument("--node-spacing", type=float, default=25.0, help="resample step, m")
    p.add_argument("--smooth-m", type=float, default=60.0, help="elevation smoothing window, m")
    p.add_argument("--dataset", default="eudem25m", help="OpenTopoData dataset (eudem25m, mapzen, srtm30m)")
    p.add_argument("--top", type=int, default=15)
    p.add_argument("--max-steps-per-start", type=int, default=20000,
                   help="search steps spent on one starting junction (runtime guard)")
    p.add_argument("--max-total-steps", type=int, default=4000000,
                   help="total search steps before the sweep stops (runtime guard)")
    p.add_argument("--max-walks", type=int, default=4000,
                   help="best corridors, by height gained, taken to window analysis")
    p.add_argument("--max-walks-per-start", type=int, default=400,
                   help="corridor cap per starting junction (runtime guard)")
    p.add_argument("--cache-dir", default=os.path.expanduser("~/.cache/incline-finder"))
    p.add_argument("--out-dir", default="./climbs-out")
    p.add_argument("--self-test", action="store_true", help="run offline checks and exit")
    args = p.parse_args()

    if args.self_test:
        return self_test(args)

    osm = fetch_osm(args.lat, args.lon, int(args.radius_km * 1000), args.profile, args.cache_dir)
    graph, ways = build_graph(osm, spacing=args.node_spacing)
    print(f"[graph] {len(graph.coord)} nodes, {sum(len(v) for v in graph.adj.values()) // 2} edges",
          file=sys.stderr)

    nodes = sorted(graph.coord)
    elevs = fetch_elevations([graph.coord[n] for n in nodes], args.dataset, args.cache_dir)
    for n in nodes:
        if graph.coord[n] in elevs:
            graph.elev[n] = elevs[graph.coord[n]]
    print(f"[graph] {len(graph.elev)} nodes with elevation", file=sys.stderr)
    smooth_elevations(graph, ways, args.smooth_m)

    climbs = dedupe(find_climbs(graph, args), limit=args.top)
    if not climbs:
        print("No climb matched the constraints; try --min-grade 0.02 or a larger --radius-km")
        return 1
    report(graph, climbs, args)
    write_outputs(graph, climbs, args.out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
