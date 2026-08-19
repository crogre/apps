"""Locate the Overture row groups covering our bbox, by reading footers only."""
import json, sys, time
from concurrent.futures import ThreadPoolExecutor
import pyarrow.parquet as pq
from s3_range import RangeFile

XMIN, XMAX, YMIN, YMAX = 11.85, 12.10, 57.58, 57.74      # Mölndal / Eklanda window
keys = open("seg_keys.txt").read().split("\n")

def scan(key):
    try:
        f = RangeFile(key)
        md = pq.ParquetFile(f).metadata
        paths = {md.row_group(0).column(i).path_in_schema: i for i in range(md.num_columns)}
        ix, ax = paths["bbox.xmin"], paths["bbox.xmax"]
        iy, ay = paths["bbox.ymin"], paths["bbox.ymax"]
        hits = []
        for r in range(md.num_row_groups):
            g = md.row_group(r)
            x0 = g.column(ix).statistics.min; x1 = g.column(ax).statistics.max
            y0 = g.column(iy).statistics.min; y1 = g.column(ay).statistics.max
            if x0 <= XMAX and x1 >= XMIN and y0 <= YMAX and y1 >= YMIN:
                hits.append((r, g.num_rows))
        return key, hits, f.bytes_read
    except Exception as e:
        return key, f"ERROR {e}", 0

t = time.time()
found, total_bytes = {}, 0
with ThreadPoolExecutor(max_workers=12) as ex:
    for i, (key, hits, nbytes) in enumerate(ex.map(scan, keys), 1):
        total_bytes += nbytes
        if isinstance(hits, str):
            print(hits[:120], file=sys.stderr)
        elif hits:
            found[key] = hits
            print(f"  HIT {key.split('/')[-1][:20]} -> row groups {[h[0] for h in hits]}")
        if i % 32 == 0:
            print(f"  ...{i}/{len(keys)} files, {total_bytes/1e6:.0f} MB, {time.time()-t:.0f}s", file=sys.stderr)
json.dump(found, open("rowgroups.json", "w"))
print(f"done in {time.time()-t:.0f}s; {sum(len(v) for v in found.values())} row groups, "
      f"{sum(n for v in found.values() for _, n in v):,} candidate rows")
