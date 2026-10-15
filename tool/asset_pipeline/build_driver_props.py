"""Billboard cho góc nhìn ghế lái (đường giả 3D vẽ bằng Dart): người, con vật,
quán ven đường, cây xăng, trạm thu phí, chốt CSGT, biển báo, đèn giao thông,
quà Tết rơi trên đường... Mỗi hình là một ảnh dựng đứng trên mặt đất, nhìn
thẳng từ phía trước (con vật, võng, thợ vá: nhìn ngang).

Dùng lại bộ dò tia SDF của build_vehicles_3d.py (cùng vật liệu, bầu trời
phản chiếu, bóng mềm, AO, GGX) nhưng đổi máy ảnh: máy ảnh phối cảnh đặt cách
vật [CAM_DIST] m, cao ngang mắt người lái [EYE_H] m, nhìn ngang về phía vật.
Mặt phẳng ảnh là mặt phẳng đứng y = 0 đi qua mép trước chân đế của vật, nên:
    - điểm giữa đáy ảnh = điểm mặt đất ở giữa mép trước chân đế vật;
    - 1 m trên mặt phẳng đó = [ppm] điểm ảnh, h_m = cao ảnh / ppm.
Vì nhìn hơi chếch xuống nên thấy được mặt bàn, mặt ghế; vật cao hơn mắt thì
thấy mặt dưới (dù, mái tôn, lưỡi trai). Mặt đất ngay dưới / quanh chân đế
được "hứng bóng" (chỉ kênh alpha, màu đen): bóng tiếp xúc ở chân, bóng dù
trên nền quán. Bóng dài đổ xa do game tự vẽ.

Nắng chiếu từ trên cao phía trước - bên trái. Mọi mô hình: x sang phải ảnh,
y từ mép trước chân đế đi ra xa (vào sâu), z lên trời, đơn vị mét. Người /
vật quay mặt về máy ảnh (về phía -y). Con vật quay đầu sang TRÁI (-x).

Chữ trên biển hiệu vẽ bằng PIL (font Manrope / Paytone One của game, đủ dấu
tiếng Việt) rồi dán lên tấm phẳng 3D (có đổ sáng, phản chiếu); dải diềm mái
cây xăng / trạm thu phí vẽ phẳng bằng PIL để lặp ngang liền mạch.

Ghi ra assets/images/driver/*.png và props.json (gộp với file sẵn có):
    {"<tên>": {"h_m": cao thật của cả ảnh (m), "w_m": rộng (m), "kind": ...,
               "depth_m": bề sâu chân đế tính từ mép trước,
               ["facing": "left"], ["tile_x": true],
               ["mount" | "arm_tip" | "pivot": [u, v] — điểm neo phụ, toạ độ
                chuẩn hoá theo ảnh, u từ trái, v từ trên]}}

Nhóm: animals, fascia, gas, lights, misc, people, pickups, police, signs,
stalls, toll. Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_driver_props.py                # tất cả (~12 phút)
    python tool/asset_pipeline/build_driver_props.py people stalls  # chọn nhóm
    python tool/asset_pipeline/build_driver_props.py --only person_1 duck_1
    python tool/asset_pipeline/build_driver_props.py --out DIR --sheet sheet.png
"""
import json
import math
import multiprocessing as mp
import os
import random
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_vehicles_3d as v3  # noqa: E402
from build_vehicles_3d import (  # noqa: E402
    ALU, DARK_METAL, MAT_FIELDS, RUBBER, SATIN_BLACK, Blend, Mat, Obj, capsule, ellipsoid, fabric,
    fabric_bump, fbm, field_bump, length2, length3, lin, mat_arrays, rbox, rot, round_cone, smax, smin, smoothstep,
    tyre, vnoise)
import build_traffic_3d as t3  # noqa: E402

OUT = 'assets/images/driver'
FONT_DIR = 'assets/fonts'

# Máy ảnh: cách mặt phẳng ảnh CAM_DIST m, cao EYE_H m.
CAM_DIST = 12.0
EYE_H = 1.3

# Nắng từ trên cao phía trước - bên trái (hướng tới mặt trời).
SUN = np.array([-0.45, -0.55, 0.72])
SUN /= np.linalg.norm(SUN)
v3.SUN = SUN  # quầng sáng mặt trời trong bầu trời phản chiếu (v3.env)
SUN_COL = v3.SUN_COL
SKY_IRR = v3.SKY_IRR
# ánh sáng hắt lên từ mặt đường nắng (nhìn ngang thì mặt dưới vành nón,
# cằm, gầm bàn đón nhiều ánh hắt hơn hẳn góc nhìn từ trên)
GROUND_IRR = np.array([0.34, 0.31, 0.27])


# ============================================================ Tiện ích SDF
def cone_shell(p, base, radius, height, thick):
    """Nón lá: vỏ hình nón (đỉnh ở trên), [base] tâm vành, dày [thick]."""
    x, y, z = p
    r = length2(x - base[0], y - base[1])
    h = z - base[2]
    # khoảng cách tới đường sinh (radius, 0) → (0, height) trong mặt (r, h)
    L = math.hypot(radius, height)
    ux, uh = -radius / L, height / L  # hướng đi từ vành lên đỉnh
    t = np.clip(((r - radius) * ux + h * uh) / L, 0, 1) * L
    dr = r - (radius + ux * t)
    dh = h - uh * t
    return length2(dr, dh) - thick


def cyl(p, c, r, h0, h1):
    """Trụ đứng tâm (c[0], c[1]), bán kính r, từ z = h0 tới h1."""
    x, y, z = p
    d = length2(x - c[0], y - c[1]) - r
    e = np.maximum(h0 - z, z - h1)
    return np.minimum(np.maximum(d, e), 0) + length2(np.maximum(d, 0), np.maximum(e, 0))


def cyl_x(p, c, r, h):
    """Trụ nằm ngang theo trục x: tâm c, bán kính r, nửa dài h."""
    x, y, z = p
    d = length2(y - c[1], z - c[2]) - r
    e = np.abs(x - c[0]) - h
    return np.minimum(np.maximum(d, e), 0) + length2(np.maximum(d, 0), np.maximum(e, 0))


def cyl_y(p, c, r, h):
    """Trụ nằm theo trục y (hướng nhìn): mặt tròn quay về máy ảnh."""
    x, y, z = p
    d = length2(x - c[0], z - c[2]) - r
    e = np.abs(y - c[1]) - h
    return np.minimum(np.maximum(d, e), 0) + length2(np.maximum(d, 0), np.maximum(e, 0))


def union(*fns):
    def sdf(p):
        d = None
        for f in fns:
            v = f(p)
            d = v if d is None else np.minimum(d, v)
        return d
    return sdf


def tex_sampler(img):
    """Ảnh PIL → hàm lấy mẫu song tuyến (u, v ∈ [0, 1], v = 0 ở trên) trả về
    (màu tuyến tính, alpha)."""
    a = np.asarray(img.convert('RGBA'), np.float64) / 255.0
    h, w = a.shape[:2]

    def sample(u, v):
        fx = np.clip(u, 0, 1) * (w - 1)
        fy = np.clip(v, 0, 1) * (h - 1)
        x0 = np.floor(fx).astype(np.int64)
        y0 = np.floor(fy).astype(np.int64)
        x1 = np.minimum(x0 + 1, w - 1)
        y1 = np.minimum(y0 + 1, h - 1)
        tx = (fx - x0)[:, None]
        ty = (fy - y0)[:, None]
        c = (a[y0, x0] * (1 - tx) + a[y0, x1] * tx) * (1 - ty) + (a[y1, x0] * (1 - tx) + a[y1, x1] * tx) * ty
        return c[:, :3] ** 2.2, c[:, 3]
    return sample


def decal(sample, x0, x1, z0, z1, front_y=None, face=-1, keep_alpha=True):
    """Hàm tint dán ảnh lên mặt phẳng đứng (nhìn từ phía trước): u theo x,
    v theo z. Chỉ dán ở mặt có pháp tuyến quay về phía [face] (-1: trước)."""
    def tint(p, n, alb, idx):
        x, y, z = p
        u = (x - x0) / (x1 - x0)
        v = (z1 - z) / (z1 - z0)
        inside = (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1) & (n[1] * face > 0.5)
        if front_y is not None:
            inside &= np.abs(y - front_y) < 0.02
        if not inside.any():
            return alb
        col, a = sample(u[inside], v[inside])
        out = alb.copy()
        if keep_alpha:
            out[inside] = col * a[:, None] + alb[inside] * (1 - a[:, None])
        else:
            out[inside] = col
        return out
    return tint


# ============================================================ Máy ảnh
class View:
    """Một cảnh billboard: [objs] vật đục, [glass] kính / nhựa trong (vẽ lớp
    riêng rồi phủ lên), [ppm] điểm ảnh / m trên mặt phẳng ảnh, [ss] số mẫu
    mỗi chiều, [catch] độ đậm bóng hứng trên mặt đất (0 = tắt), [glow] bán
    kính quầng sáng (px) quanh vật tự phát sáng."""

    def __init__(self, objs, ppm, ss=4, glass=(), ao_scale=1.0, catch=0.55, glow=0, bounds=None,
                 dist=CAM_DIST, eye=EYE_H, pad=0.03, shadow_k=10.0, fit_h=None, front='auto'):
        self.objs = list(objs)
        self.glass = list(glass)
        self.ppm, self.ss = ppm, ss
        self.ao_scale = ao_scale
        self.catch, self.glow = catch, glow
        self.dist, self.eye = dist, eye
        self.shadow_k = shadow_k
        allo = self.objs + self.glass
        if bounds is None:
            bounds = ((-6, -1.5, 0), (6, 4.5, 7.5))
        self.bounds = np.array(bounds, np.float64)
        self.y0 = 0.0
        self._fit(allo, fit_h)
        # mặt phẳng ảnh đi qua mép trước chân đế (phần sát đất)
        if front == 'auto':
            self.y0 = self.ground_front
        elif front is not None:
            self.y0 = float(front)
        live = [o for o in allo if o.lo[0] < o.hi[0]]
        lo = np.min([o.lo for o in live], 0)
        hi = np.max([o.hi for o in live], 0)
        self.box_lo, self.box_hi = lo, hi
        # vùng hứng bóng trên mặt đất: chân đế nới rộng một chút
        mpad = float(np.clip(0.2 * max(hi[0] - lo[0], hi[2] - lo[2]), 0.02, 0.12))
        self.catch_lo = (lo[0] - mpad, max(lo[1], self.y0) - 0.05)
        self.catch_hi = (hi[0] + mpad, hi[1] + mpad)
        # khung ảnh: chiếu 8 đỉnh hộp bao lên mặt phẳng y = 0
        xs, zs = [], []
        for cx in (lo[0], hi[0]):
            for cy in (max(lo[1], self.y0 - 0.5), hi[1]):
                for cz in (lo[2], hi[2]):
                    X, Z = self.project(cx, cy, cz)
                    xs.append(X)
                    zs.append(Z)
        m = max(abs(min(xs)), abs(max(xs))) + pad
        top = max(zs) + pad
        self.w = int(math.ceil(2 * m * ppm)) // 2 * 2 + 2
        self.h = int(math.ceil(top * ppm)) + 1
        self.origin = (self.w / 2.0, float(self.h))

    def project(self, x, y, z):
        k = self.dist / (self.dist + y - self.y0)
        return x * k, self.eye + (z - self.eye) * k

    def _fit(self, objs, h):
        """Hộp bao từng vật: dò thô trên cả vùng [bounds], rồi dò mịn trong
        hộp thô (vật mảnh như dây, cột vẫn bắt được)."""
        lo0, hi0 = self.bounds
        hc = max(hi0 - lo0) / 70.0
        gx, gy, gz = self._grid(lo0, hi0, hc)
        front = np.inf
        for o in objs:
            d = self._eval_chunks(o, gx, gy, gz)
            m = d < hc * 1.0
            if not m.any():
                o.lo = np.array([1e9] * 3)
                o.hi = np.array([-1e9] * 3)
                continue
            lo = np.array([gx[m].min(), gy[m].min(), gz[m].min()]) - hc
            hi = np.array([gx[m].max(), gy[m].max(), gz[m].max()]) + hc
            hf = h or float(np.clip(max(hi - lo) / 90.0, 0.004, 0.04))
            fx, fy, fz = self._grid(lo, hi, hf)
            d = self._eval_chunks(o, fx, fy, fz)
            m = d < hf * 1.6
            if not m.any():
                m = d < hc
            low = (d < hf * 0.5) & (fz < 0.12)
            if low.any():
                front = min(front, fy[low].min())
            pad = hf * 1.8
            o.lo = np.array([fx[m].min(), fy[m].min(), max(fz[m].min(), -0.01)]) - pad
            o.hi = np.array([fx[m].max(), fy[m].max(), fz[m].max()]) + pad
        self.ground_front = front if np.isfinite(front) else 0.0

    @staticmethod
    def _grid(lo, hi, h):
        xs = np.arange(lo[0], hi[0] + h, h)
        ys = np.arange(lo[1], hi[1] + h, h)
        zs = np.arange(max(lo[2], -0.02), hi[2] + h, h)
        gx, gy, gz = np.meshgrid(xs, ys, zs, indexing='ij')
        return gx.ravel(), gy.ravel(), gz.ravel()

    @staticmethod
    def _eval_chunks(o, gx, gy, gz):
        d = np.empty(gx.shape)
        step = 300000
        for i in range(0, gx.size, step):
            d[i:i + step] = o.sdf((gx[i:i + step], gy[i:i + step], gz[i:i + step]))
        return d

    # v3.Scene.eval / v3.ambient_occ dùng các thuộc tính này
    eval = v3.Scene.eval


def ray_boxes(objs, ro, rd):
    """Khoảng [t0, t1] tia cắt hợp các hộp bao (t0 = inf nếu trượt hết)."""
    n = rd.shape[0]
    t0 = np.full(n, np.inf)
    t1 = np.full(n, -np.inf)
    inv = 1.0 / np.where(np.abs(rd) < 1e-9, 1e-9, rd)
    for o in objs:
        if o.lo[0] > o.hi[0]:
            continue
        a = (o.lo[None, :] - ro[None, :]) * inv
        b = (o.hi[None, :] - ro[None, :]) * inv
        tn = np.minimum(a, b).max(1)
        tf = np.maximum(a, b).min(1)
        ok = (tf > np.maximum(tn, 0))
        t0 = np.where(ok, np.minimum(t0, np.maximum(tn, 0)), t0)
        t1 = np.where(ok, np.maximum(t1, tf), t1)
    return t0, t1


def march(view, ro, rd, t0, t1, objs, pix):
    """Dò tia phối cảnh. Trả về (trúng?, t, id vật)."""
    n = rd.shape[0]
    t = t0.copy()
    hit = np.zeros(n, bool)
    alive = np.flatnonzero(np.isfinite(t0))
    for _ in range(500):
        if alive.size == 0:
            break
        ta = t[alive]
        pa = (ro[0] + rd[alive, 0] * ta, ro[1] + rd[alive, 1] * ta, ro[2] + rd[alive, 2] * ta)
        d = view.eval(pa, objs)
        eps = 0.3 * pix * ta / view.dist
        got = d < eps
        hit[alive[got]] = True
        tn = ta + np.maximum(d * 0.85, eps * 0.5)
        t[alive] = np.where(got, ta, tn)
        alive = alive[~got & (tn < t1[alive])]
    hi = np.flatnonzero(hit)
    for _ in range(4):
        if hi.size == 0:
            break
        th = t[hi]
        d = view.eval((ro[0] + rd[hi, 0] * th, ro[1] + rd[hi, 1] * th, ro[2] + rd[hi, 2] * th), objs)
        t[hi] = th + d * 0.9
    oid = np.full(n, -1, np.int32)
    if hi.size:
        th = t[hi]
        _, o = view.eval((ro[0] + rd[hi, 0] * th, ro[1] + rd[hi, 1] * th, ro[2] + rd[hi, 2] * th), objs,
                         want_id=True)
        oid[hi] = o
    return hit, t, oid


def soft_shadow(view, p, nrm, objs, pix, k=None, tmax=6.0):
    k = view.shadow_k if k is None else k
    x, y, z = p
    n = x.shape[0]
    res = np.ones(n)
    bias = 2.0 * pix
    t = np.full(n, bias * 2)
    ox, oy, oz = x + nrm[0] * bias, y + nrm[1] * bias, z + nrm[2] * bias
    alive = np.arange(n)
    ztop = view.box_hi[2] + 0.05
    for _ in range(120):
        if alive.size == 0:
            break
        ta = t[alive]
        q = (ox[alive] + SUN[0] * ta, oy[alive] + SUN[1] * ta, oz[alive] + SUN[2] * ta)
        h = view.eval(q, objs, cap=0.3, cast_only=True)
        r = np.minimum(res[alive], k * h / ta)
        res[alive] = r
        t[alive] = ta + np.clip(h, 0.004, 0.15)
        keep = (r > 0.002) & (t[alive] < tmax) & (q[2] < ztop)
        alive = alive[keep]
    res = np.clip(res, 0, 1)
    return res * res * (3 - 2 * res)


def ggx(nx, ny, nz, V, rough, f0):
    """Phản xạ nắng GGX (đã nhân NdotL) với hướng nhìn V (mỗi điểm một hướng)."""
    hx, hy, hz = SUN[0] + V[0], SUN[1] + V[1], SUN[2] + V[2]
    hl = np.maximum(length3(hx, hy, hz), 1e-9)
    hx, hy, hz = hx / hl, hy / hl, hz / hl
    nh = np.clip(nx * hx + ny * hy + nz * hz, 0, 1)
    nl = np.clip(nx * SUN[0] + ny * SUN[1] + nz * SUN[2], 0, 1)
    nv = np.clip(nx * V[0] + ny * V[1] + nz * V[2], 1e-3, 1)
    a = np.maximum(rough * rough, 0.002)
    a2 = a * a
    dd = a2 / (math.pi * (nh * nh * (a2 - 1) + 1) ** 2)
    kk = a / 2
    vis = 1.0 / ((nl * (1 - kk) + kk) * (nv * (1 - kk) + kk))
    vh = np.clip(V[0] * hx + V[1] * hy + V[2] * hz, 0, 1)
    f = f0 + (1 - f0) * (1 - vh) ** 5
    return dd * vis * 0.25 * f * nl


def shade(nrm, V, ma, shadow, ao):
    nx, ny, nz = nrm
    alb = ma['albedo']
    rough, metal, coat, sheen = ma['rough'], ma['metal'], ma['coat'], ma['sheen']
    wrap, spec = ma['wrap'], ma['spec']
    nl_raw = nx * SUN[0] + ny * SUN[1] + nz * SUN[2]
    nl = np.clip((nl_raw + wrap) / (1 + wrap), 0, 1)
    ndv = nx * V[0] + ny * V[1] + nz * V[2]
    nv = np.clip(ndv, 0, 1)
    sun = SUN_COL[None, :] * (nl * shadow)[:, None]
    hemi = 0.5 + 0.5 * nz
    amb = (SKY_IRR[None, :] * hemi[:, None] + GROUND_IRR[None, :] * (1 - hemi)[:, None]) * ao[:, None]
    diff = alb * (sun + amb) * (1 - metal)[:, None]
    f0 = (0.08 * spec)[:, None] * (1 - metal)[:, None] + alb * metal[:, None]
    rx, ry, rz = 2 * ndv * nx - V[0], 2 * ndv * ny - V[1], 2 * ndv * nz - V[2]
    e = v3.env(rx, ry, rz, rough)
    fres = (1 - nv) ** 5
    fr = f0 + (np.maximum(1 - rough, f0.mean(1))[:, None] - f0) * fres[:, None]
    spec_occ = np.clip(ao * 1.15 - 0.1, 0, 1) * (0.35 + 0.65 * shadow)
    base = diff + fr * e * spec_occ[:, None]
    base = base + SUN_COL[None, :] * (ggx(nx, ny, nz, V, np.maximum(rough, 0.04), 1.0)[:, None] * f0) * shadow[:, None]
    base = base + alb * (sheen * (1 - nv) ** 2.5 * 0.9)[:, None] * (SKY_IRR[None, :] * ao[:, None] + sun * 0.4)
    if np.any(coat > 0):
        fc = 0.04 + 0.96 * fres
        ce = v3.env(rx, ry, rz, np.full_like(rough, 0.02))
        cs = SUN_COL[None, :] * ggx(nx, ny, nz, V, np.full_like(rough, 0.11), 0.04)[:, None] * shadow[:, None]
        cl = ce * fc[:, None] * spec_occ[:, None] + cs
        base = base * (1 - (coat * fc)[:, None]) + cl * coat[:, None]
    base = base + alb * ma['emit'][:, None]
    return base


def shade_hits(view, objs, P, V, oid, pix, shadow_objs=None):
    """Tô màu các điểm trúng [P] (bộ 3 mảng). Trả về (rgb tuyến tính, alpha,
    độ phát sáng)."""
    n = P[0].shape[0]
    nrm = v3.normals(objs, oid, P, 0.35 * pix)
    ma = {'albedo': np.zeros((n, 3))}
    for f in MAT_FIELDS:
        ma[f] = np.zeros(n)
    for i, o in enumerate(objs):
        sel = np.flatnonzero(oid == i)
        if sel.size == 0:
            continue
        ps = (P[0][sel], P[1][sel], P[2][sel])
        ns = (nrm[0][sel], nrm[1][sel], nrm[2][sel])
        idx = o.pick(ps, ns) if o.pick else np.zeros(sel.size, np.int32)
        sub = mat_arrays(o.mats, idx, sel.size)
        if o.tint is not None:
            sub['albedo'] = o.tint(ps, ns, sub['albedo'], idx)
        for k, v in sub.items():
            ma[k][sel] = v
    # mặt bị nhìn từ phía sau (vỏ mỏng): lật pháp tuyến về phía máy ảnh
    flip = (nrm[0] * V[0] + nrm[1] * V[1] + nrm[2] * V[2]) < -0.05
    if flip.any():
        nrm = (np.where(flip, -nrm[0], nrm[0]), np.where(flip, -nrm[1], nrm[1]), np.where(flip, -nrm[2], nrm[2]))
    so = view.objs if shadow_objs is None else shadow_objs
    sh = soft_shadow(view, P, nrm, so, pix)
    ao = v3.ambient_occ(view, P, nrm, so)
    col = shade(nrm, V, ma, sh, ao)
    alpha = 1 - ma['clear'] * np.clip(nrm[0] * V[0] + nrm[1] * V[1] + nrm[2] * V[2], 0, 1) ** 0.7
    emit = ma['emit'] * ma['albedo'].max(1)
    return col, alpha, emit, ma


_VIEW = None


def render_rows(args):
    r0, r1 = args
    view = _VIEW
    ss = view.ss
    W = view.w * ss
    pix = 1.0 / (view.ppm * ss)
    ys = (np.arange(r0, r1) + 0.5) / ss
    xs = (np.arange(W) + 0.5) / ss
    px, py = np.meshgrid(xs, ys)
    X = ((px - view.origin[0]) / view.ppm).ravel()
    Z = ((view.origin[1] - py) / view.ppm).ravel()
    n = X.shape[0]
    ro = np.array([0.0, view.y0 - view.dist, view.eye])
    rd = np.stack([X, np.full(n, view.dist), Z - view.eye], 1)
    rd /= np.linalg.norm(rd, axis=1)[:, None]
    rgb = np.zeros((n, 3))
    alpha = np.zeros(n)
    emit = np.zeros(n)
    tdep = np.full(n, np.inf)
    t0, t1 = ray_boxes(view.objs, ro, rd)
    cand = np.flatnonzero(np.isfinite(t0))
    if cand.size:
        hit, t, oid = march(view, ro, rd[cand], t0[cand], t1[cand], view.objs, pix)
        hc = cand[hit]
        if hc.size:
            th = t[hit]
            P = (ro[0] + rd[hc, 0] * th, ro[1] + rd[hc, 1] * th, ro[2] + rd[hc, 2] * th)
            V = (-rd[hc, 0], -rd[hc, 1], -rd[hc, 2])
            col, a, em, _ = shade_hits(view, view.objs, P, V, oid[hit], pix)
            rgb[hc], alpha[hc], emit[hc], tdep[hc] = col, a, em, th
    # mặt đất hứng bóng (chỉ alpha đen)
    if view.catch > 0:
        miss = np.flatnonzero((alpha < 0.999) & (rd[:, 2] < -1e-4))
        if miss.size:
            tg = -ro[2] / rd[miss, 2]
            gx = ro[0] + rd[miss, 0] * tg
            gy = ro[1] + rd[miss, 1] * tg
            lo, hi = view.catch_lo, view.catch_hi
            fade = (smoothstep(lo[0], lo[0] + 0.15, gx) * smoothstep(hi[0], hi[0] - 0.15, gx)
                    * smoothstep(lo[1], lo[1] + 0.05, gy) * smoothstep(hi[1], hi[1] - 0.15, gy))
            sel = np.flatnonzero((fade > 0) & (tg < tdep[miss]))
            if sel.size:
                m = miss[sel]
                G = (gx[sel], gy[sel], np.zeros(sel.size))
                up = (np.zeros(sel.size), np.zeros(sel.size), np.ones(sel.size))
                sh = soft_shadow(view, G, up, view.objs, pix)
                ao = v3.ambient_occ(view, G, up, view.objs)
                s = np.clip((1 - sh) * 0.8 + (1 - ao) * 0.9, 0, 1) * view.catch * fade[sel]
                a0 = alpha[m]
                # bóng nằm sau vật (vật trong suốt một phần như nilon)
                rgb[m] = rgb[m] * (a0 / np.maximum(a0 + s * (1 - a0), 1e-6))[:, None]
                alpha[m] = a0 + s * (1 - a0)
    # kính / nhựa trong: lớp riêng phủ lên trước
    if view.glass:
        g0, g1 = ray_boxes(view.glass, ro, rd)
        gc = np.flatnonzero(np.isfinite(g0))
        if gc.size:
            hit, t, oid = march(view, ro, rd[gc], g0[gc], g1[gc], view.glass, pix)
            gh = gc[hit]
            th = t[hit]
            front = th < tdep[gh]
            gh, th, go = gh[front], th[front], oid[hit][front]
            if gh.size:
                P = (ro[0] + rd[gh, 0] * th, ro[1] + rd[gh, 1] * th, ro[2] + rd[gh, 2] * th)
                V = (-rd[gh, 0], -rd[gh, 1], -rd[gh, 2])
                nrm = v3.normals(view.glass, go, P, 0.35 * pix)
                nv = np.abs(nrm[0] * V[0] + nrm[1] * V[1] + nrm[2] * V[2])
                fres = 0.06 + 0.94 * (1 - nv) ** 4
                ndv = nrm[0] * V[0] + nrm[1] * V[1] + nrm[2] * V[2]
                sgn = np.sign(ndv)
                nn = (nrm[0] * sgn, nrm[1] * sgn, nrm[2] * sgn)
                ndv = np.abs(ndv)
                r = (2 * ndv * nn[0] - V[0], 2 * ndv * nn[1] - V[1], 2 * ndv * nn[2] - V[2])
                refl = v3.env(r[0], r[1], r[2], np.full(gh.size, 0.04)) * fres[:, None] * 1.3
                refl += SUN_COL[None, :] * ggx(nn[0], nn[1], nn[2], V, np.full(gh.size, 0.06), 0.05)[:, None]
                tint = np.array([0.80, 0.86, 0.88])
                a_b = alpha[gh]
                ga = 0.10 + 0.55 * fres  # độ phủ của kính khi phía sau trống
                # premultiplied: phản chiếu + nhìn xuyên (nhuộm màu kính)
                pre = refl * 1.0 + rgb[gh] * a_b[:, None] * tint[None, :] * (1 - fres)[:, None]
                na = a_b + ga * (1 - a_b)
                rgb[gh] = pre / np.maximum(na, 1e-6)[:, None]
                alpha[gh] = na
    return rgb.reshape(r1 - r0, W, 3), alpha.reshape(r1 - r0, W), emit.reshape(r1 - r0, W)


