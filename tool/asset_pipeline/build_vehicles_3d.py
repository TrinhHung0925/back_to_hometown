"""Xe của người chơi dựng thành mô hình 3D thật rồi "chụp" thẳng từ trên xuống.

Không cần Blender: mỗi xe là một mô hình hàm khoảng cách có dấu (SDF — khối
hộp bo tròn, viên nang, elip, xuyến cho bánh xe, hoà trộn mềm cho thân vỏ,
khoét mềm cho hốc bánh / cửa kính) và được dò tia (raymarch) bằng numpy theo
phép chiếu trực giao nhìn thẳng xuống mặt đường, đúng góc nhìn của game.

Đổ sáng gần với vật lý: nắng (cùng hướng tây bắc như các hình cũ: nắng chiếu
từ phía trên - bên trái ảnh khi mũi xe hướng lên), ánh sáng bầu trời bán cầu,
bóng mềm (mẹo SDF), che khuất môi trường (AO), khuếch tán Lambert + phản xạ
GGX có Fresnel, lớp sơn bóng (clear-coat) phản chiếu bầu trời, kính tối màu có
vệt trời phản chiếu và nhìn xuyên thấy ghế bên trong, crôm cho gương / ống xả,
lốp cao su mờ, áo vải, mũ bảo hiểm bóng. Vẽ to gấp [SS] lần rồi thu nhỏ cho
mép mịn, xuất PNG RGBA nền trong. Bóng đổ xuống đường do game tự vẽ nên không
nướng vào ảnh.

Giữ nguyên tên file, kích thước ảnh, hướng (mũi xe lên trên) và vị trí xe
trong khung như hình cũ của build_vehicles.py / build_trip_events.py /
build_roadside.py nên không phải sửa code Dart. Chỉ ghi đè hình xe của người
chơi:
    img_scooter_player.png          xe số (kiểu Wave / Dream) có người lái
    img_scooter_player_raincoat.png người lái trùm áo mưa cánh dơi
    img_scooter_parked.png          xe dựng chân chống, mũ để trên yên
    img_sedan_red.png               sedan đỏ Tết (Img.imgCarPlayer)
    img_bus_player.png              xe khách đỏ

build_vehicles.py, build_trip_events.py và build_roadside.py cũng ghi các file
trên (bản vẽ phẳng cũ) nên nếu chạy lại chúng thì chạy script này sau cùng.
Dòng xe AI dựng bằng build_traffic_3d.py (dùng lại các hàm ở đây).
Ngoài ra script này ghi thêm bóng đổ theo hình xe (xem SHADOWS bên dưới):
    img_shadow_scooter_player.png, img_shadow_scooter_player_raincoat.png,
    img_shadow_scooter_parked.png, img_shadow_car_player.png,
    img_shadow_bus_player.png

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_vehicles_3d.py            # tất cả
    python tool/asset_pipeline/build_vehicles_3d.py car bus    # chọn vài xe
    python tool/asset_pipeline/build_vehicles_3d.py --out DIR  # xuất ra chỗ khác
"""
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np
from PIL import Image

OUT = 'assets/images'
SS = 4  # số mẫu mỗi chiều trên một điểm ảnh

# Nắng: cùng hướng với LIGHT trong build_vehicles.py (x sang phải ảnh, y xuống
# đuôi xe, z hướng lên trời).
SUN = np.array([-0.42, -0.58, 0.70])
SUN /= np.linalg.norm(SUN)
SUN_COL = np.array([1.0, 0.95, 0.88]) * 2.9
SKY_ZENITH = np.array([0.24, 0.40, 0.78])
SKY_HORIZON = np.array([0.78, 0.84, 0.92])
GROUND_COL = np.array([0.10, 0.10, 0.095])
SKY_IRR = np.array([0.52, 0.62, 0.82]) * 0.95
GROUND_IRR = np.array([0.30, 0.28, 0.25]) * 0.55
EXPOSURE = 0.62


def lin(rgb):
    """Màu sRGB 0..255 → tuyến tính."""
    return (np.asarray(rgb, np.float64) / 255.0) ** 2.2


# =============================================================== Hàm SDF
def length2(a, b):
    return np.sqrt(a * a + b * b)


def length3(a, b, c):
    return np.sqrt(a * a + b * b + c * c)


def smin(a, b, k):
    """Hợp mềm (đa thức bậc hai): luôn ≤ min(a, b) nên an toàn khi dò tia."""
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def sphere(p, c, r):
    x, y, z = p
    return length3(x - c[0], y - c[1], z - c[2]) - r


def ellipsoid(p, c, r):
    x, y, z = p
    px, py, pz = (x - c[0]) / r[0], (y - c[1]) / r[1], (z - c[2]) / r[2]
    k0 = np.sqrt(px * px + py * py + pz * pz)
    k1 = np.sqrt((px / r[0]) ** 2 + (py / r[1]) ** 2 + (pz / r[2]) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def rbox(p, c, b, r):
    """Hộp bo tròn: tâm [c], nửa cạnh [b] (đã gồm bo), bán kính bo [r]."""
    x, y, z = p
    qx = np.abs(x - c[0]) - b[0] + r
    qy = np.abs(y - c[1]) - b[1] + r
    qz = np.abs(z - c[2]) - b[2] + r
    out = length3(np.maximum(qx, 0), np.maximum(qy, 0), np.maximum(qz, 0))
    return out + np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0) - r


def capsule(p, a, b, r):
    x, y, z = p
    pax, pay, paz = x - a[0], y - a[1], z - a[2]
    bax, bay, baz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    h = np.clip((pax * bax + pay * bay + paz * baz) / (bax * bax + bay * bay + baz * baz), 0, 1)
    return length3(pax - bax * h, pay - bay * h, paz - baz * h) - r


def round_cone(p, a, b, r1, r2):
    """Viên nang thon (bán kính r1 ở a, r2 ở b) — tay, chân, ống."""
    x, y, z = p
    bax, bay, baz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    l2 = bax * bax + bay * bay + baz * baz
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pax, pay, paz = x - a[0], y - a[1], z - a[2]
    yy = pax * bax + pay * bay + paz * baz
    zz = yy - l2
    qx, qy, qz = pax * l2 - bax * yy, pay * l2 - bay * yy, paz * l2 - baz * yy
    x2 = qx * qx + qy * qy + qz * qz
    y2 = yy * yy * l2
    z2 = zz * zz * l2
    k = np.sign(rr) * rr * rr * x2
    d_mid = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + yy * rr) * il2 - r1
    d_b = np.sqrt(x2 + z2) * il2 - r2
    d_a = np.sqrt(x2 + y2) * il2 - r1
    return np.where(np.sign(zz) * a2 * z2 > k, d_b, np.where(np.sign(yy) * a2 * y2 < k, d_a, d_mid))


def tyre(p, c, r_out, thick, half_w, rr):
    """Lốp: xuyến có tiết diện hộp bo tròn, trục quay theo chiều ngang x."""
    x, y, z = p
    q1 = length2(y - c[1], z - c[2]) - (r_out - thick / 2)
    ax = np.abs(q1) - thick / 2 + rr
    bx = np.abs(x - c[0]) - half_w + rr
    return length2(np.maximum(ax, 0), np.maximum(bx, 0)) + np.minimum(np.maximum(ax, bx), 0) - rr


def arc_shell(p, c, radius, thick, half_w, rr):
    """Vỏ cong ôm bánh xe (chắn bùn): vành khuyên tiết diện hộp, trục x."""
    x, y, z = p
    q1 = length2(y - c[1], z - c[2]) - radius
    ax = np.abs(q1) - thick + rr
    bx = np.abs(x - c[0]) - half_w + rr
    return length2(np.maximum(ax, 0), np.maximum(bx, 0)) + np.minimum(np.maximum(ax, bx), 0) - rr


