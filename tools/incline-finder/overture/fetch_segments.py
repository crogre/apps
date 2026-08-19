"""Read the Mölndal road segments out of Overture's global Parquet, over HTTP ranges."""
import json, time
import pyarrow.parquet as pq
import pyarrow.compute as pc
from s3_range import RangeFile

XMIN, XMAX, YMIN, YMAX = 11.85, 12.10, 57.58, 57.74
COLS = ["id", "geometry", "subtype", "class", "names", "road_surface", "access_restrictions"]

groups = json.load(open("rowgroups.json"))
tables, t0, mb = [], time.time(), 0
for key, hits in groups.items():
    f = RangeFile(key)
    pf = pq.ParquetFile(f)
    for rg, nrows in hits:
        tbl = pf.read_row_group(rg, columns=COLS + ["bbox"])
        bbox = tbl.column("bbox").combine_chunks()
        keep = pc.and_(
            pc.and_(pc.less_equal(bbox.field("xmin"), XMAX), pc.greater_equal(bbox.field("xmax"), XMIN)),
            pc.and_(pc.less_equal(bbox.field("ymin"), YMAX), pc.greater_equal(bbox.field("ymax"), YMIN)),
        )
        tbl = tbl.filter(keep).drop(["bbox"])
        if tbl.num_rows:
            tables.append(tbl)
        print(f"  {key.split('/')[-1][:18]} rg{rg}: {tbl.num_rows} segments in bbox "
              f"({f.bytes_read/1e6:.0f} MB, {time.time()-t0:.0f}s)")
    mb += f.bytes_read / 1e6

import pyarrow as pa
out = pa.concat_tables(tables)
pq.write_table(out, "molndal_segments.parquet")
print(f"\n{out.num_rows:,} segments, {mb:.0f} MB downloaded, {time.time()-t0:.0f}s")
print("subtypes:", out.column("subtype").to_pylist()[:3])
