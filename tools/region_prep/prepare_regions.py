#!/usr/bin/env python3
"""Builds the act maps in data/regions/ from public-domain outlines.

Offline data prep, not game code: the game only reads the JSON this writes.
Standard library only, so any Python 3.9+ runs it.

    # 1. Download the sources each source file lists into a cache folder.
    python3 tools/region_prep/prepare_regions.py fetch --cache /tmp/region_cache \
        data/regions/sources/*.source.json
    # 2. Build the region files (and optional preview PNGs of the raster).
    python3 tools/region_prep/prepare_regions.py build --cache /tmp/region_cache \
        [--preview /tmp/previews] data/regions/sources/*.source.json

How it works, per source file (data/regions/sources/<map>.source.json):

1. Project every source outline (Natural Earth admin-0 or admin-1 polygons,
   US Census TIGER places) into the map's frame and rasterize it. Each pixel
   gets the game region its source feature belongs to; several features can
   make one region (tiny states are grouped that way).
2. For a metro map, city outlines are only cores: the rest of the land within
   `grow_km` is given to the nearest city along land, so the cities tile the
   land and water stays water.
3. Trace each region's pixels back to outlines (its largest piece is the
   "polygon", other pieces above `min_part_px` are "parts"), simplify them
   with Douglas-Peucker, and place the label at the point deepest inside.
4. Regions whose pixels touch share a land border and are adjacent. The
   source file adds water crossings (bridges, ferries, straits) on top.
5. Land that belongs to no region becomes neutral "land" scenery; flat maps
   get one water rectangle under everything, the globe draws its own ocean.

Gameplay numbers (provides, defense, pressure) and starts are copied from the
source file unchanged, so data/ stays the one place they live.
"""

import argparse
import heapq
import json
import math
import os
import struct
import sys
import urllib.request
import zlib

VIEW_ASPECT_DEFAULT = 880.0 / 620.0


# --- Projections -------------------------------------------------------------------

class LocalProjection:
    """Equirectangular around the frame's middle latitude. For a metro area."""

    def __init__(self, cfg):
        self.lat0 = math.radians(cfg["lat0"])

    def forward(self, lon, lat):
        return lon * math.cos(self.lat0), lat

    def inverse(self, x, y):
        return x / math.cos(self.lat0), y


class AlbersProjection:
    """Albers equal-area conic on a sphere, in degrees of arc."""

    def __init__(self, cfg):
        p1, p2 = math.radians(cfg["parallels"][0]), math.radians(cfg["parallels"][1])
        self.lon0 = cfg["lon0"]
        lat0 = math.radians(cfg["lat0"])
        self.n = (math.sin(p1) + math.sin(p2)) / 2.0
        self.c = math.cos(p1) ** 2 + 2.0 * self.n * math.sin(p1)
        self.rho0 = math.sqrt(self.c - 2.0 * self.n * math.sin(lat0)) / self.n

    def forward(self, lon, lat):
        rho = math.sqrt(max(0.0, self.c - 2.0 * self.n * math.sin(math.radians(lat)))) / self.n
        theta = self.n * math.radians(lon - self.lon0)
        return math.degrees(rho * math.sin(theta)), math.degrees(self.rho0 - rho * math.cos(theta))

    def inverse(self, x, y):
        x, y = math.radians(x), math.radians(y)
        rho = math.hypot(x, self.rho0 - y)
        theta = math.atan2(x, self.rho0 - y)
        lat = math.asin(max(-1.0, min(1.0, (self.c - (rho * self.n) ** 2) / (2.0 * self.n))))
        return self.lon0 + math.degrees(theta / self.n), math.degrees(lat)


class LonLatProjection:
    """Plain longitude and latitude, for the globe."""

    def __init__(self, cfg):
        pass

    def forward(self, lon, lat):
        return lon, lat

    def inverse(self, x, y):
        return x, y


PROJECTIONS = {"local": LocalProjection, "albers": AlbersProjection, "lonlat": LonLatProjection}


