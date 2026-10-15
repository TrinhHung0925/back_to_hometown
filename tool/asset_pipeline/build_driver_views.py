"""Ảnh cho góc nhìn "ghế lái" (đường giả 3D): xe AI nhìn từ sau / trước /
bên hông và khoang lái nhìn từ mắt người lái.

Dùng lại đúng các mô hình SDF của build_vehicles_3d.py (xe người chơi) và
build_traffic_3d.py (dòng xe AI) nhưng thêm máy ảnh tổng quát cho bộ dò tia:
    * máy ảnh trực giao theo phương vị / góc ngẩng bất kỳ (ảnh billboard);
    * máy ảnh lỗ kim phối cảnh (khoang lái).
Đổ sáng giữ nguyên công thức (nắng + trời bán cầu, bóng mềm, AO, GGX, sơn
bóng, kính tối) nhưng dùng đúng vector nhìn của từng tia thay cho +z. Nền
trong suốt, không vẽ mặt đất (game tự vẽ bóng).

Ảnh nhìn từ trên xuống không thấy bánh xe, đèn trên mặt đứng, biển số, cửa
sổ hông xe khách... nên ở đây bổ sung các bộ phận đó (bọc quanh mô hình cũ,
không sửa file cũ: chạy lại build_vehicles_3d.py / build_traffic_3d.py vẫn
cho ảnh y hệt từng byte).

Ghi vào assets/images/driver/:
    <tên>_rear.png, <tên>_front.png, <tên>_side.png
        tên = tên ảnh nhìn từ trên bỏ tiền tố img_ (scooter_ai_1..10,
        scooter_ai_raincoat_1..4, scooter_police, sedan_<màu>, mini_van,
        pickup_<màu>, bus_1..3, container_1, container_2, truck).
        Trực giao, góc ngẩng 7°, 80 px/m cho mọi xe. Mép dưới ảnh = điểm
        chạm đất thấp nhất của lốp, tâm xe nằm đúng giữa chiều ngang ảnh
        (sau / trước: tâm ngang xe; hông: giữa chiều dài). Ảnh hông nhìn từ
        bên TRÁI xe, mũi xe quay sang trái.
    vehicle_lamps.json   toạ độ px đèn hậu (ảnh _rear) và đèn pha (ảnh _front)
    billboards.json      kích thước, điểm neo, chiều dài / rộng thật (mét)
    cockpit_moto.png, cockpit_car.png, cockpit_car_wheel.png,
    cockpit_bus.png, cockpit_bus_wheel.png      khung 1600 × 740, nền trong
    cockpits.json        vị trí / tâm xoay vô-lăng, đường chân trời

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_driver_views.py              # tất cả
    python tool/asset_pipeline/build_driver_views.py moto car     # chọn nhóm
    python tool/asset_pipeline/build_driver_views.py --out DIR    # xuất chỗ khác
Nhóm: moto, car, bus, truck (billboard), cockpit. Có thể chọn từng xe bằng
tên ảnh, ví dụ: sedan_white scooter_ai_3 cockpit_car.
"""
import json
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_vehicles_3d as v3  # noqa: E402
import build_traffic_3d as tr  # noqa: E402
from build_vehicles_3d import (  # noqa: E402
    ALU, AMBER_LENS, BLACK_PLASTIC, CHROME, CLEAR_LENS, DARK_METAL, RUBBER, SATIN_BLACK, SEAT_VINYL, SKIN,
    SMOKE_GLASS, TAIL_LENS, Blend, Mat, Obj, Scene, capsule, ellipsoid, fabric, fbm, length2, length3, lin,
    mirror_x, paint, rbox, rot, round_cone, smax, smin, smoothstep, vnoise)

OUT = 'assets/images/driver'
BB_PPM = 80.0        # điểm ảnh / mét cho mọi billboard
BB_ELEV = 7.0        # góc ngẩng máy ảnh (độ, nhìn hơi chúc xuống)
BB_PAD = 3           # lề trong suốt (px) ở trên, trái, phải
SS = 4               # mẫu / chiều / điểm ảnh (billboard)
SS_COCKPIT = 3       # khung khoang lái lớn: 3 × 3 mẫu là đủ mịn


# ============================================================ Máy ảnh
def _unit(v):
    v = np.asarray(v, np.float64)
    return v / np.linalg.norm(v)


class OrthoCam:
    """Máy ảnh trực giao: tia song song theo [fwd]. Mặt phẳng ảnh đi qua gốc
    toạ độ; điểm ảnh (px, py) liên tục ↔ toạ độ (h, v) mét trên mặt phẳng ảnh:
    h = h0 + px / ppm, v = v_top - py / ppm."""

    def __init__(self, fwd, right, ppm, h0=0.0, v_top=0.0, size=(1, 1)):
        self.f = _unit(fwd)
        self.r = _unit(right)
        self.u = np.cross(self.f, self.r)
        self.ppm, self.h0, self.v_top, self.size = ppm, h0, v_top, size
        self.ortho = True

    @staticmethod
    def view(kind, elev=BB_ELEV, ppm=BB_PPM):
        """'rear': đứng sau xe nhìn tới (mũi xe hướng -y); 'front': đứng trước
        xe nhìn lại; 'side': đứng bên trái xe (x < 0), mũi xe quay sang trái."""
        c, s = math.cos(math.radians(elev)), math.sin(math.radians(elev))
        if kind == 'rear':
            return OrthoCam((0, -c, -s), (1, 0, 0), ppm)
        if kind == 'front':
            return OrthoCam((0, c, -s), (-1, 0, 0), ppm)
        if kind == 'side':
            return OrthoCam((c, 0, -s), (0, 1, 0), ppm)
        raise ValueError(kind)

    def project(self, p):
        """Điểm 3D → (px, py) liên tục trong khung ảnh."""
        p = np.asarray(p, np.float64)
        h, v = p @ self.r, p @ self.u
        return (h - self.h0) * self.ppm, (self.v_top - v) * self.ppm

    def hv(self, p):
        p = np.asarray(p, np.float64)
        return p @ self.r, p @ self.u

    def rays(self, px, py):
        h = self.h0 + px / self.ppm
        v = self.v_top - py / self.ppm
        # gốc tia lùi xa về phía sau mặt phẳng ảnh (ngoài mọi xe)
        o = [h * self.r[i] + v * self.u[i] - self.f[i] * 30.0 for i in range(3)]
        d = [np.full(px.shape, self.f[i]) for i in range(3)]
        return o, d

    def footprint(self, t):
        """Bề rộng một mẫu (mét) ở khoảng cách t."""
        return np.full(np.shape(t), 1.0 / self.ppm)


class PinholeCam:
    """Máy ảnh lỗ kim: mắt [eye], nhìn theo [yaw] (độ, 0 = về phía trước -y,
    dương = quay sang phải), [pitch] (độ, âm = chúc xuống), [fov] ngang (độ),
    khung [size] px, tâm ảnh lệch [shift] px (dời đường chân trời mà không
    nghiêng máy — như ống kính dịch trục)."""

    def __init__(self, eye, yaw, pitch, fov, size, shift=(0.0, 0.0), roll=0.0):
        self.eye = np.asarray(eye, np.float64)
        cy_, sy_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        f = np.array([sy_ * cp, -cy_ * cp, sp])
        r = np.array([cy_, sy_, 0.0])
        u = np.cross(f, r)
        if roll:
            cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
            r, u = r * cr + u * sr, u * cr - r * sr
        self.f, self.r, self.u = f, r, u
        self.size = size
        self.fl = size[0] / 2 / math.tan(math.radians(fov) / 2)
        self.cx = size[0] / 2 + shift[0]
        self.cy = size[1] / 2 + shift[1]
        self.ortho = False

    def project(self, p):
        q = np.asarray(p, np.float64) - self.eye
        z = q @ self.f
        return self.cx + self.fl * (q @ self.r) / z, self.cy - self.fl * (q @ self.u) / z

    def rays(self, px, py):
        a = (px - self.cx) / self.fl
        b = (self.cy - py) / self.fl
        d = [self.f[i] + a * self.r[i] + b * self.u[i] for i in range(3)]
        ln = length3(*d)
        d = [di / ln for di in d]
        o = [np.full(px.shape, self.eye[i]) for i in range(3)]
        return o, d

    def footprint(self, t):
        return np.asarray(t) / self.fl

    def horizon_row(self):
        """Hàng ảnh của đường chân trời (hướng nằm ngang ở xa vô cực)."""
        # hướng ngang cùng phương vị với f
        fh = np.array([self.f[0], self.f[1], 0.0])
        fh /= np.linalg.norm(fh)
        z = fh @ self.f
        return self.cy - self.fl * (fh @ self.u) / z


# ============================================================ Dò tia
def box_span(objs, o, d):
    """Khoảng [t0, t1] tia đi trong hợp các hộp bao bộ phận (t0 > t1: trượt)."""
    n = o[0].shape[0]
    t0 = np.full(n, np.inf)
    t1 = np.full(n, -np.inf)
    inv = [np.where(np.abs(d[i]) > 1e-12, 1.0 / np.where(np.abs(d[i]) > 1e-12, d[i], 1.0), 1e12) for i in range(3)]
    for ob in objs:
        if ob.lo[0] > ob.hi[0]:
            continue
        tn = np.zeros(n)
        tf = np.full(n, np.inf)
        for i in range(3):
            a = (ob.lo[i] - o[i]) * inv[i]
            b = (ob.hi[i] - o[i]) * inv[i]
            tn = np.maximum(tn, np.minimum(a, b))
            tf = np.minimum(tf, np.maximum(a, b))
        ok = tf >= tn
        t0 = np.where(ok, np.minimum(t0, tn), t0)
        t1 = np.where(ok, np.maximum(t1, tf), t1)
    return t0, t1


def march(scene, objs, o, d, cam, t0, t1, cap=0.12, iters=700):
    """Dò tia tổng quát từ t0 tới t1. Trả về (trúng?, t, id bộ phận)."""
    n = o[0].shape[0]
    t = t0.copy()
    hit = np.zeros(n, bool)
    alive = np.flatnonzero(t0 <= t1)
    for _ in range(iters):
        if alive.size == 0:
            break
        ta = t[alive]
        pa = tuple(o[i][alive] + d[i][alive] * ta for i in range(3))
        ds = scene.eval(pa, objs, cap=cap)
        eps = np.maximum(0.25 * cam.footprint(ta) / SS_NOW[0], 2e-5)
        got = ds < eps
        hit[alive[got]] = True
        tn = ta + np.maximum(ds * 0.8, eps * 0.6)
        t[alive] = np.where(got, ta, tn)
        alive = alive[~got & (tn <= t1[alive])]
    hi = np.flatnonzero(hit)
    for _ in range(4):
        if hi.size == 0:
            break
        p = tuple(o[i][hi] + d[i][hi] * t[hi] for i in range(3))
        t[hi] += scene.eval(p, objs) * 0.9
    oid = np.full(n, -1, np.int32)
    if hi.size:
        p = tuple(o[i][hi] + d[i][hi] * t[hi] for i in range(3))
        _, oo = scene.eval(p, objs, want_id=True)
        oid[hi] = oo
    return hit, t, oid


SS_NOW = [SS]  # số mẫu / chiều đang dùng (tiến trình con kế thừa)


# ============================================================ Đổ sáng
def ggx_v(n, v, rough, f0):
    """Phản xạ nắng GGX (đã nhân NdotL) với vector nhìn [v] tuỳ ý."""
    S = v3.SUN
    hx, hy, hz = S[0] + v[0], S[1] + v[1], S[2] + v[2]
    hl = np.maximum(length3(hx, hy, hz), 1e-9)
    hx, hy, hz = hx / hl, hy / hl, hz / hl
    nx, ny, nz = n
    nh = np.clip(nx * hx + ny * hy + nz * hz, 0, 1)
    nl = np.clip(nx * S[0] + ny * S[1] + nz * S[2], 0, 1)
    nv = np.clip(nx * v[0] + ny * v[1] + nz * v[2], 1e-3, 1)
    a = np.maximum(rough * rough, 0.002)
    a2 = a * a
    dd = a2 / (math.pi * (nh * nh * (a2 - 1) + 1) ** 2)
    kk = a / 2
    vis = 1.0 / ((nl * (1 - kk) + kk) * (nv * (1 - kk) + kk))
    vh = np.clip(v[0] * hx + v[1] * hy + v[2] * hz, 0, 1)
    f = f0 + (1 - f0) * (1 - vh) ** 5
    return dd * vis * 0.25 * f * nl


def shade_v(p, nrm, v, ma, shadow, ao, light=1.0):
    """Như v3.shade nhưng người nhìn theo [v] (vector từ điểm tới máy ảnh).
    [light] hệ số ánh sáng tới (trong khoang xe tối hơn ngoài trời)."""
    S = v3.SUN
    nx, ny, nz = nrm
    alb = ma['albedo']
    rough, metal, coat, sheen = ma['rough'], ma['metal'], ma['coat'], ma['sheen']
    wrap, spec = ma['wrap'], ma['spec']
    nl_raw = nx * S[0] + ny * S[1] + nz * S[2]
    nl = np.clip((nl_raw + wrap) / (1 + wrap), 0, 1)
    ndv = nx * v[0] + ny * v[1] + nz * v[2]
    nv = np.clip(ndv, 0, 1)
    sun = v3.SUN_COL[None, :] * (nl * shadow)[:, None]
    hemi = 0.5 + 0.5 * nz
    amb = (v3.SKY_IRR[None, :] * hemi[:, None] + v3.GROUND_IRR[None, :] * (1 - hemi)[:, None]) * ao[:, None]
    amb = amb * np.asarray(light)[..., None] if np.ndim(light) else amb * light
    diff = alb * (sun + amb) * (1 - metal)[:, None]
    f0 = (0.08 * spec)[:, None] * (1 - metal)[:, None] + alb * metal[:, None]
    k = 2 * np.maximum(ndv, 0)
    rx, ry, rz = k * nx - v[0], k * ny - v[1], k * nz - v[2]
    e = v3.env(rx, ry, rz, rough)
    fres = (1 - nv) ** 5
    fr = f0 + (np.maximum(1 - rough, f0.mean(1))[:, None] - f0) * fres[:, None]
    spec_occ = np.clip(ao * 1.15 - 0.1, 0, 1) * (0.35 + 0.65 * shadow)
    if np.ndim(light):
        spec_occ = spec_occ * light
    spec_env = fr * e * spec_occ[:, None]
    spec_sun = v3.SUN_COL[None, :] * (ggx_v(nrm, v, np.maximum(rough, 0.04), 1.0)[:, None] * f0) * shadow[:, None]
    base = diff + spec_env + spec_sun
    base = base + alb * (sheen * (1 - nv) ** 2.5 * 0.9)[:, None] * (v3.SKY_IRR[None, :] * ao[:, None] + sun * 0.4)
    if np.any(coat > 0):
        fc = 0.04 + 0.96 * fres
        ce = v3.env(rx, ry, rz, np.full_like(rough, 0.02))
        cs = v3.SUN_COL[None, :] * ggx_v(nrm, v, np.full_like(rough, 0.11), 0.04)[:, None] * shadow[:, None]
        cl = ce * fc[:, None] * spec_occ[:, None] + cs
        base = base * (1 - (coat * fc)[:, None]) + cl * coat[:, None]
    base = base + alb * ma['emit'][:, None]
    return base


LAMP_NONE, LAMP_TAIL, LAMP_HEAD = 0, 1, 2


def lamp_of(m):
    return {'tail': LAMP_TAIL, 'head': LAMP_HEAD}.get(getattr(m, 'lamp', None), LAMP_NONE)


def materials(objs, oid, p, nrm):
    """Mảng thuộc tính vật liệu từng điểm + nhãn đèn (hậu / pha)."""
    x, y, z = p
    n = x.shape[0]
    ma = {'albedo': np.zeros((n, 3))}
    for f in v3.MAT_FIELDS:
        ma[f] = np.zeros(n)
    ma['light'] = np.ones(n)
    lamp = np.zeros(n, np.int8)
    for i, o in enumerate(objs):
        sel = np.flatnonzero(oid == i)
        if sel.size == 0:
            continue
        ps = (x[sel], y[sel], z[sel])
        ns = (nrm[0][sel], nrm[1][sel], nrm[2][sel])
        idx = o.pick(ps, ns) if o.pick else np.zeros(sel.size, np.int32)
        sub = v3.mat_arrays(o.mats, idx, sel.size)
        if o.tint is not None:
            sub['albedo'] = o.tint(ps, ns, sub['albedo'], idx)
        for k, v in sub.items():
            ma[k][sel] = v
        lt = np.array([lamp_of(m) for m in o.mats], np.int8)
        lamp[sel] = lt[idx]
        ma['light'][sel] = getattr(o, 'light', 1.0)
    return ma, lamp


def shade_hits_v(scene, objs, o, d, t, oid, cam, glass_pass=True, light_fn=None, shadow_objs=None):
    """Tô màu các điểm trúng theo tia (o, d). Trả về (rgb, alpha, nhãn đèn)."""
    p = tuple(o[i] + d[i] * t for i in range(3))
    v = (-d[0], -d[1], -d[2])
    h = float(np.median(cam.footprint(t))) * 0.35 / SS_NOW[0] if t.size else 1e-3
    h = max(h, 1.5e-4)
    nrm = v3.normals(objs, oid, p, h)
    # pháp tuyến quay lưng về máy ảnh (mặt rất xiên): lật nhẹ cho khỏi đen
    ndv = nrm[0] * v[0] + nrm[1] * v[1] + nrm[2] * v[2]
    back = ndv < 0.02
    if back.any():
        k = (0.02 - ndv) * back
        nn = [nrm[i] + k * v[i] for i in range(3)]
        ln = length3(*nn)
        nrm = tuple(nn[i] / ln for i in range(3))
    ma, lamp = materials(objs, oid, p, nrm)
    so = objs if shadow_objs is None else shadow_objs
    sh = v3.soft_shadow(scene, p, nrm, so)
    ao = v3.ambient_occ(scene, p, nrm, so)
    light = ma['light']
    if light_fn is not None:
        light = light * light_fn(p)
    sh = sh * np.clip(light, 0, 1)
    col = shade_v(p, nrm, v, ma, sh, ao, light=light)
    # ánh sáng hắt trong khoang xe (qua kính sau / kính hông, dội từ sàn,
    # táp-lô): đèn phụ không đổ bóng, nhân AO
    for fdir, fcol in _JOB.get('fill', ()):
        k = np.clip(nrm[0] * fdir[0] + nrm[1] * fdir[1] + nrm[2] * fdir[2], 0, 1) * ao * (1 - ma['metal'])
        col = col + ma['albedo'] * np.asarray(fcol)[None, :] * k[:, None]
    nv = np.clip(nrm[0] * v[0] + nrm[1] * v[1] + nrm[2] * v[2], 0, 1)
    alpha = 1 - ma['clear'] * nv ** 0.7
    g = np.flatnonzero(ma['glass'] > 0)
    if g.size and glass_pass:
        col[g] = glass_v(scene, tuple(pi[g] for pi in p), tuple(ni[g] for ni in nrm), tuple(vi[g] for vi in v),
                         tuple(di[g] for di in d), sh[g], cam, ma['glass'][g])
    return col, alpha, lamp


def glass_v(scene, p, nrm, v, d, shadow, cam, amount):
    """Kính tối màu: trời phản chiếu theo Fresnel + nội thất thấy xuyên qua
    (tia đi tiếp thẳng qua kính vào trong xe)."""
    nx, ny, nz = nrm
    ndv = nx * v[0] + ny * v[1] + nz * v[2]
    nv = np.clip(ndv, 0, 1)
    k = 2 * np.maximum(ndv, 0)
    rx, ry, rz = k * nx - v[0], k * ny - v[1], k * nz - v[2]
    fres = 0.07 + 0.93 * (1 - nv) ** 4
    n = nx.shape[0]
    refl = v3.env(rx, ry, rz, np.full(n, 0.03)) * fres[:, None] * 1.5
    refl += v3.SUN_COL[None, :] * ggx_v(nrm, v, np.full(n, 0.05), 0.05)[:, None] * shadow[:, None]
    inside = np.zeros((n, 3)) + lin((20, 22, 25))
    if scene.interior:
        o2 = tuple(p[i] + d[i] * 0.006 for i in range(3))
        t0, t1 = box_span(scene.interior, o2, d)
        t0 = np.maximum(t0, 0.0)
        t1 = np.minimum(t1, 3.5)
        hit, ti, oi = march(scene, scene.interior, o2, d, cam, t0, t1)
        hi = np.flatnonzero(hit)
        if hi.size:
            sub = lambda a: tuple(ai[hi] for ai in a)  # noqa: E731
            ci, _, _ = shade_hits_v(scene, scene.interior, sub(o2), sub(d), ti[hi], oi[hi], cam, glass_pass=False)
            inside[hi] = ci * 0.42
    trans = scene.glass_tint[None, :] * (1 - fres)[:, None]
    return refl + inside * trans


