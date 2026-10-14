"""Dựng ảnh nền địa hình cho bản đồ màn "Lên lộ trình": nhiều mức phóng to,
mỗi mức chia ô 512 px (game chỉ nạp các ô đang nhìn thấy).

- Độ cao + độ sâu biển: Terrain Tiles (fetch_terrain.py), public domain.
- Đất liền / hồ: Natural Earth 10m (bản theo góc nhìn Việt Nam), public domain.
- Đất Việt Nam tô màu theo độ cao + bóng đổ núi; nước láng giềng nhạt hơn để
  Việt Nam nổi bật; biển đậm dần theo độ sâu.

Cần numpy + pillow:
    python3 -m venv .venv && .venv/bin/pip install numpy pillow
    .venv/bin/python tool/route_data/build_map_tiles.py
"""
import json
import math
import os
import shutil

import numpy as np
from PIL import Image, ImageDraw

from map_common import K, LEVELS, TERRAIN_DIR, TILE, TILE_OUT_DIR, level_tiles, polygons, to_map

COUNTRIES = 'asset_source/map_natural_earth/ne_10m_admin_0_countries_vnm.geojson'
LAKES = 'asset_source/map_ne_water/ne_10m_lakes.geojson'
DART_OUT = 'lib/resource/vn_map_tiles.dart'
MARGIN = 2  # điểm ảnh thêm ở mép để tính độ dốc liền mạch giữa các ô

# Màu theo độ cao (m) — xanh đồng bằng, vàng nâu cao nguyên, nâu núi cao.
LAND_RAMP = [
    (0, (188, 219, 158)), (30, (174, 212, 146)), (150, (158, 200, 134)), (400, (170, 198, 136)),
    (800, (198, 200, 146)), (1200, (212, 192, 144)), (1700, (198, 170, 132)), (2400, (176, 150, 122)),
    (3000, (226, 220, 212)),
]
# Màu theo độ sâu (m) — ven bờ trong, ra khơi xanh đậm.
SEA_RAMP = [
    (0, (186, 226, 238)), (20, (170, 218, 236)), (60, (148, 204, 230)), (150, (122, 186, 222)),
    (500, (98, 166, 212)), (1500, (80, 146, 200)), (3000, (66, 128, 186)), (5000, (54, 110, 170)),
]
LAKE = np.array((152, 202, 230), np.float32)
NEIGHBOR_TINT = np.array((240, 236, 226), np.float32)


