"""Dựng dữ liệu lộ trình + các nét vector của bản đồ cho màn "Lên lộ trình".

1. Quãng đường, thời gian lái và phần cao tốc giữa các điểm: OSRM (dữ liệu
   © OpenStreetMap contributors). Kết quả lưu ở osrm_cache.json để chạy lại
   không cần mạng.
2. Hình dạng thật của từng đoạn đường (OSRM) và các tuyến cao tốc.
3. Bờ biển, biên giới (Natural Earth 10m, bản theo góc nhìn Việt Nam — Hoàng Sa
   và Trường Sa thuộc Việt Nam) và sông (Natural Earth 10m). Public domain.

Sinh ra:
    lib/resource/vn_route_data.dart   điểm + đoạn nối
    lib/resource/vn_map_shapes.dart   nét vẽ bản đồ

Ảnh nền địa hình dựng riêng bằng build_map_tiles.py.

Chạy từ thư mục gốc project:
    python3 -E tool/route_data/build_routes.py
"""
import json
import math
import os
import subprocess
import time

from map_common import LINKS, PLACES, lines, polygons, simplify, to_map

COUNTRIES = 'asset_source/map_natural_earth/ne_10m_admin_0_countries_vnm.geojson'
RIVERS = 'asset_source/map_ne_water/ne_10m_rivers_lake_centerlines.geojson'
CACHE = 'tool/route_data/osrm_cache.json'
ROUTE_DART = 'lib/resource/vn_route_data.dart'
SHAPES_DART = 'lib/resource/vn_map_shapes.dart'

# Vùng lấy nét vẽ (độ): rộng hơn Việt Nam một chút cho thấy nước láng giềng.
REGION = (97.0, 124.0, 2.0, 28.0)


