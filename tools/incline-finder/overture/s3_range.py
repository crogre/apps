"""Minimal random-access file over S3 HTTP range requests (no httpfs needed)."""
import io, urllib.request

BUCKET = "https://overturemaps-us-west-2.s3.amazonaws.com/"

class RangeFile(io.RawIOBase):
    def __init__(self, key, size=None):
        self.url = BUCKET + key
        self.pos = 0
        self.bytes_read = 0
        self._size = size if size is not None else self._head()

    def _head(self):
        req = urllib.request.Request(self.url, method="HEAD")
        with urllib.request.urlopen(req, timeout=60) as r:
            return int(r.headers["Content-Length"])

    def _get(self, start, end):
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                self.bytes_read += len(data)
                return data
            except Exception:
                if attempt == 3:
                    raise
    # file protocol
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos
    def size(self): return self._size
    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self._size + off)
        return self.pos
    def read(self, n=-1):
        if n is None or n < 0:
            n = self._size - self.pos
        if n == 0 or self.pos >= self._size:
            return b""
        end = min(self.pos + n, self._size) - 1
        data = self._get(self.pos, end)
        self.pos += len(data)
        return data
    def readall(self): return self.read(-1)