def ramp(values, stops):
    xs = np.array([s[0] for s in stops], np.float32)
    out = np.empty(values.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(values, xs, np.array([s[1][c] for s in stops], np.float32))
    return out


class Terrain:
    """Đọc độ cao từ các ô Terrarium (Web Mercator) và lấy mẫu song tuyến."""

    def __init__(self, zoom):
        self.zoom = zoom
        self.tiles = {}

    def tile(self, x, y):
        if (x, y) not in self.tiles:
            a = np.asarray(Image.open(f'{TERRAIN_DIR}/{self.zoom}_{x}_{y}.png').convert('RGB'), np.float32)
            self.tiles[(x, y)] = a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768
        return self.tiles[(x, y)]

    def sample(self, lon, lat):
        n = 2 ** self.zoom * 256
        px = (lon + 180) / 360 * n - 0.5
        r = np.radians(lat)
        py = (1 - np.log(np.tan(r) + 1 / np.cos(r)) / np.pi) / 2 * n - 0.5
        x0, x1 = int(np.floor(px.min())) // 256, int(np.floor(px.max()) + 1) // 256
        y0, y1 = int(np.floor(py.min())) // 256, int(np.floor(py.max()) + 1) // 256
        mosaic = np.zeros(((y1 - y0 + 1) * 256, (x1 - x0 + 1) * 256), np.float32)
        for tx in range(x0, x1 + 1):
            for ty in range(y0, y1 + 1):
                mosaic[(ty - y0) * 256:(ty - y0 + 1) * 256, (tx - x0) * 256:(tx - x0 + 1) * 256] = self.tile(tx, ty)
        fx, fy = px - x0 * 256, py - y0 * 256
        ix = np.clip(np.floor(fx).astype(int), 0, mosaic.shape[1] - 2)
        iy = np.clip(np.floor(fy).astype(int), 0, mosaic.shape[0] - 2)
        tx, ty = np.clip(fx - ix, 0, 1), np.clip(fy - iy, 0, 1)
        top = mosaic[iy, ix] * (1 - tx) + mosaic[iy, ix + 1] * tx
        bottom = mosaic[iy + 1, ix] * (1 - tx) + mosaic[iy + 1, ix + 1] * tx
        return top * (1 - ty) + bottom * ty


def load_shapes():
    """Đa giác đất liền theo toạ độ bản đồ, kèm khung bao để lọc nhanh."""
    def prepared(rings):
        out = []
        for ring in rings:
            pts = [to_map(lon, lat) for lon, lat in ring]
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            out.append((pts, (min(xs), min(ys), max(xs), max(ys))))
        return out

    data = json.load(open(COUNTRIES, encoding='utf-8'))
    vn, other = [], []
    for f in data['features']:
        target = vn if f['properties'].get('NAME') == 'Vietnam' else other
        for poly in polygons(f['geometry']):
            target.append(poly)
    lakes = [poly for f in json.load(open(LAKES, encoding='utf-8'))['features'] for poly in polygons(f['geometry'])]
    return prepared([p[0] for p in vn]), prepared([p[0] for p in other]), prepared([p[0] for p in lakes])


def rasterize(shapes, ppu, ox, oy, width, height, ss=3):
    """Mặt nạ 0..1 (khử răng cưa bằng vẽ to rồi thu nhỏ)."""
    img = Image.new('L', (width * ss, height * ss), 0)
    d = ImageDraw.Draw(img)
    x0, y0 = ox / ppu, oy / ppu
    x1, y1 = (ox + width) / ppu, (oy + height) / ppu
    for pts, (bx0, by0, bx1, by1) in shapes:
        if bx1 < x0 or bx0 > x1 or by1 < y0 or by0 > y1:
            continue
        ring = [((x * ppu - ox) * ss, (y * ppu - oy) * ss) for x, y in pts]
        if len(ring) >= 3:
            d.polygon(ring, fill=255)
    img = img.resize((width, height), Image.BOX)
    return np.asarray(img, np.float32) / 255


def hillshade(elev, ppu, lat, z):
    """Độ sáng tương đối (1 = mặt phẳng), nắng chiếu từ tây bắc."""
    dy_m = 110570 / ppu
    dx_m = 111320 * np.cos(np.radians(lat)) / K / ppu
    gy, gx = np.gradient(elev)
    dzdx = gx / dx_m * z
    dzdn = -gy / dy_m * z
    az, alt = math.radians(315), math.radians(45)
    lx, ly, lz = math.cos(alt) * math.sin(az), math.cos(alt) * math.cos(az), math.sin(alt)
    hs = (-dzdx * lx - dzdn * ly + lz) / np.sqrt(dzdx * dzdx + dzdn * dzdn + 1)
    return np.clip(hs, 0, 1) / lz


def render_strip(level, terrain, shapes, j, ii):
    ppu = level['ppu']
    vn_shapes, other_shapes, lake_shapes = shapes
    ox, oy = ii.start * TILE, j * TILE - MARGIN
    width, height = len(ii) * TILE, TILE + 2 * MARGIN
    xs = (ox + np.arange(width) + 0.5) / ppu
    ys = (oy + np.arange(height) + 0.5) / ppu
    mx, my = np.meshgrid(xs, ys)
    lon, lat = mx / K + 88.0, 32.0 - my
    elev = terrain.sample(lon, lat)

    vn = rasterize(vn_shapes, ppu, ox, oy, width, height)
    other = rasterize(other_shapes, ppu, ox, oy, width, height)
    lakes = rasterize(lake_shapes, ppu, ox, oy, width, height)
    other = np.clip(other - vn, 0, 1)
    land = np.clip(vn + other, 0, 1)

    # Độ dốc mạnh tay hơn ở mức xa (ảnh thô làm núi bẹt đi).
    z = 2.2 * math.sqrt(400 / ppu)
    land_elev = np.maximum(elev, 1)
    shade = hillshade(np.where(land > 0.02, land_elev, 0), ppu, lat, z)
    land_rgb = ramp(land_elev, LAND_RAMP) * np.clip(1 + 0.6 * (shade - 1), 0.45, 1.3)[..., None]
    neighbor_rgb = land_rgb * 0.45 + NEIGHBOR_TINT * 0.55

    depth = np.maximum(-elev, 2)
    sea_shade = hillshade(-depth, ppu, lat, z * 0.35)
    sea_rgb = ramp(depth, SEA_RAMP) * np.clip(1 + 0.25 * (sea_shade - 1), 0.85, 1.12)[..., None]

    rgb = sea_rgb * (1 - land)[..., None] + land_rgb * vn[..., None] + neighbor_rgb * other[..., None]
    rgb = rgb * (1 - lakes)[..., None] + LAKE * lakes[..., None]
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)[MARGIN:-MARGIN]
    return rgb, vn[MARGIN:-MARGIN], land[MARGIN:-MARGIN], depth[MARGIN:-MARGIN]


