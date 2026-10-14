"""Dữ liệu và phép chiếu dùng chung cho các script dựng bản đồ / lộ trình.

Hệ toạ độ bản đồ (dùng cả trong game): 1 đơn vị = 1 độ vĩ (~110,6 km).
    x = (kinh độ - LON0) * K      (K = cos 15°: co kinh độ theo vĩ độ giữa VN)
    y = LAT1 - vĩ độ              (y tăng dần xuống phía nam)
"""
import math

K = math.cos(math.radians(15))
LON0, LAT1 = 88.0, 32.0

TILE = 512
ASSET_SOURCE = 'asset_source'
TERRAIN_DIR = f'{ASSET_SOURCE}/terrain_tiles'
TILE_OUT_DIR = 'assets/images/map'

# Các mức ảnh nền: ppu = số điểm ảnh trên 1 đơn vị bản đồ. Mức cao chỉ phủ
# vùng quanh Việt Nam; chỗ nào không có ô ở mức cao thì game vẽ mức thấp hơn.
LEVELS = [
    {'ppu': 40, 'lon': (88.0, 138.0), 'lat': (-2.0, 32.0), 'terrain_zoom': 6},
    {'ppu': 100, 'lon': (97.0, 124.0), 'lat': (2.0, 28.0), 'terrain_zoom': 7},
    {'ppu': 200, 'lon': (100.0, 118.5), 'lat': (5.0, 25.0), 'terrain_zoom': 8},
    {'ppu': 400, 'lon': (102.0, 110.0), 'lat': (8.2, 23.5), 'terrain_zoom': 9},
]


def to_map(lon, lat):
    return (lon - LON0) * K, LAT1 - lat


def to_lonlat(x, y):
    return x / K + LON0, LAT1 - y


def level_tiles(level):
    """Dải chỉ số ô (i, j) phủ vùng của một mức."""
    ppu = level['ppu']
    x0, y0 = to_map(level['lon'][0], level['lat'][1])
    x1, y1 = to_map(level['lon'][1], level['lat'][0])
    i0, i1 = math.floor(x0 * ppu / TILE), math.ceil(x1 * ppu / TILE)
    j0, j1 = math.floor(y0 * ppu / TILE), math.ceil(y1 * ppu / TILE)
    return range(i0, i1), range(j0, j1)