class Frame:
    """The part of the projected plane the map shows, and its raster."""

    def __init__(self, projection, x0, y0, x1, y1, width, height):
        self.projection = projection
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.width, self.height = width, height

    @staticmethod
    def make(cfg):
        projection = PROJECTIONS[cfg["projection"]["type"]](cfg["projection"])
        width, height = cfg["raster"]
        frame = cfg["frame"]
        if "lonlat_box" in frame:
            lon0, lat0, lon1, lat1 = frame["lonlat_box"]
            xs, ys = zip(*[projection.forward(lon, lat) for lon, lat in
                           [(lon0, lat0), (lon1, lat0), (lon1, lat1), (lon0, lat1)]])
        else:
            pts = [projection.forward(lon, lat) for lon, lat in frame["fit"]]
            xs, ys = zip(*pts)
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        margin = frame.get("margin", 0.0)
        dx, dy = (x1 - x0) * margin, (y1 - y0) * margin
        x0, x1, y0, y1 = x0 - dx, x1 + dx, y0 - dy, y1 + dy
        aspect = frame.get("aspect")
        if aspect:
            # Grow the short side so the frame has the view's shape.
            w, h = x1 - x0, y1 - y0
            if w / h < aspect:
                grow = (h * aspect - w) / 2.0
                x0, x1 = x0 - grow, x1 + grow
            else:
                grow = (w / aspect - h) / 2.0
                y0, y1 = y0 - grow, y1 + grow
        return Frame(projection, x0, y0, x1, y1, width, height)

    def to_pixel(self, lon, lat):
        x, y = self.projection.forward(lon, lat)
        return ((x - self.x0) / (self.x1 - self.x0) * self.width,
                (self.y1 - y) / (self.y1 - self.y0) * self.height)

    def pixel_to_lonlat(self, px, py):
        x = self.x0 + px / self.width * (self.x1 - self.x0)
        y = self.y1 - py / self.height * (self.y1 - self.y0)
        return self.projection.inverse(x, y)

    def outline_lonlat(self, steps=12):
        """The frame's edge as longitude/latitude points, clockwise from top left."""
        pts = []
        corners = [(0, 0), (self.width, 0), (self.width, self.height), (0, self.height)]
        for i in range(4):
            (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
            for s in range(steps):
                t = s / steps
                pts.append(self.pixel_to_lonlat(ax + (bx - ax) * t, ay + (by - ay) * t))
        return pts


# --- Reading sources ----------------------------------------------------------------

def read_features(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if data.get("type") == "FeatureCollection":
        return data["features"]
    return [data]


def polygons_of(geometry):
    """A geometry's polygons, each a list of rings of (lon, lat)."""
    if geometry is None:
        return []
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    return []


def densify(ring, step):
    """Adds points so no edge is longer than `step` degrees; projected edges
    then follow parallels and meridians as curves."""
    if step <= 0:
        return ring
    out = []
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        out.append(a)
        n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) / step)
        for k in range(1, n + 1):
            t = k / (n + 1)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def to_pixel_rings(frame, polygon, step):
    rings = []
    for ring in polygon:
        pts = [tuple(p[:2]) for p in ring]
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) < 3:
            continue
        rings.append([frame.to_pixel(lon, lat) for lon, lat in densify(pts, step)])
    return rings


# --- Raster -------------------------------------------------------------------------

def new_grid(frame, value=0):
    return [bytearray([value]) * frame.width for _ in range(frame.height)]


def fill(grid, width, height, rings, value):
    """Fills a polygon (even-odd over its rings) with `value`."""
    if not rings:
        return
    ys = [y for ring in rings for _, y in ring]
    xs = [x for ring in rings for x, _ in ring]
    if max(ys) < 0 or min(ys) > height or max(xs) < 0 or min(xs) > width:
        return
    rows = {}
    for ring in rings:
        n = len(ring)
        for i in range(n):
            x0, y0 = ring[i]
            x1, y1 = ring[(i + 1) % n]
            if y0 == y1:
                continue
            if y0 > y1:
                x0, y0, x1, y1 = x1, y1, x0, y0
            r0 = max(0, math.ceil(y0 - 0.5))
            r1 = min(height - 1, math.ceil(y1 - 0.5) - 1)
            slope = (x1 - x0) / (y1 - y0)
            for r in range(r0, r1 + 1):
                rows.setdefault(r, []).append(x0 + (r + 0.5 - y0) * slope)
    one = bytes([value])
    for r, cuts in rows.items():
        cuts.sort()
        row = grid[r]
        for i in range(0, len(cuts) - 1, 2):
            c0 = max(0, math.ceil(cuts[i] - 0.5))
            c1 = min(width, math.ceil(cuts[i + 1] - 0.5))
            if c1 > c0:
                row[c0:c1] = one * (c1 - c0)