def keep_tile(index, vn, land, depth):
    if index == 0:
        return True
    if index == len(LEVELS) - 1:
        return vn.max() > 0  # mức gần nhất chỉ cho đất Việt Nam (tiết kiệm dung lượng)
    return land.max() > 0 or depth.min() < 80


def main():
    shapes = load_shapes()
    if os.path.isdir(TILE_OUT_DIR):
        shutil.rmtree(TILE_OUT_DIR)
    os.makedirs(TILE_OUT_DIR)
    kept = []
    total = 0
    for index, level in enumerate(LEVELS):
        terrain = Terrain(level['terrain_zoom'])
        ii, jj = level_tiles(level)
        level_kept = []
        for j in jj:
            rgb, vn, land, depth = render_strip(level, terrain, shapes, j, ii)
            for col, i in enumerate(ii):
                cut = slice(col * TILE, (col + 1) * TILE)
                if not keep_tile(index, vn[:, cut], land[:, cut], depth[:, cut]):
                    continue
                path = f'{TILE_OUT_DIR}/l{index}_{i}_{j}.jpg'
                Image.fromarray(rgb[:, cut]).save(path, quality=84, optimize=True)
                total += os.path.getsize(path)
                level_kept.append((i, j))
        kept.append(level_kept)
        print(f'mức {index} ({level["ppu"]} px/đv): {len(level_kept)} / {len(ii) * len(jj)} ô')
    print('tổng', total // 1024, 'KB')
    write_dart(kept)


def write_dart(kept):
    out = [
        '// GENERATED — chạy tool/route_data/build_map_tiles.py để dựng lại.',
        '// Nền địa hình: Terrain Tiles (Mapzen / AWS Open Data) + Natural Earth.',
        '',
        'abstract class VnMapTiles {',
        f'  static const int tileSize = {TILE};',
        '',
        '  /// Số điểm ảnh trên 1 đơn vị bản đồ của từng mức.',
        f'  static const List<double> levelPpu = [{", ".join(str(float(l["ppu"])) for l in LEVELS)}];',
        '',
        '  /// Các ô có ảnh ở từng mức, mã hoá i * 1000 + j.',
        '  static const List<Set<int>> tiles = [',
    ]
    for level_kept in kept:
        out.append('    {' + ', '.join(str(i * 1000 + j) for i, j in level_kept) + '},')
    out += ['  ];', '}', '']
    open(DART_OUT, 'w', encoding='utf-8').write('\n'.join(out))
    print('wrote', DART_OUT)


if __name__ == '__main__':
    main()