def render(view, procs=8):
    global _VIEW
    _VIEW = view
    H = view.h * view.ss
    chunk = max(view.ss * 2, (H // (procs * 4)) // view.ss * view.ss)
    jobs = [(r, min(H, r + chunk)) for r in range(0, H, chunk)]
    if procs > 1:
        with mp.get_context('fork').Pool(procs) as pool:
            parts = pool.map(render_rows, jobs)
    else:
        parts = [render_rows(j) for j in jobs]
    rgb = np.concatenate([p[0] for p in parts], 0)
    alpha = np.concatenate([p[1] for p in parts], 0)
    emit = np.concatenate([p[2] for p in parts], 0)
    return rgb, alpha, emit


def finish(view, rgb, alpha, emit):
    """Tone-map, thu nhỏ, (quầng sáng), cắt sát. Trả về ảnh PIL RGBA."""
    ss = view.ss
    w, h = view.w, view.h
    col = v3.tonemap(rgb)
    pre = col * alpha[..., None]
    pre = pre.reshape(h, ss, w, ss, 3).mean((1, 3))
    a = alpha.reshape(h, ss, w, ss).mean((1, 3))
    if view.glow:
        # quầng sáng quanh đèn đang bật: lấy màu phần tự phát sáng, nhoè Gauss
        e = emit.reshape(h, ss, w, ss).mean((1, 3))
        ecol = pre * np.clip(e, 0, 1)[..., None]
        acc = np.zeros_like(ecol)
        for c in range(3):
            im = Image.fromarray(np.clip(ecol[..., c] * 255, 0, 255).astype(np.uint8))
            acc[..., c] = np.asarray(im.filter(ImageFilter.GaussianBlur(view.glow)), np.float64) / 255
        acc *= 2.2
        ga = np.clip(acc.max(2), 0, 1)
        pre = pre + acc * (1 - a)[..., None]
        a = a + ga * (1 - a)
    rgb8 = np.where(a[..., None] > 1e-4, pre / np.maximum(a[..., None], 1e-4), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(rgb8 * 255 + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return crop(Image.fromarray(out))


def crop(img, keep_bottom=True):
    """Cắt sát theo alpha, giữ đối xứng quanh cột giữa và giữ nguyên đáy."""
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > 2)
    if ys.size == 0:
        return img
    w, h = img.size
    cx = w / 2.0
    m = max(cx - xs.min(), xs.max() + 1 - cx)
    left = int(math.floor(cx - m)) - 1
    right = int(math.ceil(cx + m)) + 1
    left, right = max(left, 0), min(right, w)
    top = max(ys.min() - 1, 0)
    bottom = h if keep_bottom else ys.max() + 1
    return img.crop((left, top, right, bottom))


# ============================================================ Ghi file
REGISTRY = {}


def save_img(img, out, name, ppm, kind, **extra):
    img.save(f'{out}/{name}.png', optimize=True)
    w, h = img.size
    REGISTRY[name] = dict(h_m=round(h / ppm, 3), w_m=round(w / ppm, 3), kind=kind, **extra)
    return img


def shoot(out, name, objs, ppm, kind, ss=4, glass=(), bounds=None, catch=0.55, glow=0, ao_scale=1.0, extra=None,
          post=None, fit_h=None, shadow_k=10.0, front='auto'):
    t0 = time.time()
    view = View(objs, ppm, ss=ss, glass=glass, bounds=bounds, catch=catch, glow=glow, ao_scale=ao_scale,
                fit_h=fit_h, shadow_k=shadow_k, front=front)
    rgb, alpha, emit = render(view)
    img = finish(view, rgb, alpha, emit)
    if post is not None:
        img = post(img)
    ex = dict(extra or {})
    # bề sâu chân đế tính từ mép trước (đáy ảnh) vào trong
    ex.setdefault('depth_m', round(float(view.box_hi[1] - view.y0), 2))
    save_img(img, out, name, ppm, kind, **ex)
    print(f'{name}: {img.size[0]}x{img.size[1]}  {time.time() - t0:.1f}s', flush=True)
    return img


# ============================================================ Dời / xoay
def rot_mat(axis, ang):
    """Ma trận quay quanh trục 'x' / 'y' / 'z' (quy tắc bàn tay phải)."""
    c, s_ = math.cos(ang), math.sin(ang)
    if axis == 'x':
        return np.array([[1, 0, 0], [0, c, -s_], [0, s_, c]])
    if axis == 'y':
        return np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
    return np.array([[c, -s_, 0], [s_, c, 0], [0, 0, 1]])


def placed(objs, dx=0.0, dy=0.0, dz=0.0, yaw=0.0, scale=1.0, R=None):
    """Đặt một nhóm vật (mô hình toạ độ riêng) vào cảnh: quay [R] (ma trận
    riêng → cảnh) hoặc [yaw] quanh trục đứng (dương: ngược chiều kim đồng hồ
    nhìn từ trên), phóng [scale], rồi dời (dx, dy, dz)."""
    M = np.asarray(R, np.float64) if R is not None else rot_mat('z', yaw)
    Mt = M.T

    def to_local(p):
        x, y, z = p[0] - dx, p[1] - dy, p[2] - dz
        return ((Mt[0, 0] * x + Mt[0, 1] * y + Mt[0, 2] * z) / scale,
                (Mt[1, 0] * x + Mt[1, 1] * y + Mt[1, 2] * z) / scale,
                (Mt[2, 0] * x + Mt[2, 1] * y + Mt[2, 2] * z) / scale)

    def n_local(n):
        return (Mt[0, 0] * n[0] + Mt[0, 1] * n[1] + Mt[0, 2] * n[2],
                Mt[1, 0] * n[0] + Mt[1, 1] * n[1] + Mt[1, 2] * n[2],
                Mt[2, 0] * n[0] + Mt[2, 1] * n[1] + Mt[2, 2] * n[2])

    def n_world(n):
        return (M[0, 0] * n[0] + M[0, 1] * n[1] + M[0, 2] * n[2],
                M[1, 0] * n[0] + M[1, 1] * n[1] + M[1, 2] * n[2],
                M[2, 0] * n[0] + M[2, 1] * n[1] + M[2, 2] * n[2])

    out = []
    for o in objs:
        sdf = (lambda f: (lambda p: f(to_local(p)) * scale))(o.sdf)
        pick = None if o.pick is None else (lambda f: (lambda p, n: f(to_local(p), n_local(n))))(o.pick)
        tint = None if o.tint is None else (lambda f: (lambda p, n, a, i: f(to_local(p), n_local(n), a, i)))(o.tint)
        bump = None if o.bump is None else (lambda f: (lambda p, n: n_world(f(to_local(p), n_local(n)))))(o.bump)
        out.append(Obj(o.name, sdf, o.mats, pick=pick, tint=tint, cast=o.cast, bump=bump))
    return out


# ================================================================ Người
def multi(name, groups, mats, k_out, bump=None, tint=None):
    """Một khối liền từ nhiều nhóm: trong nhóm hoà mềm theo k riêng, các nhóm
    hoà với nhau theo [k_out] (nhỏ → giữ nếp gấp nách, bẹn). Vật liệu mỗi
    điểm theo thành phần gần nhất. groups = [(k, [(sdf, chỉ số vật liệu)])]."""
    def group_d(p, k, comps):
        d = None
        for fn, _ in comps:
            v = fn(p)
            d = v if d is None else smin(d, v, k)
        return d

    def sdf(p):
        d = None
        for k, comps in groups:
            v = group_d(p, k, comps)
            d = v if d is None else smin(d, v, k_out)
        return d

    def pick(p, n):
        best = idx = None
        for _, comps in groups:
            for fn, mi in comps:
                v = fn(p)
                if best is None:
                    best, idx = v, np.full(v.shape, mi, np.int32)
                else:
                    m = v < best
                    best = np.where(m, v, best)
                    idx = np.where(m, mi, idx)
        return idx
    return Obj(name, sdf, mats, pick=pick, bump=bump, tint=tint)


def limb(a, b, r1, r2):
    if abs(r1 - r2) < 1e-5:
        return lambda p: capsule(p, a, b, r1)
    return lambda p: round_cone(p, a, b, r1, r2)


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k)


def unit(v):
    L = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (v[0] / L, v[1] / L, v[2] / L)


SKINS = {
    'tan': (196, 142, 104),
    'mid': (210, 160, 122),
    'light': (226, 182, 146),
    'kid': (232, 188, 152),
    'old': (192, 140, 108),
}
HAIR_BLACK = (26, 22, 20)
HAIR_GREY = (168, 166, 160)


def skin_mat(tone):
    # emit nhỏ: giả tán xạ dưới da để mặt dưới vành nón không đen kịt
    return Mat(SKINS.get(tone, tone) if isinstance(tone, str) else tone, rough=0.52, wrap=0.4, spec=0.38, emit=0.05)


# bông mai trên áo dài: (x, z, bán kính) theo người 1,70 m
FLOWERS = [(0.075, 0.42, 0.026), (0.040, 0.50, 0.020), (0.090, 0.57, 0.017), (0.020, 0.64, 0.024),
           (-0.010, 0.73, 0.016), (0.045, 0.70, 0.013), (-0.030, 0.84, 0.020), (-0.060, 0.93, 0.015),
           (-0.050, 1.12, 0.022), (-0.085, 1.20, 0.016), (-0.020, 1.21, 0.013), (-0.070, 1.30, 0.012)]


class Fig:
    """Khung xương một người (mét, mặt quay về -y). [height] chiều cao (không
    tính mũ), [sex] 'm' / 'f', [head_k] cỡ đầu so với người lớn 1,70 m (trẻ con đầu to so với người)."""

    def __init__(self, height=1.70, sex='m', head=None, girth=1.0):
        hs = head if head else height / 1.70
        self.hs = hs
        # thân: 1,47 m (tới cằm) + đầu 0,23 m
        s = (height - 0.228 * hs) / 1.472
        self.s = s
        self.sex = sex
        f = sex == 'f'
        g = girth
        sw = (0.146 if f else 0.164) * s * g ** 0.5
        self.j = dict(
            head=(0.0, 0.0, 1.472 * s + 0.113 * hs),
            neck0=(0.0, 0.006, 1.38 * s), neck1=(0.0, 0.004, 1.472 * s + 0.03 * hs),
            sh_l=(-sw, 0.012, 1.385 * s), sh_r=(sw, 0.012, 1.385 * s),
            el_l=(-sw - 0.05 * s, 0.035, 1.10 * s), el_r=(sw + 0.05 * s, 0.035, 1.10 * s),
            wr_l=(-sw - 0.066 * s, 0.0, 0.855 * s), wr_r=(sw + 0.066 * s, 0.0, 0.855 * s),
            hip_l=(-0.088 * s * g ** 0.3, 0.012, 0.885 * s), hip_r=(0.088 * s * g ** 0.3, 0.012, 0.885 * s),
            kn_l=(-0.096 * s, 0.0, 0.48 * s), kn_r=(0.096 * s, 0.0, 0.48 * s),
            an_l=(-0.10 * s, 0.03, 0.085 * s), an_r=(0.10 * s, 0.03, 0.085 * s),
        )
        # trục thân (dời / nghiêng khi ngồi)
        self.chest = (0.0, 0.012, 1.25 * s)
        self.waist = (0.0, 0.012, 1.065 * s)
        self.pelvis = (0.0, 0.014, 0.925 * s)
        r = (0.142, 0.10, 0.145) if f else (0.155, 0.106, 0.15)
        self.chest_r = (r[0] * s * g, r[1] * s * g, r[2] * s)
        r = (0.118, 0.088, 0.15) if f else (0.138, 0.096, 0.15)
        self.waist_r = (r[0] * s * g, r[1] * s * g ** 1.5, r[2] * s)
        r = (0.168, 0.112, 0.112) if f else (0.160, 0.106, 0.11)
        self.pelvis_r = (r[0] * s * g, r[1] * s * g, r[2] * s)
        self.hand_dir = {'l': (0.0, -0.05, -1.0), 'r': (0.0, -0.05, -1.0)}
        self.foot_dir = {'l': (0.0, -1.0, 0.0), 'r': (0.0, -1.0, 0.0)}

    lean = 0.0

    def lean_by(self, a):
        """Cúi người về trước góc [a] (rad) quanh khung chậu: dời đầu, cổ,
        vai, tay; các khối thân (ngực, eo) được xoay khi dựng."""
        self.lean = a
        px, py, pz = self.pelvis
        c, s_ = math.cos(a), math.sin(a)
        for k in ('head', 'neck0', 'neck1', 'sh_l', 'sh_r', 'el_l', 'el_r', 'wr_l', 'wr_r'):
            x, y, z = self.j[k]
            yy, zz = y - py, z - pz
            self.j[k] = (x, py + yy * c - zz * s_, pz + yy * s_ + zz * c)

    def unlean(self, p):
        """Đưa điểm về khung thân chưa cúi."""
        if not self.lean:
            return p
        px, py, pz = self.pelvis
        c, s_ = math.cos(self.lean), math.sin(self.lean)
        x, y, z = p
        yy, zz = y - py, z - pz
        return x, py + yy * c + zz * s_, pz - yy * s_ + zz * c

    def arm(self, side, elbow, wrist, hand=None):
        self.j['el_' + side] = elbow
        self.j['wr_' + side] = wrist
        if hand is not None:
            self.hand_dir[side] = hand
        else:
            self.hand_dir[side] = unit((wrist[0] - elbow[0], wrist[1] - elbow[1], wrist[2] - elbow[2]))

    def leg(self, side, knee, ankle, foot=None):
        self.j['kn_' + side] = knee
        self.j['an_' + side] = ankle
        if foot is not None:
            self.foot_dir[side] = foot

    def shift_upper(self, dz, dy=0.0):
        """Dời cả nửa trên (ngồi xuống)."""
        for k in ('head', 'neck0', 'neck1', 'sh_l', 'sh_r', 'el_l', 'el_r', 'wr_l', 'wr_r', 'hip_l', 'hip_r'):
            x, y, z = self.j[k]
            self.j[k] = (x, y + dy, z + dz)
        self.chest = add(self.chest, (0, dy, dz))
        self.waist = add(self.waist, (0, dy, dz))
        self.pelvis = add(self.pelvis, (0, dy, dz))


def head_parts(fig, skin, hair=HAIR_BLACK, style='short', face=True, seed=1, beard=False):
    """Đầu: sọ + hàm + mũi + tai (da), mắt / mày / miệng tô nhỏ (nhìn xa nên
    chỉ chấm nhẹ), tóc là vỏ ôm sọ khoét phần mặt."""
    hx, hy, hz = fig.j['head']
    k = fig.hs
    f = fig.sex == 'f'
    rx, ry, rz = (0.076, 0.091, 0.111) if f else (0.080, 0.095, 0.115)
    rx, ry, rz = rx * k, ry * k, rz * k

    def skull(p):
        return ellipsoid(p, (hx, hy + 0.004 * k, hz), (rx, ry, rz))

    def jaw(p):
        return ellipsoid(p, (hx, hy - 0.012 * k, hz - 0.052 * k), (rx * 0.80, ry * 0.80, rz * 0.66))

    def nose(p):
        return ellipsoid(p, (hx, hy - ry * 0.93, hz - 0.022 * k), (0.012 * k, 0.018 * k, 0.024 * k))

    def ears(p):
        q = (np.abs(p[0] - hx), p[1], p[2])
        return ellipsoid(q, (rx * 0.97, hy + 0.005 * k, hz - 0.012 * k), (0.012 * k, 0.02 * k, 0.028 * k))

    def sdf(p):
        d = smin(skull(p), jaw(p), 0.03 * k)
        d = smin(d, nose(p), 0.012 * k)
        return smin(d, ears(p), 0.006 * k)

    ez = hz - 0.006 * k
    eye_col, brow_col, lip_col = lin((34, 24, 22)), lin(hair if style != 'bald' else (60, 50, 44)), lin((150, 82, 72))

    def tint(p, n, alb, idx):
        if not face:
            return alb
        x, y, z = p
        front = (n[1] < -0.35) & (y < hy - ry * 0.55)
        ax = np.abs(x - hx)
        eye = front & (((ax - 0.030 * k) / (0.0105 * k)) ** 2 + ((z - ez) / (0.0062 * k)) ** 2 < 1)
        brow = front & (np.abs(ax - 0.031 * k) < 0.015 * k) & (np.abs(z - (ez + 0.021 * k + 0.004 * k * (1 - ((ax - 0.031 * k) / 0.015 / k) ** 2))) < 0.0035 * k)
        mouth = front & (ax < 0.017 * k) & (np.abs(z - (hz - 0.064 * k) - 0.002 * k * (ax / 0.017 / k) ** 2) < 0.0034 * k)
        out = np.where(eye[:, None], eye_col, alb)
        out = np.where(brow[:, None], alb * 0.35 + brow_col * 0.65, out)
        out = np.where(mouth[:, None], alb * 0.4 + lip_col * 0.6, out)
        # má hồng nhẹ, cằm râu
        cheek = front & (((ax - 0.038 * k) / 0.02 / k) ** 2 + ((z - hz + 0.032 * k) / 0.015 / k) ** 2 < 1)
        out = np.where(cheek[:, None], out * np.array([1.05, 0.93, 0.90]), out)
        if beard:
            b = (z < hz - 0.05 * k) & ~mouth & (y < hy)
            out = np.where(b[:, None], out * 0.55 + lin((70, 60, 52)) * 0.45, out)
        return out
    parts = [Obj('head', sdf, skin, tint=tint)]

    if style in ('bald', None):
        return parts
    hmat = Mat(hair, rough=0.42, sheen=0.7, spec=0.55, wrap=0.2)
    line_z = hz + (0.040 if f else 0.046) * k

    def hair_cap(p):
        x, y, z = p
        e = ellipsoid(p, (hx, hy + 0.008 * k, hz + 0.003 * k), (rx + 0.0065 * k, ry + 0.008 * k, rz + 0.0055 * k))
        face_cut = smax(z - line_z + 0.012 * (np.abs(x - hx) / rx) ** 2 * k, y - hy + 0.012 * k, 0.012 * k)
        d = smax(e, -face_cut, 0.008 * k)
        low = hz - (0.06 if style != 'crop' else 0.03) * k
        return smax(d, low - z + 0.04 * np.clip(-(y - hy) / ry, 0, 1), 0.01 * k)

    comps = [hair_cap]
    if style in ('long', 'bun', 'pony'):
        def back(p):
            x, y, z = p
            if style == 'long':
                a = round_cone(p, (hx, hy + 0.045 * k, hz - 0.02 * k), (hx, hy + 0.07 * k, hz - 0.29 * k), 0.085 * k, 0.07 * k)
                sides = ellipsoid((np.abs(x - hx), y, z), (0.07 * k, hy + 0.03 * k, hz - 0.13 * k), (0.035 * k, 0.05 * k, 0.12 * k))
                return smin(a, sides, 0.03 * k)
            if style == 'bun':
                return ellipsoid(p, (hx, hy + 0.098 * k, hz + 0.02 * k), (0.048 * k, 0.04 * k, 0.042 * k))
            return round_cone(p, (hx, hy + 0.09 * k, hz + 0.0 * k), (hx, hy + 0.12 * k, hz - 0.17 * k), 0.035 * k, 0.022 * k)
        comps.append(back)

    def hair_sdf(p):
        d = None
        for c in comps:
            v = c(p)
            d = v if d is None else smin(d, v, 0.02 * k)
        return d

    def strands(x, y, z):
        return np.sin((x - hx) * 420 / k + fbm(x * 60, z * 60, seed, 2) * 4) * 0.5 + np.sin(z * 300 / k) * 0.2
    parts.append(Obj('hair', hair_sdf, hmat, bump=field_bump(strands, 0.0012)))
    return parts


def hat_parts(fig, kind, color=None, seed=3):
    hx, hy, hz = fig.j['head']
    k = fig.hs
    top = hz + 0.112 * k
    if kind == 'conical':
        straw = Mat(color or (226, 204, 150), rough=0.7, wrap=0.35, spec=0.35, sheen=0.25)
        base = (hx, hy + 0.01, top - 0.075 * k)

        def sdf(p):
            return cone_shell(p, base, 0.215 * k, 0.175 * k, 0.0035)

        def tint(p, n, alb, idx):
            x, y, z = p
            r = length2(x - base[0], y - base[1])
            ring = np.abs(((r / k) % 0.032) - 0.016) < 0.0022
            rib = np.abs(np.sin(np.arctan2(y - base[1], x - base[0]) * 16)) < 0.07
            under = n[2] < 0
            out = np.where(ring[:, None], alb * 0.72, alb)
            out = np.where(rib[:, None], out * 0.88, out)
            return np.where(under[:, None], out * 0.85, out)
        return [Obj('conical', sdf, straw, tint=tint)]
    if kind == 'beanie':
        wool = fabric(color or (150, 30, 36), rough=0.9, sheen=0.4)

        def sdf(p):
            x, y, z = p
            e = ellipsoid(p, (hx, hy + 0.01 * k, hz + 0.024 * k), (0.092 * k, 0.106 * k, 0.108 * k))
            return smax(e, hz + 0.03 * k - z - 0.035 * k * np.clip((y - hy) / 0.09 / k, 0, 1), 0.01 * k)

        def rib(x, y, z):
            return np.sin(np.arctan2(y - hy, x - hx) * 60) * (z < hz + 0.06 * k)
        return [Obj('beanie', sdf, wool, bump=field_bump(rib, 0.0015))]
    if kind == 'cap':
        cl = Mat(color or (196, 30, 32), rough=0.7, sheen=0.35, wrap=0.2, spec=0.35)

        def dome(p):
            x, y, z = p
            e = ellipsoid(p, (hx, hy + 0.008 * k, hz + 0.018 * k), (0.092 * k, 0.106 * k, 0.106 * k))
            return smax(e, hz + 0.030 * k - z, 0.008 * k)

        def bill(p):
            x, y, z = p
            yb, zb = rot(y - (hy - 0.115 * k), z - (hz + 0.032 * k), 0.16)
            d = ellipsoid((x, yb, zb), (hx, 0, 0), (0.078 * k, 0.088 * k, 0.006 * k))
            return smax(d, yb - 0.02 * k, 0.004)

        def tint(p, n, alb, idx):
            x, y, z = p
            # nút trên đỉnh, đường may
            seam = (np.abs(x - hx) < 0.003) & (z > hz + 0.05 * k)
            return np.where(seam[:, None], alb * 0.7, alb)
        return [Obj('cap', lambda p: smin(dome(p), bill(p), 0.006 * k), cl, tint=tint)]
    if kind == 'kepi':
        olive = Mat(color or (92, 98, 56), rough=0.6, sheen=0.3, wrap=0.2, spec=0.4)
        band = Mat((38, 40, 30), rough=0.5, sheen=0.2)
        visor = Mat((20, 20, 20), rough=0.12, spec=1.0, coat=0.8)
        zc = hz + 0.03 * k

        def crown(p):
            x, y, z = p
            # chóp mũ: đáy ôm đầu, loe rộng lên trên, mặt trên hơi nghiêng ra trước
            t = np.clip((z - zc) / (0.11 * k), 0, 1)
            r = (0.093 + 0.042 * t) * k
            rr = length2((x - hx) / 1.0, (y - hy - 0.004) / 1.08)
            d = rr - r
            top = z - (zc + 0.105 * k - 0.03 * (y - hy) * -1.0)
            return smax(smax(d, top, 0.02 * k), zc - z, 0.005)

        def peak(p):
            x, y, z = p
            yb, zb = rot(y - (hy - 0.1 * k), z - (zc + 0.008 * k), 0.38)
            d = ellipsoid((x, yb, zb), (hx, 0, 0), (0.085 * k, 0.065 * k, 0.005 * k))
            return smax(d, yb - 0.01 * k, 0.004)

        def pick(p, n):
            x, y, z = p
            b = (z < zc + 0.035 * k) & (z > zc - 0.01)
            pk = peak(p) < 0.004
            return np.where(pk, 2, np.where(b, 1, 0)).astype(np.int32)
        return [Obj('kepi', lambda p: np.minimum(crown(p), peak(p)), [olive, band, visor], pick=pick)]
    if kind == 'flatcap':
        cl = fabric(color or (70, 66, 60), rough=0.85, sheen=0.4)

        def sdf(p):
            x, y, z = p
            yb, zb = rot(y - hy, z - (hz + 0.07 * k), 0.12)
            body = ellipsoid((x, yb, zb), (hx, -0.01 * k, 0), (0.098 * k, 0.112 * k, 0.045 * k))
            brim = ellipsoid((x, yb, zb), (hx, -0.085 * k, -0.018 * k), (0.07 * k, 0.05 * k, 0.012 * k))
            return smin(body, brim, 0.01)
        return [Obj('flatcap', sdf, cl, bump=fabric_bump(90, 0.001, seed))]
    return []


def person(fig, top, bottom, skin='mid', hair=HAIR_BLACK, hair_style='short', hat=None, hat_color=None,
           kind='jacket', shoes=(36, 34, 34), puffy=0.0, hem=None, collar=None, scarf=None, zipper=True,
           seed=5, stripes=None, face=True, beard=False, sleeves=None, gloves=None, apron=None, aodai=None):
    """Dựng một người theo khung [fig]. [top] / [bottom] màu áo / quần; [kind]:
    'jacket' áo khoác (puffy > 0: áo phao chần bông), 'shirt' sơ mi, 'coat'
    áo khoác dài, 'aodai' áo dài (aodai = màu hoạ tiết), 'uniform' CSGT
    (stripes = màu dải phản quang)."""
    j = fig.j
    s = fig.s
    sk = skin_mat(skin)
    th = 0.012 + puffy  # độ dày áo
    if kind == 'shirt':
        topm = fabric(top, rough=0.8, sheen=0.35)
        th = 0.006
    elif kind == 'aodai':
        topm = Mat(top, rough=0.38, sheen=0.75, wrap=0.3, spec=0.7)
        th = 0.002
    elif kind == 'uniform':
        topm = fabric(top, rough=0.75, sheen=0.4)
        th = 0.010
    else:
        topm = fabric(top, rough=0.62 if puffy > 0 else 0.85, sheen=0.55 if puffy > 0 else 0.45)
    botm = fabric(bottom, rough=0.85, sheen=0.3) if kind != 'aodai' else Mat(bottom, rough=0.45, sheen=0.7, wrap=0.3, spec=0.6)
    if hem is None:
        hem = {'coat': 0.66, 'shirt': 0.90, 'aodai': 0.90, 'uniform': 0.94}.get(kind, 0.84) * s
    parts = []

    # ---- nửa trên (áo)
    cx, cy, cz = fig.chest
    wx_, wy_, wz_ = fig.waist
    px_, py_, pz_ = fig.pelvis
    cr, wr, pr = fig.chest_r, fig.waist_r, fig.pelvis_r
    shr = j['sh_r']

    def chest(p):
        return ellipsoid(fig.unlean(p), (cx, cy, cz), (cr[0] + th, cr[1] + th, cr[2] + th))

    def waist(p):
        return ellipsoid(fig.unlean(p), (wx_, wy_, wz_), (wr[0] + th, wr[1] + th, wr[2]))

    n0 = j['neck0']

    def yoke(p):
        # cơ thang: dốc xuống từ chân cổ ra hai vai
        q = (np.abs(p[0] - n0[0]), p[1], p[2])
        return capsule(q, (0.045 * s, n0[1] + 0.006, n0[2] + 0.045 * s), (abs(shr[0] - n0[0]) * 0.86, shr[1], shr[2] - 0.018 * s),
                       0.043 * s + th)

    def skirt(p):
        x, y, z = fig.unlean(p)
        # vạt áo phủ hông, cắt ngang ở gấu áo
        fl = 1.0 + (0.12 if kind == 'coat' else 0.0) * np.clip((pz_ - z) / 0.25, 0, 1)
        e = ellipsoid((x / fl, y, z), (px_, py_, pz_ + 0.02), (pr[0] + th + 0.008, pr[1] + th + 0.006, pr[2] + 0.05))
        if kind == 'coat':
            e = smin(e, round_cone(p, (px_, py_, pz_), (px_, py_ + 0.01, hem), pr[0] + th, pr[0] + th + 0.02), 0.05)
        return smax(e, hem - z, 0.012)

    upper = [(0.07 * s, [(chest, 0), (waist, 0), (yoke, 0), (skirt, 0)])]

    def arm_comps(side):
        sh, el, wr_ = j['sh_' + side], j['el_' + side], j['wr_' + side]
        sg = 1.0 if sh[0] > 0 else -1.0
        ua = limb(add(sh, (0.006 * sg * s, 0, -0.03 * s)), el, 0.050 * s + th, 0.043 * s + th)
        fa = limb(el, wr_, 0.042 * s + th * 0.9, 0.033 * s + th * 0.7)
        cap = lambda p: ellipsoid(p, add(sh, (0, 0, -0.016 * s)), (0.048 * s + th, 0.05 * s + th, 0.040 * s + th))
        return (0.02, [(ua, 0), (fa, 0), (cap, 0)])
    upper += [arm_comps('l'), arm_comps('r')]

    if kind == 'aodai':
        def collar_(p):
            return cyl(p, (j['neck0'][0], j['neck0'][1] + 0.002), 0.047 * s, j['neck0'][2] + 0.02, j['neck0'][2] + 0.075)
        upper.append((0.005, [(collar_, 0)]))
    elif collar:
        def collar_(p):
            n0 = j['neck0']
            x, y, z = p
            q = length2(x - n0[0], y - n0[1] - 0.01) - 0.075 * s
            d = length2(q, (z - n0[2] - 0.02) * 1.0) - 0.022 - puffy * 0.5
            return d
        upper.append((0.02, [(collar_, 0)]))

    zipper_col = lin((30, 30, 32))
    pattern = lin(aodai) if aodai is not None else None
    stripe_col = lin(stripes) if stripes is not None else None

    def top_tint(p, n, alb, idx):
        x, y, z = p
        out = alb
        if zipper and kind in ('jacket', 'coat'):
            zp = (np.abs(x - cx) < 0.0045) & (z < j['neck0'][2] + 0.02) & (z > hem) & (n[1] < -0.3)
            out = np.where(zp[:, None], out * 0.35 + zipper_col * 0.65, out)
        if kind == 'shirt':
            # nẹp khuy, cổ áo
            pl = (np.abs(x - cx) < 0.010) & (n[1] < -0.3) & (z > hem)
            out = np.where(pl[:, None], out * 0.92, out)
            btn = pl & (np.abs(((z - hem) % 0.085) - 0.042) < 0.004) & (np.abs(x - cx) < 0.004)
            out = np.where(btn[:, None], out * 0.6, out)
        if pattern is not None:
            # hoa văn áo dài: cành mai vàng vắt chéo vạt trước và ngực
            fr = (n[1] < -0.2)
            for (fx, fz, fr_) in FLOWERS:
                dx, dz = x - (cx + fx * s), z - fz * s
                r = length2(dx, dz)
                th_ = np.arctan2(dz, dx)
                petal = r < fr_ * s * (0.55 + 0.45 * np.abs(np.cos(2.5 * th_)))
                core = r < fr_ * s * 0.28
                out = np.where((fr & petal)[:, None], out * 0.25 + pattern * 0.75, out)
                out = np.where((fr & core)[:, None], out * 0.4 + lin((180, 60, 20)) * 0.6, out)
            # cành nâu mảnh nối các bông
            u = x - cx - (0.10 - 0.16 * (z / s - 0.35)) * s
            br = fr & (np.abs(u + 0.012 * np.sin(z * 40)) < 0.0035) & (z < 1.30 * s) & (z > 0.36 * s)
            out = np.where(br[:, None], out * 0.4 + lin((120, 70, 40)) * 0.6, out)
        if stripe_col is not None:
            band = (np.abs(z - (cz + 0.02 * s)) < 0.022 * s) | (np.abs(z - (wz_ - 0.02 * s)) < 0.022 * s)
            arm_band = np.abs(np.abs(x - cx) - 0.0) > 0.20 * s
            band = band & ~arm_band
            sl = arm_band & (np.abs(z - (j['el_r'][2] + 0.06 * s)) < 0.018 * s)
            out = np.where((band | sl)[:, None], stripe_col, out)
        return out

    bump = None
    if puffy > 0:
        def quilt(x, y, z):
            return np.abs(np.sin(z * math.pi / 0.085)) ** 0.6
        bump = field_bump(quilt, 0.006)
    else:
        bump = fabric_bump(55, 0.0018, seed)
    tmats = [topm]
    if kind == 'uniform':
        tmats = [topm]
    parts.append(multi('upper', upper, tmats, 0.012 * s, bump=bump, tint=top_tint))

    # cổ
    parts.append(Obj('neck', limb(j['neck0'], j['neck1'], 0.05 * s * fig.hs ** 0.3, 0.046 * s * fig.hs ** 0.3), sk))

    # ---- nửa dưới (quần)
    lth = 0.010 if kind != 'aodai' else 0.018

    def leg_comps(side):
        hp, kn, an = j['hip_' + side], j['kn_' + side], j['an_' + side]
        thigh = limb(hp, kn, 0.082 * s + lth, 0.056 * s + lth)
        shin = limb(kn, an, 0.054 * s + lth, 0.040 * s + lth + (0.02 if kind == 'aodai' else 0.0))
        return (0.03, [(thigh, 0), (shin, 0)])

    def pelvis(p):
        return ellipsoid(p, (px_, py_, pz_), (pr[0] + lth * 0.5, pr[1] + lth * 0.5, pr[2]))
    parts.append(multi('lower', [(0.03, [(pelvis, 0)]), leg_comps('l'), leg_comps('r')], [botm], 0.045 * s,
                       bump=fabric_bump(60, 0.0015, seed + 1)))

    # ---- tà áo dài: hai vạt trước / sau buông từ eo tới giữa ống chân
    if kind == 'aodai':
        zt, zb = hem + 0.03 * s, 0.30 * s

        def flap(sign):
            def sdf(p):
                x, y, z = p
                t = np.clip((zt - z) / (zt - zb), 0, 1)
                hw = pr[0] + 0.012 + 0.03 * s * t
                yc = py_ + sign * (pr[1] + 0.016 + 0.035 * t * t)
                curve = 0.045 * ((x - px_) / hw) ** 2 * sign
                slab = np.abs(y - yc + curve) - 0.006
                d = smax(slab, np.abs(x - px_) - hw, 0.01)
                return smax(d, np.maximum(z - zt - 0.06, zb - z), 0.01)
            return sdf
        parts.append(Obj('aodai_flaps', union(flap(-1), flap(1)), topm, tint=top_tint,
                         bump=field_bump(lambda x, y, z: np.sin(x * 55 + fbm(x * 8, z * 8, seed, 2) * 3), 0.003)))

    # ---- tay
    def hand(side):
        wr_ = j['wr_' + side]
        dv = unit(fig.hand_dir[side])
        tip = add(wr_, dv, 0.075 * s)
        palm = limb(add(wr_, dv, 0.012 * s), tip, 0.029 * s, 0.025 * s)
        return palm
    hm = fabric(gloves, rough=0.7) if gloves else sk
    parts.append(Obj('hands', union(hand('l'), hand('r')), hm))

    # ---- giày
    def shoe(side):
        an = j['an_' + side]
        fd = unit(fig.foot_dir[side])
        c = (an[0] + fd[0] * 0.05 * s, an[1] + fd[1] * 0.05 * s, 0.032 * s)

        def sdf(p):
            x, y, z = p
            # toạ độ dọc bàn chân
            ang = math.atan2(fd[0], -fd[1])
            u, v = rot(x - c[0], y - c[1], ang)
            e = ellipsoid((u, v, z), (0, 0, c[2]), (0.048 * s, 0.128 * s, 0.05 * s))
            heel = ellipsoid((u, v, z), (0, 0.06 * s, c[2] + 0.02 * s), (0.044 * s, 0.07 * s, 0.05 * s))
            return smax(smin(e, heel, 0.02), -z, 0.004)
        return sdf
    shm = Mat(shoes, rough=0.45, spec=0.6, coat=0.2)
    parts.append(Obj('shoes', union(shoe('l'), shoe('r')), [shm, Mat((210, 206, 196), rough=0.6)],
                     pick=lambda p, n: (p[2] < 0.012).astype(np.int32)))

    # ---- khăn quàng
    if scarf:
        n0 = j['neck0']

        def scarf_sdf(p):
            x, y, z = p
            q = length2(x - n0[0], (y - n0[1]) * 1.1) - 0.062 * s
            ring = length2(q, z - n0[2] - 0.035) - 0.03
            tail = round_cone(p, (n0[0] + 0.04, n0[1] - 0.08 - puffy, n0[2] + 0.01), (n0[0] + 0.06, n0[1] - 0.10 - puffy, n0[2] - 0.22), 0.03, 0.026)
            return smin(ring, tail, 0.03)
        parts.append(Obj('scarf', scarf_sdf, fabric(scarf, rough=0.9, sheen=0.5), bump=fabric_bump(80, 0.002, seed + 4)))

    # ---- tạp dề: vỏ mỏng ôm phía trước thân, từ ngực xuống gối
    if apron:
        def apron_sdf(p):
            x, y, z = fig.unlean(p)
            ez = (cz + 0.06 * s + 0.50 * s) / 2
            e = ellipsoid((x, y, z), (cx, py_ + 0.01, ez), (pr[0] + th + 0.03, pr[1] + th + 0.035, (cz + 0.06 * s - 0.50 * s) / 2 + 0.05))
            shell = np.abs(e) - 0.004
            d = smax(shell, y - (py_ - 0.03), 0.01)
            d = smax(d, np.abs(x - cx) - 0.15 * s, 0.01)
            return smax(d, np.maximum(z - (cz + 0.06 * s), 0.50 * s - z), 0.01)
        parts.append(Obj('apron', apron_sdf, fabric(apron, rough=0.85, sheen=0.3), bump=fabric_bump(50, 0.0015, seed + 7)))

    parts += head_parts(fig, sk, hair=hair, style=hair_style, face=face, seed=seed, beard=beard)
    if hat:
        parts += hat_parts(fig, hat, hat_color, seed)
    return parts


# ------------------------------------------------------------ Đồ cầm tay
GOLD = (226, 178, 64)


def gift_bag(top, color=(196, 26, 30), size=(0.13, 0.05, 0.16), seed=0):
    """Túi giấy quà Tết treo dưới bàn tay: [top] điểm nắm quai."""
    tx, ty, tz = top
    hx, hy, hz = size
    zc = tz - 0.07 - hz
    paper = Mat(color, rough=0.45, spec=0.6, coat=0.3)

    def bag(p):
        return rbox(p, (tx, ty, zc), (hx, hy, hz), 0.006)

    def handles(p):
        x, y, z = p
        q = (np.abs(x - tx) - 0.035, y - ty, z)
        return capsule(q, (0, 0, zc + hz - 0.004), (-0.03, 0, tz - 0.005), 0.0035)

    def tint(p, n, alb, idx):
        x, y, z = p
        u, v = x - tx, z - zc
        r = length2(u, v - 0.01)
        ring = (np.abs(r - 0.055) < 0.006) | (r < 0.035)
        border = (np.abs(np.abs(u) - hx + 0.012) < 0.004) | (np.abs(np.abs(v) - hz + 0.012) < 0.004)
        gold = (ring | border) & (np.abs(n[1]) > 0.5)
        return np.where(gold[:, None], lin(GOLD), alb)
    return [Obj('bag', bag, paper, tint=tint), Obj('bag_handles', handles, Mat((200, 160, 60), rough=0.5))]


def gift_box_parts(center, half, color=(30, 80, 170), ribbon=(206, 30, 36), bow=True):
    cx, cy, cz = center
    hx, hy, hz = half
    wrap = Mat(color, rough=0.35, spec=0.7, coat=0.4)

    def tint(p, n, alb, idx):
        x, y, z = p
        rb = (np.abs(x - cx) < 0.018) | (np.abs(z - cz) < 0.018) & (np.abs(n[2]) < 0.5)
        rb |= (np.abs(y - cy) < 0.018) & (n[2] > 0.5)
        dots = (np.sin(x * 160) * np.sin(z * 160 + y * 160) > 0.8) & ~rb
        out = np.where(dots[:, None], alb * 0.6 + lin(GOLD) * 0.4, alb)
        return np.where(rb[:, None], lin(ribbon), out)
    parts = [Obj('giftbox', lambda p: rbox(p, center, half, 0.008), wrap, tint=tint)]
    if bow:
        def bow_sdf(p):
            x, y, z = p
            q = (np.abs(x - cx), y - cy, z - cz - hz)
            loop = ellipsoid(q, (0.035, 0, 0.022), (0.04, 0.016, 0.024))
            knot = ellipsoid((x - cx, y - cy, z - cz - hz), (0, 0, 0.012), (0.018, 0.018, 0.016))
            return smin(loop, knot, 0.01)
        parts.append(Obj('bow', bow_sdf, Mat(ribbon, rough=0.3, spec=0.8, coat=0.5)))
    return parts


def suitcase(base, color=(150, 156, 166), h=0.56):
    """Va li kéo vỏ cứng: gân dọc, 4 bánh xe, cần kéo rút lên."""
    bx, by, bz = base
    shell = Mat(color, rough=0.25, spec=0.8, coat=0.6, metal=0.2)

    def body(p):
        return rbox(p, (bx, by, bz + 0.05 + h / 2), (0.17, 0.11, h / 2), 0.03)

    def ribs(x, y, z):
        return np.cos((x - bx) * math.pi / 0.045) * (np.abs(y - by) > 0.09)

    def handle(p):
        x, y, z = p
        q = (np.abs(x - bx) - 0.075, y - by - 0.085, z)
        rod = capsule(q, (0, 0, bz + 0.05 + h - 0.02), (0, 0, bz + h + 0.36), 0.0085)
        grip = capsule(p, (bx - 0.085, by + 0.085, bz + h + 0.37), (bx + 0.085, by + 0.085, bz + h + 0.37), 0.016)
        return np.minimum(rod, grip)

    def wheels(p):
        x, y, z = p
        q = (np.abs(x - bx) - 0.13, np.abs(y - by) - 0.07, z - bz - 0.025)
        return ellipsoid(q, (0, 0, 0), (0.014, 0.025, 0.025))
    return [Obj('suitcase', body, shell, bump=field_bump(ribs, 0.004)),
            Obj('handle', handle, [ALU, SATIN_BLACK], pick=lambda p, n: (p[2] > bz + h + 0.35).astype(np.int32)),
            Obj('wheels', wheels, RUBBER)]


def peach_branch(base, height=0.9, seed=4, wrap=(206, 36, 40)):
    """Cành đào cầm tay: gốc bó giấy đỏ, cành nở hoa phía trên."""
    bx, by, bz = base
    parts = t3.peach_parts((bx, by, bz + 0.24), (0.34, 0.18, 0.18), height, seed, branches=8, lean=(0.35, 0.8),
                           blossom=1.4, bloom=1.25)
    parts.append(Obj('wrap', lambda p: round_cone(p, (bx, by, bz - 0.08), (bx, by, bz + 0.26), 0.02, 0.034),
                     Mat(wrap, rough=0.4, spec=0.6, coat=0.4),
                     bump=field_bump(lambda x, y, z: np.sin(np.arctan2(y - by, x - bx) * 9 + z * 30), 0.004)))
    return parts


def kumquat_pot(base, scale=1.0, seed=6, pot_color=(150, 40, 30)):
    """Chậu quất nhỏ: chậu sành, tán tròn quả vàng, treo lì xì."""
    bx, by, bz = base
    k = scale
    parts = t3.kumquat_parts((bx, by, bz + 0.36 * k), (0.19 * k, 0.17 * k, 0.21 * k), seed=seed,
                             fruits=int(44 * k), lixi=3)
    pot = Mat(pot_color, rough=0.3, spec=0.7, coat=0.6)

    def pot_sdf(p):
        x, y, z = p
        body = round_cone(p, (bx, by, bz + 0.03 * k), (bx, by, bz + 0.14 * k), 0.075 * k, 0.10 * k)
        rim = cyl(p, (bx, by), 0.112 * k, bz + 0.13 * k, bz + 0.16 * k)
        return smin(body, rim, 0.01)

    def pot_tint(p, n, alb, idx):
        band = np.abs(p[2] - bz - 0.09 * k) < 0.012 * k
        return np.where(band[:, None], lin(GOLD), alb)
    parts.append(Obj('pot', pot_sdf, pot, tint=pot_tint))
    parts.append(Obj('soil', lambda p: cyl(p, (bx, by), 0.10 * k, bz + 0.13 * k, bz + 0.155 * k), Mat((60, 44, 34), rough=0.95)))
    parts.append(Obj('trunk', lambda p: round_cone(p, (bx, by, bz + 0.15 * k), (bx, by, bz + 0.25 * k), 0.018 * k, 0.012 * k),
                     Mat((80, 60, 40), rough=0.8)))
    return parts


def lixi_card(center, yaw=0.0, size=(0.045, 0.07)):
    """Phong bao lì xì nhỏ cầm tay (mặt quay về máy ảnh)."""
    cx, cy, cz = center
    hw, hh = size

    def sdf(p):
        x, y, z = p
        u, v = rot(x - cx, y - cy, -yaw)
        return rbox((u, v, z - cz), (0, 0, 0), (hw, 0.003, hh), 0.002)

    def tint(p, n, alb, idx):
        x, y, z = p
        u, _ = rot(x - cx, y - cy, -yaw)
        r = length2(u, z - cz + 0.01)
        g = (r < 0.018) | (np.abs(np.abs(u) - hw + 0.006) < 0.002)
        return np.where(g[:, None], lin(GOLD), alb)
    return [Obj('lixi', sdf, Mat((206, 22, 30), rough=0.35, spec=0.7, coat=0.5), tint=tint)]


def baton(a, b, r=0.014):
    """Gậy chỉ huy giao thông: trắng sọc đỏ."""
    ax_ = np.array(a, np.float64)
    bv = np.array(b, np.float64) - ax_
    L = np.linalg.norm(bv)

    def tint(p, n, alb, idx):
        t = ((p[0] - ax_[0]) * bv[0] + (p[1] - ax_[1]) * bv[1] + (p[2] - ax_[2]) * bv[2]) / (L * L)
        red = (np.floor(t * 9) % 2 == 1) & (t > 0.18)
        grip = t < 0.18
        out = np.where(red[:, None], lin((206, 30, 34)), alb)
        return np.where(grip[:, None], lin((30, 30, 32)), out)
    return [Obj('baton', lambda p: capsule(p, a, b, r), Mat((240, 240, 236), rough=0.3, spec=0.7, coat=0.5), tint=tint)]


def radar_gun(c):
    """Súng bắn tốc độ cầm tay: thân xám đen, loa tròn quay về phía xe."""
    cx, cy, cz = c

    def body(p):
        b = rbox(p, (cx, cy + 0.05, cz), (0.045, 0.10, 0.05), 0.02)
        horn = cyl_y(p, (cx, cy - 0.06, cz + 0.005), 0.052, 0.035)
        grip = capsule(p, (cx, cy + 0.08, cz - 0.04), (cx, cy + 0.10, cz - 0.15), 0.022)
        return smin(smin(b, horn, 0.012), grip, 0.01)

    def pick(p, n):
        x, y, z = p
        lens = (n[1] < -0.8) & (y < cy - 0.09) & (length2(x - cx, z - cz - 0.005) < 0.042)
        scr = (n[2] > 0.6) & (np.abs(x - cx) < 0.03) & (np.abs(y - cy - 0.09) < 0.035)
        return np.where(lens, 1, np.where(scr, 2, 0)).astype(np.int32)
    return [Obj('radar', body, [Mat((58, 60, 64), rough=0.35, spec=0.6, coat=0.3),
                                Mat((24, 26, 30), rough=0.08, spec=1.0, coat=1.0),
                                Mat((60, 160, 90), rough=0.1, coat=1.0, emit=0.6)], pick=pick)]


def stool(c, color=(206, 34, 36), h=0.27, top=0.27):
    """Ghế nhựa thấp kiểu quán vỉa hè: hình chóp cụt rỗng, mặt có lỗ xách,
    bốn mặt khoét vòm thành bốn chân loe."""
    cx, cy, cz = c
    plastic = Mat(color, rough=0.30, spec=0.7, coat=0.3)
    ht, hb = top / 2, top / 2 + 0.03

    def rrect2(u, v, hu, hv, r):
        qu, qv = np.abs(u) - hu + r, v - hv + r
        return length2(np.maximum(qu, 0), np.maximum(qv, 0)) + np.minimum(np.maximum(qu, qv), 0) - r

    def sdf(p):
        x, y, z = p
        t = np.clip((z - cz) / h, 0, 1)
        hs = hb + (ht - hb) * t
        ax, ay = np.abs(x - cx), np.abs(y - cy)
        side = (np.maximum(ax, ay) - hs) * 0.995
        rnd = length2(np.maximum(ax - hs + 0.03, 0), np.maximum(ay - hs + 0.03, 0)) - 0.03
        outer = np.where((ax > hs - 0.03) & (ay > hs - 0.03), rnd, side)
        shell = np.abs(outer + 0.004) - 0.0045
        d = smax(shell, np.maximum(z - cz - h, cz - z), 0.003)
        plate = smax(outer, np.abs(z - cz - h + 0.012) - 0.012, 0.004)
        d = np.minimum(d, plate)
        slot = rbox(p, (cx, cy, cz + h), (0.045, 0.013, 0.04), 0.012)
        d = smax(d, -slot, 0.003)
        # khoét vòm bốn mặt
        o1 = rrect2(x - cx, z - cz, 0.088, 0.16, 0.06)
        o2 = rrect2(y - cy, z - cz, 0.088, 0.16, 0.06)
        return smax(d, -np.minimum(o1, o2), 0.006)
    return [Obj('stool', sdf, plastic)]


# ------------------------------------------------------------ Dàn người
POLICE_UNIFORM = t3.POLICE_UNIFORM  # (196, 210, 62) vàng chanh như hình nhìn từ trên
POLICE_PANTS = (70, 74, 48)
REFLECT = (214, 218, 214)


def p_woman_box():
    """Chị áo phao đỏ, nón lá, ôm hộp quà xanh trước bụng."""
    f = Fig(1.56, 'f')
    s = f.s
    f.arm('l', (-0.20 * s, -0.07, 1.06 * s), (-0.13 * s, -0.24, 0.93 * s), (0.6, -0.2, 0.2))
    f.arm('r', (0.20 * s, -0.07, 1.06 * s), (0.13 * s, -0.24, 0.93 * s), (-0.6, -0.2, 0.2))
    parts = person(f, (196, 34, 40), (40, 40, 48), skin='mid', hair_style='bun', hat='conical', puffy=0.012,
                   collar=True, seed=11)
    parts += gift_box_parts((0.0, -0.25, 0.97 * s), (0.15, 0.10, 0.09))
    return parts


def p_man_suitcase():
    """Anh áo phao xanh dương kéo va li."""
    f = Fig(1.71, 'm')
    s = f.s
    f.arm('r', (0.25 * s, 0.04, 1.11 * s), (0.36, 0.06, 0.92), (0.2, 0.1, -1))
    parts = person(f, (34, 70, 150), (52, 58, 74), skin='mid', puffy=0.016, collar=True, seed=12)
    parts += suitcase((0.42, 0.0, 0.0), h=0.50)
    return parts


def p_teen_helmet():
    """Cậu thanh niên sơ mi trắng, quần âu, xách mũ bảo hiểm xanh."""
    f = Fig(1.65, 'm', girth=0.92)
    s = f.s
    f.arm('r', (0.215 * s, 0.03, 1.10 * s), (0.25 * s, -0.02, 0.86 * s))
    parts = person(f, (240, 240, 236), (36, 40, 58), kind='shirt', skin='light', seed=13, hair_style='crop')
    hand = add(f.j['wr_r'], unit(f.hand_dir['r']), 0.05)
    parts += v3.helmet_parts((40, 90, 180), (hand[0] + 0.01, hand[1], hand[2] - 0.16), yaw=0.4)
    parts.append(Obj('strap', lambda p: capsule(p, hand, (hand[0] + 0.02, hand[1], hand[2] - 0.10), 0.005),
                     Mat((20, 20, 20), rough=0.6)))
    return parts


def p_man_peach():
    """Chú áo khoác xanh rêu vác cành đào."""
    f = Fig(1.68, 'm')
    s = f.s
    f.arm('r', (0.24 * s, -0.02, 1.10 * s), (0.24 * s, -0.10, 1.12 * s), (-0.3, -0.1, 0.9))
    parts = person(f, (66, 88, 52), (48, 46, 44), kind='coat', skin='tan', collar=True, seed=14, puffy=0.006)
    hand = f.j['wr_r']
    parts += peach_branch((hand[0] + 0.01, hand[1] - 0.02, hand[2] + 0.02), height=0.85, seed=21)
    return parts


def p_woman_aodai():
    """Cô áo dài đỏ hoa mai, nón lá, xách túi quà vàng."""
    f = Fig(1.59, 'f')
    s = f.s
    f.arm('l', (-0.20 * s, 0.03, 1.09 * s), (-0.23 * s, -0.01, 0.86 * s))
    parts = person(f, (198, 26, 34), (244, 242, 236), kind='aodai', aodai=(240, 196, 70), skin='light',
                   hair_style='long', hat='conical', shoes=(120, 40, 40), seed=15)
    hand = add(f.j['wr_l'], unit(f.hand_dir['l']), 0.06)
    parts += gift_bag(hand, color=(232, 176, 40), size=(0.11, 0.045, 0.13))
    return parts


def p_old_woman_kumquat():
    """Bà áo bông tím, tóc búi, bê chậu quất."""
    f = Fig(1.50, 'f', girth=1.08)
    s = f.s
    f.arm('l', (-0.19 * s, -0.08, 1.04 * s), (-0.12 * s, -0.25, 0.90 * s), (0.5, -0.2, 0.3))
    f.arm('r', (0.19 * s, -0.08, 1.04 * s), (0.12 * s, -0.25, 0.90 * s), (-0.5, -0.2, 0.3))
    parts = person(f, (110, 60, 130), (40, 38, 40), skin='old', hair=(70, 66, 62), hair_style='bun', puffy=0.012,
                   collar=True, seed=16, scarf=(150, 110, 70))
    parts += kumquat_pot((0.0, -0.27, 0.80 * s), scale=0.95, seed=26)
    return parts


def p_old_man():
    """Ông cụ áo khoác dạ xám, mũ nồi, chống gậy."""
    f = Fig(1.63, 'm')
    s = f.s
    f.arm('r', (0.23 * s, -0.02, 1.08 * s), (0.27 * s, -0.10, 0.88 * s), (0.05, -0.1, -1))
    parts = person(f, (112, 112, 108), (58, 56, 52), kind='coat', skin='old', hair=HAIR_GREY, hair_style='crop',
                   hat='flatcap', hat_color=(60, 56, 50), seed=17, scarf=(150, 40, 40), zipper=False)
    hand = f.j['wr_r']
    tip = (hand[0] + 0.02, hand[1] - 0.06, 0.0)
    parts.append(Obj('cane', lambda p: smin(capsule(p, (hand[0], hand[1] - 0.02, hand[2] - 0.02), tip, 0.012),
                                            capsule(p, (hand[0] - 0.05, hand[1] - 0.02, hand[2] + 0.0),
                                                    (hand[0] + 0.01, hand[1] - 0.02, hand[2] - 0.0), 0.013), 0.01),
                     Mat((96, 62, 36), rough=0.4, spec=0.6, coat=0.4)))
    return parts


def p_kid_lixi():
    """Bé gái áo phao hồng, mũ len, giơ bao lì xì."""
    f = Fig(1.16, 'f', head=0.86)
    s = f.s
    f.arm('l', (-0.24 * s, -0.04, 1.30 * s), (-0.28 * s, -0.10, 1.62 * s), (0.0, -0.1, 1))
    parts = person(f, (236, 120, 160), (60, 70, 120), skin='kid', hair_style='long', hat='beanie',
                   hat_color=(236, 236, 230), puffy=0.016, collar=True, seed=18, shoes=(220, 60, 80))
    hand = add(f.j['wr_l'], unit(f.hand_dir['l']), 0.06)
    parts += lixi_card((hand[0], hand[1] - 0.03, hand[2] + 0.04), yaw=0.2)
    return parts


def sit_fig(height, sex, girth=1.0, stool_h=0.27, knees=0.15, head=None):
    """Khung người ngồi ghế nhựa thấp: hông ngang mặt ghế, gối cao và ra trước."""
    f = Fig(height, sex, girth=girth, head=head)
    s = f.s
    dz = (stool_h + 0.10) - f.pelvis[2]
    f.shift_upper(dz, dy=0.0)
    f.lean_by(0.10)
    hz = f.j['hip_l'][2]
    for side, sg in (('l', -1), ('r', 1)):
        f.leg(side, (sg * knees, -0.37 * s, hz + 0.16 * s), (sg * (knees - 0.02), -0.36 * s, 0.085 * s))
    # tay đặt lên gối
    for side, sg in (('l', -1), ('r', 1)):
        f.arm(side, (sg * 0.21 * s, -0.10, 0.62), (sg * (knees + 0.0), -0.33 * s, hz + 0.24 * s), (0, -0.6, -0.5))
    return f


def p_sit_tea():
    f = sit_fig(1.68, 'm', knees=0.17)
    s = f.s
    f.arm('l', (-0.22 * s, -0.10, f.j['sh_l'][2] - 0.26), (-0.10, -0.28, f.j['sh_l'][2] - 0.16), (0.3, -0.2, 0.9))
    parts = person(f, (110, 76, 52), (50, 52, 58), skin='tan', puffy=0.008, collar=True, seed=21)
    hand = f.j['wr_l']
    parts += tea_glass((hand[0] + 0.03, hand[1] - 0.02, hand[2] + 0.02))
    parts += stool((0, 0.04, 0), color=(40, 90, 180))
    return parts


def p_sit_woman():
    f = sit_fig(1.56, 'f', knees=0.12)
    parts = person(f, (56, 120, 90), (40, 40, 46), skin='mid', hair_style='bun', puffy=0.0, kind='jacket', seed=22,
                   zipper=False, collar=True)
    parts += stool((0, 0.04, 0), color=(206, 34, 36))
    return parts


def p_sit_phone():
    f = sit_fig(1.70, 'm', knees=0.16)
    s = f.s
    for side, sg in (('l', -1), ('r', 1)):
        f.arm(side, (sg * 0.20 * s, -0.12, f.j['sh_l'][2] - 0.27), (sg * 0.04, -0.30, f.j['sh_l'][2] - 0.22), (0, -0.4, 0.9))
    parts = person(f, (34, 34, 38), (60, 76, 110), skin='light', seed=23, hair_style='crop', puffy=0.004, collar=True)
    hz = f.j['wr_l'][2]
    parts.append(Obj('phone', lambda p: rbox(p, (0, -0.33, hz + 0.05), (0.036, 0.006, 0.07), 0.006),
                     [Mat((20, 20, 24), rough=0.1, coat=1.0), Mat((120, 170, 220), rough=0.1, coat=1.0, emit=0.5)],
                     pick=lambda p, n: (n[1] > 0.6).astype(np.int32)))
    parts += stool((0, 0.04, 0), color=(206, 34, 36))
    return parts


def tea_glass(c, h=0.095, r=0.03):
    """Cốc trà đá: thuỷ tinh dày, trà màu hổ phách, đá viên."""
    cx, cy, cz = c

    def sdf(p):
        return round_cone(p, (cx, cy, cz), (cx, cy, cz + h), r * 0.82, r)

    def tint(p, n, alb, idx):
        x, y, z = p
        top = z > cz + h * 0.88
        rim = top & (n[2] < 0.6)
        ice = top & (n[2] > 0.6) & (np.sin(x * 400) * np.sin(y * 400) > 0.1)
        out = np.where(rim[:, None], lin((230, 220, 190)), alb)
        return np.where(ice[:, None], lin((236, 230, 210)), out)
    return [Obj('tea', sdf, Mat((176, 104, 30), rough=0.06, spec=1.4, coat=1.0, wrap=0.6), tint=tint)]


def police_fig(height=1.72):
    f = Fig(height, 'm', girth=1.03)
    return f


def police_parts(f, seed=31):
    parts = person(f, POLICE_UNIFORM, POLICE_PANTS, kind='uniform', skin='tan', hat='kepi', stripes=REFLECT,
                   seed=seed, shoes=(24, 24, 26), zipper=False, hair_style='crop')
    # thắt lưng đen
    zb = 0.94 * f.s + 0.005
    pz = f.pelvis[2]
    parts.append(Obj('belt', lambda p: smax(ellipsoid(f.unlean(p), (0, f.pelvis[1], pz + 0.03), (f.pelvis_r[0] + 0.02, f.pelvis_r[1] + 0.02, 0.10)),
                                            np.abs(f.unlean(p)[2] - zb) - 0.02, 0.004),
                     [Mat((26, 26, 28), rough=0.35, spec=0.7), Mat((200, 200, 196), rough=0.2, metal=1.0)],
                     pick=lambda p, n: ((np.abs(p[0]) < 0.03) & (n[1] < -0.5)).astype(np.int32)))
    return parts


def p_police_stand():
    f = police_fig()
    s = f.s
    for side, sg in (('l', -1), ('r', 1)):
        f.arm(side, (sg * 0.215 * s, 0.03, 1.10 * s), (sg * 0.17 * s, -0.04, 0.90 * s), (-sg * 0.25, -0.2, -1))
    return police_parts(f)


def p_police_wave():
    f = police_fig()
    s = f.s
    # tay phải (bên trái ảnh) giơ cao vẫy gậy, tay kia buông
    f.arm('l', (-0.33 * s, -0.04, 1.52 * s), (-0.40 * s, -0.10, 1.80 * s), (-0.25, -0.1, 1))
    parts = police_parts(f)
    w = f.j['wr_l']
    a = add(w, unit((-0.25, -0.1, 1)), 0.03)
    b = add(w, unit((-0.55, -0.25, 1)), 0.62)
    parts += baton(a, b)
    return parts


def p_police_radar():
    f = police_fig()
    s = f.s
    f.arm('l', (-0.20 * s, -0.17, 1.16 * s), (-0.07, -0.36, 1.24 * s), (0.5, -0.6, 0.2))
    f.arm('r', (0.21 * s, -0.15, 1.15 * s), (0.06, -0.36, 1.21 * s), (-0.6, -0.5, 0.1))
    parts = police_parts(f)
    parts += radar_gun((0.0, -0.44, 1.31 * s))
    return parts


def p_attendant():
    """Nhân viên cây xăng: mũ lưỡi trai đỏ, áo xanh dương, quần sẫm."""
    f = Fig(1.69, 'm')
    s = f.s
    for side, sg in (('l', -1), ('r', 1)):
        f.arm(side, (sg * 0.215 * s, 0.03, 1.10 * s), (sg * 0.24 * s, -0.01, 0.86 * s))
    parts = person(f, (36, 92, 176), (40, 44, 56), kind='shirt', skin='tan', hat='cap', hat_color=(200, 32, 34),
                   seed=41, hair_style='crop')
    # dải đỏ trên vai áo đồng phục
    for o in parts:
        if o.name == 'upper':
            old = o.tint

            def tint(p, n, alb, idx, old=old):
                out = old(p, n, alb, idx)
                band = (np.abs(p[2] - f.j['sh_r'][2] + 0.06) < 0.02) & (np.abs(p[0]) > 0.04)
                return np.where(band[:, None], lin((200, 34, 36)), out)
            o.tint = tint
    return parts


def p_seller_stand():
    """Chị bán hàng: áo hồng, tạp dề, nón lá."""
    f = Fig(1.57, 'f')
    s = f.s
    f.arm('l', (-0.20 * s, -0.05, 1.08 * s), (-0.08, -0.18, 0.98 * s), (0.6, -0.3, 0.1))
    f.arm('r', (0.20 * s, -0.05, 1.08 * s), (0.08, -0.18, 0.98 * s), (-0.6, -0.3, 0.1))
    return person(f, (226, 120, 150), (50, 50, 60), kind='shirt', skin='mid', hair_style='bun', hat='conical',
                  apron=(236, 236, 230), seed=42)


def p_seller_sit(stool_color=(40, 90, 180)):
    """Bà bán hàng ngồi ghế thấp: áo bà ba hoa, khăn rằn, tay đặt lên gối."""
    f = sit_fig(1.52, 'f', knees=0.13, girth=1.05)
    parts = person(f, (120, 66, 96), (30, 30, 34), kind='shirt', skin='old', hair=(84, 80, 76), hair_style='bun',
                   hat='conical', seed=43)
    parts += stool((0, 0.04, 0), color=stool_color)
    return parts


PEOPLE = {
    'person_1': p_woman_box,
    'person_2': p_man_suitcase,
    'person_3': p_teen_helmet,
    'person_4': p_man_peach,
    'person_5': p_woman_aodai,
    'person_6': p_old_woman_kumquat,
    'person_7': p_old_man,
    'person_8': p_kid_lixi,
    'person_sit_1': p_sit_tea,
    'person_sit_2': p_sit_woman,
    'person_sit_3': p_sit_phone,
    'police_officer_stand': p_police_stand,
    'police_officer_wave': p_police_wave,
    'police_officer_radar': p_police_radar,
    'worker_attendant': p_attendant,
    'seller_1': p_seller_stand,
    'seller_2': p_seller_sit,
}
PERSON_PPM = 170.0


# ------------------------------------------------------- Võng, thợ vá xe
def hammock_parts(xa, xb, z_end, sag=0.55, width=0.42, y=0.0, color=(40, 110, 170), seed=1, posts=True,
                  post_h=None):
    """Võng lưới căng giữa hai cột theo phương x (nhìn ngang thấy đường võng
    cong). Hai đầu túm lại, dây buộc lên cột."""
    gx0, gx1 = xa + 0.35, xb - 0.35  # đoạn lưới (đầu túm)

    def zc(x):
        u = np.clip((x - gx0) / (gx1 - gx0), 0, 1) * 2 - 1
        return z_end - 0.06 - sag * (1 - u * u)

    def sdf(p):
        x, yy, z = p
        u = np.clip((x - gx0) / (gx1 - gx0), 0, 1) * 2 - 1
        w = width * np.sqrt(np.clip(1 - u ** 4, 0, 1)) + 0.02
        dy = (yy - y) / np.maximum(w, 1e-3)
        f = zc(x) + 0.16 * dy * dy * (w / width)
        slope = 2 * sag * u * 2 / (gx1 - gx0)
        d = (z - f) / np.sqrt(1 + slope * slope + (0.32 * dy / np.maximum(w, 1e-3)) ** 2) 
        sheet = np.abs(d) - 0.006
        sheet = smax(sheet, np.abs(yy - y) - w, 0.01)
        return smax(sheet, np.maximum(gx0 - x, x - gx1), 0.01)

    def tint(p, n, alb, idx):
        x, yy, z = p
        a = np.sin((x + yy) * 160) * np.sin((x - yy) * 160)
        return np.where((a > 0.55)[:, None], alb * 0.55, alb * (0.9 + 0.1 * a[:, None]))
    net = Mat(color, rough=0.75, sheen=0.5, wrap=0.4, spec=0.3)
    rope = Mat((200, 190, 160), rough=0.8)

    def ropes(p):
        z0 = zc(np.array([gx0]))[0]
        a = capsule(p, (xa + 0.04, y, z_end), (gx0, y, z0 + 0.0), 0.008)
        b = capsule(p, (xb - 0.04, y, z_end), (gx1, y, z0 + 0.0), 0.008)
        # dây túm hai đầu lưới
        ga = ellipsoid(p, (gx0 + 0.02, y, z0), (0.05, 0.03, 0.025))
        gb = ellipsoid(p, (gx1 - 0.02, y, z0), (0.05, 0.03, 0.025))
        return np.minimum(np.minimum(a, b), np.minimum(ga, gb))
    parts = [Obj('hammock', sdf, net, tint=tint), Obj('hammock_rope', ropes, rope)]
    if posts:
        ph = post_h or z_end + 0.25
        wood = Mat((112, 80, 52), rough=0.75, spec=0.3)
        bark = lambda x, y_, z: fbm(x * 30, z * 6, seed, 3)
        parts.append(Obj('posts', union(lambda p: cyl(p, (xa, y), 0.05, 0.0, ph), lambda p: cyl(p, (xb, y), 0.05, 0.0, ph)),
                         wood, bump=field_bump(bark, 0.01)))
    return parts, zc


def lying_person(at, tilt=0.22, **kw):
    """Người nằm ngửa trên võng, đầu bên trái, nhìn ngang."""
    f = Fig(kw.pop('height', 1.68), kw.pop('sex', 'm'))
    s = f.s
    for side, sg in (('l', -1), ('r', 1)):
        f.leg(side, (sg * 0.10 * s, -0.22, 0.56 * s), (sg * 0.11 * s, -0.12, 0.18 * s), (0, -0.8, 0.2))
        f.arm(side, (sg * 0.22 * s, -0.05, 1.12 * s), (sg * 0.06, -0.17, 1.02 * s), (-sg * 0.8, -0.3, 0.1))
    parts = person(f, **kw)
    R = rot_mat('y', tilt) @ rot_mat('z', math.pi / 2) @ rot_mat('x', -math.pi / 2)
    # khung chậu → vị trí [at]
    pc = np.array(f.pelvis)
    w = R @ pc
    return placed(parts, at[0] - w[0], at[1] - w[1], at[2] - w[2], R=R)


def p_hammock():
    parts, zc = hammock_parts(-1.25, 1.25, 1.25, sag=0.55, color=(36, 120, 180))
    zlow = float(zc(np.array([0.05]))[0])
    parts += lying_person((0.12, 0.0, zlow + 0.14), tilt=0.40, top=(236, 236, 230), bottom=(40, 60, 100), kind='shirt',
                          skin='tan', seed=51)
    return parts


def tyre_y(p, c, r_out, thick, half_w, rr):
    """Lốp xe trục theo y (mặt lốp quay về máy ảnh)."""
    return tyre((p[1], p[0], p[2]), (c[1], c[0], c[2]), r_out, thick, half_w, rr)


def moto_wheel(c, r=0.29, axis='y'):
    """Bánh xe máy: lốp gai + vành nhôm đúc + đùm."""
    cx, cy, cz = c
    if axis == 'y':
        tsdf = lambda p: tyre_y(p, c, r, 0.075, 0.042, 0.026)
        rim = lambda p: smax(np.abs(length2(p[0] - cx, p[2] - cz) - (r - 0.085)) - 0.012, np.abs(p[1] - cy) - 0.03, 0.006)
        hub = lambda p: cyl_y(p, c, 0.05, 0.05)

        def spokes(p):
            x, y, z = p
            ang = np.arctan2(z - cz, x - cx)
            rr_ = length2(x - cx, z - cz)
            k = np.abs(np.sin(ang * 2.5)) * rr_ - 0.012
            return smax(smax(k, np.abs(y - cy) - 0.018, 0.004), rr_ - (r - 0.08), 0.004)
    else:
        tsdf = lambda p: tyre(p, c, r, 0.075, 0.042, 0.026)
        rim = lambda p: smax(np.abs(length2(p[1] - cy, p[2] - cz) - (r - 0.085)) - 0.012, np.abs(p[0] - cx) - 0.03, 0.006)
        hub = lambda p: smax(length2(p[1] - cy, p[2] - cz) - 0.05, np.abs(p[0] - cx) - 0.05, 0.004)

        def spokes(p):
            x, y, z = p
            ang = np.arctan2(z - cz, y - cy)
            rr_ = length2(y - cy, z - cz)
            k = np.abs(np.sin(ang * 2.5)) * rr_ - 0.012
            return smax(smax(k, np.abs(x - cx) - 0.018, 0.004), rr_ - (r - 0.08), 0.004)

    def tread(x, y, z):
        if axis == 'y':
            ang = np.arctan2(z - cz, x - cx)
        else:
            ang = np.arctan2(z - cz, y - cy)
        return np.sin(ang * 60)
    return [Obj('tyre', tsdf, RUBBER, bump=field_bump(tread, 0.0012)),
            Obj('rim', union(rim, hub, spokes), Mat((180, 182, 186), rough=0.25, metal=1.0))]


def p_mechanic():
    """Thợ vá xe ngồi xổm cạnh bánh xe, nhìn ngang, quay mặt sang trái."""
    f = Fig(1.66, 'm')
    s = f.s
    f.shift_upper(0.42 - f.pelvis[2], dy=0.12)
    f.lean_by(0.55)
    for side, sg in (('l', -1), ('r', 1)):
        f.leg(side, (sg * 0.16 * s, -0.20, 0.44), (sg * 0.12 * s, -0.02, 0.085))
    f.arm('l', (-0.23 * s, -0.28, 0.66), (-0.10, -0.50, 0.46), (0.2, -0.5, -0.6))
    f.arm('r', (0.25 * s, -0.24, 0.70), (0.13, -0.50, 0.55), (-0.2, -0.6, -0.4))
    parts = person(f, (84, 92, 104), (48, 48, 52), kind='shirt', skin='tan', seed=61, hair_style='crop',
                   shoes=(60, 58, 54))
    parts += moto_wheel((0.0, -0.80, 0.29), axis='x')
    # cái nạy lốp trong tay phải
    w = f.j['wr_r']
    parts.append(Obj('lever', lambda p: capsule(p, (w[0] - 0.02, w[1] - 0.05, w[2] - 0.02), (0.02, -0.80 + 0.06, 0.50), 0.007),
                     Mat((150, 152, 156), rough=0.3, metal=1.0)))
    return placed(parts, yaw=-math.pi / 2)


PEOPLE['person_hammock_1'] = p_hammock
PEOPLE['worker_mechanic'] = p_mechanic


# ================================================================ Con vật
# Nhìn ngang, đầu quay sang TRÁI (-x); y = 0 là mặt phẳng giữa con vật, chân
# phía máy ảnh ở -y. Gốc x = 0 nằm giữa hai bàn chân.
def ell_rot(p, c, r, ang):
    """Elip xoay trong mặt phẳng x-z (dương: đuôi vểnh lên khi đầu ở -x)."""
    x, y, z = p
    u, w = rot(x - c[0], z - c[2], -ang)
    return ellipsoid((u, y - c[1], w), (0, 0, 0), r)


def bezier_tube(p0, p1, p2, r0, r1, n=6):
    """Ống cong bậc hai (lông đuôi gà, đuôi chó cong)."""
    pts = []
    for i in range(n + 1):
        t = i / n
        a = [(1 - t) ** 2 * p0[k] + 2 * (1 - t) * t * p1[k] + t * t * p2[k] for k in range(3)]
        pts.append(tuple(a))
    segs = [(pts[i], pts[i + 1], r0 + (r1 - r0) * i / n, r0 + (r1 - r0) * (i + 1) / n) for i in range(n)]
    return t3.segments(segs)


def feather_bump(scale, amp, seed):
    def f(x, y, z):
        return np.sin(x * scale + fbm(x * 20, z * 20, seed, 2) * 3) * np.sin(z * scale * 0.8 + x * scale * 0.3)
    return field_bump(f, amp)


def duck_parts(frame=0, white=False):
    if white:
        body_c, head_c, wing_c = (238, 238, 230), (242, 242, 236), (228, 228, 220)
        bill_c, leg_c = (236, 150, 40), (236, 140, 40)
    else:
        body_c, head_c, wing_c = (140, 110, 80), (92, 74, 56), (118, 90, 64)
        bill_c, leg_c = (196, 150, 70), (226, 128, 44)
    mats = [Mat(body_c, rough=0.75, sheen=0.5, wrap=0.35, spec=0.35),
            Mat(head_c, rough=0.6, sheen=0.6, wrap=0.3, spec=0.45),
            Mat(wing_c, rough=0.7, sheen=0.5, wrap=0.3, spec=0.4)]
    bob = (0.006 if frame else 0.0) - 0.022

    def body(p):
        return ell_rot(p, (0.03, 0, 0.205 + bob), (0.165, 0.092, 0.088), 0.16)

    def breast(p):
        return ellipsoid(p, (-0.075, 0, 0.195 + bob), (0.092, 0.084, 0.086))

    def tail(p):
        return ell_rot(p, (0.18, 0, 0.255 + bob), (0.065, 0.035, 0.018), 0.5)

    def neck(p):
        return round_cone(p, (-0.10, 0, 0.245 + bob), (-0.13, 0, 0.36 + bob), 0.046, 0.032)

    def head(p):
        return ellipsoid(p, (-0.142, 0, 0.385 + bob), (0.052, 0.038, 0.041))

    def wings(p):
        q = (p[0], np.abs(p[1]), p[2])
        return ell_rot(q, (0.045, 0.062, 0.228 + bob), (0.13, 0.034, 0.06), 0.18)

    comps = [(body, 0), (breast, 0), (tail, 2), (neck, 1 if not white else 0), (head, 1), (wings, 2)]
    ex, ez = -0.163, 0.397 + bob

    def tint(p, n, alb, idx):
        x, y, z = p
        out = alb
        if not white:
            sp = fbm(x * 70, z * 70 + y * 30, 3, 3)
            out = out * (0.8 + 0.4 * sp[:, None])
            # vạch xanh tím trên cánh (gương cánh), mày sáng
            spec_ = (idx == 2) & (np.abs(z - 0.215 - bob - (x - 0.10) * 0.2) < 0.007) & (x > 0.07) & (x < 0.14)
            out = np.where(spec_[:, None], out * 0.4 + lin((60, 80, 150)) * 0.6, out)
            brow = (idx == 1) & (np.abs(z - ez - 0.011) < 0.0028) & (x < -0.13) & (x > -0.18)
            out = np.where(brow[:, None], out * 0.5 + lin((170, 150, 120)) * 0.5, out)
        eye = (((x - ex) / 0.0085) ** 2 + ((z - ez) / 0.0085) ** 2 < 1) & (np.abs(n[1]) > 0.35)
        return np.where(eye[:, None], lin((14, 12, 12)), out)

    parts = [Blend('duck', comps, mats, 0.035, bump=feather_bump(130, 0.0012, 4), tint=tint)]
    parts.append(Obj('bill', lambda p: ell_rot(p, (-0.205, 0, 0.373 + bob), (0.046, 0.021, 0.0115), -0.12),
                     Mat(bill_c, rough=0.35, spec=0.6, coat=0.3)))
    legm = Mat(leg_c, rough=0.45, spec=0.5)
    # bước đi: hai khung hình đổi chân trước / sau
    steps = [(-0.035, 0.040, 0.0, 0.018), (0.040, -0.035, 0.018, 0.0)][frame]
    legs = []
    for side, dx, lift in ((-1, steps[0], steps[2]), (1, steps[1], steps[3])):
        yy = side * 0.036
        top = (0.01, yy, 0.14 + bob)
        ank = (dx, yy, 0.03 + lift)
        legs.append(lambda p, top=top, ank=ank: round_cone(p, top, ank, 0.016, 0.009))
        legs.append(lambda p, ank=ank, yy=yy, lift=lift: ell_rot(p, (ank[0] - 0.03, yy, 0.008 + lift), (0.046, 0.03, 0.007), -lift * 4))
    parts.append(Obj('legs', union(*legs), legm))
    return parts


def chicken_parts(rooster=True):
    k = 1.0 if rooster else 0.86
    if rooster:
        body_c, breast_c, hackle_c, wing_c = (130, 48, 26), (40, 30, 26), (226, 136, 40), (150, 60, 28)
    else:
        body_c, breast_c, hackle_c, wing_c = (172, 112, 60), (186, 128, 72), (196, 140, 76), (150, 96, 52)
    mats = [Mat(body_c, rough=0.7, sheen=0.6, wrap=0.3, spec=0.4),
            Mat(breast_c, rough=0.55, sheen=0.6, wrap=0.3, spec=0.5),
            Mat(hackle_c, rough=0.5, sheen=0.8, wrap=0.3, spec=0.6),
            Mat(wing_c, rough=0.6, sheen=0.6, wrap=0.3, spec=0.45)]

    def body(p):
        return ell_rot(p, (0.02 * k, 0, 0.31 * k), (0.16 * k, 0.098 * k, 0.115 * k), 0.24)

    def breast(p):
        return ellipsoid(p, (-0.09 * k, 0, 0.30 * k), (0.092 * k, 0.09 * k, 0.105 * k))

    def neck(p):
        return round_cone(p, (-0.075 * k, 0, 0.37 * k), (-0.118 * k, 0, 0.50 * k), 0.066 * k, 0.04 * k)

    def head(p):
        return ellipsoid(p, (-0.125 * k, 0, 0.532 * k), (0.042 * k, 0.032 * k, 0.036 * k))

    def wings(p):
        q = (p[0], np.abs(p[1]), p[2])
        return ell_rot(q, (0.045 * k, 0.07 * k, 0.33 * k), (0.115 * k, 0.03 * k, 0.066 * k), 0.2)

    def thighs(p):
        q = (p[0], np.abs(p[1]), p[2])
        return ellipsoid(q, (0.01 * k, 0.045 * k, 0.235 * k), (0.052 * k, 0.04 * k, 0.065 * k))

    comps = [(body, 0), (breast, 1), (neck, 2), (head, 2), (wings, 3), (thighs, 1 if rooster else 0)]
    if not rooster:
        comps.append((lambda p: ell_rot(p, (0.15 * k, 0, 0.42 * k), (0.055 * k, 0.04 * k, 0.07 * k), -0.5), 0))
    ex, ez = -0.14 * k, 0.54 * k

    comp_cols = [mats[mi].albedo for _, mi in comps]

    def tint(p, n, alb, idx):
        x, y, z = p
        sp = fbm(x * 60, z * 60 + y * 20, 7, 3)
        # ranh giới màu lông mềm, lởm chởm như lông vũ (không cắt gọn theo khối)
        ds = np.stack([fn(p) for fn, _ in comps], 1)
        jit = (fbm(x * 90 + 3, z * 90, 11, 2)[:, None] - 0.5) * 0.02
        w = np.exp(-(ds - ds.min(1, keepdims=True) + jit * np.arange(len(comps))[None, :] * 0.5) / 0.010)
        w /= w.sum(1, keepdims=True)
        alb = sum(w[:, i:i + 1] * comp_cols[i][None, :] for i in range(len(comps)))
        out = alb * (0.82 + 0.36 * sp[:, None])
        if not rooster:
            # viền lông sẫm như vảy cá
            sc = np.sin(x * 140 / k) * np.sin(z * 140 / k + x * 50) > 0.6
            out = np.where((sc & (idx != 2))[:, None], out * 0.7, out)
        else:
            # lông cánh sơ cấp xanh đen ở mép sau cánh, chuyển màu mềm
            wi = [i for i, (_, mi) in enumerate(comps) if mi == 3][0]
            pw = w[:, wi] * smoothstep(0.06 * k, 0.12 * k, x) * smoothstep(0.34 * k, 0.29 * k, z)
            out = out * (1 - pw[:, None]) + lin((30, 52, 40))[None, :] * pw[:, None]
        # mặt đỏ quanh mắt
        face = (idx == 2) & (x < -0.135 * k) & (z < 0.55 * k) & (z > 0.505 * k)
        out = np.where(face[:, None], lin((196, 50, 40)), out)
        eye = (((x - ex) / (0.008 * k)) ** 2 + ((z - ez) / (0.008 * k)) ** 2 < 1) & (np.abs(n[1]) > 0.35)
        out = np.where(eye[:, None], lin((150, 90, 20)), out)
        pupil = (((x - ex) / (0.0045 * k)) ** 2 + ((z - ez) / (0.0045 * k)) ** 2 < 1) & (np.abs(n[1]) > 0.35)
        return np.where(pupil[:, None], lin((10, 8, 8)), out)

    parts = [Blend('chicken', comps, mats, 0.03 * k, bump=feather_bump(120, 0.0014, 6), tint=tint)]
    red = Mat((206, 30, 34), rough=0.45, spec=0.5, wrap=0.4)

    def comb(p):
        x, y, z = p
        h = (0.032 if rooster else 0.014) * k
        e = ellipsoid(p, (-0.118 * k, 0, 0.568 * k + h * 0.4), ((0.052 if rooster else 0.03) * k, 0.006 * k, h))
        teeth = 0.25 * h * (np.abs(np.sin((x + 0.12 * k) * 95 / k)) - 0.5)
        return smax(e + teeth * (z > 0.568 * k), 0.565 * k - z, 0.004)

    def wattle(p):
        x, y, z = p
        q = (x, np.abs(y), z)
        return ellipsoid(q, (-0.155 * k, 0.006 * k, 0.495 * k), (0.014 * k, 0.007 * k, (0.026 if rooster else 0.014) * k))
    parts.append(Obj('comb', union(comb, wattle), red))
    parts.append(Obj('beak', lambda p: round_cone(p, (-0.155 * k, 0, 0.53 * k), (-0.195 * k, 0, 0.516 * k), 0.012 * k, 0.003 * k),
                     Mat((222, 178, 70), rough=0.35, spec=0.6)))
    if rooster:
        tails = []
        for i, (dy, span, hgt, r) in enumerate(((0.0, 0.20, 0.30, 0.016), (0.025, 0.17, 0.26, 0.014),
                                                (-0.025, 0.15, 0.23, 0.014), (0.012, 0.12, 0.19, 0.012))):
            p0 = (0.11, dy, 0.38)
            p1 = (0.13 + span * 0.5, dy, 0.38 + hgt)
            p2 = (0.13 + span, dy, 0.40 + hgt * 0.15)
            tails.append(bezier_tube(p0, p1, p2, r * 1.3, r * 0.3, n=7))
        parts.append(Obj('tail', union(*tails), Mat((22, 48, 36), rough=0.22, spec=0.9, metal=0.35, sheen=0.6)))
    legm = Mat((214, 170, 70), rough=0.45, spec=0.5)
    legs = []
    for side, dx in ((-1, -0.02), (1, 0.03)):
        yy = side * 0.04 * k
        top = (0.0, yy, 0.21 * k)
        ank = (dx * k, yy, 0.025)
        legs.append(lambda p, top=top, ank=ank: capsule(p, top, ank, 0.011 * k))
        for tx, ty in ((-0.075, 0.0), (-0.06, 0.028), (-0.06, -0.028), (0.04, 0.0)):
            legs.append(lambda p, ank=ank, tx=tx, ty=ty, yy=yy: capsule(p, (ank[0], yy, 0.012), (ank[0] + tx * k, yy + ty * k, 0.007), 0.0065 * k))
    parts.append(Obj('legs', union(*legs), legm))
    return parts


def dog_parts(frame=0):
    """Chó vàng ta (chó cỏ): lông vàng rơm, bụng / mõm nhạt, tai dựng, đuôi
    cong vắt lên lưng; hai khung hình phi (duỗi / thu chân)."""
    fur = Mat((184, 124, 58), rough=0.8, sheen=0.6, wrap=0.35, spec=0.3)
    arch = 0.0 if frame == 0 else 0.02
    lift = 0.04 if frame == 0 else 0.02

    def L(c):
        return (c[0], c[1], c[2] + lift)

    def chest(p):
        return ellipsoid(p, L((-0.16, 0, 0.42)), (0.14, 0.108, 0.15))

    def torso(p):
        return ell_rot(p, L((0.03, 0, 0.445 + arch)), (0.22, 0.10, 0.115), -0.03)

    def hips(p):
        return ellipsoid(p, L((0.20, 0, 0.45)), (0.12, 0.10, 0.12))

    def neck(p):
        return round_cone(p, L((-0.20, 0, 0.47)), L((-0.30, 0, 0.585)), 0.078, 0.06)

    def skull(p):
        return ellipsoid(p, L((-0.335, 0, 0.62)), (0.076, 0.064, 0.068))

    def muzzle(p):
        return round_cone(p, L((-0.37, 0, 0.60)), L((-0.465, 0, 0.583)), 0.043, 0.026)

    def ears(p):
        q = (p[0], np.abs(p[1]), p[2])
        e = round_cone(q, L((-0.315, 0.035, 0.665)), L((-0.31, 0.045, 0.745)), 0.03, 0.005)
        return e

    # chân: (vai/hông, khuỷu, cổ chân, bàn) theo khung hình
    if frame == 0:
        fl = [((-0.15, -0.055, 0.40), (-0.25, -0.055, 0.27), (-0.37, -0.055, 0.12), (-0.41, -0.055, 0.075)),
              ((-0.15, 0.055, 0.40), (-0.22, 0.055, 0.26), (-0.32, 0.055, 0.14), (-0.36, 0.055, 0.10))]
        hl = [((0.22, -0.055, 0.43), (0.30, -0.055, 0.29), (0.42, -0.055, 0.18), (0.50, -0.055, 0.12)),
              ((0.22, 0.055, 0.43), (0.28, 0.055, 0.28), (0.38, 0.055, 0.17), (0.45, 0.055, 0.10))]
    else:
        fl = [((-0.15, -0.055, 0.40), (-0.12, -0.055, 0.25), (-0.04, -0.055, 0.10), (-0.01, -0.055, 0.05)),
              ((-0.15, 0.055, 0.40), (-0.16, 0.055, 0.25), (-0.10, 0.055, 0.10), (-0.07, 0.055, 0.06))]
        hl = [((0.20, -0.055, 0.43), (0.12, -0.055, 0.31), (0.08, -0.055, 0.16), (0.02, -0.055, 0.07)),
              ((0.20, 0.055, 0.43), (0.15, 0.055, 0.30), (0.12, 0.055, 0.15), (0.07, 0.055, 0.08))]

    def leg_sdf(chain, front):
        a, b, c, d = [L(v) for v in chain]
        r = (0.056, 0.034, 0.024) if front else (0.078, 0.04, 0.024)
        s1 = round_cone_f(a, b, r[0], r[1])
        s2 = round_cone_f(b, c, r[1] * 0.8, r[2])
        s3 = lambda p: ellipsoid(p, (d[0] - 0.012, d[1], d[2] - 0.0), (0.03, 0.022, 0.018))
        s4 = round_cone_f(c, (d[0], d[1], d[2] + 0.005), r[2], r[2] * 0.9)
        return lambda p: smin(smin(smin(s1(p), s2(p), 0.02), s4(p), 0.01), s3(p), 0.01)

    comps = [(chest, 0), (torso, 0), (hips, 0), (neck, 0), (skull, 0), (muzzle, 0), (ears, 0)]
    for ch in fl:
        comps.append((leg_sdf(ch, True), 0))
    for ch in hl:
        comps.append((leg_sdf(ch, False), 0))
    tail = bezier_tube(L((0.29, 0, 0.50)), L((0.40, 0, 0.66)), L((0.29, 0, 0.68)), 0.034, 0.016, n=8)
    comps.append((tail, 0))
    ex, ez = -0.388, 0.638 + lift

    def tint(p, n, alb, idx):
        x, y, z = p
        out = alb * (0.86 + 0.28 * fbm(x * 25, z * 25, 9, 3)[:, None])
        light = lin((226, 196, 142))
        under = smoothstep(-0.2, -0.7, n[2])
        mz = (x < -0.40) & (z < 0.60 + lift) & (z > 0.52 + lift)
        chest_l = (smoothstep(-0.16, -0.24, x) * smoothstep(-0.34, -0.26, x) * smoothstep(0.30, 0.38, z - lift)
                   * smoothstep(0.56, 0.48, z - lift) * smoothstep(-0.1, -0.5, n[0]))
        k = np.clip(under * 0.8 + mz * 0.9 + chest_l * 0.5, 0, 1)
        out = out * (1 - k[:, None]) + light * k[:, None]
        back = smoothstep(0.6, 0.95, n[2]) * (x > -0.25)
        out = out * (1 - 0.3 * back[:, None])
        eye = (((x - ex) / 0.011) ** 2 + ((z - ez) / 0.009) ** 2 < 1) & (np.abs(n[1]) > 0.3)
        out = np.where(eye[:, None], lin((40, 24, 14)), out)
        nose = (x < -0.468) & (z > 0.585 + lift)
        ear_in = (idx == 0) & (z > 0.67 + lift) & (n[1] < -0.5) & (np.abs(x + 0.31) < 0.015)
        out = np.where(ear_in[:, None], out * 0.8 + lin((200, 120, 100)) * 0.2, out)
        return np.where(nose[:, None], lin((24, 20, 20)), out)

    def fur_f(x, y, z):
        return fbm(x * 60, z * 160 + y * 40, 2, 3)
    parts = [Blend('dog', comps, [fur], 0.035, bump=field_bump(fur_f, 0.0009), tint=tint)]
    parts.append(Obj('nose', lambda p: ellipsoid(p, L((-0.475, 0, 0.592)), (0.017, 0.017, 0.014)),
                     Mat((22, 20, 20), rough=0.25, spec=0.8, coat=0.5)))
    return placed(parts, scale=0.9)


def round_cone_f(a, b, r1, r2):
    return lambda p: round_cone(p, a, b, r1, r2)


ANIMALS = {
    'duck_1': lambda: duck_parts(0),
    'duck_2': lambda: duck_parts(1),
    'duck_white_1': lambda: duck_parts(0, white=True),
    'chicken_1': lambda: chicken_parts(True),
    'chicken_2': lambda: chicken_parts(False),
    'dog_1': lambda: dog_parts(0),
    'dog_2': lambda: dog_parts(1),
}
ANIMAL_PPM = 420.0


# ================================================================ Chữ, biển
def font(name, size):
    files = {'paytone': 'PaytoneOne-Regular.ttf', 'xbold': 'Manrope-ExtraBold.ttf', 'bold': 'Manrope-Bold.ttf',
             'semi': 'Manrope-SemiBold.ttf', 'medium': 'Manrope-Medium.ttf'}
    return ImageFont.truetype(os.path.join(FONT_DIR, files[name]), size)


def fit_font(draw, text, name, box_w, box_h, start=400):
    """Cỡ chữ lớn nhất vừa khung (kể cả dấu tiếng Việt trên đầu chữ hoa)."""
    size = start
    while size > 6:
        f = font(name, size)
        l, t, r, b = draw.textbbox((0, 0), text, font=f)
        if r - l <= box_w and b - t <= box_h:
            return f, (l, t, r, b)
        size = int(size * 0.94)
    f = font(name, 6)
    return f, draw.textbbox((0, 0), text, font=f)


def draw_center(draw, text, name, box, fill, stroke=0, stroke_fill=None, start=400):
    x0, y0, x1, y1 = box
    f, (l, t, r, b) = fit_font(draw, text, name, x1 - x0 - 2 * stroke, y1 - y0 - 2 * stroke, start)
    x = (x0 + x1) / 2 - (l + r) / 2
    y = (y0 + y1) / 2 - (t + b) / 2
    draw.text((x, y), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
    return f


def hand_text(img, text, box, color, name='paytone', seed=1, jitter=1.0, start=300):
    """Chữ viết tay bằng sơn / bút lông: từng chữ lệch, nghiêng, to nhỏ khác
    nhau, nét hơi nhoè loang."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    W, H = img.size
    d0 = ImageDraw.Draw(img)
    f, (l, t, r, b) = fit_font(d0, text, name, (x1 - x0) * 0.92, (y1 - y0) * 0.82, start)
    layer = Image.new('L', (W, H), 0)
    x = (x0 + x1) / 2 - (r - l) / 2 - l
    yb = (y0 + y1) / 2 - (t + b) / 2
    for ch in text:
        adv = d0.textlength(ch, font=f)
        if ch != ' ':
            sz = int(f.size * rnd.uniform(0.9, 1.1))
            g = font(name, sz)
            bb = d0.textbbox((0, 0), ch, font=g)
            gw, gh = bb[2] - bb[0] + 20, bb[3] - bb[1] + 20
            gl = Image.new('L', (gw, gh), 0)
            ImageDraw.Draw(gl).text((10 - bb[0], 10 - bb[1]), ch, font=g, fill=255)
            gl = gl.rotate(rnd.uniform(-7, 7) * jitter, resample=Image.BICUBIC, expand=True)
            oy = yb + rnd.uniform(-0.06, 0.06) * f.size * jitter + bb[1] - (gl.size[1] - gh) / 2 - 10
            layer.paste(255, (int(x + bb[0] - 10 + rnd.uniform(-2, 2)), int(oy)), gl)
        x += adv * rnd.uniform(0.96, 1.04)
    # mép nét sơn lởm chởm, loang
    a = np.asarray(layer.filter(ImageFilter.GaussianBlur(1.2)), np.float64) / 255
    yy, xx = np.mgrid[0:H, 0:W]
    nz = fbm(xx / 7.0, yy / 7.0, seed, 3)
    a = np.clip((a - 0.35 - 0.25 * (nz - 0.5)) * 4, 0, 1) * (0.85 + 0.15 * nz)
    paint_ = Image.new('RGBA', (W, H), tuple(color) + (255,))
    paint_.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
    img.alpha_composite(paint_)
    return img


def cardboard_tex(w, h, seed=3):
    """Bìa các-tông: nâu vàng, lốm đốm, vết gấp."""
    yy, xx = np.mgrid[0:h, 0:w]
    n = fbm(xx / 40.0, yy / 40.0, seed, 4)
    base = np.array([186, 150, 104], np.float64)
    col = base[None, None, :] * (0.85 + 0.25 * n[..., None])
    crease = np.abs(yy - h * 0.62 - 6 * np.sin(xx / 50.0)) < 2
    col[crease] *= 0.8
    out = np.dstack([np.clip(col, 0, 255), np.full((h, w), 255)]).astype(np.uint8)
    return Image.fromarray(out)


def panel(name, center, half_w, half_h, thick, tex, mat=None, back=None, face=-1):
    """Tấm biển phẳng dựng đứng, mặt trước (phía -y) dán ảnh [tex]."""
    cx, cy, cz = center
    sm = tex_sampler(tex)
    mat = mat or Mat((240, 240, 236), rough=0.45, spec=0.5, coat=0.2)
    back = back or Mat((150, 152, 156), rough=0.4, metal=0.8)
    tint = decal(sm, cx - half_w, cx + half_w, cz - half_h, cz + half_h, face=face)

    def pick(p, n):
        return (n[1] * face < 0.5).astype(np.int32)
    return Obj(name, lambda p: rbox(p, center, (half_w, thick, half_h), min(thick, 0.004)), [mat, back], pick=pick,
               tint=lambda p, n, alb, idx: np.where((idx == 0)[:, None], tint(p, n, alb, idx), alb))


# ================================================================ Đồ quán
WOOD = Mat((120, 84, 52), rough=0.7, spec=0.3)
STEEL = Mat((196, 200, 204), rough=0.28, metal=1.0)
TARP_BLUE = (40, 96, 176)


def wood_bump(seed=1, k=1.0):
    return field_bump(lambda x, y, z: fbm(x * 8 * k, (y + z) * 90 * k, seed, 3), 0.004)


def umbrella(c, R=1.3, h=2.45, drop=0.42, cols=((40, 90, 180), (240, 240, 236)), panels=8, seed=1):
    """Ô dù lớn kiểu quán: tán vải 8 múi xen màu, diềm vải quanh mép, gọng,
    cán sắt. Mặt dưới tán hơi sáng do nắng xuyên qua vải."""
    cx, cy, cz = c
    ze = h - drop

    def canopy(p):
        x, y, z = p
        r = length2(x - cx, y - cy)
        ang = np.arctan2(y - cy, x - cx)
        # múi vải hơi võng giữa hai gọng
        sag = 0.03 * np.abs(np.sin(ang * panels / 2)) * (r / R)
        f = h - drop * (r / R) ** 1.25 - sag
        slope = drop * 1.25 * (r / R) ** 0.25 / R
        d = (z - f) / np.sqrt(1 + slope * slope)
        shell = np.abs(d) - 0.006
        return smax(shell, r - R, 0.01)

    def valance(p):
        x, y, z = p
        r = length2(x - cx, y - cy)
        ang = np.arctan2(y - cy, x - cx)
        bot = ze - 0.14 + 0.03 * np.abs(np.sin(ang * panels))
        d = np.abs(r - R + 0.004) - 0.004
        return smax(d, np.maximum(z - ze - 0.005, bot - z), 0.004)

    def pick(p, n):
        x, y, z = p
        ang = np.arctan2(y - cy, x - cx)
        k = (np.floor((ang + math.pi) / (2 * math.pi / panels)) % 2).astype(np.int32)
        under = n[2] < 0
        return k + 2 * under

    m0 = Mat(cols[0], rough=0.75, sheen=0.4, wrap=0.3, spec=0.35)
    m1 = Mat(cols[1], rough=0.75, sheen=0.4, wrap=0.3, spec=0.35)
    u0 = Mat(cols[0], rough=0.9, wrap=0.5, spec=0.1, emit=0.30)
    u1 = Mat(cols[1], rough=0.9, wrap=0.5, spec=0.1, emit=0.30)
    mats = [m0, m1, u0, u1]
    parts = [Obj('canopy', lambda p: np.minimum(canopy(p), valance(p)), mats, pick=pick,
                 bump=fabric_bump(30, 0.002, seed))]

    def ribs(p):
        x, y, z = p
        r = length2(x - cx, y - cy)
        ang = np.arctan2(y - cy, x - cx)
        seg = 2 * math.pi / panels
        a = np.mod(ang + math.pi + seg / 2, seg) - seg / 2  # gọng nằm ở ranh giới hai múi
        lat = np.abs(np.sin(a)) * r
        f = h - drop * (r / R) ** 1.25 - 0.018
        rib = length2(lat, z - f) - 0.007
        rib = smax(rib, r - R + 0.02, 0.005)
        # thanh chống từ cán lên giữa gọng
        t = np.clip(r / (R * 0.55), 0, 1)
        zs = (h - 0.85) + t * (h - drop * 0.55 ** 1.25 - 0.04 - (h - 0.85))
        strut = length2(lat, z - zs) - 0.006
        strut = smax(strut, r - R * 0.55, 0.005)
        return np.minimum(rib, strut)
    parts.append(Obj('ribs', ribs, Mat((200, 200, 196), rough=0.35, metal=0.8)))
    parts.append(Obj('pole', lambda p: np.minimum(cyl(p, (cx, cy), 0.022, cz, h + 0.04),
                                                  cyl(p, (cx, cy), 0.045, h - 0.88, h - 0.80)),
                     Mat((210, 210, 206), rough=0.3, metal=0.9)))
    parts.append(Obj('pole_base', lambda p: smin(cyl(p, (cx, cy), 0.20, cz, cz + 0.06), cyl(p, (cx, cy), 0.05, cz, cz + 0.25), 0.04),
                     Mat((50, 52, 56), rough=0.5, spec=0.4)))
    return parts


def low_table(c, half=(0.42, 0.26), h=0.42, top_mat=None, legs_mat=None, cloth=None):
    """Bàn thấp quán vỉa hè: mặt gỗ dán / nhựa, bốn chân."""
    cx, cy, cz = c
    tm = top_mat or Mat((168, 118, 70), rough=0.55, spec=0.4, coat=0.2)
    lm = legs_mat or Mat((90, 62, 40), rough=0.6, spec=0.3)

    def top(p):
        return rbox(p, (cx, cy, cz + h - 0.015), (half[0], half[1], 0.015), 0.006)

    def legs(p):
        x, y, z = p
        q = (np.abs(x - cx) - half[0] + 0.05, np.abs(y - cy) - half[1] + 0.05, z)
        leg = rbox(q, (0, 0, cz + (h - 0.03) / 2), (0.018, 0.018, (h - 0.03) / 2), 0.004)
        apron = rbox(p, (cx, cy, cz + h - 0.06), (half[0] - 0.04, half[1] - 0.04, 0.03), 0.004)
        apron = smax(apron, -rbox(p, (cx, cy, cz + h - 0.06), (half[0] - 0.06, half[1] - 0.06, 0.05), 0.004), 0.002)
        return np.minimum(leg, apron)
    return [Obj('table_top', top, tm, bump=wood_bump(3, 0.5)), Obj('table_legs', legs, lm)]


def tea_jug(c, color=(214, 70, 34)):
    """Bình trà đá nhựa to: thân trụ, nắp trắng, vòi rót."""
    cx, cy, cz = c
    body = Mat(color, rough=0.3, spec=0.6, coat=0.4)

    def sdf(p):
        x, y, z = p
        b = round_cone(p, (cx, cy, cz + 0.02), (cx, cy, cz + 0.20), 0.105, 0.098)
        b = smax(b, cz - z, 0.01)
        spout = round_cone(p, (cx - 0.08, cy - 0.02, cz + 0.07), (cx - 0.16, cy - 0.02, cz + 0.12), 0.025, 0.014)
        handle = smax(np.abs(length2(x - cx - 0.12, z - cz - 0.15) - 0.06) - 0.012, np.abs(y - cy) - 0.014, 0.005)
        handle = smax(handle, cx + 0.09 - x, 0.01)
        return smin(smin(b, spout, 0.02), handle, 0.01)
    lid = Mat((240, 240, 236), rough=0.35, spec=0.6)
    return [Obj('jug', sdf, body, tint=lambda p, n, alb, idx: np.where((np.abs(p[2] - cz - 0.05) < 0.012)[:, None], lin((240, 240, 236)), alb)),
            Obj('jug_lid', lambda p: smin(cyl(p, (cx, cy), 0.088, cz + 0.20, cz + 0.235), cyl(p, (cx, cy), 0.03, cz + 0.23, cz + 0.26), 0.01), lid)]


def glass_jar(c, r=0.07, h=0.18, fill=(200, 120, 60), seed=1):
    """Hũ kẹo lạc / hướng dương: nắp đỏ, ruột màu (vẽ đục, mặt kính giả bằng
    lớp phủ bóng)."""
    cx, cy, cz = c
    content = Mat(fill, rough=0.2, spec=1.0, coat=1.0, wrap=0.4)
    return [Obj('jar', lambda p: round_cone(p, (cx, cy, cz + r * 0.6), (cx, cy, cz + h - r * 0.5), r * 0.9, r * 0.82),
                content, tint=lambda p, n, alb, idx: alb * (0.75 + 0.5 * fbm(p[0] * 120, p[2] * 120 + p[1] * 80, seed, 2))[:, None]),
            Obj('jar_lid', lambda p: cyl(p, (cx, cy), r * 0.78, cz + h - 0.02, cz + h + 0.012), Mat((200, 30, 30), rough=0.3, spec=0.7, coat=0.5))]


def cooler(c, half=(0.30, 0.20, 0.20), color=(206, 40, 36)):
    """Thùng đá nhựa: thân màu, nắp trắng, quai."""
    cx, cy, cz = c
    hx, hy, hz = half
    return [Obj('cooler', lambda p: rbox(p, (cx, cy, cz + hz * 0.85), (hx, hy, hz * 0.85), 0.03), Mat(color, rough=0.3, spec=0.6, coat=0.4)),
            Obj('cooler_lid', lambda p: rbox(p, (cx, cy, cz + hz * 1.82), (hx + 0.01, hy + 0.01, hz * 0.16), 0.025),
                Mat((240, 240, 236), rough=0.35, spec=0.6, coat=0.3)),
            Obj('cooler_grip', lambda p: rbox(p, (cx, cy - hy - 0.012, cz + hz * 1.45), (hx * 0.4, 0.012, 0.018), 0.008),
                Mat((240, 240, 236), rough=0.35, spec=0.6))]


def glass_case(c, half=(0.26, 0.15, 0.16), items=True, seed=2):
    """Tủ kính nhỏ bày thuốc lá, kẹo: khung nhôm, kính (lớp trong suốt), hàng
    hộp màu bên trong. Trả về (vật đục, vật kính)."""
    cx, cy, cz = c
    hx, hy, hz = half
    frame = Mat((200, 202, 206), rough=0.3, metal=0.9)

    def frame_sdf(p):
        x, y, z = p
        ob = rbox(p, (cx, cy, cz + hz), (hx, hy, hz), 0.004)
        inner = rbox(p, (cx, cy, cz + hz), (hx - 0.014, hy - 0.014, hz - 0.014), 0.002)
        # chỉ giữ các cạnh: bỏ phần giữa của mỗi mặt
        fx = rbox(p, (cx, cy, cz + hz), (hx - 0.014, hy + 0.1, hz - 0.014), 0.002)
        fy = rbox(p, (cx, cy, cz + hz), (hx + 0.1, hy - 0.014, hz - 0.014), 0.002)
        fz = rbox(p, (cx, cy, cz + hz), (hx - 0.014, hy - 0.014, hz + 0.1), 0.002)
        d = smax(ob, -inner, 0.002)
        d = smax(d, -np.minimum(np.minimum(fx, fy), fz), 0.002)
        base = rbox(p, (cx, cy, cz + 0.008), (hx, hy, 0.008), 0.003)
        return np.minimum(d, base)
    opaque = [Obj('case_frame', frame_sdf, frame)]
    if items:
        rnd = random.Random(seed)
        cols = [(230, 40, 40), (240, 240, 236), (40, 90, 180), (240, 200, 40), (30, 140, 70), (200, 120, 40)]
        boxes = []
        for row in range(2):
            x = cx - hx + 0.03
            while x < cx + hx - 0.06:
                w = rnd.uniform(0.025, 0.04)
                hgt = rnd.uniform(0.06, 0.09)
                boxes.append(((x + w, cy - 0.02 + row * 0.06, cz + 0.016 + row * hz * 0.95 + hgt / 2), (w, 0.025, hgt / 2), rnd.choice(cols)))
                x += 2 * w + 0.008
        ms = [Mat(b[2], rough=0.4, spec=0.6, coat=0.4) for b in boxes]

        def bsdf(p):
            d = None
            for (bc, bh, _) in boxes:
                v = rbox(p, bc, bh, 0.003)
                d = v if d is None else np.minimum(d, v)
            return d

        def bpick(p, n):
            best = np.full(p[0].shape, 1e9)
            idx = np.zeros(p[0].shape, np.int32)
            for i, (bc, bh, _) in enumerate(boxes):
                v = rbox(p, bc, bh, 0.003)
                m = v < best
                best = np.where(m, v, best)
                idx = np.where(m, i, idx)
            return idx
        opaque.append(Obj('case_items', bsdf, ms, pick=bpick))
        opaque.append(Obj('case_shelf', lambda p: rbox(p, (cx, cy, cz + hz), (hx - 0.016, hy - 0.016, 0.004), 0.002), Mat((220, 224, 228), rough=0.2, spec=0.8)))
    glass = [Obj('case_glass', lambda p: np.abs(rbox(p, (cx, cy, cz + hz), (hx - 0.006, hy - 0.006, hz - 0.006), 0.003)) - 0.002, Mat((200, 210, 215)))]
    return opaque, glass


# ================================================================ Quán ven đường
# Gốc x = 0 giữa quán, y = 0 mép quán sát đường, quán lùi vào phía +y.
STALL_PPM = 135.0


def at(parts, x, y, yaw=0.0, z=0.0):
    """Đặt nhóm vật (người, đồ) tại (x, y), quay mặt: yaw = 0 nhìn ra đường,
    π/2 nhìn sang phải ảnh, -π/2 sang trái, π quay lưng."""
    return placed(parts, x, y, z, yaw=yaw)


def sign_board_tex(text, w, h, bg, fg, sub=None, name='paytone', border=None, sub_col=None):
    img = Image.new('RGBA', (w, h), tuple(bg) + (255,))
    d = ImageDraw.Draw(img)
    pad = int(h * 0.08)
    if border:
        d.rectangle((pad // 2, pad // 2, w - pad // 2 - 1, h - pad // 2 - 1), outline=tuple(border), width=max(2, h // 30))
    if sub:
        draw_center(d, text, name, (pad * 2, pad, w - pad * 2, int(h * 0.68)), tuple(fg))
        draw_center(d, sub, 'xbold', (pad * 3, int(h * 0.68), w - pad * 3, h - pad), tuple(sub_col or fg))
    else:
        draw_center(d, text, name, (pad * 2, pad, w - pad * 2, h - pad), tuple(fg))
    return img


def cardboard_sign(text, w=600, h=300, color=(30, 30, 34), seed=5):
    img = cardboard_tex(w, h, seed)
    hand_text(img, text, (int(w * 0.04), int(h * 0.05), int(w * 0.96), int(h * 0.95)), color, seed=seed)
    return img


def stall_tra_da():
    parts = []
    parts += umbrella((0.15, 1.05, 0.0), R=1.35, h=2.40, cols=((40, 92, 184), (240, 240, 236)))
    parts += low_table((0.0, 0.95, 0.0), half=(0.40, 0.24), h=0.40)
    parts += tea_jug((-0.20, 1.02, 0.40))
    for i, (gx, gy) in enumerate(((-0.02, 0.84), (0.12, 0.88), (0.24, 0.80), (0.05, 1.05), (0.30, 1.02))):
        parts += tea_glass((gx, gy, 0.40), h=0.085, r=0.027)
    parts += glass_jar((0.30, 1.12, 0.40), r=0.06, h=0.15, fill=(214, 160, 90), seed=3)
    parts += glass_jar((0.18, 1.14, 0.40), r=0.05, h=0.13, fill=(60, 50, 40), seed=4)
    # bà chủ quán ngồi sau bàn, khách hai bên, một khách quay lưng ra đường
    parts += at(p_seller_sit((40, 90, 180)), 0.0, 1.50)
    parts += at(p_sit_tea(), -0.78, 0.92, yaw=math.pi / 2)
    parts += at(p_sit_phone(), 0.80, 0.98, yaw=-math.pi / 2 + 0.25)
    parts += at(p_sit_woman(), 0.12, 0.32, yaw=math.pi + 0.15)
    parts += at(stool((0, 0, 0), color=(40, 90, 180)), 0.62, 0.40)
    parts += at(stool((0, 0, 0), color=(206, 34, 36)), -0.55, 0.30)
    parts += cooler((-1.10, 1.55, 0.0), half=(0.28, 0.20, 0.19), color=(206, 40, 36))
    op, gl = glass_case((1.15, 1.45, 0.42), half=(0.24, 0.14, 0.15))
    parts += op
    parts += low_table((1.15, 1.45, 0.0), half=(0.30, 0.20), h=0.42, top_mat=Mat((40, 92, 170), rough=0.35, spec=0.6, coat=0.4),
                       legs_mat=Mat((40, 92, 170), rough=0.35, spec=0.6, coat=0.4))
    tex = cardboard_sign('TRÀ ĐÁ', 520, 260, seed=7)
    parts.append(panel('sign', (-1.10, 1.33, 0.58), 0.24, 0.12, 0.004, tex, mat=Mat((190, 150, 104), rough=0.85, spec=0.2),
                       back=Mat((170, 136, 96), rough=0.9)))
    return parts, gl


def multi_obj(name, items, mats_of=None):
    """Gộp nhiều vật nhỏ cùng loại [(sdf, chỉ số vật liệu)] thành một Obj."""
    mats = mats_of

    def sdf(p):
        d = None
        for f, _ in items:
            v = f(p)
            d = v if d is None else np.minimum(d, v)
        return d

    def pick(p, n):
        best = np.full(p[0].shape, 1e9)
        idx = np.zeros(p[0].shape, np.int32)
        for f, mi in items:
            v = f(p)
            m = v < best
            best = np.where(m, v, best)
            idx = np.where(m, mi, idx)
        return idx
    return Obj(name, sdf, mats, pick=pick)


def cane_bundle(base, n=14, height=2.1, seed=5, lean=0.10):
    """Bó mía cây dựng đứng tựa vào xe: thân tím / xanh, đốt sẫm."""
    rnd = random.Random(seed)
    bx, by, bz = base
    cols = [(92, 46, 78), (110, 62, 92), (78, 40, 66), (120, 140, 66), (100, 52, 84)]
    mats = [Mat(c, rough=0.35, spec=0.7, coat=0.4) for c in cols]
    items = []
    for i in range(n):
        ox, oy = rnd.uniform(-0.09, 0.09), rnd.uniform(-0.07, 0.07)
        lx, ly = lean + rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04)
        h = height * rnd.uniform(0.85, 1.05)
        a = (bx + ox, by + oy, bz)
        b = (bx + ox + lx * h, by + oy + ly * h, bz + h)
        r = rnd.uniform(0.016, 0.022)
        items.append(((lambda p, a=a, b=b, r=r: capsule(p, a, b, r)), rnd.randrange(len(cols))))
    o = multi_obj('canes', items, mats)

    def tint(p, n, alb, idx):
        node = np.abs(((p[2] + 0.03 * idx) % 0.16) - 0.08) > 0.072
        out = np.where(node[:, None], alb * 0.55 + lin((200, 190, 140)) * 0.15, alb)
        return out * (0.9 + 0.2 * fbm(p[2] * 40, p[0] * 40, 5, 2))[:, None]
    o.tint = tint
    rope = Obj('cane_rope', lambda p: smax(np.abs(length2(p[0] - bx - lean * 0.9, p[1] - by) - 0.12) - 0.008,
                                           np.abs(p[2] - bz - 0.9) - 0.012, 0.004), Mat((210, 180, 100), rough=0.8))
    return [o, rope]


def bottles(c, cols_rows, spacing=(0.09, 0.0), r=0.034, h=0.23, liquid=((226, 176, 40), (230, 120, 130)), seed=2):
    """Hàng chai nhựa đựng xăng: thân trong chứa xăng vàng / hồng, nắp màu."""
    rnd = random.Random(seed)
    cx, cy, cz = c
    ncol, nrow = cols_rows
    mats = [Mat(liquid[0], rough=0.05, spec=1.4, coat=1.0, wrap=0.6, emit=0.12),
            Mat(liquid[1], rough=0.05, spec=1.4, coat=1.0, wrap=0.6, emit=0.12)]
    caps = [Mat((230, 200, 40), rough=0.3, spec=0.6), Mat((220, 60, 120), rough=0.3, spec=0.6),
            Mat((40, 90, 180), rough=0.3, spec=0.6)]
    items, cap_items = [], []
    for i in range(ncol):
        for j in range(nrow):
            x = cx + (i - (ncol - 1) / 2) * spacing[0] + rnd.uniform(-0.005, 0.005)
            y = cy + j * 0.09
            hh = h * rnd.uniform(0.95, 1.05)
            k = 0 if rnd.random() < 0.7 else 1

            def body(p, x=x, y=y, hh=hh):
                b = round_cone(p, (x, y, cz + r), (x, y, cz + hh * 0.72), r, r * 0.98)
                neck = round_cone(p, (x, y, cz + hh * 0.72), (x, y, cz + hh * 0.92), r * 0.95, r * 0.36)
                return smin(b, neck, 0.02)
            items.append((body, k))
            cap_items.append(((lambda p, x=x, y=y, hh=hh: cyl(p, (x, y), r * 0.40, cz + hh * 0.9, cz + hh + 0.012)), rnd.randrange(3)))
    o = multi_obj('bottles', items, mats)

    def tint(p, n, alb, idx):
        # nhãn mờ quanh thân, mức xăng
        lab = (np.abs(p[2] - cz - h * 0.40) < h * 0.09)
        out = np.where(lab[:, None], alb * 0.5 + lin((240, 240, 236)) * 0.5, alb)
        air = p[2] > cz + h * 0.80
        return np.where(air[:, None], lin((200, 205, 205)), out)
    o.tint = tint
    return [o, multi_obj('caps', cap_items, caps)]


def shelf(c, w=0.9, d=0.32, h=1.0, tiers=3, mat=None):
    """Kệ gỗ nhiều tầng (bán xăng lẻ)."""
    cx, cy, cz = c
    m = mat or Mat((128, 88, 52), rough=0.65, spec=0.35)

    def sdf(p):
        x, y, z = p
        q = (np.abs(x - cx) - w / 2 + 0.02, np.abs(y - cy) - d / 2 + 0.02, z)
        posts = rbox(q, (0, 0, cz + h / 2), (0.02, 0.02, h / 2), 0.004)
        out = posts
        for i in range(tiers):
            zt = cz + 0.12 + i * (h - 0.16) / max(tiers - 1, 1)
            out = np.minimum(out, rbox(p, (cx, cy, zt), (w / 2, d / 2, 0.012), 0.004))
            out = np.minimum(out, rbox(p, (cx, cy - d / 2 + 0.01, zt + 0.04), (w / 2, 0.008, 0.012), 0.003))
        return out
    return [Obj('shelf', sdf, m, bump=wood_bump(7, 0.6))]


def p_seller_man():
    """Anh bán bánh mì: áo phông trắng, tạp dề xanh, mũ lưỡi trai."""
    f = Fig(1.69, 'm')
    s = f.s
    f.arm('l', (-0.21 * s, -0.06, 1.08 * s), (-0.12, -0.24, 1.0 * s), (0.6, -0.4, 0.0))
    f.arm('r', (0.21 * s, -0.06, 1.08 * s), (0.10, -0.26, 1.0 * s), (-0.6, -0.4, 0.0))
    return person(f, (238, 238, 232), (60, 62, 70), kind='shirt', skin='tan', hat='cap', hat_color=(30, 60, 120),
                  apron=(40, 110, 90), seed=44, hair_style='crop', zipper=False)


def cane_cart(c):
    """Xe nước mía: tủ inox trên bánh xe, máy ép (hộp inox + bánh đà), tủ kính
    nhỏ bày mía khúc + quất, biển xanh "NƯỚC MÍA" trên hai cột."""
    cx, cy, cz = c
    st = Mat((206, 210, 214), rough=0.22, metal=1.0)
    parts = []

    def body(p):
        return rbox(p, (cx, cy, cz + 0.58), (0.58, 0.28, 0.32), 0.02)

    def body_tint(p, n, alb, idx):
        x, y, z = p
        seams = (np.abs(np.abs(x - cx) - 0.20) < 0.004) & (n[1] < -0.5)
        brushed = 0.92 + 0.08 * np.sin(z * 900 + fbm(x * 50, z * 5, 3, 2) * 4)
        out = alb * brushed[:, None]
        return np.where(seams[:, None], out * 0.5, out)
    parts.append(Obj('cart', body, st, tint=body_tint))
    # khung chân + bánh xe đẩy
    parts.append(Obj('cart_legs', lambda p: rbox((np.abs(p[0] - cx) - 0.52, np.abs(p[1] - cy) - 0.22, p[2]), (0, 0, cz + 0.17), (0.02, 0.02, 0.10), 0.005), st))
    parts += [o for o in moto_wheel((cx - 0.42, cy - 0.30, 0.17), r=0.17, axis='y')]
    parts += [o for o in moto_wheel((cx + 0.42, cy - 0.30, 0.17), r=0.17, axis='y')]
    # máy ép bên phải
    mx = cx + 0.30

    def press(p):
        housing = rbox(p, (mx, cy, cz + 1.05), (0.20, 0.17, 0.15), 0.025)
        motor = rbox(p, (mx + 0.02, cy + 0.10, cz + 1.25), (0.13, 0.08, 0.07), 0.03)
        chute = rbox(p, (mx - 0.05, cy - 0.20, cz + 0.98), (0.06, 0.05, 0.015), 0.008)
        return np.minimum(np.minimum(housing, motor), chute)
    parts.append(Obj('press', press, [st, Mat((40, 120, 70), rough=0.35, spec=0.6, coat=0.5)],
                     pick=lambda p, n: (p[2] > cz + 1.19).astype(np.int32)))
    parts.append(Obj('flywheel', lambda p: smax(np.abs(length2(p[0] - mx - 0.22, p[2] - cz - 1.08) - 0.14) - 0.018,
                                                 np.abs(p[1] - cy + 0.02) - 0.02, 0.004), Mat((60, 62, 66), rough=0.4, metal=0.7)))
    parts.append(Obj('rollers', lambda p: np.minimum(cyl_x(p, (mx, cy - 0.18, cz + 1.12), 0.035, 0.12),
                                                      cyl_x(p, (mx, cy - 0.18, cz + 1.05), 0.035, 0.12)), Mat((160, 164, 168), rough=0.3, metal=1.0),
                     tint=lambda p, n, alb, idx: alb * (0.75 + 0.25 * np.sin(np.arctan2(p[2] - cz - 1.08, p[1] - cy) * 30))[:, None]))
    # cốc nước mía trên mặt tủ
    for i, gx in enumerate((-0.42, -0.33, -0.24)):
        def juice(p, gx=gx):
            return round_cone(p, (cx + gx, cy - 0.18, cz + 0.91), (cx + gx, cy - 0.18, cz + 1.02), 0.026, 0.032)
        parts.append(Obj(f'juice{i}', juice, Mat((196, 200, 110), rough=0.08, spec=1.2, coat=1.0, wrap=0.5),
                         tint=lambda p, n, alb, idx: np.where((p[2] > cz + 1.0)[:, None], lin((236, 232, 200)), alb)))
    # tủ kính nhỏ bên trái: mía khúc + quất
    op, gl = glass_case((cx - 0.25, cy + 0.05, cz + 0.90), half=(0.24, 0.16, 0.16), items=False)
    parts += op
    pieces = []
    for i in range(7):
        x0 = cx - 0.42 + i * 0.05
        pieces.append(((lambda p, x0=x0: capsule(p, (x0, cy - 0.02, cz + 0.94), (x0 + 0.02, cy + 0.12, cz + 0.94 + 0.01 * (i % 2)), 0.018)), 0))
    fruits = [((lambda p, k=k: ellipsoid(p, (cx - 0.38 + 0.06 * k, cy + 0.08, cz + 0.97), (0.02, 0.02, 0.02))), 1) for k in range(5)]
    parts.append(multi_obj('case_fill', pieces + fruits, [Mat((226, 220, 170), rough=0.5, spec=0.5), Mat((236, 140, 30), rough=0.3, spec=0.7, coat=0.4)]))
    # biển xanh trên hai cột
    tex = sign_board_tex('NƯỚC MÍA', 900, 300, (24, 128, 66), (255, 255, 255), sub='SIÊU SẠCH', border=(250, 220, 60),
                         sub_col=(250, 220, 60))
    parts.append(panel('sign', (cx, cy + 0.05, cz + 1.72), 0.62, 0.21, 0.012, tex, mat=Mat((240, 240, 236), rough=0.35, spec=0.6, coat=0.3)))
    parts.append(Obj('sign_posts', lambda p: np.minimum(cyl(p, (cx - 0.55, cy + 0.08), 0.014, cz + 0.88, cz + 1.55),
                                                        cyl(p, (cx + 0.55, cy + 0.08), 0.014, cz + 0.88, cz + 1.55)), st))
    return parts, gl


def stall_nuoc_mia():
    parts = []
    parts += umbrella((0.35, 1.25, 0.0), R=1.30, h=2.55, cols=((36, 140, 66), (246, 206, 46)), seed=3)
    cart, gl = cane_cart((0.15, 0.55, 0.0))
    parts += cart
    parts += cane_bundle((-0.75, 0.65, 0.0), n=16, height=2.0, lean=0.08, seed=8)
    parts += at(p_seller_stand(), 0.35, 1.25)
    parts += at(stool((0, 0, 0), color=(206, 34, 36)), 1.15, 0.55)
    parts += at(stool((0, 0, 0), color=(40, 90, 180)), 1.45, 0.95)
    parts += at(p_sit_phone(), 1.30, 1.55, yaw=-0.5)
    return parts, gl


def shed(xh, y0, y1, h_front, h_back, roof_col=(64, 110, 150), post_r=0.055, overhang=0.25, seed=2):
    """Lán mái tôn: bốn cột gỗ, xà, mái tôn sóng dốc ra phía trước."""
    wood = Mat((110, 78, 50), rough=0.75, spec=0.3)
    parts = []

    def posts(p):
        x, y, z = p
        q = (np.abs(x) - xh, y, z)
        a = cyl(q, (0, y0), post_r, 0, h_front)
        b = cyl(q, (0, y1), post_r, 0, h_back)
        beam_f = rbox(p, (0, y0, h_front - 0.06), (xh + 0.1, 0.04, 0.06), 0.01)
        beam_b = rbox(p, (0, y1, h_back - 0.06), (xh + 0.1, 0.04, 0.06), 0.01)
        return np.minimum(np.minimum(a, b), np.minimum(beam_f, beam_b))
    parts.append(Obj('posts', posts, wood, bump=wood_bump(seed)))
    slope = (h_back - h_front) / (y1 - y0)
    k = math.sqrt(1 + slope * slope)

    def roof(p):
        x, y, z = p
        zr = h_front + 0.02 + (y - y0) * slope + 0.018 * np.sin(x * 2 * math.pi / 0.076)
        d = np.abs(z - zr) / k - 0.004
        d = smax(d, np.abs(x) - xh - overhang, 0.01)
        return smax(d, np.maximum(y0 - overhang - y, y - y1 - 0.15), 0.01)

    def tint(p, n, alb, idx):
        x, y, z = p
        rust = fbm(x * 3, y * 3, seed, 4)
        out = alb * (0.8 + 0.35 * rust[:, None])
        streak = (fbm(x * 30, y * 2, seed + 1, 2) > 0.62)
        out = np.where(streak[:, None], out * 0.7 + lin((120, 70, 40)) * 0.3, out)
        return out
    parts.append(Obj('roof', roof, [Mat(roof_col, rough=0.4, metal=0.5, spec=0.6), Mat(roof_col, rough=0.6, metal=0.3, spec=0.4)],
                     pick=lambda p, n: (n[2] < 0).astype(np.int32), tint=tint))
    return parts


def coffee_glass(c):
    cx, cy, cz = c
    return [Obj('coffee', lambda p: round_cone(p, (cx, cy, cz), (cx, cy, cz + 0.10), 0.026, 0.032),
                Mat((56, 32, 20), rough=0.06, spec=1.3, coat=1.0, wrap=0.4),
                tint=lambda p, n, alb, idx: np.where((p[2] > cz + 0.088)[:, None], lin((200, 170, 130)), alb))]


def stall_ca_phe_vong():
    parts = []
    xh = 1.75
    parts += shed(xh, 0.25, 2.15, 2.30, 2.55, roof_col=(150, 66, 50))
    hm, zc = hammock_parts(-xh, xh, 1.30, sag=0.62, y=0.25, color=(36, 120, 180), posts=False)
    parts += hm
    zlow = float(zc(np.array([0.1]))[0])
    parts += lying_person((0.18, 0.25, zlow + 0.14), tilt=0.40, top=(236, 236, 230), bottom=(40, 60, 100), kind='shirt',
                          skin='tan', seed=52)
    hm2, zc2 = hammock_parts(-xh, xh, 1.35, sag=0.60, y=2.15, color=(200, 60, 60), posts=False)
    parts += hm2
    hm3, zc3 = hammock_parts(-xh, xh, 1.32, sag=0.66, y=1.20, color=(60, 150, 80), posts=False)
    # võng giữa buộc vào hai cột phụ
    parts += hm3
    parts.append(Obj('mid_posts', lambda p: cyl((np.abs(p[0]) - xh, p[1], p[2]), (0, 1.20), 0.045, 0, 2.42),
                     Mat((110, 78, 50), rough=0.75), bump=wood_bump(4)))
    zl3 = float(zc3(np.array([-0.1]))[0])
    parts += lying_person((-0.05, 1.20, zl3 + 0.14), tilt=0.40, top=(60, 70, 90), bottom=(34, 34, 40), kind='jacket',
                          skin='mid', seed=53, height=1.66)
    tex = sign_board_tex('CÀ PHÊ VÕNG', 1100, 220, (250, 236, 200), (150, 40, 30), border=(150, 40, 30))
    parts.append(panel('sign', (0.0, 0.17, 2.12), 1.0, 0.20, 0.012, tex, mat=Mat((240, 240, 236), rough=0.6, spec=0.3),
                       back=Mat((110, 78, 50), rough=0.75)))
    parts += low_table((-1.05, 0.70, 0.0), half=(0.30, 0.22), h=0.42)
    parts += coffee_glass((-1.15, 0.65, 0.42))
    parts += coffee_glass((-0.98, 0.72, 0.42))
    parts += at(stool((0, 0, 0), color=(40, 90, 180)), -1.30, 1.15)
    parts += at(stool((0, 0, 0), color=(206, 34, 36)), 1.20, 0.75)
    return parts, []


def bread_loaves(c, n, dx=0.10, seed=1, rows=2):
    """Ổ bánh mì vàng giòn nằm dọc theo bề ngang tủ, xếp lớp so le."""
    cx, cy, cz = c
    rnd = random.Random(seed)
    items = []
    for r_ in range(rows):
        for i in range(n - r_):
            x = cx + (i - (n - r_ - 1) / 2) * dx + rnd.uniform(-0.01, 0.01)
            y = cy + r_ * 0.05 + rnd.uniform(-0.02, 0.02)
            z = cz + r_ * 0.05
            yaw = rnd.uniform(-0.25, 0.25) + math.pi / 2

            def loaf(p, x=x, y=y, z=z, yaw=yaw):
                u, v = rot(p[0] - x, p[1] - y, -yaw)
                return ellipsoid((u, v, p[2]), (0, 0, z + 0.034), (0.040, 0.15, 0.034))
            items.append((loaf, 0))
    o = multi_obj('loaves', items, [Mat((214, 150, 70), rough=0.4, spec=0.7, coat=0.3, wrap=0.3)])

    def tint(p, n, alb, idx):
        # vết khía trên lưng ổ bánh, chân bánh nhạt màu
        cut = (np.sin(p[0] * 60 + p[1] * 30) > 0.8) & (n[2] > 0.6)
        out = alb * (0.8 + 0.25 * n[2][:, None])
        return np.where(cut[:, None], out * 1.35, out)
    o.tint = tint
    return [o]


def bread_cart(c):
    """Xe bánh mì: tủ kính khung nhôm trên thân tôn đỏ, chữ "BÁNH MÌ" vàng
    viền đỏ, bánh mì vàng ruộm xếp hai tầng, bánh xe đạp hai bên."""
    cx, cy, cz = c
    red = Mat((196, 34, 32), rough=0.3, spec=0.6, coat=0.6)
    parts = []
    w, d = 0.62, 0.30
    tex = Image.new('RGBA', (1000, 300), (196, 34, 32, 255))
    dr = ImageDraw.Draw(tex)
    draw_center(dr, 'BÁNH MÌ', 'paytone', (40, 30, 960, 270), (252, 214, 60), stroke=6, stroke_fill=(120, 20, 20))
    lower = Obj('cart_body', lambda p: rbox(p, (cx, cy, cz + 0.55), (w, d, 0.27), 0.02), red,
                tint=decal(tex_sampler(tex), cx - w + 0.03, cx + w - 0.03, cz + 0.32, cz + 0.78))
    parts.append(lower)
    parts.append(Obj('cart_legs', lambda p: rbox((np.abs(p[0] - cx) - w + 0.05, np.abs(p[1] - cy) - d + 0.05, p[2]), (0, 0, cz + 0.15), (0.02, 0.02, 0.14), 0.005), STEEL))
    parts += moto_wheel((cx - w - 0.06, cy, 0.30), r=0.30, axis='x')
    parts += moto_wheel((cx + w + 0.06, cy, 0.30), r=0.30, axis='x')
    op, gl = glass_case((cx, cy, cz + 0.82), half=(w, d, 0.30), items=False)
    parts += op
    parts += bread_loaves((cx, cy - 0.06, cz + 0.835), 13, dx=0.088, seed=3)
    parts.append(Obj('mid_shelf', lambda p: rbox(p, (cx, cy, cz + 1.10), (w - 0.02, d - 0.02, 0.006), 0.002),
                     Mat((210, 214, 218), rough=0.2, spec=0.8)))
    parts += bread_loaves((cx, cy - 0.06, cz + 1.11), 12, dx=0.092, seed=4)
    # mặt kính trên: biển nhỏ "PATE - TRỨNG - CHẢ"
    tex2 = sign_board_tex('PATE · TRỨNG · CHẢ', 1000, 160, (252, 214, 60), (170, 30, 26), name='xbold')
    parts.append(panel('top_sign', (cx, cy - 0.02, cz + 1.50), w, 0.08, 0.01, tex2, mat=Mat((240, 240, 236), rough=0.4, spec=0.5, coat=0.3)))
    parts.append(Obj('top_posts', lambda p: cyl((np.abs(p[0] - cx) - w + 0.03, p[1], p[2]), (0, cy), 0.01, cz + 1.4, cz + 1.44), STEEL))
    return parts, gl


def stall_banh_mi():
    parts = []
    parts += umbrella((-0.10, 1.45, 0.0), R=1.30, h=2.55, cols=((206, 34, 36), (240, 240, 236)), seed=5)
    cart, gl = bread_cart((0.0, 0.45, 0.0))
    parts += cart
    parts += at(p_seller_man(), 0.10, 1.10)
    parts += at(stool((0, 0, 0), color=(40, 90, 180)), 1.10, 0.70)
    parts += cooler((-1.15, 1.05, 0.0), half=(0.26, 0.18, 0.18), color=(240, 240, 236))
    return parts, gl


def food_trays(c, w, seed=1):
    """Khay thức ăn trong tủ kính quán cơm: thịt kho, rau xào, trứng, đậu..."""
    cx, cy, cz = c
    cols = [(150, 70, 36), (70, 140, 50), (236, 200, 90), (200, 160, 110), (170, 50, 30), (110, 70, 50), (230, 220, 200)]
    items = []
    n = int(w / 0.22)
    for i in range(n):
        x = cx - w / 2 + 0.11 + i * 0.22
        k = i % len(cols)

        def heap(p, x=x):
            return ellipsoid(p, (x, cy, cz + 0.03), (0.09, 0.10, 0.035))
        items.append((heap, k))
    mats = [Mat(c, rough=0.4, spec=0.7, coat=0.3, wrap=0.3) for c in cols]
    o = multi_obj('food', items, mats)
    o.tint = lambda p, n, alb, idx: alb * (0.7 + 0.6 * fbm(p[0] * 90, p[1] * 90 + p[2] * 50, seed, 2))[:, None]
    trays = Obj('trays', lambda p: smax(rbox(p, (cx, cy, cz + 0.02), (w / 2, 0.12, 0.02), 0.006),
                                        -rbox(p, (cx, cy, cz + 0.035), (w / 2 - 0.01, 0.11, 0.02), 0.004), 0.002), STEEL)
    return [o, trays]


def stall_com():
    parts = []
    xh = 2.0
    # mái bạt căng trên cột sắt
    def tarp(p):
        x, y, z = p
        zr = 2.25 + 0.12 * (y - 0.2) + 0.05 * np.cos(x * math.pi / xh * 2)
        d = np.abs(z - zr) - 0.005
        d = smax(d, np.abs(x) - xh - 0.1, 0.01)
        return smax(d, np.maximum(0.05 - y, y - 2.3), 0.01)
    parts.append(Obj('tarp', tarp, [Mat(TARP_BLUE, rough=0.55, sheen=0.3, wrap=0.4, spec=0.5), Mat(TARP_BLUE, rough=0.9, wrap=0.5, emit=0.22)],
                     pick=lambda p, n: (n[2] < 0).astype(np.int32),
                     tint=lambda p, n, alb, idx: np.where((np.abs(((p[0] + 4) % 1.0) - 0.5) < 0.012)[:, None], alb * 0.7, alb)))
    parts.append(Obj('tarp_posts', lambda p: cyl((np.abs(p[0]) - xh, p[1], p[2]), (0, 0.15), 0.025, 0, 2.27),
                     Mat((160, 162, 166), rough=0.35, metal=0.9)))
    tex = sign_board_tex('CƠM BÌNH DÂN', 1300, 260, (200, 30, 30), (255, 230, 80), border=(255, 230, 80))
    parts.append(panel('sign', (0.0, 0.10, 2.05), 1.35, 0.27, 0.01, tex, mat=Mat((240, 240, 236), rough=0.6, sheen=0.3, spec=0.3),
                       back=Mat((200, 30, 30), rough=0.7)))
    # tủ kính bày thức ăn bên trái
    parts += low_table((-1.15, 0.55, 0.0), half=(0.62, 0.30), h=0.78, top_mat=STEEL, legs_mat=STEEL)
    op, gl = glass_case((-1.15, 0.55, 0.78), half=(0.60, 0.28, 0.26), items=False)
    parts += op
    parts += food_trays((-1.15, 0.50, 0.80), 1.1, seed=3)
    parts += food_trays((-1.15, 0.55, 1.04), 1.1, seed=4)
    # nồi cơm to
    def pot(p):
        x, y, z = p
        body = cyl(p, (-1.92, 0.95), 0.20, 0.35, 0.68) - 0.012
        lid = smax(ellipsoid(p, (-1.92, 0.95, 0.68), (0.20, 0.20, 0.06)), 0.68 - z, 0.004)
        knob = ellipsoid(p, (-1.92, 0.95, 0.75), (0.03, 0.03, 0.02))
        ears = rbox((np.abs(x + 1.92) - 0.22, y - 0.95, z), (0, 0, 0.62), (0.03, 0.02, 0.012), 0.008)
        stand = smax(np.abs(cyl(p, (-1.92, 0.95), 0.19, 0.0, 0.35)) - 0.008, -np.minimum(rbox(p, (-1.92, 0.95, 0.17), (0.10, 0.4, 0.10), 0.05),
                     rbox(p, (-1.92, 0.95, 0.17), (0.4, 0.10, 0.10), 0.05)), 0.01)
        return np.minimum(np.minimum(np.minimum(body, lid), np.minimum(knob, ears)), stand)
    parts.append(Obj('rice_pot', pot, [Mat((214, 218, 222), rough=0.25, metal=1.0), Mat((40, 40, 44), rough=0.5, spec=0.4)],
                     pick=lambda p, n: (p[2] < 0.35).astype(np.int32)))
    # bàn ăn + khách
    parts += low_table((0.75, 1.15, 0.0), half=(0.50, 0.30), h=0.45, top_mat=STEEL)
    parts += at(p_sit_tea(), 0.75, 1.65)
    parts += at(p_sit_woman(), 1.50, 1.05, yaw=-math.pi / 2)
    parts += at(stool((0, 0, 0), color=(40, 90, 180)), 0.20, 1.10)
    parts += at(stool((0, 0, 0), color=(206, 34, 36)), 0.65, 0.60)
    parts += at(p_seller_stand(), -1.10, 1.25)
    for gx in (0.55, 0.95):
        parts.append(Obj(f'bowl{gx}', (lambda gx: lambda p: smax(ellipsoid(p, (gx, 1.10, 0.48), (0.07, 0.07, 0.045)), p[2] - 0.50, 0.004))(gx),
                         Mat((240, 240, 236), rough=0.2, spec=0.8, coat=0.6)))
    return parts, gl


def tyre_stack(c, n=4, r=0.30):
    """Chồng lốp cũ nằm ngang (trục đứng)."""
    cx, cy, cz = c

    def sdf(p):
        x, y, z = p
        out = None
        for i in range(n):
            zc = cz + 0.06 + i * 0.12
            q = length2(x - cx - 0.01 * (i % 2), y - cy) - (r - 0.06)
            d = length2(np.maximum(np.abs(q) - 0.06 + 0.03, 0), np.maximum(np.abs(z - zc) - 0.06 + 0.03, 0)) - 0.03
            out = d if out is None else np.minimum(out, d)
        return out

    def tread(x, y, z):
        return np.sin(np.arctan2(y - cy, x - cx) * 70)
    return [Obj('tyres', sdf, Mat((34, 34, 36), rough=0.8, spec=0.35), bump=field_bump(tread, 0.0012))]


def compressor(c):
    """Máy nén khí: bình đỏ nằm ngang, mô-tơ + đầu nén, bánh xe, dây hơi."""
    cx, cy, cz = c
    parts = [Obj('tank', lambda p: smin(cyl_x(p, (cx, cy, cz + 0.30), 0.17, 0.30), ellipsoid(p, (cx, cy, cz + 0.30), (0.40, 0.17, 0.17)), 0.05),
                 Mat((196, 32, 30), rough=0.3, spec=0.6, coat=0.6)),
             Obj('motor', lambda p: np.minimum(rbox(p, (cx - 0.08, cy, cz + 0.55), (0.12, 0.10, 0.08), 0.03),
                                               cyl(p, (cx + 0.14, cy), 0.07, cz + 0.45, cz + 0.62)), Mat((50, 52, 56), rough=0.4, metal=0.5)),
             Obj('gauge', lambda p: cyl_y(p, (cx + 0.12, cy - 0.12, cz + 0.52), 0.035, 0.012), [Mat((240, 240, 236), rough=0.2, coat=1.0)]),
             Obj('legs', lambda p: np.minimum(rbox(p, (cx - 0.25, cy, cz + 0.07), (0.02, 0.12, 0.07), 0.01),
                                              rbox(p, (cx + 0.25, cy, cz + 0.07), (0.02, 0.12, 0.07), 0.01)), DARK_METAL)]

    def hose(p):
        x, y, z = p
        q = length2(x - cx - 0.55, y - cy + 0.05) - 0.16
        return length2(q, z - cz - 0.02 - 0.012 * np.sin(np.arctan2(y - cy, x - cx - 0.55) * 3)) - 0.012
    parts.append(Obj('hose', hose, Mat((30, 30, 32), rough=0.4, spec=0.6)))
    return parts


def basin(c, r=0.28, color=(40, 110, 190)):
    cx, cy, cz = c
    return [Obj('basin', lambda p: smax(round_cone(p, (cx, cy, cz + 0.02), (cx, cy, cz + 0.16), r * 0.8, r), -round_cone(p, (cx, cy, cz + 0.04), (cx, cy, cz + 0.19), r * 0.76, r - 0.012), 0.004),
                Mat(color, rough=0.3, spec=0.6, coat=0.3)),
            Obj('water', lambda p: smax(round_cone(p, (cx, cy, cz + 0.04), (cx, cy, cz + 0.12), r * 0.77, r * 0.92), p[2] - cz - 0.12, 0.002),
                Mat((90, 110, 120), rough=0.02, spec=1.0, coat=1.0))]


def stall_va_xe():
    parts = []
    parts += umbrella((0.25, 1.40, 0.0), R=1.30, h=2.50, cols=((206, 34, 36), (240, 240, 236)), seed=7)
    parts += tyre_stack((-1.65, 1.45, 0.0), n=5, r=0.30)
    parts += tyre_stack((-1.05, 1.75, 0.0), n=3, r=0.27)
    parts += compressor((1.55, 1.55, 0.0))
    parts += basin((-0.40, 0.35, 0.0))
    # xe máy đang vá, dựng chân chống, nhìn ngang (đầu xe bên trái)
    bike = v3.bike_parts((40, 90, 170), kickstand=True)
    parts += placed(bike, -1.00, 1.00, 0.0, yaw=-math.pi / 2)
    parts += at(p_mechanic(), 1.50, 0.60)
    tex = Image.new('RGBA', (700, 360), (238, 236, 228, 255))
    yy, xx = np.mgrid[0:360, 0:700]
    grain = (fbm(xx / 30.0, yy / 4.0, 4, 3) * 40).astype(np.int16)
    arr = np.asarray(tex).copy()
    arr[..., :3] = np.clip(arr[..., :3].astype(np.int16) - grain[..., None], 0, 255).astype(np.uint8)
    tex = Image.fromarray(arr)
    hand_text(tex, 'VÁ XE', (30, 30, 670, 330), (200, 26, 26), seed=11)
    parts.append(panel('sign', (-1.65, 0.72, 0.80), 0.34, 0.175, 0.012, tex, mat=Mat((236, 234, 226), rough=0.8, spec=0.2),
                       back=Mat((150, 120, 90), rough=0.9)))
    parts.append(Obj('sign_leg', lambda p: rbox(p, (-1.65, 0.74, 0.40), (0.025, 0.012, 0.40), 0.006), WOOD))
    return parts, []


def stall_xang_le():
    parts = []
    parts += umbrella((0.20, 1.10, 0.0), R=1.20, h=2.35, cols=((36, 140, 66), (246, 206, 46)), seed=9)
    parts += shelf((-0.35, 0.65, 0.0), w=0.95, d=0.32, h=0.95, tiers=3)
    for i, zt in enumerate((0.132, 0.536, 0.94)):
        parts += bottles((-0.35, 0.60, zt), (9, 1), spacing=(0.098, 0), seed=10 + i)
    tex = Image.new('RGBA', (600, 300), (246, 244, 236, 255))
    hand_text(tex, 'XĂNG', (20, 20, 580, 280), (206, 26, 26), seed=13)
    parts.append(panel('sign', (-0.35, 0.56, 1.30), 0.36, 0.18, 0.01, tex, mat=Mat((240, 240, 232), rough=0.75, spec=0.2),
                       back=Mat((110, 78, 50), rough=0.8)))
    parts.append(Obj('sign_posts', lambda p: rbox((np.abs(p[0] + 0.35) - 0.30, p[1], p[2]), (0, 0.58, 1.06), (0.015, 0.012, 0.14), 0.004), WOOD))
    parts += at(p_seller_sit((206, 34, 36)), 0.55, 0.85, yaw=-0.35)
    jc = t3.jerrycan_parts(y0=0.0, z0=0.0)
    parts += placed(jc, 1.05, 0.55, 0.0, yaw=0.3)
    def funnel(p):
        cone = round_cone(p, (1.02, 0.50, 0.42), (1.02, 0.50, 0.53), 0.012, 0.065)
        hollow = round_cone(p, (1.02, 0.50, 0.44), (1.02, 0.50, 0.56), 0.008, 0.060)
        return smin(smax(cone, -hollow, 0.003), cyl(p, (1.02, 0.50), 0.009, 0.34, 0.43), 0.006)
    parts.append(Obj('funnel', funnel, Mat((226, 120, 30), rough=0.35, spec=0.6)))
    return parts, []


STALLS = {
    'stall_tra_da': stall_tra_da,
    'stall_nuoc_mia': stall_nuoc_mia,
    'stall_ca_phe_vong': stall_ca_phe_vong,
    'stall_banh_mi': stall_banh_mi,
    'stall_com': stall_com,
    'stall_va_xe': stall_va_xe,
    'stall_xang_le': stall_xang_le,
}


# ================================================================ Đèn LED, biển phẳng
SEG = {'0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc', '5': 'afgcd', '6': 'afgedc', '7': 'abc',
       '8': 'abcdefg', '9': 'abcdfg', '-': 'g', ' ': ''}


def draw_7seg(draw, text, box, color, dim=None, slant=0.10, thick=0.13, gap=0.12):
    """Số LED 7 đoạn (đồng hồ giá xăng, đèn đếm ngược). Dấu '.' / ',' vẽ
    thành chấm nhỏ giữa hai số."""
    x0, y0, x1, y1 = box
    H = y1 - y0
    digits = [c for c in text if c not in '.,']
    n = len(digits)
    t = H * thick
    dw = H * 0.56
    sp = dw * 0.30
    total = n * dw + (n - 1) * sp
    x = (x0 + x1) / 2 - total / 2
    g = t * gap

    def P(px, py):
        return (px + (y1 - py) * slant, py)
    for ch in text:
        if ch in '.,':
            r = t * 0.55
            cx_ = x - sp / 2
            px_, py_ = P(cx_, y1 - r)
            draw.ellipse((px_ - r, py_ - r, px_ + r, py_ + r), fill=color)
            continue
        on = SEG.get(ch, '')
        L, R = x + t / 2, x + dw - t / 2
        T, M, B = y0 + t / 2, y0 + H / 2, y1 - t / 2
        segs = {'a': ('h', L, R, T), 'g': ('h', L, R, M), 'd': ('h', L, R, B),
                'f': ('v', L, T, M), 'b': ('v', R, T, M), 'e': ('v', L, M, B), 'c': ('v', R, M, B)}
        h2 = t / 2
        for name, (kind, a, b, c) in segs.items():
            col = color if name in on else dim
            if col is None:
                continue
            if kind == 'h':
                xa, xb, yy = a + g, b - g, c
                pts = [(xa, yy), (xa + h2, yy - h2), (xb - h2, yy - h2), (xb, yy), (xb - h2, yy + h2), (xa + h2, yy + h2)]
            else:
                xx, ya, yb = a, b + g, c - g
                pts = [(xx, ya), (xx + h2, ya + h2), (xx + h2, yb - h2), (xx, yb), (xx - h2, yb - h2), (xx - h2, ya + h2)]
            draw.polygon([P(px_, py_) for px_, py_ in pts], fill=col)
        x += dw + sp


def led_glow(img, radius=3, k=1.0):
    """Viền sáng mờ quanh chữ LED (ảnh nền đen)."""
    blur = img.filter(ImageFilter.GaussianBlur(radius))
    a = np.asarray(img, np.float64) + np.asarray(blur, np.float64) * k
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def plate(name, shape, center, size, tex, thick=0.006, back=(150, 152, 156), face_mat=None, rim=True):
    """Tấm biển kim loại hình 'disc' / 'tri' / 'rect' / 'oct' dựng đứng, mặt
    trước (−y) dán [tex] theo khung size = (rộng, cao)."""
    cx, cy, cz = center
    W, H = size

    def shape2d(x, z):
        u, v = x - cx, z - cz
        if shape == 'disc':
            return length2(u, v) - W / 2
        if shape == 'tri':
            # tam giác đều đỉnh lên: đáy ở v = -H/2, đỉnh ở v = +H/2
            side = (math.sqrt(3) * np.abs(u) + (v - H / 2)) / 2
            return np.maximum(side, -(v + H / 2))
        if shape == 'oct':
            uu, vv = np.abs(u), np.abs(v)
            return np.maximum(np.maximum(uu, vv), (uu + vv) / math.sqrt(2)) - W / 2
        qx, qz = np.abs(u) - W / 2 + 0.02, np.abs(v) - H / 2 + 0.02
        return length2(np.maximum(qx, 0), np.maximum(qz, 0)) + np.minimum(np.maximum(qx, qz), 0) - 0.02

    def sdf(p):
        x, y, z = p
        d2 = shape2d(x, z)
        e = np.abs(y - cy) - thick
        body = np.minimum(np.maximum(d2, e), 0) + length2(np.maximum(d2, 0), np.maximum(e, 0))
        if rim:
            lip = smax(np.abs(d2 + 0.008) - 0.008, np.abs(y - cy - thick * 1.5) - thick * 1.5, 0.002)
            body = np.minimum(body, lip)
        return body
    sm = tex_sampler(tex)
    fm = face_mat or Mat((240, 240, 236), rough=0.35, spec=0.6, coat=0.4)
    tint0 = decal(sm, cx - W / 2, cx + W / 2, cz - H / 2, cz + H / 2, face=-1)

    def pick(p, n):
        return ((n[1] > -0.5) | (p[1] > cy - thick * 0.5)).astype(np.int32)
    return Obj(name, sdf, [fm, Mat(back, rough=0.4, metal=0.8)], pick=pick,
               tint=lambda p, n, alb, idx: np.where((idx == 0)[:, None], tint0(p, n, alb, idx), alb))


GALV = Mat((172, 176, 180), rough=0.35, metal=0.9)


def sign_pole(x=0.0, y=0.05, h=2.9, r=0.038, base=True):
    """Cột biển báo thép mạ kẽm, chân đế bê tông."""
    parts = [Obj('pole', lambda p: cyl(p, (x, y), r, 0.0, h), GALV,
                 tint=lambda p, n, alb, idx: alb * (0.92 + 0.12 * fbm(p[2] * 6, p[0] * 40, 3, 2))[:, None]),
             Obj('cap', lambda p: ellipsoid(p, (x, y, h), (r * 1.05, r * 1.05, r * 0.5)), GALV)]
    if base:
        parts.append(Obj('footing', lambda p: smin(cyl(p, (x, y), 0.14, 0.0, 0.08), cyl(p, (x, y), 0.07, 0.0, 0.14), 0.03),
                         Mat((170, 168, 160), rough=0.85, spec=0.2)))
    return parts


def clamps(x, y, zs, r=0.04):
    """Đai ôm cột giữ biển."""
    items = [(lambda p, z=z: smax(np.abs(length2(p[0] - x, p[1] - y) - r - 0.006) - 0.006, np.abs(p[2] - z) - 0.02, 0.003), 0) for z in zs]
    return multi_obj('clamps', items, [GALV])


# ------------------------------------------------------------ Hình biển
def tex_speed(n, px=600):
    img = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, px - 1, px - 1), fill=(206, 24, 30, 255))
    rr = px * 0.40
    c = px / 2
    d.ellipse((c - rr, c - rr, c + rr, c + rr), fill=(248, 248, 244, 255))
    draw_center(d, str(n), 'xbold', (c - rr * 0.82, c - rr * 0.62, c + rr * 0.82, c + rr * 0.62), (20, 20, 22))
    return img


def tex_no_uturn(px=600):
    img = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = px / 2
    d.ellipse((0, 0, px - 1, px - 1), fill=(206, 24, 30, 255))
    rr = px * 0.40
    d.ellipse((c - rr, c - rr, c + rr, c + rr), fill=(248, 248, 244, 255))
    # mũi tên quay đầu: thân dọc phải, vòng cung trên, mũi tên chúc xuống bên trái
    k = px / 600
    w = 34 * k
    d.line([(c + 70 * k, c + 150 * k), (c + 70 * k, c - 40 * k)], fill=(20, 20, 22), width=int(w))
    d.arc((c - 70 * k, c - 110 * k, c + 70 * k + w / 2, c + 30 * k), 180, 360, fill=(20, 20, 22), width=int(w))
    d.line([(c - 70 * k + w / 2 - 17 * k, c - 40 * k), (c - 70 * k + w / 2 - 17 * k, c + 40 * k)], fill=(20, 20, 22), width=int(w))
    ax = c - 70 * k + w / 2 - 17 * k
    d.polygon([(ax - 55 * k, c + 30 * k), (ax + 55 * k, c + 30 * k), (ax, c + 110 * k)], fill=(20, 20, 22))
    # vạch chéo đỏ
    d.line([(c - rr * 0.72, c - rr * 0.72), (c + rr * 0.72, c + rr * 0.72)], fill=(206, 24, 30), width=int(56 * k))
    return img


def tex_curve(left=True, px=700):
    """Biển W.201: tam giác vàng viền đỏ, mũi tên cong đen."""
    H = int(px * math.sqrt(3) / 2)
    img = Image.new('RGBA', (px, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(px / 2, 0), (px, H), (0, H)], fill=(206, 24, 30, 255))
    m = px * 0.11
    d.polygon([(px / 2, m * 1.25), (px - m, H - m * 0.62), (m, H - m * 0.62)], fill=(250, 200, 30, 255))
    k = px / 700
    # đường mũi tên: thẳng lên rồi cong 90° sang trái / phải, mũi tên ở cuối
    sgn = -1 if left else 1
    x0, yb = px / 2 - sgn * 55 * k, H - m * 0.62 - 45 * k
    R = 105 * k
    pts = [(x0, yb - t) for t in np.linspace(0, 150 * k, 30)]
    cy_ = yb - 150 * k
    for a in np.linspace(0, math.pi / 2, 30):
        pts.append((x0 + sgn * R * (1 - math.cos(a)), cy_ - R * math.sin(a)))
    w = 42 * k
    for (ax, ay) in pts:
        d.ellipse((ax - w / 2, ay - w / 2, ax + w / 2, ay + w / 2), fill=(18, 18, 20))
    ex, ey = pts[-1]
    d.polygon([(ex, ey - 52 * k), (ex, ey + 52 * k), (ex + sgn * 85 * k, ey)], fill=(18, 18, 20))
    return img


def tex_city(px=(900, 600)):
    w, h = px
    img = Image.new('RGBA', (w, h), (24, 84, 170, 255))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((8, 8, w - 9, h - 9), radius=30, outline=(248, 248, 244), width=10)
    # dãy nhà trắng
    base = int(h * 0.55)
    xs = [(0.16, 0.22, 0.30), (0.30, 0.16, 0.42), (0.44, 0.20, 0.34), (0.60, 0.15, 0.46), (0.73, 0.16, 0.30)]
    for x, ww, hh in xs:
        X0, X1 = int(w * x), int(w * (x + ww * 0.9))
        d.rectangle((X0, base - int(h * hh), X1, base), fill=(248, 248, 244))
        for wy in range(base - int(h * hh) + 18, base - 20, 34):
            for wx in range(X0 + 12, X1 - 18, 30):
                d.rectangle((wx, wy, wx + 14, wy + 18), fill=(24, 84, 170))
    d.polygon([(int(w * 0.30), base - int(h * 0.42)), (int(w * 0.37), base - int(h * 0.55)), (int(w * 0.44), base - int(h * 0.42))], fill=(248, 248, 244))
    draw_center(d, 'KHU ĐÔNG DÂN CƯ', 'xbold', (40, int(h * 0.62), w - 40, h - 40), (248, 248, 244))
    return img


def round_sign(tex, d=0.70, h=2.9, shape='disc', size=None):
    """Biển trên cột: mép trên biển cao [h] m, đỉnh cột khuất sau biển."""
    sz = size or (d, d)
    zc = h - sz[1] / 2
    parts = sign_pole(0.0, 0.06, h=zc + sz[1] * 0.3)
    parts.append(plate('plate', shape, (0.0, 0.0, zc), sz, tex))
    parts.append(clamps(0.0, 0.06, (zc - sz[1] * 0.28, zc + sz[1] * 0.28)))
    parts.append(Obj('bracket', lambda p: rbox(p, (0.0, 0.025, zc), (0.03, 0.022, sz[1] * 0.36), 0.006), GALV))
    return parts


def sign_speed(n):
    return lambda: (round_sign(tex_speed(n)), [])


def sign_curve(left):
    def build():
        tex = tex_curve(left)
        H = 0.70 * math.sqrt(3) / 2
        return round_sign(tex, h=2.9, shape='tri', size=(0.70, H)), []
    return build


SIGNS = {
    'sign_speed_50': sign_speed(50),
    'sign_speed_60': sign_speed(60),
    'sign_speed_80': sign_speed(80),
    'sign_curve_left': sign_curve(True),
    'sign_curve_right': sign_curve(False),
    'sign_no_uturn': lambda: (round_sign(tex_no_uturn()), []),
    'sign_city': lambda: (round_sign(tex_city(), h=3.0, shape='rect', size=(1.2, 0.8)), []),
}
SIGN_PPM = 150.0


# ================================================================ Cây xăng
RED_PAINT = Mat((200, 30, 34), rough=0.3, spec=0.6, coat=0.6)
WHITE_PAINT = Mat((238, 238, 234), rough=0.35, spec=0.6, coat=0.5)
BLUE_PAINT = Mat((28, 70, 160), rough=0.3, spec=0.6, coat=0.6)


def curb_tint(cz, h, period=0.30):
    """Sơn vạch vàng đen trên mặt trước gờ đảo."""
    def tint(p, n, alb, idx):
        x, y, z = p
        band = ((np.floor((x + z) / period) % 2) == 0) & (n[1] < -0.5)
        out = np.where(band[:, None], lin((240, 196, 30)), np.where((n[1] < -0.5)[:, None], lin((24, 24, 26)), alb))
        return out
    return tint


def pump_display_tex():
    w, h = 600, 520
    img = Image.new('RGBA', (w, h), (18, 20, 24, 255))
    d = ImageDraw.Draw(img)
    rows = [('THÀNH TIỀN', '150000'), ('SỐ LÍT', '6.27'), ('ĐƠN GIÁ', '23950')]
    for i, (lab, val) in enumerate(rows):
        y0 = 20 + i * 165
        d.rounded_rectangle((20, y0, w - 20, y0 + 150), radius=12, fill=(30, 34, 40), outline=(90, 96, 104), width=3)
        draw_center(d, lab, 'xbold', (30, y0 + 6, 300, y0 + 40), (220, 224, 228))
        draw_7seg(d, val, (40, y0 + 52, w - 50, y0 + 138), (255, 70, 40), dim=(52, 20, 18))
    return led_glow(img, 3, 0.6)


def gas_pump():
    """Trụ bơm xăng (nhìn từ phía trước, ~2,2 m): thân trắng đỏ, màn số LED,
    hai vòi bơm treo hai bên, dây vòi cong, đảo bê tông sơn vàng đen."""
    parts = []
    parts.append(Obj('island', lambda p: rbox(p, (0, 0.40, 0.10), (0.75, 0.40, 0.10), 0.02),
                     Mat((180, 178, 170), rough=0.8, spec=0.2), tint=curb_tint(0, 0.2)))

    def body(p):
        return rbox(p, (0, 0.40, 1.08), (0.40, 0.24, 0.88), 0.03)

    def body_pick(p, n):
        x, y, z = p
        red = (z > 1.72) | ((z > 0.70) & (z < 0.80))
        return red.astype(np.int32)
    parts.append(Obj('pump_body', body, [WHITE_PAINT, RED_PAINT], pick=body_pick))
    # nắp đầu trụ đỏ có chữ
    tex = sign_board_tex('XĂNG', 500, 160, (200, 30, 34), (255, 255, 255), name='paytone')
    parts.append(panel('head', (0, 0.155, 1.86), 0.36, 0.10, 0.01, tex, mat=Mat((240, 240, 236), rough=0.3, spec=0.6, coat=0.6)))
    disp = pump_display_tex()
    parts.append(plate('display', 'rect', (0, 0.155, 1.36), (0.52, 0.45), disp, thick=0.006,
                       face_mat=Mat((240, 240, 240), rough=0.1, spec=1.0, coat=1.0, emit=0.55), rim=False))
    # bàn phím
    keys = Image.new('RGBA', (300, 200), (40, 44, 50, 255))
    dk = ImageDraw.Draw(keys)
    for r_ in range(3):
        for c_ in range(4):
            dk.rounded_rectangle((20 + c_ * 70, 20 + r_ * 60, 70 + c_ * 70, 62 + r_ * 60), radius=8, fill=(200, 204, 208))
    parts.append(plate('keypad', 'rect', (0.0, 0.155, 1.00), (0.26, 0.17), keys, thick=0.005, rim=False))
    # chữ nhỏ loại xăng
    lab = sign_board_tex('RON 95', 400, 120, (36, 92, 176), (255, 255, 255), name='xbold')
    parts.append(plate('label', 'rect', (0.0, 0.155, 0.62), (0.40, 0.12), lab, thick=0.005, rim=False))
    # bao vòi + vòi bơm hai bên
    for sg, col in ((-1, (30, 140, 70)), (1, (240, 190, 30))):
        hx = sg * 0.43
        parts.append(Obj(f'holster{sg}', (lambda hx: lambda p: rbox(p, (hx, 0.40, 1.20), (0.04, 0.09, 0.10), 0.015))(hx), Mat((40, 42, 46), rough=0.4, spec=0.5)))

        def nozzle(p, hx=hx, sg=sg):
            grip = round_cone(p, (hx + sg * 0.02, 0.33, 1.06), (hx + sg * 0.03, 0.30, 1.25), 0.022, 0.03)
            spout = round_cone(p, (hx + sg * 0.03, 0.30, 1.25), (hx + sg * 0.03, 0.18, 1.22), 0.012, 0.01)
            return smin(grip, spout, 0.01)
        parts.append(Obj(f'nozzle{sg}', nozzle, Mat(col, rough=0.3, spec=0.7, coat=0.5)))
        hose = bezier_tube((sg * 0.38, 0.35, 1.75), (sg * 0.68, 0.30, 1.20), (hx + sg * 0.02, 0.33, 1.06), 0.016, 0.016, n=12)
        parts.append(Obj(f'hose{sg}', hose, Mat((24, 24, 26), rough=0.35, spec=0.6)))
    return parts, []


def gas_shop():
    """Cửa hàng ở cây xăng (~6 m): tường trắng, dải biển đỏ xanh, mặt kính
    nhôm (nhìn thấy kệ hàng, quầy), cửa kính, bình cứu hoả, chậu quất Tết,
    băng rôn "CHÚC MỪNG NĂM MỚI"."""
    parts, glass = [], []
    W, D, H = 3.0, 3.2, 3.5  # nửa rộng, sâu, cao
    wall = Mat((236, 234, 228), rough=0.7, spec=0.3)

    def building(p):
        x, y, z = p
        outer = rbox(p, (0, D / 2 + 0.3, H / 2), (W, D / 2, H / 2), 0.02)
        # khoét mặt tiền kính
        win = rbox(p, (0.0, 0.3, 1.40), (W - 0.35, 0.25, 1.15), 0.005)
        inside = rbox(p, (0, D / 2 + 0.3, 1.55), (W - 0.2, D / 2 - 0.2, 1.4), 0.02)
        return smax(smax(outer, -win, 0.004), -inside, 0.004)
    parts.append(Obj('building', building, [wall, Mat((90, 92, 96), rough=0.8)],
                     pick=lambda p, n: (p[2] < 0.15).astype(np.int32)))
    parts.append(Obj('step', lambda p: rbox(p, (0, 0.15, 0.06), (W + 0.1, 0.25, 0.06), 0.01), Mat((176, 174, 168), rough=0.8)))
    # dải biển trên mặt tiền
    tex = Image.new('RGBA', (2400, 300), (240, 240, 236, 255))
    d = ImageDraw.Draw(tex)
    d.rectangle((0, 0, 2400, 60), fill=(200, 30, 34))
    d.rectangle((0, 240, 2400, 300), fill=(28, 70, 160))
    draw_center(d, 'CỬA HÀNG XĂNG DẦU', 'paytone', (120, 70, 2280, 232), (200, 30, 34))
    parts.append(panel('fascia', (0, 0.26, 3.05), W + 0.05, 0.38, 0.03, tex, mat=Mat((240, 240, 236), rough=0.4, spec=0.5, coat=0.3)))
    # khung nhôm mặt kính
    def mullions(p):
        x, y, z = p
        out = rbox(p, (0, 0.33, 0.27), (W - 0.35, 0.04, 0.03), 0.004)
        out = np.minimum(out, rbox(p, (0, 0.33, 2.53), (W - 0.35, 0.04, 0.03), 0.004))
        for xm in (-1.55, -0.55, 0.55, 1.55):
            out = np.minimum(out, rbox(p, (xm, 0.33, 1.40), (0.03, 0.04, 1.15), 0.004))
        out = np.minimum(out, rbox(p, (0, 0.33, 2.25), (W - 0.35, 0.035, 0.02), 0.004))
        # tay nắm cửa
        out = np.minimum(out, rbox((np.abs(x) - 0.08, y, z), (0, 0.28, 1.10), (0.012, 0.03, 0.25), 0.008))
        return out
    parts.append(Obj('mullions', mullions, Mat((180, 184, 188), rough=0.3, metal=0.9)))
    glass.append(Obj('shop_glass', lambda p: rbox(p, (0, 0.33, 1.40), (W - 0.36, 0.006, 1.14), 0.002), Mat((200, 210, 215))))
    # bên trong: kệ hàng nhiều màu, quầy thu ngân, đèn trần
    rnd = random.Random(5)
    cols = [(220, 40, 40), (240, 200, 40), (40, 120, 200), (40, 160, 80), (240, 240, 236), (230, 120, 40)]
    items = []
    for xs in (-2.1, -1.0, 1.4):
        for tier in range(4):
            x = xs - 0.45
            while x < xs + 0.45:
                w = rnd.uniform(0.04, 0.08)
                hgt = rnd.uniform(0.12, 0.25)
                items.append((((lambda p, x=x, w=w, hgt=hgt, tier=tier: rbox(p, (x + w, 2.2, 0.30 + tier * 0.42 + hgt / 2), (w, 0.12, hgt / 2), 0.006))), rnd.randrange(len(cols))))
                x += 2 * w + 0.01
    parts.append(multi_obj('goods', items, [Mat(c, rough=0.4, spec=0.6, coat=0.3) for c in cols]))
    parts.append(Obj('racks', union(*[(lambda tier: lambda q: rbox(q, (-0.6, 2.25, 0.28 + tier * 0.42), (2.4, 0.2, 0.01), 0.004))(t)
                                      for t in range(4)]), Mat((200, 204, 208), rough=0.3, metal=0.6)))
    parts.append(Obj('counter', lambda p: rbox(p, (0.35, 1.30, 0.50), (0.65, 0.30, 0.50), 0.02), [Mat((200, 30, 34), rough=0.4, spec=0.5), Mat((240, 240, 236), rough=0.3)],
                     pick=lambda p, n: (p[2] > 0.96).astype(np.int32)))
    parts.append(Obj('lights', lambda p: union(*[(lambda xl: lambda q: rbox(q, (xl, 1.8, 2.92), (0.5, 0.06, 0.02), 0.01))(xl) for xl in (-1.6, 0.0, 1.6)])(p),
                     Mat((255, 255, 250), rough=0.3, emit=3.0)))
    parts.append(Obj('back_wall_inner', lambda p: rbox(p, (0, 3.0, 1.5), (W - 0.2, 0.05, 1.5), 0.01), Mat((226, 230, 232), rough=0.8, emit=0.15)))
    # băng rôn Tết
    ban = Image.new('RGBA', (1600, 200), (200, 26, 30, 255))
    db = ImageDraw.Draw(ban)
    draw_center(db, 'CHÚC MỪNG NĂM MỚI', 'paytone', (60, 20, 1540, 180), (252, 214, 60))
    parts.append(panel('banner', (0.0, 0.22, 2.42), 1.25, 0.15, 0.004, ban, mat=Mat((240, 240, 236), rough=0.6, sheen=0.4)))
    # bình cứu hoả, chậu quất hai bên cửa
    parts.append(Obj('extinguisher', lambda p: smin(round_cone(p, (2.72, 0.12, 0.15), (2.72, 0.12, 0.62), 0.085, 0.08),
                                                     cyl(p, (2.72, 0.12), 0.025, 0.6, 0.72), 0.02), RED_PAINT))
    parts.append(Obj('ext_stand', lambda p: rbox(p, (2.72, 0.12, 0.07), (0.14, 0.12, 0.02), 0.005), RED_PAINT))
    parts += kumquat_pot((-0.75, 0.10, 0.12), scale=2.0, seed=31, pot_color=(40, 70, 140))
    parts += kumquat_pot((0.75, 0.10, 0.12), scale=2.0, seed=32, pot_color=(40, 70, 140))
    # máy lạnh treo tường bên trái
    parts.append(Obj('ac', lambda p: rbox(p, (-2.55, 0.25, 2.62), (0.30, 0.12, 0.25), 0.02), Mat((214, 216, 214), rough=0.4, spec=0.5),
                     tint=lambda p, n, alb, idx: np.where((np.sin(p[2] * 120) > 0.7)[:, None] & (n[1] < -0.5)[:, None], alb * 0.6, alb)))
    return parts, glass


def price_tex():
    w, h = 700, 1100
    img = Image.new('RGBA', (w, h), (240, 240, 236, 255))
    d = ImageDraw.Draw(img)
    # đầu biển: nền đỏ, giọt lửa vàng, chữ
    d.rectangle((0, 0, w, 330), fill=(200, 30, 34))
    d.ellipse((w / 2 - 70, 70, w / 2 + 70, 210), fill=(252, 200, 40))
    d.polygon([(w / 2 - 66, 150), (w / 2, 20), (w / 2 + 66, 150)], fill=(252, 200, 40))
    d.ellipse((w / 2 - 30, 130, w / 2 + 30, 190), fill=(200, 30, 34))
    draw_center(d, 'XĂNG DẦU', 'paytone', (40, 220, w - 40, 320), (255, 255, 255))
    d.rectangle((0, 330, w, 350), fill=(28, 70, 160))
    rows = [('RON 95', '24.350'), ('E5 RON 92', '23.120'), ('DẦU DO', '20.870')]
    for i, (lab, val) in enumerate(rows):
        y0 = 380 + i * 235
        d.rounded_rectangle((30, y0, w - 30, y0 + 210), radius=16, fill=(28, 70, 160))
        draw_center(d, lab, 'xbold', (50, y0 + 10, w - 50, y0 + 64), (255, 255, 255))
        d.rectangle((50, y0 + 74, w - 50, y0 + 196), fill=(10, 10, 12))
    return img


def gas_price_sign():
    """Trụ biển giá xăng (~5,5 m): hai chân hộp, mặt biển đỏ-trắng-xanh, ba
    dòng giá số LED đỏ."""
    parts = []
    tex = price_tex()
    W, H = 1.40, 2.2
    zc = 5.3 - H / 2
    parts.append(plate('face', 'rect', (0, 0.0, zc), (W, H), tex, thick=0.12, back=(200, 30, 34), rim=False))
    parts.append(Obj('legs', lambda p: rbox((np.abs(p[0]) - 0.42, p[1], p[2]), (0, 0.0, zc / 2), (0.12, 0.10, zc / 2), 0.02),
                     [Mat((200, 30, 34), rough=0.3, spec=0.6, coat=0.6)]))
    parts.append(Obj('base', lambda p: rbox(p, (0, 0.0, 0.15), (0.75, 0.30, 0.15), 0.02), Mat((180, 178, 170), rough=0.8), tint=curb_tint(0, 0.3)))
    # ba dải số LED (tự phát sáng)
    for i, val in enumerate(('24.350', '23.120', '20.870')):
        img = Image.new('RGBA', (620, 150), (10, 10, 12, 255))
        dd = ImageDraw.Draw(img)
        draw_7seg(dd, val, (40, 18, 580, 132), (255, 60, 36), dim=(40, 14, 12))
        img = led_glow(img, 4, 0.7)
        # vị trí theo texture: ô số ở y0 + 74 .. y0 + 196 trên ảnh 1100 px
        y0 = 380 + i * 235
        v0, v1 = (y0 + 74) / 1100, (y0 + 196) / 1100
        z1 = zc + H / 2 - v0 * H
        z0 = zc + H / 2 - v1 * H
        u0, u1 = 50 / 700, (700 - 50) / 700
        parts.append(plate(f'led{i}', 'rect', ((u0 + u1) / 2 * W - W / 2, -0.125, (z0 + z1) / 2), ((u1 - u0) * W, z1 - z0), img,
                           thick=0.004, face_mat=Mat((255, 255, 255), rough=0.1, spec=1.0, coat=1.0, emit=1.6), rim=False))
    return parts, []


# ================================================================ Trạm thu phí
def toll_booth():
    """Ca-bin thu phí trên đảo bê tông: tường trắng sọc xanh, cửa sổ kính lớn
    (nhân viên ngồi bên trong), mái đua, đèn làn trên nóc, cọc chống va."""
    parts, glass = [], []
    parts.append(Obj('island', lambda p: rbox(p, (0, 1.0, 0.13), (1.0, 1.4, 0.13), 0.03), Mat((180, 178, 170), rough=0.8), tint=curb_tint(0, 0.26)))

    def cab(p):
        outer = rbox(p, (0, 1.0, 1.55), (0.80, 0.70, 1.30), 0.04)
        win = rbox(p, (0, 0.30, 1.75), (0.58, 0.2, 0.55), 0.03)
        inner = rbox(p, (0, 1.0, 1.55), (0.74, 0.64, 1.24), 0.03)
        return smax(smax(outer, -win, 0.004), -inner, 0.004)

    def cab_pick(p, n):
        z = p[2]
        return (((z > 0.70) & (z < 0.95)) | (z > 2.7)).astype(np.int32)
    parts.append(Obj('cab', cab, [WHITE_PAINT, BLUE_PAINT], pick=cab_pick))
    parts.append(Obj('roof', lambda p: rbox(p, (0, 1.0, 2.92), (1.0, 0.95, 0.06), 0.02), Mat((60, 64, 70), rough=0.4, metal=0.5)))
    parts.append(Obj('sill', lambda p: rbox(p, (0, 0.28, 1.18), (0.62, 0.08, 0.02), 0.006), Mat((180, 184, 188), rough=0.3, metal=0.8)))
    glass.append(Obj('win_glass', lambda p: rbox(p, (0, 0.34, 1.75), (0.58, 0.006, 0.55), 0.002), Mat((200, 210, 215))))
    # nhân viên bên trong (nửa người trên), ghế, máy tính
    f = Fig(1.66, 'f')
    s = f.s
    for side, sg in (('l', -1), ('r', 1)):
        f.arm(side, (sg * 0.2 * s, -0.12, 1.08 * s), (sg * 0.12, -0.32, 1.02 * s), (0, -0.8, 0))
    staff = person(f, (36, 92, 176), (40, 44, 56), kind='shirt', skin='light', hair_style='bun', seed=71)
    parts += placed(staff, 0.0, 1.20, 0.30)
    parts.append(Obj('desk', lambda p: rbox(p, (0, 0.62, 1.10), (0.70, 0.25, 0.02), 0.005), Mat((150, 120, 90), rough=0.6)))
    parts.append(Obj('monitor', lambda p: rbox(p, (0.35, 0.70, 1.30), (0.18, 0.02, 0.13), 0.01), [Mat((30, 30, 34), rough=0.3), Mat((120, 180, 230), emit=0.8)],
                     pick=lambda p, n: (n[1] > 0.6).astype(np.int32)))
    parts.append(Obj('inside', lambda p: rbox(p, (0, 1.62, 1.55), (0.75, 0.03, 1.25), 0.01), Mat((220, 222, 220), rough=0.8, emit=0.1)))
    # biển nhỏ trên cửa sổ, đèn làn trên nóc
    t = sign_board_tex('THU PHÍ', 600, 140, (28, 70, 160), (255, 255, 255), name='xbold')
    parts.append(panel('label', (0, 0.28, 2.50), 0.45, 0.10, 0.008, t))
    lamp = Image.new('RGBA', (200, 200), (12, 12, 14, 255))
    dl = ImageDraw.Draw(lamp)
    dl.polygon([(100, 170), (30, 70), (70, 70), (70, 30), (130, 30), (130, 70), (170, 70)], fill=(40, 240, 120))
    lamp = led_glow(lamp, 6, 0.8)
    parts.append(Obj('lamp_box', lambda p: rbox(p, (0, 0.55, 3.15), (0.22, 0.10, 0.17), 0.02), Mat((30, 32, 36), rough=0.4)))
    parts.append(plate('lamp', 'rect', (0, 0.44, 3.15), (0.30, 0.30), lamp, thick=0.004,
                       face_mat=Mat((255, 255, 255), rough=0.1, coat=1.0, emit=1.6), rim=False))
    parts.append(Obj('lamp_post', lambda p: cyl(p, (0, 0.55), 0.03, 2.95, 3.0), DARK_METAL))
    # cọc chống va sơn vàng đen
    parts.append(Obj('bollard', lambda p: smin(cyl(p, (0, -0.25), 0.10, 0.0, 0.95), ellipsoid(p, (0, -0.25, 0.95), (0.10, 0.10, 0.05)), 0.02),
                     Mat((240, 196, 30), rough=0.35, spec=0.6, coat=0.5),
                     tint=lambda p, n, alb, idx: np.where(((np.floor((p[2] + 0.4 * np.arctan2(p[1] + 0.25, p[0]) / math.pi * 0.2) / 0.16) % 2) == 1)[:, None], lin((24, 24, 26)), alb)))
    return parts, glass


def toll_barrier():
    """Thanh chắn trạm thu phí: tủ điều khiển bên trái, cần chắn sọc đỏ trắng
    nằm ngang (đóng) dài 3 m, đầu cao su."""
    L = 3.0
    x0 = -(L + 0.35) / 2  # gốc toạ độ ở giữa cả cụm
    zc = 1.0
    parts = []
    parts.append(Obj('cabinet', lambda p: rbox(p, (x0 + 0.17, 0.2, 0.55), (0.17, 0.17, 0.55), 0.02),
                     [Mat((240, 196, 30), rough=0.35, spec=0.6, coat=0.5), Mat((30, 30, 32), rough=0.4)],
                     pick=lambda p, n: (p[2] < 0.12).astype(np.int32)))
    parts.append(Obj('hub', lambda p: cyl_y(p, (x0 + 0.17, 0.02, zc), 0.08, 0.03), DARK_METAL))

    def boom(p):
        x, y, z = p
        a = rbox(p, (x0 + 0.17 + L / 2 + 0.05, 0.0, zc), (L / 2, 0.035, 0.05), 0.02)
        return a

    def boom_tint(p, n, alb, idx):
        t = (p[0] - x0 - 0.2) / 0.40
        red = (np.floor(t) % 2) == 0
        return np.where(red[:, None], lin((206, 26, 30)), alb)
    parts.append(Obj('boom', boom, Mat((244, 244, 240), rough=0.3, spec=0.6, coat=0.6), tint=boom_tint))
    parts.append(Obj('tip', lambda p: rbox(p, (x0 + 0.17 + L + 0.08, 0.0, zc), (0.06, 0.04, 0.055), 0.02), Mat((30, 30, 32), rough=0.7)))
    return parts, []


def toll_fascia(w=1024, h=192, path=None):
    """Dải diềm mái trạm thu phí, lặp ngang liền mạch (1024 px = 8 m, 1,5 m
    cao): nền xanh lá đậm, chữ trắng, hai hộp đèn làn: mũi tên xanh (mở) và
    dấu X đỏ (đóng)."""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    a = np.zeros((h, w, 3))
    yy = np.arange(h)[:, None] / h
    base = np.array([20, 96, 70]) / 255
    shade = 0.82 + 0.22 * np.exp(-((yy - 0.25) / 0.25) ** 2)
    a[:] = base[None, None, :] * shade[..., None]
    xx = np.arange(w)[None, :]
    seam = (xx % 128) < 2
    a[np.broadcast_to(seam, (h, w))] *= 0.75
    a[: int(h * 0.06)] = np.array([210, 214, 218]) / 255
    a[int(h * 0.94):] = np.array([150, 154, 160]) / 255
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert('RGBA')
    d = ImageDraw.Draw(img)
    draw_center(d, 'TRẠM THU PHÍ', 'paytone', (int(w * 0.24), int(h * 0.18), int(w * 0.76), int(h * 0.82)), (255, 255, 255))
    for cxp, kind in ((w * 0.11, 'go'), (w * 0.89, 'stop')):
        bx0, by0 = int(cxp - h * 0.33), int(h * 0.14)
        bx1, by1 = int(cxp + h * 0.33), int(h * 0.86)
        d.rounded_rectangle((bx0, by0, bx1, by1), radius=10, fill=(12, 12, 14), outline=(120, 124, 130), width=3)
        cxx, cyy, r = (bx0 + bx1) / 2, (by0 + by1) / 2, (bx1 - bx0) * 0.36
        lamp = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        dl = ImageDraw.Draw(lamp)
        if kind == 'go':
            col = (40, 240, 120, 255)
            dl.polygon([(cxx, cyy + r), (cxx - r, cyy - r * 0.1), (cxx - r * 0.4, cyy - r * 0.1), (cxx - r * 0.4, cyy - r),
                        (cxx + r * 0.4, cyy - r), (cxx + r * 0.4, cyy - r * 0.1), (cxx + r, cyy - r * 0.1)], fill=col)
        else:
            col = (255, 50, 40, 255)
            dl.line([(cxx - r, cyy - r), (cxx + r, cyy + r)], fill=col, width=int(r * 0.45))
            dl.line([(cxx - r, cyy + r), (cxx + r, cyy - r)], fill=col, width=int(r * 0.45))
        glow = lamp.filter(ImageFilter.GaussianBlur(5))
        img.alpha_composite(glow)
        img.alpha_composite(lamp)
    return img


def gas_fascia(w=1024, h=128):
    """Dải diềm mái che cây xăng, lặp ngang (1024 px = 12 m, cao 1,5 m): sọc
    đỏ trên, nền trắng, sọc xanh dưới, chữ "XĂNG DẦU" đỏ, nẹp nhôm."""
    a = np.zeros((h, w, 3))
    yy = np.arange(h)[:, None] / h
    white = np.array([242, 242, 238]) / 255
    a[:] = white
    a[(yy < 0.22).repeat(w, 1)] = np.array([200, 30, 34]) / 255
    a[(yy > 0.80).repeat(w, 1)] = np.array([28, 70, 160]) / 255
    # bóng nhẹ: sáng phía trên (trời), tối dần xuống
    a *= (1.04 - 0.12 * yy)[..., None]
    xx = np.arange(w)[None, :]
    a[np.broadcast_to((xx % 128) < 1, (h, w))] *= 0.86
    a[: 3] = np.array([220, 222, 226]) / 255
    a[-4:] = np.array([120, 124, 130]) / 255
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert('RGBA')
    d = ImageDraw.Draw(img)
    # giọt lửa + chữ ở giữa ô
    f, (l, t, r, b) = fit_font(d, 'XĂNG DẦU', 'paytone', w * 0.5, h * 0.50)
    tw = r - l
    fh = h * 0.40
    total = fh * 0.75 + 18 + tw
    x = w / 2 - total / 2
    cy = h * 0.51
    d.ellipse((x, cy - fh * 0.12, x + fh * 0.75, cy + fh * 0.5), fill=(240, 160, 30))
    d.polygon([(x + 1, cy + fh * 0.16), (x + fh * 0.375, cy - fh * 0.55), (x + fh * 0.75 - 1, cy + fh * 0.16)], fill=(240, 160, 30))
    d.ellipse((x + fh * 0.22, cy + fh * 0.08, x + fh * 0.53, cy + fh * 0.38), fill=(250, 220, 90))
    d.text((x + fh * 0.75 + 18 - l, cy - (t + b) / 2), 'XĂNG DẦU', font=f, fill=(200, 30, 34))
    return img


# ================================================================ Chốt CSGT
def plastic_chair(c, yaw=0.0, color=(36, 90, 180)):
    """Ghế nhựa có tựa (quán, lều CSGT)."""
    m = Mat(color, rough=0.3, spec=0.7, coat=0.3)

    def sdf(p):
        x, y, z = p
        seat = rbox(p, (0, 0, 0.44), (0.22, 0.21, 0.02), 0.015)
        back = rbox(p, (0, 0.21 + 0.06 * np.clip((z - 0.46) / 0.4, 0, 1), 0.66), (0.21, 0.015, 0.20), 0.012)
        back = smax(back, -rbox(p, (0, 0.22, 0.66), (0.14, 0.1, 0.03), 0.01), 0.004)
        q = (np.abs(x) - 0.19, np.abs(y) - 0.17, z)
        legs = round_cone(q, (0, 0, 0.43), (0.03 * 1, 0.03, 0.0), 0.022, 0.016)
        arms = rbox((np.abs(x) - 0.22, y, z), (0, 0.0, 0.62), (0.02, 0.2, 0.012), 0.008)
        return np.minimum(np.minimum(seat, back), np.minimum(legs, arms))
    return placed([Obj('chair', sdf, m)], c[0], c[1], c[2], yaw=yaw)


def police_tent():
    """Lều bạt xanh dương (~4 m): khung sắt, mái chóp, diềm bạt; bàn phủ khăn
    xanh, ghế nhựa, bộ đàm, sổ."""
    parts = []
    hw, y0, y1 = 2.0, 0.20, 2.70
    zl, zr = 2.15, 2.85

    def roof(p):
        x, y, z = p
        ym = (y0 + y1) / 2
        # mái chóp bốn mặt
        t = np.maximum(np.abs(x) / hw, np.abs(y - ym) / ((y1 - y0) / 2))
        f = zr - (zr - zl) * t
        d = (z - f) / 1.2
        sh = np.abs(d) - 0.005
        return smax(sh, t - 1.04, 0.01)

    def valance(p):
        x, y, z = p
        ym = (y0 + y1) / 2
        box_ = rbox(p, (0, ym, zl - 0.12), (hw * 1.04, (y1 - y0) / 2 * 1.04, 0.13), 0.01)
        inner = rbox(p, (0, ym, zl - 0.12), (hw * 1.04 - 0.008, (y1 - y0) / 2 * 1.04 - 0.008, 0.2), 0.01)
        return smax(box_, -inner, 0.003)
    tarp = [Mat(TARP_BLUE, rough=0.55, sheen=0.3, wrap=0.4, spec=0.5), Mat(TARP_BLUE, rough=0.9, wrap=0.5, emit=0.25)]
    parts.append(Obj('tent_roof', lambda p: np.minimum(roof(p), valance(p)), tarp, pick=lambda p, n: (n[2] < -0.05).astype(np.int32),
                     bump=fabric_bump(25, 0.002, 3),
                     tint=lambda p, n, alb, idx: np.where((np.abs(p[2] - zl + 0.12) < 0.03)[:, None], lin((240, 240, 236)), alb)))
    parts.append(Obj('tent_legs', lambda p: cyl((np.abs(p[0]) - hw + 0.02, np.abs(p[1] - (y0 + y1) / 2) - (y1 - y0) / 2 + 0.02, p[2]), (0, 0), 0.022, 0, zl),
                     Mat((200, 202, 206), rough=0.3, metal=0.9)))
    # bàn phủ khăn xanh lá
    parts.append(Obj('table', lambda p: rbox(p, (0, 1.20, 0.38), (0.75, 0.38, 0.38), 0.02), Mat((30, 110, 70), rough=0.8, sheen=0.4, wrap=0.3),
                     bump=fabric_bump(30, 0.002, 5)))
    parts.append(Obj('book', lambda p: rbox(p, (-0.25, 1.10, 0.775), (0.12, 0.09, 0.012), 0.004), Mat((236, 236, 230), rough=0.6)))
    parts.append(Obj('radio', lambda p: rbox(p, (0.30, 1.15, 0.84), (0.03, 0.02, 0.08), 0.008), Mat((30, 30, 32), rough=0.4)))
    parts += plastic_chair((-0.40, 1.85, 0.0), yaw=0.0)
    parts += plastic_chair((0.40, 1.85, 0.0), yaw=0.1)
    f = sit_fig(1.72, 'm', stool_h=0.44, knees=0.14)
    for side, sg in (('l', -1), ('r', 1)):
        f.arm(side, (sg * 0.22, -0.12, f.j['sh_l'][2] - 0.27), (sg * 0.12, -0.36, 0.80), (0, -0.9, 0.0))
    parts += placed(police_parts(f, seed=33), -0.40, 1.80, 0.0)
    parts += plastic_chair((1.40, 1.20, 0.0), yaw=-math.pi / 2 + 0.2)
    return parts, []


def police_sign():
    """Biển đứng chốt kiểm soát: bảng xanh viền trắng trên giá chữ A."""
    w, h = 1200, 700
    img = Image.new('RGBA', (w, h), (24, 70, 160, 255))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((14, 14, w - 15, h - 15), radius=26, outline=(255, 255, 255), width=12)
    d.rectangle((14, 14, w - 15, 200), fill=(200, 30, 34))
    draw_center(d, 'CẢNH SÁT GIAO THÔNG', 'xbold', (60, 40, w - 60, 180), (255, 255, 255))
    draw_center(d, 'TRẠM KIỂM SOÁT', 'paytone', (60, 240, w - 60, 460), (255, 230, 70))
    draw_center(d, 'ĐỀ NGHỊ GIẢM TỐC ĐỘ', 'xbold', (100, 500, w - 100, 640), (255, 255, 255))
    parts = [plate('board', 'rect', (0, 0.0, 1.05), (1.20, 0.70), img, thick=0.012)]

    def frame(p):
        x, y, z = p
        q = (np.abs(x) - 0.52, y, z)
        front = capsule(q, (0, 0.03, 1.40), (0, 0.03, 0.0), 0.02)
        back = capsule(q, (0, 0.06, 1.40), (0, 0.55, 0.0), 0.02)
        bar = capsule(p, (-0.52, 0.30, 0.35), (0.52, 0.30, 0.35), 0.015)
        return np.minimum(np.minimum(front, back), bar)
    parts.append(Obj('frame', frame, Mat((200, 202, 206), rough=0.3, metal=0.9)))
    return parts, []


def traffic_cone(c=(0, 0.2, 0), h=0.70):
    cx, cy, cz = c

    def sdf(p):
        x, y, z = p
        body = round_cone(p, (cx, cy, cz + 0.05), (cx, cy, cz + h - 0.02), 0.13, 0.025)
        base = rbox(p, (cx, cy, cz + 0.02), (0.19, 0.19, 0.02), 0.02)
        return smin(body, base, 0.02)

    def pick(p, n):
        z = p[2] - cz
        band = ((z > h * 0.36) & (z < h * 0.50)) | ((z > h * 0.62) & (z < h * 0.72))
        base = z < 0.045
        return np.where(base, 2, np.where(band, 1, 0)).astype(np.int32)
    return [Obj('cone', sdf, [Mat((240, 92, 20), rough=0.35, spec=0.6, coat=0.4),
                              Mat((236, 236, 236), rough=0.15, spec=1.2, metal=0.3, coat=0.6),
                              Mat((30, 30, 32), rough=0.6)], pick=pick)]


def pothole_cone():
    """Cọc tiêu cũ đặt nghiêng cạnh ổ gà: bám bụi đất, sứt mẻ, vài cục nhựa
    đường vỡ quanh chân."""
    cone = traffic_cone((0, 0, 0))
    old = cone[0].tint

    def dirty(p, n, alb, idx):
        out = alb if old is None else old(p, n, alb, idx)
        dust = smoothstep(0.35, 0.0, p[2]) * (0.4 + 0.6 * fbm(p[0] * 30, p[2] * 30 + p[1] * 20, 8, 3))
        streak = (fbm(p[0] * 60, p[2] * 6, 9, 2) > 0.62) * 0.35
        k = np.clip(dust * 0.8 + streak, 0, 0.85) * np.where(idx == 2, 0.25, 1.0)
        return out * (1 - k[:, None]) + lin((120, 96, 70))[None, :] * k[:, None]
    cone[0].tint = dirty
    parts = placed(cone, 0.0, 0.25, 0.0, R=rot_mat('x', -0.13) @ rot_mat('y', 0.06))
    rnd = random.Random(4)
    items = []
    for i in range(7):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.22, 0.34)
        c = (math.cos(a) * r, 0.25 + math.sin(a) * r * 0.7, 0.0)
        e = (rnd.uniform(0.03, 0.06), rnd.uniform(0.025, 0.05), rnd.uniform(0.015, 0.03))
        items.append(((lambda p, c=c, e=e: ellipsoid(p, c, e)), 0))
    chunks = multi_obj('chunks', items, [Mat((54, 52, 50), rough=0.9, spec=0.2)])
    chunks.tint = lambda p, n, alb, idx: alb * (0.7 + 0.6 * vnoise(p[0] * 300, p[1] * 300 + p[2] * 200, 3))[:, None]
    return parts + [chunks], []


# ================================================================ Linh tinh
def bus_shelter():
    """Nhà chờ xe buýt: cột thép, mái xanh dương cong, vách kính sau, ghế
    inox, biển "ĐIỂM DỪNG XE BUÝT" trên diềm mái, pa-nô quảng cáo Tết."""
    parts, glass = [], []
    hw, d = 1.75, 1.5
    parts.append(Obj('posts', lambda p: cyl((np.abs(p[0]) - hw + 0.05, p[1], p[2]), (0, d - 0.1), 0.045, 0, 2.55),
                     Mat((200, 204, 208), rough=0.3, metal=0.9)))

    def roof(p):
        x, y, z = p
        zr = 2.60 + 0.25 * (1 - ((y - d / 2) / (d / 2 + 0.3)) ** 2)
        dd = np.abs(z - zr) - 0.02
        dd = smax(dd, np.abs(x) - hw - 0.15, 0.01)
        return smax(dd, np.abs(y - d / 2) - d / 2 - 0.3, 0.01)
    parts.append(Obj('roof', roof, [Mat((24, 84, 170), rough=0.3, spec=0.6, coat=0.5), Mat((20, 70, 150), rough=0.5)],
                     pick=lambda p, n: (n[2] < 0).astype(np.int32)))
    tex = sign_board_tex('ĐIỂM DỪNG XE BUÝT', 1600, 180, (24, 84, 170), (255, 255, 255), name='xbold')
    parts.append(panel('fascia', (0, -0.34, 2.64), hw + 0.15, 0.12, 0.02, tex, mat=Mat((240, 240, 236), rough=0.35, spec=0.6, coat=0.4)))
    glass.append(Obj('back_glass', lambda p: rbox(p, (-0.55, d - 0.1, 1.35), (1.1, 0.006, 1.05), 0.002), Mat((200, 210, 215))))
    ad = Image.new('RGBA', (500, 900), (200, 26, 30, 255))
    da = ImageDraw.Draw(ad)
    da.ellipse((60, 120, 440, 500), fill=(240, 180, 40))
    for k in range(5):
        a = k * math.tau / 5 - math.pi / 2
        da.ellipse((250 + 120 * math.cos(a) - 90, 310 + 120 * math.sin(a) - 90, 250 + 120 * math.cos(a) + 90, 310 + 120 * math.sin(a) + 90), fill=(250, 214, 70))
    da.ellipse((200, 260, 300, 360), fill=(220, 120, 30))
    draw_center(da, 'XUÂN', 'paytone', (60, 560, 440, 700), (252, 230, 120))
    draw_center(da, 'AN KHANG', 'xbold', (60, 720, 440, 800), (255, 255, 255))
    parts.append(Obj('ad_frame', lambda p: rbox(p, (1.15, d - 0.1, 1.40), (0.48, 0.05, 0.92), 0.02), Mat((180, 184, 188), rough=0.3, metal=0.9)))
    parts.append(panel('ad', (1.15, d - 0.16, 1.40), 0.42, 0.80, 0.006, ad, mat=Mat((240, 240, 236), rough=0.2, spec=0.8, coat=0.8, emit=0.35)))

    def bench(p):
        x, y, z = p
        seat = rbox(p, (-0.45, d - 0.45, 0.45), (0.95, 0.20, 0.02), 0.01)
        legs = rbox((np.abs(x + 0.45) - 0.8, y, z), (0, d - 0.45, 0.22), (0.025, 0.15, 0.22), 0.006)
        return np.minimum(seat, legs)
    parts.append(Obj('bench', bench, Mat((200, 204, 208), rough=0.25, metal=1.0),
                     tint=lambda p, n, alb, idx: np.where(((np.sin(p[0] * 160) > 0.6) & (n[2] > 0.5))[:, None], alb * 0.4, alb)))
    return parts, glass


def lixi_tex(w=360, h=640):
    img = Image.new('RGBA', (w, h), (200, 18, 28, 255))
    d = ImageDraw.Draw(img)
    gold = (238, 192, 70)
    d.rectangle((14, 14, w - 15, h - 15), outline=gold, width=8)
    d.rectangle((28, 28, w - 29, h - 29), outline=gold, width=3)
    # nắp phong bao
    d.polygon([(28, 28), (w - 29, 28), (w / 2, 200)], outline=gold)
    d.line([(28, 28), (w / 2, 200), (w - 29, 28)], fill=gold, width=4)
    cx, cy, r = w / 2, 380, 110
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=gold, width=8)
    for k in range(5):
        a = k * math.tau / 5 - math.pi / 2
        px_, py_ = cx + 45 * math.cos(a), cy - 30 + 45 * math.sin(a)
        d.ellipse((px_ - 30, py_ - 30, px_ + 30, py_ + 30), fill=gold)
    d.ellipse((cx - 18, cy - 48, cx + 18, cy - 12), fill=(200, 18, 28))
    draw_center(d, 'LỘC', 'paytone', (cx - 80, cy + 30, cx + 80, cy + 90), gold)
    draw_center(d, 'AN KHANG', 'xbold', (50, 530, w - 50, 600), gold)
    return img


def lixi_float():
    tex = lixi_tex()
    W, H = 0.09, 0.16
    parts = [plate('envelope', 'rect', (0, 0.0, H / 2 + 0.002), (W, H), tex, thick=0.0015, back=(190, 18, 26),
                   face_mat=Mat((240, 240, 236), rough=0.25, spec=0.9, coat=0.7), rim=False)]
    return parts, []


def gift_peach():
    """Cành đào rơi nằm trên đường (nhìn ngang): gốc bọc giấy đỏ bên trái."""
    parts = peach_branch((0, 0, 0), height=0.85, seed=41)
    # quay cho cánh quạt cành toả theo chiều sâu, trục cành nằm dọc x
    R = rot_mat('y', math.pi / 2 - 0.10) @ rot_mat('z', math.pi / 2)
    return placed(parts, -0.62, 0.25, 0.17, R=R), []


def gift_kumquat():
    return kumquat_pot((0, 0, 0), scale=1.25, seed=44, pot_color=(150, 40, 30)), []


def gift_box():
    parts = gift_box_parts((0, 0.15, 0.13), (0.17, 0.13, 0.13), color=(206, 26, 30), ribbon=(240, 196, 60))
    parts += gift_box_parts((0.03, 0.15, 0.31), (0.10, 0.08, 0.05), color=(240, 196, 60), ribbon=(206, 26, 30))
    return parts, []


def nail_sign():
    w, h = 700, 420
    tex = cardboard_tex(w, h, seed=9)
    hand_text(tex, 'CẨN THẬN', (30, 20, w - 30, 200), (20, 20, 24), seed=21)
    hand_text(tex, 'ĐINH TẶC', (30, 200, w - 30, 400), (200, 26, 26), seed=22)
    parts = [panel('card', (0, 0.0, 0.95), 0.32, 0.19, 0.004, tex, mat=Mat((190, 152, 104), rough=0.9, spec=0.2),
                   back=Mat((170, 136, 96), rough=0.9))]
    parts.append(Obj('stick', lambda p: capsule(p, (0.0, 0.015, 0.0), (0.01, 0.015, 1.10), 0.016), WOOD, bump=wood_bump(3)))
    parts.append(Obj('nails', lambda p: union(*[(lambda z: lambda q: ellipsoid(q, (0.0, -0.004, z), (0.008, 0.004, 0.008)))(z) for z in (0.85, 1.05)])(p),
                     Mat((150, 150, 150), rough=0.3, metal=1.0)))
    return parts, []


# ================================================================ Đèn giao thông
LAMP_COLS = {'red': (255, 50, 36), 'yellow': (255, 186, 24), 'green': (40, 236, 120)}


def lamp_tex(col, on):
    """Mặt đèn LED: lưới chấm sáng (bật) hoặc tối (tắt)."""
    n = 220
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = tuple(int(c * (1.0 if on else 0.16)) for c in col)
    d.ellipse((0, 0, n - 1, n - 1), fill=base + (255,))
    if on:
        for yy in range(10, n, 16):
            for xx in range(10, n, 16):
                if (xx - n / 2) ** 2 + (yy - n / 2) ** 2 < (n / 2 - 12) ** 2:
                    d.ellipse((xx - 5, yy - 5, xx + 5, yy + 5), fill=(255, 255, 230, 255))
        img = img.filter(ImageFilter.GaussianBlur(1.5))
    else:
        for yy in range(10, n, 16):
            for xx in range(10, n, 16):
                if (xx - n / 2) ** 2 + (yy - n / 2) ** 2 < (n / 2 - 12) ** 2:
                    d.ellipse((xx - 4, yy - 4, xx + 4, yy + 4), fill=tuple(int(c * 0.28) for c in col) + (255,))
    return img


def traffic_light_head(lit):
    """Cụm đèn 3 bóng dọc (đỏ trên, vàng giữa, xanh dưới) có chụp che nắng,
    tấm nền đen viền trắng; hộp đếm ngược "15" bên phải. Gốc: giữa cả cụm;
    giá treo ở đỉnh."""
    parts = []
    xh = -0.20  # tâm cụm 3 bóng (hộp số bên phải)
    zc = 0.75
    house = Mat((26, 28, 30), rough=0.45, spec=0.5, coat=0.3)
    parts.append(Obj('housing', lambda p: rbox(p, (xh, 0.12, zc), (0.17, 0.11, 0.52), 0.04), house))
    back = Image.new('RGBA', (300, 900), (18, 18, 20, 255))
    ImageDraw.Draw(back).rounded_rectangle((6, 6, 293, 893), radius=30, outline=(240, 240, 236), width=12)
    parts.append(plate('backplate', 'rect', (xh, 0.24, zc), (0.50, 1.40), back, thick=0.008, back=(18, 18, 20)))
    for i, (name, dz) in enumerate((('red', 0.34), ('yellow', 0.0), ('green', -0.34))):
        on = name == lit
        z = zc + dz
        tex = lamp_tex(LAMP_COLS[name], on)
        fm = Mat((255, 255, 255), rough=0.08, spec=1.0, coat=1.0, emit=2.2 if on else 0.0)
        parts.append(plate(f'lamp_{name}', 'disc', (xh, -0.005, z), (0.24, 0.24), tex, thick=0.006, face_mat=fm, back=(20, 20, 22), rim=False))

        def visor(p, z=z):
            x, y, zz = p
            r = length2(x - xh, zz - z)
            sh = smax(np.abs(r - 0.135) - 0.006, np.maximum(y - 0.01, -0.20 - y + 0.12 * np.clip((z - zz) / 0.135, 0, 1) * 1.0), 0.004)
            return smax(sh, z - 0.03 - zz, 0.004)
        parts.append(Obj(f'visor{i}', visor, house))
    # hộp đếm ngược
    col = LAMP_COLS[lit]
    img = Image.new('RGBA', (300, 300), (8, 8, 10, 255))
    draw_7seg(ImageDraw.Draw(img), '15', (40, 50, 260, 250), col, dim=tuple(int(c * 0.12) for c in col))
    img = led_glow(img, 5, 0.8)
    parts.append(Obj('count_box', lambda p: rbox(p, (0.22, 0.12, zc), (0.17, 0.10, 0.17), 0.03), house))
    parts.append(plate('count', 'rect', (0.22, 0.015, zc), (0.28, 0.28), img, thick=0.004,
                       face_mat=Mat((255, 255, 255), rough=0.1, coat=1.0, emit=1.8), rim=False))
    parts.append(Obj('count_arm', lambda p: rbox(p, (0.02, 0.15, zc), (0.06, 0.03, 0.03), 0.01), house))
    parts.append(Obj('bracket', lambda p: np.minimum(cyl(p, (xh, 0.12), 0.03, zc + 0.52, zc + 0.75),
                                                     rbox(p, (xh, 0.12, zc + 0.77), (0.07, 0.07, 0.03), 0.01)), DARK_METAL))
    return parts, []


def traffic_light_pole():
    """Cột đèn tín hiệu có cần vươn ngang sang trái (cột đứng ở lề phải):
    cao 6 m, cần dài 4,5 m; chân cột sơn sọc vàng đen."""
    parts = []
    H, L = 6.0, 4.5
    paint_ = Mat((196, 200, 204), rough=0.35, metal=0.85)

    def pole(p):
        x, y, z = p
        main = round_cone(p, (0, 0.1, 0.05), (0, 0.1, H), 0.11, 0.08)
        arm = round_cone(p, (0.0, 0.1, H - 0.35), (-L, 0.1, H - 0.15), 0.075, 0.05)
        brace = capsule(p, (0.0, 0.1, H - 1.2), (-1.4, 0.1, H - 0.30), 0.03)
        base = rbox(p, (0, 0.1, 0.03), (0.26, 0.26, 0.03), 0.01)
        return np.minimum(np.minimum(smin(main, arm, 0.05), brace), base)

    def tint(p, n, alb, idx):
        x, y, z = p
        stripe = (z < 1.2) & (z > 0.06) & ((np.floor((z + 0.0) / 0.2) % 2) == 0)
        out = np.where(stripe[:, None], lin((24, 24, 26)), np.where(((z < 1.2) & (z > 0.06))[:, None], lin((240, 196, 30)), alb))
        return out
    parts.append(Obj('pole', pole, paint_, tint=tint))
    parts.append(Obj('cap', lambda p: ellipsoid(p, (0, 0.1, H), (0.085, 0.085, 0.05)), paint_))
    parts.append(Obj('arm_end', lambda p: ellipsoid(p, (-L, 0.1, H - 0.15), (0.03, 0.055, 0.055)), paint_))
    return parts, []


MISC = {
    'gas_pump': gas_pump,
    'gas_shop': gas_shop,
    'gas_price_sign': gas_price_sign,
    'toll_booth': toll_booth,
    'toll_barrier': toll_barrier,
    'police_tent': police_tent,
    'police_sign': police_sign,
    'traffic_cone': lambda: (traffic_cone(), []),
    'bus_shelter': bus_shelter,
    'lixi_float': lixi_float,
    'gift_peach': gift_peach,
    'gift_kumquat': gift_kumquat,
    'gift_box': gift_box,
    'nail_sign': nail_sign,
    'traffic_light_head_red': lambda: traffic_light_head('red'),
    'traffic_light_head_yellow': lambda: traffic_light_head('yellow'),
    'traffic_light_head_green': lambda: traffic_light_head('green'),
    'traffic_light_pole': traffic_light_pole,
}


# ================================================================ Danh mục
# tên → (hàm dựng trả về (vật, kính) hoặc danh sách vật, ppm, kind, tuỳ chọn)
def _p(fn):
    return lambda: (fn(), [])


CATALOG = {}


def reg(group, name, fn, ppm, kind, **opt):
    CATALOG[name] = dict(group=group, fn=fn, ppm=ppm, kind=kind, **opt)


for _n, _f in PEOPLE.items():
    _k = 'police' if _n.startswith('police') else ('worker' if _n.startswith(('worker', 'seller')) else 'person')
    reg('people', _n, _p(_f), PERSON_PPM, _k)
for _n, _f in ANIMALS.items():
    reg('animals', _n, _p(_f), ANIMAL_PPM, 'animal', facing='left')
for _n, _f in STALLS.items():
    reg('stalls', _n, _f, STALL_PPM, 'stall', ss=3)
for _n, _f in SIGNS.items():
    reg('signs', _n, _f, SIGN_PPM, 'sign', ss=3)
reg('gas', 'gas_pump', gas_pump, 150, 'gas_station')
reg('gas', 'gas_shop', gas_shop, 105, 'gas_station', ss=3)
reg('gas', 'gas_price_sign', gas_price_sign, 120, 'gas_station', ss=3, glow=3)
reg('toll', 'toll_booth', toll_booth, 130, 'toll', ss=3, glow=3)
reg('toll', 'toll_barrier', toll_barrier, 150, 'toll', ss=3)
reg('police', 'police_tent', police_tent, 130, 'police', ss=3)
reg('police', 'police_sign', police_sign, 180, 'police', ss=3)
reg('police', 'traffic_cone', lambda: (traffic_cone(), []), 300, 'prop')
reg('misc', 'pothole_warning_cone', pothole_cone, 300, 'prop')
reg('misc', 'bus_shelter', bus_shelter, 130, 'prop', ss=3)
reg('misc', 'nail_sign', nail_sign, 220, 'prop')
reg('pickups', 'lixi_float', lixi_float, 1500, 'pickup', catch=0.0)
reg('pickups', 'gift_peach', gift_peach, 400, 'pickup', ss=3)
reg('pickups', 'gift_kumquat', gift_kumquat, 400, 'pickup')
reg('pickups', 'gift_box', gift_box, 400, 'pickup')
for _c in ('red', 'yellow', 'green'):
    reg('lights', f'traffic_light_head_{_c}', (lambda c: lambda: traffic_light_head(c))(_c), 220, 'traffic_light', glow=5,
        catch=0.0)
reg('lights', 'traffic_light_pole', traffic_light_pole, 80, 'traffic_light', ss=3)

# điểm neo phụ (toạ độ mét trong mô hình) → ghi vào props.json dạng [u, v]
# chuẩn hoá theo ảnh (u từ trái, v từ trên)
ANCHORS = {
    'traffic_light_head_red': {'mount': (-0.20, 1.55)},
    'traffic_light_head_yellow': {'mount': (-0.20, 1.55)},
    'traffic_light_head_green': {'mount': (-0.20, 1.55)},
    'traffic_light_pole': {'arm_tip': (-4.5, 5.85)},
    'toll_barrier': {'pivot': (-(3.0 + 0.35) / 2 + 0.17, 1.0)},
}

FLAT = {
    'gas_canopy_fascia': (gas_fascia, 12.0, 1.5, 'fascia'),
    'toll_fascia': (toll_fascia, 8.0, 1.5, 'fascia'),
}


def build_one(name, out):
    if name in FLAT:
        fn, wm, hm, kind = FLAT[name]
        img = fn()
        img.save(f'{out}/{name}.png', optimize=True)
        REGISTRY[name] = dict(h_m=hm, w_m=wm, kind=kind, tile_x=True)
        print(f'{name}: {img.size[0]}x{img.size[1]}', flush=True)
        return img
    c = CATALOG[name]
    res = c['fn']()
    objs, glass = res if isinstance(res, tuple) else (res, [])
    extra = {k: c[k] for k in ('facing',) if k in c}
    img = shoot(out, name, objs, c['ppm'], c['kind'], ss=c.get('ss', 4), glass=glass, glow=c.get('glow', 0),
                catch=c.get('catch', 0.55), extra=extra)
    if name in ANCHORS:
        w, h = img.size
        ppm = c['ppm']
        for k, (ax, az) in ANCHORS[name].items():
            REGISTRY[name][k] = [round(0.5 + ax * ppm / w, 4), round(1 - az * ppm / h, 4)]
    return img


GROUPS = sorted({c['group'] for c in CATALOG.values()} | {'fascia'})


def names_for(groups):
    out = []
    for g in groups:
        if g == 'fascia':
            out += list(FLAT)
        else:
            out += [n for n, c in CATALOG.items() if c['group'] == g]
    return out


def contact_sheet(out, path, names=None):
    """Bảng xem nhanh mọi ảnh trên nền trời / mặt đường, kèm tên và cỡ."""
    names = names or sorted(REGISTRY)
    cell_w, cell_h = 340, 300
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell_w, rows * cell_h), (0, 0, 0))
    d = ImageDraw.Draw(sheet)
    small = font('semi', 13)
    for i, n in enumerate(names):
        x0, y0 = (i % cols) * cell_w, (i // cols) * cell_h
        horizon = y0 + int(cell_h * 0.80)
        for yy in range(y0, horizon):
            t = (yy - y0) / max(horizon - y0, 1)
            d.line([(x0, yy), (x0 + cell_w, yy)], fill=(int(150 + 60 * t), int(185 + 40 * t), int(225 + 15 * t)))
        d.rectangle((x0, horizon, x0 + cell_w, y0 + cell_h), fill=(92, 92, 90))
        try:
            im = Image.open(f'{out}/{n}.png').convert('RGBA')
        except FileNotFoundError:
            continue
        s = min((cell_w - 16) / im.width, (cell_h - 40) / im.height, 2.0)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
        if REGISTRY.get(n, {}).get('kind') == 'fascia':
            py = y0 + 30
        else:
            py = horizon + 10 - im.height
        sheet.paste(im, (x0 + (cell_w - im.width) // 2, max(py, y0 + 4)), im)
        r = REGISTRY.get(n, {})
        d.rectangle((x0, y0 + cell_h - 20, x0 + cell_w, y0 + cell_h), fill=(20, 20, 22))
        d.text((x0 + 6, y0 + cell_h - 18), f"{n}  {r.get('w_m', '?')}×{r.get('h_m', '?')} m", font=small, fill=(255, 255, 255))
    sheet.save(path)
    return sheet


def main(argv):
    out = OUT
    sheet = None
    only = []
    args = list(argv)
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        del args[i:i + 2]
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet = args[i + 1]
        del args[i:i + 2]
    if '--only' in args:
        i = args.index('--only')
        only = args[i + 1:]
        args = args[:i]
    os.makedirs(out, exist_ok=True)
    jpath = os.path.join(out, 'props.json')
    if os.path.exists(jpath):
        with open(jpath) as fh:
            REGISTRY.update(json.load(fh))
    names = only or names_for(args or GROUPS)
    t0 = time.time()
    for n in names:
        build_one(n, out)
        with open(jpath, 'w') as fh:
            json.dump(dict(sorted(REGISTRY.items())), fh, ensure_ascii=False, indent=1)
    print(f'xong {len(names)} ảnh trong {time.time() - t0:.0f}s → {out}')
    if sheet:
        contact_sheet(out, sheet)
        print('bảng xem nhanh:', sheet)


if __name__ == '__main__':
    main(sys.argv[1:])
