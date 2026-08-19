"""Build an elevation grid from AWS Terrain Tiles (terrarium encoding)."""
import io, math, os, urllib.request
import numpy as np
from PIL import Image

Z = 14
BASE = "https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png"
CACHE = "tiles"

def lonlat_to_tile(lon, lat, z=Z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    lat_r = math.radians(lat)
    y = (1 - math.log(math.tan(lat_r) + 1 / math.cos(lat_r)) / math.pi) / 2 * n
    return x, y

def fetch(x, y, z=Z):
    os.makedirs(CACHE, exist_ok=True)
    path = f"{CACHE}/{z}_{x}_{y}.png"
    if not os.path.exists(path):
        url = BASE.format(z=z, x=x, y=y)
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
        open(path, "wb").write(data)
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)

def build(lat0, lon0, lat1, lon1, z=Z):
    """Return (grid, x_min_px, y_min_px) where grid[j, i] is elevation in metres."""
    xa, ya = lonlat_to_tile(lon0, lat1, z)     # NW corner
    xb, yb = lonlat_to_tile(lon1, lat0, z)     # SE corner
    tx0, tx1 = int(math.floor(xa)), int(math.floor(xb))
    ty0, ty1 = int(math.floor(ya)), int(math.floor(yb))
    rows = []
    for ty in range(ty0, ty1 + 1):
        cols = []
        for tx in range(tx0, tx1 + 1):
            rgb = fetch(tx, ty, z)
            cols.append(rgb[:, :, 0] * 256 + rgb[:, :, 1] + rgb[:, :, 2] / 256 - 32768)
        rows.append(np.hstack(cols))
    grid = np.vstack(rows)
    return grid, tx0 * 256, ty0 * 256

class DEM:
    def __init__(self, grid, px0, py0, z=Z):
        self.g, self.px0, self.py0, self.z = grid, px0, py0, z
    def at(self, lat, lon):
        """Bilinear elevation lookup, metres."""
        x, y = lonlat_to_tile(lon, lat, self.z)
        px, py = x * 256 - self.px0, y * 256 - self.py0
        i, j = int(px), int(py)
        if not (0 <= i < self.g.shape[1] - 1 and 0 <= j < self.g.shape[0] - 1):
            return float("nan")
        fx, fy = px - i, py - j
        g = self.g
        return float(
            g[j, i] * (1 - fx) * (1 - fy) + g[j, i + 1] * fx * (1 - fy)
            + g[j + 1, i] * (1 - fx) * fy + g[j + 1, i + 1] * fx * fy
        )

if __name__ == "__main__":
    LAT, LON = 57.65612, 11.96150   # Eklanda Hage, from Overture street geometry
    grid, px0, py0 = build(LAT - 0.055, LON - 0.105, LAT + 0.055, LON + 0.105)
    np.savez("dem.npz", grid=grid, px0=px0, py0=py0, z=Z)
    d = DEM(grid, px0, py0)
    print("grid", grid.shape, "min", round(grid.min(), 1), "max", round(grid.max(), 1))
    for name, la, lo in [
        ("Eklanda Hage", 57.65612, 11.96150),
        ("Molndal centrum (Molndals bro)", 57.6560, 12.0140),
        ("Vasterberget, Anggardsbergen", 57.6740, 11.9660),
        ("Stensjon lake", 57.6520, 12.0330),
    ]:
        print(f"  {name:34s} {d.at(la, lo):7.1f} m")
