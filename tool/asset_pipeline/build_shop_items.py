"""Ảnh minh hoạ cửa hàng ở trạm dừng nghỉ: nâng cấp xe (lốp tốt, bình xăng
phụ, đèn LED, còi hơi, đệm ghế hạt gỗ) và quà Tết cho cả nhà (mứt Tết, khăn
len, trà sen, rượu nếp, ấm trà, cờ tướng, bánh chưng, bánh quy, khăn lụa,
gấu bông, bút sáp màu, lì xì).

Mỗi món là một mô hình SDF dò tia bằng bộ vẽ của build_driver_props.py (cùng
vật liệu, phản chiếu bầu trời, bóng mềm, AO như người nhà ra cổng đón), máy
ảnh đặt gần và cao hơn vật nên nhìn chếch xuống thấy mặt trên. Ảnh vuông
[S]×[S], vật nằm giữa, đáy chạm mép dưới (có bóng hứng dưới chân).

Ghi assets/images/img_shop_<tên>.png. Chạy từ thư mục gốc (numpy + pillow):
    python tool/asset_pipeline/build_shop_items.py            # tất cả
    python tool/asset_pipeline/build_shop_items.py tra_sen    # chọn món
    python tool/asset_pipeline/build_shop_items.py --fast --sheet /tmp/sheet.png
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_driver_props as P  # noqa: E402
from build_vehicles_3d import (  # noqa: E402
    ALU, CHROME, DARK_METAL, RUBBER, SATIN_BLACK, Mat, Obj, capsule, ellipsoid, fbm, field_bump, length2, length3,
    lin, rbox, rot, round_cone, smax, smin, smoothstep, sphere, tyre, vnoise)

OUT = 'assets/images'
S = 160
GOLD = P.GOLD
cyl, cyl_x, cyl_y = P.cyl, P.cyl_x, P.cyl_y


def hash2(i, j, seed=0):
    n = np.sin(i * 127.1 + j * 311.7 + seed * 74.7) * 43758.5453
    return n - np.floor(n)


def torus_z(p, c, R, r):
    """Xuyến nằm ngang (trục z) tâm [c]."""
    x, y, z = p
    return length2(length2(x - c[0], y - c[1]) - R, z - c[2]) - r


def torus_y(p, c, R, r):
    """Xuyến đứng quay mặt về máy ảnh (trục y)."""
    x, y, z = p
    return length2(length2(x - c[0], z - c[2]) - R, y - c[1]) - r


def torus_x(p, c, R, r):
    x, y, z = p
    return length2(length2(y - c[1], z - c[2]) - R, x - c[0]) - r


def ribbon_bow(c, color, scale=1.0, yaw=0.0):
    """Nơ ruy băng: hai quai phồng và nút giữa (nhìn từ phía trước)."""
    cx, cy, cz = c
    k = scale

    def sdf(p):
        x, y, z = p
        u, v = rot(x - cx, y - cy, -yaw)
        q = (np.abs(u), v, z - cz)
        loop = ellipsoid(q, (0.026 * k, 0, 0.004 * k), (0.026 * k, 0.012 * k, 0.017 * k))
        tail = capsule(q, (0.004 * k, 0, -0.004 * k), (0.022 * k, -0.002 * k, -0.03 * k), 0.006 * k)
        knot = ellipsoid((u, v, z - cz), (0, 0, 0), (0.011 * k, 0.011 * k, 0.012 * k))
        return smin(smin(loop, knot, 0.006 * k), tail, 0.004 * k)
    return Obj('bow', sdf, Mat(color, rough=0.3, spec=0.8, coat=0.5, sheen=0.3))


# ============================================================ Nâng cấp xe
def lop_tot():
    """Lốp gai sâu đứng nghiêng, mâm hợp kim năm chấu sáng bóng."""
    R, thick, hw = 0.30, 0.10, 0.105
    c = (0.0, 0.0, R)

    def tread(x, y, z):
        th = np.arctan2(z - c[2], y - c[1])
        r = length2(y - c[1], z - c[2])
        on = smoothstep(R - 0.03, R - 0.008, r)
        ax = np.abs(x)
        chevron = np.tanh(3.0 * np.sin(th * 34 + ax * 26)) * smoothstep(0.012, 0.02, ax)
        side = smoothstep(R - 0.035, R - 0.06, r) * 0.25 * np.sin(r * 400)
        return on * (0.6 * chevron - 0.9 * np.exp(-(ax / 0.008) ** 2)) + side

    tire = Obj('tire', lambda p: tyre(p, c, R, thick, hw, 0.035), Mat((34, 34, 37), rough=0.72, spec=0.4),
               bump=field_bump(tread, 0.0045))
    rim_r = R - thick + 0.008
    spokes = 5

    def rim(p):
        x, y, z = p
        dy, dz = y - c[1], z - c[2]
        r = length2(dy, dz)
        barrel = cyl_x(p, c, rim_r, 0.085)
        # khoét lỗ giữa các chấu ở mặt ngoài (phía -x)
        th = np.arctan2(dz, dy)
        a = np.mod(th + math.pi / spokes, 2 * math.pi / spokes) - math.pi / spokes
        u, v = r * np.cos(a), r * np.sin(a)
        half = 0.33 * u - 0.012
        win = np.maximum(np.maximum(0.075 - u, u - (rim_r - 0.022)), np.abs(v) - half)
        dish = smax(barrel, -np.maximum(win, x - 0.03), 0.006)
        # lõm mặt mâm vào trong một chút
        return smax(dish, -(cyl_x(p, (c[0] - 0.1, c[1], c[2]), rim_r - 0.018, 0.02)), 0.005)

    hub = Obj('hub', lambda p: cyl_x(p, (c[0] - 0.072, c[1], c[2]), 0.032, 0.012), CHROME)
    rotor = Obj('rotor', lambda p: cyl_x(p, (c[0] + 0.02, c[1], c[2]), 0.15, 0.008), DARK_METAL)
    caliper = Obj('caliper', lambda p: rbox(p, (c[0] + 0.0, c[1] - 0.09, c[2] + 0.09), (0.022, 0.035, 0.03), 0.01),
                  Mat((206, 34, 36), rough=0.3, spec=0.8, coat=0.6))
    nuts = Obj('nuts', lambda p: _nuts(p, c), CHROME)
    parts = [tire, Obj('rim', rim, Mat((214, 217, 222), rough=0.3, metal=0.45, coat=0.6, spec=0.9)), hub, rotor, caliper, nuts]
    return P.placed(parts, yaw=math.radians(58)), dict(dist=2.6, eye=1.2)


def _nuts(p, c):
    x, y, z = p
    d = None
    for i in range(5):
        a = i * 2 * math.pi / 5 + 0.3
        e = sphere(p, (c[0] - 0.078, c[1] + math.cos(a) * 0.05, c[2] + math.sin(a) * 0.05), 0.008)
        d = e if d is None else np.minimum(d, e)
    return d


def binh_xang():
    """Can xăng phụ sơn đỏ: gân chữ X dập nổi hai bên, ba quai trên nóc, nắp vàng."""
    hx, hy, hz = 0.17, 0.08, 0.22
    cz = hz

    def ribs(x, y, z):
        u, v = x / (hx - 0.04), (z - cz) / (hz - 0.05)
        inside = smoothstep(1.05, 0.95, np.maximum(np.abs(u), np.abs(v)))
        dx = np.minimum(np.abs(u - v), np.abs(u + v))
        x_rib = np.exp(-(dx / 0.12) ** 2)
        frame = np.exp(-((np.maximum(np.abs(u), np.abs(v)) - 0.98) / 0.05) ** 2)
        return (x_rib + frame) * inside * (np.abs(y) > hy - 0.02)

    paint = Mat((196, 28, 30), rough=0.28, metal=0.35, coat=0.75, spec=0.8)
    body = Obj('can', lambda p: rbox(p, (0, 0, cz), (hx, hy, hz), 0.03), paint, bump=field_bump(ribs, 0.012))

    def handles(p):
        x, y, z = p
        top = 2 * hz
        d = capsule(p, (-0.13, 0, top + 0.055), (0.07, 0, top + 0.055), 0.013)
        for px in (-0.11, -0.02, 0.06):
            d = np.minimum(d, capsule(p, (px, 0, top - 0.01), (px, 0, top + 0.05), 0.011))
        return d

    spout = Obj('spout', lambda p: smin(cyl(p, (0.12, 0), 0.034, 2 * hz - 0.02, 2 * hz + 0.03),
                                        cyl(p, (0.12, 0), 0.04, 2 * hz + 0.02, 2 * hz + 0.05), 0.004),
                Mat((236, 186, 40), rough=0.3, metal=0.5, coat=0.5))
    return P.placed([body, Obj('handles', handles, paint), spout], yaw=math.radians(-28)), dict(dist=2.4, eye=1.25)


def den_led():
    """Đèn pha LED tròn: vỏ đen, viền mạ crôm, ba bi cầu LED và vòng đèn
    định vị sáng trắng xanh."""
    R = 0.15
    cz = R + 0.045

    def housing(p):
        x, y, z = p
        shell = ellipsoid(p, (0, 0.05, cz), (R, 0.12, R))
        # cắt phẳng mặt trước (giữ phần y ≥ 0)
        return smax(shell, -y, 0.004)

    def bezel(p):
        return torus_y(p, (0, -0.002, cz), R - 0.012, 0.016)

    def face(p):
        return cyl_y(p, (0, 0.012, cz), R - 0.02, 0.008)

    spots = ((-0.05, 0.028), (0.05, 0.028), (0.0, -0.05))

    def cups(p):
        # chén phản quang crôm quanh mỗi bi cầu
        d = None
        for (dx, dz) in spots:
            e = smax(cyl_y(p, (dx, 0.004, cz + dz), 0.042, 0.008), -ellipsoid(p, (dx, -0.006, cz + dz), (0.036, 0.016, 0.036)), 0.003)
            d = e if d is None else np.minimum(d, e)
        return d

    def lenses(p):
        d = None
        for (dx, dz) in spots:
            e = ellipsoid(p, (dx, 0.004, cz + dz), (0.026, 0.016, 0.026))
            d = e if d is None else np.minimum(d, e)
        return d

    def eyes(p):
        # vòng "mắt thiên thần" sáng quanh từng bi cầu
        d = None
        for (dx, dz) in spots:
            e = torus_y(p, (dx, -0.005, cz + dz), 0.035, 0.0052)
            d = e if d is None else np.minimum(d, e)
        return d

    def drl(p):
        return torus_y(p, (0, -0.007, cz), R - 0.034, 0.0075)

    def bracket(p):
        x, y, z = p
        q = (np.abs(x) - R + 0.01, y - 0.06, z)
        ear = rbox(q, (0, 0, cz), (0.012, 0.025, 0.03), 0.008)
        stand = rbox(p, (0, 0.07, 0.025), (0.09, 0.05, 0.025), 0.012)
        post = rbox(p, (0, 0.08, 0.06), (0.025, 0.02, 0.05), 0.01)
        return np.minimum(np.minimum(ear, stand), post)

    led = Mat((206, 230, 255), rough=0.05, spec=1.2, coat=1.0, emit=4.5)
    lens_mat = Mat((176, 200, 236), rough=0.02, spec=1.4, coat=1.0, emit=0.9)
    parts = [
        Obj('housing', housing, Mat((24, 25, 28), rough=0.35, spec=0.7, coat=0.4)),
        Obj('face', face, Mat((44, 46, 52), rough=0.25, metal=0.9)),
        Obj('cups', cups, Mat((210, 214, 222), rough=0.08, metal=1.0)),
        Obj('bezel', bezel, CHROME),
        Obj('lens', lenses, lens_mat),
        Obj('eyes', eyes, led, cast=False),
        Obj('drl', drl, led, cast=False),
        Obj('bracket', bracket, SATIN_BLACK),
    ]
    return P.placed(parts, yaw=math.radians(24)), dict(dist=2.2, eye=0.9, glow=6)


def coi_hoi():
    """Còi hơi đôi mạ crôm: hai loa kèn dài ngắn trên giá đen, bình nén khí nhỏ."""
    chrome = Mat((236, 238, 242), rough=0.07, metal=1.0)
    # (y, z, x đầu, dài, bán kính cổ, bán kính loa)
    specs = ((0.0, 0.085, -0.17, 0.42, 0.013, 0.066), (0.1, 0.1, -0.13, 0.32, 0.012, 0.054))

    def horn(p, y0, z0, x0, length, r0, r1):
        x, y, z = p
        t = np.clip((x - x0) / length, 0, 1)
        r = r0 + (r1 - r0) * t ** 4
        dr = 4 * (r1 - r0) * t ** 3 / length
        radial = length2(y - y0, z - z0)
        tube = np.abs(radial - r) / np.sqrt(1 + dr * dr) - 0.0035
        tube = np.maximum(tube, np.maximum(x0 - x, x - x0 - length))
        lip = torus_x(p, (x0 + length, y0, z0), r1, 0.0055)
        cap = capsule(p, (x0 - 0.01, y0, z0), (x0 + 0.02, y0, z0), r0 + 0.006)
        return np.minimum(np.minimum(tube, lip), cap)

    def horns(p):
        return np.minimum(horn(p, *specs[0]), horn(p, *specs[1]))

    def base(p):
        x, y, z = p
        bar = rbox(p, (-0.07, 0.05, 0.03), (0.02, 0.085, 0.012), 0.005)
        clamps = np.minimum(torus_x(p, (-0.07, specs[0][0], specs[0][1]), specs[0][4] + 0.006, 0.005),
                            torus_x(p, (-0.07, specs[1][0], specs[1][1]), specs[1][4] + 0.006, 0.005))
        legs = rbox(p, (-0.07, 0.05, 0.012), (0.035, 0.1, 0.012), 0.006)
        return np.minimum(np.minimum(bar, clamps), legs)

    def valve(p):
        # van điện gắn đuôi hai loa, dây hơi đỏ nối vào
        body = rbox(p, (-0.2, 0.05, 0.09), (0.028, 0.075, 0.025), 0.012)
        hose = capsule(p, (-0.225, 0.05, 0.08), (-0.27, -0.02, 0.012), 0.008)
        return smin(body, hose, 0.006)

    parts = [Obj('horns', horns, chrome), Obj('base', base, SATIN_BLACK),
             Obj('valve', valve, Mat((200, 30, 32), rough=0.3, spec=0.8, coat=0.6))]
    return P.placed(parts, yaw=math.radians(-36)), dict(dist=1.8, eye=0.9)


def dem_ghe():
    """Đệm ghế hạt gỗ (kiểu tài xế xe khách hay lót): lưng tựa và mặt ngồi
    kết bằng hạt gỗ sáng tối xen kẽ, viền vải nâu."""
    s = 0.034

    def panel(u, v, w, hu, hv):
        """Hạt gỗ trên một tấm (u, v trong mặt tấm, w pháp tuyến)."""
        iu, iv = np.floor(u / s), np.floor(v / s)
        qu, qv = u - (iu + 0.5) * s, v - (iv + 0.5) * s
        bead = ellipsoid((qu, qv, w), (0, 0, 0), (0.0155, 0.0155, 0.013))
        rect = np.maximum(np.abs(u) - hu, np.abs(v) - hv)
        return np.maximum(bead, rect), iu, iv

    tilt = math.radians(14)

    def seat_uv(p):
        x, y, z = p
        return x, y + 0.02, z - 0.07

    def back_uv(p):
        x, y, z = p
        # lưng tựa dựng gần đứng phía sau, ngả ra sau [tilt]
        yy, zz = y - 0.17, z - 0.33
        v = zz * math.cos(tilt) + yy * math.sin(tilt)
        w = yy * math.cos(tilt) - zz * math.sin(tilt)
        return x, v, w

    def beads(p):
        u, v, w = seat_uv(p)
        a, _, _ = panel(u, v, w, 0.2, 0.17)
        u2, v2, w2 = back_uv(p)
        b, _, _ = panel(u2, v2, w2, 0.2, 0.24)
        return np.minimum(a, b)

    def tint(p, n, alb, idx):
        u, v, w = seat_uv(p)
        u2, v2, w2 = back_uv(p)
        on_back = np.abs(w2) < np.abs(w)
        uu, vv = np.where(on_back, u2, u), np.where(on_back, v2, v)
        iu, iv = np.floor(uu / s), np.floor(vv / s)
        # hoa văn quả trám: hạt sẫm theo đường chéo
        dark = (np.mod(np.abs(iu) + np.abs(iv), 4) == 0) | (np.mod(np.abs(iu) - np.abs(iv), 4) == 0)
        h = hash2(iu, iv + on_back * 50, 3)
        light = lin((214, 172, 112)) * (0.85 + 0.3 * h[:, None])
        darkc = lin((120, 72, 40)) * (0.85 + 0.3 * h[:, None])
        return np.where(dark[:, None], darkc, light)

    def trim(p):
        u, v, w = seat_uv(p)
        e1 = np.maximum(np.abs(np.maximum(np.abs(u) - 0.2, np.abs(v) - 0.17)) - 0.006, np.abs(w) - 0.012)
        u2, v2, w2 = back_uv(p)
        e2 = np.maximum(np.abs(np.maximum(np.abs(u2) - 0.2, np.abs(v2) - 0.24)) - 0.006, np.abs(w2) - 0.012)
        return np.minimum(e1, e2)

    def frame(p):
        # ghế ngồi giả (khung tối mờ) để đệm có chỗ tựa
        x, y, z = p
        seat = rbox(p, (0, -0.02, 0.035), (0.215, 0.19, 0.035), 0.02)
        u2, v2, w2 = back_uv(p)
        back = rbox((u2, v2, w2 - 0.03), (0, 0, 0), (0.215, 0.255, 0.025), 0.02)
        return np.minimum(seat, back)

    parts = [Obj('beads', beads, Mat((200, 160, 100), rough=0.35, spec=0.7, coat=0.5), tint=tint),
             Obj('trim', trim, Mat((92, 52, 30), rough=0.8, sheen=0.4)),
             Obj('seat', frame, Mat((52, 54, 60), rough=0.85, sheen=0.3))]
    return P.placed(parts, yaw=math.radians(-30)), dict(dist=2.6, eye=1.4)


# ============================================================ Quà Tết
def mut_tet():
    """Khay mứt Tết sơn mài đỏ mở nắp: sáu ngăn quanh một ngăn giữa, mứt gừng,
    mứt dừa xanh hồng, hạt sen, ô mai; nắp dựng phía sau."""
    R, H = 0.17, 0.06
    lacquer = Mat((176, 20, 26), rough=0.12, spec=0.9, coat=0.95)

    def box(p):
        x, y, z = p
        outer = cyl(p, (0, 0), R, 0, H)
        inner = cyl(p, (0, 0), R - 0.012, 0.012, H + 0.01)
        return smax(outer, -inner, 0.004)

    def box_tint(p, n, alb, idx):
        x, y, z = p
        r = length2(x, y)
        band = (np.abs(z - H * 0.55) < 0.006) & (r > R - 0.004)
        rim = (z > H - 0.004)
        return np.where((band | rim)[:, None], lin(GOLD), alb)

    def walls(p):
        x, y, z = p
        r = length2(x, y)
        th = np.arctan2(y, x)
        a = np.mod(th, math.pi / 3) - math.pi / 6
        radial = np.maximum(np.abs(r * np.sin(a + math.pi / 6)) - 0.0025, np.maximum(0.055 - r, r - R + 0.01))
        ring = np.abs(r - 0.055) - 0.0025
        return np.maximum(np.minimum(radial, ring), np.maximum(z - H + 0.004, -z))

    sp = 0.026

    def candy(p):
        x, y, z = p
        ix, iy = np.floor(x / sp), np.floor(y / sp)
        jx = (hash2(ix, iy, 1) - 0.5) * 0.006
        jy = (hash2(ix, iy, 2) - 0.5) * 0.006
        jz = hash2(ix, iy, 3) * 0.008
        cx, cy = (ix + 0.5) * sp + jx, (iy + 0.5) * sp + jy
        r = length2(cx, cy)
        sector = np.floor(np.mod(np.arctan2(cy, cx), 2 * math.pi) / (math.pi / 3))
        center = r < 0.05
        # hạt sen tròn ở giữa, mứt gừng dẹt dài, mứt dừa sợi
        rx = np.where(center, 0.011, np.where(np.mod(sector, 2) == 0, 0.0115, 0.0125))
        ry = np.where(center, 0.011, np.where(np.mod(sector, 2) == 0, 0.0075, 0.0065))
        rz = np.where(center, 0.0095, 0.0065)
        ang = hash2(ix, iy, 4) * math.pi
        ca, sa = np.cos(ang), np.sin(ang)
        u, v = (x - cx) * ca + (y - cy) * sa, -(x - cx) * sa + (y - cy) * ca
        d = ellipsoid((u, v, z - (H - 0.012 + jz)), (0, 0, 0), (rx, ry, rz))
        return np.maximum(d, length2(x, y) - (R - 0.016))

    palette = [(232, 196, 92), (120, 186, 96), (236, 236, 222), (226, 110, 140), (238, 160, 60), (150, 40, 40)]

    def candy_tint(p, n, alb, idx):
        x, y, z = p
        r = length2(x, y)
        sector = np.floor(np.mod(np.arctan2(y, x), 2 * math.pi) / (math.pi / 3)).astype(int) % 6
        cols = np.array([lin(c) for c in palette])
        out = cols[sector]
        out = np.where((r < 0.052)[:, None], lin((240, 228, 196)), out)
        sugar = vnoise(x * 900, y * 900, 7)
        return out * (0.85 + 0.3 * sugar[:, None])

    lean = math.radians(24)
    lc = (0.0, 0.2 + R * math.sin(lean), R * math.cos(lean) + 0.012)

    def lid_uw(p):
        x, y, z = p
        yy, zz = y - lc[1], z - lc[2]
        # u: theo pháp tuyến nắp (quay về máy ảnh, ngửa lên), w: trong mặt nắp
        u = -yy * math.cos(lean) + zz * math.sin(lean)
        w = yy * math.sin(lean) + zz * math.cos(lean)
        return x, u, w

    def lid(p):
        x, u, w = lid_uw(p)
        return cyl((x, w, u), (0, 0), R, -0.012, 0.012)

    def lid_tint(p, n, alb, idx):
        x, u, w = lid_uw(p)
        r = length2(x, w)
        a = np.arctan2(w, x)
        gold = (np.abs(r - 0.145) < 0.005) | (np.abs(r - 0.058) < 0.004) | (r > R - 0.005)
        # chữ Phúc cách điệu giữa nắp, hoa mai quanh vành
        glyph = (r < 0.045) & (((np.abs(x) < 0.006) & (np.abs(w) < 0.03)) | ((np.abs(w - 0.014) < 0.005) & (np.abs(x) < 0.026)) |
                               ((np.abs(w + 0.014) < 0.005) & (np.abs(x) < 0.022)))
        blossom = (r > 0.08) & (r < 0.13) & (length2(np.mod(a, math.pi / 4) - math.pi / 8, (r - 0.105) * 8) < 0.11)
        return np.where((gold | glyph | blossom)[:, None], lin(GOLD), alb)

    parts = [Obj('box', box, lacquer, tint=box_tint), Obj('walls', walls, Mat(GOLD, rough=0.3, metal=0.8)),
             Obj('candy', candy, Mat((220, 200, 120), rough=0.55, spec=0.5, coat=0.2), tint=candy_tint),
             Obj('lid', lid, lacquer, tint=lid_tint)]
    return parts, dict(dist=2.4, eye=1.3)


def khan_len():
    """Khăn len đỏ đô gấp ba lớp, mép kẻ sọc kem, tua rua thả trước."""
    wool = Mat((150, 28, 40), rough=0.9, sheen=0.7, wrap=0.3, spec=0.3)

    def knit(x, y, z):
        return np.abs(np.sin(x * 260 + 4 * np.abs(np.sin(y * 130 + z * 130)))) + 0.4 * np.sin(z * 300 + y * 300)

    def layers(p):
        x, y, z = p
        d = None
        for i, (dx, w) in enumerate([(0.0, 0.0), (0.012, 0.02), (-0.006, 0.04)]):
            e = rbox(p, (dx, 0.0, 0.019 + i * 0.034), (0.15 - i * 0.004, 0.09, 0.019), 0.018)
            d = e if d is None else smin(d, e, 0.004)
        # đầu khăn vắt xuống phía trước
        drape = rbox(p, (-0.03, -0.098, 0.05), (0.075, 0.015, 0.05), 0.014)
        return smin(d, drape, 0.012)

    def tint(p, n, alb, idx):
        x, y, z = p
        stripe = (np.abs(np.abs(x - 0.0) - 0.11) < 0.008) | (np.abs(np.abs(x) - 0.125) < 0.004)
        drape_stripe = (y < -0.08) & (np.abs(z - 0.03) < 0.007)
        return np.where((stripe | drape_stripe)[:, None], lin((238, 226, 200)), alb)

    def fringe(p):
        x, y, z = p
        d = None
        for i in range(9):
            fx = -0.098 + i * 0.017
            e = capsule(p, (fx, -0.116, 0.008), (fx + 0.002, -0.13, -0.0), 0.004)
            d = e if d is None else np.minimum(d, e)
        return d

    parts = [Obj('scarf', layers, wool, tint=tint, bump=field_bump(knit, 0.0026)),
             Obj('fringe', fringe, wool)]
    return P.placed(parts, yaw=math.radians(-18)), dict(dist=2.0, eye=1.2)


def tra_sen():
    """Hộp trà sen sơn mài đen viền vàng, bông sen hồng nở trên nắp, lá sen xanh."""
    lacquer = Mat((46, 16, 18), rough=0.1, spec=0.9, coat=0.95)
    hx, hy, hz = 0.13, 0.085, 0.045

    def box(p):
        return rbox(p, (0, 0, hz), (hx, hy, hz), 0.01)

    def box_tint(p, n, alb, idx):
        x, y, z = p
        edge = (np.abs(np.abs(x) - hx + 0.012) < 0.004) | (np.abs(np.abs(y) - hy + 0.012) < 0.004)
        edge &= n[2] > 0.6
        side = (np.abs(z - hz) < 0.004) & (np.abs(n[2]) < 0.5)
        return np.where((edge | side)[:, None], lin(GOLD), alb)

    lc = (0.035, 0.0, 2 * hz)

    def leaf(p):
        x, y, z = p
        u, v = x - lc[0] + 0.02, y - lc[1]
        return ellipsoid((u, v, z - lc[2] - 0.004), (0, 0, 0), (0.09, 0.07, 0.006))

    def leaf_tint(p, n, alb, idx):
        x, y, z = p
        a = np.arctan2(y - lc[1], x - lc[0] + 0.02)
        vein = np.abs(np.sin(a * 6)) > 0.94
        return np.where(vein[:, None], alb * 1.5, alb)

    def petals(p):
        x, y, z = p
        px, py, pz = x - lc[0], y - lc[1], z - lc[2] - 0.01
        d = None
        for ring, (n_, tilt, ln, wd, lift) in enumerate([(8, 1.05, 0.05, 0.02, 0.0), (6, 0.55, 0.045, 0.018, 0.008), (4, 0.25, 0.038, 0.015, 0.014)]):
            for i in range(n_):
                a = i * 2 * math.pi / n_ + ring * 0.4
                # vào toạ độ cánh: quay quanh z, nghiêng ra ngoài
                u, v = rot(px, py, -a)
                cu, sw = math.cos(tilt), math.sin(tilt)
                uu = u * cu + (pz - lift) * sw
                ww = -u * sw + (pz - lift) * cu
                e = ellipsoid((uu - 0.0, v, ww - ln * 0.9), (0, 0, 0), (0.008, wd, ln))
                d = e if d is None else smin(d, e, 0.002)
        return d

    def petal_tint(p, n, alb, idx):
        x, y, z = p
        h = z - lc[2]
        t = np.clip(h / 0.07, 0, 1)
        base = lin((246, 222, 230)) * (1 - t[:, None]) + lin((224, 90, 140)) * t[:, None]
        return base

    def pod(p):
        return cyl(p, (lc[0], lc[1]), 0.014, lc[2] + 0.02, lc[2] + 0.034)

    parts = [Obj('box', box, lacquer, tint=box_tint),
             Obj('leaf', leaf, Mat((62, 128, 58), rough=0.4, spec=0.6, coat=0.3), tint=leaf_tint),
             Obj('petals', petals, Mat((240, 150, 180), rough=0.45, wrap=0.4, sheen=0.3), tint=petal_tint),
             Obj('pod', pod, Mat((226, 196, 70), rough=0.5))]
    return P.placed(parts, yaw=math.radians(-20)), dict(dist=1.9, eye=1.15)


def ruou_nep():
    """Chai rượu nếp thuỷ tinh, nút lá chuối buộc lạt đỏ, nhãn giấy đỏ viền vàng."""
    def shell(p):
        body = round_cone(p, (0, 0, 0.012), (0, 0, 0.19), 0.062, 0.062)
        shoulder = round_cone(p, (0, 0, 0.19), (0, 0, 0.27), 0.062, 0.019)
        neck = round_cone(p, (0, 0, 0.27), (0, 0, 0.33), 0.019, 0.02)
        return smin(smin(body, shoulder, 0.02), neck, 0.01)

    def liquid(p):
        x, y, z = p
        inner = round_cone(p, (0, 0, 0.018), (0, 0, 0.19), 0.056, 0.056)
        return np.maximum(inner, z - 0.235)

    def label(p):
        x, y, z = p
        band = cyl(p, (0, 0), 0.0635, 0.075, 0.155)
        return smax(band, -cyl(p, (0, 0), 0.0605, 0.06, 0.17), 0.001)

    def label_tint(p, n, alb, idx):
        x, y, z = p
        a = np.arctan2(y, x)
        edge = (np.abs(z - 0.08) < 0.004) | (np.abs(z - 0.15) < 0.004)
        seal = (length2(np.sin(a + 1.5708) * 0.0635, z - 0.115) < 0.022) & (np.abs(np.sin(a + 1.5708)) < 0.5)
        ring = seal & (length2(np.sin(a + 1.5708) * 0.0635, z - 0.115) > 0.016)
        return np.where((edge | ring)[:, None], lin(GOLD), alb)

    def stopper(p):
        x, y, z = p
        plug = round_cone(p, (0, 0, 0.31), (0, 0, 0.36), 0.022, 0.026)
        tuft = ellipsoid(p, (0.0, 0.0, 0.372), (0.034, 0.03, 0.022))
        return smin(plug, tuft, 0.01)

    def string(p):
        return torus_z(p, (0, 0, 0.325), 0.022, 0.0035)

    glass = [Obj('glass', shell, Mat((200, 220, 210), rough=0.05))]
    parts = [Obj('wine', liquid, Mat((214, 168, 86), rough=0.05, spec=1.0, coat=0.9, wrap=0.5)),
             Obj('label', label, Mat((196, 24, 30), rough=0.5, spec=0.5), tint=label_tint),
             Obj('stopper', stopper, Mat((96, 140, 60), rough=0.6, sheen=0.3),
                 bump=field_bump(lambda x, y, z: np.sin(np.arctan2(y, x) * 14 + z * 80), 0.002)),
             Obj('string', string, Mat((206, 30, 34), rough=0.5))]
    return parts, dict(dist=1.8, eye=0.95, glass=glass)


def am_tra():
    """Ấm trà gốm Bát Tràng men trắng vẽ lam, kèm một chén."""
    glaze = Mat((240, 241, 236), rough=0.1, spec=0.9, coat=0.9)

    def pot(p):
        x, y, z = p
        body = ellipsoid(p, (0, 0, 0.085), (0.105, 0.105, 0.08))
        foot = cyl(p, (0, 0), 0.06, 0.0, 0.02)
        lid = cyl(p, (0, 0), 0.052, 0.15, 0.168)
        knob = sphere(p, (0, 0, 0.18), 0.017)
        spout = round_cone(p, (0.085, 0, 0.075), (0.18, 0, 0.16), 0.024, 0.01)
        q = (x + 0.115, y, z - 0.095)
        handle = np.maximum(length2(length2(q[0], q[2]) - 0.048, q[1]) - 0.011, x + 0.095)
        d = smin(body, foot, 0.012)
        d = smin(d, lid, 0.006)
        d = smin(d, knob, 0.008)
        d = smin(d, spout, 0.012)
        return smin(d, handle, 0.008)

    def cup(p):
        x, y, z = p
        c = (0.13, -0.11)
        outer = round_cone(p, (c[0], c[1], 0.012), (c[0], c[1], 0.05), 0.03, 0.042)
        inner = round_cone(p, (c[0], c[1], 0.02), (c[0], c[1], 0.06), 0.024, 0.036)
        return smax(outer, -inner, 0.003)

    def tint(p, n, alb, idx):
        x, y, z = p
        blue = lin((32, 64, 150))
        a = np.arctan2(y, x)
        band = (np.abs(z - 0.035) < 0.004) | (np.abs(z - 0.142) < 0.004)
        flowers = (fbm(a * 3.0 + 3, z * 40, seed=3, octaves=3) > 0.58) & (z > 0.055) & (z < 0.125)
        stems = (np.abs(np.sin(a * 5 + z * 60)) < 0.07) & (z > 0.05) & (z < 0.13)
        cup_rim = (length2(x - 0.13, y + 0.11) < 0.06) & (np.abs(z - 0.042) < 0.004)
        pat = band | flowers | stems | cup_rim
        return np.where(pat[:, None], blue, alb)

    parts = [Obj('pot', pot, glaze, tint=tint), Obj('cup', cup, glaze, tint=tint)]
    return P.placed(parts, yaw=math.radians(-12)), dict(dist=1.9, eye=1.05)


def co_tuong():
    """Bàn cờ tướng gỗ gấp đôi, vài quân cờ tròn khắc chữ đỏ / đen."""
    wood = Mat((206, 150, 92), rough=0.45, spec=0.6, coat=0.4)
    hx, hy, hz = 0.17, 0.12, 0.016

    def board(p):
        return rbox(p, (0, 0, hz), (hx, hy, hz), 0.006)

    def board_tint(p, n, alb, idx):
        x, y, z = p
        grain = 0.85 + 0.25 * np.sin(x * 160 + 6 * fbm(x * 20, y * 60, seed=2, octaves=3))
        out = alb * grain[:, None]
        top = n[2] > 0.6
        gx = np.abs(np.mod(x + 0.15, 0.0375) - 0.01875) > 0.0168
        gy = np.abs(np.mod(y + 0.105, 0.035) - 0.0175) > 0.0158
        inside = (np.abs(x) < 0.152) & (np.abs(y) < 0.107)
        river = np.abs(y) < 0.016
        line = top & inside & (gx | (gy & ~river))
        hinge = np.abs(x) < 0.003
        return np.where((line | (hinge & top))[:, None], lin((70, 40, 22)), out)

    pieces = [((-0.075, -0.035), 0, True), ((0.0375, 0.035), 0, False), ((0.11, -0.07), 0, True),
              ((-0.03, -0.075), 0, False), ((0.2, -0.1), 0, True), ((0.2, -0.1), 1, False)]

    def men(p):
        d = None
        for (cx, cy), lvl, red in pieces:
            z0 = 2 * hz if abs(cx) < hx else 0.0
            e = cyl(p, (cx, cy), 0.026, z0 + lvl * 0.017, z0 + lvl * 0.017 + 0.016)
            e = e - 0.002
            d = e if d is None else np.minimum(d, e)
        return d

    def men_tint(p, n, alb, idx):
        x, y, z = p
        out = alb.copy()
        for (cx, cy), lvl, red in pieces:
            r = length2(x - cx, y - cy)
            mine = r < 0.03
            ring = mine & (np.abs(r - 0.019) < 0.0022) & (n[2] > 0.6)
            u, v = x - cx, y - cy
            glyph = mine & (n[2] > 0.6) & (((np.abs(u) < 0.0022) & (np.abs(v) < 0.011)) | ((np.abs(v) < 0.0022) & (np.abs(u) < 0.01)) |
                                         ((np.abs(v - 0.007) < 0.0018) & (np.abs(u) < 0.007)))
            col = lin((190, 30, 30)) if red else lin((30, 28, 26))
            out = np.where((ring | glyph)[:, None], col, out)
        return out

    parts = [Obj('board', board, wood, tint=board_tint),
             Obj('men', men, Mat((232, 200, 146), rough=0.35, spec=0.7, coat=0.5), tint=men_tint)]
    return P.placed(parts, yaw=math.radians(-16)), dict(dist=2.0, eye=1.25)


def banh_chung():
    """Cặp bánh chưng gói lá dong xanh, buộc lạt giang, xếp chồng lệch nhau."""
    leaf = Mat((58, 118, 52), rough=0.42, spec=0.6, coat=0.3)
    h = 0.115

    def cake(p, cz, yaw):
        x, y, z = p
        u, v = rot(x, y, -yaw)
        return rbox((u, v, z), (0, 0, cz), (h, h, 0.04), 0.014), u, v

    def cakes(p):
        a, _, _ = cake(p, 0.04, 0.0)
        b, _, _ = cake(p, 0.122, math.radians(14))
        return np.minimum(a, b)

    def veins(x, y, z):
        return np.sin((x + y) * 160 + 2 * np.sin(x * 30)) * 0.6 + 0.4 * np.sin((x - y) * 40)

    def leaf_tint(p, n, alb, idx):
        x, y, z = p
        k = 0.85 + 0.3 * fbm(x * 30, y * 30 + z * 30, seed=5, octaves=3)
        fold = np.abs(np.sin((x - y) * 26)) > 0.96
        return np.where(fold[:, None], alb * 0.7, alb * k[:, None])

    def strings(p):
        x, y, z = p
        d = None
        for cz, yaw in ((0.04, 0.0), (0.122, math.radians(14))):
            u, v = rot(x, y, -yaw)
            shell = np.abs(rbox((u, v, z), (0, 0, cz), (h + 0.0025, h + 0.0025, 0.0425), 0.016)) - 0.0018
            for off in (-0.045, 0.045):
                e1 = np.maximum(shell, np.abs(u - off) - 0.006)
                e2 = np.maximum(shell, np.abs(v - off) - 0.006)
                e = np.minimum(e1, e2)
                d = e if d is None else np.minimum(d, e)
        return d

    def label(p):
        x, y, z = p
        u, v = rot(x, y, -math.radians(14))
        return rbox((u, v, z), (0, 0, 0.162), (0.035, 0.035, 0.002), 0.001)

    def label_tint(p, n, alb, idx):
        x, y, z = p
        u, v = rot(x, y, -math.radians(14))
        r = length2(u, v)
        g = (np.abs(r - 0.022) < 0.003) | (np.maximum(np.abs(u), np.abs(v)) > 0.03)
        return np.where(g[:, None], lin(GOLD), alb)

    parts = [Obj('cakes', cakes, leaf, tint=leaf_tint, bump=field_bump(veins, 0.0012)),
             Obj('strings', strings, Mat((222, 200, 140), rough=0.6, sheen=0.3)),
             Obj('label', label, Mat((200, 30, 32), rough=0.5), tint=label_tint)]
    return P.placed(parts, yaw=math.radians(-22)), dict(dist=2.1, eye=1.3)


def hop_banh():
    """Hộp bánh quy thiếc tròn màu xanh dương, dải hoa văn vàng, nơ đỏ trên nắp."""
    tin = Mat((26, 66, 168), rough=0.18, metal=0.55, coat=0.85, spec=0.9)
    R = 0.14

    def body(p):
        x, y, z = p
        can = cyl(p, (0, 0), R - 0.004, 0.0, 0.08) - 0.003
        lid = cyl(p, (0, 0), R, 0.072, 0.1) - 0.004
        return smin(can, lid, 0.002)

    def tint(p, n, alb, idx):
        x, y, z = p
        r = length2(x, y)
        a = np.arctan2(y, x)
        top = n[2] > 0.6
        band = (~top) & (np.abs(z - 0.04) < 0.012)
        dots = band & (np.abs(np.sin(a * 24)) > 0.75) & (np.abs(z - 0.04) < 0.006)
        rim = (~top) & (np.abs(z - 0.086) < 0.003)
        ring = top & ((np.abs(r - 0.115) < 0.004) | (np.abs(r - 0.06) < 0.003))
        flakes = top & (r > 0.065) & (r < 0.11) & (np.abs(np.sin(a * 6)) < 0.08)
        cookie = top & (r < 0.055)
        out = np.where((band & ~dots)[:, None], lin((236, 196, 92)), alb)
        out = np.where((rim | ring)[:, None], lin(GOLD), out)
        out = np.where((dots | flakes)[:, None], lin((246, 246, 240)), out)
        cookie_col = lin((214, 164, 92)) * (0.85 + 0.3 * vnoise(x * 400, y * 400, 3))[:, None]
        return np.where(cookie[:, None], cookie_col, out)

    def ribbon(p):
        x, y, z = p
        u, v = rot(x, y, -0.5)
        shell = np.abs(cyl(p, (0, 0), R + 0.002, 0.0, 0.102) - 0.004) - 0.0015
        return np.maximum(shell, np.abs(v) - 0.012)

    parts = [Obj('tin', body, tin, tint=tint),
             Obj('ribbon', ribbon, Mat((200, 26, 34), rough=0.3, spec=0.8, coat=0.5, sheen=0.3)),
             ribbon_bow((0.03, 0.03, 0.112), (210, 30, 38), scale=1.4, yaw=-0.5)]
    return parts, dict(dist=2.0, eye=1.25)


def khan_lua():
    """Khăn lụa tơ tằm cuộn tròn, đầu khăn trải ra phía trước gợn sóng, dệt
    hoa văn vàng trên nền đỏ mận."""
    silk = Mat((150, 30, 76), rough=0.22, sheen=0.8, coat=0.25, spec=0.8, wrap=0.2)

    def cloth(p):
        x, y, z = p
        roll = cyl_x(p, (0, 0.05, 0.042), 0.04, 0.14) - 0.002
        wave = 0.004 * np.sin(x * 40) + 0.003 * np.sin(y * 55 + x * 10)
        tongue = rbox((x, y, z - wave), (0.0, -0.035, 0.006), (0.135, 0.085, 0.004), 0.003)
        return smin(roll, tongue, 0.012)

    def tint(p, n, alb, idx):
        x, y, z = p
        f = fbm(x * 55, (y + z) * 55, seed=8, octaves=3)
        flower = (f > 0.6)
        border = (np.abs(np.abs(x) - 0.12) < 0.006)
        stripe = (np.abs(y + 0.105) < 0.005) & (z < 0.02)
        return np.where((flower | border | stripe)[:, None], lin((232, 186, 90)), alb)

    def ends(p):
        x, y, z = p
        return cyl_x(p, (0, 0.05, 0.042), 0.03, 0.142) - 0.001

    parts = [Obj('silk', cloth, silk, tint=tint),
             Obj('ends', ends, Mat((120, 22, 60), rough=0.4, sheen=0.6))]
    return P.placed(parts, yaw=math.radians(-24)), dict(dist=1.7, eye=1.05)


def gau_bong():
    """Gấu bông nâu ngồi, mõm sáng màu, mắt nút đen, thắt nơ đỏ ở cổ."""
    fur = Mat((156, 100, 58), rough=0.9, sheen=0.75, wrap=0.35, spec=0.3)

    def bear(p):
        x, y, z = p
        body = ellipsoid(p, (0, 0, 0.1), (0.088, 0.075, 0.1))
        head = sphere(p, (0, -0.005, 0.235), 0.072)
        q = (np.abs(x), y, z)
        ear = sphere(q, (0.055, 0.0, 0.295), 0.026)
        arm = round_cone(q, (0.07, -0.005, 0.165), (0.098, -0.05, 0.085), 0.026, 0.024)
        leg = round_cone(q, (0.048, -0.02, 0.045), (0.06, -0.105, 0.032), 0.034, 0.03)
        d = smin(body, head, 0.03)
        d = smin(d, ear, 0.01)
        d = smin(d, arm, 0.014)
        return smin(d, leg, 0.016)

    def light(p):
        x, y, z = p
        q = (np.abs(x), y, z)
        muzzle = ellipsoid(p, (0, -0.064, 0.222), (0.036, 0.026, 0.027))
        belly = ellipsoid(p, (0, -0.058, 0.095), (0.05, 0.02, 0.06))
        pads = ellipsoid(q, (0.06, -0.134, 0.032), (0.022, 0.006, 0.024))
        inner_ear = ellipsoid(q, (0.055, -0.016, 0.296), (0.013, 0.006, 0.013))
        return np.minimum(np.minimum(muzzle, belly), np.minimum(pads, inner_ear))

    def black(p):
        x, y, z = p
        q = (np.abs(x), y, z)
        eyes = sphere(q, (0.027, -0.06, 0.255), 0.0095)
        nose = ellipsoid(p, (0, -0.09, 0.233), (0.014, 0.008, 0.01))
        return np.minimum(eyes, nose)

    def collar(p):
        return torus_z(p, (0, -0.004, 0.172), 0.062, 0.009)

    def fuzz(x, y, z):
        return fbm(x * 220, (y + z) * 220, seed=4, octaves=2) + 0.5 * fbm(x * 600 + z * 300, y * 600, seed=9, octaves=1)

    parts = [Obj('bear', bear, fur, bump=field_bump(fuzz, 0.0035)),
             Obj('light', light, Mat((222, 184, 136), rough=0.85, sheen=0.6, wrap=0.3), bump=field_bump(fuzz, 0.002)),
             Obj('black', black, Mat((16, 14, 14), rough=0.08, spec=1.0, coat=1.0)),
             Obj('collar', collar, Mat((206, 28, 36), rough=0.3, spec=0.8, coat=0.5, sheen=0.3)),
             ribbon_bow((0.0, -0.068, 0.172), (210, 30, 38), scale=1.1)]
    return P.placed(parts, yaw=math.radians(-14)), dict(dist=1.9, eye=1.0)


def but_mau():
    """Hộp bút sáp màu bìa vàng mở nắp, các cây sáp đủ màu cắm thò lên, hai
    cây nằm phía trước."""
    colors = [(214, 36, 40), (240, 120, 30), (246, 200, 40), (70, 170, 70), (40, 150, 200), (40, 70, 180), (120, 60, 170),
              (230, 110, 160), (120, 72, 40)]
    n = len(colors)
    gap = 0.021
    x0 = -gap * (n - 1) / 2

    def box(p):
        x, y, z = p
        outer = rbox(p, (0, 0, 0.055), (0.105, 0.03, 0.055), 0.004)
        inner = rbox(p, (0, 0, 0.075), (0.1, 0.025, 0.06), 0.003)
        front_lid = rbox(p, (0, -0.032, 0.03), (0.105, 0.003, 0.03), 0.002)
        return np.minimum(smax(outer, -inner, 0.002), front_lid)

    def box_tint(p, n_, alb, idx):
        x, y, z = p
        band = (np.abs(z - 0.03) < 0.012) & (y < -0.02)
        rainbow = band & (np.abs(np.sin(x * 140)) > 0.3)
        k = np.clip(((x + 0.105) / 0.21 * n).astype(int), 0, n - 1)
        cols = np.array([lin(c) for c in colors])[k]
        out = np.where(rainbow[:, None], cols, alb)
        stripe = (np.abs(z - 0.075) < 0.004) & (y < -0.02)
        return np.where(stripe[:, None], lin((30, 110, 60)), out)

    heights = [0.15, 0.135, 0.158, 0.142, 0.152, 0.13, 0.146, 0.138, 0.155]

    def crayons(p):
        x, y, z = p
        d = None
        for i in range(n):
            cx = x0 + i * gap
            top = heights[i]
            stick = cyl(p, (cx, 0.0), 0.0085, 0.01, top - 0.018)
            tip = round_cone(p, (cx, 0.0, top - 0.02), (cx, 0.0, top), 0.0085, 0.002)
            e = smin(stick, tip, 0.002)
            d = e if d is None else np.minimum(d, e)
        for k, (cx, cy, a) in enumerate([(-0.04, -0.085, 0.25), (0.05, -0.1, -0.35)]):
            u, v = rot(x - cx, y - cy, -a)
            e = smin(cyl_x((u, v, z), (0, 0, 0.0085), 0.0085, 0.05), round_cone((u, v, z), (0.048, 0, 0.0085), (0.068, 0, 0.0085), 0.0085, 0.002), 0.002)
            d = np.minimum(d, e)
        return d

    def crayon_tint(p, n_, alb, idx):
        x, y, z = p
        k = np.clip(np.round((x - x0) / gap).astype(int), 0, n - 1)
        cols = np.array([lin(c) for c in colors])
        out = cols[k]
        lying = y < -0.05
        out = np.where((lying & (x < 0))[:, None], lin(colors[0]), out)
        out = np.where((lying & (x >= 0))[:, None], lin(colors[4]), out)
        wrap = (~lying) & (z < 0.115) & (np.abs(np.mod(z, 0.03) - 0.015) < 0.002)
        return np.where(wrap[:, None], out * 0.55, out)

    parts = [Obj('box', box, Mat((246, 206, 60), rough=0.55, spec=0.4), tint=box_tint),
             Obj('crayons', crayons, Mat((200, 60, 60), rough=0.45, spec=0.6, coat=0.3), tint=crayon_tint)]
    return P.placed(parts, yaw=math.radians(-10)), dict(dist=1.7, eye=0.95)


def lixi_do():
    """Ba phong bao lì xì đỏ xoè quạt, in viền và chữ Phúc vàng kim."""
    w, h = 0.05, 0.085
    cards = [(-0.045, 0.02, math.radians(-16), math.radians(14)), (0.045, 0.02, math.radians(16), math.radians(-14)),
             (0.0, -0.01, 0.0, 0.0)]

    def local(p, cx, cy, yaw, roll):
        x, y, z = p
        u, v = rot(x - cx, y - cy, -yaw)
        # nghiêng sang bên (quanh trục y) quanh mép đáy
        zz = z - 0.0
        uu = u * math.cos(roll) + zz * math.sin(roll)
        ww = -u * math.sin(roll) + zz * math.cos(roll)
        return uu, v, ww

    def env_sdf(p):
        d = None
        for cx, cy, yaw, roll in cards:
            u, v, ww = local(p, cx, cy, yaw, roll)
            e = rbox((u, v, ww), (0, 0, h + 0.002), (w, 0.0025, h), 0.002)
            d = e if d is None else np.minimum(d, e)
        return d

    def tint(p, n, alb, idx):
        out = alb.copy()
        for cx, cy, yaw, roll in cards:
            u, v, ww = local(p, cx, cy, yaw, roll)
            mine = (np.abs(v) < 0.006) & (np.abs(u) < w + 0.003) & (ww > -0.002) & (ww < 2 * h + 0.006)
            zc = ww - h * 1.05
            r = length2(u, zc)
            border = (np.abs(np.abs(u) - w + 0.008) < 0.0025) | (np.abs(ww - 2 * h + 0.008) < 0.0025) | (np.abs(ww - 0.008) < 0.0025)
            disc = r < 0.026
            ring = np.abs(r - 0.032) < 0.002
            flap = np.abs(ww - (2 * h - 0.03) + 0.4 * np.abs(u)) < 0.002
            glyph = disc & (((np.abs(u) < 0.0035) & (np.abs(zc) < 0.017)) | ((np.abs(zc - 0.008) < 0.003) & (np.abs(u) < 0.014)) |
                            ((np.abs(zc + 0.008) < 0.003) & (np.abs(u) < 0.012)))
            gold = mine & (border | ring | flap | (disc & ~glyph))
            red_in_disc = mine & glyph
            out = np.where(gold[:, None], lin(GOLD), out)
            out = np.where(red_in_disc[:, None], lin((190, 20, 28)), out)
        return out

    parts = [Obj('lixi', env_sdf, Mat((200, 20, 30), rough=0.32, spec=0.8, coat=0.6), tint=tint)]
    return parts, dict(dist=1.6, eye=0.75)


ITEMS = {
    'lop_tot': lop_tot, 'binh_xang': binh_xang, 'den_led': den_led, 'coi_hoi': coi_hoi, 'dem_ghe': dem_ghe,
    'mut_tet': mut_tet, 'khan_len': khan_len, 'tra_sen': tra_sen, 'ruou_nep': ruou_nep, 'am_tra': am_tra,
    'co_tuong': co_tuong, 'banh_chung': banh_chung, 'hop_banh': hop_banh, 'khan_lua': khan_lua,
    'gau_bong': gau_bong, 'but_mau': but_mau, 'lixi_do': lixi_do,
}


def finish_glow(view, rgb, alpha, emit, glow):
    """Như P.finish nhưng quầng sáng của phần tự phát sáng (đèn LED) phủ cả
    lên mặt vật chứ không chỉ loang ra ngoài viền."""
    from PIL import ImageFilter
    import build_vehicles_3d as v3
    ss = view.ss
    w, h = view.w, view.h
    col = v3.tonemap(rgb)
    pre = col * alpha[..., None]
    pre = pre.reshape(h, ss, w, ss, 3).mean((1, 3))
    a = alpha.reshape(h, ss, w, ss).mean((1, 3))
    if glow:
        e = emit.reshape(h, ss, w, ss).mean((1, 3))
        ecol = pre * np.clip(e, 0, 1)[..., None]
        acc = np.zeros_like(ecol)
        for c in range(3):
            im = Image.fromarray(np.clip(ecol[..., c] * 255, 0, 255).astype(np.uint8))
            acc[..., c] = np.asarray(im.filter(ImageFilter.GaussianBlur(glow)), np.float64) / 255
        acc *= 1.2
        ga = np.clip(acc.max(2), 0, 1)
        # cộng kiểu màn hình: chỗ đã sáng không cháy trắng thêm
        pre = pre + acc * (1 - pre) * a[..., None] + acc * (1 - a)[..., None]
        a = a + ga * (1 - a)
    rgb8 = np.where(a[..., None] > 1e-4, pre / np.maximum(a[..., None], 1e-4), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(rgb8 * 255 + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return P.crop(Image.fromarray(out))


def render_item(name, fast=False):
    objs, opt = ITEMS[name]()
    glass = opt.get('glass', ())
    ss = 2 if fast else 4
    kw = dict(ss=ss, glass=glass, catch=0.42, glow=0, ao_scale=0.32, dist=opt['dist'], eye=opt['eye'],
              bounds=((-0.6, -0.6, 0.0), (0.6, 0.6, 0.8)), shadow_k=8.0)
    ppm = 400.0
    view = P.View(objs, ppm, **kw)
    k = (S - 10) / max(view.w, view.h)
    view = P.View(objs, ppm * k, **kw)
    rgb, alpha, emit = P.render(view)
    img = finish_glow(view, rgb, alpha, emit, opt.get('glow', 0))
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    w, h = img.size
    if max(w, h) > S - 4:
        f = (S - 4) / max(w, h)
        img = img.resize((max(1, int(w * f)), max(1, int(h * f))), Image.LANCZOS)
        w, h = img.size
    out.alpha_composite(img, ((S - w) // 2, S - h - max(2, (S - h) // 6)))
    return out


def main():
    args = [a for a in sys.argv[1:]]
    fast = '--fast' in args
    sheet = None
    if '--sheet' in args:
        sheet = args[args.index('--sheet') + 1]
        args.remove(sheet)
    names = [a for a in args if not a.startswith('--')] or list(ITEMS)
    imgs = []
    for name in names:
        img = render_item(name, fast=fast)
        if not fast:
            img.save(f'{OUT}/img_shop_{name}.png', optimize=True)
        imgs.append(img)
        print(name, flush=True)
    if sheet:
        cols = 6
        rows = (len(imgs) + cols - 1) // cols
        bg = Image.new('RGBA', (cols * S, rows * S), (241, 231, 210, 255))
        for i, im in enumerate(imgs):
            bg.alpha_composite(im, ((i % cols) * S, (i // cols) * S))
        bg.save(sheet)


if __name__ == '__main__':
    random.seed(1)
    main()
