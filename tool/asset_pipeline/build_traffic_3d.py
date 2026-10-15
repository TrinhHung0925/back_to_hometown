"""Dòng xe AI trên đường dựng 3D bằng cùng bộ dò tia với xe của người chơi
(build_vehicles_3d.py), để cả con đường chung một kiểu ảnh thật.

Ghi đè (giữ nguyên tên file và hướng mũi xe lên trên):
    img_scooter_ai_1..10.png          xe số kiểu Wave và xe tay ga kiểu Vision /
                                      Lead; có người ngồi sau, chở cành đào, cây
                                      quất, thùng hàng, bao gạo
    img_scooter_ai_raincoat_1..4.png  người lái trùm áo mưa cánh dơi
    img_scooter_parked_1..3.png       xe dựng chân chống trước quán
    img_scooter_police(_parked).png   xe CSGT trắng, thùng sau, cụm đèn
    img_sedan_<màu>.png               sedan (cùng mô hình xe của người chơi)
    img_mini_van.png                  xe đa dụng 7 chỗ (kiểu Innova / Xpander)
    img_pickup_<màu>.png              bán tải cabin kép, thùng chở cây Tết
    img_bus_1..3.png                  xe khách (cùng mô hình xe khách người chơi)
    img_container_1.png               xe tải thùng mui bạt
    img_container_2.png               xe tải thùng kín
    img_truck.png                     xe ben chở cát (khung đổi sang 62 × 184
                                      cho khớp hộp va chạm của xe tải)
Thêm mới:
    img_scooter_mechanic.png          thợ vá lưu động chạy tới (hộp đồ nghề, săm)
    img_scooter_fuel.png              người mang xăng tới (can xăng đỏ)
    img_shadow_<tên>.png              bóng đổ theo dáng từng xe chạy trên đường

build_vehicles.py, build_trip_events.py và build_roadside.py cũng ghi các file
trên (bản vẽ phẳng cũ) nên nếu chạy lại chúng thì chạy script này sau.

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_traffic_3d.py             # tất cả
    python tool/asset_pipeline/build_traffic_3d.py moto car    # chọn nhóm
    python tool/asset_pipeline/build_traffic_3d.py --out DIR --zoom 3
"""
import math
import os
import random
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_vehicles_3d as v3  # noqa: E402
from build_vehicles_3d import (  # noqa: E402
    ALU, AMBER_LENS, BLACK_PLASTIC, CHROME, CLEAR_LENS, DARK_METAL, RUBBER, SATIN_BLACK, SEAT_VINYL, SKIN,
    SMOKE_GLASS, TAIL_LENS, Blend, Curve, Mat, Obj, Scene, arc_shell, capsule, ellipsoid, fabric, fabric_bump,
    field_bump, fbm, length2, lin, mirror_x, paint, rbox, rot, round_cone, smax, smin, smoothstep, tyre, vnoise,
    _in_rrect)

OUT = 'assets/images'


# ================================================================ Chung
def save_ai(scene, out, name, sigma, layers=None, shadow=True):
    """Vẽ rồi ghi ảnh xe + ảnh bóng đổ img_shadow_<tên> (khung như bóng xe
    người chơi: 1,16 × rộng, 1,08 × dài; xe dựng bên quán, xe người giúp
    không cần — game tự đổ bóng theo chính hình xe)."""
    t0 = time.time()
    if layers is None:
        v3.zoomed(scene)
        rgb, alpha, _ = v3.render(scene)
    else:
        rgb, alpha = layers
    img = v3.finish(rgb, alpha, *scene.size)
    img.save(f'{out}/{name}.png', optimize=True)
    if shadow:
        sname = 'img_shadow_' + name[len('img_'):]
        v3.shadow_png(alpha, scene.size[0], scene.size[1], sigma * v3.ZOOM).save(f'{out}/{sname}.png', optimize=True)
    print(f'{name}: {time.time() - t0:.1f}s')
    return img


def shifted(objs, dx=0.0, dy=0.0, dz=0.0):
    """Dời cả nhóm bộ phận (nội thất dùng lại cho xe khác)."""
    def wrap(fn):
        if fn is None:
            return None
        return lambda p, *a: fn((p[0] - dx, p[1] - dy, p[2] - dz), *a)
    out = []
    for o in objs:
        n = Obj(o.name, wrap(o.sdf), o.mats, pick=wrap(o.pick), tint=wrap(o.tint), cast=o.cast, bump=wrap(o.bump))
        out.append(n)
    return out


