#!/usr/bin/env python3
"""Offline end-to-end smoke test: synthetic grid town on a hillside.

Runs the whole pipeline except the two network calls, so the graph build,
smoothing, search and file writers are all exercised without egress.
"""
import math
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import find_climbs as fc


def synthetic_town(lat0=57.66, lon0=11.97, n=12, step=120.0):
    """n x n grid of streets on a slope that rises ~5 % towards the north."""
    mlat = step / 111320.0
    mlon = step / (111320.0 * math.cos(math.radians(lat0)))
    elements, ids = [], {}
    for r in range(n):
        for c in range(n):
            nid = 10000 + r * n + c
            ids[(r, c)] = nid
            elements.append({"type": "node", "id": nid,
                             "lat": lat0 + r * mlat, "lon": lon0 + c * mlon})
    for r in range(n):
        elements.append({"type": "way", "id": 100 + r,
                         "nodes": [ids[(r, c)] for c in range(n)],
                         "tags": {"highway": "residential", "name": f"Tvargatan {r}"}})
    for c in range(n):
        elements.append({"type": "way", "id": 200 + c,
                         "nodes": [ids[(r, c)] for r in range(n)],
                         "tags": {"highway": "residential", "name": f"Backgatan {c}"}})
    # Height: 5 % northwards, a gentle east-west tilt so streets are not identical.
    def elevation(r, c):
        return r * step * 0.05 + c * step * 0.004
    return elements, ids, elevation


class Args:
    lat, lon = 57.66, 11.97
    target_length, target_grade = 1000.0, 0.05
    min_length, max_length = 500.0, 2500.0
    min_grade, max_drop = 0.03, 8.0
    node_spacing, smooth_m = 25.0, 60.0
    top, max_walks, max_walks_per_start = 10, 4000, 400
    max_steps_per_start, max_total_steps = 20000, 4000000


def main() -> int:
    elements, ids, elevation = synthetic_town()
    graph, ways = fc.build_graph({"elements": elements}, spacing=Args.node_spacing)
    n = 12
    for (r, c), nid in ids.items():
        if nid in graph.coord:
            graph.elev[nid] = elevation(r, c)
    fc.smooth_elevations(graph, ways, Args.smooth_m)

    climbs = fc.dedupe(fc.find_climbs(graph, Args), limit=Args.top)
    checks = [
        ("finds climbs in a grid town", bool(climbs)),
        ("top climb close to target", climbs and abs(climbs[0].length - 1000) < 400
                                      and abs(climbs[0].grade - 0.05) < 0.015),
        ("all climbs run uphill", all(c.gain > 0 for c in climbs)),
        ("dedupe returns distinct routes", len({tuple(c.nodes) for c in climbs}) == len(climbs)),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        fc.write_outputs(graph, climbs, tmp)
        checks += [
            ("geojson written", os.path.getsize(os.path.join(tmp, "climbs.geojson")) > 100),
            ("csv written", os.path.getsize(os.path.join(tmp, "climbs.csv")) > 50),
            ("gpx written", os.path.exists(os.path.join(tmp, "climb_01.gpx"))),
        ]
        fc.report(graph, climbs, Args)

    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok &= bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