def merc_tile_xy(lon, lat, zoom):
    n = 2 ** zoom
    r = math.radians(lat)
    return (lon + 180) / 360 * n, (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n


def terrain_tile_range(level):
    """Các ô độ cao (Web Mercator) cần để phủ hết các ô ảnh của một mức."""
    ppu = level['ppu']
    ii, jj = level_tiles(level)
    lon0, lat1 = to_lonlat(ii.start * TILE / ppu, jj.start * TILE / ppu)
    lon1, lat0 = to_lonlat(ii.stop * TILE / ppu, jj.stop * TILE / ppu)
    zoom = level['terrain_zoom']
    tx0, ty0 = merc_tile_xy(lon0, lat1, zoom)
    tx1, ty1 = merc_tile_xy(lon1, lat0, zoom)
    return range(int(tx0), int(tx1) + 1), range(int(ty0), int(ty1) + 1)


# (id, tên hiển thị, vĩ độ, kinh độ, phía đặt nhãn: r/l/t/b, tỉnh cũ)
# "Tỉnh cũ" = tên tỉnh quen thuộc trước đợt sáp nhập 2025, chỉ ghi khi khác tên
# điểm: hiện mờ trong danh sách chọn và tìm được theo tên đó ("quang binh" ra
# Đồng Hới).
PLACES = [
    # Miền Bắc — đồng bằng sông Hồng, Đông Bắc
    ('ha_noi', 'Hà Nội', 21.0285, 105.8542, 'l', None),
    ('bac_ninh', 'Bắc Ninh', 21.1861, 106.0763, 'b', None),
    ('bac_giang', 'Bắc Giang', 21.2731, 106.1946, 'r', None),
    ('vinh_yen', 'Vĩnh Yên', 21.3089, 105.6049, 't', 'Vĩnh Phúc'),
    ('viet_tri', 'Việt Trì', 21.3227, 105.4020, 'l', 'Phú Thọ'),
    ('thai_nguyen', 'Thái Nguyên', 21.5942, 105.8482, 'l', None),
    ('tuyen_quang', 'Tuyên Quang', 21.8233, 105.2180, 'r', None),
    ('bac_kan', 'Bắc Kạn', 22.1470, 105.8348, 'r', None),
    ('ha_giang', 'Hà Giang', 22.8233, 104.9836, 'r', None),
    ('cao_bang', 'Cao Bằng', 22.6657, 106.2570, 'r', None),
    ('lang_son', 'Lạng Sơn', 21.8537, 106.7615, 'r', None),
    ('mong_cai', 'Móng Cái', 21.5243, 107.9662, 'l', 'Quảng Ninh'),
    ('ha_long', 'Hạ Long', 20.9517, 107.0800, 'r', 'Quảng Ninh'),
    ('hai_duong', 'Hải Dương', 20.9373, 106.3146, 'b', None),
    ('hai_phong', 'Hải Phòng', 20.8449, 106.6881, 'r', None),
    ('hung_yen', 'Hưng Yên', 20.6464, 106.0511, 'r', None),
    ('phu_ly', 'Phủ Lý', 20.5411, 105.9139, 'l', 'Hà Nam'),
    ('nam_dinh', 'Nam Định', 20.4200, 106.1683, 'r', None),
    ('thai_binh', 'Thái Bình', 20.4463, 106.3366, 'r', None),
    ('ninh_binh', 'Ninh Bình', 20.2506, 105.9745, 'l', None),
    # Miền Bắc — Tây Bắc
    ('lao_cai', 'Lào Cai', 22.4856, 103.9707, 'r', None),
    ('sa_pa', 'Sa Pa', 22.3364, 103.8438, 'b', 'Lào Cai'),
    ('lai_chau', 'Lai Châu', 22.3964, 103.4582, 'l', None),
    ('dien_bien', 'Điện Biên Phủ', 21.3860, 103.0230, 'b', 'Điện Biên'),
    ('son_la', 'Sơn La', 21.3256, 103.9188, 'r', None),
    ('yen_bai', 'Yên Bái', 21.7229, 104.9113, 'l', None),
    ('moc_chau', 'Mộc Châu', 20.8456, 104.6380, 'b', 'Sơn La'),
    ('hoa_binh', 'Hoà Bình', 20.8172, 105.3376, 'l', None),
    # Miền Trung
    ('thanh_hoa', 'Thanh Hoá', 19.8067, 105.7852, 'l', None),
    ('vinh', 'Vinh', 18.6796, 105.6813, 'l', 'Nghệ An'),
    ('ha_tinh', 'Hà Tĩnh', 18.3428, 105.9057, 'r', None),
    ('dong_hoi', 'Đồng Hới', 17.4689, 106.6223, 'r', 'Quảng Bình'),
    ('dong_ha', 'Đông Hà', 16.8163, 107.1003, 'r', 'Quảng Trị'),
    ('hue', 'Huế', 16.4637, 107.5909, 'r', 'Thừa Thiên Huế'),
    ('da_nang', 'Đà Nẵng', 16.0544, 108.2022, 'r', None),
    ('hoi_an', 'Hội An', 15.8801, 108.3380, 'r', 'Quảng Nam'),
    ('tam_ky', 'Tam Kỳ', 15.5736, 108.4740, 'r', 'Quảng Nam'),
    ('quang_ngai', 'Quảng Ngãi', 15.1214, 108.8044, 'r', None),
    ('quy_nhon', 'Quy Nhơn', 13.7829, 109.2196, 'r', 'Bình Định'),
    ('tuy_hoa', 'Tuy Hoà', 13.0882, 109.0929, 'r', 'Phú Yên'),
    ('nha_trang', 'Nha Trang', 12.2388, 109.1967, 'r', 'Khánh Hoà'),
    ('phan_rang', 'Phan Rang', 11.5643, 108.9886, 'r', 'Ninh Thuận'),
    ('phan_thiet', 'Phan Thiết', 10.9289, 108.1021, 'r', 'Bình Thuận'),
    # Tây Nguyên
    ('kon_tum', 'Kon Tum', 14.3497, 108.0005, 'l', None),
    ('pleiku', 'Pleiku', 13.9833, 108.0000, 'l', 'Gia Lai'),
    ('buon_ma_thuot', 'Buôn Ma Thuột', 12.6667, 108.0500, 'l', 'Đắk Lắk'),
    ('gia_nghia', 'Gia Nghĩa', 12.0042, 107.6907, 'l', 'Đắk Nông'),
    ('da_lat', 'Đà Lạt', 11.9404, 108.4583, 'r', 'Lâm Đồng'),
    ('bao_loc', 'Bảo Lộc', 11.5480, 107.8077, 'r', 'Lâm Đồng'),
    # Miền Nam — Đông Nam Bộ
    ('dong_xoai', 'Đồng Xoài', 11.5349, 106.8832, 'l', 'Bình Phước'),
    ('tay_ninh', 'Tây Ninh', 11.3100, 106.0983, 'l', None),
    ('thu_dau_mot', 'Thủ Dầu Một', 10.9804, 106.6519, 't', 'Bình Dương'),
    ('bien_hoa', 'Biên Hoà', 10.9574, 106.8426, 'r', 'Đồng Nai'),
    ('tp_hcm', 'TP. Hồ Chí Minh', 10.7769, 106.7009, 'l', None),
    ('vung_tau', 'Vũng Tàu', 10.4114, 107.1362, 'r', 'Bà Rịa – Vũng Tàu'),
    # Miền Nam — đồng bằng sông Cửu Long
    ('tan_an', 'Tân An', 10.5359, 106.4137, 'l', 'Long An'),
    ('my_tho', 'Mỹ Tho', 10.3600, 106.3600, 'r', 'Tiền Giang'),
    ('ben_tre', 'Bến Tre', 10.2433, 106.3756, 'b', None),
    ('tra_vinh', 'Trà Vinh', 9.9347, 106.3453, 'r', None),
    ('vinh_long', 'Vĩnh Long', 10.2537, 105.9722, 'l', None),
    ('cao_lanh', 'Cao Lãnh', 10.4602, 105.6329, 't', 'Đồng Tháp'),
    ('can_tho', 'Cần Thơ', 10.0452, 105.7469, 'l', None),
    ('long_xuyen', 'Long Xuyên', 10.3864, 105.4352, 'l', 'An Giang'),
    ('chau_doc', 'Châu Đốc', 10.7007, 105.1169, 'l', 'An Giang'),
    ('ha_tien', 'Hà Tiên', 10.3831, 104.4875, 'b', 'Kiên Giang'),
    ('rach_gia', 'Rạch Giá', 10.0124, 105.0809, 'l', 'Kiên Giang'),
    ('vi_thanh', 'Vị Thanh', 9.7845, 105.4701, 'l', 'Hậu Giang'),
    ('soc_trang', 'Sóc Trăng', 9.6025, 105.9739, 'r', None),
    ('bac_lieu', 'Bạc Liêu', 9.2941, 105.7278, 'r', None),
    ('ca_mau', 'Cà Mau', 9.1769, 105.1524, 'l', None),
]

# Vùng miền để nhóm danh sách chọn điểm.
HIGHLANDS = {'kon_tum', 'pleiku', 'buon_ma_thuot', 'gia_nghia', 'da_lat', 'bao_loc'}


def zone_of(place):
    pid, _, lat, lon = place[:4]
    if pid in HIGHLANDS:
        return 'highlands'
    if lat >= 19.95:
        return 'north'
    if lat > 12 or lon > 107.5:
        return 'central'
    return 'south'


# Đoạn nối giữa hai điểm kề nhau (dọc quốc lộ / cao tốc). Có thể có đường
# song song (vd. Hà Nội – Hải Phòng thẳng cao tốc, hoặc qua Hải Dương theo QL5):
# tìm đường tự chọn đường nhanh nhất.
LINKS = [
    ('ha_noi', 'bac_ninh'), ('bac_ninh', 'lang_son'), ('ha_noi', 'thai_nguyen'), ('ha_noi', 'lao_cai'),
    ('ha_noi', 'hai_phong'), ('hai_phong', 'ha_long'), ('bac_ninh', 'ha_long'),
    ('ha_noi', 'phu_ly'), ('phu_ly', 'ninh_binh'), ('phu_ly', 'nam_dinh'), ('nam_dinh', 'thai_binh'),
    ('thai_binh', 'hai_phong'), ('nam_dinh', 'ninh_binh'), ('ninh_binh', 'thanh_hoa'),
    ('thanh_hoa', 'vinh'), ('vinh', 'ha_tinh'), ('ha_tinh', 'dong_hoi'), ('dong_hoi', 'dong_ha'),
    ('dong_ha', 'hue'), ('hue', 'da_nang'), ('da_nang', 'tam_ky'), ('tam_ky', 'quang_ngai'),
    ('quang_ngai', 'quy_nhon'), ('quy_nhon', 'tuy_hoa'), ('tuy_hoa', 'nha_trang'), ('nha_trang', 'phan_rang'),
    ('phan_rang', 'phan_thiet'), ('phan_thiet', 'bien_hoa'), ('bien_hoa', 'tp_hcm'),
    ('quy_nhon', 'pleiku'), ('quang_ngai', 'pleiku'), ('pleiku', 'buon_ma_thuot'),
    ('buon_ma_thuot', 'nha_trang'), ('buon_ma_thuot', 'tp_hcm'), ('buon_ma_thuot', 'da_lat'),
    ('da_lat', 'phan_rang'), ('da_lat', 'nha_trang'), ('da_lat', 'bien_hoa'),
    ('tp_hcm', 'vung_tau'), ('bien_hoa', 'vung_tau'), ('tp_hcm', 'tay_ninh'), ('tp_hcm', 'my_tho'),
    ('my_tho', 'ben_tre'), ('my_tho', 'can_tho'), ('can_tho', 'long_xuyen'), ('long_xuyen', 'rach_gia'),
    ('can_tho', 'rach_gia'), ('can_tho', 'soc_trang'), ('soc_trang', 'bac_lieu'), ('bac_lieu', 'ca_mau'),
    ('can_tho', 'ca_mau'), ('rach_gia', 'ca_mau'),
    # Tây Bắc, Việt Bắc (QL2, CT05, QL4D, QL12, QL6, QL279, QL3, QL4A)
    ('ha_noi', 'vinh_yen'), ('vinh_yen', 'viet_tri'), ('viet_tri', 'yen_bai'), ('yen_bai', 'lao_cai'),
    ('viet_tri', 'tuyen_quang'), ('tuyen_quang', 'ha_giang'), ('lao_cai', 'sa_pa'), ('sa_pa', 'lai_chau'),
    ('lai_chau', 'dien_bien'), ('ha_noi', 'hoa_binh'), ('hoa_binh', 'moc_chau'), ('moc_chau', 'son_la'),
    ('son_la', 'dien_bien'), ('thai_nguyen', 'bac_kan'), ('bac_kan', 'cao_bang'), ('lang_son', 'cao_bang'),
    # Đông Bắc, đồng bằng sông Hồng (QL1, QL5, QL39, QL18)
    ('bac_ninh', 'bac_giang'), ('bac_giang', 'lang_son'), ('ha_noi', 'hai_duong'), ('hai_duong', 'hai_phong'),
    ('ha_noi', 'hung_yen'), ('hung_yen', 'thai_binh'), ('ha_long', 'mong_cai'),
    # Miền Trung, Tây Nguyên (QL14, QL24, QL20)
    ('da_nang', 'hoi_an'), ('hoi_an', 'tam_ky'), ('pleiku', 'kon_tum'), ('quang_ngai', 'kon_tum'),
    ('buon_ma_thuot', 'gia_nghia'), ('gia_nghia', 'dong_xoai'), ('da_lat', 'bao_loc'), ('bao_loc', 'bien_hoa'),
    # Đông Nam Bộ, đồng bằng sông Cửu Long (QL13, CT TP.HCM – Trung Lương, QL30, QL1, QL53, QL60,
    # QL61C, QL61, QL91, QL80)
    ('tp_hcm', 'thu_dau_mot'), ('thu_dau_mot', 'dong_xoai'), ('tp_hcm', 'tan_an'), ('tan_an', 'my_tho'),
    ('my_tho', 'cao_lanh'), ('cao_lanh', 'long_xuyen'), ('my_tho', 'vinh_long'), ('vinh_long', 'can_tho'),
    ('vinh_long', 'tra_vinh'), ('ben_tre', 'tra_vinh'), ('can_tho', 'vi_thanh'), ('vi_thanh', 'rach_gia'),
    ('long_xuyen', 'chau_doc'), ('chau_doc', 'ha_tien'), ('rach_gia', 'ha_tien'),
]


def polygons(geometry):
    if geometry['type'] == 'Polygon':
        return [geometry['coordinates']]
    if geometry['type'] == 'MultiPolygon':
        return geometry['coordinates']
    return []


def lines(geometry):
    if geometry['type'] == 'LineString':
        return [geometry['coordinates']]
    if geometry['type'] == 'MultiLineString':
        return geometry['coordinates']
    return []


def simplify(points, tolerance):
    """Douglas–Peucker, không đệ quy."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        length2 = dx * dx + dy * dy
        best, best_d = -1, tolerance
        for i in range(a + 1, b):
            px, py = points[i]
            if length2 == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
                d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if d > best_d:
                best, best_d = i, d
        if best >= 0:
            keep[best] = True
            stack.append((a, best))
            stack.append((best, b))
    return [p for p, k in zip(points, keep) if k]