def spheres(centers, radii):
    c = np.asarray(centers, np.float64)
    r = np.asarray(radii, np.float64)

    def sdf(p):
        x, y, z = p
        d = None
        for (cx, cy, cz), rr in zip(c, r):
            v = np.sqrt((x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2) - rr
            d = v if d is None else np.minimum(d, v)
        return d
    return sdf


def segments(segs):
    """Hợp các đoạn thon (a, b, r1, r2) — cành cây, dây buộc."""
    def sdf(p):
        d = None
        for a, b, r1, r2 in segs:
            v = round_cone(p, a, b, r1, r2) if abs(r1 - r2) > 1e-4 else capsule(p, a, b, r1)
            d = v if d is None else np.minimum(d, v)
        return d
    return sdf


# ================================================================ Xe máy
MOTO_BOUNDS_X = 0.44


def moto_scene(parts, ztop=2.05):
    return Scene(parts, ((-MOTO_BOUNDS_X, -0.33, 0.0), (MOTO_BOUNDS_X, 1.76, ztop)), v3.BIKE_PPM, v3.BIKE_ORIGIN,
                 v3.BIKE_SIZE, ao_scale=0.55)


class Pose:
    """Tư thế người ngồi trên xe (mét, hệ toạ độ xe; điểm bên phải, x > 0)."""

    def __init__(self, head, shoulder, elbow, wrist, palm, hip, knee, foot):
        self.head, self.shoulder, self.elbow, self.wrist = head, shoulder, elbow, wrist
        self.palm, self.hip, self.knee, self.foot = palm, hip, knee, foot


# Người lái xe số (đúng tư thế xe người chơi).
WAVE_RIDER = Pose(head=v3.HEAD, shoulder=v3.SHOULDER, elbow=v3.ELBOW, wrist=v3.WRIST, palm=(0.27, 0.338, 1.005),
                  hip=v3.HIP, knee=v3.KNEE, foot=(v3.KNEE[0] - 0.03, v3.KNEE[1] - 0.035, 0.37))
# Người ngồi sau xe số: hai tay vịn eo người lái, chân trên gác chân sau.
WAVE_PILLION = Pose(head=(0.0, 1.03, 1.50), shoulder=(0.15, 1.08, 1.27), elbow=(0.225, 0.99, 1.07),
                    wrist=(0.19, 0.885, 0.98), palm=(0.178, 0.855, 0.97), hip=(0.0, 1.18, 0.87),
                    knee=(0.19, 0.955, 0.765), foot=(0.205, 1.0, 0.41))
# Xe tay ga: hai gối khép, bàn chân đặt trên sàn phẳng.
GA_RIDER = Pose(head=(0.0, 0.665, 1.53), shoulder=(0.158, 0.725, 1.29), elbow=(0.252, 0.53, 1.11),
                wrist=(0.272, 0.375, 1.025), palm=(0.27, 0.338, 1.005), hip=(0.0, 0.86, 0.865),
                knee=(0.15, 0.55, 0.705), foot=(0.122, 0.47, 0.36))
GA_PILLION = Pose(head=(0.0, 1.07, 1.53), shoulder=(0.15, 1.115, 1.30), elbow=(0.225, 1.02, 1.09),
                  wrist=(0.19, 0.915, 1.0), palm=(0.178, 0.885, 0.99), hip=(0.0, 1.21, 0.90),
                  knee=(0.19, 0.985, 0.79), foot=(0.21, 1.03, 0.42))


def person_parts(pose, helmet, jacket, pants, skin=SKIN, gloves=None, hair=None, seed=7, helmet_yaw=0.0):
    """Người ngồi trên xe theo [pose]: mũ nửa đầu, áo (có mũ trùm sau gáy),
    tay, chân, giày; [gloves] găng tay chống nắng, [hair] tóc buộc đuôi gà
    thò ra sau mũ."""
    jk = fabric(jacket)
    pn = fabric(pants, rough=0.8, sheen=0.3)
    hx, hy, hz = pose.head
    sx, sy, sz = pose.shoulder
    ex, ey, ez = pose.elbow
    wx, wy, wz = pose.wrist
    kx, ky, kz = pose.knee
    fx, fy, fz = pose.foot
    px_, py_, pz_ = pose.hip
    parts = v3.helmet_parts(helmet, pose.head, yaw=helmet_yaw)

    def torso(p):
        x, y, z = p
        return round_cone((x / 1.55, y, z), (0, py_ + 0.035, pz_ + 0.03), (0, sy + 0.035, sz - 0.07), 0.118, 0.118)

    def shoulders(p):
        return capsule(p, (-sx, sy, sz), (sx, sy, sz), 0.068)

    def hood(p):
        return ellipsoid(p, (0, hy + 0.13, hz - 0.145), (0.10, 0.07, 0.05))

    def arms(p):
        q = (np.abs(p[0]), p[1], p[2])
        ua = round_cone(q, (sx + 0.01, sy, sz - 0.01), (ex, ey, ez), 0.060, 0.049)
        fa = round_cone(q, (ex, ey, ez), (wx, wy, wz), 0.048, 0.037)
        return smin(ua, fa, 0.02)

    def neck(p):
        return ellipsoid(p, (0, hy + 0.03, hz - 0.13), (0.065, 0.075, 0.09))

    def hips(p):
        return ellipsoid(p, (0, py_ + 0.045, pz_ - 0.02), (0.168, 0.125, 0.09))

    def legs(p):
        q = (np.abs(p[0]), p[1], p[2])
        th = round_cone(q, (0.092, py_, pz_ - 0.03), (kx, ky, kz), 0.077, 0.058)
        sh = round_cone(q, (kx, ky - 0.005, kz - 0.02), (fx, fy, fz), 0.055, 0.04)
        return smin(th, sh, 0.03)

    parts.append(Blend('person', [(torso, 0), (shoulders, 0), (hood, 0), (arms, 0), (neck, 2), (hips, 0), (legs, 1)],
                       [jk, pn, skin], 0.045, bump=fabric_bump(70, 0.0016, seed)))
    ax_, ay_, az_ = pose.palm
    parts.append(Obj('hands', mirror_x(lambda p: ellipsoid(p, (ax_, ay_, az_), (0.043, 0.052, 0.030))),
                     fabric(gloves, rough=0.7) if gloves else skin))
    parts.append(Obj('shoes', mirror_x(lambda p: ellipsoid(p, (fx - 0.005, fy + 0.005, fz - 0.025), (0.046, 0.11, 0.04))),
                     Mat((40, 38, 36), rough=0.6)))
    if hair:
        def tail(p):
            return round_cone(p, (0, hy + 0.135, hz - 0.07), (0, hy + 0.2, hz - 0.29), 0.035, 0.022)
        parts.append(Obj('hair', tail, Mat(hair, rough=0.45, sheen=0.6, spec=0.5)))
    return parts


# ------------------------------------------------------------ Xe tay ga
# Kiểu Honda Vision / Lead: bánh 14 in, trục cách trục 1,255 m, yếm trước
# cao ôm hai chân, sàn để chân phẳng, thân sau đầy đặn, yên dài hai bậc.
GA_AXLE = 1.255
GA_R = 0.262


def ga_parts(body, inner=None, kickstand=False):
    pt = paint(body)
    inn = Mat(inner, rough=0.45, spec=0.5) if inner else BLACK_PLASTIC
    parts = [Obj('tyre_f', lambda p: tyre(p, (0, 0, GA_R), GA_R, 0.07, 0.044, 0.025), RUBBER),
             Obj('tyre_r', lambda p: tyre(p, (0, GA_AXLE, GA_R), GA_R, 0.075, 0.05, 0.027), RUBBER)]

    def fender_f(p):
        x, y, z = p
        hw = 0.06 - 0.025 * np.clip(-y / 0.22, 0, 1)
        r = length2(y, z - GA_R)
        d = smax(np.abs(r - 0.305) - 0.008, np.abs(x) - hw, 0.012)
        d = smax(d, 0.47 - z, 0.03)
        return smax(d, y - 0.12, 0.02)
    parts.append(Obj('fender_f', fender_f, pt))

    def shield(p):
        x, y, z = p
        yb = y - 0.14 * (z - 0.6)
        main = ellipsoid((x, yb, z), (0, 0.27, 0.62), (0.168, 0.15, 0.335))
        nose = ellipsoid((x, yb, z), (0, 0.155, 0.63), (0.085, 0.10, 0.27))
        d = smin(main, nose, 0.07)
        d = smax(d, y - (0.385 + 0.8 * x * x + 0.05 * (z - 0.6)), 0.03)
        return smax(d, 0.36 - z, 0.03)

    def shield_pick(p, n):
        x, y, z = p
        back = y > 0.36 + 0.8 * x * x + 0.05 * (z - 0.6) - 0.01
        return np.where(back & (n[1] > 0.25), 1, 0).astype(np.int32)

    def shield_tint(p, n, alb, idx):
        # đường gân chữ V giữa mặt nạ trước
        x, y, z = p
        v = (np.abs(np.abs(x) - (0.035 + 0.45 * (y - 0.12))) < 0.006) & (y > 0.12) & (y < 0.30) & (idx == 0)
        return np.where(v[:, None], alb * 0.55, alb)
    parts.append(Obj('shield', shield, [pt, inn], pick=shield_pick, tint=shield_tint))

    def cover(p):
        a = ellipsoid(p, (0, 0.345, 0.985), (0.185, 0.095, 0.068))
        b = ellipsoid(p, (0, 0.255, 0.955), (0.112, 0.085, 0.07))
        return smin(a, b, 0.05)

    def cover_pick(p, n):
        x, y, z = p
        lens = (y < 0.215) & (n[1] < -0.4) & (z > 0.905) & (np.abs(x) < 0.09)
        gauge = ((x / 0.072) ** 2 + ((y - 0.36) / 0.042) ** 2 < 1) & (n[2] > 0.6)
        low = z < 0.93
        return np.where(lens, 1, np.where(gauge, 2, np.where(low, 3, 0))).astype(np.int32)
    parts.append(Obj('cover', cover, [pt, CLEAR_LENS, SMOKE_GLASS, BLACK_PLASTIC], pick=cover_pick))
    parts.append(Obj('blink_f', mirror_x(lambda p: ellipsoid(p, (0.14, 0.235, 0.86), (0.03, 0.04, 0.025))), AMBER_LENS))

    # tay nắm, tay phanh, gương: như xe số
    parts.append(Obj('grips', mirror_x(lambda p: capsule(p, (0.18, 0.33, 0.988), (0.312, 0.337, 0.993), 0.0195)),
                     [RUBBER, ALU], pick=lambda p, n: (np.abs(p[0]) > 0.31).astype(np.int32)))
    parts.append(Obj('levers', mirror_x(lambda p: capsule(p, (0.17, 0.30, 1.005), (0.30, 0.28, 1.0), 0.0065)), ALU))

    def mirrors(p):
        stalk = capsule(p, (0.15, 0.32, 1.0), (0.265, 0.20, 1.20), 0.0075)
        x, y, z = p
        xr, yr = rot(x - 0.30, y - 0.175, -0.35)
        return np.minimum(stalk, ellipsoid((xr, yr, z), (0, 0, 1.225), (0.068, 0.034, 0.042)))
    parts.append(Obj('mirrors', mirror_x(mirrors), [SATIN_BLACK, CHROME],
                     pick=lambda p, n: ((p[2] < 1.17) & (p[2] > 1.02)).astype(np.int32)))

    def floor(p):
        mat = rbox(p, (0, 0.59, 0.305), (0.148, 0.17, 0.028), 0.02)
        side = rbox(p, (0, 0.60, 0.265), (0.168, 0.19, 0.045), 0.03)
        return np.minimum(mat, side)
    parts.append(Obj('floor', floor, [RUBBER, pt], pick=lambda p, n: ((p[2] < 0.315) | (np.abs(p[0]) > 0.15)).astype(np.int32),
                     bump=lambda p, n: (n[0] + 0.3 * np.sin(p[0] * 220) * (p[2] > 0.315), n[1], n[2])))

    def rear(p):
        a = ellipsoid(p, (0, 1.15, 0.56), (0.176, 0.50, 0.21))
        b = ellipsoid(p, (0, 0.80, 0.47), (0.14, 0.12, 0.17))
        c = ellipsoid(p, (0, 1.50, 0.62), (0.115, 0.16, 0.13))
        return smin(smin(a, b, 0.08), c, 0.07)

    def rear_pick(p, n):
        # ốp nhựa sẫm dưới yên, dọc sườn thấp
        return ((p[2] < 0.47) & (p[1] > 0.9)).astype(np.int32)
    parts.append(Obj('rear_body', rear, [pt, inn], pick=rear_pick))

    def seat(p):
        x, y, z = p
        xs = x * (1 + 0.5 * ((y - 1.03) / 0.42) ** 2)
        zs = z - 0.035 * smoothstep(0.98, 1.12, y)
        return rbox((xs, y, zs), (0, 1.03, 0.765), (0.148, 0.40, 0.05), 0.046)
    parts.append(Obj('seat', seat, SEAT_VINYL,
                     tint=lambda p, n, alb, idx: np.where((np.abs(p[1] - 1.05) < 0.008)[:, None], alb * 0.4, alb)))

    def rail(p):
        side = mirror_x(lambda q: capsule(q, (0.128, 1.22, 0.80), (0.135, 1.50, 0.815), 0.013))(p)
        back = capsule(p, (-0.10, 1.565, 0.815), (0.10, 1.565, 0.815), 0.013)
        corner = mirror_x(lambda q: capsule(q, (0.135, 1.50, 0.815), (0.10, 1.565, 0.815), 0.013))(p)
        return np.minimum(np.minimum(side, back), corner)
    parts.append(Obj('rail', rail, ALU))
    parts.append(Obj('taillight', lambda p: ellipsoid(p, (0, 1.635, 0.64), (0.092, 0.042, 0.045)), TAIL_LENS))
    parts.append(Obj('blink_r', mirror_x(lambda p: ellipsoid(p, (0.088, 1.625, 0.615), (0.03, 0.026, 0.024))), AMBER_LENS))

    def fender_r(p):
        d = arc_shell(p, (0, GA_AXLE, GA_R), 0.30, 0.01, 0.055, 0.008)
        d = smax(d, 1.50 - p[1], 0.02)
        d = smax(d, 0.25 - p[2], 0.02)
        y2, z2 = rot(p[1] - 1.66, p[2] - 0.42, 0.3)
        return np.minimum(d, rbox((p[0], y2, z2), (0, 0, 0), (0.088, 0.005, 0.058), 0.004))
    parts.append(Obj('fender_r', fender_r, [BLACK_PLASTIC, Mat((225, 225, 220), rough=0.4)],
                     pick=lambda p, n: (p[1] > 1.64).astype(np.int32)))

    def muffler(p):
        pipe = round_cone(p, (0.08, 0.80, 0.22), (0.15, 1.0, 0.28), 0.022, 0.03)
        muff = round_cone(p, (0.15, 0.98, 0.29), (0.18, 1.45, 0.35), 0.055, 0.045)
        return smin(pipe, muff, 0.03)
    parts.append(Obj('muffler', muffler, [SATIN_BLACK, CHROME],
                     pick=lambda p, n: (((p[1] > 1.05) & (p[1] < 1.3) & (n[0] > -0.2)) | (p[1] > 1.45)).astype(np.int32)))
    parts.append(Obj('cvt', lambda p: ellipsoid(p, (-0.13, 1.06, 0.30), (0.062, 0.32, 0.11)), [DARK_METAL, ALU],
                     pick=lambda p, n: (p[2] > 0.36).astype(np.int32)))
    if kickstand:
        parts.append(Obj('stand', lambda p: capsule(p, (-0.10, 0.86, 0.22), (-0.27, 0.92, 0.02), 0.011), DARK_METAL))
    return parts


def bike_body(model, body, kickstand=False, inner=None):
    if model == 'ga':
        return ga_parts(body, inner=inner, kickstand=kickstand)
    return v3.bike_parts(body, kickstand=kickstand)


# --------------------------------------------------------- Hàng chở theo
def kumquat_parts(center, radii, seed, fruits=46, lixi=6, pot=None):
    """Cây quất Tết: tán lá tròn xanh đậm (mặt lá lổn nhổn), quả chín vàng
    cam, treo vài bao lì xì đỏ; [pot] (tâm đáy, bán kính, cao) chậu sành."""
    cx, cy, cz = center
    rx, ry, rz = radii

    def canopy(p):
        x, y, z = p
        base = ellipsoid(p, center, radii)
        n = vnoise(x * 13 + z * 5 + seed, y * 13 - z * 7) + 0.5 * vnoise(x * 27 - z * 9, y * 27 + z * 11 + seed)
        return (base - 0.05 * (n - 0.75)) * 0.7

    def leaves(x, y, z):
        return vnoise(x * 70 + z * 31, y * 70 - z * 23, seed + 3) + 0.5 * vnoise(x * 140 - z * 50, y * 140 + z * 41, seed + 9)

    def canopy_pick(p, n):
        x, y, z = p
        return (vnoise(x * 22 + z * 9, y * 22 - z * 6, seed + 1) > 0.55).astype(np.int32)
    parts = [Obj('canopy', canopy, [Mat((30, 66, 30), rough=0.55, wrap=0.3, spec=0.6), Mat((58, 104, 40), rough=0.5, wrap=0.3, spec=0.6)],
                 pick=canopy_pick, bump=field_bump(leaves, 0.010))]
    rng = random.Random(seed)
    cs, rs = [], []
    for _ in range(fruits):
        th = rng.uniform(0, math.tau)
        ph = rng.uniform(0.15, 1.45)
        d = (math.cos(th) * math.sin(ph), math.sin(th) * math.sin(ph), math.cos(ph))
        k = rng.uniform(0.93, 1.0)
        cs.append((cx + d[0] * rx * k, cy + d[1] * ry * k, cz + d[2] * rz * k))
        rs.append(rng.uniform(0.019, 0.025) * max(rx, 0.3) / 0.3)
    parts.append(Obj('fruit', spheres(cs, rs), Mat((236, 128, 18), rough=0.25, spec=0.8, coat=0.4)))
    for i in range(lixi):
        th = rng.uniform(0, math.tau)
        ph = rng.uniform(0.6, 1.3)
        ex, ey, ez = cx + math.cos(th) * math.sin(ph) * rx * 1.0, cy + math.sin(th) * math.sin(ph) * ry * 1.0, cz + math.cos(ph) * rz
        yaw = th + math.pi / 2
        s = max(rx, 0.3) / 0.3

        def env(p, ex=ex, ey=ey, ez=ez, yaw=yaw, s=s):
            u, v = rot(p[0] - ex, p[1] - ey, -yaw)
            return rbox((u, v, p[2] - ez), (0, 0, 0), (0.028 * s, 0.006 * s, 0.042 * s), 0.003)

        def env_tint(p, n, alb, idx, ex=ex, ey=ey, ez=ez, s=s):
            gold = np.abs(p[2] - ez) < 0.012 * s
            return np.where(gold[:, None], lin((232, 186, 60)), alb)
        parts.append(Obj(f'lixi{i}', env, Mat((200, 22, 26), rough=0.35, spec=0.7, coat=0.5), tint=env_tint))
    if pot:
        (px_, py_, pz_), pr, ph_ = pot
        parts.append(Obj('pot', lambda p: round_cone(p, (px_, py_, pz_ + 0.02), (px_, py_, pz_ + ph_), pr * 0.75, pr),
                         Mat((40, 70, 140), rough=0.15, spec=0.8, coat=0.8)))
    return parts


def peach_parts(base, reach, height, seed, branches=7, lean=(0.45, 0.85), blossom=1.0, bloom=1.0):
    """Cành đào Tết: cành nâu sẫm toả lên như cái quạt, nụ và hoa hồng phấn
    dọc nửa trên các nhánh. [reach] (rx, ry_trước, ry_sau) độ toả ngang."""
    rng = random.Random(seed)
    bx, by, bz = base
    rx, ry_f, ry_b = reach
    wood = Mat((70, 46, 34), rough=0.7, spec=0.3)
    petal = [Mat((246, 166, 192), rough=0.6, wrap=0.45, spec=0.3), Mat((240, 130, 170), rough=0.6, wrap=0.45, spec=0.3),
             Mat((252, 204, 216), rough=0.6, wrap=0.45, spec=0.3)]
    parts = []
    for i in range(branches):
        ang = (i + rng.uniform(-0.3, 0.3)) / branches * math.tau
        out_ = rng.uniform(*lean)
        L = rng.uniform(0.75, 1.0) * height
        dx, dy = math.cos(ang), math.sin(ang)
        ry = ry_b if dy > 0 else ry_f
        tip = (bx + dx * rx * out_, by + dy * ry * out_, bz + L)
        mid = (bx + dx * rx * out_ * 0.4 + rng.uniform(-0.03, 0.03), by + dy * ry * out_ * 0.4, bz + L * 0.55)
        segs = [((bx, by, bz), mid, 0.016, 0.011), (mid, tip, 0.011, 0.005)]
        twigs = []
        for k in range(3):
            t = rng.uniform(0.25, 0.85)
            a = (mid[0] + (tip[0] - mid[0]) * t, mid[1] + (tip[1] - mid[1]) * t, mid[2] + (tip[2] - mid[2]) * t)
            ta = ang + rng.choice((-1, 1)) * rng.uniform(0.5, 1.1)
            tl = rng.uniform(0.12, 0.22) * height / 0.8
            b = (a[0] + math.cos(ta) * tl * rx / 0.4, a[1] + math.sin(ta) * tl * ry / 0.35, a[2] + tl * 0.6)
            segs.append((a, b, 0.006, 0.004))
            twigs.append((a, b))
        parts.append(Obj(f'branch{i}', segments(segs), wood))
        cs, rs, ks = [], [], []
        for a, b, n in [(mid, tip, 11)] + [(ta, tb, 5) for ta, tb in twigs] + [((bx, by, bz), mid, 3)]:
            for _ in range(round(n * blossom)):
                t = rng.uniform(0.15, 1.0)
                pos = tuple(a[j] + (b[j] - a[j]) * t + rng.uniform(-0.018, 0.018) * bloom for j in range(3))
                cs.append(pos)
                bud = rng.random() < 0.25
                rs.append((rng.uniform(0.011, 0.015) if bud else rng.uniform(0.019, 0.028)) * bloom)
                ks.append(1 if bud else rng.choice((0, 0, 2)))
        ks = np.array(ks)
        cs_arr = np.array(cs)

        def pick(p, n, cs_arr=cs_arr, ks=ks):
            x, y, z = p
            best = np.full(x.shape, 1e9)
            idx = np.zeros(x.shape, np.int32)
            for (cx, cy, cz), k in zip(cs_arr, ks):
                d = (x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2
                m = d < best
                best = np.where(m, d, best)
                idx = np.where(m, k, idx)
            return idx
        parts.append(Obj(f'blossom{i}', spheres(cs, rs), petal, pick=pick,
                         bump=field_bump(lambda x, y, z: np.sin(np.arctan2(y - by, x - bx) * 5 + z * 40), 0.004)))
    return parts


def boxes_parts(y0=1.40, z0=0.80):
    """Thùng các-tông buộc dây chun trên yên sau; thùng bia Tết đỏ ở trên."""
    card = Mat((182, 146, 98), rough=0.8, spec=0.3)
    red = Mat((190, 24, 28), rough=0.4, spec=0.6, coat=0.3)

    def low(p):
        return rbox(p, (0, y0, z0 + 0.14), (0.20, 0.17, 0.14), 0.012)

    def low_tint(p, n, alb, idx):
        tape = (np.abs(p[0]) < 0.03) & (p[2] > z0 + 0.26)
        return np.where(tape[:, None], lin((206, 176, 120)), alb)

    def top(p):
        u, v = rot(p[0], p[1] - y0 - 0.01, -0.09)
        return rbox((u, v, p[2]), (0, 0, z0 + 0.375), (0.17, 0.125, 0.095), 0.01)

    def top_tint(p, n, alb, idx):
        u, v = rot(p[0], p[1] - y0 - 0.01, -0.09)
        band = (np.abs(v) < 0.03) | ((np.abs(u - 0.07) < 0.035) & (np.abs(v + 0.07) < 0.035))
        return np.where(band[:, None], lin((236, 196, 70)), alb)

    def strap(p):
        z1 = z0 + 0.475
        a = capsule(p, (-0.17, y0 - 0.04, z1), (0.17, y0 + 0.02, z1), 0.008)
        b = capsule(p, (0.0, y0 - 0.15, z1 - 0.01), (0.03, y0 + 0.16, z1 - 0.01), 0.008)
        return np.minimum(a, b)
    return [Obj('box_low', low, card, tint=low_tint), Obj('box_top', top, red, tint=top_tint),
            Obj('strap', strap, Mat((30, 30, 32), rough=0.5),
                tint=lambda p, n, alb, idx: np.where((np.sin((p[0] + p[1]) * 90) > 0.6)[:, None], lin((200, 40, 40)), alb))]


def sack_parts(y0=1.40, z0=0.80):
    """Bao gạo dứa trắng nằm ngang yên sau, in sọc đỏ xanh."""
    def sack(p):
        x, y, z = p
        k = 1 + 0.25 * (1 - (x / 0.3) ** 2).clip(0, 1)
        return rbox((x, (y - y0) / k, (z - z0 - 0.11) / k), (0, 0, 0), (0.29, 0.15, 0.085), 0.075) * 0.85

    def weave(x, y, z):
        return np.sin(x * 900) * 0.5 + np.sin(y * 900 + z * 900) * 0.5

    def tint(p, n, alb, idx):
        x, y, z = p
        band = (np.abs(x - 0.0) < 0.12) & (np.abs(y - y0) < 0.11)
        red = band & (np.abs(np.abs(y - y0) - 0.07) < 0.015)
        blue = band & (np.abs(y - y0) < 0.045) & (np.abs(x) < 0.08)
        out = np.where(red[:, None], lin((196, 40, 36)), alb)
        return np.where(blue[:, None], lin((40, 90, 170)), out)
    return [Obj('sack', sack, Mat((232, 228, 214), rough=0.75, spec=0.35, sheen=0.3), tint=tint, bump=field_bump(weave, 0.0004))]


def toolkit_parts(y0=1.42, z0=0.80):
    """Đồ nghề thợ vá: hộp sắt đỏ, săm cuộn tròn, cái bơm tay buộc bên hông."""
    def box(p):
        return rbox(p, (0, y0, z0 + 0.10), (0.19, 0.115, 0.10), 0.012)

    def handle(p):
        return capsule(p, (-0.08, y0, z0 + 0.235), (0.08, y0, z0 + 0.235), 0.012)

    def tube(p):
        x, y, z = p
        q = length2(x, y - (y0 - 0.20)) - 0.15
        return length2(q, z - (z0 + 0.03)) - 0.024

    def pump(p):
        return capsule(p, (0.22, y0 - 0.25, z0 - 0.02), (0.235, y0 + 0.12, z0 + 0.0), 0.025)
    return [Obj('toolbox', box, Mat((176, 30, 28), rough=0.3, metal=0.4, coat=0.6),
                tint=lambda p, n, alb, idx: np.where((np.abs(p[2] - z0 - 0.165) < 0.006)[:, None], alb * 0.4, alb)),
            Obj('handle', handle, DARK_METAL),
            Obj('tube', tube, Mat((24, 24, 26), rough=0.5, spec=0.5)),
            Obj('pump', pump, [Mat((40, 90, 170), rough=0.3, spec=0.6, coat=0.5), DARK_METAL],
                pick=lambda p, n: (p[1] > y0 + 0.02).astype(np.int32))]


def jerrycan_parts(y0=1.42, z0=0.80):
    """Hai can nhựa đỏ đựng xăng buộc trên yên sau."""
    can = Mat((178, 40, 32), rough=0.35, spec=0.6, coat=0.3)
    parts = []
    for side in (-1, 1):
        def body(p, side=side):
            return rbox(p, (side * 0.115, y0, z0 + 0.17), (0.10, 0.15, 0.17), 0.03)

        def grip(p, side=side):
            return capsule(p, (side * 0.115, y0 - 0.06, z0 + 0.355), (side * 0.115, y0 + 0.05, z0 + 0.355), 0.014)

        def cap_(p, side=side):
            return capsule(p, (side * 0.115 + side * 0.05, y0 - 0.11, z0 + 0.34), (side * 0.115 + side * 0.05, y0 - 0.11, z0 + 0.37), 0.022)
        parts += [Obj(f'can{side}', body, can,
                      tint=lambda p, n, alb, idx, side=side: np.where((np.abs(np.abs(p[1] - y0) - 0.07) < 0.008)[:, None], alb * 0.7, alb)),
                  Obj(f'grip{side}', grip, can), Obj(f'cap{side}', cap_, Mat((230, 200, 40), rough=0.4))]
    return parts


# ------------------------------------------------------------ Dựng xe máy
def scooter(model, body, helmet, jacket, pants, passenger=None, cargo=None, hair=None, gloves=None, inner=None, seed=7):
    parts = bike_body(model, body, inner=inner)
    rider, pillion = (GA_RIDER, GA_PILLION) if model == 'ga' else (WAVE_RIDER, WAVE_PILLION)
    parts += person_parts(rider, helmet, jacket, pants, hair=hair, gloves=gloves, seed=seed)
    if passenger:
        parts += person_parts(pillion, passenger['helmet'], passenger['jacket'], passenger['pants'],
                              hair=passenger.get('hair'), seed=seed + 5)
    zc = 0.84 if model == 'ga' else 0.80
    if cargo == 'kumquat':
        parts += kumquat_parts((0.0, 1.33, zc + 0.56), (0.33, 0.29, 0.34), seed=seed, fruits=40, lixi=4,
                               pot=((0.0, 1.33, zc), 0.13, 0.22))
    elif cargo == 'peach':
        parts += peach_parts((0.0, 1.34, zc + 0.05), (0.40, 0.22, 0.36), 0.95, seed=seed)
    elif cargo == 'box':
        parts += boxes_parts(z0=zc)
    elif cargo == 'sack':
        parts += sack_parts(z0=zc)
    elif cargo == 'tools':
        parts += toolkit_parts(z0=zc)
    elif cargo == 'fuel':
        parts += jerrycan_parts(z0=zc)
    return parts


def raincoat_layers(parts, coat_color):
    """Áo mưa cánh dơi trùm lên người lái (cách ghép như xe người chơi)."""
    under = v3.zoomed(moto_scene(parts))
    rgb_u, a_u, z_u = v3.render(under)
    coat = v3.zoomed(moto_scene([v3.raincoat_obj(coat_color)]))
    rgb_c, a_c, z_c = v3.render(coat)
    on = (a_c > 0) & (z_c > z_u)
    ac = np.where(on, a_c, 0.0)
    tint = 0.3 + 0.7 * lin(coat_color) / lin(coat_color).max()
    alpha = ac + a_u * (1 - ac)
    pre = rgb_c * ac[..., None] + rgb_u * a_u[..., None] * (1 - ac)[..., None] * np.where(on[..., None], tint, 1.0)
    return under, (pre / np.maximum(alpha, 1e-6)[..., None], alpha)


# Bảng phối màu dòng xe máy Việt: thân xe, mũ, áo chống nắng / áo khoác, quần.
AI_SCOOTERS = [
    dict(model='so', body=(236, 236, 234), helmet=(245, 245, 245), jacket=(60, 150, 140), pants=(40, 50, 80)),
    dict(model='ga', body=(150, 24, 40), helmet=(240, 130, 170), jacket=(236, 236, 240), pants=(30, 30, 34),
         hair=(26, 22, 20), gloves=(236, 236, 240),
         passenger=dict(helmet=(40, 90, 190), jacket=(90, 90, 96), pants=(40, 50, 80))),
    dict(model='so', body=(30, 32, 36), helmet=(250, 200, 40), jacket=(240, 150, 60), pants=(110, 100, 90), cargo='sack'),
    dict(model='so', body=(110, 26, 36), helmet=(30, 30, 34), jacket=(90, 96, 104), pants=(40, 50, 80), cargo='box'),
    dict(model='ga', body=(236, 236, 232), helmet=(220, 40, 40), jacket=(210, 60, 90), pants=(30, 30, 34), hair=(30, 24, 20),
         passenger=dict(helmet=(245, 245, 245), jacket=(60, 110, 200), pants=(60, 70, 90))),
    dict(model='so', body=(40, 90, 170), helmet=(150, 150, 155), jacket=(200, 190, 160), pants=(60, 70, 90), cargo='peach'),
    dict(model='so', body=(150, 155, 160), helmet=(60, 160, 90), jacket=(150, 80, 160), pants=(40, 50, 80), cargo='kumquat'),
    dict(model='ga', body=(64, 68, 74), helmet=(40, 90, 190), jacket=(60, 110, 200), pants=(30, 30, 34),
         passenger=dict(helmet=(250, 200, 40), jacket=(240, 240, 236), pants=(110, 100, 90), hair=(30, 24, 20))),
    dict(model='ga', body=(222, 200, 160), inner=(120, 84, 60), helmet=(245, 245, 245), jacket=(240, 130, 170),
         pants=(40, 50, 80), hair=(26, 22, 20), gloves=(240, 130, 170), cargo='peach'),
    dict(model='so', body=(40, 40, 44), helmet=(245, 245, 245), jacket=(96, 130, 64), pants=(30, 30, 34),
         passenger=dict(helmet=(240, 130, 170), jacket=(236, 236, 240), pants=(40, 50, 80), hair=(26, 22, 20))),
]

AI_RAINCOATS = [
    dict(body=(236, 236, 234), helmet=(245, 245, 245), coat=(230, 120, 170)),
    dict(body=(40, 90, 170), helmet=(40, 90, 190), coat=(60, 160, 230)),
    dict(body=(30, 32, 36), helmet=(30, 30, 34), coat=(250, 210, 60)),
    dict(body=(110, 26, 36), helmet=(245, 245, 245), coat=(90, 190, 110)),
]

PARKED = [
    dict(model='so', body=(40, 90, 170), helmet=(245, 245, 245)),
    dict(model='ga', body=(236, 236, 232), helmet=None),
    dict(model='so', body=(110, 26, 36), helmet=(250, 200, 40)),
]

# CSGT: áo vàng chanh, mũ trắng; xe trắng sọc xanh, thùng sau, cụm đèn.
POLICE_UNIFORM = (196, 210, 62)


def police_bike(kickstand=False):
    parts = v3.bike_parts((236, 236, 236), kickstand=kickstand)

    def stripe(p, n, alb, idx):
        x, y, z = p
        s = (np.abs(np.abs(x) - 0.105) < 0.016) & (y > 0.85) & (y < 1.5)
        return np.where(s[:, None], lin((30, 70, 170)), alb)
    for o in parts:
        if o.name == 'rear_body':
            o.tint = stripe

    def box(p):
        return rbox(p, (0, 1.40, 0.97), (0.19, 0.15, 0.15), 0.045)

    def box_tint(p, n, alb, idx):
        band = (np.abs(p[2] - 1.0) < 0.025) | ((n[2] > 0.8) & (np.abs(p[1] - 1.40) < 0.02))
        return np.where(band[:, None], lin((30, 70, 170)), alb)
    parts.append(Obj('topbox', box, paint((236, 236, 236), metal=0.15), tint=box_tint))
    parts.append(Obj('lightbar', lambda p: rbox(p, (0, 1.42, 1.135), (0.20, 0.04, 0.025), 0.015), Mat((24, 24, 26), rough=0.4)))
    parts.append(Obj('lamps', lambda p: np.minimum(ellipsoid(p, (-0.155, 1.42, 1.165), (0.045, 0.035, 0.03)),
                                                   ellipsoid(p, (0.155, 1.42, 1.165), (0.045, 0.035, 0.03))),
                     [Mat((200, 30, 30), rough=0.08, spec=1.2, coat=1.0), Mat((40, 80, 220), rough=0.08, spec=1.2, coat=1.0)],
                     pick=lambda p, n: (p[0] > 0).astype(np.int32)))
    return parts


def build_moto(out):
    for i, c in enumerate(AI_SCOOTERS):
        parts = scooter(c['model'], c['body'], c['helmet'], c['jacket'], c['pants'], passenger=c.get('passenger'),
                        cargo=c.get('cargo'), hair=c.get('hair'), gloves=c.get('gloves'), inner=c.get('inner'), seed=11 + i)
        save_ai(moto_scene(parts), out, f'img_scooter_ai_{i + 1}', 1.6)
    for i, c in enumerate(AI_RAINCOATS):
        parts = scooter('so', c['body'], c['helmet'], (90, 90, 96), (40, 50, 80), seed=31 + i)
        under, layers = raincoat_layers(parts, c['coat'])
        save_ai(under, out, f'img_scooter_ai_raincoat_{i + 1}', 1.6, layers=layers)
    for i, c in enumerate(PARKED):
        parts = bike_body(c['model'], c['body'], kickstand=True)
        if c['helmet']:
            parts += v3.helmet_parts(c['helmet'], (0.0, 0.93 if c['model'] == 'so' else 0.95, 0.872 if c['model'] == 'so' else 0.90),
                                     yaw=0.35 - i * 0.5)
        save_ai(moto_scene(parts), out, f'img_scooter_parked_{i + 1}', 1.6, shadow=False)
    save_ai(moto_scene(police_bike() + person_parts(WAVE_RIDER, (245, 245, 245), POLICE_UNIFORM, (64, 72, 52), seed=41)),
            out, 'img_scooter_police', 1.6)
    save_ai(moto_scene(police_bike(kickstand=True)), out, 'img_scooter_police_parked', 1.6, shadow=False)
    save_ai(moto_scene(scooter('so', (40, 70, 130), (40, 40, 44), (90, 96, 104), (40, 44, 50), cargo='tools', seed=51)),
            out, 'img_scooter_mechanic', 1.6, shadow=False)
    save_ai(moto_scene(scooter('so', (30, 32, 36), (200, 36, 32), (40, 90, 170), (40, 50, 80), cargo='fuel', seed=52)),
            out, 'img_scooter_fuel', 1.6, shadow=False)


# ================================================================== Ô tô
PAINT_I, GLASS_I, FRIT_I, TRIM_I, HEAD_I, HEADIN_I, DRL_I, TAIL_I, TAILIN_I, CHROME_I, LINER_I = range(11)


def car_mats(color, metal=0.55):
    """Bộ vật liệu thân xe như sedan người chơi (+ lót thùng bán tải)."""
    return [paint(color, metal=metal),
            Mat((10, 11, 12), rough=0.03, glass=1.0, spec=1.0),
            Mat((12, 12, 13), rough=0.12, spec=1.0, coat=0.8),
            Mat((20, 21, 22), rough=0.45, spec=0.5),
            Mat((190, 196, 202), rough=0.04, metal=0.75, coat=1.0),
            Mat((26, 28, 32), rough=0.15, metal=0.5, coat=1.0),
            Mat((240, 244, 250), rough=0.05, coat=1.0, emit=0.6),
            Mat((215, 30, 30), rough=0.05, spec=1.2, coat=1.0, emit=0.35),
            Mat((40, 6, 8), rough=0.05, spec=1.2, coat=1.0),
            CHROME,
            Mat((30, 31, 33), rough=0.7, spec=0.4)]


class Shape:
    """Thân xe dựng như sedan người chơi nhưng tham số hoá: [W] nửa bề rộng
    theo chiều dài, [H] mặt trên thân dưới, [ROOF] nóc, [WG] nửa bề rộng
    khoang kính ở đường gân hông [belt], [tumble] độ thu vào của kính sườn."""

    def __init__(self, L, W, H, ROOF, WG, belt, tumble, f_round=0.20, r_round=0.15, hood=(0.25, 1.30), belly=0.20):
        self.L, self.W, self.H, self.ROOF, self.WG = L, W, H, ROOF, WG
        self.belt, self.tumble, self.f_round, self.r_round = belt, tumble, f_round, r_round
        self.hood, self.belly = hood, belly

    def lower(self, p):
        x, y, z = p
        ax = np.abs(x)
        bul = 1 - 0.06 * ((z - (self.belt - 0.4)) / 0.4) ** 2
        w = self.W(y) * bul
        d_side = (ax - w) / np.sqrt(1 + self.W.d(y) ** 2)
        yf = self.f_round * (ax / 0.9) ** 2.4
        yr = self.L - self.r_round * (ax / 0.9) ** 2.4
        d_front = (yf - y) / np.sqrt(1 + (self.f_round * 2.4 * (ax / 0.9) ** 1.4 / 0.9) ** 2)
        d_rear = (y - yr) / np.sqrt(1 + (self.r_round * 2.4 * (ax / 0.9) ** 1.4 / 0.9) ** 2)
        plan = smax(smax(d_side, d_front, 0.36), d_rear, 0.26)
        crown = 0.08 * (ax / 0.85) ** 2
        h0, h1 = self.hood
        hood_t = np.clip((h1 - y) / 0.3, 0, 1) * np.clip((y - h0) / 0.25, 0, 1)
        crease = 0.014 * np.exp(-((ax - 0.42) / 0.05) ** 2) * hood_t
        hy = self.H.d(y)
        d_top = (z - self.H(y) + crown - crease) / np.sqrt(1 + hy * hy + (0.18 * ax / 0.72) ** 2)
        body = smax(plan, d_top, 0.17)
        return smax(body, self.belly - z, 0.05)

    def wg(self, y, z):
        return self.WG(y) - self.tumble * (z - self.belt)

    def green(self, p):
        x, y, z = p
        ax = np.abs(x)
        d_side = (ax - self.wg(y, z)) / np.sqrt(1 + self.tumble ** 2)
        ry = self.ROOF.d(y)
        crown = 0.05 * (ax / 0.6) ** 2
        d_top = (z - self.ROOF(y) + crown) / np.sqrt(1 + ry * ry + (0.17 * ax / 0.6) ** 2)
        g = smax(d_side, d_top, 0.12)
        return smax(g, self.belt - 0.17 - z, 0.02)

    def body(self, p):
        return smin(self.lower(p), self.green(p), 0.035)


def door_mirror(x0, y0, z0):
    def sdf(p):
        x, y, z = p
        q0 = np.abs(x)
        head = ellipsoid((q0, y + 0.25 * (q0 - x0), z), (x0, y0, z0), (0.105, 0.07, 0.062))
        stalk = rbox((q0, y, z), (x0 - 0.10, y0 - 0.005, z0 - 0.035), (0.06, 0.045, 0.03), 0.02)
        return smin(head, stalk, 0.03)
    return sdf


def wipers(shape, ya):
    def sdf(p):
        out = None
        for (x0, y0), (x1, y1) in (((-0.62, ya), (0.02, ya - 0.04)), ((0.06, ya - 0.01), (0.60, ya + 0.03))):
            z0 = shape.ROOF(np.array([y0]))[0] + 0.012
            z1 = shape.ROOF(np.array([y1]))[0] + 0.012
            d = capsule(p, (x0, y0, z0), (x1, y1, z1), 0.009)
            out = d if out is None else np.minimum(out, d)
        return out
    return sdf


def windows(shape, p, n, idx, ws_end, rw_start, ya0, ya_k, yc0, yc_k, pillars, rear_mode='slope'):
    """Kính lái, kính hậu, kính sườn (theo khung cửa) + viền gốm đen."""
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    wg = shape.wg(y, z)
    zr = shape.ROOF(y)
    above = z > shape.belt + 0.012
    ws = above & (y < ws_end) & (ax < wg - 0.07) & (ny < -0.15)
    ws_in = ws & (ax < wg - 0.10) & (y < ws_end - 0.05) & (z > shape.belt + 0.035)
    if rear_mode == 'slope':
        rw = above & (y > rw_start) & (ax < wg - 0.10) & (ny > 0.15)
        rw_in = rw & (ax < wg - 0.13) & (y > rw_start + 0.05) & (z > shape.belt + 0.06)
    else:  # kính hậu dựng đứng (MPV, cabin bán tải)
        rw = above & (y > rw_start) & (ny > 0.3) & (ax < wg - 0.09) & (z < zr - 0.04)
        rw_in = rw & (ax < wg - 0.12) & (z < zr - 0.07) & (z > shape.belt + 0.10)
    ya = ya0 + (z - shape.belt) * ya_k
    yc = yc0 - (z - shape.belt) * yc_k
    sw = above & (np.abs(nx) > 0.45) & (z < zr - 0.07) & (y > ya) & (y < yc)
    pil = np.zeros_like(sw)
    for yp, w in pillars:
        pil |= sw & (np.abs(y - yp) < w)
    sw_in = sw & ~pil & (z < zr - 0.09) & (z > shape.belt + 0.04) & (y > ya + 0.03) & (y < yc - 0.03)
    idx[ws | rw | sw] = FRIT_I
    idx[ws_in | rw_in | sw_in] = GLASS_I
    idx[pil] = FRIT_I
    return idx


def lamps(idx, x, y, z, head, headin, z_head):
    """Đèn pha vuốt về hai góc: [head]/[headin] (tâm x, y, nửa dài, nửa rộng,
    góc, bo) viền ngoài / hốc trong, chỉ ở trên độ cao [z_head]."""
    ax = np.abs(x)
    hd = _in_rrect(ax, y, *head)
    h = (hd < 0) & (z > z_head)
    idx[h] = HEAD_I
    idx[h & (_in_rrect(ax, y, *headin) < 0)] = HEADIN_I
    idx[h & (np.abs(hd + 0.012) < 0.009) & (rot(ax - head[0], y - head[1], -head[4])[1] < 0)] = DRL_I
    return idx


# ------------------------------------------------- MPV 7 chỗ (Innova / Xpander)
MPV = Shape(
    L=4.50,
    W=Curve([(-0.2, 0.78), (0.0, 0.80), (0.25, 0.85), (0.9, 0.885), (2.3, 0.88), (3.6, 0.888), (4.2, 0.876), (4.5, 0.85), (4.7, 0.82)]),
    H=Curve([(-0.2, 0.60), (0.0, 0.66), (0.12, 0.78), (0.4, 0.88), (0.8, 0.95), (1.05, 0.985), (1.15, 1.0), (2.5, 1.03),
             (4.15, 1.06), (4.38, 1.04), (4.50, 0.88), (4.65, 0.6)]),
    ROOF=Curve([(0.95, 0.85), (1.12, 1.03), (1.40, 1.33), (1.70, 1.57), (2.0, 1.705), (2.4, 1.755), (3.5, 1.765), (4.1, 1.75),
                (4.3, 1.69), (4.42, 1.52), (4.52, 1.06), (4.6, 0.75)]),
    WG=Curve([(1.0, 0.66), (1.2, 0.72), (1.8, 0.765), (3.0, 0.775), (4.1, 0.77), (4.4, 0.72), (4.55, 0.65)]),
    belt=1.04, tumble=0.22, f_round=0.20, r_round=0.10, hood=(0.30, 1.10))


def mpv_pick(p, n):
    x, y, z = p
    ax = np.abs(x)
    idx = np.full(x.shape, PAINT_I, np.int32)
    idx = windows(MPV, p, n, idx, ws_end=2.02, rw_start=4.22, ya0=1.18, ya_k=1.15, yc0=4.30, yc_k=0.25,
                  pillars=((2.30, 0.045), (3.36, 0.06)), rear_mode='upright')
    idx[(y > 1.06) & (y < 1.16) & (z < 1.06) & (n[2] > 0.3) & (ax < 0.68)] = TRIM_I
    idx = lamps(idx, x, y, z, (0.62, 0.17, 0.22, 0.07, 0.35, 0.04), (0.60, 0.16, 0.14, 0.04, 0.35, 0.03), 0.62)
    grille = (ax < 0.50) & (y < 0.10 + 0.08 * (ax / 0.5) ** 2) & (n[1] < -0.25) & (z > 0.40)
    idx[grille] = TRIM_I
    idx[grille & (np.abs(((z - 0.45) % 0.075) - 0.0375) < 0.008)] = CHROME_I
    tail = (ax > 0.58) & (y > 4.28) & (n[1] > 0.25) & (z > 0.80) & (z < 1.32)
    idx[tail] = TAIL_I
    idx[tail & (ax < 0.66)] = TAILIN_I
    idx[(ax < 0.45) & (np.abs(z - 1.10) < 0.013) & (n[1] > 0.5)] = CHROME_I
    return idx


def body_lines(hood_y, hood_x, trunk=None):
    """Khe nắp ca-pô (và cốp / cửa hậu) — đường ron sơn mảnh."""
    h0, h1 = hood_y

    def tint(p, n, alb, idx):
        x, y, z = p
        ax = np.abs(x)
        pt = idx == PAINT_I
        side = np.abs(ax - (hood_x - 0.10 * np.clip((h1 - y) / 1.0, 0, 1))) < 0.0065
        line = (side & (y > h0) & (y < h1)) | ((np.abs(y - h1) < 0.0065) & (ax < hood_x))
        line |= (np.abs(y - (h0 + 0.09 * (ax / 0.6) ** 2)) < 0.0075) & (ax < hood_x - 0.1) & (n[2] > 0.3)
        if trunk:
            t0, tx = trunk
            line |= ((np.abs(ax - tx) < 0.0065) & (y > t0)) | ((np.abs(y - t0) < 0.0065) & (ax < tx) & (n[2] > 0.3))
        return np.where((pt & line)[:, None], alb * 0.45, alb)
    return tint


def roof_rails(shape, x0, ya, yb):
    ys = np.linspace(ya, yb, 7)
    zs = shape.ROOF(ys) - 0.05 * (x0 / 0.6) ** 2 + 0.05
    segs = [((x0, ys[i], zs[i]), (x0, ys[i + 1], zs[i + 1]), 0.017, 0.017) for i in range(len(ys) - 1)]
    rail = segments(segs)
    return mirror_x(rail)


def mpv_scene(color, metal=0.55, shirt=(92, 104, 122)):
    parts = [Obj('body', MPV.body, car_mats(color, metal), pick=mpv_pick, tint=body_lines((0.30, 1.10), 0.68)),
             Obj('mirrors', door_mirror(0.965, 1.28, 1.13), [paint(color, metal=metal), Mat((20, 21, 22), rough=0.45)],
                 pick=lambda p, n: (p[2] < 1.10).astype(np.int32)),
             Obj('wipers', wipers(MPV, 1.20), Mat((16, 16, 18), rough=0.4)),
             Obj('rails', roof_rails(MPV, 0.56, 1.98, 4.12), [Mat((30, 30, 32), rough=0.35, spec=0.6), ALU],
                 pick=lambda p, n: (p[2] > MPV.ROOF(p[1]) + 0.045).astype(np.int32)),
             Obj('antenna', lambda p: ellipsoid(p, (0, 4.02, 1.75), (0.03, 0.09, 0.04)),
                 Mat((14, 14, 16), rough=0.15, spec=0.8, coat=1.0))]
    interior = shifted(v3.car_interior(shirt=shirt), dy=-0.30, dz=0.17)
    return Scene(parts, ((-1.12, -0.06, 0.15), (1.12, 4.56, 1.90)), v3.CAR_PPM, v3.CAR_ORIGIN, v3.CAR_SIZE,
                 ao_scale=1.6, interior=interior, glass_tint=(0.30, 0.33, 0.36))


# --------------------------------------------- Bán tải cabin kép (kiểu Ranger)
PU = Shape(
    L=5.28,
    W=Curve([(-0.2, 0.80), (0.0, 0.84), (0.3, 0.90), (1.0, 0.935), (3.0, 0.93), (4.2, 0.935), (5.0, 0.928), (5.28, 0.905), (5.45, 0.86)]),
    H=Curve([(-0.2, 0.72), (0.0, 0.82), (0.12, 0.95), (0.4, 1.05), (0.9, 1.10), (1.3, 1.13), (1.45, 1.15), (2.5, 1.18),
             (3.3, 1.21), (5.15, 1.22), (5.28, 1.14), (5.4, 0.75)]),
    ROOF=Curve([(1.25, 1.02), (1.45, 1.24), (1.75, 1.57), (2.0, 1.76), (2.3, 1.82), (3.0, 1.82), (3.18, 1.80), (3.27, 1.64),
                (3.31, 1.24), (3.33, 0.9)]),
    WG=Curve([(1.3, 0.70), (1.6, 0.76), (2.2, 0.79), (3.0, 0.79), (3.3, 0.78)]),
    belt=1.17, tumble=0.22, f_round=0.16, r_round=0.05, hood=(0.25, 1.40))

PU_BED = (3.44, 5.16)
PU_WELL_Y = 4.17


def pu_body(p):
    x, y, z = p
    b = PU.body(p)
    y0, y1 = PU_BED
    inner = rbox(p, (0, (y0 + y1) / 2, 1.40), (0.862, (y1 - y0) / 2, 0.62), 0.03)
    b = smax(b, -inner, 0.015)
    # hốc bánh sau gồ lên trong lòng thùng
    well = rbox((np.abs(x), y, z), (0.80, PU_WELL_Y, 0.80), (0.12, 0.42, 0.22), 0.08)
    return np.minimum(b, smax(well, np.abs(x) - 0.866, 0.01))


def pu_pick(p, n):
    x, y, z = p
    ax = np.abs(x)
    idx = np.full(x.shape, PAINT_I, np.int32)
    idx = windows(PU, p, n, idx, ws_end=2.30, rw_start=3.22, ya0=1.32, ya_k=1.1, yc0=3.27, yc_k=0.1,
                  pillars=((2.38, 0.045),), rear_mode='upright')
    idx[(y > 1.20) & (y < 1.30) & (z < 1.18) & (n[2] > 0.3) & (ax < 0.70)] = TRIM_I
    idx = lamps(idx, x, y, z, (0.66, 0.16, 0.22, 0.06, 0.30, 0.03), (0.64, 0.155, 0.14, 0.035, 0.30, 0.025), 0.80)
    grille = (ax < 0.55) & (y < 0.12 + 0.05 * (ax / 0.55) ** 2) & (n[1] < -0.25) & (z > 0.50)
    idx[grille] = TRIM_I
    idx[grille & ((np.abs(z - 0.86) < 0.025) | (np.abs(z - 0.70) < 0.02))] = CHROME_I
    y0, y1 = PU_BED
    bed = (y > y0 - 0.02) & (y < y1 + 0.02) & (ax < 0.875) & (z < 1.19)
    idx[bed] = LINER_I
    tail = (ax > 0.80) & (y > 5.10) & (n[1] > 0.3) & (z > 0.85) & (z < 1.18)
    idx[tail] = TAIL_I
    return idx


def pu_bump(p, n):
    x, y, z = p
    y0, y1 = PU_BED
    floor = (z < 0.84) & (y > y0) & (y < y1) & (np.abs(x) < 0.86)
    return n[0] + 0.35 * np.sin(x * 38) * floor, n[1], n[2]


def pu_extras():
    def sportbar(p):
        q = (np.abs(p[0]), p[1], p[2])
        post = capsule(q, (0.80, 3.56, 1.20), (0.70, 3.56, 1.52), 0.032)
        top = capsule(p, (-0.70, 3.56, 1.52), (0.70, 3.56, 1.52), 0.032)
        brace = capsule(q, (0.72, 3.58, 1.50), (0.84, 3.98, 1.22), 0.026)
        return np.minimum(np.minimum(post, top), brace)

    def flares(p):
        q = (np.abs(p[0]), p[1], p[2])
        d = None
        for yc in (0.98, PU_WELL_Y):
            v = arc_shell(q, (0.905, yc, 0.42), 0.46, 0.035, 0.065, 0.015)
            v = smax(v, 0.72 - q[2], 0.02)
            d = v if d is None else np.minimum(d, v)
        return d
    return [Obj('mirrors', door_mirror(1.0, 1.55, 1.27), [Mat((26, 27, 29), rough=0.35, spec=0.6), Mat((20, 21, 22), rough=0.45)],
                pick=lambda p, n: (p[2] < 1.24).astype(np.int32)),
            Obj('wipers', wipers(PU, 1.36), Mat((16, 16, 18), rough=0.4)),
            Obj('sportbar', sportbar, Mat((32, 33, 36), rough=0.3, metal=0.6, coat=0.6)),
            Obj('flares', flares, Mat((26, 27, 29), rough=0.6, spec=0.4))]


def pu_scene(color, cargo=None, metal=0.55, shirt=(92, 104, 122), seed=5):
    parts = [Obj('body', pu_body, car_mats(color, metal), pick=pu_pick, bump=pu_bump,
                 tint=body_lines((0.25, 1.40), 0.70, trunk=None))] + pu_extras()
    yc = (PU_BED[0] + PU_BED[1]) / 2
    if cargo == 'kumquat':
        parts += kumquat_parts((0.0, yc, 1.85), (0.62, 0.66, 0.60), seed=seed, fruits=150, lixi=12,
                               pot=((0.0, yc, 0.80), 0.30, 0.48))
    elif cargo == 'peach':
        parts += peach_parts((0.0, yc, 1.10), (0.86, 0.80, 0.80), 1.25, seed=seed, branches=13, blossom=2.6, bloom=1.45)
        parts.append(Obj('pot', lambda p: round_cone(p, (0, yc, 0.82), (0, yc, 1.18), 0.22, 0.30),
                         Mat((150, 70, 40), rough=0.5, spec=0.5)))
    elif cargo == 'boxes':
        card = Mat((182, 146, 98), rough=0.8, spec=0.3)
        for i, (bxp, byp, yaw, hw, hl, hh) in enumerate(((-0.42, 3.80, 0.05, 0.36, 0.28, 0.25), (0.40, 3.86, -0.04, 0.36, 0.30, 0.22),
                                                         (-0.30, 4.55, -0.08, 0.40, 0.32, 0.20), (0.45, 4.62, 0.10, 0.30, 0.26, 0.28))):
            def box(p, bxp=bxp, byp=byp, yaw=yaw, hw=hw, hl=hl, hh=hh):
                u, v = rot(p[0] - bxp, p[1] - byp, -yaw)
                return rbox((u, v, p[2]), (0, 0, 0.80 + hh), (hw, hl, hh), 0.015)

            def tape(p, n, alb, idx, bxp=bxp, byp=byp, yaw=yaw):
                u, v = rot(p[0] - bxp, p[1] - byp, -yaw)
                return np.where(((np.abs(u) < 0.035) & (n[2] > 0.7))[:, None], lin((206, 176, 120)), alb)
            parts.append(Obj(f'carton{i}', box, card, tint=tape))
    interior = shifted(v3.car_interior(shirt=shirt), dy=0.0, dz=0.27)
    return Scene(parts, ((-1.18, -0.06, 0.15), (1.18, 5.34, 2.55)), v3.CAR_PPM, (55.5, 1.0), (111, 250),
                 ao_scale=1.6, interior=interior, glass_tint=(0.30, 0.33, 0.36))


# ---------------------------------------------------------------- Sedan AI
def sedan_scene(color, metal=0.55, shirt=(92, 104, 122)):
    parts = v3.car_parts(color)
    parts[0].mats[0] = paint(color, metal=metal)
    parts[1].mats[0] = paint(color, metal=metal)
    return Scene(parts, ((-1.12, -0.06, 0.15), (1.12, 4.52, 1.52)), v3.CAR_PPM, v3.CAR_ORIGIN, v3.CAR_SIZE,
                 ao_scale=1.6, interior=v3.car_interior(shirt=shirt), glass_tint=(0.36, 0.39, 0.42))


SEDANS = [
    ('white', (236, 236, 232), 0.12, (60, 70, 90)),
    ('silver', (178, 182, 188), 0.85, (200, 200, 196)),
    ('black', (16, 17, 19), 0.35, (230, 230, 226)),
    ('blue', (28, 58, 132), 0.6, (120, 60, 60)),
    ('gray', (92, 96, 102), 0.7, (40, 40, 44)),
    ('brown', (104, 66, 44), 0.65, (90, 110, 150)),
    ('green', (28, 84, 62), 0.6, (230, 220, 200)),
]


def build_car(out):
    for name, rgb, metal, shirt in SEDANS:
        save_ai(sedan_scene(rgb, metal, shirt), out, f'img_sedan_{name}', 2.2)
    save_ai(mpv_scene((196, 200, 204), metal=0.85, shirt=(150, 40, 40)), out, 'img_mini_van', 2.2)
    save_ai(pu_scene((34, 84, 160), cargo='kumquat', metal=0.6, seed=61), out, 'img_pickup_blue', 2.2)
    save_ai(pu_scene((236, 236, 232), cargo='peach', metal=0.12, seed=62), out, 'img_pickup_white', 2.2)
    save_ai(pu_scene((112, 116, 120), cargo='boxes', metal=0.7, seed=63), out, 'img_pickup_gray', 2.2)


# ============================================================== Xe khách
BUSES = [
    ('img_bus_1', (238, 238, 234), (200, 36, 32), 0.12),
    ('img_bus_2', (240, 240, 238), (30, 90, 180), 0.12),
    ('img_bus_3', (232, 112, 32), (246, 246, 244), 0.3),
]


def build_bus(out):
    for name, main, stripe, metal in BUSES:
        save_ai(v3.bus_scene(main, stripe, metal=metal), out, name, 2.4)


# =============================================================== Xe tải
# Xe tải cabin lật (kiểu Hyundai HD / Hino): dài 7,95 m, rộng 2,45 m. Khung
# ảnh 62 × 184 px như xe container cũ; game vẽ rộng 52 nên dài ≈ 154, khớp
# hộp va chạm 150 của TrafficType.truck.
TRUCK_PPM = 22.5
TRUCK_ORIGIN = (31.0, 3.0)
TRUCK_SIZE = (62, 184)
TRUCK_Y1 = 7.95


def cab_parts(color, visor=False, length=1.95, height=2.72, w=1.13):
    pt = paint(color, metal=0.25)

    def cab(p):
        x, y, z = p
        base = rbox(p, (0, length / 2, (0.55 + height) / 2), (w, length / 2, (height - 0.55) / 2), 0.17)
        slope = ((z - 1.45) * 0.17 - y) / math.sqrt(1 + 0.17 ** 2)
        return smax(base, slope, 0.12)

    def pick(p, n):
        x, y, z = p
        ax = np.abs(x)
        idx = np.zeros(x.shape, np.int32)
        ws = (n[1] < -0.35) & (z > 1.60) & (z < 2.54) & (ax < w - 0.08)
        idx[ws] = 2
        idx[ws & (z > 1.66) & (z < 2.48) & (ax < w - 0.13) & (np.abs(x) > 0.025)] = 1
        lamp = (z > height - 0.06) & (y < 0.30) & (np.abs(((x + 0.9) % 0.45) - 0.225) < 0.05) & (ax < 1.0)
        idx[lamp] = 3
        return idx

    def tint(p, n, alb, idx):
        x, y, z = p
        hatch = (np.abs(x) < 0.32) & (np.abs(y - length * 0.55) < 0.28) & (n[2] > 0.9)
        edge = hatch & ((np.abs(np.abs(x) - 0.32) < 0.02) | (np.abs(np.abs(y - length * 0.55) - 0.28) < 0.02))
        return np.where(edge[:, None], alb * 0.55, alb)
    mats = [pt, Mat((10, 11, 12), rough=0.03, glass=1.0, spec=1.0), Mat((14, 14, 15), rough=0.2, spec=0.8),
            Mat((240, 150, 30), rough=0.08, coat=1.0, emit=0.4)]
    parts = [Obj('cab', cab, mats, pick=pick, tint=tint)]

    def mirrors(p):
        q = (np.abs(p[0]), p[1], p[2])
        arm = capsule(q, (w - 0.03, 0.32, 2.10), (w + 0.17, 0.10, 2.14), 0.025)
        arm2 = capsule(q, (w - 0.03, 0.32, 1.50), (w + 0.17, 0.10, 1.56), 0.025)
        head = rbox(q, (w + 0.19, 0.05, 1.84), (0.05, 0.10, 0.30), 0.03)
        return np.minimum(np.minimum(arm, arm2), head)
    parts.append(Obj('mirrors', mirrors, Mat((24, 24, 26), rough=0.35, spec=0.6)))
    if visor:
        parts.append(Obj('visor', lambda p: rbox(p, (0, 0.10, height - 0.02), (w - 0.10, 0.16, 0.025), 0.02),
                         Mat((30, 34, 40), rough=0.3, spec=0.6, coat=0.5)))
    parts.append(Obj('chassis', lambda p: rbox(p, (0, length + 0.12, 0.85), (0.55, 0.18, 0.2), 0.04), DARK_METAL))
    return parts


def tarp_parts(color, y0=2.08):
    y1 = TRUCK_Y1
    yc, hl = (y0 + y1) / 2, (y1 - y0) / 2
    bay = (y1 - y0) / 6

    def tarp(p):
        x, y, z = p
        plan = rbox((x, y, np.zeros_like(z)), (0, yc, 0), (1.22, hl, 1.0), 0.08)
        k = (y - y0) / bay
        top = 3.22 - 0.085 * np.sin(np.pi * k) ** 2 * (1 - 0.6 * (np.abs(x) / 1.22) ** 4)
        d = smax(plan, (z - top) * 0.95, 0.10)
        return smax(d, 1.0 - z, 0.02)

    def tint(p, n, alb, idx):
        x, y, z = p
        ax = np.abs(x)
        k = (y - y0) / bay
        rope = ((np.abs(k - np.round(k)) * bay < 0.012) & (np.round(k) > 0) & (np.round(k) < 6)) | (np.abs(ax - 1.08) < 0.011)
        # dây chéo chữ X trong mỗi khoang
        fk = k - np.floor(k)
        rope |= (np.abs(np.abs(fk - 0.5) * bay * 2.2 - ax) < 0.011) & (ax < 1.08)
        dirt = 0.82 + 0.3 * fbm(x * 1.6, y * 1.6, 23, 3)
        out = alb * dirt[:, None]
        return np.where(rope[:, None], lin((150, 130, 96)), out)

    def head(p):
        return rbox(p, (0, y0 - 0.03, 2.05), (1.20, 0.04, 1.22), 0.02)
    return [Obj('tarp', tarp, fabric(color, rough=0.8, sheen=0.35), tint=tint,
                bump=field_bump(lambda x, y, z: fbm(x * 6, y * 6, 31, 3) + 0.3 * np.sin(x * 25 + fbm(x * 3, y * 3, 5, 2) * 6), 0.012)),
            Obj('headboard', head, paint((70, 74, 80), metal=0.3))]


def box_parts(y0=2.08):
    y1 = TRUCK_Y1
    yc, hl = (y0 + y1) / 2, (y1 - y0) / 2

    def box(p):
        return rbox(p, (0, yc, 2.08), (1.235, hl, 1.30), 0.05)

    def tint(p, n, alb, idx):
        x, y, z = p
        seam = (n[2] > 0.9) & (np.abs(((y - y0) % 0.62) - 0.31) > 0.296)
        rail = np.abs(x) > 1.17
        rivet = seam & (np.abs(((x + 1.2) % 0.16) - 0.08) < 0.012)
        k = np.where(seam, 0.78, 1.0) * np.where(rail, 1.08, 1.0) * np.where(rivet, 1.3, 1.0)
        streak = 0.94 + 0.08 * fbm(x * 0.8, y * 3.5, 41, 3)
        return alb * (k * streak)[:, None]
    return [Obj('box', box, paint((214, 218, 222), rough=0.35, metal=0.5), tint=tint)]


def dump_parts(y0=2.30):
    y1 = 7.85
    yc, hl = (y0 + y1) / 2, (y1 - y0) / 2
    steel = paint((66, 70, 76), rough=0.5, metal=0.35)

    def tipper(p):
        outer = rbox(p, (0, yc, 1.95), (1.20, hl, 0.70), 0.05)
        inner = rbox(p, (0, yc, 2.32), (1.125, hl - 0.075, 0.72), 0.03)
        d = smax(outer, -inner, 0.015)
        canopy = rbox(p, (0, 1.82, 2.86), (1.10, 0.52, 0.035), 0.02)
        front = rbox(p, (0, y0 + 0.04, 2.25), (1.20, 0.05, 0.64), 0.02)
        return np.minimum(np.minimum(d, canopy), front)

    def tipper_tint(p, n, alb, idx):
        x, y, z = p
        rust = smoothstep(0.55, 0.75, fbm(x * 3, y * 3 + z * 2, 51, 4))
        rib = (n[2] > 0.8) & (y > 1.35) & (y < 2.33) & (np.abs(((x + 1.1) % 0.27) - 0.135) < 0.02)
        out = alb * (1 - 0.35 * rust)[:, None] + lin((120, 66, 36)) * (0.35 * rust)[:, None]
        return np.where(rib[:, None], out * 0.7, out)

    def sand(p):
        x, y, z = p
        plan = rbox((x, y, np.zeros_like(z)), (0, yc, 0), (1.12, hl - 0.08, 1.0), 0.03)
        u = (y - yc) / hl
        heap = 2.30 + 0.46 * (1 - (x / 1.25) ** 2) * (1 - np.abs(u) ** 3) + 0.07 * (fbm(x * 2.5, y * 2.5, 17, 3) - 0.5)
        d = smax(plan, (z - heap) * 0.8, 0.04)
        return smax(d, 1.6 - z, 0.02)

    def sand_pick(p, n):
        x, y, z = p
        return (fbm(x * 1.7, y * 1.7, 29, 3) > 0.6).astype(np.int32)

    def grain(x, y, z):
        return vnoise(x * 140, y * 140, 3) + 0.5 * vnoise(x * 33 + 7, y * 33, 8)
    return [Obj('tipper', tipper, steel, tint=tipper_tint),
            Obj('sand', sand, [Mat((198, 168, 120), rough=0.95, spec=0.2), Mat((178, 150, 108), rough=0.9, spec=0.25)],
                pick=sand_pick, bump=field_bump(grain, 0.004))]


def truck_scene(parts):
    return Scene(parts, ((-1.40, -0.12, 0.3), (1.40, 8.05, 3.5)), TRUCK_PPM, TRUCK_ORIGIN, TRUCK_SIZE, ao_scale=2.4)


def build_truck(out):
    save_ai(truck_scene(cab_parts((36, 86, 168), visor=True) + tarp_parts((56, 92, 60))), out, 'img_container_1', 2.4)
    save_ai(truck_scene(cab_parts((236, 236, 232)) + box_parts()), out, 'img_container_2', 2.4)
    save_ai(truck_scene(cab_parts((184, 30, 28), height=2.74) + dump_parts()), out, 'img_truck', 2.4)


BUILDERS = {
    'moto': build_moto,
    'car': build_car,
    'bus': build_bus,
    'truck': build_truck,
}


if __name__ == '__main__':
    args = sys.argv[1:]
    out = OUT
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    if '--zoom' in args:
        i = args.index('--zoom')
        v3.ZOOM = int(args[i + 1])
        args = args[:i] + args[i + 2:]
    os.makedirs(out, exist_ok=True)
    for k in (args or list(BUILDERS)):
        BUILDERS[k](out)
