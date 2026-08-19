# incline-finder

Finds the best sustained climb around a point, from OpenStreetMap geometry plus a
digital elevation model. Built to answer: *where near Eklanda Hage in Mölndal can I
ride roughly 1 km at 5 %?*

Standard library only — no pip install.

```bash
python3 find_climbs.py                      # Eklanda Hage, 4 km radius, bike profile
python3 find_climbs.py --radius-km 6 --profile road
python3 find_climbs.py --target-length 1200 --target-grade 0.06
python3 find_climbs.py --self-test          # offline checks, no network
python3 test_pipeline.py                    # offline end-to-end smoke test
```

Output: a ranked table on stdout, plus `climbs-out/climbs.geojson` (drop it on
[geojson.io](https://geojson.io)), `climbs-out/climbs.csv`, and one GPX per top climb.

## Data sources

| what | where | notes |
| --- | --- | --- |
| road & path network | Overpass API | `way(around:R,lat,lon)[highway~...]`, private/`area` ways excluded |
| elevation | OpenTopoData, dataset `eudem25m` | EU-DEM 25 m covers Sweden; ~7 m RMSE vertical |

The free OpenTopoData endpoint allows 100 points per call, 1 call/s, 1000 calls/day.
A 4 km radius is roughly 100–250 calls, so a first run takes a few minutes; everything
is cached in `~/.cache/incline-finder`, so re-runs with different targets are instant.

For better vertical accuracy, swap in Lantmäteriet's *Höjddata Grid 1+* (1 m national
LiDAR DEM, open data) and point `fetch_elevations` at a local raster instead.

## Method

1. **Network** — Overpass ways in the radius, resampled to one node every
   `--node-spacing` metres (junctions always kept).
2. **Elevation** — one DEM lookup per node, then a moving average of `--smooth-m`
   along each way. Without smoothing, DEM noise invents 8 % ramps that aren't there.
3. **Contraction** — degree-2 chains collapse, so the search runs over junctions.
4. **Corridor walk** — depth-first from every junction, only extending while the route
   keeps climbing: a branch is dropped once it drops more than `--max-drop` (default 8 m)
   below its high point, which is what separates "one climb" from "two climbs with a
   descent between". One corridor is kept per start/end pair, the one gaining most height.
5. **Trim** — each corridor is trimmed to the sub-stretch that best matches the target,
   because climbs rarely start and end exactly at a junction.
6. **Score** — a 0–100 similarity to the target: Gaussian on length (tolerant) times
   Gaussian on gradient (strict). 1000 m at 5.0 % = 100. 400 m at 12 % and 3 km at 2 %
   both score low: they are climbs, just not *this* climb.
7. **Dedupe** — near-identical routes (>50 % shared nodes) collapse to the best one.

Useful knobs: `--min-grade` (default 3 %), `--min-length` / `--max-length`
(500 / 2500 m), `--max-drop`, `--profile road|bike|all`, `--dataset`.

## Caveats

- `--profile bike` includes `path` and `track`; Änggårdsbergen is a nature reserve where
  cycling is restricted to marked routes and only in certain periods. Check before riding.
- Grades come from a DEM sampled at road nodes, not from the road surface: expect ±1 %
  on any single 100 m stretch. Averages over 500 m+ are trustworthy.
- One-way restrictions are ignored — the search treats every road as ridable both ways.
- The search is exhaustive per junction but capped by `--max-steps-per-start` and
  `--max-total-steps`; raise them for a wider sweep at the cost of runtime.