# ============================================================ Vẽ ảnh
_JOB = {}


def render_rows_v(args):
    r0, r1 = args
    scene, cam, ss = _JOB['scene'], _JOB['cam'], SS_NOW[0]
    w, h = cam.size
    W = w * ss
    ys = (np.arange(r0, r1) + 0.5) / ss
    xs = (np.arange(W) + 0.5) / ss
    px, py = np.meshgrid(xs, ys)
    px, py = px.ravel(), py.ravel()
    o, d = cam.rays(px, py)
    n = px.shape[0]
    rgb = np.zeros((n, 3))
    alpha = np.zeros(n)
    depth = np.full(n, np.inf)
    lamp = np.zeros(n, np.int8)
    prim = getattr(scene, 'primary', None) or scene.objs
    t0, t1 = box_span(prim, o, d)
    if not cam.ortho:
        t0 = np.maximum(t0, _JOB.get('near', 0.0))
    cand = np.flatnonzero(t0 <= t1)
    if cand.size:
        oc = tuple(a[cand] for a in o)
        dc = tuple(a[cand] for a in d)
        hit, t, oid = march(scene, prim, oc, dc, cam, t0[cand], t1[cand])
        hc = np.flatnonzero(hit)
        if hc.size:
            col, a, lp = shade_hits_v(scene, prim, tuple(a[hc] for a in oc), tuple(a[hc] for a in dc), t[hc],
                                      oid[hc], cam, light_fn=_JOB.get('light_fn'), shadow_objs=scene.objs)
            idx = cand[hc]
            rgb[idx] = col
            alpha[idx] = a
            depth[idx] = t[hc]
            lamp[idx] = lp
    sh = (r1 - r0, W)
    return rgb.reshape(sh + (3,)), alpha.reshape(sh), depth.reshape(sh), lamp.reshape(sh)


