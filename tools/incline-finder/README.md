# incline-finder

Finds the best sustained climb around a point, from OpenStreetMap road geometry plus a
digital elevation model. Built to answer: *where near Eklanda Hage in Mölndal can I ride
roughly 1 km at 5 %?*

## The answer

Every tarmac road within 4 km of Eklanda Hage (57.65612, 11.96150) was walked uphill and
measured against two independent elevation models. Best matches:

| # | Climb | Length | Gain | Avg grade (GLO-30 / terrain-tiles) | Pulling ≥3 % | From Eklanda Hage |
|---|-------|--------|------|------------------------------------|--------------|-------------------|
| 1 | **Sisjövägen** (one road, no turns) | 995 m | 50 m | 5.16 / 4.93 % | 78 % | 2.0 km |
| 2 | Toltorpsgatan → Ehrenströmsgatan → Södermalmsgatan | 989 m | 49 m | 4.94 / 5.05 % | 78 % | 2.25 km |
| 3 | Tunnlandsgatan → Dirigentgatan (Flatås) | 977 m | 48 m | 4.90 / 4.72 % | 84 % | 2.1 km |
| 4 | Krokslättsgatan | 1000 m | 52 m | 5.16 / 5.13 % | 74 % | 3.3 km |
| 5 | Askims Svedjeväg → Gamla Särövägen → Högabergsvägen | 939 m | 45 m | 4.82 / 4.83 % | 92 % | 3.2 km |

Sisjövägen climbs from the Datavägen/Knapegårdsvägen junction (14 m) south-east to 65 m.
Nothing inside 2 km of Eklanda Hage holds a steady 5 % for a kilometre: the nearest
candidate, the service road up Västra Eklanda Höjd (625 m away), reads 6.0 % in one model
and 4.9 % in the other and flattens through its middle third.

`results/` holds GPX per climb, a combined GeoJSON, and a report page.

## Two ways to get the data

**A. Overpass + OpenTopoData** (`find_climbs.py`) — the simple path, one command, needs
outbound access to `overpass-api.de` and `api.opentopodata.org`:

```bash
python3 find_climbs.py                    # Eklanda Hage, 4 km radius, bike profile
python3 find_climbs.py --radius-km 6 --profile road --target-grade 0.06
python3 find_climbs.py --self-test        # offline checks of search and scoring
python3 test_pipeline.py                  # offline end-to-end smoke test
```

**B. Overture + AWS open data** (`overture/`, `terrain_tiles.py`, `search_eklanda.py`) — the
path actually used here, because the environment's egress policy blocked Overpass, Nominatim
and every elevation API, but allowed S3. No API keys:

```bash
python3 overture/scan_rowgroups.py        # footer-only scan of 128 global Parquet files (~20 s)
python3 overture/fetch_segments.py        # range-read just the row groups covering the bbox
python3 terrain_tiles.py                  # AWS Terrain Tiles -> dem.npz
python3 search_eklanda.py                 # the search
python3 verify_two_dems.py                # re-measure against Copernicus GLO-30
python3 report/export_gpx.py              # GPX + GeoJSON
python3 report/profiles.py && python3 report/build_page.py
```

`overture/s3_range.py` is a ~40-line random-access file over HTTP range requests, which is
what lets pyarrow read row groups out of a 71 GB global dataset without DuckDB's httpfs
extension. Reading 128 Parquet footers costs ~260 MB; the segments themselves ~50 MB.

Copernicus GLO-30 tiles come from `copernicus-dem-30m.s3.amazonaws.com`; one 1°×1° tile per
5–30 MB. Verification needs the tiles either side of the 12°E meridian for this area.

## Method

1. **Network** — road segments in the radius, resampled to a node every 25 m (junctions kept).
2. **Elevation** — one DEM lookup per node, then a moving average over 80 m along each way.
   Without it, surface-model noise invents 8 % ramps that aren't there.
3. **Contraction** — degree-2 chains collapse, so the search runs over junctions.
4. **Corridor walk** — depth-first from every junction, nearest the query point first, extending
   only while the route keeps climbing: a branch is dropped once it falls more than 6 m below its
   high point, which is what separates "one climb" from "two climbs with a dip". One corridor is
   kept per start/end pair, the one gaining most height.
5. **Trim** — each corridor is trimmed to the sub-stretch that best matches the target, since
   climbs rarely start and end at a junction.
6. **Score** — similarity to the target (Gaussian on length, tighter on gradient), multiplied by
   how much of the climb actually pulls ≥3 %, and by how well the two DEMs agree.
7. **Dedupe** — routes sharing >35 % of their nodes collapse to the best one.

## Caveats

- Both DEMs are *surface* models: trees, buildings and noise walls beside the road show up as
  spikes. Kilometre averages are good to about ±0.3 points; single 100 m readings are not.
- One-way restrictions are ignored — the search treats every road as ridable both ways.
- The `road` profile is tarmac only. Änggårdsbergen is a nature reserve where cycling is
  restricted to marked routes in certain periods; its paths are excluded for that reason.
- Terrain tiles are read at zoom 14 (~5 m/px), oversampled from a ~30 m source.