def curl_json(url):
    # Python đi kèm Xcode dùng LibreSSL cũ, bắt tay TLS lỗi — gọi qua curl.
    out = subprocess.run(['curl', '-sS', '--max-time', '90', '-A', 've-que-thoi-dev/1.0 (route precompute)', url],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def is_expressway(step):
    return 'CT.' in (step.get('ref') or '') or 'cao tốc' in (step.get('name') or '').lower()


# --------------------------------------------------------------- OSRM
def osrm(a, b, cache):
    key = f'{a[0]}|{b[0]}'
    if key not in cache:
        data = curl_json(f'https://router.project-osrm.org/route/v1/driving/{a[3]},{a[2]};{b[3]},{b[2]}'
                         '?overview=false&steps=true')
        route = data['routes'][0]
        ct = sum(st['distance'] for leg in route['legs'] for st in leg['steps'] if is_expressway(st))
        cache[key] = {'km': route['distance'] / 1000, 'hours': route['duration'] / 3600, 'ctKm': ct / 1000}
        time.sleep(1.1)  # tôn trọng giới hạn máy chủ demo
    return cache[key]


def osrm_geometry(a, b, cache):
    """Hình dạng đường đi giữa hai điểm, đã rút gọn, [(kinh, vĩ)]."""
    key = f'geom|{a[0]}|{b[0]}'
    if key not in cache:
        data = curl_json(f'https://router.project-osrm.org/route/v1/driving/{a[3]},{a[2]};{b[3]},{b[2]}'
                         '?overview=full&geometries=geojson')
        coords = data['routes'][0]['geometry']['coordinates']
        cache[key] = [[round(x, 5), round(y, 5)] for x, y in simplify(coords, 0.001)]
        time.sleep(1.1)
    return cache[key]


# Các tuyến dài để biết đoạn nào có cao tốc: đi xa thì ô tô chạy thẳng trên
# cao tốc, còn đi từng chặng ngắn giữa hai trung tâm thành phố OSRM hay chọn
# quốc lộ — nên lấy phần cao tốc của tuyến dài rồi gán về từng đoạn nối.
CORRIDORS = [
    ('ha_noi', 'da_nang'), ('da_nang', 'nha_trang'), ('nha_trang', 'tp_hcm'), ('tp_hcm', 'ca_mau'),
    ('ha_noi', 'lang_son'), ('ha_noi', 'ha_long'), ('ha_noi', 'lao_cai'), ('tp_hcm', 'vung_tau'),
    ('ha_noi', 'thai_nguyen'), ('tp_hcm', 'can_tho'),
]


def corridor_steps(a, b, cache):
    key = f'corridor|{a[0]}|{b[0]}'
    if key not in cache:
        route = curl_json(f'https://router.project-osrm.org/route/v1/driving/{a[3]},{a[2]};{b[3]},{b[2]}'
                          '?overview=false&steps=true&geometries=geojson')['routes'][0]
        cache[key] = [st['geometry']['coordinates'] for leg in route['legs'] for st in leg['steps']
                      if is_expressway(st)]
        time.sleep(1.1)
    return cache[key]


def point_segment_km(p, a, b):
    """Khoảng cách xấp xỉ (km) từ điểm p tới đoạn thẳng ab, toạ độ (kinh, vĩ)."""
    kx = 111.32 * math.cos(math.radians(p[1]))
    ky = 110.57
    px, py = p[0] * kx, p[1] * ky
    ax, ay, bx, by = a[0] * kx, a[1] * ky, b[0] * kx, b[1] * ky
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def expressway_by_link(cache):
    by_id = {p[0]: p for p in PLACES}
    total = {link: 0.0 for link in LINKS}
    for a, b in CORRIDORS:
        for line in corridor_steps(by_id[a], by_id[b], cache):
            for p, q in zip(line, line[1:]):
                mid = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
                seg_km = point_segment_km(p, q, q)
                best = min(LINKS, key=lambda l: point_segment_km(mid, (by_id[l[0]][3], by_id[l[0]][2]),
                                                                 (by_id[l[1]][3], by_id[l[1]][2])))
                total[best] += seg_km
    return total


# Bổ sung tay: OSRM (dữ liệu demo) chưa đi qua cao tốc TP.HCM – Trung Lương –
# Mỹ Thuận – Cần Thơ dù tuyến đã khai thác. Số km lấy xấp xỉ, chỉ để chia
# loại đường trong game.
MANUAL_EXPRESSWAY_KM = {
    ('tp_hcm', 'my_tho'): 50.0,
    ('my_tho', 'can_tho'): 85.0,
}


def build_routes(cache):
    by_id = {p[0]: p for p in PLACES}
    links = []
    for a, b in LINKS:
        r = dict(osrm(by_id[a], by_id[b], cache))
        geom = osrm_geometry(by_id[a], by_id[b], cache)
        json.dump(cache, open(CACHE, 'w'), ensure_ascii=False, indent=1)
        links.append((a, b, r, geom))
    corridor = expressway_by_link(cache)
    json.dump(cache, open(CACHE, 'w'), ensure_ascii=False, indent=1)
    for a, b, r, _ in links:
        # Lấy phần cao tốc lớn hơn trong hai cách tính, không vượt quá 95% đoạn.
        r['ctKm'] = min(r['km'] * 0.95, max(r['ctKm'], corridor[(a, b)], MANUAL_EXPRESSWAY_KM.get((a, b), 0)))
        print(f'{a:>14} → {b:<14} {r["km"]:6.1f} km  {r["hours"]:4.1f} h  cao tốc {r["ctKm"]:5.1f} km')
    return links


def expressway_lines(cache, links):
    """Các tuyến cao tốc để vẽ trên bản đồ, toạ độ (kinh, vĩ)."""
    result = []
    for a, b in CORRIDORS:
        for line in cache[f'corridor|{a}|{b}']:
            if len(line) >= 2:
                result.append(simplify(line, 0.002))
    for a, b, _, geom in links:
        if (a, b) in MANUAL_EXPRESSWAY_KM:
            result.append(geom)
    return result


# ------------------------------------------------------- Nét vẽ bản đồ
def in_region(ring):
    lo0, lo1, la0, la1 = REGION
    return any(lo0 < x < lo1 and la0 < y < la1 for x, y in ring)


def country_edges():
    """Tách viền các nước thành: bờ biển Việt Nam, biên giới Việt Nam, biên giới
    giữa các nước khác. Một cạnh là biên giới khi cả hai đầu cạnh cùng là đỉnh
    của hai nước (Natural Earth dùng chung đỉnh ở đường biên)."""
    data = json.load(open(COUNTRIES, encoding='utf-8'))
    owners = {}
    rings = []
    for f in data['features']:
        name = f['properties'].get('NAME')
        for poly in polygons(f['geometry']):
            ring = poly[0]
            if not in_region(ring):
                continue
            rings.append((name, ring))
            for x, y in ring:
                owners.setdefault((round(x, 6), round(y, 6)), set()).add(name)

    def shared(p):
        return len(owners[(round(p[0], 6), round(p[1], 6))]) >= 2

    vn_coast, vn_border, other_border, vn_islands = [], [], [], []

    def flush(name, kind, pts):
        if len(pts) < 2:
            return
        if name == 'Vietnam':
            (vn_coast if kind == 'coast' else vn_border).append(pts)
        elif kind == 'border':
            other_border.append(pts)

    for name, ring in rings:
        if name == 'Vietnam' and len(ring) < 40 and ring[0][0] > 109.3:
            vn_islands.append(ring)  # đảo nhỏ ngoài khơi: vẽ cả mảng cho thấy rõ
        current, current_kind = [], None
        for p, q in zip(ring, ring[1:]):
            kind = 'border' if shared(p) and shared(q) else 'coast'
            if kind != current_kind:
                flush(name, current_kind, current)
                current = [p]
            current.append(q)
            current_kind = kind
        flush(name, current_kind, current)
    # Biên giới giữa các nước khác bị lặp hai lần (mỗi nước một lần): bỏ trùng.
    seen, unique = set(), []
    for line in other_border:
        key = frozenset((round(x, 4), round(y, 4)) for x, y in line)
        if key not in seen:
            seen.add(key)
            unique.append(line)
    # Biên giới Việt Nam cũng là biên giới của nước bên kia — bỏ khỏi danh sách kia.
    vn_keys = {(round(x, 4), round(y, 4)) for line in vn_border for x, y in line}
    unique = [l for l in unique if sum((round(x, 4), round(y, 4)) in vn_keys for x, y in l) < len(l) * 0.8]
    return vn_coast, vn_border, unique, vn_islands


def river_lines():
    data = json.load(open(RIVERS, encoding='utf-8'))
    lo0, lo1, la0, la1 = 100.0, 112.0, 8.0, 24.5
    result = []
    for f in data['features']:
        rank = f['properties'].get('scalerank') or 9
        for line in lines(f['geometry']):
            if any(lo0 < x < lo1 and la0 < y < la1 for x, y in line):
                result.append((rank, line))
    return result


# --------------------------------------------------------------- Dart
def flat(points, tolerance):
    pts = simplify([to_map(lon, lat) for lon, lat in points], tolerance)
    return '[' + ', '.join(f'{x:.4f}, {y:.4f}' for x, y in pts) + ']'


def write_route_dart(links):
    side = {'r': 'right', 'l': 'left', 't': 'top', 'b': 'bottom'}
    out = [
        '// GENERATED — chạy tool/route_data/build_routes.py để dựng lại.',
        '// Quãng đường: OSRM trên dữ liệu © OpenStreetMap contributors (ước tính).',
        '',
        "import '../model/place.dart';",
        '',
        'abstract class VnRouteData {',
        '  static const List<Place> places = [',
    ]
    for pid, name, lat, lon, label in PLACES:
        x, y = to_map(lon, lat)
        out.append(f"    Place(id: '{pid}', name: '{name}', x: {x:.4f}, y: {y:.4f}, label: LabelSide.{side[label]}),")
    out += ['  ];', '', '  static const List<RoadLink> links = [']
    for a, b, r, _ in links:
        out.append(
            f"    RoadLink(a: '{a}', b: '{b}', km: {r['km']:.1f}, expresswayKm: {r['ctKm']:.1f}, carHours: {r['hours']:.2f}),")
    out += ['  ];', '}', '']
    open(ROUTE_DART, 'w', encoding='utf-8').write('\n'.join(out))
    print('wrote', ROUTE_DART)


def write_shapes_dart(links, expressways):
    vn_coast, vn_border, other_border, islands = country_edges()
    rivers = river_lines()

    def block(name, doc, items, tolerance):
        rows = [f'  /// {doc}', f'  static const List<List<double>> {name} = [']
        for pts in items:
            if len(pts) >= 2:
                rows.append(f'    {flat(pts, tolerance)},')
        rows.append('  ];')
        return rows

    out = [
        '// GENERATED — chạy tool/route_data/build_routes.py để dựng lại.',
        '// Bờ biển, biên giới, sông: Natural Earth 10m (public domain).',
        '// Hình dạng đường: OSRM trên dữ liệu © OpenStreetMap contributors.',
        '//',
        '// Mỗi nét là một dãy x0, y0, x1, y1… theo toạ độ bản đồ (xem MapProjection).',
        '',
        'abstract class VnMapShapes {',
    ]
    out += block('vietnamCoast', 'Bờ biển Việt Nam (kể cả đảo).', vn_coast, 0.003)
    out += block('vietnamBorder', 'Biên giới trên đất liền của Việt Nam.', vn_border, 0.003)
    out += block('otherBorders', 'Biên giới giữa các nước láng giềng.', other_border, 0.008)
    out += block('islands', 'Các đảo nhỏ ngoài khơi (vòng khép kín).', islands, 0.0005)
    out += block('majorRivers', 'Sông lớn (Hồng, Mê Kông, Đà...).', [l for r, l in rivers if r <= 6], 0.004)
    out += block('rivers', 'Sông nhỏ hơn.', [l for r, l in rivers if r > 6], 0.005)
    out += block('expressways', 'Các tuyến cao tốc.', expressways, 0.003)
    out += block('linkPaths', 'Hình dạng từng đoạn nối, cùng thứ tự VnRouteData.links (đi từ a tới b).',
                 [geom for _, _, _, geom in links], 0.002)
    out += ['}', '']
    open(SHAPES_DART, 'w', encoding='utf-8').write('\n'.join(out))
    print('wrote', SHAPES_DART, os.path.getsize(SHAPES_DART) // 1024, 'KB')


if __name__ == '__main__':
    osrm_cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    built = build_routes(osrm_cache)
    write_route_dart(built)
    write_shapes_dart(built, expressway_lines(osrm_cache, built))