def grow_over_land(labels, land, width, height, max_px):
    """Gives unlabeled land within `max_px` of a labeled pixel, measured along
    land, to the nearest label (Dijkstra over 8 neighbors)."""
    dist = {}
    heap = []
    for r in range(height):
        row = labels[r]
        for c in range(width):
            if row[c]:
                key = r * width + c
                dist[key] = 0.0
                heap.append((0.0, key, row[c]))
    heapq.heapify(heap)
    steps = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
             (-1, -1, 1.4142), (-1, 1, 1.4142), (1, -1, 1.4142), (1, 1, 1.4142)]
    while heap:
        d, key, label = heapq.heappop(heap)
        if d > dist.get(key, math.inf):
            continue
        r, c = divmod(key, width)
        for dr, dc, w in steps:
            rr, cc = r + dr, c + dc
            if rr < 0 or rr >= height or cc < 0 or cc >= width:
                continue
            if not land[rr][cc]:
                continue
            nd = d + w
            if nd > max_px:
                continue
            nkey = rr * width + cc
            if nd < dist.get(nkey, math.inf):
                dist[nkey] = nd
                labels[rr][cc] = label
                heapq.heappush(heap, (nd, nkey, label))


def unpinch(grid, width, height):
    """Where two pixels of one value touch only at a corner, gives one of the
    other two pixels of that 2x2 block to the value too, until none are left.
    Traced outlines then never touch themselves at a point."""
    for _ in range(20):
        changed = 0
        for r in range(height - 1):
            top, bottom = grid[r], grid[r + 1]
            for c in range(width - 1):
                a, b, d, e = top[c], top[c + 1], bottom[c], bottom[c + 1]
                if a and a == e and b != a and d != a:
                    top[c + 1] = a
                    changed += 1
                elif b and b == d and a != b and e != b:
                    top[c] = b
                    changed += 1
        if not changed:
            return
    sys.exit("pinches did not clear")


def components(grid, width, height):
    """{value: [pixel key sets]} for every non-zero value, 4-connected."""
    seen = bytearray(width * height)
    out = {}
    for r in range(height):
        row = grid[r]
        for c in range(width):
            v = row[c]
            key = r * width + c
            if not v or seen[key]:
                continue
            comp = set()
            stack = [key]
            seen[key] = 1
            while stack:
                k = stack.pop()
                comp.add(k)
                kr, kc = divmod(k, width)
                for rr, cc in ((kr - 1, kc), (kr + 1, kc), (kr, kc - 1), (kr, kc + 1)):
                    if 0 <= rr < height and 0 <= cc < width and grid[rr][cc] == v:
                        nk = rr * width + cc
                        if not seen[nk]:
                            seen[nk] = 1
                            stack.append(nk)
            out.setdefault(v, []).append(comp)
    return out