def render_cam(scene, cam, ss=SS, procs=8, near=0.0, light_fn=None, fill=()):
    """Vẽ [scene] qua máy ảnh [cam] → (rgb tuyến tính, alpha, độ sâu t, nhãn
    đèn) ở độ phân giải mẫu (size × ss). [fill]: đèn phụ [(hướng, màu)]."""
    _JOB.clear()
    _JOB.update(scene=scene, cam=cam, near=near, light_fn=light_fn,
                fill=[(_unit(d), np.asarray(c, np.float64)) for d, c in fill])
    SS_NOW[0] = ss
    w, h = cam.size
    H = h * ss
    chunk = max(ss * 2, (H // (procs * 4)) // ss * ss)
    jobs = [(r, min(H, r + chunk)) for r in range(0, H, chunk)]
    if procs > 1:
        with mp.get_context('fork').Pool(procs) as pool:
            parts = pool.map(render_rows_v, jobs)
    else:
        parts = [render_rows_v(j) for j in jobs]
    return tuple(np.concatenate([p[k] for p in parts], 0) for k in range(4))


def finish_v(rgb, alpha, w, h, ss):
    """Như v3.finish nhưng với số mẫu [ss] tuỳ ý."""
    col = v3.tonemap(rgb)
    pre = col * alpha[..., None]
    pre = pre.reshape(h, ss, w, ss, 3).mean((1, 3))
    a = alpha.reshape(h, ss, w, ss).mean((1, 3))
    rgb8 = np.where(a[..., None] > 1e-4, pre / np.maximum(a[..., None], 1e-4), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(rgb8 * 255 + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


class sun_from:
    """Đặt hướng nắng tạm thời (v3.SUN) trong khối with."""

    def __init__(self, direction):
        self.d = _unit(direction)

    def __enter__(self):
        self.old = v3.SUN
        v3.SUN = self.d
        return self

    def __exit__(self, *a):
        v3.SUN = self.old


def key_light(cam):
    """Nắng cho billboard: từ phía trên - bên trái máy ảnh, hơi chếch về phía
    người xem để mặt xe hướng về máy ảnh được rọi sáng (như ảnh nhìn từ trên
    xuống: nắng từ góc trên - trái ảnh)."""
    back = -np.array([cam.f[0], cam.f[1], 0.0])
    back /= np.linalg.norm(back)
    return -0.42 * cam.r + 0.40 * back + 0.80 * np.array([0, 0, 1.0])


# ======================================================= Bộ phận dùng chung
def tagged(mat, lamp):
    """Bản sao vật liệu có nhãn đèn ('tail' / 'head') để tính toạ độ đèn."""
    m = Mat((0, 0, 0))
    m.__dict__.update(mat.__dict__)
    m.lamp = lamp
    return m


def lit(obj, k):
    """Bộ phận nằm trong khoang tối (ánh sáng tới giảm còn [k])."""
    obj.light = k
    return obj


def surface_along(sdf, p0, d, tmax=3.0, step=0.002):
    """Khoảng cách từ p0 theo hướng d tới mặt [sdf] (lấy mẫu dày)."""
    t = np.arange(0, tmax, step)
    v = sdf(tuple(p0[i] + d[i] * t for i in range(3)))
    k = np.flatnonzero(v < 0)
    return None if k.size == 0 else float(t[k[0]])


FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'fonts', 'Manrope-Bold.ttf')


def text_tex(lines, size_mm, squeeze=0.78, border=True, weight=1.0):
    """Vân chữ (biển số, số kẻ thành xe): mảng [0..1] (1 = mực), mỗi mm 4 px."""
    from PIL import ImageDraw, ImageFont
    k = 4
    W, H = int(size_mm[0] * k), int(size_mm[1] * k)
    img = Image.new('L', (W, H), 0)
    dr = ImageDraw.Draw(img)
    if border:
        b = max(2, int(3 * k))
        dr.rectangle([b, b, W - 1 - b, H - 1 - b], outline=255, width=max(2, int(2.2 * k)))
    n = len(lines)
    line_h = (H - 10 * k) / n
    for i, s in enumerate(lines):
        fs = int(line_h * 1.05)
        font = ImageFont.truetype(FONT, fs)
        bb = dr.textbbox((0, 0), s, font=font, stroke_width=int(weight))
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        tmp = Image.new('L', (tw + 4, th + 4), 0)
        ImageDraw.Draw(tmp).text((2 - bb[0], 2 - bb[1]), s, fill=255, font=font, stroke_width=int(weight), stroke_fill=255)
        tw2 = int(min(W - 16 * k, tw * squeeze))
        th2 = int(line_h * 0.80)
        tmp = tmp.resize((tw2, th2), Image.LANCZOS)
        img.paste(tmp, ((W - tw2) // 2, int(5 * k + i * line_h + (line_h - th2) / 2)), tmp)
    return np.asarray(img, np.float64) / 255.0


def sample_tex(tex, u, v):
    """Lấy mẫu song tuyến vân [tex] tại (u, v) ∈ [0, 1]² (u sang phải, v xuống)."""
    H, W = tex.shape
    fx = np.clip(u, 0, 1) * (W - 1)
    fy = np.clip(v, 0, 1) * (H - 1)
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    x1, y1 = np.minimum(x0 + 1, W - 1), np.minimum(y0 + 1, H - 1)
    ax, ay = fx - x0, fy - y0
    a = tex[y0, x0] * (1 - ax) + tex[y0, x1] * ax
    b = tex[y1, x0] * (1 - ax) + tex[y1, x1] * ax
    return a * (1 - ay) + b * ay


PLATE_WHITE = Mat((232, 232, 226), rough=0.35, spec=0.6)
PLATE_FRAME = Mat((18, 18, 20), rough=0.4, spec=0.5)


def plate_obj(name, center, half, facing, lines, tilt=0.0, frame=True):
    """Biển số phẳng (nền trắng chữ đen) đặt đứng, mặt quay về +y ([facing]
    = 1, đuôi xe) hoặc -y (-1, đầu xe); [half] (nửa rộng, nửa cao) mét."""
    cx, cy, cz = center
    hw, hh = half
    tex = text_tex(lines, (hw * 2000, hh * 2000))

    def local(p):
        x, y, z = p
        yy, zz = rot(y - cy, z - cz, tilt * facing)
        return x - cx, yy, zz

    def sdf(p):
        u, w, v = local(p)
        plate = rbox((u, w, v), (0, 0, 0), (hw, 0.004, hh), 0.003)
        if frame:
            fr = rbox((u, w, v), (0, -facing * 0.006, 0), (hw + 0.012, 0.005, hh + 0.012), 0.006)
            plate = np.minimum(plate, fr)
        return plate

    def pick(p, n):
        u, w, v = local(p)
        on = (np.abs(u) < hw - 0.001) & (np.abs(v) < hh - 0.001) & (w * facing > 0.0)
        return np.where(on, 0, 1).astype(np.int32)

    def tint(p, n, alb, idx):
        u, w, v = local(p)
        uu = (u * facing + hw) / (2 * hw)
        vv = (hh - v) / (2 * hh)
        ink = sample_tex(tex, uu, vv)
        out = alb * (1 - 0.93 * ink)[:, None]
        return np.where((idx == 0)[:, None], out, alb)
    return Obj(name, sdf, [PLATE_WHITE, PLATE_FRAME], pick=pick, tint=tint)


# ------------------------------------------------------------ Bánh xe
TYRE = Mat((28, 28, 30), rough=0.72, spec=0.4)
RIM_ALLOY = Mat((214, 216, 220), rough=0.28, metal=0.5, spec=0.8)
RIM_DARK = Mat((40, 41, 44), rough=0.45, metal=0.6)
RIM_STEEL = Mat((150, 152, 156), rough=0.35, metal=0.8)


def wheel_objs(name, ya, R, xc, hw, rim_r, spokes=5, style='alloy', side=None):
    """Một bánh xe (lốp + mâm) trục ngang x tại (xc, ya, R); [side] -1 / +1:
    mặt ngoài quay về x âm / dương (mặc định theo dấu xc)."""
    sd = side if side is not None else (1.0 if xc > 0 else -1.0)
    rr = min(0.035, hw * 0.45)
    th = R - rim_r + 0.015

    def tyre_sdf(p):
        return v3.tyre(p, (xc, ya, R), R, th, hw, rr)

    def tyre_tint(p, n, alb, idx):
        # gân gai lốp ở mặt lăn, chữ nổi mờ ở hông lốp
        x, y, z = p
        r = length2(y - ya, z - R)
        ang = np.arctan2(z - R, y - ya)
        tread = (r > R - 0.02) & (np.sin(ang * 70) > 0.55)
        return alb * np.where(tread, 0.7, 1.0)[:, None]
    face = hw - 0.018

    def rim_sdf(p):
        x, y, z = p
        lx = (x - xc) * sd
        ly, lz = y - ya, z - R
        r = length2(ly, lz)
        # vành ngoài
        q1 = r - (rim_r - 0.012)
        q2 = lx - (face - 0.045)
        lip = length2(np.maximum(np.abs(q1) - 0.012, 0), np.maximum(np.abs(q2) - 0.045, 0)) - 0.003
        # đĩa phanh / lòng mâm sẫm phía sau
        back = np.maximum(r - (rim_r - 0.006), np.abs(lx - (face - 0.085)) - 0.012)
        if style == 'steel':
            disc = np.maximum(r - (rim_r - 0.01), np.abs(lx - (face - 0.03 - 0.02 * (r / rim_r))) - 0.008)
            holes = None
            for k in range(6):
                a = k * math.tau / 6
                hdist = length2(ly - math.cos(a) * rim_r * 0.62, lz - math.sin(a) * rim_r * 0.62) - rim_r * 0.14
                holes = hdist if holes is None else np.minimum(holes, hdist)
            disc = smax(disc, -holes, 0.006)
            hub = np.maximum(r - rim_r * 0.30, np.abs(lx - (face - 0.01)) - 0.02)
            return np.minimum(np.minimum(lip, back), np.minimum(disc, hub))
        sector = math.tau / spokes
        ang = np.arctan2(lz, ly)
        a = ang - sector * np.round(ang / sector)
        u, w = r * np.cos(a), r * np.sin(a)
        hwid = 0.019 - 0.007 * (u / rim_r)
        sp_x = face - 0.012 - 0.028 * (1 - u / rim_r)
        spoke = np.maximum(np.maximum(np.abs(u - (0.04 + rim_r) / 2) - (rim_r - 0.04) / 2, np.abs(w) - hwid),
                           np.abs(lx - sp_x) - 0.011)
        hub = np.maximum(r - 0.058, np.abs(lx - (face - 0.035)) - 0.026)
        return np.minimum(np.minimum(lip, back), smin(spoke, hub, 0.012))

    def rim_pick(p, n):
        x, y, z = p
        lx = (x - xc) * sd
        return (lx < face - 0.07).astype(np.int32)

    def rim_tint(p, n, alb, idx):
        x, y, z = p
        ly, lz = y - ya, z - R
        r = length2(ly, lz)
        ang = np.arctan2(lz, ly)
        nut = (r > 0.032) & (r < 0.05) & (np.cos(ang * spokes + math.pi) > 0.86)
        cap = r < 0.026
        return alb * np.where(nut, 0.45, 1.0)[:, None] * np.where(cap, 0.55, 1.0)[:, None]
    rim_m = RIM_STEEL if style == 'steel' else RIM_ALLOY
    return [Obj(name + '_tyre', tyre_sdf, TYRE, tint=tyre_tint),
            Obj(name + '_rim', rim_sdf, [rim_m, RIM_DARK], pick=rim_pick, tint=rim_tint)]


def four_wheels(axles, R, track, hw, rim_r, spokes=5, style='alloy'):
    out = []
    for i, ya in enumerate(axles):
        for s in (-1, 1):
            out += wheel_objs(f'wheel{i}{"lr"[s > 0]}', ya, R, s * track, hw, rim_r, spokes, style)
    return out


def arch_cut(body, axles, arch_r, arch_z, x_in):
    """Khoét hốc bánh xe vào thân (ống trụ trục x, chỉ phần ngoài |x| > x_in)."""
    def sdf(p):
        x, y, z = p
        d = body(p)
        ax = np.abs(x)
        for ya in axles:
            cyl = length2(y - ya, z - arch_z) - arch_r
            cut = smax(cyl, x_in - ax, 0.03)
            d = smax(d, -cut, 0.02)
        return d
    return sdf


def in_arch(y, z, axles, arch_r, arch_z, extra=0.004):
    m = np.zeros(y.shape, bool)
    for ya in axles:
        m |= length2(y - ya, z - arch_z) < arch_r + extra
    return m


def line_mask(d, w=0.0055):
    return np.abs(d) < w


# ================================================================== Ô tô
# Vật liệu thêm sau bộ vật liệu thân xe của build_traffic_3d.car_mats.
(PAINT_I, GLASS_I, FRIT_I, TRIM_I, HEAD_I, HEADIN_I, DRL_I, TAIL_I, TAILIN_I, CHROME_I, LINER_I,
 WELL_I, REFLECT_I, REVERSE_I, DEEP_I, FOG_I, AMBER_I, MGLASS_I, STOP_I) = range(19)


def car_mats_v(color, metal=0.55):
    """Vật liệu thân xe (như ảnh từ trên) + lót hốc bánh, đèn lùi, phản
    quang, lưới sâu, đèn sương mù, xi-nhan, mặt gương; đèn được gắn nhãn."""
    m = tr.car_mats(color, metal)
    m[HEAD_I] = tagged(Mat((200, 206, 212), rough=0.04, metal=0.75, coat=1.0), 'head')
    m[HEADIN_I] = tagged(m[HEADIN_I], 'head')
    m[DRL_I] = tagged(m[DRL_I], 'head')
    m[TAIL_I] = tagged(Mat((205, 24, 26), rough=0.05, spec=1.2, coat=1.0, emit=0.45), 'tail')
    m[TAILIN_I] = tagged(Mat((96, 10, 12), rough=0.05, spec=1.2, coat=1.0, emit=0.15), 'tail')
    return m + [Mat((20, 20, 22), rough=0.85, spec=0.3),                      # hốc bánh
                Mat((150, 20, 22), rough=0.15, spec=0.8, coat=0.8),            # phản quang
                tagged(Mat((210, 214, 218), rough=0.05, metal=0.4, coat=1.0), 'tail'),  # đèn lùi
                Mat((7, 7, 8), rough=0.7, spec=0.3),                           # lòng lưới
                Mat((228, 230, 234), rough=0.05, coat=1.0, emit=0.08),         # đèn gầm
                Mat((235, 130, 20), rough=0.08, spec=1.2, coat=0.8),           # xi-nhan
                Mat((70, 78, 88), rough=0.02, metal=1.0),                      # mặt gương
                Mat((205, 24, 26), rough=0.05, spec=1.2, coat=1.0, emit=0.45)]  # đèn phanh trên cao


def rrect_in(a, b, c, half, ang=0.0, r=0.02):
    """(a, b) nằm trong hình chữ nhật bo góc (tâm c, nửa cạnh half, xoay ang)?"""
    return _rr(a, b, c, half, ang, r) < 0


def _rr(a, b, c, half, ang=0.0, r=0.02):
    u, v = rot(a - c[0], b - c[1], -ang)
    qx, qy = np.abs(u) - half[0] + r, np.abs(v) - half[1] + r
    return length2(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


class CarSpec:
    """Thông số phần thêm cho ô tô (mét): trục bánh [axles], bán kính lốp [R],
    tâm lốp [track] (|x|), nửa bề rộng lốp [hw], bán kính mâm [rim_r], hốc
    bánh (bán kính, độ cao tâm, |x| bắt đầu khoét), [belt] gân hông."""

    def __init__(self, L, axles, R, track, hw, rim_r, arch_r, arch_z, arch_in, belt, spokes=5, rim='alloy'):
        self.L, self.axles, self.R, self.track, self.hw, self.rim_r = L, axles, R, track, hw, rim_r
        self.arch_r, self.arch_z, self.arch_in, self.belt = arch_r, arch_z, arch_in, belt
        self.spokes, self.rim = spokes, rim

    def wheels(self):
        return four_wheels(self.axles, self.R, self.track, self.hw, self.rim_r, self.spokes, self.rim)

    def body(self, sdf):
        cut = arch_cut(sdf, self.axles, self.arch_r, self.arch_z, self.arch_in)
        L = self.L
        # chặn đầu / đuôi: khoang kính của mô hình cũ không có giới hạn trước
        # (ảnh từ trên không thấy) nên nhìn ngang lòi ra một lá mỏng
        return lambda p: np.maximum(cut(p), np.maximum(-0.004 - p[1], p[1] - L - 0.10))

    def well(self, y, z):
        return in_arch(y, z, self.axles, self.arch_r, self.arch_z)


SEDAN_V = CarSpec(L=4.45, axles=(0.93, 3.50), R=0.300, track=0.765, hw=0.094, rim_r=0.19, arch_r=0.372, arch_z=0.315,
                  arch_in=0.56, belt=v3.CAR_BELT, spokes=5)


def sedan_pick_v(p, n):
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    idx = v3.car_pick(p, n)
    L = SEDAN_V.L
    glass = (idx == GLASS_I) | (idx == FRIT_I)
    front = (y < 0.75) & (nz < 0.62) & ~glass
    rear = (y > L - 0.70) & (nz < 0.62) & ~glass
    idx[(front | rear) & (idx != PAINT_I)] = PAINT_I
    # ---- đầu xe
    hl = ((0.635, 0.618), (0.215, 0.054), 0.13, 0.035)
    head = front & rrect_in(ax, z, *hl) & (y < 0.55)
    idx[head] = HEAD_I
    proj = head & ((length2(ax - 0.515, z - 0.603) < 0.031) | (length2(ax - 0.612, z - 0.616) < 0.029))
    idx[proj] = HEADIN_I
    drl = head & (np.abs(_rr(ax, z, *hl) + 0.009) < 0.0065) & (rot(ax - 0.635, z - 0.618, -0.13)[1] < 0)
    idx[drl] = DRL_I
    grille = front & (z > 0.505) & (z < 0.605) & (ax < 0.375 - 0.3 * (0.605 - z)) & (y < 0.3)
    idx[grille] = TRIM_I
    idx[grille & (z > 0.591)] = CHROME_I
    idx[grille & (np.abs(((z - 0.505) % 0.03) - 0.015) < 0.004)] = CHROME_I
    idx[front & (((ax / 0.046) ** 2 + ((z - 0.556) / 0.030) ** 2) < 1) & (y < 0.3)] = CHROME_I
    intake = front & (z > 0.245) & (z < 0.372) & (ax < 0.47 - 0.4 * (0.372 - z)) & (y < 0.2)
    idx[intake] = DEEP_I
    fogb = front & (((ax - 0.665) / 0.078) ** 2 + ((z - 0.32) / 0.046) ** 2 < 1) & (y < 0.4)
    idx[fogb] = TRIM_I
    idx[fogb & (length2(ax - 0.665, z - 0.32) < 0.026)] = FOG_I
    idx[front & (z < 0.235) & (y < 0.35)] = TRIM_I
    # ---- đuôi xe
    tl = rear & (_rr(ax, z, (0.675, 0.838), (0.205, 0.056), -0.06, 0.03) < 0) & (y > L - 0.48)
    idx[tl] = TAIL_I
    idx[tl & (np.abs(z - 0.838 + 0.06 * (ax - 0.675)) < 0.013)] = TAILIN_I
    idx[tl & (ax < 0.565)] = REVERSE_I
    idx[rear & (z > 0.772) & (z < 0.79) & (ax < 0.47)] = CHROME_I
    idx[rear & (((ax / 0.042) ** 2 + ((z - 0.862) / 0.026) ** 2) < 1)] = CHROME_I
    idx[rear & (z < 0.315) & (ax < 0.80)] = TRIM_I
    idx[rear & (ax > 0.56) & (ax < 0.74) & (np.abs(z - 0.37) < 0.014)] = REFLECT_I
    # ---- hông xe
    side = (np.abs(nx) > 0.45) & ~glass & (z < SEDAN_V.belt + 0.02)
    idx[side & (z < 0.272) & (y > 0.4) & (y < L - 0.4)] = TRIM_I
    sw = (np.abs(nx) > 0.45) & (y > 1.52) & (y < 3.48)
    idx[sw & (z > SEDAN_V.belt - 0.004) & (z < SEDAN_V.belt + 0.012) & ~glass] = CHROME_I
    idx[SEDAN_V.well(y, z) & (ax < 0.905) & (z < SEDAN_V.arch_z + SEDAN_V.arch_r + 0.01)] = WELL_I
    return idx


def door_lines(y, z, segs, arcs=()):
    """Đường ron cửa trên mặt hông: [segs] đoạn đứng (y, z0, z1), [arcs] cung
    (tâm y, tâm z, bán kính, góc đầu, góc cuối) quanh hốc bánh."""
    m = np.zeros(y.shape, bool)
    for yy, z0, z1 in segs:
        m |= line_mask(y - yy) & (z > z0) & (z < z1)
    for cy, cz, r, a0, a1 in arcs:
        ang = np.arctan2(z - cz, y - cy)
        m |= line_mask(length2(y - cy, z - cz) - r) & (ang > a0) & (ang < a1)
    return m


def sedan_tint_v(p, n, alb, idx):
    x, y, z = p
    ax = np.abs(x)
    nx, ny, nz = n
    out = v3.car_tint(p, n, alb, idx)
    paint_ = idx == PAINT_I
    side = (np.abs(nx) > 0.45) & paint_
    belt = SEDAN_V.belt
    dl = door_lines(y, z, [(1.50, 0.272, belt), (2.52, 0.272, belt), (3.50, 0.69, belt)],
                    [(3.50, 0.315, 0.40, 1.5708, 3.1416)])
    dl |= line_mask(z - 0.276) & (y > 1.50) & (y < 3.10)
    fuel = (x < 0) & line_mask(length2(y - 3.98, z - 0.84) - 0.068, 0.005)
    rear = (ny > 0.4) & paint_
    trunk = rear & ((line_mask(ax - 0.60) & (z > 0.60)) | (line_mask(z - 0.60) & (ax < 0.60)))
    m = (side & (dl | fuel)) | trunk
    out = np.where(m[:, None], out * 0.35, out)
    # lưới tổ ong của hốc gió dưới
    deep = idx == DEEP_I
    hexs = (np.sin(x * 160) * np.sin(z * 160 + 0.5 * np.sin(x * 160)) > 0.35)
    out = np.where((deep & hexs)[:, None], lin((30, 30, 32)), out)
    return out


def car_mirror_pick(base_z):
    def pick(p, n):
        idx = (p[2] >= base_z).astype(np.int32)
        idx[(n[1] > 0.55) & (p[2] > base_z - 0.02)] = 2
        return idx
    return pick


def door_handles(sdf, spots, z, color_mat):
    """Tay nắm cửa nổi trên mặt hông (cả hai bên), đặt đúng mặt thân xe."""
    objs = []
    boxes = []
    for yc in spots:
        t = surface_along(sdf, (-1.6, yc, z), (1, 0, 0))
        xs = 1.6 - t
        boxes.append((xs, yc))

    def h(p):
        q = (np.abs(p[0]), p[1], p[2])
        d = None
        for xs, yc in boxes:
            v = rbox(q, (xs + 0.004, yc, z), (0.012, 0.068, 0.013), 0.009)
            d = v if d is None else np.minimum(d, v)
        return d
    objs.append(Obj('handles', h, color_mat))
    return objs


def plate_on(sdf, x, z, facing, half, lines, name, y_far):
    """Đặt biển số áp vào mặt đầu / đuôi xe ở độ cao z."""
    if facing > 0:
        t = surface_along(sdf, (x, y_far, z), (0, -1, 0), tmax=4)
        yf = y_far - t
        t2 = surface_along(sdf, (x, y_far, z + half[1]), (0, -1, 0), tmax=4)
        t3 = surface_along(sdf, (x, y_far, z - half[1]), (0, -1, 0), tmax=4)
        yc = yf + 0.010
        tilt = math.atan2((y_far - t2) - (y_far - t3), 2 * half[1])
    else:
        t = surface_along(sdf, (x, y_far, z), (0, 1, 0), tmax=4)
        yf = y_far + t
        t2 = surface_along(sdf, (x, y_far, z + half[1]), (0, 1, 0), tmax=4)
        t3 = surface_along(sdf, (x, y_far, z - half[1]), (0, 1, 0), tmax=4)
        yc = yf - 0.010
        tilt = -math.atan2((y_far + t2) - (y_far + t3), 2 * half[1])
    return plate_obj(name, (x, yc, z), half, facing, lines, tilt=tilt)


def sedan_v(color, metal=0.55, shirt=(92, 104, 122), plate=('51K-386.27',)):
    """Sedan AI (cùng thân xe người chơi) đủ bánh, đèn, biển số cho billboard."""
    S = SEDAN_V
    body = S.body(v3.car_body)
    pt = paint(color, metal=metal)
    mats = car_mats_v(color, metal)
    parts = [Obj('body', body, mats, pick=sedan_pick_v, tint=sedan_tint_v),
             Obj('mirrors', v3.car_mirror, [pt, Mat((20, 21, 22), rough=0.45), mats[MGLASS_I]],
                 pick=car_mirror_pick(0.955)),
             Obj('wipers', v3.car_wipers, Mat((16, 16, 18), rough=0.4)),
             Obj('antenna', lambda p: ellipsoid(p, (0, 3.02, 1.435), (0.026, 0.085, 0.036)),
                 Mat((14, 14, 16), rough=0.15, spec=0.8, coat=1.0))]
    parts += S.wheels()
    parts += door_handles(v3.car_body, (2.30, 3.26), 0.885, pt)
    parts.append(plate_on(v3.car_body, 0.0, 0.70, 1, (0.26, 0.055), plate, 'plate_r', 5.2))
    parts.append(plate_on(v3.car_body, 0.0, 0.443, -1, (0.26, 0.055), plate, 'plate_f', -0.8))
    sc = Scene(parts, ((-1.12, -0.12, 0.0), (1.12, 4.56, 1.52)), BB_PPM, (0, 0), (1, 1), ao_scale=1.6,
               interior=v3.car_interior(shirt=shirt), glass_tint=(0.36, 0.39, 0.42))
    return sc


# ============================================================ Billboard
class Model:
    """Một xe để chụp billboard: cảnh SDF, các điểm chạm đất của lốp, đoạn
    chiều dài thân xe (y0, y1), nửa bề rộng [half_w] (mét) và tuỳ chọn
    [layers] (hàm vẽ ghép riêng, ví dụ áo mưa)."""

    def __init__(self, scene, contacts, y_span, half_w, kind, layers=None):
        self.scene, self.contacts, self.y_span, self.half_w = scene, contacts, y_span, half_w
        self.kind, self.layers = kind, layers


def frame_for(cam, model):
    """Khung ảnh sơ bộ: bao mọi hộp bộ phận, mép dưới = điểm chạm đất thấp
    nhất, tâm xe giữa khung (bề rộng chẵn)."""
    corners = []
    for o in model.scene.objs:
        if o.lo[0] > o.hi[0]:
            continue
        for a in (o.lo[0], o.hi[0]):
            for b in (o.lo[1], o.hi[1]):
                for c in (o.lo[2], o.hi[2]):
                    corners.append((a, b, c))
    h, v = cam.hv(np.array(corners))
    yc = (model.y_span[0] + model.y_span[1]) / 2
    ch, _ = cam.hv(np.array([0.0, yc, 0.0]))
    _, vc = cam.hv(np.array(model.contacts))
    v_bot = vc.min()
    ppm = cam.ppm
    half = max(ch - h.min(), h.max() - ch) + 2.0 / ppm
    W = 2 * int(math.ceil(half * ppm))
    H = int(math.ceil((v.max() - v_bot) * ppm)) + 2
    cam.h0 = ch - W / (2 * ppm)
    cam.v_top = v_bot + H / ppm
    cam.size = (W, H)
    return cam


def crop_bb(img, pad=BB_PAD):
    """Cắt sát (lề [pad] px) giữ nguyên tâm ngang (cắt đều hai bên) và mép
    dưới (điểm chạm đất). Trả về (ảnh, số px đã cắt bên trái, phía trên)."""
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > 0)
    W, H = img.size
    left, right = xs.min(), W - 1 - xs.max()
    cut = max(0, min(left, right) - pad)
    top = max(0, ys.min() - pad)
    return img.crop((cut, top, W - cut, H)), cut, top


def lamp_points(lamp, alpha, ss, which, x_mid, single):
    """Trọng tâm các mẫu mang nhãn đèn [which] (trái / phải tâm ảnh)."""
    m = (lamp == which) & (alpha > 0.5)
    ys, xs = np.nonzero(m)
    if xs.size == 0:
        return []
    fx, fy = (xs + 0.5) / ss, (ys + 0.5) / ss
    if single:
        return [[float(fx.mean()), float(fy.mean())]]
    out = []
    for sel in (fx < x_mid, fx >= x_mid):
        if sel.sum() > 3:
            out.append([float(fx[sel].mean()), float(fy[sel].mean())])
    return out


def shoot(model, kind):
    """Chụp một hướng nhìn → (ảnh PIL đã cắt, thông tin neo / đèn)."""
    cam = frame_for(OrthoCam.view(kind), model)
    with sun_from(key_light(cam)):
        if model.layers is not None:
            rgb, alpha, depth, lamp = model.layers(cam)
        else:
            rgb, alpha, depth, lamp = render_cam(model.scene, cam, ss=SS)
    img = finish_v(rgb, alpha, *cam.size, SS)
    W0 = cam.size[0]
    img, cut, top = crop_bb(img)
    info = {'w': img.size[0], 'h': img.size[1]}
    if kind in ('rear', 'front'):
        single = model.kind == 'moto'
        pts = lamp_points(lamp, alpha, SS, LAMP_TAIL if kind == 'rear' else LAMP_HEAD, W0 / 2, single)
        info['lamps'] = [[round(px - cut, 1), round(py - top, 1)] for px, py in pts]
    # điểm đất ngay dưới tâm xe (y giữa chiều dài, x = 0)
    yc = (model.y_span[0] + model.y_span[1]) / 2
    gx, gy = cam.project((0.0, yc, 0.0))
    info['center_ground'] = [round(gx - cut, 1), round(gy - top, 1)]
    return img, info


def save_billboards(model, base, out, meta, lamps):
    t0 = time.time()
    entry = {}
    lamp_entry = {}
    for kind in ('rear', 'front', 'side'):
        img, info = shoot(model, kind)
        img.save(f'{out}/{base}_{kind}.png', optimize=True)
        if 'lamps' in info:
            lamp_entry[kind] = info.pop('lamps')
        entry[kind] = info
    entry['length_m'] = round(model.y_span[1] - model.y_span[0], 3)
    entry['width_m'] = round(2 * model.half_w, 3)
    meta[base] = entry
    lamps[base] = lamp_entry
    print(f'{base}: {time.time() - t0:.1f}s  ' + '  '.join(f'{k} {entry[k]["w"]}x{entry[k]["h"]}' for k in ('rear', 'front', 'side')))


def car_model(scene, spec, half_w, y_span=None):
    contacts = [(s * (spec.track + spec.hw), ya, 0.0) for ya in spec.axles for s in (-1, 1)]
    return Model(scene, contacts, y_span or (0.0, spec.L), half_w, 'car')


def front_face(idx, ax, z, front, y, lamp, grille, intake, fog, lip_z, logo=None, bars=0.03):
    """Mặt trước chung: đèn pha (c, half, góc, bo), lưới (z0, z1, nửa rộng
    trên, độ thu), hốc gió dưới (z0, z1, nửa rộng), đèn gầm (|x|, z)."""
    (c, half, ang, r) = lamp
    head = front & rrect_in(ax, z, c, half, ang, r)
    idx[head] = HEAD_I
    inner = head & (_rr(ax, z, (c[0] - half[0] * 0.25, c[1]), (half[0] * 0.55, half[1] * 0.62), ang, r * 0.8) < 0)
    idx[inner] = HEADIN_I
    idx[inner & (length2(ax - (c[0] - half[0] * 0.35), z - c[1] + 0.005) < half[1] * 0.5)] = HEAD_I
    drl = head & (np.abs(_rr(ax, z, c, half, ang, r) + 0.009) < 0.0065) & (rot(ax - c[0], z - c[1], -ang)[1] < 0)
    idx[drl] = DRL_I
    g0, g1, gw, gk = grille
    g = front & (z > g0) & (z < g1) & (ax < gw - gk * (g1 - z))
    idx[g] = TRIM_I
    if bars:
        idx[g & (np.abs(((z - g0) % bars) - bars / 2) < 0.0045)] = CHROME_I
    idx[g & (z > g1 - 0.014)] = CHROME_I
    if logo:
        idx[front & (((ax / logo[1]) ** 2 + ((z - logo[0]) / (logo[1] * 0.65)) ** 2) < 1)] = CHROME_I
    i0, i1, iw = intake
    idx[front & (z > i0) & (z < i1) & (ax < iw - 0.4 * (i1 - z))] = DEEP_I
    fx, fz = fog
    fb = front & (((ax - fx) / 0.078) ** 2 + ((z - fz) / 0.046) ** 2 < 1)
    idx[fb] = TRIM_I
    idx[fb & (length2(ax - fx, z - fz) < 0.026)] = FOG_I
    idx[front & (z < lip_z)] = TRIM_I
    return idx


def grille_tint(x, z, idx, out):
    deep = idx == DEEP_I
    hexs = (np.sin(x * 160) * np.sin(z * 160 + 0.5 * np.sin(x * 160)) > 0.35)
    return np.where((deep & hexs)[:, None], lin((30, 30, 32)), out)


# ------------------------------------------------- MPV 7 chỗ (Innova / Xpander)
MPV_V = CarSpec(L=4.50, axles=(0.90, 3.62), R=0.330, track=0.772, hw=0.100, rim_r=0.205, arch_r=0.405, arch_z=0.345,
                arch_in=0.57, belt=tr.MPV.belt, spokes=6)


def mpv_pick_v(p, n):
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    idx = tr.mpv_pick(p, n)
    L = MPV_V.L
    glass = (idx == GLASS_I) | (idx == FRIT_I)
    front = (y < 0.80) & (nz < 0.62) & ~glass
    rear = (y > L - 0.45) & (nz < 0.62) & ~glass & (z < MPV_V.belt + 0.06)
    tails = (idx == TAIL_I) | (idx == TAILIN_I)
    idx[front & (idx != PAINT_I)] = PAINT_I
    idx[rear & (idx != PAINT_I) & ~tails] = PAINT_I
    idx = front_face(idx, ax, z, front & (y < 0.6), y, ((0.625, 0.705), (0.205, 0.062), 0.10, 0.035),
                     (0.53, 0.735, 0.43, 0.25), (0.25, 0.372, 0.52), (0.68, 0.31), 0.235, logo=(0.64, 0.05), bars=0.034)
    # đuôi: đèn hậu đứng dọc cột D (giữ của ảnh từ trên), thêm đèn lùi, phản quang
    idx[rear & tails & (z < 0.92)] = REVERSE_I
    idx[rear & (z < 0.33) & (ax < 0.80)] = TRIM_I
    idx[rear & (ax > 0.55) & (ax < 0.74) & (np.abs(z - 0.43) < 0.014)] = REFLECT_I
    # kính hậu đứng của cửa hậu (mô hình cũ chỉ vẽ phần thấy từ trên)
    hatch = (y > 4.30) & (ny > 0.35) & (z > 1.0)
    idx[hatch & (idx != TAIL_I) & (idx != TAILIN_I)] = PAINT_I
    rw = hatch & (z > 1.10) & (z < 1.66) & (ax < 0.585 - 0.10 * (z - 1.10))
    idx[rw] = FRIT_I
    idx[rw & (z > 1.14) & (z < 1.62) & (ax < 0.55 - 0.10 * (z - 1.10))] = GLASS_I
    idx[hatch & (z > 1.635) & (z < 1.66) & (ax < 0.16)] = STOP_I
    idx[rear & (np.abs(z - 1.10) < 0.013) & (ax < 0.45)] = CHROME_I
    side = (np.abs(nx) > 0.45) & ~glass & (z < MPV_V.belt + 0.02)
    idx[side & (z < 0.275) & (y > 0.4) & (y < L - 0.4)] = TRIM_I
    idx[(np.abs(nx) > 0.45) & (y > 1.40) & (y < 4.25) & (z > MPV_V.belt - 0.004) & (z < MPV_V.belt + 0.012) & ~glass] = CHROME_I
    idx[MPV_V.well(y, z) & (ax < 0.90) & (z < MPV_V.arch_z + MPV_V.arch_r + 0.01)] = WELL_I
    return idx


def mpv_tint_v(p, n, alb, idx):
    x, y, z = p
    ax = np.abs(x)
    nx, ny, nz = n
    out = tr.body_lines((0.30, 1.10), 0.68)(p, n, alb, idx)
    paint_ = idx == PAINT_I
    side = (np.abs(nx) > 0.45) & paint_
    belt = MPV_V.belt
    dl = door_lines(y, z, [(1.40, 0.275, belt), (2.30, 0.275, belt), (3.33, 0.66, belt)],
                    [(3.62, 0.345, 0.435, 1.75, 3.1416)])
    dl |= line_mask(z - 0.279) & (y > 1.40) & (y < 3.20)
    fuel = (x < 0) & line_mask(length2(y - 3.98, z - 0.90) - 0.068, 0.005)
    rear = (ny > 0.4) & paint_
    hatch = rear & ((line_mask(ax - 0.62) & (z > 0.62)) | (line_mask(z - 0.62) & (ax < 0.62)))
    m = (side & (dl | fuel)) | hatch
    out = np.where(m[:, None], out * 0.35, out)
    return grille_tint(x, z, idx, out)


def mpv_v(color, metal=0.55, shirt=(92, 104, 122), plate=('30H-571.08',)):
    S = MPV_V
    body = S.body(tr.MPV.body)
    pt = paint(color, metal=metal)
    mats = car_mats_v(color, metal)
    parts = [Obj('body', body, mats, pick=mpv_pick_v, tint=mpv_tint_v),
             Obj('mirrors', tr.door_mirror(0.965, 1.28, 1.13), [pt, Mat((20, 21, 22), rough=0.45), mats[MGLASS_I]],
                 pick=car_mirror_pick(1.10)),
             Obj('wipers', tr.wipers(tr.MPV, 1.20), Mat((16, 16, 18), rough=0.4)),
             Obj('rails', tr.roof_rails(tr.MPV, 0.56, 1.98, 4.12), [Mat((30, 30, 32), rough=0.35, spec=0.6), ALU],
                 pick=lambda p, n: (p[2] > tr.MPV.ROOF(p[1]) + 0.045).astype(np.int32)),
             Obj('antenna', lambda p: ellipsoid(p, (0, 4.02, 1.75), (0.03, 0.09, 0.04)),
                 Mat((14, 14, 16), rough=0.15, spec=0.8, coat=1.0))]
    parts += S.wheels()
    parts += door_handles(tr.MPV.body, (2.15, 3.18), 0.955, pt)
    parts.append(plate_on(tr.MPV.body, 0.0, 0.70, 1, (0.26, 0.055), plate, 'plate_r', 5.2))
    parts.append(plate_on(tr.MPV.body, 0.0, 0.44, -1, (0.26, 0.055), plate, 'plate_f', -0.8))
    interior = tr.shifted(v3.car_interior(shirt=shirt), dy=-0.30, dz=0.17)
    return Scene(parts, ((-1.12, -0.12, 0.0), (1.12, 4.62, 1.90)), BB_PPM, (0, 0), (1, 1), ao_scale=1.6,
                 interior=interior, glass_tint=(0.30, 0.33, 0.36))


# --------------------------------------------- Bán tải cabin kép (kiểu Ranger)
PU_V = CarSpec(L=5.28, axles=(0.98, 4.17), R=0.385, track=0.80, hw=0.128, rim_r=0.215, arch_r=0.455, arch_z=0.42,
               arch_in=0.60, belt=tr.PU.belt, spokes=6)


def pu_body_v(p):
    """Thân bán tải (như tr.pu_body nhưng khoang kính chặn trước cột A) nâng
    gầm: sườn cabin cao 0,44 m, thùng 0,58 m, cản trước 0,38 m."""
    x, y, z = p
    P = tr.PU
    b = smin(P.lower(p), smax(P.green(p), 1.22 - y, 0.04), 0.035)
    y0, y1 = tr.PU_BED
    inner = rbox(p, (0, (y0 + y1) / 2, 1.40), (0.862, (y1 - y0) / 2, 0.62), 0.03)
    b = smax(b, -inner, 0.015)
    well = rbox((np.abs(x), y, z), (0.80, tr.PU_WELL_Y, 0.80), (0.12, 0.42, 0.22), 0.08)
    b = np.minimum(b, smax(well, np.abs(x) - 0.866, 0.01))
    floor = 0.44 + 0.14 * smoothstep(3.30, 3.50, y) - 0.06 * smoothstep(0.55, 0.25, y)
    return smax(b, floor - z, 0.03)


def pu_pick_v(p, n):
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    idx = tr.pu_pick(p, n)
    L = PU_V.L
    glass = (idx == GLASS_I) | (idx == FRIT_I)
    front = (y < 0.70) & (nz < 0.62) & ~glass
    idx[front & (idx != PAINT_I)] = PAINT_I
    idx = front_face(idx, ax, z, front & (y < 0.6), y, ((0.70, 0.905), (0.19, 0.062), 0.06, 0.03),
                     (0.66, 0.96, 0.56, 0.20), (0.43, 0.53, 0.50), (0.74, 0.56), 0.41, logo=(0.84, 0.06), bars=0.07)
    rear = (y > L - 0.10) & (ny > 0.3) & ~glass
    tails = (idx == TAIL_I)
    idx[rear & ~tails & (idx != LINER_I)] = PAINT_I
    tl = (y > L - 0.22) & (ax > 0.715) & (z > 0.80) & (z < 1.185) & (ny > -0.2) & ~glass
    idx[tl] = TAIL_I
    idx[tl & (np.abs(z - 0.99) < 0.012)] = TAILIN_I
    idx[tl & (z < 0.90)] = REVERSE_I
    idx[tl & (z > 1.09)] = AMBER_I
    idx[rear & (np.abs(z - 1.10) < 0.035) & (ax < 0.13)] = TRIM_I
    side = (np.abs(nx) > 0.45) & ~glass & (z < PU_V.belt + 0.02)
    idx[side & (z < 0.50) & (y > 0.4) & (y < 3.40)] = TRIM_I
    idx[PU_V.well(y, z) & (ax < 0.95) & (z < PU_V.arch_z + PU_V.arch_r + 0.01)] = WELL_I
    return idx


def pu_tint_v(p, n, alb, idx):
    x, y, z = p
    ax = np.abs(x)
    nx, ny, nz = n
    out = tr.body_lines((0.25, 1.40), 0.70)(p, n, alb, idx)
    paint_ = idx == PAINT_I
    side = (np.abs(nx) > 0.45) & paint_
    belt = PU_V.belt
    dl = door_lines(y, z, [(1.55, 0.50, belt), (2.38, 0.50, belt), (3.22, 0.50, belt), (3.40, 0.58, belt)])
    fuel = (x < 0) & line_mask(length2(y - 3.78, z - 1.00) - 0.07, 0.005)
    rear = (ny > 0.4) & paint_ & (y > PU_V.L - 0.1)
    gate = rear & (line_mask(z - 0.66) | (line_mask(ax - 0.70) & (z > 0.66)))
    m = (side & (dl | fuel)) | gate
    out = np.where(m[:, None], out * 0.35, out)
    return grille_tint(x, z, idx, out)


def pu_under(color_mat):
    """Gầm bán tải: khung xương, bậc lên xuống, cản sau có bậc, lốp dự phòng
    treo dưới thùng, vi sai cầu sau, bình nhiên liệu."""
    frame_m = Mat((24, 24, 26), rough=0.6, metal=0.3)
    objs = []

    def frame(p):
        q = (np.abs(p[0]), p[1], p[2])
        rail = rbox(q, (0.47, 2.75, 0.50), (0.04, 2.35, 0.08), 0.01)
        cross = rbox(p, (0, 2.3, 0.48), (0.47, 0.04, 0.04), 0.01)
        cross2 = rbox(p, (0, 3.6, 0.50), (0.47, 0.04, 0.04), 0.01)
        tank = rbox(p, (-0.18, 3.0, 0.45), (0.26, 0.42, 0.10), 0.04)
        return np.minimum(np.minimum(rail, cross), np.minimum(cross2, tank))
    objs.append(Obj('frame', frame, frame_m))

    def axle(p):
        diff = ellipsoid(p, (0.0, PU_V.axles[1], PU_V.R), (0.15, 0.13, 0.13))
        tube = capsule(p, (-0.70, PU_V.axles[1], PU_V.R), (0.70, PU_V.axles[1], PU_V.R), 0.045)
        fr = capsule(p, (-0.62, PU_V.axles[0], PU_V.R + 0.02), (0.62, PU_V.axles[0], PU_V.R + 0.02), 0.04)
        return np.minimum(smin(diff, tube, 0.03), fr)
    objs.append(Obj('axles', axle, DARK_METAL))

    def steps(p):
        q = (np.abs(p[0]), p[1], p[2])
        return rbox(q, (0.86, 2.38, 0.40), (0.085, 0.86, 0.025), 0.012)

    def steps_pick(p, n):
        return ((n[2] > 0.7) & (np.sin(p[1] * 90) > 0.3)).astype(np.int32)
    objs.append(Obj('steps', steps, [Mat((150, 152, 156), rough=0.3, metal=0.8), Mat((26, 26, 28), rough=0.7)],
                    pick=steps_pick))

    def bumper(p):
        main = rbox(p, (0, PU_V.L + 0.06, 0.53), (0.86, 0.075, 0.085), 0.03)
        stepc = rbox(p, (0, PU_V.L + 0.10, 0.60), (0.20, 0.07, 0.012), 0.008)
        hitch = rbox(p, (0, PU_V.L + 0.10, 0.415), (0.035, 0.10, 0.035), 0.005)
        return np.minimum(np.minimum(main, stepc), hitch)

    def bumper_pick(p, n):
        x, y, z = p
        top = (n[2] > 0.7) & (np.abs(x) < 0.20)
        return np.where(top | (z < 0.44), 1, 0).astype(np.int32)
    objs.append(Obj('bumper_r', bumper, [CHROME, Mat((24, 24, 26), rough=0.7)], pick=bumper_pick))
    # lốp dự phòng nằm ngang dưới thùng (trục đứng)
    objs.append(Obj('spare', lambda p: v3.tyre((p[2], p[1], p[0]), (0.31, 4.92, 0.0), 0.36, 0.13, 0.105, 0.035), TYRE))
    skid = Obj('skid', lambda p: rbox(p, (0, 0.30, 0.37), (0.48, 0.30, 0.02), 0.015), Mat((140, 142, 146), rough=0.35, metal=0.8))
    objs.append(skid)
    return objs


def pu_v(color, cargo=None, metal=0.55, shirt=(92, 104, 122), seed=5, plate=('60C-224.91',)):
    S = PU_V
    body = S.body(pu_body_v)
    pt = paint(color, metal=metal)
    mats = car_mats_v(color, metal)
    ex = tr.pu_extras()
    ex[0] = Obj('mirrors', tr.door_mirror(1.0, 1.55, 1.27), [Mat((26, 27, 29), rough=0.35, spec=0.6), Mat((20, 21, 22), rough=0.45),
                                                            mats[MGLASS_I]], pick=car_mirror_pick(1.24))
    parts = [Obj('body', body, mats, pick=pu_pick_v, bump=tr.pu_bump, tint=pu_tint_v)] + ex
    parts += S.wheels()
    parts += door_handles(pu_body_v, (2.22, 3.05), 1.06, pt)
    parts += pu_under(pt)
    parts.append(plate_on(pu_body_v, 0.0, 0.53, -1, (0.26, 0.055), plate, 'plate_f', -0.8))
    parts.append(plate_on(pu_body_v, 0.0, 0.77, 1, (0.165, 0.0825), ('60C', '224.91'), 'plate_r', 6.0))
    yc = (tr.PU_BED[0] + tr.PU_BED[1]) / 2
    if cargo == 'kumquat':
        parts += tr.kumquat_parts((0.0, yc, 1.85), (0.62, 0.66, 0.60), seed=seed, fruits=150, lixi=12,
                                  pot=((0.0, yc, 0.80), 0.30, 0.48))
    elif cargo == 'peach':
        parts += tr.peach_parts((0.0, yc, 1.10), (0.86, 0.80, 0.80), 1.25, seed=seed, branches=13, blossom=2.6, bloom=1.45)
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
    interior = tr.shifted(v3.car_interior(shirt=shirt), dy=0.0, dz=0.27)
    return Scene(parts, ((-1.18, -0.12, 0.0), (1.18, 5.50, 2.55)), BB_PPM, (0, 0), (1, 1), ao_scale=1.6,
                 interior=interior, glass_tint=(0.30, 0.33, 0.36))


# ============================================================== Xe khách
# Xe khách 8,5 m (cùng thân xe khách người chơi): trục trước 1,95 m, trục sau
# 6,15 m bánh đôi, lốp 8.25-16. Ảnh từ trên chỉ có nóc nên ở đây thêm dải kính
# hông (thấy ghế, rèm bên trong), cửa khoang hành lý, sơn sọc thân, đèn, lưới
# tản nhiệt, bảng điện tử tuyến đường, cụm đèn hậu, lưới khoang máy sau.
BUS_AXLES = (1.95, 6.15)
BUS_R = 0.435
(B_PAINT, B_GLASS, B_FRIT, B_STRIPE, B_WHITE, B_LAMP, B_RLAMP, B_TRIM, B_HEAD, B_HEADIN, B_TAIL, B_REV, B_AMBER,
 B_CHROME, B_DEEP, B_WELL, B_LED, B_FOG, B_DRL) = range(19)


def bus_mats_v(main, stripe, metal):
    pt = paint(main, metal=metal)
    return [pt,
            Mat((10, 11, 12), rough=0.03, glass=1.0, spec=1.0),
            Mat((12, 12, 13), rough=0.12, spec=1.0, coat=0.8),
            paint(stripe),
            paint((236, 236, 232), rough=0.5),
            Mat((250, 160, 30), rough=0.05, coat=1.0, emit=0.3),
            Mat((210, 30, 26), rough=0.05, coat=1.0, emit=0.3),
            Mat((34, 35, 37), rough=0.5, spec=0.5),
            tagged(Mat((200, 206, 212), rough=0.04, metal=0.75, coat=1.0), 'head'),
            tagged(Mat((26, 28, 32), rough=0.15, metal=0.5, coat=1.0), 'head'),
            tagged(Mat((205, 24, 26), rough=0.05, spec=1.2, coat=1.0, emit=0.45), 'tail'),
            Mat((215, 218, 222), rough=0.05, metal=0.4, coat=1.0),
            Mat((235, 130, 20), rough=0.08, spec=1.2, coat=0.8, emit=0.1),
            CHROME,
            Mat((7, 7, 8), rough=0.7, spec=0.3),
            Mat((20, 20, 22), rough=0.85, spec=0.3),
            Mat((12, 10, 8), rough=0.2, spec=0.6, coat=0.8),
            Mat((228, 230, 234), rough=0.05, coat=1.0, emit=0.08),
            tagged(Mat((240, 244, 250), rough=0.05, coat=1.0, emit=0.6), 'head')]


# Thân xe khách cho ảnh đứng: đường cong độ cao của ảnh từ trên dựng đứng ở
# mũi và rơi thẳng sau đuôi — làm hàm khoảng cách ước lượng quá xa trước mũi
# xe và gãy khúc ngay mặt sau (nhìn từ trên không lộ). Ở đây mặt trước là mặt
# nghiêng y = yf(z) (hơi ngả về sau như kính lái xe khách), nóc phẳng bo xuống
# đuôi, mặt đuôi phẳng đứng y = 8,5.
BUS_ROOF_V = v3.Curve([(6.5, 3.32), (7.2, 3.32), (7.6, 3.32), (7.9, 3.315), (8.15, 3.29), (8.35, 3.22), (8.55, 3.08),
                       (8.75, 2.86), (8.95, 2.6)])


def bus_body_v(p):
    x, y, z = p
    ax = np.abs(x)
    yf = 0.065 + 0.02 * z + 0.025 * z * z
    d_front = (yf - y) / np.sqrt(1 + (0.02 + 0.05 * z) ** 2)
    plan = smax(smax(ax - v3.BUS_W, d_front, 0.55), y - v3.BUS_L, 0.45)
    hy = BUS_ROOF_V.d(y)
    d_top = (z - BUS_ROOF_V(y) + 0.05 * (ax / v3.BUS_W) ** 2) / np.sqrt(1 + hy * hy)
    d = smax(smax(plan, d_top, 0.34), 0.35 - z, 0.05)
    for ya in BUS_AXLES:
        cyl = length2(y - ya, z - 0.46) - 0.545
        d = smax(d, -smax(cyl, 0.72 - ax, 0.03), 0.025)
    return d


LED_TEX = None


def bus_pick_v(p, n):
    x, y, z = p
    nx, ny, nz = n
    ax = np.abs(x)
    idx = v3.bus_pick(p, n)
    W = v3.BUS_W
    side = np.abs(nx) > 0.55
    front = (ny < -0.3) & (y < 0.6)
    rear = (ny > 0.3) & (y > 8.2)
    # ---- dải kính hông, cột kính đen, ô kính tài xế
    band = side & (z > 1.60) & (z < 2.78) & (y > 1.62) & (y < 8.20)
    idx[band] = B_FRIT
    yk = (y - 1.62) % 1.098
    idx[band & (z > 1.645) & (z < 2.74) & (yk > 0.045) & (yk < 1.053) & (y < 8.14)] = B_GLASS
    drv = side & (y > 0.30 + 0.12 * (z - 1.2)) & (y < 1.50) & (z > 1.22) & (z < 2.80)
    idx[drv] = B_FRIT
    idx[drv & (y > 0.34 + 0.12 * (z - 1.2)) & (y < 1.46) & (z > 1.26) & (z < 2.76)] = B_GLASS
    idx[side & (z < 0.47)] = B_TRIM
    idx[side & (z < 0.62) & (np.abs(((y - 0.8) % 1.6) - 0.8) < 0.035) & (np.abs(z - 0.54) < 0.03)] = B_AMBER
    for ya in BUS_AXLES:
        idx[(length2(y - ya, z - 0.46) < 0.55) & (ax < W - 0.01)] = B_WELL
    # ---- đầu xe
    f = front & (z < 1.10)
    idx[f] = B_PAINT
    hl = ((0.92, 0.74), (0.21, 0.085), 0.0, 0.03)
    head = f & rrect_in(ax, z, *hl)
    idx[head] = B_TRIM
    idx[head & ((length2(ax - 0.80, z - 0.75) < 0.05) | (length2(ax - 0.93, z - 0.75) < 0.05))] = B_HEADIN
    idx[head & ((length2(ax - 0.80, z - 0.75) < 0.032) | (length2(ax - 0.93, z - 0.75) < 0.032))] = B_HEAD
    idx[head & (ax > 1.04)] = B_AMBER
    idx[head & (np.abs(z - 0.672) < 0.010) & (ax < 1.04)] = B_DRL
    g = f & (ax < 0.62) & (z > 0.62) & (z < 1.00)
    idx[g] = B_TRIM
    idx[g & (np.abs(((z - 0.62) % 0.055) - 0.0275) < 0.008)] = B_CHROME
    idx[f & (((ax / 0.07) ** 2 + ((z - 1.04) / 0.035) ** 2) < 1)] = B_CHROME
    idx[f & (z < 0.585)] = B_TRIM
    fog = f & (length2(ax - 0.95, z - 0.46) < 0.045)
    idx[fog] = B_FOG
    # bảng điện tử tuyến đường trên kính lái
    idx[front & (z > 2.80) & (z < 3.02) & (ax < 0.86)] = B_LED
    # ---- đuôi xe
    r = rear & (z < 2.12)
    idx[r] = B_PAINT
    lamp = r & (ax > 0.92) & (ax < 1.20) & (z > 0.66) & (z < 1.58)
    idx[lamp] = B_TRIM
    for zc, m in ((1.46, B_TAIL), (1.24, B_AMBER), (1.02, B_TAIL), (0.80, B_REV)):
        idx[lamp & (length2(ax - 1.06, z - zc) < 0.072)] = m
    grill = r & (ax < 0.72) & (z > 0.98) & (z < 1.86)
    idx[grill] = B_DEEP
    idx[grill & (np.abs(((z - 0.98) % 0.06) - 0.03) < 0.012)] = B_TRIM
    idx[r & (z < 0.585)] = B_TRIM
    return idx


def bus_tint_v(p, n, alb, idx):
    x, y, z = p
    nx, ny, nz = n
    out = v3.bus_tint(p, n, alb, idx)
    side = (np.abs(nx) > 0.55) & ((idx == B_PAINT) | (idx == B_STRIPE))
    # sọc thân xe màu phụ: dải chính chạy dốc lên về đuôi + chỉ mảnh
    zc = 0.92 + 0.07 * (y - 0.4)
    s1 = np.abs(z - zc) < 0.11 - 0.006 * y
    s2 = np.abs(z - zc - 0.24) < 0.03
    s3 = np.abs(z - 1.50) < 0.035
    stripe = side & (s1 | s2 | s3) & (z > 0.5) & (z < 1.58)
    out = np.where(stripe[:, None], lin(BUS_STRIPE_NOW[0]) * 0.92, out)
    # cửa khoang hành lý giữa hai trục
    bays = np.zeros(z.shape, bool)
    for y0, y1 in ((2.62, 3.72), (3.80, 4.90), (4.98, 5.50)):
        inside = (y > y0) & (y < y1) & (z > 0.52) & (z < 1.40)
        edge = inside & ((np.abs(y - y0) < 0.007) | (np.abs(y - y1) < 0.007) | (np.abs(z - 0.52) < 0.007) | (np.abs(z - 1.40) < 0.007))
        handle = inside & (np.abs(y - (y0 + y1) / 2) < 0.07) & (np.abs(z - 0.62) < 0.012)
        bays |= edge | handle
    out = np.where((side & bays)[:, None], out * 0.35, out)
    # đường ghép tấm hông, vạch ron cửa tài xế
    seam = side & ((np.abs(z - 1.565) < 0.005) | ((np.abs(y - 1.52) < 0.006) & (z > 0.6) & (z < 2.8)))
    out = np.where(seam[:, None], out * 0.5, out)
    led = idx == B_LED
    if led.any():
        u = (0.86 - x) / 1.72
        v = (3.02 - z) / 0.22
        ink = sample_tex(LED_TEX, u, v)
        out = np.where(led[:, None], lin((12, 10, 8)) + lin((255, 150, 30)) * (ink * 3.0)[:, None], out)
    return out


BUS_STRIPE_NOW = [(200, 36, 32)]


def bus_interior_v(shirt=(70, 80, 100)):
    """Khoang khách: táp-lô, tài xế + vô-lăng, hàng ghế bọc áo trắng, rèm
    cửa sổ, giá hành lý trên trần, sàn."""
    dash = Mat((40, 40, 42), rough=0.6)
    seat = Mat((60, 52, 50), rough=0.7, sheen=0.3)
    cover = fabric((226, 226, 220))
    objs = [Obj('dash', lambda p: rbox(p, (0, 0.55, 0.95), (1.15, 0.45, 0.25), 0.1), dash),
            Obj('floor', lambda p: rbox(p, (0, 4.3, 0.62), (1.2, 4.1, 0.05), 0.04), Mat((50, 50, 52), rough=0.9))]

    def wheel(p):
        x, y, z = p
        y2, z2 = rot(y - 1.12, z - 1.42, -0.55)
        return length2(length2(x + 0.70, y2) - 0.24, z2) - 0.02
    objs.append(Obj('wheel', wheel, Mat((24, 24, 26), rough=0.4)))
    objs.append(Obj('dseat', lambda p: rbox(p, (-0.70, 1.62, 1.15), (0.28, 0.3, 0.42), 0.12), seat))

    def driver(p):
        x, y, z = p
        q = (x + 0.70, y, z)
        torso = round_cone((q[0] / 1.5, q[1], q[2]), (0, 1.55, 1.05), (0, 1.50, 1.62), 0.13, 0.12)
        arms = mirror_x(lambda r: round_cone(r, (0.19, 1.50, 1.62), (0.22, 1.18, 1.46), 0.05, 0.04))(q)
        return smin(torso, arms, 0.04)
    objs.append(Obj('driver', driver, fabric(shirt)))
    objs.append(Obj('dhead', lambda p: ellipsoid(p, (-0.70, 1.48, 1.86), (0.085, 0.10, 0.11)), Mat((26, 22, 20), rough=0.5, sheen=0.5)))

    def seats(p):
        x, y, z = p
        ax = np.abs(x)
        k = np.clip(np.round((y - 2.25) / 0.82), 0, 7)
        yy = y - (2.25 + k * 0.82)
        q = (ax - 0.72, yy, z)
        back = rbox(q, (0, 0.18, 1.52), (0.30, 0.07, 0.36), 0.06)
        cush = rbox(q, (0, -0.05, 1.12), (0.30, 0.24, 0.07), 0.05)
        return np.minimum(back, cush)

    def seats_pick(p, n):
        return (p[2] > 1.70).astype(np.int32)
    objs.append(Obj('seats', seats, [seat, cover], pick=seats_pick))

    def curtains(p):
        x, y, z = p
        k = np.round((y - 1.62) / 1.098)
        yy = y - (1.62 + k * 1.098)
        return rbox((np.abs(x), yy, z), (1.16, 0.0, 2.18), (0.03, 0.17, 0.52), 0.02)
    objs.append(Obj('curtains', curtains, fabric((150, 40, 50), sheen=0.6),
                    bump=lambda p, n: (n[0], n[1] + 0.5 * np.sin(p[1] * 120), n[2])))
    objs.append(Obj('racks', lambda p: rbox((np.abs(p[0]), p[1], p[2]), (0.95, 5.0, 2.80), (0.22, 3.1, 0.06), 0.03), dash))
    return objs


def bus_v(main, stripe, metal=0.12, plate=('51B-268.79',), route='SAI GON - NHA TRANG'):
    global LED_TEX
    LED_TEX = text_tex([route], (1720, 220), squeeze=0.62, border=False)
    BUS_STRIPE_NOW[0] = stripe
    mats = bus_mats_v(main, stripe, metal)
    acw = Mat((176, 180, 184), rough=0.55, coat=0.25, spec=0.3)
    parts = [Obj('body', bus_body_v, mats, pick=bus_pick_v, tint=bus_tint_v),
             Obj('ac', lambda p: smax(v3.ac_unit(p), 3.05 - p[2], 0.02), [acw, Mat((150, 154, 158), rough=0.5), Mat((40, 42, 44), rough=0.5, metal=0.3)],
                 pick=v3.ac_pick, tint=v3.ac_tint),
             Obj('hatches', v3.bus_hatches, [Mat((200, 202, 204), rough=0.4), Mat((70, 76, 82), rough=0.15, coat=1.0)],
                 pick=v3.bus_hatch_pick),
             Obj('mirrors', v3.bus_mirrors, [Mat((22, 22, 24), rough=0.35, spec=0.6), Mat((70, 78, 88), rough=0.02, metal=1.0)],
                 pick=lambda p, n: ((n[1] > 0.6) & (p[2] < 2.55) & (p[2] > 1.95)).astype(np.int32)),
             Obj('wipers', v3.bus_wipers, Mat((16, 16, 18), rough=0.4))]
    for i, ya in enumerate(BUS_AXLES):
        for s in (-1, 1):
            parts += wheel_objs(f'w{i}{s}', ya, BUS_R, s * (1.02 if i == 0 else 1.05), 0.115, 0.255, style='steel')
            if i == 1:
                parts.append(Obj(f'w{i}{s}_in', lambda p, s=s: v3.tyre(p, (s * 0.78, ya, BUS_R), BUS_R, 0.2, 0.11, 0.04), TYRE))
    t = surface_along(bus_body_v, (0.0, 9.5, 0.72), (0, -1, 0), tmax=3)
    parts.append(plate_obj('plate_r', (0.0, 9.5 - t + 0.012, 0.72), (0.26, 0.055), 1, plate))
    t = surface_along(bus_body_v, (0.0, -1.0, 0.46), (0, 1, 0), tmax=3)
    parts.append(plate_obj('plate_f', (0.0, -1.0 + t - 0.012, 0.46), (0.26, 0.055), -1, plate))
    sc = Scene(parts, ((-1.42, -0.35, 0.0), (1.42, 8.75, 3.62)), BB_PPM, (0, 0), (1, 1), ao_scale=2.4,
               interior=bus_interior_v(), glass_tint=(0.36, 0.39, 0.42))
    contacts = [(s * (1.05 + 0.115), ya, 0.0) for ya in BUS_AXLES for s in (-1, 1)]
    return Model(sc, contacts, (0.0, v3.BUS_L), v3.BUS_W, 'bus')


# =============================================================== Xe tải
# Xe tải cabin lật (cùng mô hình build_traffic_3d): thêm bánh xe 8.25R20 (trục
# trước dưới cabin, trục sau bánh đôi), lưới tản nhiệt, đèn, cản thép, cửa
# cabin có kính, khung gầm, bình dầu, khung chắn hông, cản sau sơn phản quang,
# chắn bùn cao su, đèn hậu trên dầm sau và số đăng ký kẻ to trên thành sau.
TRUCK_AXLES = (0.98, 5.95)
TRUCK_R = 0.47
(T_PAINT, T_GLASS, T_FRIT, T_LAMP, T_TRIM, T_HEAD, T_HEADIN, T_AMBER, T_CHROME, T_DEEP, T_WELL) = range(11)


def truck_cab_v(color, visor=False, length=1.95, height=2.72, w=1.13):
    pt = paint(color, metal=0.25)
    mats = [pt, Mat((10, 11, 12), rough=0.03, glass=1.0, spec=1.0), Mat((14, 14, 15), rough=0.2, spec=0.8),
            Mat((240, 150, 30), rough=0.08, coat=1.0, emit=0.4), Mat((30, 31, 33), rough=0.5, spec=0.5),
            tagged(Mat((200, 206, 212), rough=0.04, metal=0.75, coat=1.0), 'head'),
            tagged(Mat((26, 28, 32), rough=0.15, metal=0.5, coat=1.0), 'head'),
            Mat((235, 130, 20), rough=0.08, spec=1.2, coat=0.8, emit=0.1), CHROME, Mat((7, 7, 8), rough=0.7, spec=0.3),
            Mat((20, 20, 22), rough=0.85, spec=0.3)]
    base = tr.cab_parts(color, visor=visor, length=length, height=height, w=w)
    cab_sdf = base[0].sdf
    ya = TRUCK_AXLES[0]

    def cab(p):
        x, y, z = p
        d = cab_sdf(p)
        cyl = length2(y - ya, z - 0.47) - 0.565
        return smax(d, -smax(cyl, 0.80 - np.abs(x), 0.03), 0.02)

    def pick(p, n):
        x, y, z = p
        nx, ny, nz = n
        ax = np.abs(x)
        idx = base[0].pick(p, n)
        front = (ny < -0.5) & (z < 1.58)
        idx[front] = T_PAINT
        g = front & (ax < 0.68) & (z > 0.98) & (z < 1.42)
        idx[g] = T_DEEP
        idx[g & (np.abs(((z - 0.98) % 0.055) - 0.0275) < 0.011)] = T_TRIM
        idx[front & (((ax / 0.11) ** 2 + ((z - 1.48) / 0.04) ** 2) < 1)] = T_CHROME
        hl = front & rrect_in(ax, z, (0.86, 0.86), (0.21, 0.09), 0.0, 0.03)
        idx[hl] = T_TRIM
        idx[hl & ((length2(ax - 0.77, z - 0.86) < 0.062) | (length2(ax - 0.93, z - 0.86) < 0.062))] = T_HEADIN
        idx[hl & ((length2(ax - 0.77, z - 0.86) < 0.042) | (length2(ax - 0.93, z - 0.86) < 0.042))] = T_HEAD
        idx[front & (ax > 0.86) & (ax < 1.10) & (z > 1.02) & (z < 1.12)] = T_AMBER
        side = np.abs(nx) > 0.5
        # cửa cabin: ô kính (cạnh trước theo độ ngả kính lái), viền đen
        win = side & (z > 1.62) & (z < 2.46) & (y > 0.30 + 0.17 * (z - 1.45)) & (y < 1.55)
        idx[win] = T_FRIT
        idx[win & (z > 1.66) & (z < 2.42) & (y > 0.34 + 0.17 * (z - 1.45)) & (y < 1.51)] = T_GLASS
        idx[side & (z < 0.62)] = T_TRIM
        idx[(length2(y - ya, z - 0.47) < 0.57) & (ax < w - 0.01) & (z < 1.06)] = T_WELL
        return idx

    def tint(p, n, alb, idx):
        x, y, z = p
        out = base[0].tint(p, n, alb, idx)
        side = (np.abs(n[0]) > 0.5) & (idx == T_PAINT)
        door = (line_mask(y - 0.22 - 0.17 * np.maximum(z - 1.45, 0)) & (z > 1.05) & (z < 2.55)) | \
            (line_mask(y - 1.62) & (z > 0.70) & (z < 2.55)) | (line_mask(z - 2.55) & (y > 0.3) & (y < 1.62))
        handle = (np.abs(y - 1.45) < 0.07) & (np.abs(z - 1.52) < 0.015)
        lower = line_mask(length2(y - ya, z - 0.47) - 0.64) & (z > 0.9)
        return np.where((side & (door | handle | lower))[:, None], out * 0.35, out)
    parts = [Obj('cab', cab, mats, pick=pick, tint=tint)] + base[1:]

    def bumper(p):
        x, y, z = p
        main = rbox(p, (0, -0.04, 0.52), (1.16, 0.10, 0.13), 0.03)
        step = rbox((np.abs(x), y, z), (1.02, 1.70, 0.50), (0.12, 0.16, 0.03), 0.01)
        return np.minimum(main, step)

    def bumper_pick(p, n):
        x, y, z = p
        fog = (length2(np.abs(x) - 0.88, z - 0.52) < 0.045) & (n[1] < -0.5)
        return fog.astype(np.int32)
    parts.append(Obj('bumper_f', bumper, [Mat((60, 62, 66), rough=0.4, metal=0.5), Mat((228, 230, 234), rough=0.05, coat=1.0, emit=0.08)],
                     pick=bumper_pick))
    parts.append(Obj('wipers_t', lambda p: np.minimum(capsule(p, (-1.0, -0.02, 1.62), (-0.10, 0.04, 2.20), 0.018),
                                                       capsule(p, (0.08, -0.02, 1.62), (0.98, 0.04, 2.20), 0.018)),
                     Mat((16, 16, 18), rough=0.4)))
    return parts, cab


def truck_chassis(bed_bottom=1.0):
    """Khung gầm, bình dầu, chắn hông, cản sau phản quang, chắn bùn, đèn hậu."""
    frame_m = Mat((24, 24, 26), rough=0.6, metal=0.3)
    objs = []

    def frame(p):
        q = (np.abs(p[0]), p[1], p[2])
        rail = rbox(q, (0.44, 4.0, 0.86), (0.05, 3.9, 0.12), 0.01)
        cross = rbox(p, (0, 7.80, 0.86), (0.48, 0.05, 0.10), 0.01)
        return np.minimum(rail, cross)
    objs.append(Obj('frame', frame, frame_m))

    def tank(p):
        x, y, z = p
        body = rbox((x + 0.82, y - 2.75, z - 0.74), (0, 0, 0), (0.24, 0.40, 0.22), 0.10)
        batt = rbox(p, (0.86, 2.85, 0.76), (0.20, 0.30, 0.17), 0.02)
        return np.minimum(body, batt)

    def tank_pick(p, n):
        return (p[0] > 0).astype(np.int32)
    objs.append(Obj('tank', tank, [Mat((176, 178, 182), rough=0.3, metal=0.9), Mat((30, 31, 33), rough=0.5)], pick=tank_pick))

    def guard(p):
        q = (np.abs(p[0]), p[1], p[2])
        rails = np.minimum(rbox(q, (1.12, 4.25, 0.58), (0.025, 0.95, 0.045), 0.01),
                           rbox(q, (1.12, 4.25, 0.80), (0.025, 0.95, 0.045), 0.01))
        posts = rbox((q[0], np.abs(q[1] - 4.25), q[2]), (1.04, 0.70, 0.74), (0.08, 0.025, 0.20), 0.01)
        return np.minimum(rails, posts)
    objs.append(Obj('guard', guard, Mat((120, 124, 128), rough=0.45, metal=0.5)))

    def rear_bar(p):
        bar = rbox(p, (0, 7.97, 0.56), (1.10, 0.05, 0.075), 0.015)
        legs = rbox((np.abs(p[0]), p[1], p[2]), (0.55, 7.90, 0.72), (0.04, 0.06, 0.12), 0.01)
        lamps = rbox((np.abs(p[0]), p[1], p[2]), (0.86, 7.98, 0.86), (0.20, 0.045, 0.065), 0.015)
        return np.minimum(np.minimum(bar, legs), lamps)

    def rear_pick(p, n):
        x, y, z = p
        ax = np.abs(x)
        idx = np.zeros(x.shape, np.int32)
        lamp = (z > 0.79) & (n[1] > 0.5)
        idx[lamp] = 1
        idx[lamp & (ax > 0.99)] = 2
        idx[lamp & (ax < 0.735)] = 3
        idx[lamp & (np.abs(z - 0.86) > 0.048)] = 4
        stripe = (z < 0.64) & (n[1] > 0.5) & (np.sin((x + z) * 22) > 0)
        idx[stripe] = 5
        return idx
    objs.append(Obj('rear_bar', rear_bar, [Mat((236, 236, 232), rough=0.35, spec=0.6),
                                           tagged(Mat((205, 24, 26), rough=0.05, spec=1.2, coat=1.0, emit=0.45), 'tail'),
                                           Mat((235, 130, 20), rough=0.08, spec=1.2, coat=0.8, emit=0.1),
                                           Mat((215, 218, 222), rough=0.05, metal=0.4, coat=1.0),
                                           Mat((30, 31, 33), rough=0.5),
                                           Mat((200, 30, 30), rough=0.2, spec=0.8, coat=0.6)], pick=rear_pick))

    def flaps(p):
        q = (np.abs(p[0]), p[1], p[2])
        return rbox(q, (0.86, 6.60, 0.46), (0.27, 0.008, 0.28), 0.005)
    objs.append(Obj('flaps', flaps, Mat((22, 22, 24), rough=0.75, spec=0.3)))
    return objs


def truck_wheels():
    objs = []
    for s in (-1, 1):
        objs += wheel_objs(f'tf{s}', TRUCK_AXLES[0], TRUCK_R, s * 0.98, 0.125, 0.275, style='steel')
        objs += wheel_objs(f'tr{s}', TRUCK_AXLES[1], TRUCK_R, s * 0.99, 0.125, 0.275, style='steel')
        objs.append(Obj(f'tri{s}', lambda p, s=s: v3.tyre(p, (s * 0.71, TRUCK_AXLES[1], TRUCK_R), TRUCK_R, 0.2, 0.12, 0.04), TYRE))
    return objs


def painted_number(name, center, half, lines, facing=1, ink=(20, 20, 22)):
    """Số đăng ký kẻ sơn trên thành sau (chỉ vân, mặt phẳng mỏng sát thành)."""
    cx, cy, cz = center
    hw, hh = half
    tex = text_tex(lines, (hw * 2000, hh * 2000), squeeze=0.85, border=False)

    def sdf(p):
        return rbox(p, center, (hw, 0.002, hh), 0.001)

    def tint(p, n, alb, idx):
        x, y, z = p
        u = (x * facing + hw) / (2 * hw)
        v = (cz + hh - z) / (2 * hh)
        k = sample_tex(tex, u, v)
        return alb * (1 - k)[:, None] + lin(ink) * k[:, None]
    return Obj(name, sdf, Mat((236, 236, 232), rough=0.5, spec=0.4), tint=tint)


def truck_interior(shirt=(60, 90, 140)):
    dash = Mat((40, 40, 42), rough=0.6)
    objs = [Obj('dash', lambda p: rbox(p, (0, 0.38, 1.40), (1.05, 0.22, 0.16), 0.06), dash),
            Obj('back', lambda p: rbox(p, (0, 1.80, 1.80), (1.05, 0.05, 0.75), 0.03), Mat((50, 50, 52), rough=0.8)),
            Obj('seat', lambda p: rbox((np.abs(p[0]) - 0.55, p[1], p[2]), (0, 1.40, 1.55), (0.25, 0.25, 0.40), 0.08),
                Mat((60, 52, 50), rough=0.7))]

    def driver(p):
        q = (p[0] + 0.55, p[1], p[2])
        torso = round_cone((q[0] / 1.5, q[1], q[2]), (0, 1.30, 1.45), (0, 1.25, 1.95), 0.13, 0.12)
        arms = mirror_x(lambda r: round_cone(r, (0.19, 1.25, 1.95), (0.20, 0.80, 1.72), 0.05, 0.04))(q)
        return smin(torso, arms, 0.04)
    objs.append(Obj('driver', driver, fabric(shirt)))
    objs.append(Obj('dhead', lambda p: ellipsoid(p, (-0.55, 1.22, 2.18), (0.085, 0.10, 0.11)), Mat((26, 22, 20), rough=0.5, sheen=0.5)))
    objs.append(Obj('wheel', lambda p: length2(length2(p[0] + 0.55, rot(p[1] - 0.72, p[2] - 1.72, -0.75)[0]) - 0.22,
                                               rot(p[1] - 0.72, p[2] - 1.72, -0.75)[1]) - 0.02, Mat((24, 24, 26), rough=0.4)))
    return objs


def truck_v(kind, plate):
    """kind: 'tarp' (thùng mui bạt), 'box' (thùng kín), 'dump' (xe ben)."""
    num = (plate.split('-')[0], plate.split('-')[1])
    if kind == 'tarp':
        cab, cab_sdf = truck_cab_v((36, 86, 168), visor=True)
        tp = tr.tarp_parts((56, 92, 60))
        tarp = tp[0]
        tsdf = tarp.sdf

        def tarp_pick(p, n):
            return (p[2] < 1.56).astype(np.int32)

        def tarp_tint(p, n, alb, idx):
            out = tp[0].tint(p, n, alb, idx)
            x, y, z = p
            wall = idx == 1
            rib = wall & (np.abs(((y - 2.08) % 0.47) - 0.235) < 0.02) & (np.abs(n[0]) > 0.5)
            rib |= wall & (np.abs(((x + 1.2) % 0.40) - 0.20) < 0.02) & (n[1] > 0.5)
            edge = wall & (np.abs(z - 1.53) < 0.02)
            return np.where((rib | edge)[:, None], out * 0.7, out)
        cargo = [Obj('tarp', tsdf, [tarp.mats[0], paint((66, 70, 76), rough=0.45, metal=0.4)], pick=tarp_pick,
                     tint=tarp_tint, bump=tarp.bump), tp[1]]
        cargo.append(painted_number('rear_no', (0.0, tr.TRUCK_Y1 + 0.002, 1.27), (0.62, 0.17), [plate], ink=(20, 20, 22)))
        cargo[-1].mats = [paint((66, 70, 76), rough=0.45, metal=0.4)]
        cargo[-1].tint = _num_tint(cargo[-1], (0.0, 1.27), (0.62, 0.17), plate, (236, 236, 232))
    elif kind == 'box':
        cab, cab_sdf = truck_cab_v((236, 236, 232))
        y0, y1 = 2.08, tr.TRUCK_Y1
        yc, hl = (y0 + y1) / 2, (y1 - y0) / 2

        def box(p):
            return rbox(p, (0, yc, 2.24), (1.235, hl, 1.14), 0.05)

        def box_pick(p, n):
            x, y, z = p
            ax = np.abs(x)
            idx = np.zeros(x.shape, np.int32)
            rear = (n[1] > 0.5) & (y > y1 - 0.05)
            idx[rear & ((ax > 1.10) | (z > 3.22) | (z < 1.26))] = 1
            rods = rear & (np.abs(np.abs(np.abs(x) - 0.55) - 0.30) < 0.018) & (z > 1.26) & (z < 3.22)
            idx[rods] = 2
            return idx

        def box_tint(p, n, alb, idx):
            x, y, z = p
            ax = np.abs(x)
            out = tr.box_parts()[0].tint(p, n, alb, idx)
            side = np.abs(n[0]) > 0.5
            ribs = side & (np.abs(((y - y0) % 0.62) - 0.31) > 0.296)
            seam = (n[1] > 0.5) & (np.abs(x) < 0.006) & (z > 1.26) & (z < 3.22)
            hinge = (n[1] > 0.5) & (ax > 1.04) & (ax < 1.10) & (np.abs(((z - 1.3) % 0.62) - 0.31) < 0.05)
            out = np.where((ribs | seam | hinge)[:, None], out * 0.6, out)
            return out
        cargo = [Obj('box', box, [paint((214, 218, 222), rough=0.35, metal=0.5), Mat((176, 178, 182), rough=0.35, metal=0.6), CHROME],
                     pick=box_pick, tint=box_tint)]
        cargo.append(painted_number('rear_no', (0.0, y1 + 0.003, 1.75), (0.70, 0.19), [plate]))
        cargo[-1].mats = [paint((214, 218, 222), rough=0.35, metal=0.5)]
        cargo[-1].tint = _num_tint(cargo[-1], (0.0, 1.75), (0.70, 0.19), plate, (20, 20, 22), paper=False)
    else:
        cab, cab_sdf = truck_cab_v((184, 30, 28), height=2.74)
        dp = tr.dump_parts()
        cargo = dp
        cargo.append(painted_number('rear_no', (0.0, 7.85 + 0.003, 1.80), (0.62, 0.17), [plate]))
        cargo[-1].tint = _num_tint(cargo[-1], (0.0, 1.80), (0.62, 0.17), plate, (236, 236, 232))
    parts = cab + cargo + truck_chassis() + truck_wheels()
    parts.append(plate_obj('plate_f', (0.0, -0.152, 0.52), (0.26, 0.055), -1, (plate,)))
    parts.append(plate_obj('plate_r', (0.0, 8.035, 0.84), (0.165, 0.0825), 1, num))
    sc = Scene(parts, ((-1.42, -0.20, 0.0), (1.42, 8.12, 3.5)), BB_PPM, (0, 0), (1, 1), ao_scale=2.4,
               interior=truck_interior(), glass_tint=(0.36, 0.39, 0.42))
    contacts = [(s * (0.99 + 0.125), ya, 0.0) for ya in TRUCK_AXLES for s in (-1, 1)]
    return Model(sc, contacts, (-0.14, tr.TRUCK_Y1 + 0.02), 1.235, 'truck')


def _num_tint(obj, c, half, plate, ink, paper=True):
    """Vân số kẻ sơn: chữ đen trên nền trắng ([paper]) hoặc chữ trực tiếp."""
    tex = text_tex([plate], (half[0] * 2000, half[1] * 2000), squeeze=0.85, border=False)

    def tint(p, n, alb, idx):
        x, y, z = p
        u = (x + half[0]) / (2 * half[0])
        v = (c[1] + half[1] - z) / (2 * half[1])
        k = sample_tex(tex, u, v)
        base = lin((236, 236, 232)) if paper else alb
        if paper:
            return base * (1 - k)[:, None] + lin((20, 20, 22)) * k[:, None] + 0 * alb
        return alb * (1 - k)[:, None] + lin(ink) * k[:, None]
    obj.mats = [Mat((236, 236, 232), rough=0.5, spec=0.4)] if paper else obj.mats
    return tint


# ================================================================ Xe máy
def moto_model(parts, kind_model='so', layers=None, ztop=2.2):
    axle = v3.REAR_AXLE if kind_model == 'so' else tr.GA_AXLE
    r = v3.WHEEL_R if kind_model == 'so' else tr.GA_R
    sc = Scene(parts, ((-0.48, -0.40, 0.0), (0.48, 1.90, ztop)), BB_PPM, (0, 0), (1, 1), ao_scale=0.55)
    hw = 0.046 if kind_model == 'so' else 0.05
    contacts = [(s * hw, ya, 0.0) for ya in (0.0, axle) for s in (-1, 1)]
    # chiều dài: mép trước lốp trước → đuôi (biển số / baga)
    return Model(sc, contacts, (-r - 0.02, 1.68), 0.36, 'moto', layers=layers)


def bike_rim(name, ya, R_in, mat, spokes=5, half_w=0.026, disc=0.0, hub_w=0.05):
    """Mâm đúc xe máy (đối xứng hai mặt) trong lòng lốp: vành, nan đúc, đùm;
    [disc] > 0: đĩa phanh bán kính đó bên trái (x < 0)."""
    zc = None

    def sdf(p):
        x, y, z = p
        ax = np.abs(x)
        ly, lz = y - ya, z - zc
        r = length2(ly, lz)
        lip = length2(np.maximum(np.abs(r - (R_in - 0.009)) - 0.009, 0), np.maximum(ax - half_w, 0)) - 0.002
        sector = math.tau / spokes
        ang = np.arctan2(lz, ly)
        a = ang - sector * np.round(ang / sector)
        u, w = r * np.cos(a), r * np.sin(a)
        spoke = np.maximum(np.maximum(np.abs(u - R_in / 2) - R_in / 2 + 0.012, np.abs(w) - (0.011 - 0.004 * u / R_in)),
                           ax - 0.010)
        hub = np.maximum(r - 0.052, ax - hub_w)
        d = np.minimum(lip, smin(spoke, hub, 0.01))
        if disc:
            dd = np.maximum(np.maximum(r - disc, 0.045 - r), np.abs(x + 0.048) - 0.0025)
            d = np.minimum(d, dd)
        return d

    def pick(p, n):
        x, y, z = p
        r = length2(y - ya, z - zc)
        idx = np.zeros(x.shape, np.int32)
        idx[(r < 0.058) & (np.abs(x) > 0.02)] = 1
        if disc:
            idx[(np.abs(x + 0.048) < 0.004) & (r > 0.05)] = 2
        return idx

    def tint(p, n, alb, idx):
        x, y, z = p
        r = length2(y - ya, z - zc)
        ang = np.arctan2(z - zc, y - ya)
        holes = (idx == 2) & (np.sin(ang * 14) > 0.7) & (np.abs(r - disc * 0.75) < 0.012)
        return np.where(holes[:, None], alb * 0.3, alb)

    def make(z0):
        nonlocal zc
        zc = z0
        return Obj(name, sdf, [mat, Mat((60, 62, 66), rough=0.4, metal=0.6), Mat((170, 172, 176), rough=0.25, metal=0.9)],
                   pick=pick, tint=tint)
    return make


MOTO_RIM_MATS = {'silver': Mat((196, 198, 202), rough=0.25, metal=0.6, spec=0.8), 'black': Mat((26, 26, 28), rough=0.3, spec=0.7),
                 'gold': Mat((190, 150, 70), rough=0.25, metal=0.8)}


def moto_running_gear(model, rim='silver', disc=False):
    """Mâm hai bánh, gắp sau, phuộc sau, hộp xích (xe số) / phuộc đơn bên
    trái (xe ga), gác chân sau."""
    rm = MOTO_RIM_MATS[rim]
    parts = []
    if model == 'so':
        R, ax_r = v3.WHEEL_R, v3.REAR_AXLE
        parts.append(bike_rim('rim_f', 0.0, R - 0.075, rm, disc=0.105 if disc else 0.0)(R))
        parts.append(bike_rim('rim_r', ax_r, R - 0.082, rm, hub_w=0.06)(R))

        def swing(p):
            q = (np.abs(p[0]), p[1], p[2])
            arm = capsule(q, (0.075, 0.80, 0.33), (0.075, ax_r, R), 0.016)
            return arm
        parts.append(Obj('swingarm', swing, SATIN_BLACK))
        parts.append(Obj('chaincase', lambda p: rbox(p, (-0.085, 1.01, 0.305), (0.018, 0.27, 0.052), 0.03), BLACK_PLASTIC))

        def shocks(p):
            q = (np.abs(p[0]), p[1], p[2])
            return round_cone(q, (0.088, ax_r - 0.01, R + 0.02), (0.092, 1.13, 0.60), 0.019, 0.022)

        def shock_tint(p, n, alb, idx):
            coil = (np.sin(p[2] * 230) > 0.2) & (p[2] > 0.36) & (p[2] < 0.56)
            return np.where(coil[:, None], lin((150, 30, 30)) if rim == 'gold' else lin((40, 40, 44)), alb)
        parts.append(Obj('shocks', shocks, CHROME, tint=shock_tint))
        pegs = (0.205, 1.0, 0.39)
    else:
        R, ax_r = tr.GA_R, tr.GA_AXLE
        parts.append(bike_rim('rim_f', 0.0, R - 0.07, rm, disc=0.10 if disc else 0.0)(R))
        parts.append(bike_rim('rim_r', ax_r, R - 0.075, rm, hub_w=0.065)(R))

        def shock(p):
            return round_cone(p, (-0.125, 1.32, 0.36), (-0.115, 1.33, 0.62), 0.02, 0.024)
        parts.append(Obj('shock', shock, CHROME,
                         tint=lambda p, n, alb, idx: np.where(((np.sin(p[2] * 230) > 0.2) & (p[2] > 0.40) & (p[2] < 0.58))[:, None],
                                                              lin((40, 40, 44)), alb)))
        parts.append(Obj('arm_r', lambda p: capsule(p, (0.10, 1.05, 0.30), (0.075, ax_r, R), 0.018), SATIN_BLACK))
        pegs = (0.21, 1.03, 0.41)
    px, py, pz = pegs
    parts.append(Obj('pegs', mirror_x(lambda p: capsule(p, (px - 0.06, py, pz), (px + 0.02, py, pz), 0.011)), RUBBER))
    return parts


MASKS = [(120, 170, 220), (30, 30, 34), (236, 236, 240), (230, 140, 170), (60, 90, 150), (200, 200, 196)]


def face_parts(head, mask, glasses=False, name='face'):
    """Mặt dưới vành mũ: đầu (da), khẩu trang vải che mũi miệng, gọng tai.
    Mắt nằm trong bóng lưỡi trai nên không vẽ chi tiết (khỏi 'ma quái')."""
    hx, hy, hz = head
    fc = (hx, hy - 0.035, hz - 0.075)

    def sdf(p):
        f = ellipsoid(p, fc, (0.066, 0.086, 0.108))
        nose = ellipsoid(p, (hx, hy - 0.118, hz - 0.098), (0.016, 0.022, 0.024))
        return smin(f, nose, 0.02)

    def pick(p, n):
        x, y, z = p
        m = (z < hz - 0.092 + 0.18 * np.maximum(y - (hy - 0.06), 0)) & (y < hy - 0.01)
        idx = np.where(m, 1, 0).astype(np.int32)
        if glasses:
            g = (np.abs(z - (hz - 0.078)) < 0.012) & (n[1] < -0.3)
            idx[g] = 2
        return idx

    def tint(p, n, alb, idx):
        x, y, z = p
        # nếp gấp ngang của khẩu trang, dây đeo tai
        fold = (idx == 1) & (np.sin((z - hz) * 260) > 0.75)
        strap = (idx == 0) & (np.abs(z - (hz - 0.105) - 0.2 * (y - hy)) < 0.005) & (np.abs(x) > 0.045)
        out = np.where(fold[:, None], alb * 0.82, alb)
        return np.where(strap[:, None], lin(mask) * 0.9, out)
    mats = [SKIN, fabric(mask, rough=0.9, sheen=0.4), Mat((12, 12, 14), rough=0.05, spec=1.0, coat=1.0)]
    return [Obj(name, sdf, mats, pick=pick, tint=tint)]


def no_vents(old):
    """Chọn vật liệu vỏ mũ như cũ nhưng bỏ khe thông gió trên đỉnh (giữ viền)."""
    def pick(p, n):
        idx = old(p, n)
        idx[(idx == 1) & (n[2] > 0.6)] = 0
        return idx
    return pick


def tag_moto(parts, plate_lines, model):
    """Gắn nhãn đèn hậu / đèn pha, in chữ biển số lên biển sau, thêm pát biển
    số; bỏ hai khe thông gió đỉnh mũ (nhìn thẳng từ trước trông như mắt)."""
    yp, zp = (1.655, 0.43) if model == 'so' else (1.66, 0.42)
    y_f = 1.50 if model == 'so' else 1.56
    parts.append(Obj('plate_bracket', lambda p: rbox(p, (0, (y_f + yp) / 2, zp + 0.04), (0.05, (yp - y_f) / 2, 0.012), 0.008),
                     BLACK_PLASTIC))
    for o in parts:
        if o.name == 'helmet':
            o.pick = no_vents(o.pick)
        if o.name == 'taillight':
            o.mats = [tagged(o.mats[0], 'tail')]
        elif o.name in ('cowl', 'cover'):
            o.mats = list(o.mats)
            o.mats[1] = tagged(o.mats[1], 'head')
        elif o.name == 'fender_r':
            tex = text_tex(list(plate_lines), (176, 116), squeeze=0.9)

            def tint(p, n, alb, idx, yp=yp, zp=zp, tex=tex, old=o.tint):
                x, y, z = p
                y2, z2 = rot(y - yp, z - zp, 0.3)
                k = sample_tex(tex, (x + 0.088) / 0.176, (0.058 - z2) / 0.116)
                out = old(p, n, alb, idx) if old else alb
                return np.where((idx == 1)[:, None], out * (1 - 0.92 * k)[:, None], out)
            o.tint = tint
    return parts


MOTO_PLATES = ['59-X1|386.27', '51-G2|104.58', '29-B1|772.06', '60-B4|219.83', '72-C1|540.17', '59-T2|068.91',
               '43-D1|315.40', '65-F1|928.32', '51-H8|447.09', '79-N1|603.25']
MOTO_RIMS = ['silver', 'black', 'silver', 'gold', 'black', 'silver', 'black', 'silver', 'gold', 'black']


def moto_people(c, i, model):
    """Mặt + khẩu trang cho người lái (và người ngồi sau)."""
    rider, pillion = (tr.GA_RIDER, tr.GA_PILLION) if model == 'ga' else (tr.WAVE_RIDER, tr.WAVE_PILLION)
    out = face_parts(rider.head, MASKS[i % len(MASKS)], glasses=(i % 3 == 1))
    if c.get('passenger'):
        out += face_parts(pillion.head, MASKS[(i + 3) % len(MASKS)], name='face_p')
    return out


def scooter_v(i, c):
    """Xe AI số [i] (0..9) trong tr.AI_SCOOTERS, đủ chi tiết cho ảnh đứng."""
    model = c['model']
    parts = tr.scooter(model, c['body'], c['helmet'], c['jacket'], c['pants'], passenger=c.get('passenger'),
                       cargo=c.get('cargo'), hair=c.get('hair'), gloves=c.get('gloves'), inner=c.get('inner'), seed=11 + i)
    parts += moto_running_gear(model, MOTO_RIMS[i], disc=(model == 'ga' or i % 2 == 0))
    parts += moto_people(c, i, model)
    tag_moto(parts, MOTO_PLATES[i].split('|'), model)
    return moto_model(parts, model)


def raincoat_layers_v(under, coat_color):
    """Áo mưa cánh dơi trùm lên người lái: vẽ riêng xe + người và áo (cùng máy
    ảnh) rồi ghép theo độ sâu như build_traffic_3d.raincoat_layers — chỗ áo
    nằm trước thì nilon trong mờ phủ lên, ánh sáng xuyên qua bị nhuộm màu áo."""
    coat = Scene([v3.raincoat_obj(coat_color)], under.bounds, BB_PPM, (0, 0), (1, 1), ao_scale=0.55)
    tint = 0.3 + 0.7 * lin(coat_color) / lin(coat_color).max()

    def layers(cam):
        rgb_u, a_u, t_u, lamp = render_cam(under, cam, ss=SS)
        rgb_c, a_c, t_c, _ = render_cam(coat, cam, ss=SS)
        on = (a_c > 0) & (t_c < t_u)
        ac = np.where(on, a_c, 0.0)
        alpha = ac + a_u * (1 - ac)
        pre = rgb_c * ac[..., None] + rgb_u * a_u[..., None] * (1 - ac)[..., None] * np.where(on[..., None], tint, 1.0)
        return pre / np.maximum(alpha, 1e-6)[..., None], alpha, np.minimum(t_u, t_c), lamp
    return layers


def raincoat_v(i, c):
    parts = tr.scooter('so', c['body'], c['helmet'], (90, 90, 96), (40, 50, 80), seed=31 + i)
    parts += moto_running_gear('so', ('black', 'silver', 'black', 'silver')[i], disc=i % 2 == 1)
    parts += face_parts(tr.WAVE_RIDER.head, MASKS[(i + 2) % len(MASKS)])
    tag_moto(parts, ('51-K3|208.14', '30-E1|655.72', '62-B1|431.90', '74-D1|180.36')[i].split('|'), 'so')
    m = moto_model(parts, 'so')
    m.layers = raincoat_layers_v(m.scene, c['coat'])
    return m


def police_v():
    parts = tr.police_bike() + tr.person_parts(tr.WAVE_RIDER, (245, 245, 245), tr.POLICE_UNIFORM, (64, 72, 52), seed=41)
    parts += moto_running_gear('so', 'silver', disc=True)
    parts += face_parts(tr.WAVE_RIDER.head, (236, 236, 240), glasses=True)
    tag_moto(parts, ['80-A1', '113.13'], 'so')
    return moto_model(parts, 'so')


# ============================================================ Danh sách
def billboard_jobs():
    """(tên, nhóm, hàm dựng Model) cho mọi ảnh xe AI trong game."""
    jobs = []
    for i, c in enumerate(tr.AI_SCOOTERS):
        jobs.append((f'scooter_ai_{i + 1}', 'moto', lambda i=i, c=c: scooter_v(i, c)))
    for i, c in enumerate(tr.AI_RAINCOATS):
        jobs.append((f'scooter_ai_raincoat_{i + 1}', 'moto', lambda i=i, c=c: raincoat_v(i, c)))
    jobs.append(('scooter_police', 'moto', police_v))
    plates = ['51K-386.27', '30G-112.49', '43A-675.10', '51H-920.33', '29A-547.81', '65A-238.06', '92A-401.75']
    for k, (name, rgb, metal, shirt) in enumerate(tr.SEDANS):
        jobs.append((f'sedan_{name}', 'car', lambda rgb=rgb, metal=metal, shirt=shirt, k=k:
                     car_model(sedan_v(rgb, metal, shirt, plate=(plates[k],)), SEDAN_V, 0.91)))
    jobs.append(('mini_van', 'car', lambda: car_model(mpv_v((196, 200, 204), metal=0.85, shirt=(150, 40, 40)), MPV_V, 0.89)))
    for name, rgb, cargo, metal, seed, pl in (('blue', (34, 84, 160), 'kumquat', 0.6, 61, '60C-224.91'),
                                              ('white', (236, 236, 232), 'peach', 0.12, 62, '51D-307.58'),
                                              ('gray', (112, 116, 120), 'boxes', 0.7, 63, '47C-163.20')):
        jobs.append((f'pickup_{name}', 'car', lambda rgb=rgb, cargo=cargo, metal=metal, seed=seed, pl=pl:
                     car_model(pu_v(rgb, cargo, metal, seed=seed, plate=(pl,)), PU_V, 0.95)))
    routes = ['SAI GON - NHA TRANG', 'HA NOI - VINH', 'CAN THO - SAI GON']
    bplates = ['51B-268.79', '29B-604.15', '65B-017.92']
    for k, (name, main, stripe, metal) in enumerate(tr.BUSES):
        jobs.append((name[4:], 'bus', lambda main=main, stripe=stripe, metal=metal, k=k:
                     bus_v(main, stripe, metal, plate=(bplates[k],), route=routes[k])))
    jobs.append(('container_1', 'truck', lambda: truck_v('tarp', '51C-473.26')))
    jobs.append(('container_2', 'truck', lambda: truck_v('box', '29C-815.04')))
    jobs.append(('truck', 'truck', lambda: truck_v('dump', '61C-092.37')))
    return jobs


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def build_billboards(out, groups, names):
    jobs = [j for j in billboard_jobs() if j[1] in groups or j[0] in names]
    if not jobs:
        return
    lamps = load_json(f'{out}/vehicle_lamps.json')
    meta = load_json(f'{out}/billboards.json')
    meta.pop('_info', None)
    for base, _, make in jobs:
        save_billboards(make(), base, out, meta, lamps)
    meta = {'_info': {'ppm': BB_PPM, 'elevation_deg': BB_ELEV, 'anchor': 'bottom-center = ground contact line of the lowest '
                      'tyre, vehicle centre at x = w/2', 'center_ground': 'pixel of the ground point under the vehicle '
                      'centre (y-mid of length) — the bottom row is the nearest tyre contact', 'side': 'seen from the '
                      'vehicle LEFT, nose pointing left (mirror for the other direction)'}, **dict(sorted(meta.items()))}
    with open(f'{out}/vehicle_lamps.json', 'w') as f:
        json.dump(dict(sorted(lamps.items())), f, indent=1)
    with open(f'{out}/billboards.json', 'w') as f:
        json.dump(meta, f, indent=1)


# ============================================================ Khoang lái
CP_SIZE = (1600, 740)
CP_HORIZON = 0.40   # đường chân trời game đặt ở 40 % chiều cao màn hình


def pitch_for(horizon_row, fov, size=CP_SIZE, shift_y=0.0):
    """Góc ngẩng (độ) để đường chân trời rơi đúng hàng [horizon_row]."""
    fl = size[0] / 2 / math.tan(math.radians(fov) / 2)
    cy = size[1] / 2 + shift_y
    return math.degrees(math.atan((horizon_row - cy) / fl))


def render_cockpit(scene, cam, ss=SS_COCKPIT, near=0.05, sun=(-0.35, 0.25, 0.90), fill=()):
    with sun_from(sun):
        rgb, alpha, depth, _ = render_cam(scene, cam, ss=ss, near=near, fill=fill)
    return finish_v(rgb, alpha, *cam.size, ss)


# đèn phụ trong khoang ô tô / xe khách: trời qua kính sau (sau lưng người lái),
# kính hông, ánh dội từ sàn / ghế lên trần
CABIN_FILL = (((0.0, 1.0, 0.45), (0.55, 0.60, 0.68)), ((-1.0, 0.2, 0.2), (0.22, 0.24, 0.28)),
              ((1.0, 0.2, 0.2), (0.22, 0.24, 0.28)), ((0.0, 0.0, -1.0), (0.30, 0.27, 0.24)))


# ---------------------------------------------------------------- Xe máy
GLOVE = (52, 54, 60)


def moto_arms(jacket, glove=GLOVE):
    """Cẳng tay (áo chống nắng) và bàn tay đeo găng nắm tay ga / tay côn —
    phần người lái duy nhất thấy được từ mắt (đầu, thân giấu đi)."""
    jk = fabric(jacket)
    gl = fabric(glove, rough=0.75, sheen=0.5)
    ex, ey, ez = v3.ELBOW
    wx, wy, wz = v3.WRIST
    sx, sy, sz = v3.SHOULDER

    def arms(p):
        q = (np.abs(p[0]), p[1], p[2])
        fa = round_cone(q, (ex, ey, ez), (wx, wy + 0.01, wz + 0.005), 0.050, 0.040)
        ua = round_cone(q, (sx + 0.03, sy, sz - 0.02), (ex, ey, ez), 0.062, 0.051)
        cuff = capsule(q, (wx - 0.002, wy + 0.012, wz + 0.004), (wx + 0.001, wy - 0.006, wz - 0.002), 0.043)
        return smin(smin(fa, ua, 0.02), cuff, 0.01)

    def arms_pick(p, n):
        x, y, z = p
        return (length3(np.abs(x) - wx, y - wy, z - wz) < 0.05).astype(np.int32)

    def hands(p):
        q = (np.abs(p[0]), p[1], p[2])
        # nắm tay quanh tay nắm (trục x, tâm y 0,334, z 0,990)
        gx = q[0] - 0.252
        r = length2(q[1] - 0.334, q[2] - 0.990)
        fist = smax(np.abs(r - 0.030) - 0.016, np.abs(gx) - 0.046, 0.012)
        back = ellipsoid(q, (0.262, 0.352, 1.012), (0.050, 0.040, 0.028))
        thumb = capsule(q, (0.222, 0.352, 1.004), (0.214, 0.318, 1.000), 0.012)
        knuckle = capsule(q, (0.212, 0.305, 0.992), (0.292, 0.305, 0.996), 0.016)
        return smin(smin(smin(fist, back, 0.018), thumb, 0.01), knuckle, 0.012)

    def hand_tint(p, n, alb, idx):
        x, y, z = p
        seam = np.abs(np.sin((np.abs(x) - 0.21) * 220)) < 0.12
        return np.where((seam & (y < 0.325))[:, None], alb * 0.6, alb)
    return [Blend('arms', [(arms, 0)], [jk, gl], 0.01, bump=v3.fabric_bump(70, 0.0016, 7)),
            Obj('gloves', hands, gl, tint=hand_tint)]


def dial_tex(kind='moto', needle=40.0, size=512):
    """Vân mặt đồng hồ vẽ bằng PIL (RGB 0..1): vạch, số, kim, đèn báo.
    'moto': đồng hồ xe số (0-120 km/h, cung trên, đồng hồ xăng bên phải);
    'speed' / 'rpm': hai mặt tròn của ô tô / xe khách."""
    from PIL import ImageDraw, ImageFont
    W = size
    H = size // 2 if kind == 'moto' else size
    img = Image.new('RGB', (W, H), (10, 11, 13))
    dr = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(W * (0.055 if kind == 'moto' else 0.075)))
    small = ImageFont.truetype(FONT, int(W * 0.04))
    if kind == 'moto':
        cx, cy, R = W * 0.43, H * 0.97, H * 0.80
        a0, a1, vmax, step = 196.0, 344.0, 120, 20
    else:
        cx, cy, R = W / 2, H / 2, W * 0.44
        a0, a1 = 135.0, 405.0
        vmax, step = (180, 20) if kind == 'speed' else (8, 1)
    # vòng vạch chia
    def pt(a, r):
        return cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
    if kind != 'moto':
        dr.ellipse([cx - R * 1.06, cy - R * 1.06, cx + R * 1.06, cy + R * 1.06], outline=(150, 152, 158), width=max(2, W // 120))
    n_minor = (vmax // step) * 5
    for i in range(n_minor + 1):
        a = a0 + (a1 - a0) * i / n_minor
        major = i % 5 == 0
        red = kind == 'rpm' and a > a0 + (a1 - a0) * 0.75
        col = (235, 60, 50) if red else (236, 238, 242)
        r0 = R * (0.80 if major else 0.88)
        dr.line([pt(a, r0), pt(a, R * 0.97)], fill=col, width=max(2, W // (90 if major else 200)))
        if major:
            v = vmax * i / n_minor
            txt = f'{int(v)}'
            bb = dr.textbbox((0, 0), txt, font=font)
            tx, ty = pt(a, R * 0.64)
            dr.text((tx - (bb[2] - bb[0]) / 2, ty - (bb[3] - bb[1]) / 2 - bb[1]), txt, fill=col, font=font)
    unit = 'km/h' if kind != 'rpm' else 'x1000r/min'
    bb = dr.textbbox((0, 0), unit, font=small)
    dr.text((cx - (bb[2] - bb[0]) / 2, cy - R * (0.32 if kind == 'moto' else -0.25)), unit, fill=(180, 182, 188), font=small)
    if kind == 'moto':
        # đồng hồ xăng dạng vạch đứng bên phải + đèn báo số N, xi-nhan, pha
        fx, f0, f1 = W * 0.90, H * 0.28, H * 0.86
        for i in range(5):
            yy = f1 - (f1 - f0) * i / 4
            col = (235, 60, 50) if i == 0 else (236, 238, 242)
            dr.line([(fx - W * 0.03, yy), (fx + W * 0.02, yy)], fill=col, width=max(2, W // 160))
        lvl = f1 - (f1 - f0) * 0.7
        dr.rectangle([fx - W * 0.012, lvl, fx + W * 0.008, f1], fill=(255, 150, 40))
        dr.text((fx + W * 0.03, f0 - H * 0.07), 'F', fill=(236, 238, 242), font=small)
        dr.text((fx + W * 0.03, f1 - H * 0.07), 'E', fill=(235, 60, 50), font=small)
        for k, (col, lx) in enumerate((((40, 210, 90), 0.06), ((60, 120, 255), 0.14), ((40, 210, 90), 0.22))):
            dr.ellipse([W * lx - H * 0.045, H * 0.06, W * lx + H * 0.045, H * 0.15], fill=col)
        bb = dr.textbbox((0, 0), 'N', font=small)
        dr.text((W * 0.06 - (bb[2] - bb[0]) / 2, H * 0.105 - (bb[3] + bb[1]) / 2), 'N', fill=(10, 30, 10), font=small)
    else:
        txt = '012345' if kind == 'speed' else 'D'
        bb = dr.textbbox((0, 0), txt, font=small)
        dr.rectangle([cx - (bb[2] - bb[0]) / 2 - 6, cy + R * 0.42, cx + (bb[2] - bb[0]) / 2 + 6, cy + R * 0.42 + (bb[3] - bb[1]) + 12],
                     fill=(30, 40, 46))
        dr.text((cx - (bb[2] - bb[0]) / 2, cy + R * 0.42 + 6 - bb[1]), txt, fill=(150, 230, 255), font=small)
    # kim
    a = math.radians(a0 + (a1 - a0) * min(needle, vmax) / vmax)
    tip = (cx + R * 0.86 * math.cos(a), cy + R * 0.86 * math.sin(a))
    tail = (cx - R * 0.10 * math.cos(a), cy - R * 0.10 * math.sin(a))
    dr.line([tail, tip], fill=(255, 64, 32), width=max(3, W // 70))
    hub = R * 0.07
    dr.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=(40, 42, 46))
    return np.asarray(img, np.float64) / 255.0


def sample_rgb(tex, u, v):
    return np.stack([sample_tex(tex[..., k], u, v) for k in range(3)], -1)


def emissive_face(name, sdf, uv, tex, glow=1.0, base=(12, 13, 15)):
    """Mặt đồng hồ phát sáng: [uv](p) → (u, v) ∈ [0, 1] trên vân [tex]."""
    def tint(p, n, alb, idx):
        u, v = uv(p)
        c = sample_rgb(tex, u, v)
        return c ** 2.2
    m = Mat(base, rough=0.25, spec=0.6, coat=0.7, emit=glow)
    return Obj(name, sdf, m, tint=tint)


def moto_cowl_cp(body):
    """Ốp đầu đèn xe số nhìn từ yên: rộng, dẹt, hốc đồng hồ ở mặt sau-trên
    (kính khói trong suốt phía trên mặt số), ốp nhựa đen phía dưới."""
    pt = paint(body)
    tilt = 0.55  # mặt đồng hồ ngửa về phía người lái

    def frame(p):
        x, y, z = p
        yy, zz = rot(y - 0.33, z - 1.035, tilt)
        return yy, zz

    def cowl(p):
        x, y, z = p
        a = ellipsoid(p, (0, 0.265, 0.972), (0.168, 0.150, 0.074))
        b = ellipsoid(p, (0, 0.150, 0.952), (0.105, 0.085, 0.066))
        c = ellipsoid(p, (0, 0.320, 0.935), (0.120, 0.090, 0.066))
        d = smin(smin(a, b, 0.06), c, 0.04)
        # hốc mặt đồng hồ: khoét nông theo mặt nghiêng
        yy, zz = frame(p)
        pocket = smax(rbox((x, yy, zz), (0, 0, 0.012), (0.072, 0.050, 0.020), 0.018), -zz - 0.004, 0.004)
        return smax(d, -pocket, 0.006)

    def pick(p, n):
        x, y, z = p
        yy, zz = frame(p)
        bezel = (np.abs(x) < 0.085) & (np.abs(yy) < 0.062) & (zz < 0.016)
        low = z < 0.925
        return np.where(bezel, 1, np.where(low, 2, 0)).astype(np.int32)
    obj = Obj('cowl', cowl, [pt, Mat((16, 16, 18), rough=0.35, spec=0.6), BLACK_PLASTIC], pick=pick)
    tex = dial_tex('moto', needle=38)

    def face_sdf(p):
        x, y, z = p
        yy, zz = frame(p)
        return rbox((x, yy, zz), (0, 0, 0.0), (0.070, 0.047, 0.002), 0.012)

    def face_uv(p):
        x, y, z = p
        yy, zz = frame(p)
        return (x + 0.070) / 0.140, (yy + 0.047) / 0.094
    # mặt số bóng như có kính phủ, đèn nền hơi sáng
    face = emissive_face('speedo', face_sdf, face_uv, tex, glow=0.35)
    face.mats = [Mat((12, 13, 15), rough=0.15, spec=0.8, coat=0.9, emit=0.35)]

    def switches(p):
        q = (np.abs(p[0]), p[1], p[2])
        return rbox(q, (0.178, 0.336, 0.99), (0.020, 0.030, 0.030), 0.012)

    def sw_pick(p, n):
        q = np.abs(p[0])
        btn = (n[1] > 0.5) & (np.abs(p[2] - 0.99) < 0.012) & (np.abs(q - 0.178) < 0.010)
        return btn.astype(np.int32)
    sw = Obj('switches', switches, [Mat((22, 22, 24), rough=0.45, spec=0.5), Mat((120, 122, 126), rough=0.3, metal=0.6)],
             pick=sw_pick)
    return [obj, face, sw]


def moto_cockpit_scene():
    parts = v3.bike_parts(v3.PLAYER_BODY)
    keep = {'grips', 'levers', 'mirrors', 'blink_f'}
    parts = [o for o in parts if o.name in keep] + moto_cowl_cp(v3.PLAYER_BODY)
    for o in parts:
        if o.name == 'grips':
            o.tint = lambda p, n, alb, idx: np.where(((idx == 0) & (np.sin(np.abs(p[0]) * 420) > 0.3))[:, None], alb * 0.6, alb)
    for o in parts:
        if o.name == 'mirrors':
            # chân gương choãi ra ngoài hơn một chút để đầu gương nằm hai bên
            # khung hình; mặt gương (phía sau, hướng người lái) tối, bóng soi trời
            def msdf(p):
                q = (np.abs(p[0]), p[1], p[2])
                stalk = capsule(q, (0.16, 0.315, 1.0), (0.32, 0.20, 1.19), 0.0075)
                xr, yr = rot(q[0] - 0.355, q[1] - 0.18, -0.35)
                return np.minimum(stalk, ellipsoid((xr, yr, q[2]), (0, 0, 1.21), (0.068, 0.034, 0.042)))
            o.sdf = msdf
            o.mats = [SATIN_BLACK, CHROME, Mat((96, 106, 122), rough=0.02, metal=1.0)]

            def mpick(p, n):
                x, y, z = p
                xr, yr = rot(np.abs(x) - 0.355, y - 0.18, -0.35)
                idx = ((z < 1.155) & (z > 1.02)).astype(np.int32)
                glass = (z > 1.17) & (yr > 0.010) & (((xr / 0.060) ** 2 + ((z - 1.21) / 0.035) ** 2) < 1)
                idx[glass] = 2
                return idx
            o.pick = mpick
    parts += moto_arms(v3.PLAYER_JACKET)
    return Scene(parts, ((-0.48, -0.40, 0.0), (0.48, 0.80, 1.40)), 2000.0, (0, 0), (1, 1), ao_scale=0.55)


# ------------------------------------------------------------------ Ô tô
def beam(a, b, half_w, half_d, r, normal):
    """Thanh hộp bo tròn từ a tới b; [normal] gợi ý hướng mặt dày (half_d)."""
    a = np.asarray(a, np.float64)
    b = np.asarray(b, np.float64)
    t = b - a
    L = float(np.linalg.norm(t))
    t /= L
    s = np.cross(t, np.asarray(normal, np.float64))
    s /= np.linalg.norm(s)
    n = np.cross(s, t)

    def sdf(p):
        q = [p[i] - a[i] for i in range(3)]
        u = q[0] * s[0] + q[1] * s[1] + q[2] * s[2]
        v = q[0] * t[0] + q[1] * t[1] + q[2] * t[2]
        w = q[0] * n[0] + q[1] * n[1] + q[2] * n[2]
        return rbox((u, v, w), (0, L / 2, 0), (half_w, L / 2 + half_w * 0.5, half_d), r)
    return sdf


class WheelFrame:
    """Hệ toạ độ vô-lăng: tâm [H], pháp tuyến hướng về mắt [eye]."""

    def __init__(self, H, eye):
        self.H = np.asarray(H, np.float64)
        n = np.asarray(eye, np.float64) - self.H
        self.n = n / np.linalg.norm(n)
        r = np.cross(self.n, np.array([0, 0, 1.0]))
        self.r = r / np.linalg.norm(r)
        self.u = np.cross(self.r, self.n)

    def local(self, p):
        q = [p[i] - self.H[i] for i in range(3)]
        dot = lambda v: q[0] * v[0] + q[1] * v[1] + q[2] * v[2]  # noqa: E731
        return dot(self.r), dot(self.u), dot(self.n)


LEATHER = Mat((26, 25, 26), rough=0.5, spec=0.5, sheen=0.25)


def steering_wheel(wf, R=0.185, tube=0.0175, spokes=3, hub=(0.078, 0.062), name='wheel', trim=(150, 152, 158)):
    """Vô-lăng bọc da: vành (dày hơn ở chỗ đặt ngón cái), ba / bốn chấu,
    nắp túi khí giữa có logo, nút bấm trên chấu."""
    def rim(p):
        a, b, c = wf.local(p)
        rr = length2(a, b)
        ang = np.arctan2(b, a)
        th = tube * (1 + 0.18 * np.exp(-((np.abs(np.cos(ang)) - 1) / 0.08) ** 2) * (np.sin(ang) < 0.3))
        return length2(rr - R, c) - th

    def spoke_sdf(p):
        a, b, c = wf.local(p)
        sides = rbox((np.abs(a), b, c), ((R + hub[0]) / 2 - 0.01, -0.015, -0.012), ((R - hub[0]) / 2 + 0.012, 0.026, 0.011), 0.008)
        d = sides
        if spokes >= 3:
            low = rbox((a, b, c), (0, -(R + hub[1]) / 2, -0.016), (0.022, (R - hub[1]) / 2 + 0.01, 0.010), 0.007)
            d = np.minimum(d, low)
        if spokes == 4:
            d = np.minimum(d, rbox((np.abs(a) - 0.06, b, c), (0, -(R + hub[1]) / 2 + 0.01, -0.016), (0.015, (R - hub[1]) / 2, 0.010), 0.006))
        hb = rbox((a, b, c), (0, -0.005, 0.0), (hub[0], hub[1], 0.026), 0.022)
        return smin(d, hb, 0.012)

    def spoke_pick(p, n):
        a, b, c = wf.local(p)
        idx = np.zeros(a.shape, np.int32)
        idx[(np.abs(a) > hub[0] + 0.004) & (np.abs(b + 0.015) < 0.010) & (c > 0.0)] = 1
        logo = ((a / 0.017) ** 2 + ((b - 0.0) / 0.011) ** 2 < 1) & (c > 0.018)
        idx[logo] = 1
        btn = (np.abs(np.abs(a) - (hub[0] + 0.045)) < 0.012) & (np.abs(b + 0.012) < 0.012) & (c > 0.005)
        idx[btn] = 2
        return idx
    rim_obj = Obj(name + '_rim', rim, LEATHER,
                  tint=lambda p, n, alb, idx: np.where((np.abs(wf.local(p)[2]) < 0.0025)[:, None], alb * 1.8, alb))
    spoke_obj = Obj(name + '_hub', spoke_sdf, [Mat((30, 30, 32), rough=0.45, spec=0.5), Mat(trim, rough=0.25, metal=0.8),
                                               Mat((60, 62, 66), rough=0.35, spec=0.6)], pick=spoke_pick)
    return [rim_obj, spoke_obj]


DASH_TOP = Mat((44, 44, 47), rough=0.72, spec=0.35)
DASH_LOW = Mat((40, 40, 43), rough=0.6, spec=0.4)
TRIM_FABRIC = fabric((160, 156, 148), rough=0.9, sheen=0.3)
SILVER_TRIM = Mat((168, 170, 175), rough=0.25, metal=0.85)


class CarCabin:
    """Khoang lái sedan (vô-lăng bên trái) dựng riêng quanh mắt ảo [eye]:
    kính lái từ chân (yb, zb) lên mép trần (yh, zh), cột A, trần nỉ, tấm che
    nắng, gương chiếu hậu trong, táp-lô có cụm đồng hồ, màn hình giữa, cửa
    gió, mép cửa / khung kính hai bên, gương chiếu hậu ngoài."""

    def __init__(self, eye, yb=1.40, zb=0.77, yh=2.02, zh=1.48, hb=0.72, ht=0.66, yd=2.05, belt=0.98):
        self.eye = np.asarray(eye, np.float64)
        self.yb, self.zb, self.yh, self.zh, self.hb, self.ht, self.yd, self.belt = yb, zb, yh, zh, hb, ht, yd, belt
        dx = -0.37  # vô-lăng / ghế lái
        self.dx = dx
        H = (dx, eye[1] - 0.50, eye[2] - 0.31)
        self.wf = WheelFrame(H, eye)

    def parts(self):
        yb, zb, yh, zh, hb, ht, yd = self.yb, self.zb, self.yh, self.zh, self.hb, self.ht, self.yd
        glass_n = np.cross(np.array([ht - hb, yh - yb, zh - zb]), np.array([1.0, 0, 0]))
        glass_n /= np.linalg.norm(glass_n)
        if glass_n[1] < 0:
            glass_n = -glass_n
        objs = []
        # cột A hai bên (trái dày hơn vì gần mắt), thanh mép trần kính
        pl = beam((-hb - 0.035, yb, zb - 0.02), (-ht - 0.035, yh + 0.02, zh + 0.01), 0.050, 0.035, 0.03, glass_n)
        pr = beam((hb + 0.030, yb, zb - 0.02), (ht + 0.030, yh + 0.02, zh + 0.01), 0.042, 0.032, 0.026, glass_n)
        header = beam((-ht - 0.06, yh + 0.03, zh + 0.025), (ht + 0.06, yh + 0.03, zh + 0.025), 0.045, 0.03, 0.025, (0, 0, 1.0))

        def pillars(p):
            return np.minimum(np.minimum(pl(p), pr(p)), header(p))
        objs.append(lit(Obj('pillars', pillars, TRIM_FABRIC), 0.75))

        # trần nỉ + gờ trần hai bên, khung cửa kính hông
        def roof(p):
            x, y, z = p
            ceil = rbox(p, (0, (yh + 3.4) / 2, zh + 0.07 - 0.03 * (x / 0.74) ** 2), (0.80, (3.4 - yh) / 2 + 0.03, 0.035), 0.02)
            rail = rbox((np.abs(x), y, z), (0.73, (yh + 3.4) / 2, zh + 0.0), (0.06, (3.4 - yh) / 2, 0.05), 0.03)
            return np.minimum(ceil, rail)
        objs.append(lit(Obj('roof', roof, TRIM_FABRIC, bump=v3.fabric_bump(120, 0.0006, 3)), 0.6))

        # tấm che nắng gập sát trần
        def visors(p):
            x, y, z = p
            q = (np.abs(x + 0.0) - 0.37, y - (yh + 0.15), z - (zh + 0.005))
            yy, zz = rot(q[1], q[2], -0.10)
            return rbox((q[0], yy, zz), (0, 0, 0), (0.175, 0.085, 0.016), 0.014)

        def visor_tint(p, n, alb, idx):
            x, y, z = p
            seam = np.abs(np.abs(np.abs(x) - 0.37) - 0.160) < 0.004
            seam |= np.abs(np.abs(y - (yh + 0.15)) - 0.072) < 0.004
            return np.where(seam[:, None], alb * 0.75, alb)
        objs.append(lit(Obj('visors', visors, fabric((150, 146, 138), rough=0.9, sheen=0.3), tint=visor_tint), 0.65))

        # gương chiếu hậu trong: chân dán kính, thân gương nghiêng về người lái
        mc = np.array([0.0, yh - 0.02, zh - 0.10])

        def mirror(p):
            x, y, z = p
            stalk = capsule(p, (0, yh - 0.06, zh - 0.015), (0, mc[1] + 0.01, mc[2] + 0.03), 0.010)
            u, v = rot(x - mc[0], y - mc[1], -0.22)
            body = rbox((u, v, z - mc[2]), (0, 0, 0), (0.125, 0.022, 0.034), 0.02)
            return smin(stalk, body, 0.01)

        def mirror_pick(p, n):
            x, y, z = p
            u, v = rot(x - mc[0], y - mc[1], -0.22)
            glass = (v > 0.012) & (np.abs(u) < 0.112) & (np.abs(z - mc[2]) < 0.024)
            return glass.astype(np.int32)
        objs.append(Obj('rv_mirror', mirror, [Mat((28, 28, 30), rough=0.4, spec=0.5), Mat((120, 128, 140), rough=0.02, metal=1.0)],
                        pick=mirror_pick))

        # táp-lô
        zt = zb + 0.10
        GY, GZ = 1.90, 1.035   # tâm mặt đồng hồ

        def dash(p):
            x, y, z = p
            ax = np.abs(x)
            k = (y - yb) / (yd - yb)
            top = zb + 0.015 + (zt - zb) * np.clip(k, 0, 1) ** 0.8
            d_top = (z - top) / 1.03
            d_rear = y - yd
            d_front = yb - 0.06 - y
            d_side = ax - (hb + 0.03)
            body = smax(smax(smax(d_top, d_rear, 0.06), d_front, 0.02), d_side, 0.04)
            body = smax(body, 0.45 - z, 0.02)
            # ụ che cụm đồng hồ trước người lái (nhô cao hơn mép táp-lô, thấy qua
            # nửa trên vô-lăng), khoét lòng hướng về người lái
            hood = rbox(p, (self.dx, GY - 0.07, GZ + 0.01), (0.215, 0.13, 0.085), 0.05)
            recess = rbox(p, (self.dx, GY + 0.05, GZ - 0.005), (0.185, 0.11, 0.068), 0.04)
            hood = smax(hood, -recess, 0.012)
            hood = smax(hood, 0.55 - z, 0.02)
            # khối giữa (màn hình, cửa gió)
            stack = rbox(p, (0.03, yd + 0.01, zt - 0.10), (0.15, 0.05, 0.11), 0.03)
            return smin(smin(body, hood, 0.04), stack, 0.03)

        def dash_pick(p, n):
            x, y, z = p
            ax = np.abs(x)
            idx = np.where(n[2] > 0.55, 0, 1).astype(np.int32)
            # nẹp bạc chạy ngang mặt táp-lô phía phụ, cửa gió
            idx[(n[1] > 0.5) & (np.abs(z - (zt - 0.07)) < 0.006) & (x > 0.20)] = 2
            vent = (n[1] > 0.5) & (((np.abs(x - 0.03) < 0.13) & (np.abs(z - (zt - 0.035)) < 0.022)) |
                                   ((np.abs(x - 0.60) < 0.07) & (np.abs(z - (zt - 0.04)) < 0.026)))
            idx[vent] = 3
            scr = (n[1] > 0.5) & (np.abs(x - 0.03) < 0.115) & (np.abs(z - (zt - 0.13)) < 0.06)
            idx[scr] = 4
            haz = (n[1] > 0.5) & (np.abs(x - 0.03) < 0.012) & (np.abs(z - (zt - 0.065)) < 0.008)
            idx[haz] = 5
            return idx

        def dash_tint(p, n, alb, idx):
            x, y, z = p
            out = alb
            slots = (idx == 3) & (np.sin(z * 520) > 0.2)
            out = np.where(slots[:, None], alb * 0.3, out)
            defrost = (n[2] > 0.55) & (np.abs(y - (yb + 0.07)) < 0.025) & (np.abs(x) < 0.55) & (np.sin(x * 260) > 0.4)
            out = np.where(defrost[:, None], alb * 0.35, out)
            # màn hình: bản đồ mờ
            scr = idx == 4
            if scr.any():
                g = (np.abs(np.sin(x * 90 + z * 30)) < 0.05) | (np.abs(np.sin(x * 40 - z * 70)) < 0.05)
                ui = lin((30, 50, 70)) + lin((90, 140, 190)) * g[:, None] * 0.6
                out = np.where(scr[:, None], ui, out)
            glove = (x > 0.25) & (n[1] > 0.5) & (np.abs(_rr(x, z, (0.48, zt - 0.20), (0.20, 0.08), 0.0, 0.02)) < 0.004)
            return np.where(glove[:, None], out * 0.4, out)
        dash_mats = [DASH_TOP, DASH_LOW, SILVER_TRIM, Mat((14, 14, 15), rough=0.5),
                     Mat((14, 16, 20), rough=0.05, spec=1.0, coat=1.0, emit=0.6), Mat((180, 30, 26), rough=0.3, coat=0.5)]
        objs.append(lit(Obj('dash', dash, dash_mats, pick=dash_pick, tint=dash_tint), 0.8))

        # mặt cụm đồng hồ: tốc độ (trái), vòng tua (phải) trong lòng ụ
        spd, rpm = dial_tex('speed', needle=45), dial_tex('rpm', needle=2.2)
        fy, fz = GY + 0.0, GZ
        tilt = 0.35

        def gauge(p):
            x, y, z = p
            yy, zz = rot(y - fy, z - fz, tilt)
            return rbox((x - self.dx, yy, zz), (0, 0, 0), (0.17, 0.004, 0.058), 0.01)

        def gauge_tint(p, n, alb, idx):
            x, y, z = p
            yy, zz = rot(y - fy, z - fz, tilt)
            u = x - self.dx
            out = np.zeros((x.shape[0], 3)) + lin((8, 9, 11))
            for cx, tex in ((-0.085, spd), (0.085, rpm)):
                r = length2(u - cx, zz)
                m = r < 0.056
                if m.any():
                    c = sample_rgb(tex, (u[m] - cx) / 0.112 + 0.5, 0.5 - zz[m] / 0.112) ** 2.2
                    out[m] = c
            mid = (np.abs(u) < 0.022) & (np.abs(zz) < 0.03)
            out[mid] = lin((40, 70, 90))
            return out
        objs.append(Obj('gauges', gauge, Mat((10, 10, 12), rough=0.1, spec=0.8, coat=0.8, emit=0.55), tint=gauge_tint))

        # màn hình nổi giữa táp-lô (bản đồ dẫn đường)
        def screen(p):
            x, y, z = p
            yy, zz = rot(y - 1.86, z - 0.965, 0.25)
            panel = rbox((x - 0.13, yy, zz), (0, 0, 0), (0.135, 0.012, 0.078), 0.01)
            foot = rbox(p, (0.13, 1.84, zt - 0.02), (0.05, 0.03, 0.05), 0.015)
            return smin(panel, foot, 0.01)

        def screen_pick(p, n):
            x, y, z = p
            yy, zz = rot(y - 1.86, z - 0.965, 0.25)
            return ((yy > 0.008) & (np.abs(x - 0.13) < 0.124) & (np.abs(zz) < 0.068)).astype(np.int32)

        def screen_tint(p, n, alb, idx):
            x, y, z = p
            yy, zz = rot(y - 1.86, z - 0.965, 0.25)
            u, v = (x - 0.13) / 0.124, zz / 0.068
            road = (np.abs(np.sin(u * 7 + v * 3)) < 0.08) | (np.abs(np.sin(u * 3 - v * 9 + 1)) < 0.06)
            route = np.abs(u * 0.6 - v * 0.8 + 0.1) < 0.05
            ui = lin((26, 34, 30)) + lin((70, 80, 76)) * road[:, None] + lin((60, 150, 255)) * route[:, None] * 1.5
            bar = v > 0.78
            ui = np.where(bar[:, None], lin((20, 22, 26)), ui)
            return np.where((idx == 1)[:, None], ui, alb)
        objs.append(Obj('screen', screen, [Mat((18, 18, 20), rough=0.35, spec=0.5), Mat((10, 10, 12), rough=0.05, spec=1.0, coat=1.0, emit=0.7)],
                        pick=screen_pick, tint=screen_tint))

        # cột lái
        H = self.wf.H
        objs.append(Obj('column', lambda p: round_cone(p, (self.dx, GY, GZ - 0.12), tuple(H - self.wf.n * 0.05), 0.06, 0.045),
                        DASH_LOW))

        # mép cửa (bệ tì tay, tay nắm) và khung kính hông
        bl = self.belt

        def doors(p):
            x, y, z = p
            q = (np.abs(x), y, z)
            panel = rbox(q, (hb + 0.08, (yb + 3.0) / 2, (0.45 + bl) / 2), (0.06, (3.0 - yb) / 2, (bl - 0.45) / 2), 0.03)
            arm = rbox(q, (hb + 0.0, 2.45, 0.80), (0.05, 0.30, 0.03), 0.025)
            return smin(panel, arm, 0.03)

        def door_pick(p, n):
            return ((p[2] > self.belt - 0.04) | (n[2] > 0.6)).astype(np.int32)
        objs.append(lit(Obj('doors', doors, [Mat((52, 50, 50), rough=0.7, sheen=0.3), DASH_TOP], pick=door_pick), 0.75))

        # gương chiếu hậu ngoài (thấy qua kính hông, mặt gương quay vào xe)
        def wing(p):
            x, y, z = p
            q = (np.abs(x), y, z)
            head = ellipsoid(q, (hb + 0.28, yb + 0.14, zb + 0.10), (0.10, 0.045, 0.065))
            arm = rbox(q, (hb + 0.14, yb + 0.12, zb + 0.07), (0.08, 0.03, 0.025), 0.02)
            return smin(head, arm, 0.02)

        def wing_pick(p, n):
            q = np.abs(p[0])
            return ((n[1] > 0.55) & (p[1] > yb + 0.15)).astype(np.int32) + ((q > hb + 0.2) & (n[1] <= 0.55)).astype(np.int32) * 2
        objs.append(Obj('wing', wing, [Mat((24, 24, 26), rough=0.4), Mat((110, 118, 130), rough=0.02, metal=1.0),
                                       paint((168, 9, 17))], pick=wing_pick))
        return objs

    def wheel_parts(self):
        return steering_wheel(self.wf)

    def bounds(self):
        return ((-1.15, 1.20, 0.30), (1.15, 3.50, 1.65))


def car_cockpit(size=CP_SIZE, fov=96.0):
    eye = (-0.32, 2.62, 1.30)
    cab = CarCabin(eye)
    pitch = pitch_for(CP_HORIZON * size[1], fov, size)
    cam = PinholeCam(eye, 0.0, pitch, fov, size)
    return cab, cam


MOTO_CAM = dict(eye=(0.0, 0.70, 1.47), yaw=0.0, pitch=-35.0, fov=100.0)
CAR_SUN = (-0.30, -0.45, 0.84)


def build_cockpit_moto(out, info):
    t0 = time.time()
    c = MOTO_CAM
    cam = PinholeCam(c['eye'], c['yaw'], c['pitch'], c['fov'], CP_SIZE)
    img = render_cockpit(moto_cockpit_scene(), cam)
    img.save(f'{out}/cockpit_moto.png', optimize=True)
    info['moto'] = {'image': 'cockpit_moto.png', 'size': list(CP_SIZE),
                    'camera': {'eye_m': list(c['eye']), 'pitch_deg': c['pitch'], 'hfov_deg': c['fov']},
                    'horizon_row': None,
                    'note': 'virtual camera ~10 cm behind the rider eyes pitched down 35 deg; its own horizon is above '
                            'the frame, so the overlay is a stylised lower-periphery view: just draw it full-screen over '
                            'the road (horizon 40 %). Rider head/torso hidden; speedometer needle fixed at ~38 km/h.'}
    print(f'cockpit_moto: {time.time() - t0:.1f}s')


def build_cockpit_car(out, info):
    t0 = time.time()
    fov = 96.0
    cab, cam = car_cockpit(CP_SIZE, fov)
    parts, wheel = cab.parts(), cab.wheel_parts()
    sc = Scene(parts, cab.bounds(), 1500.0, (0, 0), (1, 1), ao_scale=1.6)
    img = render_cockpit(sc, cam, near=0.05, sun=CAR_SUN, fill=CABIN_FILL)
    img.save(f'{out}/cockpit_car.png', optimize=True)
    # vô-lăng riêng: khung sát quanh vành (có thể thò xuống dưới mép 740)
    wf = cab.wf
    ang = np.linspace(0, math.tau, 96, endpoint=False)
    R = 0.185 + 0.03
    pts = [wf.H + R * (math.cos(a) * wf.r + math.sin(a) * wf.u) for a in ang]
    xs, ys = zip(*[cam.project(q) for q in pts])
    x0, y0 = int(math.floor(min(xs))) - 4, int(math.floor(min(ys))) - 4
    x1, y1 = int(math.ceil(max(xs))) + 4, int(math.ceil(max(ys))) + 4
    w, h = x1 - x0, y1 - y0
    wcam = PinholeCam(cab.eye, 0.0, pitch_for(CP_HORIZON * CP_SIZE[1], fov), fov, (w, h),
                      shift=(cam.cx - x0 - w / 2, cam.cy - y0 - h / 2))
    wcam.fl = cam.fl
    ws = Scene(parts + wheel, cab.bounds(), 1500.0, (0, 0), (1, 1), ao_scale=1.6)
    ws.primary = wheel
    wimg = render_cockpit(ws, wcam, near=0.05, sun=CAR_SUN, fill=CABIN_FILL)
    wimg.save(f'{out}/cockpit_car_wheel.png', optimize=True)
    px, py = cam.project(wf.H)
    info['car'] = {'image': 'cockpit_car.png', 'size': list(CP_SIZE), 'horizon_row': round(cam.horizon_row(), 1),
                   'camera': {'eye_m': [float(v) for v in cab.eye], 'hfov_deg': fov, 'pitch_deg': round(pitch_for(296, fov), 3),
                              'eye_height_m': float(cab.eye[2])},
                   'wheel': {'image': 'cockpit_car_wheel.png', 'pos': [x0, y0], 'size': [w, h],
                             'pivot': [round(px, 1), round(py, 1)],
                             'note': 'draw at pos (top-left, cockpit frame px), rotate around pivot; the wheel faces the '
                                     'eye so a 2D rotation is exact; it extends below the 740 px frame'}}
    print(f'cockpit_car: {time.time() - t0:.1f}s')


def build_cockpits(out, names):
    info = load_json(f'{out}/cockpits.json')
    if 'cockpit_moto' in names or 'cockpit' in names:
        build_cockpit_moto(out, info)
    if 'cockpit_car' in names or 'cockpit' in names:
        build_cockpit_car(out, info)
    with open(f'{out}/cockpits.json', 'w') as f:
        json.dump(info, f, indent=1)


GROUPS = ('moto', 'car', 'bus', 'truck', 'cockpit')

if __name__ == '__main__':
    args = sys.argv[1:]
    out = OUT
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    os.makedirs(out, exist_ok=True)
    sel = set(args or GROUPS)
    build_billboards(out, sel & set(GROUPS[:4]), sel)
    if sel & {'cockpit', 'cockpit_moto', 'cockpit_car'}:
        build_cockpits(out, sel)