def rot(a, b, ang):
    """Quay cặp toạ độ (a, b) một góc [ang]."""
    c, s = math.cos(ang), math.sin(ang)
    return a * c - b * s, a * s + b * c


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def vnoise(x, y, seed=0):
    """Nhiễu giá trị mượt 2D (xác định, không dùng bộ sinh ngẫu nhiên)."""
    xi, yi = np.floor(x), np.floor(y)
    xf, yf = x - xi, y - yi

    def h(i, j):
        n = np.sin((i * 127.1 + j * 311.7 + seed * 74.7)) * 43758.5453
        return n - np.floor(n)

    u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    a, b = h(xi, yi), h(xi + 1, yi)
    c, d = h(xi, yi + 1), h(xi + 1, yi + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


def fbm(x, y, seed=0, octaves=4):
    s, amp, f = 0.0, 0.5, 1.0
    for i in range(octaves):
        s = s + amp * vnoise(x * f, y * f, seed + i * 13)
        amp *= 0.5
        f *= 2.03
    return s


# ============================================================= Vật liệu
class Mat:
    """Vật liệu: [rough] độ nhám, [metal] kim loại, [coat] lớp bóng phủ,
    [sheen] ánh vải, [wrap] độ tản sáng mềm (da, vải), [glass] kính tối."""

    def __init__(self, rgb, rough=0.5, metal=0.0, coat=0.0, sheen=0.0, wrap=0.0, glass=0.0, spec=0.5, emit=0.0, clear=0.0):
        self.albedo = lin(rgb)
        self.rough, self.metal, self.coat, self.sheen = rough, metal, coat, sheen
        self.wrap, self.glass, self.spec, self.emit, self.clear = wrap, glass, spec, emit, clear


MAT_FIELDS = ('rough', 'metal', 'coat', 'sheen', 'wrap', 'glass', 'spec', 'emit', 'clear')


def mat_arrays(mats, idx, n):
    """Ghép mảng thuộc tính vật liệu theo chỉ số [idx] (mỗi điểm một vật liệu)."""
    out = {'albedo': np.zeros((n, 3))}
    for f in MAT_FIELDS:
        out[f] = np.zeros(n)
    for k, m in enumerate(mats):
        sel = idx == k
        if not sel.any():
            continue
        out['albedo'][sel] = m.albedo
        for f in MAT_FIELDS:
            out[f][sel] = getattr(m, f)
    return out


class Obj:
    """Một bộ phận: [sdf](p) → khoảng cách (mét); [mats] danh sách vật liệu;
    [pick](p, n) → chỉ số vật liệu mỗi điểm (mặc định 0); [tint](p, n, alb)
    → chỉnh màu (hoạ tiết, bẩn); [cast] có đổ bóng không."""

    def __init__(self, name, sdf, mats, pick=None, tint=None, cast=True, bump=None):
        self.name, self.sdf = name, sdf
        self.mats = mats if isinstance(mats, (list, tuple)) else [mats]
        self.pick, self.tint, self.cast, self.bump = pick, tint, cast, bump
        self.lo = self.hi = None


class Scene:
    def __init__(self, objs, bounds, ppm, origin, size, ao_scale=1.0, interior=None, glass_tint=(0.30, 0.33, 0.36)):
        """[bounds] ((x0,y0,z0),(x1,y1,z1)) mét; [ppm] điểm ảnh/mét; [origin]
        toạ độ ảnh (px) của gốc toạ độ mét; [size] (w, h) ảnh."""
        self.objs = objs
        self.bounds = np.array(bounds, np.float64)
        self.ppm, self.origin, self.size = ppm, origin, size
        self.ao_scale = ao_scale
        self.interior = interior  # danh sách Obj nhìn thấy sau kính
        self.glass_tint = np.array(glass_tint)
        self._fit_boxes(self.objs)
        if interior:
            self._fit_boxes(interior)

    def _fit_boxes(self, objs):
        """Hộp bao từng bộ phận: lấy mẫu lưới thô, giữ chỗ SDF gần 0."""
        (x0, y0, z0), (x1, y1, z1) = self.bounds
        h = 0.012 if (x1 - x0) < 1.5 else 0.025
        xs = np.arange(x0, x1 + h, h)
        ys = np.arange(y0, y1 + h, h)
        zs = np.arange(z0, z1 + h, h)
        gx, gy, gz = np.meshgrid(xs, ys, zs, indexing='ij')
        gx, gy, gz = gx.ravel(), gy.ravel(), gz.ravel()
        for o in objs:
            d = o.sdf((gx, gy, gz))
            m = d < h * 1.6
            if not m.any():
                o.lo = np.array([1e9] * 3)
                o.hi = np.array([-1e9] * 3)
                continue
            pad = h * 1.8
            o.lo = np.array([gx[m].min(), gy[m].min(), gz[m].min()]) - pad
            o.hi = np.array([gx[m].max(), gy[m].max(), gz[m].max()]) + pad

    def eval(self, p, objs=None, cap=0.08, want_id=False, cast_only=False, ground=False):
        objs = self.objs if objs is None else objs
        x, y, z = p
        n = x.shape[0]
        d = np.full(n, cap)
        oid = np.full(n, -1, np.int32) if want_id else None
        for i, o in enumerate(objs):
            if cast_only and not o.cast:
                continue
            bd = np.maximum(np.maximum(o.lo[0] - x, x - o.hi[0]), np.maximum(o.lo[1] - y, y - o.hi[1]))
            bd = np.maximum(bd, np.maximum(o.lo[2] - z, z - o.hi[2]))
            idx = np.flatnonzero(bd < d)
            if idx.size == 0:
                continue
            if idx.size == n:
                di = o.sdf(p)
                better = di < d
                d = np.where(better, di, d)
                if want_id:
                    oid[better] = i
            else:
                di = o.sdf((x[idx], y[idx], z[idx]))
                better = di < d[idx]
                sel = idx[better]
                d[sel] = di[better]
                if want_id:
                    oid[sel] = i
        if ground:
            d = np.minimum(d, z)
        return (d, oid) if want_id else d


# ============================================================ Dò tia
def march_down(scene, x, y, ztop, objs=None, eps=None):
    """Tia thẳng đứng từ [ztop] đi xuống. Trả về (trúng?, z, id bộ phận)."""
    objs = scene.objs if objs is None else objs
    eps = eps if eps is not None else 0.25 / (scene.ppm * SS)
    n = x.shape[0]
    z = ztop.copy()
    hit = np.zeros(n, bool)
    alive = np.arange(n)
    for _ in range(400):
        if alive.size == 0:
            break
        pa = (x[alive], y[alive], z[alive])
        d = scene.eval(pa, objs)
        got = d < eps
        hit[alive[got]] = True
        za = z[alive] - np.maximum(d * 0.8, eps * 0.6)
        z[alive] = np.where(got, z[alive], za)
        gone = za < -0.02
        alive = alive[~got & ~gone]
    # tinh chỉnh: kéo điểm trúng về đúng mặt (đề phòng vượt quá do hợp mềm)
    hi = np.flatnonzero(hit)
    for _ in range(4):
        if hi.size == 0:
            break
        d = scene.eval((x[hi], y[hi], z[hi]), objs)
        z[hi] -= d * 0.9
    oid = np.full(n, -1, np.int32)
    if hi.size:
        _, o = scene.eval((x[hi], y[hi], z[hi]), objs, want_id=True)
        oid[hi] = o
    return hit, z, oid


def normals(objs, oid, p, h):
    x, y, z = p
    n = x.shape[0]
    nx, ny, nz = np.zeros(n), np.zeros(n), np.ones(n)
    for i, o in enumerate(objs):
        sel = np.flatnonzero(oid == i)
        if sel.size == 0:
            continue
        xs, ys, zs = x[sel], y[sel], z[sel]
        # bốn điểm tứ diện
        k = ((1, -1, -1), (-1, -1, 1), (-1, 1, -1), (1, 1, 1))
        gx = gy = gz = 0
        for a, b, c in k:
            dv = o.sdf((xs + a * h, ys + b * h, zs + c * h))
            gx = gx + a * dv
            gy = gy + b * dv
            gz = gz + c * dv
        ln = np.maximum(length3(gx, gy, gz), 1e-12)
        nx[sel], ny[sel], nz[sel] = gx / ln, gy / ln, gz / ln
        if o.bump is not None:
            bx, by, bz = o.bump((xs, ys, zs), (nx[sel], ny[sel], nz[sel]))
            ln = np.maximum(length3(bx, by, bz), 1e-12)
            nx[sel], ny[sel], nz[sel] = bx / ln, by / ln, bz / ln
    return nx, ny, nz


def soft_shadow(scene, p, nrm, objs=None, k=10.0, tmax=2.5):
    objs = scene.objs if objs is None else objs
    x, y, z = p
    n = x.shape[0]
    res = np.ones(n)
    bias = 1.2 / (scene.ppm * SS)
    t = np.full(n, bias * 2)
    ox = x + nrm[0] * bias
    oy = y + nrm[1] * bias
    oz = z + nrm[2] * bias
    alive = np.arange(n)
    for _ in range(90):
        if alive.size == 0:
            break
        ta = t[alive]
        q = (ox[alive] + SUN[0] * ta, oy[alive] + SUN[1] * ta, oz[alive] + SUN[2] * ta)
        h = scene.eval(q, objs, cap=0.25, cast_only=True)
        r = np.minimum(res[alive], k * h / ta)
        res[alive] = r
        t[alive] = ta + np.clip(h, 0.004, 0.12)
        keep = (r > 0.002) & (t[alive] < tmax) & (q[2] < scene.bounds[1][2] + 0.05)
        alive = alive[keep]
    res = np.clip(res, 0, 1)
    return res * res * (3 - 2 * res)


def ambient_occ(scene, p, nrm, objs=None):
    objs = scene.objs if objs is None else objs
    x, y, z = p
    occ = np.zeros(x.shape[0])
    sca = 1.0
    s = scene.ao_scale
    for i in range(1, 6):
        hd = s * (0.006 + 0.022 * i)
        d = scene.eval((x + nrm[0] * hd, y + nrm[1] * hd, z + nrm[2] * hd), objs, cap=0.5, ground=True)
        occ += (hd - d) * sca
        sca *= 0.72
    return np.clip(1.0 - 2.6 * occ / s / 0.1, 0.0, 1.0)


# ============================================================ Môi trường
def env(rx, ry, rz, rough):
    """Bầu trời phản chiếu (không gồm mặt trời): trời xanh đậm ở đỉnh, sáng ở
    chân trời, dải cây / nhà tối ở chân trời, mặt đường nhựa phía dưới, vài
    đám mây mờ."""
    el = rz
    t = smoothstep(0.0, 0.75, np.maximum(el, 0)) ** 0.7
    sky = SKY_HORIZON[None, :] * (1 - t[:, None]) + SKY_ZENITH[None, :] * t[:, None]
    # mây: chiếu hướng lên mặt phẳng trời
    w = np.maximum(el, 0.08)
    cu, cv = rx / w * 1.3, ry / w * 1.3
    cl = fbm(cu + 3.1, cv - 1.7, seed=5, octaves=4)
    cl = smoothstep(0.50, 0.80, cl) * (1 - rough) * smoothstep(0.02, 0.25, el)
    sky = sky * (1 - 0.7 * cl[:, None]) + np.array([2.2, 2.2, 2.25])[None, :] * 0.7 * cl[:, None]
    # hàng cây, mái nhà ở chân trời: cao thấp theo phương vị
    az = np.arctan2(ry, rx)
    top = 0.03 + 0.22 * fbm(az * 2.2 + 7.0, np.full_like(az, 1.3), seed=9, octaves=4) ** 1.8
    soft_t = 0.015 + rough * 0.25
    band = smoothstep(top + soft_t, top - soft_t, el) * smoothstep(-0.05, 0.0, el)
    tree = np.array([0.07, 0.09, 0.07]) * (0.7 + 0.6 * fbm(az * 18, el * 18, seed=4, octaves=3))[:, None]
    sky = sky * (1 - band[:, None]) + tree * band[:, None]
    # quầng sáng quanh mặt trời
    cs = np.clip(rx * SUN[0] + ry * SUN[1] + rz * SUN[2], 0, 1)
    sky = sky + np.array([1.0, 0.97, 0.9])[None, :] * (1.6 * cs ** 10 + 0.5 * cs ** 3)[:, None] * (1 - 0.6 * rough)[:, None]
    ground = GROUND_COL[None, :] * (1.0 + 0.6 * smoothstep(-0.25, 0.0, el))[:, None]
    soft = 0.03 + rough * 0.35
    m = smoothstep(-soft, soft, el)[:, None]
    out = ground * (1 - m) + sky * m
    # nhám thì phản chiếu nhoè về màu trung bình
    avg = SKY_IRR[None, :] * 0.9 * (0.5 + 0.5 * el)[:, None] + GROUND_IRR[None, :] * (0.5 - 0.5 * el)[:, None]
    r2 = np.clip(rough * 1.3, 0, 1)[:, None]
    return out * (1 - r2) + avg * r2


# ============================================================== Đổ sáng
def ggx_spec(nx, ny, nz, rough, f0):
    """Phản xạ nắng GGX (đã nhân NdotL), người nhìn ở +z."""
    hx, hy, hz = SUN[0], SUN[1], SUN[2] + 1.0
    hl = math.sqrt(hx * hx + hy * hy + hz * hz)
    hx, hy, hz = hx / hl, hy / hl, hz / hl
    nh = np.clip(nx * hx + ny * hy + nz * hz, 0, 1)
    nl = np.clip(nx * SUN[0] + ny * SUN[1] + nz * SUN[2], 0, 1)
    nv = np.clip(nz, 1e-3, 1)
    a = np.maximum(rough * rough, 0.002)
    a2 = a * a
    dd = a2 / (math.pi * (nh * nh * (a2 - 1) + 1) ** 2)
    kk = a / 2
    vis = 1.0 / ((nl * (1 - kk) + kk) * (nv * (1 - kk) + kk))
    vh = hz  # v·h với v = (0,0,1)
    f = f0 + (1 - f0) * (1 - vh) ** 5
    return dd * vis * 0.25 * f * nl


def shade(scene, p, nrm, ma, shadow, ao):
    nx, ny, nz = nrm
    alb = ma['albedo']
    rough, metal, coat, sheen = ma['rough'], ma['metal'], ma['coat'], ma['sheen']
    wrap, spec = ma['wrap'], ma['spec']
    nl_raw = nx * SUN[0] + ny * SUN[1] + nz * SUN[2]
    nl = np.clip((nl_raw + wrap) / (1 + wrap), 0, 1)
    nv = np.clip(nz, 0, 1)
    sun = SUN_COL[None, :] * (nl * shadow)[:, None]
    hemi = 0.5 + 0.5 * nz
    amb = (SKY_IRR[None, :] * hemi[:, None] + GROUND_IRR[None, :] * (1 - hemi)[:, None]) * ao[:, None]
    # khuếch tán
    diff = alb * (sun + amb) * (1 - metal)[:, None]
    # phản xạ gương lớp nền
    f0 = (0.08 * spec)[:, None] * (1 - metal)[:, None] + alb * metal[:, None]
    rx, ry, rz = 2 * nz * nx, 2 * nz * ny, 2 * nz * nz - 1
    e = env(rx, ry, rz, rough)
    fres = (1 - nv) ** 5
    fr = f0 + (np.maximum(1 - rough, f0.mean(1))[:, None] - f0) * fres[:, None]
    spec_occ = np.clip(ao * 1.15 - 0.1, 0, 1) * (0.35 + 0.65 * shadow)
    spec_env = fr * e * spec_occ[:, None]
    spec_sun = SUN_COL[None, :] * (ggx_spec(nx, ny, nz, np.maximum(rough, 0.04), 1.0)[:, None] * f0) * shadow[:, None]
    base = diff + spec_env + spec_sun
    # ánh vải ở mép
    base = base + alb * (sheen * (1 - nv) ** 2.5 * 0.9)[:, None] * (SKY_IRR[None, :] * ao[:, None] + sun * 0.4)
    # lớp sơn bóng
    if np.any(coat > 0):
        fc = 0.04 + 0.96 * fres
        ce = env(rx, ry, rz, np.full_like(rough, 0.02))
        cs = SUN_COL[None, :] * ggx_spec(nx, ny, nz, np.full_like(rough, 0.11), 0.04)[:, None] * shadow[:, None]
        cl = ce * fc[:, None] * spec_occ[:, None] + cs
        base = base * (1 - (coat * fc)[:, None]) + cl * coat[:, None]
    base = base + alb * ma['emit'][:, None]
    return base


def tonemap(c):
    c = c * EXPOSURE
    a, b, cc, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    t = np.clip((c * (a * c + b)) / (c * (cc * c + d) + e), 0, 1)
    return t ** (1 / 2.2)


# ============================================================== Vẽ ảnh
def shade_hits(scene, objs, x, y, z, oid, glass_pass=True):
    """Tô màu các điểm trúng. Trả về (rgb tuyến tính, alpha phủ)."""
    n = x.shape[0]
    h = 0.35 / (scene.ppm * SS)
    p = (x, y, z)
    nrm = normals(objs, oid, p, h)
    # vật liệu
    ma = {'albedo': np.zeros((n, 3))}
    for f in MAT_FIELDS:
        ma[f] = np.zeros(n)
    for i, o in enumerate(objs):
        sel = np.flatnonzero(oid == i)
        if sel.size == 0:
            continue
        ps = (x[sel], y[sel], z[sel])
        ns = (nrm[0][sel], nrm[1][sel], nrm[2][sel])
        idx = o.pick(ps, ns) if o.pick else np.zeros(sel.size, np.int32)
        sub = mat_arrays(o.mats, idx, sel.size)
        if o.tint is not None:
            sub['albedo'] = o.tint(ps, ns, sub['albedo'], idx)
        for k, v in sub.items():
            ma[k][sel] = v
    sh = soft_shadow(scene, p, nrm, objs)
    ao = ambient_occ(scene, p, nrm, objs)
    col = shade(scene, p, nrm, ma, sh, ao)
    # nhựa trong (áo mưa): đục hơn khi nhìn xiên
    alpha = 1 - ma['clear'] * np.clip(nrm[2], 0, 1) ** 0.7
    g = np.flatnonzero(ma['glass'] > 0)
    if g.size and glass_pass:
        col[g] = glass_color(scene, (x[g], y[g], z[g]), (nrm[0][g], nrm[1][g], nrm[2][g]), ma['glass'][g], sh[g], ao[g])
    return col, alpha, ma


def glass_color(scene, p, nrm, amount, shadow, ao):
    """Kính tối màu: phản chiếu trời theo Fresnel + nội thất mờ phía sau."""
    x, y, z = p
    nx, ny, nz = nrm
    nv = np.clip(nz, 0, 1)
    rx, ry, rz = 2 * nz * nx, 2 * nz * ny, 2 * nz * nz - 1
    fres = 0.07 + 0.93 * (1 - nv) ** 4
    refl = env(rx, ry, rz, np.full_like(x, 0.03)) * fres[:, None] * 1.5
    refl += SUN_COL[None, :] * ggx_spec(nx, ny, nz, np.full_like(x, 0.05), 0.05)[:, None] * shadow[:, None]
    inside = np.zeros((x.shape[0], 3)) + lin((20, 22, 25))
    if scene.interior:
        ztop = z - 0.004
        hit, zi, oi = march_down(scene, x, y, ztop, objs=scene.interior)
        hi = np.flatnonzero(hit)
        if hi.size:
            ci, _, _ = shade_hits(scene, scene.interior, x[hi], y[hi], zi[hi], oi[hi], glass_pass=False)
            # ánh sáng trong xe yếu hơn: trần xe che bớt
            inside[hi] = ci * 0.42
    trans = scene.glass_tint[None, :] * (1 - fres)[:, None]
    return refl + inside * trans


_SCENE = None  # cảnh đang vẽ (các tiến trình con kế thừa qua fork)


def render_rows(args):
    r0, r1 = args
    scene = _SCENE
    w, h = scene.size
    W = w * SS
    ys = (np.arange(r0, r1) + 0.5) / SS
    xs = (np.arange(W) + 0.5) / SS
    px, py = np.meshgrid(xs, ys)
    px, py = px.ravel(), py.ravel()
    x = (px - scene.origin[0]) / scene.ppm
    y = (py - scene.origin[1]) / scene.ppm
    n = x.shape[0]
    rgb = np.zeros((n, 3))
    alpha = np.zeros(n)
    depth = np.full(n, -1.0)
    # mỗi cột tia chỉ bắt đầu từ nóc của các bộ phận có hộp bao chứa nó
    ztop = np.full(n, -1.0)
    for o in scene.objs:
        inside = (x >= o.lo[0]) & (x <= o.hi[0]) & (y >= o.lo[1]) & (y <= o.hi[1])
        ztop = np.where(inside, np.maximum(ztop, o.hi[2]), ztop)
    cand = np.flatnonzero(ztop > 0)
    if cand.size:
        hit, z, oid = march_down(scene, x[cand], y[cand], ztop[cand] + 0.01)
        hc = cand[hit]
        if hc.size:
            col, a, _ = shade_hits(scene, scene.objs, x[hc], y[hc], z[hit], oid[hit])
            rgb[hc] = col
            alpha[hc] = a
            depth[hc] = z[hit]
    return rgb.reshape(r1 - r0, W, 3), alpha.reshape(r1 - r0, W), depth.reshape(r1 - r0, W)


def render(scene, procs=8):
    global _SCENE
    _SCENE = scene
    w, h = scene.size
    H = h * SS
    chunk = max(SS * 2, (H // (procs * 3)) // SS * SS)
    jobs = [(r, min(H, r + chunk)) for r in range(0, H, chunk)]
    if procs > 1:
        with mp.get_context('fork').Pool(procs) as pool:
            parts = pool.map(render_rows, jobs)
    else:
        parts = [render_rows(j) for j in jobs]
    rgb = np.concatenate([p[0] for p in parts], 0)
    alpha = np.concatenate([p[1] for p in parts], 0)
    depth = np.concatenate([p[2] for p in parts], 0)
    return rgb, alpha, depth


def finish(rgb, alpha, w, h, post=None):
    """Tone-map, thu nhỏ (trộn trước theo alpha) → ảnh PIL RGBA."""
    col = tonemap(rgb)
    if post is not None:
        col = post(col)
    pre = col * alpha[..., None]
    H, W = alpha.shape
    pre = pre.reshape(h, SS, w, SS, 3).mean((1, 3))
    a = alpha.reshape(h, SS, w, SS).mean((1, 3))
    rgb8 = np.where(a[..., None] > 1e-4, pre / np.maximum(a[..., None], 1e-4), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(rgb8 * 255 + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


# ================================================================ Xe máy
# Toạ độ mét: x sang phải, y từ trục bánh trước về đuôi xe, z lên trời.
# Kiểu Honda Wave: dài 1,91 m, rộng 0,71 m, trục cách trục 1,22 m.
BIKE_PPM = 73.0
BIKE_ORIGIN = (32.0, 25.2)  # trục bánh trước nằm ở (32, 25.2) px
BIKE_SIZE = (64, 150)
REAR_AXLE = 1.224
WHEEL_R = 0.29

RUBBER = Mat((30, 30, 32), rough=0.78, spec=0.35)
BLACK_PLASTIC = Mat((28, 29, 31), rough=0.5, spec=0.5)
SATIN_BLACK = Mat((22, 22, 24), rough=0.32, spec=0.6)
DARK_METAL = Mat((46, 47, 50), rough=0.38, metal=0.7)
CHROME = Mat((225, 226, 230), rough=0.12, metal=1.0)
ALU = Mat((170, 172, 176), rough=0.3, metal=1.0)
SEAT_VINYL = Mat((30, 29, 30), rough=0.3, spec=0.8)
TAIL_LENS = Mat((190, 18, 22), rough=0.06, spec=1.2, coat=0.8, emit=0.15)
AMBER_LENS = Mat((235, 130, 20), rough=0.08, spec=1.2, coat=0.8)
CLEAR_LENS = Mat((205, 210, 215), rough=0.05, metal=0.6, coat=1.0)
SMOKE_GLASS = Mat((14, 16, 18), rough=0.05, spec=1.0, coat=1.0)
SKIN = Mat((204, 152, 112), rough=0.55, wrap=0.35, spec=0.4)


def paint(rgb, rough=0.32, metal=0.55):
    """Sơn xe ánh kim: lớp màu có vảy kim loại (sáng bừng khi nghiêng về phía
    nắng, sẫm khi nhìn xiên) dưới lớp phủ trong bóng loáng."""
    return Mat(rgb, rough=rough, coat=1.0, spec=0.12, metal=metal)


def fabric(rgb, rough=0.85, sheen=0.5):
    return Mat(rgb, rough=rough, sheen=sheen, wrap=0.25, spec=0.3)


def mirror_x(fn):
    """Bộ phận đối xứng hai bên: tính với |x|."""
    return lambda p: fn((np.abs(p[0]), p[1], p[2]))


def fabric_bump(scale, amp, seed):
    """Nếp nhăn vải: nghiêng pháp tuyến theo nếp gợn mượt (bước sóng vài cm)."""
    def fold(x, y, z):
        u = (x * 0.6 + y + z * 0.5) * scale
        w = fbm(x * scale * 0.5, (y + z) * scale * 0.5, seed, 3)
        return np.abs(np.sin(u + 4.0 * w)) * 0.7 + 0.3 * w

    def bump(p, n):
        x, y, z = p
        e = 0.003
        f0 = fold(x, y, z)
        fx = (fold(x + e, y, z) - f0) / e
        fy = (fold(x, y + e, z) - f0) / e
        fz = (fold(x, y, z + e) - f0) / e
        # chỉ lấy phần gradient tiếp tuyến với mặt
        dn = fx * n[0] + fy * n[1] + fz * n[2]
        return n[0] - amp * (fx - dn * n[0]), n[1] - amp * (fy - dn * n[1]), n[2] - amp * (fz - dn * n[2])
    return bump


def bike_parts(body, black_body=None, kickstand=False):
    """Thân xe số kiểu Wave, chưa có người."""
    pt = paint(body)
    trim = black_body or BLACK_PLASTIC
    parts = []
    ax_r = REAR_AXLE

    # Bánh xe
    parts.append(Obj('tyre_f', lambda p: tyre(p, (0, 0, WHEEL_R), WHEEL_R, 0.075, 0.040, 0.026), RUBBER))
    parts.append(Obj('tyre_r', lambda p: tyre(p, (0, ax_r, WHEEL_R), WHEEL_R, 0.082, 0.046, 0.029), RUBBER))

    # Phuộc trước (hai ống) lấp ló hai bên chắn bùn
    parts.append(Obj('fork', mirror_x(lambda p: capsule(p, (0.066, 0.0, WHEEL_R), (0.066, 0.25, 0.86), 0.017)),
                     [ALU, SATIN_BLACK], pick=lambda p, n: (p[2] > 0.55).astype(np.int32)))

    # Chắn bùn trước
    def fender_f(p):
        x, y, z = p
        # thon dần về mũi, mặt trên vồng tròn
        hw = 0.056 - 0.03 * np.clip(-y / 0.25, 0, 1)
        r = length2(y, z - WHEEL_R)
        q1 = r - 0.336 + 0.022 * (1 - (x / 0.058) ** 2).clip(0, 1) ** 0.5
        d = smax(np.abs(q1) - 0.009, np.abs(x) - hw, 0.012)
        d = smax(d, 0.535 - z, 0.03)
        return smax(d, y - 0.15, 0.02)
    parts.append(Obj('fender_f', fender_f, pt))

    # Đầu đèn (ốp ghi-đông): đèn pha phía trước, đồng hồ phía sau.
    def cowl(p):
        x, y, z = p
        a = ellipsoid(p, (0, 0.27, 0.975), (0.122, 0.14, 0.08))
        b = ellipsoid(p, (0, 0.16, 0.95), (0.095, 0.08, 0.07))
        c = ellipsoid(p, (0, 0.31, 0.93), (0.10, 0.09, 0.07))
        return smin(smin(a, b, 0.06), c, 0.04)

    def cowl_pick(p, n):
        x, y, z = p
        lens = (y < 0.19) & (z > 0.905) & (np.abs(x) < 0.08) & (n[1] < -0.6)
        gauge = ((x / 0.056) ** 2 + ((y - 0.318) / 0.042) ** 4 < 1) & (n[2] > 0.5)
        low = z < 0.915
        return np.where(lens, 1, np.where(gauge, 2, np.where(low, 3, 0))).astype(np.int32)
    parts.append(Obj('cowl', cowl, [pt, CLEAR_LENS, SMOKE_GLASS, trim], pick=cowl_pick))

    # Ghi-đông, tay nắm, tay phanh, gương chiếu hậu
    def bar(p):
        d = capsule(p, (-0.2, 0.33, 0.985), (0.2, 0.33, 0.985), 0.011)
        g = mirror_x(lambda q: capsule(q, (0.19, 0.33, 0.988), (0.312, 0.337, 0.993), 0.0195))(p)
        return np.minimum(d, g)
    parts.append(Obj('grips', bar, [RUBBER, ALU], pick=lambda p, n: ((np.abs(p[0]) < 0.17) | (np.abs(p[0]) > 0.31)).astype(np.int32)))
    parts.append(Obj('levers', mirror_x(lambda p: capsule(p, (0.165, 0.30, 1.005), (0.30, 0.28, 1.0), 0.0065)), ALU))

    def mirrors(p):
        stalk = capsule(p, (0.16, 0.315, 1.0), (0.265, 0.20, 1.20), 0.0075)
        x, y, z = p
        xr, yr = rot(x - 0.30, y - 0.175, -0.35)
        head = ellipsoid((xr, yr, z), (0, 0, 1.225), (0.068, 0.034, 0.042))
        return np.minimum(stalk, head)
    parts.append(Obj('mirrors', mirror_x(mirrors), [SATIN_BLACK, CHROME],
                     pick=lambda p, n: ((p[2] < 1.17) & (p[2] > 1.02)).astype(np.int32)))

    # Yếm trước + ốp chắn chân (cong ôm hai chân)
    def front_body(p):
        x, y, z = p
        apron = ellipsoid(p, (0, 0.34, 0.62), (0.13, 0.12, 0.28))
        yb = y - 0.44 + 1.5 * x * x
        shield = rbox((x, yb, z), (0, 0, 0.655), (0.205, 0.034, 0.235), 0.03)
        lower = ellipsoid(p, (0, 0.44, 0.40), (0.12, 0.17, 0.14))
        return smin(smin(apron, shield, 0.07), lower, 0.06)
    parts.append(Obj('front_body', front_body, [pt, trim],
                     pick=lambda p, n: ((p[2] < 0.47) | ((p[1] > 0.44 + 0.012 - 1.5 * p[0] ** 2) & (n[1] > 0.2))).astype(np.int32)))

    # Sàn để chân (cao su gân) + ống sống giữa
    def floor(p):
        f = rbox(p, (0, 0.60, 0.305), (0.152, 0.15, 0.024), 0.018)
        t = ellipsoid(p, (0, 0.62, 0.38), (0.072, 0.21, 0.10))
        return smin(f, t, 0.03)
    parts.append(Obj('floor', floor, [RUBBER, pt], pick=lambda p, n: (p[2] > 0.34).astype(np.int32),
                     bump=lambda p, n: (n[0], n[1] + 0.25 * np.sin(p[1] * 260) * (p[2] < 0.34), n[2])))

    # Lốc máy dưới sàn
    parts.append(Obj('engine', lambda p: smin(ellipsoid(p, (0.0, 0.78, 0.25), (0.168, 0.19, 0.13)),
                                              ellipsoid(p, (-0.07, 0.70, 0.22), (0.10, 0.13, 0.11)), 0.04),
                     [DARK_METAL, ALU], pick=lambda p, n: (p[0] < -0.12).astype(np.int32)))

    # Thân sau (ốp sườn dưới yên)
    def rear_body(p):
        a = ellipsoid(p, (0, 1.12, 0.565), (0.162, 0.46, 0.185))
        b = ellipsoid(p, (0, 1.47, 0.60), (0.108, 0.18, 0.12))
        c = ellipsoid(p, (0, 0.78, 0.55), (0.118, 0.13, 0.13))
        return smin(smin(a, b, 0.08), c, 0.06)

    parts.append(Obj('rear_body', rear_body, pt))

    # Yên xe: phẳng trên, bo tròn mép, thon hai đầu
    def seat(p):
        x, y, z = p
        xs = x * (1 + 0.55 * ((y - 1.0) / 0.40) ** 2)
        zs = z - 0.03 * (y - 0.62)
        return rbox((xs, y, zs), (0, 1.0, 0.738), (0.128, 0.39, 0.052), 0.045)
    parts.append(Obj('seat', seat, SEAT_VINYL))

    # Tay dắt sau + baga
    def rack(p):
        x, y, z = p
        side = mirror_x(lambda q: capsule(q, (0.112, 1.20, 0.74), (0.112, 1.50, 0.752), 0.0105))(p)
        back = capsule(p, (-0.112, 1.54, 0.752), (0.112, 1.54, 0.752), 0.0105)
        corner = mirror_x(lambda q: capsule(q, (0.112, 1.50, 0.752), (0.08, 1.54, 0.752), 0.0105))(p)
        plate = rbox(p, (0, 1.47, 0.766), (0.085, 0.065, 0.007), 0.005)
        bars = np.minimum(np.minimum(side, back), corner)
        return np.minimum(bars, plate)
    parts.append(Obj('rack', rack, DARK_METAL))

    # Đèn hậu + xi-nhan sau
    parts.append(Obj('taillight', lambda p: ellipsoid(p, (0, 1.585, 0.605), (0.085, 0.048, 0.05)), TAIL_LENS))
    parts.append(Obj('blink_r', mirror_x(lambda p: ellipsoid(p, (0.118, 1.575, 0.59), (0.036, 0.03, 0.028))), AMBER_LENS))
    parts.append(Obj('blink_f', mirror_x(lambda p: ellipsoid(p, (0.10, 0.285, 0.84), (0.03, 0.035, 0.026))), AMBER_LENS))

    # Chắn bùn sau + biển số
    def fender_r(p):
        d = arc_shell(p, (0, ax_r, WHEEL_R), 0.33, 0.01, 0.052, 0.008)
        d = smax(d, 1.38 - p[1], 0.02)
        d = smax(d, 0.27 - p[2], 0.02)
        y2, z2 = rot(p[1] - 1.655, p[2] - 0.43, 0.3)
        plate = rbox((p[0], y2, z2), (0, 0, 0), (0.088, 0.005, 0.058), 0.004)
        return np.minimum(d, plate)
    parts.append(Obj('fender_r', fender_r, [BLACK_PLASTIC, Mat((225, 225, 220), rough=0.4)],
                     pick=lambda p, n: (p[1] > 1.63).astype(np.int32)))

    # Ống xả bên phải: ống đen, ốp chống nóng crôm
    def exhaust(p):
        pipe = round_cone(p, (0.09, 0.60, 0.20), (0.165, 0.95, 0.27), 0.02, 0.028)
        muff = round_cone(p, (0.16, 0.93, 0.26), (0.172, 1.43, 0.31), 0.044, 0.034)
        return smin(pipe, muff, 0.03)
    parts.append(Obj('exhaust', exhaust, [SATIN_BLACK, CHROME],
                     pick=lambda p, n: (((p[1] > 0.98) & (p[1] < 1.24) & (n[0] > -0.3)) | (p[1] > 1.43)).astype(np.int32)))


    if kickstand:
        parts.append(Obj('stand', lambda p: capsule(p, (-0.10, 0.92, 0.24), (-0.26, 0.99, 0.02), 0.011), DARK_METAL))
    return parts


class Blend(Obj):
    """Một khối liền hoà trộn mềm từ nhiều phần, mỗi phần một vật liệu (vật
    liệu ở mỗi điểm theo phần gần nhất) — không có nếp gãy giữa các phần."""

    def __init__(self, name, comps, mats, k, bump=None, tint=None):
        self.comps, self.k = comps, k

        def sdf(p):
            d = None
            for fn, _ in comps:
                v = fn(p)
                d = v if d is None else smin(d, v, k)
            return d

        def pick(p, n):
            best = None
            idx = None
            for fn, mi in comps:
                v = fn(p)
                if best is None:
                    best, idx = v, np.full(v.shape, mi, np.int32)
                else:
                    m = v < best
                    best = np.where(m, v, best)
                    idx = np.where(m, mi, idx)
            return idx
        super().__init__(name, sdf, mats, pick=pick, bump=bump, tint=tint)


# Tư thế người lái (mét, cùng hệ toạ độ xe).
HIP = (0.0, 0.80, 0.86)
SHOULDER = (0.158, 0.675, 1.295)
ELBOW = (0.252, 0.505, 1.115)
WRIST = (0.272, 0.375, 1.025)
KNEE = (0.168, 0.495, 0.725)
HEAD = (0.0, 0.615, 1.535)


def helmet_parts(color, center, yaw=0.0):
    """Mũ bảo hiểm nửa đầu: vỏ bóng, tem trắng, lỗ thông gió, viền đen, lưỡi
    trai kính khói phía trước. [yaw] xoay quanh trục đứng."""
    cx, cy, cz = center

    def local(p):
        x, y, z = p
        u, v = rot(x - cx, y - cy, -yaw)
        return u, v, z - cz

    def shell(p):
        u, v, w = local(p)
        d = ellipsoid((u, v, w), (0, 0, 0), (0.130, 0.148, 0.122))
        return smax(d, -0.082 - w, 0.03)

    def shell_pick(p, n):
        u, v, w = local(p)
        rim = w < -0.066
        vent = (np.abs(np.abs(u) - 0.03) < 0.0065) & (v > -0.105) & (v < -0.07) & (n[2] > 0.6)
        return np.where(rim | vent, 1, 0).astype(np.int32)

    def shell_tint(p, n, alb, idx):
        u, v, w = local(p)
        st = (np.abs(np.abs(u) - 0.072 + 0.06 * v) < 0.005) & (v > -0.04) & (v < 0.12) & (idx == 0)
        return np.where(st[:, None], lin((236, 236, 232)), alb)

    def visor(p):
        u, v, w = local(p)
        y2, z2 = rot(v + 0.135, w + 0.05, -0.22)
        d = ellipsoid((u, y2, z2), (0, 0, 0), (0.104, 0.068, 0.015))
        return smax(d, v + 0.09, 0.01)
    return [Obj('helmet', shell, [Mat(color, rough=0.22, coat=1.0, spec=0.5), Mat((22, 22, 24), rough=0.5)],
                pick=shell_pick, tint=shell_tint),
            Obj('visor', visor, SMOKE_GLASS)]


def rider_parts(helmet, jacket, pants, skin=SKIN):
    """Người lái ngồi trên xe: mũ nửa đầu, áo chống nắng, tay vươn tới
    ghi-đông, gối kẹp hai bên sàn xe."""
    jk = fabric(jacket)
    pn = fabric(pants, rough=0.8, sheen=0.3)
    parts = []
    hx, hy, hz = HEAD

    parts += helmet_parts(helmet, HEAD)

    sx, sy, sz = SHOULDER
    ex, ey, ez = ELBOW
    wx, wy, wz = WRIST
    kx, ky, kz = KNEE
    px_, py_, pz_ = HIP

    def torso(p):
        x, y, z = p
        q = (x / 1.55, y, z)
        return round_cone(q, (0, py_ + 0.035, pz_ + 0.03), (0, sy + 0.035, sz - 0.07), 0.118, 0.118)

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
        sh = round_cone(q, (kx, ky - 0.005, kz - 0.02), (kx - 0.03, ky - 0.035, 0.37), 0.055, 0.04)
        return smin(th, sh, 0.03)

    parts.append(Blend('rider', [(torso, 0), (shoulders, 0), (hood, 0), (arms, 0), (neck, 2), (hips, 0), (legs, 1)],
                       [jk, pn, skin], 0.045, bump=fabric_bump(70, 0.0016, 7)))

    def hands(p):
        palm = ellipsoid(p, (0.27, 0.338, 1.005), (0.043, 0.052, 0.030))
        thumb = capsule(p, (0.245, 0.355, 1.0), (0.236, 0.322, 0.99), 0.012)
        return smin(palm, thumb, 0.01)
    parts.append(Obj('hands', mirror_x(hands), skin))
    parts.append(Obj('shoes', mirror_x(lambda p: ellipsoid(p, (kx - 0.035, ky - 0.03, 0.345), (0.046, 0.11, 0.04))),
                     Mat((40, 38, 36), rough=0.6)))
    return parts


def bike_scene(parts):
    return Scene(parts, ((-0.44, -0.33, 0.0), (0.44, 1.76, 1.72)), BIKE_PPM, BIKE_ORIGIN, BIKE_SIZE, ao_scale=0.55)


PLAYER_BODY = (206, 26, 32)
PLAYER_HELMET = (220, 30, 34)
PLAYER_JACKET = (246, 194, 36)
PLAYER_PANTS = (44, 56, 88)


def build_scooter_player(out):
    sc = bike_scene(bike_parts(PLAYER_BODY) + rider_parts(PLAYER_HELMET, PLAYER_JACKET, PLAYER_PANTS))
    return save(sc, out, 'img_scooter_player')


def field_bump(field, amp):
    """Gợn bề mặt theo trường vô hướng field(x, y, z) (nếp áo mưa, nếp vải)."""
    def bump(p, n):
        x, y, z = p
        e = 0.003
        f0 = field(x, y, z)
        fx = (field(x + e, y, z) - f0) / e
        fy = (field(x, y + e, z) - f0) / e
        fz = (field(x, y, z + e) - f0) / e
        dn = fx * n[0] + fy * n[1] + fz * n[2]
        return n[0] - amp * (fx - dn * n[0]), n[1] - amp * (fy - dn * n[1]), n[2] - amp * (fz - dn * n[2])
    return bump


def raincoat_obj(color):
    """Áo mưa cánh dơi: tấm nilon trùm vai, hai tay, phủ cả đầu xe; cổ áo
    ôm quanh mũ bảo hiểm. Nếp nhăn toả ra từ cổ."""
    sx, sy, sz = SHOULDER
    wx, wy, wz = WRIST

    def hull(p):
        x, y, z = p
        q = (np.abs(x), y, z)
        torso = round_cone((x / 1.5, y, z), (0, HIP[1] + 0.06, HIP[2] + 0.02), (0, sy + 0.03, sz - 0.07), 0.14, 0.135)
        sh = capsule(p, (-sx, sy, sz - 0.01), (sx, sy, sz - 0.01), 0.094)
        arm = round_cone(q, (sx + 0.01, sy, sz - 0.02), (wx, wy, wz + 0.005), 0.08, 0.066)
        hands = ellipsoid(q, (0.275, 0.335, 1.0), (0.085, 0.085, 0.07))
        front = ellipsoid(p, (0, 0.25, 0.95), (0.20, 0.20, 0.10))
        web = ellipsoid(p, (0, 0.56, 1.08), (0.33, 0.30, 0.11))
        d = smin(torso, sh, 0.08)
        d = smin(d, arm, 0.10)
        d = smin(d, web, 0.12)
        d = smin(d, hands, 0.07)
        d = smin(d, front, 0.13)
        return smax(d, 0.78 - z, 0.04)

    def folds(x, y, z):
        ang = np.arctan2(y - (HEAD[1] + 0.02), x)
        r = length2(x, y - HEAD[1])
        w = fbm(x * 9, y * 9, 21, 3)
        return np.sin(ang * 11 + w * 5.0) * smoothstep(0.12, 0.3, r) + 0.6 * np.sin(r * 38 + w * 4)
    plastic = Mat(color, rough=0.12, coat=1.0, spec=0.6, clear=0.5)
    return Obj('raincoat', hull, plastic, bump=field_bump(folds, 0.0035))


def build_scooter_raincoat(out):
    t0 = time.time()
    under = zoomed(bike_scene(bike_parts(PLAYER_BODY) + rider_parts(PLAYER_HELMET, PLAYER_JACKET, PLAYER_PANTS)))
    rgb_u, a_u, z_u = render(under)
    coat_color = (70, 150, 230)
    coat = zoomed(bike_scene([raincoat_obj(coat_color)]))
    rgb_c, a_c, z_c = render(coat)
    # áo trùm lên mọi thứ trừ mũ bảo hiểm (cao hơn cổ áo)
    on = (a_c > 0) & (z_c > z_u)
    ac = np.where(on, a_c, 0.0)
    # ánh sáng xuyên qua nilon bị nhuộm màu áo
    tint = 0.3 + 0.7 * lin(coat_color) / lin(coat_color).max()
    alpha = ac + a_u * (1 - ac)
    pre = rgb_c * ac[..., None] + rgb_u * a_u[..., None] * (1 - ac)[..., None] * np.where(on[..., None], tint, 1.0)
    rgb = pre / np.maximum(alpha, 1e-6)[..., None]
    img = save(under, out, 'img_scooter_player_raincoat', layers=(rgb, alpha))
    print(f'  (tổng {time.time() - t0:.1f}s)')
    return img


def build_scooter_parked(out):
    """Xe dựng chân chống, mũ bảo hiểm để trên yên (người lái xuống xe)."""
    parts = bike_parts(PLAYER_BODY, kickstand=True) + helmet_parts(PLAYER_HELMET, (0.0, 0.93, 0.872), yaw=0.35)
    return save(bike_scene(parts), out, 'img_scooter_parked')


# ================================================================== Ô tô
# Sedan cỡ C (kiểu Vios / Mazda3): dài 4,45 m, rộng 1,82 m, cao 1,45 m. Toạ
# độ mét: x sang phải, y từ cản trước về đuôi, z lên trời. Thân xe dựng như
# bản vẽ ba hình chiếu: bề rộng theo chiều dài (nhìn từ trên), độ cao nắp
# ca-pô / nóc / cốp theo chiều dài (nhìn ngang), thân thu dần lên trên.
CAR_PPM = 47.0
CAR_ORIGIN = (49.0, 2.4)
CAR_SIZE = (98, 214)
CAR_L = 4.45


def spline(ctrl, n=900):
    """Catmull-Rom qua các điểm (t, v) → bảng dày (ts, vs, dv/dt)."""
    P = np.array(ctrl, np.float64)
    pts = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1:i + 3]
        for s in np.linspace(0, 1, 60, endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * s ** 3))
    out.append(P[-1])
    out = np.array(out)
    ts = np.linspace(P[0, 0], P[-1, 0], n)
    vs = np.interp(ts, out[:, 0], out[:, 1])
    return ts, vs, np.gradient(vs, ts)


class Curve:
    def __init__(self, ctrl):
        self.t, self.v, self.dv = spline(ctrl)

    def __call__(self, q):
        return np.interp(q, self.t, self.v)

    def d(self, q):
        return np.interp(q, self.t, self.dv)


# bề rộng nửa thân (nhìn từ trên): hông nở ở hai hốc bánh
CAR_W = Curve([(-0.2, 0.80), (0.0, 0.82), (0.25, 0.865), (0.92, 0.905), (1.5, 0.893), (2.3, 0.885),
               (3.0, 0.893), (3.55, 0.91), (4.1, 0.888), (4.45, 0.86), (4.7, 0.84)])
# mặt trên thân dưới: cản trước → ca-pô → hõm kính lái → (dưới kính) → cốp → cản sau
CAR_H = Curve([(-0.2, 0.55), (0.0, 0.60), (0.12, 0.70), (0.4, 0.775), (0.8, 0.83), (1.2, 0.872),
               (1.32, 0.885), (1.42, 0.90), (2.5, 0.93), (3.5, 0.965), (3.8, 1.0), (4.1, 1.015), (4.33, 0.98),
               (4.45, 0.87), (4.6, 0.6)])
# nóc: chân kính lái → nóc → kính hậu → cốp
CAR_ROOF = Curve([(1.0, 0.60), (1.36, 0.93), (1.70, 1.16), (1.98, 1.335), (2.22, 1.425), (2.6, 1.455),
                  (2.95, 1.445), (3.2, 1.38), (3.47, 1.225), (3.78, 1.03), (4.1, 0.75)])
# bề rộng nửa khoang kính ở ngang đường gân hông
CAR_WG = Curve([(1.1, 0.60), (1.36, 0.685), (1.8, 0.748), (2.5, 0.768), (3.2, 0.758), (3.78, 0.70), (4.1, 0.62)])
CAR_BELT = 0.975
TUMBLE = 0.40
CAR_FRONT = 0.0
CAR_REAR = CAR_L


def car_lower(p):
    x, y, z = p
    ax = np.abs(x)
    bul = 1 - 0.06 * ((z - 0.58) / 0.36) ** 2
    w = CAR_W(y) * bul
    d_side = (ax - w) / np.sqrt(1 + CAR_W.d(y) ** 2)
    # mặt trước / sau cong vào ở hai góc
    yf = CAR_FRONT + 0.20 * (ax / 0.9) ** 2.4
    yr = CAR_REAR - 0.15 * (ax / 0.9) ** 2.4
    d_front = (yf - y) / np.sqrt(1 + (0.48 * (ax / 0.9) ** 1.4 / 0.9) ** 2)
    d_rear = (y - yr) / np.sqrt(1 + (0.36 * (ax / 0.9) ** 1.4 / 0.9) ** 2)
    plan = smax(smax(d_side, d_front, 0.42), d_rear, 0.34)
    crown = 0.10 * (ax / 0.85) ** 2
    # hai gân nổi dọc nắp ca-pô
    hood_t = np.clip((1.30 - y) / 0.3, 0, 1) * np.clip((y - 0.25) / 0.25, 0, 1)
    crease = 0.014 * np.exp(-((ax - 0.42) / 0.05) ** 2) * hood_t
    hy = CAR_H.d(y)
    d_top = (z - CAR_H(y) + crown - crease) / np.sqrt(1 + hy * hy + (0.22 * ax / 0.72) ** 2)
    body = smax(plan, d_top, 0.21)
    return smax(body, 0.20 - z, 0.05)


def car_green(p):
    x, y, z = p
    ax = np.abs(x)
    wg = CAR_WG(y) - TUMBLE * (z - CAR_BELT)
    d_side = (ax - wg) / np.sqrt(1 + TUMBLE ** 2)
    ry = CAR_ROOF.d(y)
    crown = 0.06 * (ax / 0.6) ** 2
    d_top = (z - CAR_ROOF(y) + crown) / np.sqrt(1 + ry * ry + (0.2 * ax / 0.6) ** 2)
    g = smax(d_side, d_top, 0.13)
    return smax(g, 0.80 - z, 0.02)


def car_body(p):
    return smin(car_lower(p), car_green(p), 0.035)


def _in_rrect(x, y, cx, cy, hl, hw, ang, r):
    """Khoảng cách 2D tới hình chữ nhật bo góc đã xoay (âm = bên trong)."""
    u, v = rot(x - cx, y - cy, -ang)
    qx, qy = np.abs(u) - hl + r, np.abs(v) - hw + r
    return length2(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


CAR_PAINT_I, CAR_GLASS_I, CAR_FRIT_I, CAR_TRIM_I, CAR_HEAD_I, CAR_HEADIN_I, CAR_DRL_I, CAR_TAIL_I, CAR_TAILIN_I, CAR_CHROME_I = range(10)


def car_pick(p, n):
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    idx = np.full(x.shape, CAR_PAINT_I, np.int32)
    wg = CAR_WG(y) - TUMBLE * (z - CAR_BELT)
    zr = CAR_ROOF(y)
    above = z > CAR_BELT + 0.012 + 0.03 * (y - 1.4) / 2.4
    # kính lái
    ws = above & (y < 2.24) & (ax < wg - 0.07) & (ny < -0.15)
    ws_in = ws & (ax < wg - 0.10) & (y < 2.19) & (z > CAR_BELT + 0.035)
    # kính hậu
    rw = above & (y > 3.13) & (ax < wg - 0.115) & (ny > 0.15)
    rw_in = rw & (ax < wg - 0.145) & (y > 3.18) & (z > CAR_BELT + 0.06)
    # kính sườn (thấy được vì thân thu vào phía nóc)
    ya = 1.47 + (z - CAR_BELT) * 1.70
    yc = 3.50 - (z - CAR_BELT) * 1.0
    sw = above & (np.abs(nx) > 0.5) & (z < zr - 0.075) & (y > ya) & (y < yc)
    bpil = sw & (np.abs(y - 2.52) < 0.045)
    sw_in = sw & ~bpil & (z < zr - 0.095) & (z > CAR_BELT + 0.04) & (y > ya + 0.03) & (y < yc - 0.03)
    idx[ws | rw | sw] = CAR_FRIT_I
    idx[ws_in | rw_in | sw_in] = CAR_GLASS_I
    idx[bpil] = CAR_FRIT_I
    # hõm kính lái (ốp nhựa đen, cần gạt)
    cowl = (y > 1.315) & (y < 1.40) & (z < 0.97) & (nz > 0.3) & (ax < 0.70)
    idx[cowl] = CAR_TRIM_I
    # đèn pha vuốt về hai góc
    hd = _in_rrect(ax, y, 0.635, 0.20, 0.23, 0.062, 0.42, 0.04)
    head = (hd < 0) & (z > 0.45)
    idx[head] = CAR_HEAD_I
    idx[head & (_in_rrect(ax, y, 0.60, 0.19, 0.14, 0.034, 0.42, 0.03) < 0)] = CAR_HEADIN_I
    idx[head & (np.abs(hd + 0.012) < 0.009) & (rot(ax - 0.635, y - 0.20, -0.42)[1] < 0)] = CAR_DRL_I
    # lưới tản nhiệt + logo
    grille = (ax < 0.46) & (y < 0.085 + 0.1 * (ax / 0.46) ** 2) & (ny < -0.25) & (z > 0.30)
    idx[grille] = CAR_TRIM_I
    idx[grille & (length2(x, (z - 0.55) * 1.0) < 0.045)] = CAR_CHROME_I
    # đèn hậu ôm góc
    td = _in_rrect(ax, y, 0.67, 4.30, 0.22, 0.062, -0.36, 0.035)
    tail = (td < 0) & (z > 0.55)
    idx[tail] = CAR_TAIL_I
    idx[tail & (td > -0.008)] = CAR_TAILIN_I
    idx[tail & (np.abs(td + 0.03) < 0.006)] = CAR_TAILIN_I
    # nẹp crôm cốp sau
    idx[(ax < 0.42) & (np.abs(y - 4.405) < 0.012) & (z > 0.8)] = CAR_CHROME_I
    return idx


def car_tint(p, n, alb, idx):
    """Khe nắp ca-pô, nắp cốp (đường ron sơn mảnh)."""
    x, y, z = p
    ax = np.abs(x)
    paint = idx == CAR_PAINT_I
    hood_side = np.abs(ax - (0.70 - 0.10 * np.clip((1.30 - y) / 1.0, 0, 1))) < 0.0065
    hood_line = (hood_side & (y > 0.30) & (y < 1.30)) | ((np.abs(y - 1.30) < 0.0065) & (ax < 0.70))
    hood_line |= (np.abs(y - (0.31 + 0.09 * (ax / 0.6) ** 2)) < 0.0075) & (ax < 0.60) & (z > 0.7)
    trunk = ((np.abs(ax - 0.665) < 0.0065) & (y > 3.83) & (y < 4.40)) | ((np.abs(y - 3.83) < 0.0065) & (ax < 0.665))
    line = paint & (hood_line | trunk)
    return np.where(line[:, None], alb * 0.45, alb)


def car_mirror(p):
    x, y, z = p
    q = (np.abs(x), y, z)
    yq, zq = q[1], q[2]
    head = ellipsoid((q[0], yq + 0.25 * (q[0] - 0.96), zq), (0.965, 1.56, 0.985), (0.105, 0.07, 0.06))
    stalk = rbox(q, (0.86, 1.555, 0.95), (0.06, 0.045, 0.03), 0.02)
    return smin(head, stalk, 0.03)


def car_wipers(p):
    """Hai cần gạt nước nằm sát chân kính lái."""
    x, y, z = p
    out = None
    for (x0, y0), (x1, y1) in (((-0.62, 1.47), (0.02, 1.43)), ((0.06, 1.46), (0.60, 1.50))):
        zs0 = CAR_ROOF(np.array([y0]))[0] + 0.012
        zs1 = CAR_ROOF(np.array([y1]))[0] + 0.012
        d = capsule(p, (x0, y0, zs0), (x1, y1, zs1), 0.009)
        out = d if out is None else np.minimum(out, d)
    return out


def car_parts(color):
    pt = paint(color)
    mats = [pt,
            Mat((10, 11, 12), rough=0.03, glass=1.0, spec=1.0),          # kính
            Mat((12, 12, 13), rough=0.12, spec=1.0, coat=0.8),           # viền gốm đen quanh kính
            Mat((20, 21, 22), rough=0.45, spec=0.5),                     # nhựa đen
            Mat((190, 196, 202), rough=0.04, metal=0.75, coat=1.0),      # mặt đèn pha
            Mat((26, 28, 32), rough=0.15, metal=0.5, coat=1.0),          # hốc đèn trong
            Mat((240, 244, 250), rough=0.05, coat=1.0, emit=0.6),        # dải LED ban ngày
            Mat((215, 30, 30), rough=0.05, spec=1.2, coat=1.0, emit=0.35),
            Mat((40, 6, 8), rough=0.05, spec=1.2, coat=1.0),
            CHROME]
    parts = [Obj('body', car_body, mats, pick=car_pick, tint=car_tint),
             Obj('mirrors', car_mirror, [pt, Mat((20, 21, 22), rough=0.45)],
                 pick=lambda p, n: (p[2] < 0.955).astype(np.int32)),
             Obj('wipers', car_wipers, Mat((16, 16, 18), rough=0.4)),
             Obj('antenna', lambda p: ellipsoid(p, (0, 3.02, 1.435), (0.026, 0.085, 0.036)),
                 Mat((14, 14, 16), rough=0.15, spec=0.8, coat=1.0))]
    return parts


def car_interior(shirt=(92, 104, 122), skin=SKIN):
    """Nội thất thấy qua kính: táp-lô, vô-lăng (tay lái bên trái), ghế, người lái."""
    seat = Mat((44, 42, 42), rough=0.6, sheen=0.3, wrap=0.2)
    dash = Mat((34, 34, 36), rough=0.55)
    sh = fabric(shirt)
    objs = []
    objs.append(Obj('floor', lambda p: rbox(p, (0, 2.6, 0.35), (0.78, 1.3, 0.05), 0.04), Mat((40, 40, 42), rough=0.9)))

    def dashboard(p):
        a = rbox(p, (0, 1.56, 0.80), (0.80, 0.22, 0.13), 0.08)
        hood = ellipsoid(p, (-0.37, 1.71, 0.92), (0.17, 0.09, 0.06))
        return smin(a, hood, 0.04)
    objs.append(Obj('dash', dashboard, dash))

    def wheel_(p):
        x, y, z = p
        y2, z2 = rot(y - 1.86, z - 0.86, -1.05)
        q1 = length2(x + 0.37, y2) - 0.175
        return length2(q1, z2) - 0.016
    objs.append(Obj('wheel', wheel_, Mat((24, 24, 26), rough=0.4)))
    objs.append(Obj('console', lambda p: rbox(p, (0, 2.23, 0.60), (0.10, 0.45, 0.10), 0.04), dash))

    def seats(p):
        x, y, z = p
        q = (np.abs(x) - 0.37, y, z)
        cush = rbox(q, (0, 2.46, 0.55), (0.25, 0.26, 0.07), 0.06)
        yb, zb = rot(y - 2.78, z - 0.85, -0.22)
        back = rbox((q[0], yb, zb), (0, 0, 0), (0.25, 0.065, 0.30), 0.06)
        head = rbox(q, (0, 2.88, 1.22), (0.13, 0.06, 0.10), 0.05)
        rear = rbox(p, (0, 3.33, 0.55), (0.70, 0.24, 0.08), 0.07)
        yb2, zb2 = rot(y - 3.60, z - 0.82, -0.25)
        rback = rbox((x, yb2, zb2), (0, 0, 0), (0.70, 0.06, 0.27), 0.06)
        rhead = rbox((np.abs(x) - 0.45, y, z), (0, 3.70, 1.12), (0.12, 0.05, 0.08), 0.04)
        shelf = rbox(p, (0, 3.83, 0.97), (0.70, 0.17, 0.02), 0.02)
        d = np.minimum(np.minimum(np.minimum(cush, back), head), np.minimum(rear, rback))
        return np.minimum(np.minimum(d, rhead), shelf)
    objs.append(Obj('seats', seats, seat))

    def driver(p):
        x, y, z = p
        q = (x + 0.37, y, z)
        torso = round_cone((q[0] / 1.5, q[1], q[2]), (0, 2.66, 0.68), (0, 2.70, 1.12), 0.12, 0.12)
        sh_ = capsule(q, (-0.19, 2.68, 1.18), (0.19, 2.68, 1.18), 0.06)
        arm = mirror_x(lambda r: smin(round_cone(r, (0.20, 2.66, 1.15), (0.24, 2.33, 0.92), 0.05, 0.042),
                                      round_cone(r, (0.24, 2.33, 0.92), (0.17, 1.96, 0.98), 0.042, 0.035), 0.02))(q)
        thighs = mirror_x(lambda r: round_cone(r, (0.10, 2.58, 0.66), (0.12, 2.13, 0.66), 0.08, 0.065))(q)
        return smin(smin(smin(torso, sh_, 0.06), arm, 0.03), thighs, 0.03)

    def driver_pick(p, n):
        return (p[2] < 0.75).astype(np.int32)
    objs.append(Obj('driver', driver, [sh, fabric((50, 56, 70))], pick=driver_pick))
    objs.append(Obj('head', lambda p: ellipsoid(p, (-0.37, 2.64, 1.33), (0.08, 0.10, 0.11)), Mat((26, 22, 20), rough=0.5, sheen=0.5)))
    objs.append(Obj('hands', mirror_x(lambda p: ellipsoid((p[0], p[1], p[2]), (0.17, 2.16, 0.99), (0.035, 0.045, 0.025))),
                    skin))
    # tay người lái chỉ ở bên trái: dời hai bàn tay vào vô-lăng
    objs[-1].sdf = lambda p: np.minimum(ellipsoid(p, (-0.54, 1.94, 0.98), (0.035, 0.045, 0.025)),
                                        ellipsoid(p, (-0.20, 1.94, 0.98), (0.035, 0.045, 0.025)))
    return objs


def car_scene(color):
    sc = Scene(car_parts(color), ((-1.12, -0.06, 0.15), (1.12, 4.52, 1.52)), CAR_PPM, CAR_ORIGIN, CAR_SIZE,
               ao_scale=1.6, interior=car_interior(), glass_tint=(0.36, 0.39, 0.42))
    return sc


def build_car_player(out):
    return save(car_scene((168, 9, 17)), out, 'img_sedan_red')


# ============================================================== Xe khách
# Xe khách đường dài kiểu Thaco / Universe: nóc trắng đỏ, dàn lạnh trên nóc,
# hai cửa thoát hiểm, kính lái lớn, gương "tai thỏ" vươn ra trước. Tỉ lệ theo
# khung hình cũ của game (66 × 214 px): dài 8,5 m, rộng 2,5 m.
BUS_PPM = 24.0
BUS_ORIGIN = (33.0, 7.0)
BUS_SIZE = (66, 214)
BUS_L = 8.5
BUS_W = 1.25

BUS_H = Curve([(-0.3, 0.3), (0.0, 0.5), (0.04, 1.0), (0.18, 2.1), (0.34, 2.85), (0.52, 3.12), (0.8, 3.27),
               (1.3, 3.32), (7.9, 3.32), (8.25, 3.25), (8.42, 3.0), (8.5, 2.4), (8.7, 1.0)])


def bus_body(p):
    x, y, z = p
    ax = np.abs(x)
    d_side = ax - BUS_W
    d_front = -y
    d_rear = y - BUS_L
    plan = smax(smax(d_side, d_front, 0.55), d_rear, 0.45)
    hy = BUS_H.d(y)
    crown = 0.05 * (ax / BUS_W) ** 2
    d_top = (z - BUS_H(y) + crown) / np.sqrt(1 + hy * hy)
    body = smax(plan, d_top, 0.34)
    return smax(body, 0.35 - z, 0.05)


BUS_PAINT_I, BUS_GLASS_I, BUS_FRIT_I, BUS_STRIPE_I, BUS_WHITE_I, BUS_LAMP_I, BUS_RLAMP_I = range(7)


def bus_pick(p, n):
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    idx = np.full(x.shape, BUS_PAINT_I, np.int32)
    # kính lái: mặt trước, uốn lên một chút phần nóc
    ws = (ny < -0.25) & (z > 1.05) & (z < 3.16) & (ax < BUS_W - 0.10)
    idx[ws] = BUS_FRIT_I
    idx[ws & (z > 1.12) & (z < 3.08) & (ax < BUS_W - 0.16) & (np.abs(x) > 0.03)] = BUS_GLASS_I
    # kính hậu trên phần đuôi cong
    rw = (y > 8.12) & (ny > 0.25) & (z > 2.1) & (z < 3.24) & (ax < BUS_W - 0.12)
    idx[rw] = BUS_FRIT_I
    idx[rw & (z > 2.2) & (z < 3.17) & (ax < BUS_W - 0.18)] = BUS_GLASS_I
    # mặt nóc, sọc vàng chạy dọc mép
    top = (nz > 0.5) & (y > 0.75) & (y < 8.15)
    idx[top & (ax > 0.97) & (ax < 1.06)] = BUS_STRIPE_I
    # đèn hông nóc: vàng phía trước, đỏ phía sau
    idx[(ax > 1.13) & (np.abs(y - 0.95) < 0.07) & (z > 3.0)] = BUS_LAMP_I
    idx[(ax > 1.13) & (np.abs(y - 8.0) < 0.07) & (z > 3.0)] = BUS_RLAMP_I
    idx[(np.abs(np.abs(x) - 0.25) < 0.06) & (np.abs(y - 8.05) < 0.035) & (nz > 0.6)] = BUS_RLAMP_I
    idx[(np.abs(x) < 0.06) & (np.abs(y - 8.05) < 0.035) & (nz > 0.6)] = BUS_RLAMP_I
    return idx


def bus_tint(p, n, alb, idx):
    """Gờ máng nước, đường ghép tấm nóc."""
    x, y, z = p
    ax = np.abs(x)
    nz = n[2]
    seam = (idx == BUS_PAINT_I) & (nz > 0.9) & (np.abs(((y - 0.9) % 1.2) - 0.6) > 0.588)
    gutter = (np.abs(ax - 1.13) < 0.012) & (y > 0.9) & (y < 8.1)
    k = np.where(seam, 0.86, 1.0) * np.where(gutter, 0.55, 1.0)
    return alb * k[:, None]


def ac_unit(p):
    """Vỏ dàn lạnh trên nóc: hộp dẹt bo tròn, mũi vát."""
    x, y, z = p
    zb = 3.31
    hgt = 0.17 - 0.10 * np.clip((2.0 - y) / 0.4, 0, 1) ** 2
    d_top = (z - zb - hgt) / 1.1
    d_plan = rbox((x, y, np.zeros_like(z)), (0, 2.95, 0), (0.70, 1.20, 1.0), 0.28)
    d = smax(d_plan, d_top, 0.07)
    # hai quạt dàn nóng khoét lõm
    fans = np.minimum(length2(x - 0.34, y - 3.62), length2(x + 0.34, y - 3.62)) - 0.21
    dish = smax(fans, zb + hgt - 0.045 - z, 0.02)
    return smax(d, -dish, 0.02)


def ac_pick(p, n):
    x, y, z = p
    r = np.minimum(length2(x - 0.34, y - 3.62), length2(x + 0.34, y - 3.62))
    grille = r < 0.225
    louver = (y > 2.0) & (y < 2.75) & (np.abs(x) < 0.48) & (n[2] > 0.8)
    idx = np.zeros(x.shape, np.int32)
    idx[louver] = 1
    idx[grille] = 2
    return idx


def ac_tint(p, n, alb, idx):
    x, y, z = p
    # khe lá gió, nan lưới + cánh quạt
    louv = (idx == 1) & (np.abs(((y - 2.0) % 0.075) - 0.0375) < 0.012)
    ang = np.arctan2(y - 3.62, np.abs(x) - 0.34)
    r = np.minimum(length2(x - 0.34, y - 3.62), length2(x + 0.34, y - 3.62))
    rings = (idx == 2) & ((np.abs((r % 0.05) - 0.025) < 0.005) | (r < 0.06))
    blades = (idx == 2) & (np.sin(ang * 5 + r * 9) > 0.55) & (r < 0.19)
    k = np.where(louv, 0.45, 1.0) * np.where(rings, 1.6, 1.0) * np.where(blades, 0.55, 1.0)
    return alb * k[:, None]


def bus_hatches(p):
    x, y, z = p
    out = None
    for yc in (5.25, 6.9):
        d = rbox(p, (0, yc, 3.33), (0.40, 0.38, 0.055), 0.04)
        out = d if out is None else np.minimum(out, d)
    return out


def bus_hatch_pick(p, n):
    x, y, z = p
    inner = (np.abs(x) < 0.32) & ((np.abs(y - 5.25) < 0.30) | (np.abs(y - 6.9) < 0.30)) & (n[2] > 0.9)
    return inner.astype(np.int32)


def bus_mirrors(p):
    """Gương tai thỏ: cần cong vươn ra trước, mặt gương buông xuống."""
    q = (np.abs(p[0]), p[1], p[2])
    a = capsule(q, (1.12, 0.45, 2.75), (1.27, 0.10, 2.90), 0.045)
    b = capsule(q, (1.27, 0.10, 2.90), (1.285, -0.16, 2.66), 0.045)
    head = rbox(q, (1.27, -0.20, 2.25), (0.10, 0.085, 0.32), 0.05)
    return np.minimum(smin(a, b, 0.05), head)


def bus_wipers(p):
    out = None
    for x0, x1 in ((-1.05, -0.10), (0.10, 1.05)):
        d = capsule(p, (x0, 0.07, 1.2), (x1, 0.11, 1.75), 0.022)
        out = d if out is None else np.minimum(out, d)
    return out


def bus_interior():
    dash = Mat((40, 40, 42), rough=0.6)
    return [Obj('dash', lambda p: rbox(p, (0, 0.55, 0.95), (1.15, 0.45, 0.25), 0.1), dash),
            Obj('seat', lambda p: rbox(p, (-0.70, 1.55, 1.1), (0.28, 0.3, 0.4), 0.12), Mat((60, 50, 44), rough=0.7)),
            Obj('floor', lambda p: rbox(p, (0, 2.0, 0.6), (1.2, 1.9, 0.05), 0.04), Mat((50, 50, 52), rough=0.9))]


def bus_scene(main, stripe, metal=0.55):
    pt = paint(main, metal=metal)
    mats = [pt,
            Mat((10, 11, 12), rough=0.03, glass=1.0, spec=1.0),
            Mat((12, 12, 13), rough=0.12, spec=1.0, coat=0.8),
            paint(stripe),
            paint((236, 236, 232), rough=0.5),
            Mat((250, 160, 30), rough=0.05, coat=1.0, emit=0.3),
            Mat((210, 30, 26), rough=0.05, coat=1.0, emit=0.3)]
    acw = Mat((176, 180, 184), rough=0.55, coat=0.25, spec=0.3)
    parts = [Obj('body', bus_body, mats, pick=bus_pick, tint=bus_tint),
             Obj('ac', ac_unit, [acw, Mat((150, 154, 158), rough=0.5), Mat((40, 42, 44), rough=0.5, metal=0.3)],
                 pick=ac_pick, tint=ac_tint),
             Obj('hatches', bus_hatches, [Mat((200, 202, 204), rough=0.4), Mat((70, 76, 82), rough=0.15, coat=1.0)],
                 pick=bus_hatch_pick),
             Obj('mirrors', bus_mirrors, Mat((22, 22, 24), rough=0.35, spec=0.6)),
             Obj('wipers', bus_wipers, Mat((16, 16, 18), rough=0.4))]
    return Scene(parts, ((-1.42, -0.35, 0.3), (1.42, 8.75, 3.62)), BUS_PPM, BUS_ORIGIN, BUS_SIZE,
                 ao_scale=2.4, interior=bus_interior(), glass_tint=(0.4, 0.43, 0.46))


def build_bus_player(out):
    return save(bus_scene((196, 22, 28), (246, 190, 48)), out, 'img_bus_player')


# ================================================================ Chung
ZOOM = 1  # >1: ảnh xem thử phóng to (không dùng cho game)


def zoomed(scene):
    if ZOOM != 1:
        scene.ppm *= ZOOM
        scene.origin = (scene.origin[0] * ZOOM, scene.origin[1] * ZOOM)
        scene.size = (scene.size[0] * ZOOM, scene.size[1] * ZOOM)
    return scene


# Bóng đổ mềm theo đúng hình xe (nhìn từ trên) thay cho bóng hộp chữ nhật
# img_shadow_box. Khung ảnh bóng khớp sẵn cách VehicleSprite đang vẽ bóng hộp
# (rộng 1,16 × ảnh xe, dài 1,08 ×, lùi -0,08 w / -0,04 h) nên chỉ cần đổi ảnh.
# tên ảnh xe → (tên ảnh bóng, độ nhoè sigma px)
SHADOWS = {
    'img_scooter_player': ('img_shadow_scooter_player', 1.6),
    'img_scooter_player_raincoat': ('img_shadow_scooter_player_raincoat', 1.6),
    'img_scooter_parked': ('img_shadow_scooter_parked', 1.6),
    'img_sedan_red': ('img_shadow_car_player', 2.2),
    'img_bus_player': ('img_shadow_bus_player', 2.4),
}
SHADOW_SCALE = (1.16, 1.08)
SHADOW_SHIFT = (0.08, 0.04)


def shadow_png(alpha, w, h, sigma):
    """Bóng: độ phủ của xe đặt vào khung 1,16w × 1,08h, nhoè Gauss, chỉ có
    kênh alpha (game tô đen, độ đậm do game quyết định)."""
    from PIL import ImageFilter
    H, W = alpha.shape
    zs = H // h  # số mẫu / px (SS × ZOOM)
    ow, oh = round(w * SHADOW_SCALE[0]), round(h * SHADOW_SCALE[1])
    ox, oy = round(w * SHADOW_SHIFT[0] * zs), round(h * SHADOW_SHIFT[1] * zs)
    big = np.zeros((oh * zs, ow * zs), np.float32)
    big[oy:oy + H, ox:ox + W] = alpha[:oh * zs - oy, :ow * zs - ox]
    im = Image.fromarray(np.clip(big * 255, 0, 255).astype(np.uint8))
    im = im.filter(ImageFilter.GaussianBlur(sigma * zs))
    a = np.asarray(im, np.float32) / 255
    a = a.reshape(oh, zs, ow, zs).mean((1, 3))
    out = np.zeros((oh, ow, 4), np.uint8)
    out[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


def save(scene, out, name, layers=None):
    """Vẽ [scene] (hoặc dùng sẵn [layers] = (rgb, alpha)) rồi ghi PNG (kèm
    ảnh bóng đổ nếu có trong [SHADOWS])."""
    t0 = time.time()
    if layers is None:
        zoomed(scene)
        rgb, alpha, _ = render(scene)
    else:
        rgb, alpha = layers
    img = finish(rgb, alpha, *scene.size)
    img.save(f'{out}/{name}.png', optimize=True)
    if name in SHADOWS:
        sname, sigma = SHADOWS[name]
        shadow_png(alpha, scene.size[0], scene.size[1], sigma * ZOOM).save(f'{out}/{sname}.png', optimize=True)
    print(f'{name}: {time.time() - t0:.1f}s')
    return img


BUILDERS = {
    'scooter': build_scooter_player,
    'raincoat': build_scooter_raincoat,
    'parked': build_scooter_parked,
    'car': build_car_player,
    'bus': build_bus_player,
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
        ZOOM = int(args[i + 1])
        args = args[:i] + args[i + 2:]
    os.makedirs(out, exist_ok=True)
    for k in (args or list(BUILDERS)):
        BUILDERS[k](out)