def outer_ring(comp, width):
    """The outline of a pixel set, as pixel-corner points, holes left out."""
    stride = width + 1
    outgoing = {}
    for k in comp:
        r, c = divmod(k, width)
        # Clockwise on screen (y down), interior on the right.
        if (k - width) not in comp or r == 0:
            outgoing.setdefault(r * stride + c, []).append(r * stride + c + 1)
        if c == width - 1 or (k + 1) not in comp:
            outgoing.setdefault(r * stride + c + 1, []).append((r + 1) * stride + c + 1)
        if (k + width) not in comp:
            outgoing.setdefault((r + 1) * stride + c + 1, []).append((r + 1) * stride + c)
        if c == 0 or (k - 1) not in comp:
            outgoing.setdefault((r + 1) * stride + c, []).append(r * stride + c)
    best, best_area = None, -1.0
    while outgoing:
        start = next(iter(outgoing))
        loop = [start]
        prev, cur = None, start
        while True:
            options = outgoing[cur]
            nxt = options[0]
            if len(options) > 1 and prev is not None:
                nxt = _turn_right_first(prev, cur, options, stride)
            options.remove(nxt)
            if not options:
                del outgoing[cur]
            prev, cur = cur, nxt
            if cur == start:
                break
            loop.append(cur)
        pts = [(v % stride, v // stride) for v in loop]
        area = abs(ring_area(pts))
        if area > best_area:
            best, best_area = pts, area
    return best


def _turn_right_first(prev, cur, options, stride):
    pr, pc = divmod(prev, stride)
    cr, cc = divmod(cur, stride)
    dr, dc = cr - pr, cc - pc
    # Screen y points down: a right turn of (dc, dr) is (-dr, dc).
    for want in ((-dr, dc), (dc, dr), (dr, -dc)):
        for o in options:
            orr, oc = divmod(o, stride)
            if (oc - cc, orr - cr) == want:
                return o
    return options[0]


def ring_area(pts):
    s = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        s += x0 * y1 - x1 * y0
    return s / 2.0


def drop_collinear(pts):
    out = []
    n = len(pts)
    for i in range(n):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(b)
    return out


def simplify_ring(pts, tolerance):
    """Douglas-Peucker on a closed ring, with the tolerance halved until the
    result does not cross itself (narrow bays and inlets can make it)."""
    pts = drop_collinear(pts)
    while tolerance > 0.2:
        ring = _simplify_once(pts, tolerance)
        if is_simple(ring):
            return ring
        tolerance /= 2.0
    return pts


def is_simple(ring):
    """True when no two edges of the ring cross or touch, other than neighbors
    sharing their end point."""
    n = len(ring)
    if len(set(ring)) != n:
        return False
    edges = []
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        edges.append((min(a[0], b[0]), max(a[0], b[0]), min(a[1], b[1]), max(a[1], b[1]), a, b))
    order = sorted(range(n), key=lambda i: edges[i][0])
    for oi, i in enumerate(order):
        x0, x1, y0, y1, a, b = edges[i]
        for j in order[oi + 1:]:
            if edges[j][0] > x1:
                break
            if abs(i - j) == 1 or abs(i - j) == n - 1:
                continue
            if edges[j][3] < y0 or edges[j][2] > y1:
                continue
            if _segments_meet(a, b, edges[j][4], edges[j][5]):
                return False
    return True


def _segments_meet(p1, p2, p3, p4):
    def orient(a, b, c):
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return (v > 0) - (v < 0)
    def on(a, b, c):
        return min(a[0], b[0]) <= c[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= c[1] <= max(a[1], b[1])
    d1, d2, d3, d4 = orient(p3, p4, p1), orient(p3, p4, p2), orient(p1, p2, p3), orient(p1, p2, p4)
    if d1 != d2 and d3 != d4:
        return True
    return ((d1 == 0 and on(p3, p4, p1)) or (d2 == 0 and on(p3, p4, p2))
            or (d3 == 0 and on(p1, p2, p3)) or (d4 == 0 and on(p1, p2, p4)))


def _simplify_once(pts, tolerance):
    """Douglas-Peucker on a closed ring, split at its two farthest points."""
    if len(pts) <= 4:
        return pts
    far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
    first = _dp(pts[: far + 1], tolerance)
    second = _dp(pts[far:] + [pts[0]], tolerance)
    ring = first[:-1] + second[:-1]
    return ring if len(ring) >= 3 else pts


def _dp(pts, tolerance):
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        ax, ay = pts[i]
        bx, by = pts[j]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, worst_d = -1, tolerance
        for k in range(i + 1, j):
            px, py = pts[k]
            if length == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if d > worst_d:
                worst, worst_d = k, d
        if worst >= 0:
            keep[worst] = True
            stack.append((i, worst))
            stack.append((worst, j))
    return [p for p, k in zip(pts, keep) if k]


def deepest_point(comp, width, height, frame, globe):
    """The pixel farthest inside a pixel set (a two-pass chamfer distance),
    where a label has the most room."""
    rows = [k // width for k in comp]
    cols = [k % width for k in comp]
    r0, r1, c0, c1 = min(rows), max(rows), min(cols), max(cols)
    w, h = c1 - c0 + 3, r1 - r0 + 3
    inf = 1e9
    d = [[0.0] * w for _ in range(h)]
    for k in comp:
        r, c = divmod(k, width)
        if 0 < r < height - 1 and 0 < c < width - 1:
            d[r - r0 + 1][c - c0 + 1] = inf
    # On the globe a pixel is narrower toward the poles.
    def hw(rr):
        if not globe:
            return 1.0
        lat = 90.0 - (rr + r0 - 1 + 0.5) * 180.0 / height
        return max(0.05, math.cos(math.radians(lat)))
    for rr in range(1, h - 1):
        x = hw(rr)
        diag = math.hypot(1.0, x)
        row, up = d[rr], d[rr - 1]
        for cc in range(1, w - 1):
            if row[cc]:
                row[cc] = min(row[cc], row[cc - 1] + x, up[cc] + 1.0, up[cc - 1] + diag, up[cc + 1] + diag)
    best, best_d = None, -1.0
    for rr in range(h - 2, 0, -1):
        x = hw(rr)
        diag = math.hypot(1.0, x)
        row, down = d[rr], d[rr + 1]
        for cc in range(w - 2, 0, -1):
            if row[cc]:
                row[cc] = min(row[cc], row[cc + 1] + x, down[cc] + 1.0, down[cc - 1] + diag, down[cc + 1] + diag)
                if row[cc] > best_d:
                    best, best_d = (cc + c0 - 1 + 0.5, rr + r0 - 1 + 0.5), row[cc]
    if best is None:
        k = next(iter(comp))
        best = (k % width + 0.5, k // width + 0.5)
    return best


def shared_borders(labels, width, height, wrap):
    """{(a, b): pixel edges} for every pair of different non-zero labels that touch."""
    counts = {}
    for r in range(height):
        row = labels[r]
        below = labels[r + 1] if r + 1 < height else None
        for c in range(width):
            a = row[c]
            if not a:
                continue
            if c + 1 < width:
                b = row[c + 1]
            elif wrap:
                b = row[0]
            else:
                b = 0
            if b and b != a:
                key = (min(a, b), max(a, b))
                counts[key] = counts.get(key, 0) + 1
            if below is not None:
                b = below[c]
                if b and b != a:
                    key = (min(a, b), max(a, b))
                    counts[key] = counts.get(key, 0) + 1
    return counts


# --- Building one map ---------------------------------------------------------------

def build(cfg_path, cache, preview_dir, root):
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    frame = Frame.make(cfg)
    width, height = frame.width, frame.height
    globe = cfg["output_projection"] == "globe"
    step = cfg.get("densify_degrees", 0.0)
    print("%s: raster %dx%d" % (cfg["id"], width, height))

    def features(name):
        spec = cfg["inputs"][name]
        out = []
        for file in spec["files"]:
            # Inputs without urls are checked in next to the source file.
            folder = cache if "urls" in spec else os.path.dirname(cfg_path)
            out.extend(read_features(os.path.join(folder, file)))
        return out

    # Land.
    land = new_grid(frame)
    for feature in [f for name in cfg["land"]["inputs"] for f in features(name)]:
        for polygon in polygons_of(feature["geometry"]):
            fill(land, width, height, to_pixel_rings(frame, polygon, step), 1)
    for name in cfg["land"].get("minus", []):
        for feature in features(name):
            for polygon in polygons_of(feature["geometry"]):
                fill(land, width, height, to_pixel_rings(frame, polygon, step), 0)
    # Islands too small for the land source, drawn by hand, go on last.
    for name in cfg["land"].get("plus", []):
        for feature in features(name):
            for polygon in polygons_of(feature["geometry"]):
                fill(land, width, height, to_pixel_rings(frame, polygon, step), 1)
    for name in cfg["land"].get("minus_last", []):
        for feature in features(name):
            for polygon in polygons_of(feature["geometry"]):
                fill(land, width, height, to_pixel_rings(frame, polygon, step), 0)

    # Regions, by member feature.
    regions = cfg["regions"]
    index = {region["id"]: i + 1 for i, region in enumerate(regions)}
    if len(index) > 254:
        sys.exit("too many regions for one byte per pixel")
    member_of = {}
    for region in regions:
        for member in region["members"]:
            if member in member_of:
                sys.exit("%s is a member of %s and %s" % (member, member_of[member], region["id"]))
            member_of[member] = region["id"]
    key = cfg["members"]["key"]
    labels = new_grid(frame)
    found = set()
    for feature in features(cfg["members"]["input"]):
        member = feature["properties"].get(key)
        region_id = member_of.get(member)
        if region_id is None:
            continue
        found.add(member)
        for polygon in polygons_of(feature["geometry"]):
            fill(labels, width, height, to_pixel_rings(frame, polygon, step), index[region_id])
    missing = sorted(set(member_of) - found)
    if missing:
        sys.exit("%s: members not found in the source: %s" % (cfg["id"], ", ".join(missing)))
    for r in range(height):
        lrow, row = land[r], labels[r]
        for c in range(width):
            if row[c] and not lrow[c]:
                row[c] = 0
    for rule in cfg.get("relabel", []):
        lon0, lat0, lon1, lat1 = rule["box"]
        src, dst = index[rule["from"]], index[rule["to"]]
        for r in range(height):
            row = labels[r]
            for c in range(width):
                if row[c] == src:
                    lon, lat = frame.pixel_to_lonlat(c + 0.5, r + 0.5)
                    if lon0 <= lon <= lon1 and lat0 <= lat <= lat1:
                        row[c] = dst
    if "grow_km" in cfg:
        km_per_px = (frame.y1 - frame.y0) * 111.2 / height
        grow_over_land(labels, land, width, height, cfg["grow_km"] / km_per_px)

    unpinch(labels, width, height)

    # Outlines.
    tolerance = cfg["simplify_px"]
    min_part = cfg["min_part_px"]
    comps = components(labels, width, height)
    out_regions = []
    for region in regions:
        pieces = sorted(comps.get(index[region["id"]], []), key=len, reverse=True)
        if not pieces:
            sys.exit("%s: region %s has no pixels in the frame" % (cfg["id"], region["id"]))
        rings = [simplify_ring(outer_ring(pieces[0], width), tolerance)]
        for piece in pieces[1:]:
            if len(piece) >= min_part:
                rings.append(simplify_ring(outer_ring(piece, width), tolerance))
        label = deepest_point(pieces[0], width, height, frame, globe)
        out_regions.append((region, rings, label))

    # Adjacency: land borders, then crossings.
    min_shared = cfg["min_shared_px"]
    ids = [region["id"] for region in regions]
    adjacent = {region_id: set() for region_id in ids}
    for (a, b), n in shared_borders(labels, width, height, globe).items():
        if n >= min_shared:
            adjacent[ids[a - 1]].add(ids[b - 1])
            adjacent[ids[b - 1]].add(ids[a - 1])
    crossings = []
    for a, b, name in cfg.get("crossings", []):
        if a not in adjacent or b not in adjacent:
            sys.exit("%s: crossing %s has an unknown region" % (cfg["id"], name))
        adjacent[a].add(b)
        adjacent[b].add(a)
        crossings.append({"between": [a, b], "name": name})
    for a, b in cfg.get("cut_borders", []):
        adjacent[a].discard(b)
        adjacent[b].discard(a)

    # Neutral land: land pixels no region holds.
    spare = new_grid(frame)
    for r in range(height):
        lrow, row, srow = land[r], labels[r], spare[r]
        for c in range(width):
            if lrow[c] and not row[c]:
                srow[c] = 1
    unpinch(spare, width, height)
    land_rings = []
    for piece in components(spare, width, height).get(1, []):
        if len(piece) >= cfg["min_land_px"]:
            land_rings.append(simplify_ring(outer_ring(piece, width), tolerance))

    def point(px, py):
        if globe:
            lon, lat = frame.pixel_to_lonlat(px, py)
            return [round(lon, 2), round(max(-90.0, min(90.0, lat)), 2)]
        return [round(min(1.0, max(0.0, px / width)), 4), round(min(1.0, max(0.0, py / height)), 4)]

    def ring_out(ring):
        out = []
        for px, py in ring:
            p = point(px, py)
            if not out or out[-1] != p:
                out.append(p)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
        return out

    result = {
        "id": cfg["id"],
        "name": cfg["name"],
        "projection": cfg["output_projection"],
        "source": cfg["credit"],
        "regions": [],
    }
    for region, rings, label in out_regions:
        entry = {"id": region["id"], "name": region["name"]}
        if "short_name" in region:
            entry["short_name"] = region["short_name"]
        entry["kind"] = region["kind"]
        entry["polygon"] = ring_out(rings[0])
        if len(rings) > 1:
            entry["parts"] = [ring_out(r) for r in rings[1:]]
        entry["label_at"] = region.get("label_at") or point(*label)
        entry["adjacent"] = [other for other in ids if other in adjacent[region["id"]]]
        for k in ("provides", "defense", "pressure_base", "starts_owned"):
            entry[k] = region[k]
        result["regions"].append(entry)
    if "starts" in cfg:
        result["starts"] = cfg["starts"]
    result["water"] = [] if globe else [[[0, 0], [1, 0], [1, 1], [0, 1]]]
    result["land"] = [ring_out(r) for r in land_rings]
    result["crossings"] = crossings
    if "zoom_inset_from" in cfg:
        with open(os.path.join(root, cfg["zoom_inset_from"]), encoding="utf-8") as f:
            inner = Frame.make(json.load(f))
        result["zoom_inset"] = ring_out([frame.to_pixel(lon, lat) for lon, lat in inner.outline_lonlat()])

    out_path = os.path.join(root, cfg["output"])
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(dump(result))
    print("  wrote %s: %d regions, %d land shapes, %d crossings" % (
        cfg["output"], len(result["regions"]), len(land_rings), len(crossings)))
    lonely = [region_id for region_id in ids if not adjacent[region_id]]
    if lonely:
        print("  WARNING: regions with no neighbor: %s" % ", ".join(lonely))
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        write_preview(os.path.join(preview_dir, cfg["id"] + ".png"), labels, land, width, height)


def dump(result):
    """JSON with one region per block and points on one line, so diffs stay readable."""
    lines = ["{"]
    keys = list(result.keys())
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        v = result[k]
        if k == "regions":
            lines.append('\t"regions": [')
            for j, region in enumerate(v):
                lines.append("\t\t{")
                rkeys = list(region.keys())
                for m, rk in enumerate(rkeys):
                    rc = "," if m < len(rkeys) - 1 else ""
                    lines.append("\t\t\t%s: %s%s" % (json.dumps(rk), json.dumps(region[rk], ensure_ascii=False, separators=(", ", ": ")), rc))
                lines.append("\t\t}" + ("," if j < len(v) - 1 else ""))
            lines.append("\t]" + comma)
        elif isinstance(v, list) and v and isinstance(v[0], (dict, list)):
            lines.append("\t%s: [" % json.dumps(k))
            for j, item in enumerate(v):
                lines.append("\t\t%s%s" % (json.dumps(item, ensure_ascii=False, separators=(", ", ": ")), "," if j < len(v) - 1 else ""))
            lines.append("\t]" + comma)
        else:
            lines.append("\t%s: %s%s" % (json.dumps(k), json.dumps(v, ensure_ascii=False, separators=(", ", ": ")), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_preview(path, labels, land, width, height):
    """A PNG of the raster: regions in hashed colors, spare land grey, water dark."""
    raw = bytearray()
    for r in range(height):
        raw.append(0)
        lrow, row = land[r], labels[r]
        for c in range(width):
            v = row[c]
            if v:
                raw += bytes(((v * 97) % 200 + 40, (v * 57) % 200 + 40, (v * 151) % 200 + 40))
            elif lrow[c]:
                raw += b"\x50\x50\x50"
            else:
                raw += b"\x10\x20\x30"
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def fetch(cfg_paths, cache):
    os.makedirs(cache, exist_ok=True)
    for cfg_path in cfg_paths:
        with open(cfg_path, encoding="utf-8") as f:
            cfg = json.load(f)
        for spec in cfg["inputs"].values():
            for file, url in zip(spec["files"], spec.get("urls", [])):
                path = os.path.join(cache, file)
                if os.path.exists(path):
                    continue
                print("fetching %s" % url)
                with urllib.request.urlopen(url) as response, open(path, "wb") as out:
                    out.write(response.read())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["fetch", "build"])
    parser.add_argument("sources", nargs="+", help="data/regions/sources/*.source.json")
    parser.add_argument("--cache", required=True, help="folder for the downloaded source files")
    parser.add_argument("--preview", help="folder for preview PNGs of each raster")
    parser.add_argument("--root", default=".", help="project root (default: the current folder)")
    args = parser.parse_args()
    if args.command == "fetch":
        fetch(args.sources, args.cache)
    else:
        for cfg_path in args.sources:
            build(cfg_path, args.cache, args.preview, args.root)


if __name__ == "__main__":
    main()
