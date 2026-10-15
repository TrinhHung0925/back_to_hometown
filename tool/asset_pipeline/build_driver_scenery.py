"""Cảnh ven đường cho góc nhìn ghế lái (giả 3D): cây cối, nhà cửa, bầu trời,
dải chân trời và cổng chào Tết.

Mọi hình đều vẽ bằng code ở đây (không cần ảnh nguồn), xuất ra
assets/images/driver/ kèm scenery.json ghi chiều cao thật (mét) của mỗi hình.

Cây cối là mô hình 3D thật dựng từng lá, từng cành rồi "chụp" thẳng ngang
(chiếu trực giao, mắt nhìn theo hướng +y):
- Khung cành mọc bằng thuật toán xâm chiếm không gian (space colonization) hoặc
  dựng tay theo dáng từng loài (bàng tầng, tre cong ngọn, dừa, chuối, phi lao,
  thông, đào, mai…); bán kính cành theo mô hình ống (pipe model).
- Lá là đa giác nhỏ trong không gian 3D, có pháp tuyến riêng; thân cành là ống
  nhiều mặt. Ánh sáng gần vật lý: nắng từ trên - bên trái - phía trước, bầu
  trời bán cầu, đất phản xạ, lá xuyên sáng khi bị chiếu sau lưng, bóng tự đổ
  và che khuất môi trường tính qua lưới mật độ lá 3D (tán dày thì trong tối).
- Vẽ đa giác xa trước gần sau (painter) ở độ phân giải gấp [SS] lần rồi thu
  nhỏ cho mép mịn. Vân vỏ cây phủ thêm theo mặt nạ vật liệu.

Nhà cửa là mặt đứng phẳng (để game dán lên tấm dọc): vẽ từng lớp có độ nhô
(bản đồ cao), rồi đổ bóng nắng / che khuất theo bản đồ cao đó nên ban công,
mái hiên, biển hiệu… có bóng đổ thật. Tường vữa loang ố, vệt nước mưa, rêu
chân tường, chữ biển hiệu tiếng Việt (font PaytoneOne / Manrope trong repo).

Quy ước ảnh đứng (billboard): điểm ảnh giữa - đáy là điểm chạm đất (gốc cây /
giữa mặt tiền nhà); [h_m] trong scenery.json là chiều cao thật của toàn ảnh.
Bầu trời 2048×512 (độ cao 0° ở đáy → ~40° ở đỉnh) và dải chân trời 2048×256
đều lặp liền mạch theo chiều ngang.

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_driver_scenery.py               # tất cả
    python tool/asset_pipeline/build_driver_scenery.py tree_broad_1  # chọn vài hình
    python tool/asset_pipeline/build_driver_scenery.py --out DIR     # xuất chỗ khác
"""
import json
import math
import multiprocessing as mp
import os
import sys
import time
import unicodedata

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'images', 'driver')
FONT_DIR = os.path.join(ROOT, 'assets', 'fonts')

# Nắng (hướng TỚI mặt trời) cho cây: x sang phải ảnh, y ra xa người nhìn, z lên.
# Trên - bên trái - hơi phía trước như mọi hình khác của game.
SUN = np.array([-0.55, -0.50, 0.67])
SUN /= np.linalg.norm(SUN)
VIEW = np.array([0.0, -1.0, 0.0])  # hướng từ vật tới mắt người nhìn
SUN_COL = np.array([1.0, 0.95, 0.86]) * 2.55
SKY_COL = np.array([0.50, 0.60, 0.80]) * 1.05
GROUND_COL = np.array([0.30, 0.30, 0.20]) * 0.55
EXPOSURE = 0.80


def lin(rgb):
    """Màu sRGB 0..255 → tuyến tính."""
    return (np.asarray(rgb, np.float64) / 255.0) ** 2.2


def tonemap(c, exposure=EXPOSURE):
    """Tuyến tính → sRGB 0..1 (đường cong kiểu phim ACES, mềm ở vùng sáng)."""
    c = np.maximum(c, 0) * exposure
    a, b, cc, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    t = np.clip((c * (a * c + b)) / (c * (cc * c + d) + e), 0, 1)
    return t ** (1 / 2.2)


def nrmz(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ================================================================ Nhiễu
def vnoise(x, y, seed=0):
    """Nhiễu giá trị mượt 2D (xác định)."""
    xi, yi = np.floor(x), np.floor(y)
    xf, yf = x - xi, y - yi

    def h(i, j):
        n = np.sin(i * 127.1 + j * 311.7 + seed * 74.7) * 43758.5453
        return n - np.floor(n)

    u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    a, b = h(xi, yi), h(xi + 1, yi)
    c, d = h(xi, yi + 1), h(xi + 1, yi + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


def vnoise3(p, seed=0):
    """Nhiễu giá trị mượt 3D cho mảng điểm (N, 3)."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    i, j, k = np.floor(x), np.floor(y), np.floor(z)
    fx, fy, fz = x - i, y - j, z - k
    ux, uy, uz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)

    def h(a, b, c):
        n = np.sin(a * 127.1 + b * 311.7 + c * 74.7 + seed * 19.3) * 43758.5453
        return n - np.floor(n)

    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (ux if dx else 1 - ux) * (uy if dy else 1 - uy) * (uz if dz else 1 - uz)
                out = out + w * h(i + dx, j + dy, k + dz)
    return out


def fbm3(p, seed=0, octaves=3):
    s, amp, tot = 0.0, 0.5, 0.0
    for o in range(octaves):
        s = s + amp * vnoise3(p * (2.03 ** o), seed + o * 7)
        tot += amp
        amp *= 0.5
    return s / tot


def fbm(x, y, seed=0, octaves=4, gain=0.5):
    s, amp, f, tot = 0.0, 0.5, 1.0, 0.0
    for i in range(octaves):
        s = s + amp * vnoise(x * f, y * f, seed + i * 13)
        tot += amp
        amp *= gain
        f *= 2.03
    return s / tot


def pnoise(h, w, sy, sx=None, seed=0):
    """Nhiễu mượt lặp liền mạch cả hai chiều (lọc Gauss trong miền tần số),
    chuẩn hoá về 0..1. [sy], [sx]: cỡ hạt (điểm ảnh)."""
    sx = sy if sx is None else sx
    r = np.random.default_rng(seed)
    white = r.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.exp(-2 * (math.pi ** 2) * ((fx * sx) ** 2 + (fy * sy) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * k))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def pfbm(h, w, base, seed=0, octaves=5, gain=0.55, sx_ratio=1.0):
    """Tổng nhiều tầng nhiễu lặp liền mạch."""
    s, amp, tot = np.zeros((h, w)), 1.0, 0.0
    for i in range(octaves):
        sz = base / (2 ** i)
        if sz < 0.5:
            break
        s += amp * (pnoise(h, w, sz, sz * sx_ratio, seed + i * 7) - 0.5)
        tot += amp
        amp *= gain
    s = s / tot
    s -= s.min()
    return s / max(s.max(), 1e-9)


def noise1d(n, scale, seed=0):
    """Nhiễu 1D lặp liền mạch (chu kỳ n mẫu), -1..1."""
    r = np.random.default_rng(seed)
    white = r.standard_normal(n)
    f = np.fft.fftfreq(n)
    k = np.exp(-2 * (math.pi * f * scale) ** 2)
    out = np.real(np.fft.ifft(np.fft.fft(white) * k))
    return out / max(np.abs(out).max(), 1e-9)


def blur(a, r):
    """Làm mờ Gauss mảng 2D bằng PIL (r: bán kính điểm ảnh)."""
    if r <= 0:
        return a
    lo, hi = float(a.min()), float(a.max())
    span = max(hi - lo, 1e-9)
    im = Image.fromarray(((a - lo) / span * 65535).astype(np.uint16).astype(np.int32), 'I').convert('F')
    out = np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float64)
    return out / 65535 * span + lo


def gblur(a, r):
    """Làm mờ Gauss chính xác (tách chiều, numpy) — dùng cho mảng float."""
    if r <= 0:
        return a
    k = int(math.ceil(r * 3))
    x = np.arange(-k, k + 1)
    w = np.exp(-0.5 * (x / r) ** 2)
    w /= w.sum()
    out = a
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (k, k)
        p = np.pad(out, pad, mode='edge')
        acc = np.zeros_like(out, dtype=np.float64)
        for i, wi in enumerate(w):
            sl = [slice(None)] * a.ndim
            sl[axis] = slice(i, i + out.shape[axis])
            acc += wi * p[tuple(sl)]
        out = acc
    return out


def gblur_wrap_x(a, r):
    """Như gblur nhưng cuộn vòng theo chiều ngang (cho ảnh lặp liền mạch)."""
    if r <= 0:
        return a
    k = int(math.ceil(r * 3))
    x = np.arange(-k, k + 1)
    w = np.exp(-0.5 * (x / r) ** 2)
    w /= w.sum()
    acc = np.zeros_like(a, dtype=np.float64)
    for i, wi in enumerate(w):
        acc += wi * np.roll(a, i - k, axis=1)
    p = np.pad(acc, [(k, k)] + [(0, 0)] * (a.ndim - 1), mode='edge')
    out = np.zeros_like(acc)
    for i, wi in enumerate(w):
        out += wi * p[i:i + a.shape[0]]
    return out


def downsample(arr, f):
    """Thu nhỏ khối f×f (trung bình). arr: (H, W, C) float."""
    h, w = arr.shape[0] // f, arr.shape[1] // f
    a = arr[:h * f, :w * f]
    return a.reshape(h, f, w, f, -1).mean(axis=(1, 3))


# ======================================================= Lưới mật độ 3D
class Volume:
    """Lưới mật độ diện tích lá (m²/m³) để tính bóng tự đổ và che khuất."""

    def __init__(self, lo, hi, vs):
        self.lo = np.asarray(lo, np.float64) - vs * 2
        self.vs = vs
        self.shape = tuple((np.ceil((np.asarray(hi) - self.lo) / vs) + 3).astype(int))
        self.d = np.zeros(self.shape)

    def splat(self, p, w):
        q = (p - self.lo) / self.vs
        i = np.clip(np.round(q).astype(int), 0, np.array(self.shape) - 1)
        np.add.at(self.d, (i[:, 0], i[:, 1], i[:, 2]), w / self.vs ** 3)

    def smooth(self, n=1):
        for _ in range(n):
            for ax in range(3):
                d = self.d
                self.d = 0.5 * d + 0.25 * (np.roll(d, 1, ax) + np.roll(d, -1, ax))

    def sample(self, p):
        q = (p - self.lo) / self.vs
        q0 = np.floor(q).astype(int)
        f = q - q0
        out = np.zeros(p.shape[0])
        sx, sy, sz = self.shape
        for dx in (0, 1):
            wx = f[:, 0] if dx else 1 - f[:, 0]
            ix = q0[:, 0] + dx
            for dy in (0, 1):
                wy = f[:, 1] if dy else 1 - f[:, 1]
                iy = q0[:, 1] + dy
                for dz in (0, 1):
                    wz = f[:, 2] if dz else 1 - f[:, 2]
                    iz = q0[:, 2] + dz
                    ok = (ix >= 0) & (ix < sx) & (iy >= 0) & (iy < sy) & (iz >= 0) & (iz < sz)
                    v = np.zeros(p.shape[0])
                    v[ok] = self.d[ix[ok], iy[ok], iz[ok]]
                    out += wx * wy * wz * v
        return out

    def optical(self, p, d, t0, tmax):
        """Độ dày quang học dọc tia p + d·t, t từ t0 đến tmax."""
        step = self.vs * 0.7
        tau = np.zeros(p.shape[0])
        t = t0
        while t < tmax:
            tau += self.sample(p + d[None, :] * t) * step
            t += step
        return tau


def hemi_dirs(n=14):
    """Các hướng nhìn lên bầu trời (xoắn Fibonacci, có cả hướng gần ngang)."""
    out = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 0.08 + 0.92 * (i + 0.5) / n
        r = math.sqrt(1 - z * z)
        out.append((math.cos(ga * i) * r, math.sin(ga * i) * r, z))
    return np.array(out)


# ============================================================ Cây 3D
MAT_LEAF, MAT_BARK, MAT_FLOWER, MAT_CULM, MAT_PLAIN, MAT_POT, MAT_STEM = 1, 2, 3, 4, 5, 6, 7

LEAF_SHAPES = {
    # (u dọc lá 0..1 từ cuống, v ngang -1..1)
    'ovate': [(0, 0), (0.12, -0.6), (0.35, -0.97), (0.62, -0.85), (0.85, -0.45), (1, 0),
              (0.85, 0.45), (0.62, 0.85), (0.35, 0.97), (0.12, 0.6)],
    'obovate': [(0, 0), (0.2, -0.45), (0.5, -0.85), (0.78, -1.0), (0.95, -0.6), (1, 0),
                (0.95, 0.6), (0.78, 1.0), (0.5, 0.85), (0.2, 0.45)],
    'lance': [(0, 0), (0.1, -0.7), (0.35, -1.0), (0.7, -0.6), (1, 0), (0.7, 0.6), (0.35, 1.0), (0.1, 0.7)],
    'round': [(math.cos(a) * 0.5 + 0.5, math.sin(a)) for a in np.linspace(0, math.tau, 9)[:-1]],
    'tri': [(0, -0.3), (1, 0), (0, 0.3)],
}


class Plant:
    """Tập đa giác 3D (lá, mặt ống thân cành) + thông số vật liệu."""

    def __init__(self):
        self.batches = []

    # -------------------------------------------------------- thêm hình
    def add_polys(self, pts, nrm, alb, mat=MAT_LEAF, alb_back=None, trans=0.0, spec=0.0, shin=20.0,
                  two_sided=True, area=None, dens=1.0, cast=True, lift=None):
        """[pts] (N, K, 3) đỉnh; [nrm] (N, 3); [alb] (N, 3) màu tuyến tính."""
        pts = np.asarray(pts, np.float64)
        n = pts.shape[0]
        if n == 0:
            return
        alb = np.broadcast_to(np.asarray(alb, np.float64), (n, 3)).copy()
        ab = alb if alb_back is None else np.broadcast_to(np.asarray(alb_back, np.float64), (n, 3)).copy()
        if area is None:
            e1 = pts[:, 1] - pts[:, 0]
            e2 = pts[:, -1] - pts[:, 0]
            area = np.linalg.norm(np.cross(e1, e2), axis=1) * 0.5 * (pts.shape[1] - 2) * 0.8
        self.batches.append(dict(pts=pts, nrm=nrmz(np.asarray(nrm, np.float64)), alb=alb, alb_back=ab,
                                 mat=np.full(n, mat), trans=np.broadcast_to(trans, (n,)).astype(np.float64),
                                 spec=np.broadcast_to(spec, (n,)).astype(np.float64), shin=shin,
                                 two=two_sided, area=np.asarray(area, np.float64) * dens if cast else np.zeros(n),
                                 lift=np.zeros(n) if lift is None else np.broadcast_to(lift, (n,)).astype(np.float64)))

    def add_leaves(self, base, axis, normal, length, width, alb, shape='ovate', bend=0.15, **kw):
        """Lá phẳng (hơi cong) gắn ở [base], dài theo [axis], mặt theo [normal]."""
        base = np.asarray(base, np.float64)
        n = base.shape[0]
        if n == 0:
            return
        axis = nrmz(np.asarray(axis, np.float64))
        normal = np.asarray(normal, np.float64)
        normal = nrmz(normal - (normal * axis).sum(1, keepdims=True) * axis)
        side = nrmz(np.cross(normal, axis))
        length = np.broadcast_to(length, (n,))[:, None, None]
        width = np.broadcast_to(width, (n,))[:, None, None]
        tpl = np.array(LEAF_SHAPES[shape] if isinstance(shape, str) else shape)
        u = tpl[None, :, 0:1]
        v = tpl[None, :, 1:2]
        # Lá cong võng: đầu lá rủ xuống theo trọng lực.
        droop = np.array([0, 0, -1.0])[None, None, :] * (bend * u * u) * length
        pts = base[:, None, :] + axis[:, None, :] * u * length + side[:, None, :] * v * width * 0.5 + droop
        self.add_polys(pts, normal, alb, **kw)

    def add_tube(self, path, radii, alb, alb_fn=None, **kw):
        """Ống thon theo đường [path] (M, 3), bán kính [radii] (M,)."""
        path = np.asarray(path, np.float64)
        radii = np.asarray(radii, np.float64)
        if len(path) < 2:
            return
        a, b = path[:-1], path[1:]
        if alb_fn is not None:
            alb = alb_fn((a + b) / 2)
        self.add_segments(a, b, radii[:-1], radii[1:], alb, **kw)

    def add_segments(self, a, b, ra, rb, alb, mat=MAT_BARK, nfac=6, spec=0.0, dens=1.0, cast=True, ext=0.5,
                     thick_cast=0.08):
        """Nhiều đoạn ống rời [a]→[b] (bán kính [ra]→[rb]). Chỉ dựng nửa mặt
        quay về phía người nhìn, chia [nfac] mặt dọc để đổ sáng."""
        a = np.asarray(a, np.float64)
        b = np.asarray(b, np.float64)
        ra = np.broadcast_to(np.asarray(ra, np.float64), (len(a),))
        rb = np.broadcast_to(np.asarray(rb, np.float64), (len(a),))
        alb = np.broadcast_to(np.asarray(alb, np.float64), (len(a), 3))
        ax = b - a
        ln = np.linalg.norm(ax, axis=1)
        keep = ln > 1e-6
        a, b, ra, rb, ax, ln, alb = a[keep], b[keep], ra[keep], rb[keep], ax[keep], ln[keep], alb[keep]
        if len(a) == 0:
            return
        A = ax / ln[:, None]
        # nối khít: kéo dài mỗi đoạn một chút về hai phía
        e = np.minimum(np.maximum(ra, rb) * ext, ln * 0.45)[:, None]
        a2, b2 = a - A * e, b + A * e
        Vp = VIEW[None, :] - (A @ VIEW)[:, None] * A
        bad = np.linalg.norm(Vp, axis=1) < 1e-4
        Vp[bad] = np.array([1.0, 0, 0])
        Vp = nrmz(Vp)
        S = np.cross(A, Vp)
        th = np.linspace(-math.pi / 2, math.pi / 2, nfac + 1)
        c0, s0 = np.cos(th[:-1]), np.sin(th[:-1])
        c1, s1 = np.cos(th[1:]), np.sin(th[1:])
        cm, sm = np.cos((th[:-1] + th[1:]) / 2), np.sin((th[:-1] + th[1:]) / 2)
        n0 = c0[None, :, None] * Vp[:, None, :] + s0[None, :, None] * S[:, None, :]
        n1 = c1[None, :, None] * Vp[:, None, :] + s1[None, :, None] * S[:, None, :]
        nm = cm[None, :, None] * Vp[:, None, :] + sm[None, :, None] * S[:, None, :]
        P = np.stack([a2[:, None, :] + ra[:, None, None] * n0, a2[:, None, :] + ra[:, None, None] * n1,
                      b2[:, None, :] + rb[:, None, None] * n1, b2[:, None, :] + rb[:, None, None] * n0], axis=2)
        m = len(a)
        P = P.reshape(m * nfac, 4, 3)
        N = nm.reshape(m * nfac, 3)
        alb = np.repeat(alb, nfac, axis=0)
        # bóng đổ: diện tích chắn sáng ~ 2·r·dài; thân to thì giảm (tránh tự che)
        rr = (ra + rb) / 2
        area = 2 * rr * ln / nfac * np.where(rr > thick_cast, 0.1, 1.0)
        area = np.repeat(area, nfac)
        self.add_polys(P, N, alb, mat=mat, two_sided=False, spec=spec, area=area, dens=dens, cast=cast)

    def add_sphere(self, centers, radii, alb, nlat=4, nlon=8, mat=MAT_PLAIN, spec=0.0, shin=20.0, squash=1.0,
                   cast=True, trans=0.0):
        """Nửa mặt cầu (phía người nhìn) chia ô, mỗi ô một pháp tuyến."""
        c = np.asarray(centers, np.float64).reshape(-1, 3)
        n = len(c)
        r = np.broadcast_to(np.asarray(radii, np.float64), (n,))
        th = np.linspace(0, math.pi / 2 * 1.02, nlat + 1)  # lệch khỏi trục nhìn
        ph = np.linspace(0, math.tau, nlon + 1)

        def dirv(t, f):
            return np.stack([np.sin(t) * np.cos(f), -np.cos(t) * np.ones_like(f), np.sin(t) * np.sin(f)], -1)

        quads, norms = [], []
        for i in range(nlat):
            for j in range(nlon):
                q = [dirv(th[i], ph[j]), dirv(th[i + 1], ph[j]), dirv(th[i + 1], ph[j + 1]), dirv(th[i], ph[j + 1])]
                quads.append(np.array(q))
                norms.append(nrmz(dirv((th[i] + th[i + 1]) / 2, (ph[j] + ph[j + 1]) / 2)))
        Q = np.array(quads)  # (F, 4, 3)
        N = np.array(norms)
        Q = Q * np.array([1, 1, squash])
        P = c[:, None, None, :] + r[:, None, None, None] * Q[None]
        NN = np.broadcast_to(N[None], (n,) + N.shape)
        alb = np.asarray(alb, np.float64)
        if alb.ndim == 1:
            alb = np.broadcast_to(alb, (n, 3))
        A = np.repeat(alb, len(Q), axis=0)
        self.add_polys(P.reshape(-1, 4, 3), NN.reshape(-1, 3), A, mat=mat, two_sided=False, spec=spec, shin=shin,
                       cast=cast, trans=trans)

    def add_lathe(self, prof, center, alb_fn, nseg=28, mat=MAT_POT, spec=0.4, shin=40.0):
        """Mặt tròn xoay quanh trục đứng (chậu cảnh): [prof] [(r, z), ...],
        [alb_fn](z, góc) → màu tuyến tính. Chỉ dựng nửa trước."""
        prof = np.asarray(prof, np.float64)
        c = np.asarray(center, np.float64)
        ang = np.linspace(math.pi, math.tau, nseg + 1)  # nửa quay về phía -y
        quads, norms, cols = [], [], []
        for i in range(len(prof) - 1):
            r0, z0 = prof[i]
            r1, z1 = prof[i + 1]
            for j in range(nseg):
                a0, a1 = ang[j], ang[j + 1]
                q = [(r0 * math.cos(a0), r0 * math.sin(a0), z0), (r1 * math.cos(a0), r1 * math.sin(a0), z1),
                     (r1 * math.cos(a1), r1 * math.sin(a1), z1), (r0 * math.cos(a1), r0 * math.sin(a1), z0)]
                am = (a0 + a1) / 2
                dz, dr = z1 - z0, r1 - r0
                nr = np.array([dz * math.cos(am), dz * math.sin(am), -dr])
                quads.append(q)
                norms.append(nr / max(np.linalg.norm(nr), 1e-9))
                cols.append(alb_fn((z0 + z1) / 2, am))
        Q = np.array(quads) + c[None, None, :]
        self.add_polys(Q, np.array(norms), np.array(cols), mat=mat, two_sided=False, spec=spec, shin=shin)

    def add_flowers(self, centers, normals, radius, petal_alb, eye_alb, petals=5, mat=MAT_FLOWER, trans=0.5,
                    cup=0.25, rng=None):
        """Hoa 5 cánh: đa giác hình hoa (mép lượn theo cánh) + nhuỵ ở giữa."""
        rng = rng or np.random.default_rng(0)
        c = np.asarray(centers, np.float64)
        n = len(c)
        if n == 0:
            return
        nr = nrmz(np.asarray(normals, np.float64))
        t1 = nrmz(np.cross(nr, rng.normal(size=(n, 3))))
        t2 = np.cross(nr, t1)
        k = 20
        a = np.linspace(0, math.tau, k, endpoint=False)
        rad = 0.55 + 0.45 * np.abs(np.cos(a * petals / 2)) ** 0.7
        r = np.broadcast_to(np.asarray(radius, np.float64), (n,))[:, None, None]
        pts = c[:, None, :] + r * (np.cos(a)[None, :, None] * rad[None, :, None] * t1[:, None, :] +
                                   np.sin(a)[None, :, None] * rad[None, :, None] * t2[:, None, :]) + \
            nr[:, None, :] * r * cup * rad[None, :, None] ** 2
        self.add_polys(pts, nr, petal_alb, mat=mat, trans=trans, alb_back=petal_alb, spec=0.05)
        a2 = np.linspace(0, math.tau, 7, endpoint=False)
        eye = c[:, None, :] + r * 0.28 * (np.cos(a2)[None, :, None] * t1[:, None, :] + np.sin(a2)[None, :, None] *
                                          t2[:, None, :]) + nr[:, None, :] * r * 0.12
        self.add_polys(eye, nr, eye_alb, mat=mat, trans=0.2, lift=np.full(n, 0.004), cast=False)

    def prune(self, rng, lo=0.12, hi=0.4, vs=0.25, k=0.5, mats=(MAT_LEAF,)):
        """Tỉa lá nằm sâu trong tán (thiếu sáng thì rụng như cây thật): tán
        rỗng ruột, lá dày ở vỏ ngoài, nhìn xuyên vào thấy cành."""
        sel = [b for b in self.batches if b['mat'][0] in mats]
        if not sel:
            return
        cen = np.concatenate([b['pts'].mean(axis=1) for b in sel])
        area = np.concatenate([b['area'] for b in sel])
        vol = Volume(cen.min(axis=0) - vs, cen.max(axis=0) + vs, vs)
        vol.splat(cen, area)
        vol.smooth(1)
        span = float(np.linalg.norm(cen.max(axis=0) - cen.min(axis=0)))
        dirs = np.concatenate([hemi_dirs(8), [[0, 0, -1.0], [1, 0, -0.3], [-1, 0, -0.3], [0, 1, -0.3], [0, -1, -0.3]]])
        expo = np.zeros(len(cen))
        for d in dirs:
            d = d / np.linalg.norm(d)
            expo += np.exp(-k * vol.optical(cen, d, vs, span))
        expo /= len(dirs)
        keep_p = smoothstep(lo, hi, expo)
        keep = rng.uniform(0, 1, len(cen)) < keep_p
        i = 0
        for b in sel:
            n = len(b['pts'])
            kb = keep[i:i + n]
            i += n
            for key in ('pts', 'nrm', 'alb', 'alb_back', 'mat', 'trans', 'spec', 'area', 'lift'):
                b[key] = b[key][kb]
        self.batches = [b for b in self.batches if len(b['pts'])]

    # ----------------------------------------------------------- dựng ảnh
    def render(self, target_px, ss=3, vs=0.22, k_shadow=0.8, k_sky=0.6, sky_dirs=14, bark_tex=None,
               crop_pad=2, light_scale=1.0, height_px=None, min_half_w=None, ground_occ=0.35, sun_col=None):
        B = self.batches
        pts = np.concatenate([b['pts'].reshape(-1, 3) for b in B])
        z_top = pts[:, 2].max()
        x_ext = np.abs(pts[:, 0]).max()
        if min_half_w:
            x_ext = max(x_ext, min_half_w)
        ppm = target_px / z_top
        H = target_px
        W = int(math.ceil(x_ext * ppm)) * 2 + crop_pad * 2
        # ---- gộp
        cen = np.concatenate([b['pts'].mean(axis=1) for b in B])
        nrm = np.concatenate([b['nrm'] for b in B])
        alb = np.concatenate([b['alb'] for b in B])
        albb = np.concatenate([b['alb_back'] for b in B])
        mat = np.concatenate([b['mat'] for b in B])
        trans = np.concatenate([b['trans'] for b in B])
        spec = np.concatenate([b['spec'] for b in B])
        shin = np.concatenate([np.full(len(b['pts']), b['shin']) for b in B])
        two = np.concatenate([np.full(len(b['pts']), b['two']) for b in B])
        area = np.concatenate([b['area'] for b in B])
        # ---- lưới mật độ
        lo = cen.min(axis=0) - vs
        hi = cen.max(axis=0) + vs
        vol = Volume(lo, hi, vs)
        vol.splat(cen, area)
        vol.smooth(1)
        span = float(np.linalg.norm(hi - lo))
        # ---- pháp tuyến hai mặt: lật về phía người nhìn
        ndv = nrm @ VIEW
        flip = two & (ndv < 0)
        n_eff = np.where(flip[:, None], -nrm, nrm)
        alb_eff = np.where(flip[:, None], albb, alb)
        # ---- bóng nắng
        start = vs * 0.9
        tau_sun = vol.optical(cen, SUN, start, span)
        t_sun = np.exp(-k_shadow * tau_sun)
        # ---- bầu trời nhìn thấy
        dirs = hemi_dirs(sky_dirs)
        sky = np.zeros(len(cen))
        wsum = 0
        for d in dirs:
            w = 0.3 + d[2]
            sky += w * np.exp(-k_sky * vol.optical(cen, d, start, span * 0.7))
            wsum += w
        sky /= wsum
        # mặt đất che bớt phần trời ở gần gốc
        sky *= 1 - ground_occ * np.exp(-np.maximum(cen[:, 2], 0) / 1.2)
        gvis = np.exp(-k_sky * vol.optical(cen, np.array([0, 0, -1.0]), start, max(1.0, span * 0.5)))
        # ---- đổ sáng
        sc = SUN_COL * light_scale if sun_col is None else np.asarray(sun_col)
        ndl = n_eff @ SUN
        front = np.clip(ndl, 0, 1)
        back = np.clip(-ndl, 0, 1) * trans
        direct = (front + back)[:, None] * sc[None, :] * t_sun[:, None]
        nz = n_eff[:, 2]
        amb = SKY_COL[None, :] * (sky * (0.62 + 0.38 * nz))[:, None] + \
            GROUND_COL[None, :] * (gvis * (0.55 - 0.45 * nz) * (0.4 + 0.6 * sky))[:, None]
        # lá bị chiếu sau lưng ánh lên màu vàng xanh (ánh xuyên lá)
        tint_back = np.where((back > 0)[:, None], np.array([1.05, 1.1, 0.55])[None, :], 1.0)
        # ống (thân cành): mép ngoài tối hơn giữa → đọc ra khối tròn
        amb = amb * np.where(two, 1.0, 0.5 + 0.5 * np.clip(n_eff @ VIEW, 0, 1))[:, None]
        col = alb_eff * (direct * tint_back + amb)
        hv = nrmz(SUN + VIEW)
        ndh = np.clip(n_eff @ hv, 0, 1)
        col += (spec * ndh ** shin * t_sun * np.clip(ndl, 0, 1))[:, None] * sc[None, :] * 0.6
        rgb = tonemap(col)
        rgb8 = np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8)
        # ---- chiếu lên ảnh
        S = ppm * ss
        ox = W * ss / 2
        polys2 = []
        depth = []
        for b in B:
            p = b['pts']
            xy = np.empty(p.shape[:2] + (2,))
            xy[..., 0] = ox + p[..., 0] * S
            xy[..., 1] = (z_top - p[..., 2]) * S
            polys2.append(xy)
            depth.append(p[..., 1].mean(axis=1) - b['lift'])
        depth = np.concatenate(depth)
        order = np.argsort(-depth, kind='stable')
        flat = []
        for xy in polys2:
            flat.extend(xy.reshape(len(xy), -1).tolist())
        img = Image.new('RGBA', (W * ss, H * ss), (0, 0, 0, 0))
        mimg = Image.new('L', (W * ss, H * ss), 0)
        dr = ImageDraw.Draw(img)
        dm = ImageDraw.Draw(mimg)
        cols = [tuple(c) + (255,) for c in rgb8.tolist()]
        matl = mat.tolist()
        for i in order.tolist():
            dr.polygon(flat[i], fill=cols[i])
            dm.polygon(flat[i], fill=matl[i])
        a = np.asarray(img, np.float64) / 255.0
        m = np.asarray(mimg)
        if bark_tex:
            # vỏ cây: xoá vết mặt cắt (làm mờ trong mặt nạ) rồi phủ vân theo mét
            hh, ww = m.shape
            for mid, fn in bark_tex.items():
                sel = m == mid
                if not sel.any():
                    continue
                msk = sel.astype(np.float64)
                rad = 1.2 * ss
                num = np.stack([gblur(a[..., c] * msk, rad) for c in range(3)], -1)
                den = gblur(msk, rad)[..., None]
                sm = num / np.maximum(den, 1e-6)
                yy, xx = np.nonzero(sel)
                tex = fn((xx - ox) / S, (hh - yy) / S)
                a[yy, xx, :3] = np.clip(sm[yy, xx] * tex[:, None], 0, 1)
        prem = a.copy()
        prem[..., :3] *= prem[..., 3:4]
        small = downsample(prem, ss)
        al = small[..., 3:4]
        rgbo = np.where(al > 1e-4, small[..., :3] / np.maximum(al, 1e-4), 0)
        out = np.concatenate([rgbo, al], axis=2)
        out8 = np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)
        im = Image.fromarray(out8, 'RGBA')
        return im, z_top


def bark_texture(xm, zm, seed=0, scale=1.0, fissure=0.55, flake=0.25):
    """Vân vỏ cây (theo mét): rãnh nứt dọc, mảng vảy bong, đốm địa y."""
    n1 = fbm(xm * 14 * scale, zm * 2.2 * scale, seed=seed, octaves=4)
    n2 = fbm(xm * 6 * scale + 7, zm * 5 * scale, seed=seed + 5, octaves=3)
    n3 = fbm(xm * 30 * scale, zm * 9 * scale, seed=seed + 9, octaves=2)
    ridge = 1 - np.abs(n1 - 0.5) * 2
    crack = smoothstep(0.78, 0.95, ridge)
    lichen = smoothstep(0.6, 0.75, n2)
    return (1.0 - fissure * crack) * (1 + flake * (n2 - 0.5) * 1.5) * (0.9 + 0.2 * n3) * (1 + 0.12 * lichen)


# ------------------------------------------------------- Khung cành
class Skeleton:
    """Cây cành: các nút (vị trí, cha). Mọc bằng xâm chiếm không gian."""

    def __init__(self, trunk_pts):
        self.pos = [np.asarray(p, np.float64) for p in trunk_pts]
        self.parent = [-1] + list(range(len(trunk_pts) - 1))
        self.fixed = set(range(len(trunk_pts)))

    def add_path(self, pts, parent):
        """Thêm một nhánh dựng tay (thân phụ) mọc từ nút [parent]."""
        idx = []
        for p in pts:
            self.pos.append(np.asarray(p, np.float64))
            self.parent.append(parent)
            parent = len(self.pos) - 1
            idx.append(parent)
            self.fixed.add(parent)
        return idx

    def grow(self, attractors, step=0.22, infl=1.6, kill=0.45, iters=120, tropism=(0, 0, 0.0),
             min_z=0.0, rng=None, jitter=0.15):
        rng = rng or np.random.default_rng(0)
        A = np.asarray(attractors, np.float64)
        alive = np.ones(len(A), bool)
        P = np.array(self.pos)
        best_d = np.full(len(A), np.inf)
        best_i = np.full(len(A), -1)
        # chỉ nút cao hơn min_z được mọc cành
        eligible = P[:, 2] >= min_z
        idx_all = np.arange(len(P))

        def update(new_idx):
            cand = new_idx[eligible_arr[new_idx]] if len(new_idx) else new_idx
            if len(cand) == 0:
                return
            Q = P_arr[cand]
            for s in range(0, len(cand), 512):
                q = Q[s:s + 512]
                d = np.linalg.norm(A[:, None, :] - q[None, :, :], axis=2)
                j = np.argmin(d, axis=1)
                dj = d[np.arange(len(A)), j]
                better = dj < best_d
                best_d[better] = dj[better]
                best_i[better] = cand[s:s + 512][j[better]]

        P_arr = P
        eligible_arr = eligible
        update(idx_all)
        trop = np.asarray(tropism, np.float64)
        for _ in range(iters):
            act = alive & (best_d < infl)
            if not act.any():
                break
            nodes = best_i[act]
            dirs = nrmz(A[act] - P_arr[nodes])
            uniq, inv = np.unique(nodes, return_inverse=True)
            acc = np.zeros((len(uniq), 3))
            np.add.at(acc, inv, dirs)
            acc = nrmz(nrmz(acc) + trop[None, :] + rng.normal(0, jitter, acc.shape))
            newp = P_arr[uniq] + acc * step
            start = len(P_arr)
            P_arr = np.concatenate([P_arr, newp])
            eligible_arr = np.concatenate([eligible_arr, np.ones(len(newp), bool)])
            self.parent.extend(uniq.tolist())
            new_idx = np.arange(start, len(P_arr))
            # loại điểm hút đã bị cành chạm tới
            for s in range(0, len(newp), 512):
                q = newp[s:s + 512]
                d = np.linalg.norm(A[:, None, :] - q[None, :, :], axis=2).min(axis=1)
                alive &= d > kill
            best_d[~alive] = np.inf
            update(new_idx)
        self.pos = list(P_arr)
        return self

    def finalize(self, tip_r=0.012, exp=2.4, smooth=2, trunk_n=0, root_r=None, gamma=1.0):
        P = np.array(self.pos)
        par = np.array(self.parent)
        n = len(P)
        kids = [[] for _ in range(n)]
        for i in range(1, n):
            kids[par[i]].append(i)
        # làm mượt đường cành (giữ gốc thân)
        for _ in range(smooth):
            Q = P.copy()
            for i in range(1, n):
                if i < trunk_n or i in self.fixed:
                    continue
                if kids[i]:
                    c = np.mean([P[k] for k in kids[i]], axis=0)
                    Q[i] = 0.5 * P[i] + 0.25 * P[par[i]] + 0.25 * c
            P = Q
        r = np.zeros(n)
        for i in range(n - 1, -1, -1):
            if not kids[i]:
                r[i] = tip_r
            else:
                r[i] = (sum(r[k] ** exp for k in kids[i])) ** (1 / exp)
        if root_r is not None:
            # đặt lại cỡ gốc thân, giữ cỡ ngọn: nội suy theo luỹ thừa [gamma]
            t = np.clip((r - tip_r) / max(r[0] - tip_r, 1e-9), 0, 1) ** gamma
            r = tip_r + t * (root_r - tip_r)
        self.P, self.par, self.kids, self.r = P, par, kids, r
        return self

    def chains(self):
        """Tách cây thành các chuỗi nút liên tục (mỗi chuỗi một ống)."""
        out = []
        par, kids, r = self.par, self.kids, self.r
        stack = [0]
        while stack:
            s = stack.pop()
            chain = [s] if par[s] < 0 else [par[s], s]
            cur = s
            while kids[cur]:
                ks = sorted(kids[cur], key=lambda k: -r[k])
                for k in ks[1:]:
                    stack.append(k)
                cur = ks[0]
                chain.append(cur)
            out.append(chain)
        return out

    def tips(self):
        return [i for i in range(len(self.P)) if not self.kids[i]]


def add_skeleton(plant, sk, bark_alb, min_r=0.0, nfac_big=10, rmul=1.0, whitewash=0.0, flare=0.5,
                 flare_h=0.35, mat=MAT_BARK):
    """Thêm toàn bộ cành của [sk] vào [plant] thành ống. Gốc thân loe ra
    ([flare]); [whitewash] > 0: quét vôi trắng gốc cây (cây ven quốc lộ)."""
    for ch in sk.chains():
        pts = sk.P[ch]
        rad = sk.r[ch] * rmul
        if rad.max() < min_r:
            continue
        if rad.max() > 0.05 and len(pts) > 1:
            # chia nhỏ đoạn thân to cho bóng đổ mượt
            seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
            cum = np.concatenate([[0], np.cumsum(seg)])
            tt = np.linspace(0, cum[-1], max(2, int(cum[-1] / 0.08) + 1))
            pts = np.stack([np.interp(tt, cum, pts[:, k]) for k in range(3)], 1)
            rad = np.interp(tt, cum, rad)
        if ch[0] == 0 and flare > 0:
            rad = rad * (1 + flare * np.exp(-np.maximum(pts[:, 2], 0) / flare_h))
        nf = nfac_big if rad.max() > 0.08 else (6 if rad.max() > 0.025 else 3)
        if whitewash > 0 and ch[0] == 0:
            def fn(mid, ww=whitewash):
                wv = smoothstep(ww + 0.03, ww - 0.03, mid[:, 2])[:, None]
                return lin((206, 204, 192))[None, :] * wv + bark_alb[None, :] * (1 - wv)
            plant.add_tube(pts, rad, bark_alb, nfac=nf, alb_fn=fn, mat=mat)
        else:
            plant.add_tube(pts, rad, bark_alb, nfac=nf, mat=mat)


def twigs(plant, rng, sk, per_tip, length, bark_alb, r0=0.010, up=0.15, droop=0.12, spread=0.8,
          nodes=None):
    """Cành con li ti mọc ra ở mỗi ngọn (2 đoạn, hơi rủ). Trả về điểm gắn
    lá dọc theo các cành con đó."""
    ids = sk.tips() if nodes is None else nodes
    n = len(ids) * per_tip
    if n == 0:
        return np.zeros((0, 3)), np.zeros((0, 3))
    p0 = np.repeat(sk.P[ids], per_tip, axis=0)
    d0 = np.repeat(nrmz(sk.P[ids] - sk.P[sk.par[ids]]), per_tip, axis=0)
    d = nrmz(d0 + rng.normal(0, spread, (n, 3)) + np.array([0, 0, up]))
    L = length * rng.uniform(0.55, 1.25, (n, 1))
    p1 = p0 + d * L * 0.55
    p2 = p0 + d * L + np.array([0, 0, -droop]) * L
    plant.add_segments(np.concatenate([p0, p1]), np.concatenate([p1, p2]),
                       np.concatenate([np.full(n, r0), np.full(n, r0 * 0.7)]),
                       np.concatenate([np.full(n, r0 * 0.7), np.full(n, r0 * 0.35)]), bark_alb, nfac=2)
    t = rng.uniform(0.2, 1.0, (n, 1))
    pts = np.where(t < 0.55, p0 + (p1 - p0) * (t / 0.55), p1 + (p2 - p1) * ((t - 0.55) / 0.45))
    return pts, d


def ellipsoid_points(rng, n, center, radii, noise=0.0, seed=0, flatten_bottom=None):
    """Điểm ngẫu nhiên trong elipxôit (có mép gồ ghề theo nhiễu)."""
    pts = []
    c = np.asarray(center, np.float64)
    r = np.asarray(radii, np.float64)
    while sum(len(p) for p in pts) < n:
        q = rng.uniform(-1, 1, (n * 2, 3))
        d = np.linalg.norm(q, axis=1)
        lim = 1.0
        if noise > 0:
            ang = np.arctan2(q[:, 1], q[:, 0])
            el = q[:, 2] / np.maximum(d, 1e-6)
            lim = 1 - noise * fbm(ang * 1.5 + 5, el * 2.0 + 3, seed=seed, octaves=3)
        ok = d < lim
        if flatten_bottom is not None:
            ok &= q[:, 2] > flatten_bottom
        pts.append(c + q[ok] * r)
    return np.concatenate(pts)[:n]


def leaf_cloud(plant, rng, anchors, per, radius, length, width, alb_fn, shape='ovate', out_bias=0.6,
               up_bias=0.5, center=None, bend=0.2, trans=0.35, spec=0.15, shin=16, alb_back_mul=(1.15, 1.12, 0.95),
               size_jit=0.25, droop=0.0, clump=0.0, clump_lo=0.35, clump_hi=0.6, seed=0):
    """Đám lá quanh các nút [anchors]: mỗi nút [per] lá trong bán kính [radius].
    [clump] > 0: tần số nhiễu 3D gom lá thành từng chòm (chỗ dày, chỗ thưa)."""
    anchors = np.asarray(anchors, np.float64)
    if clump > 0 and len(anchors):
        w = smoothstep(clump_lo, clump_hi, fbm3(anchors * clump, seed=seed))
        anchors = anchors[rng.uniform(0, 1, len(anchors)) < w * 0.7 + 0.3]
    n = len(anchors) * per
    if n == 0:
        return
    base = np.repeat(anchors, per, axis=0) + nrmz(rng.normal(size=(n, 3))) * \
        (radius * rng.uniform(0.0, 1.0, (n, 1)) ** 0.6)
    if center is None:
        center = anchors.mean(axis=0)
    out = nrmz(base - np.asarray(center)[None, :])
    axis = nrmz(rng.normal(size=(n, 3)) + out * out_bias + np.array([0, 0, -droop]))
    normal = nrmz(rng.normal(size=(n, 3)) * 0.8 + np.array([0, 0, up_bias]) + out * 0.4)
    s = 1 + rng.uniform(-size_jit, size_jit, n)
    alb = alb_fn(base, rng)
    plant.add_leaves(base, axis, normal, length * s, width * s, alb, shape=shape, bend=bend,
                     alb_back=alb * np.array(alb_back_mul)[None, :], trans=trans, spec=spec, shin=shin)


def jitter_colors(rng, n, base_rgb, h=0.06, v=0.18):
    """Màu lá dao động quanh [base_rgb] (sRGB) → tuyến tính (n, 3)."""
    base = lin(base_rgb)
    t = rng.normal(0, 1, (n, 1))
    hue = np.array([1 - h, 1 + h * 0.4, 1 + h]) ** t
    val = np.exp(rng.normal(0, v, (n, 1)))
    return np.clip(base[None, :] * hue * val, 0, 1)


# ============================================================ Các loài cây
def bark_fn(seed=0, scale=1.0, fissure=0.55, flake=0.25):
    return lambda x, z: bark_texture(x, z, seed=seed, scale=scale, fissure=fissure, flake=flake)


def tilt_path(zs, lean=(0.0, 0.0), wobble=0.08, seed=0, curve=1.0):
    """Đường thân cây: nghiêng dần theo [lean] (m lệch ở ngọn), lượn nhẹ."""
    zs = np.asarray(zs, np.float64)
    t = zs / max(zs[-1], 1e-6)
    wx = wobble * (fbm(zs * 0.6, np.full_like(zs, 1.7), seed=seed, octaves=3) - 0.5) * 2
    wy = wobble * (fbm(zs * 0.6, np.full_like(zs, 5.3), seed=seed + 3, octaves=3) - 0.5) * 2
    return np.stack([lean[0] * t ** curve + wx * t, lean[1] * t ** curve + wy * t, zs], 1)


def broad_tree(seed, trunk_h, crown, n_attr, root_r, bark_rgb, leaf_rgb, leaf_len, leaf_w, shape='ovate',
               leaves_per=22, twig_n=5, twig_len=0.5, whitewash=0.0, lean=(0.1, 0.05), stems=None,
               min_z=None, step=0.22, kill=0.35, gamma=1.3, tropism=0.12, clump=0.5, red_frac=0.0,
               leaf_h=0.08, leaf_v=0.22, trans=0.4, spec=0.22, prune=(0.02, 0.15), up_bias=0.5,
               droop=0.0, leaf_rad=0.16, flare=0.5, top_light=0.2):
    """Cây tán lá rộng mọc bằng xâm chiếm không gian. [crown]: danh sách
    (tâm, bán kính) các khối elipxôit gộp lại làm dáng tán. [stems]: các
    thân phụ dựng tay [(điểm tách, điểm ngọn)] cho cây nhiều thân."""
    rng = np.random.default_rng(seed)
    p = Plant()
    zs = np.arange(0, trunk_h + 1e-6, 0.2)
    trunk = tilt_path(zs, lean, seed=seed)
    sk = Skeleton(trunk)
    if stems:
        for (k, tip) in stems:
            j = int(np.argmin(np.abs(zs - k)))
            a = trunk[j]
            tip = np.asarray(tip, np.float64)
            m = max(3, int(np.linalg.norm(tip - a) / 0.2))
            tt = np.linspace(0, 1, m + 1)[1:]
            mid = a + (tip - a) * 0.5 + np.array([0, 0, 0.15 * np.linalg.norm(tip - a)])
            path = ((1 - tt) ** 2)[:, None] * a + (2 * tt * (1 - tt))[:, None] * mid + (tt ** 2)[:, None] * tip
            sk.add_path(path, j)
    A = np.concatenate([ellipsoid_points(rng, n, c, r, noise=0.3, seed=seed + i)
                        for i, (c, r, n) in enumerate(crown)])
    sk.grow(A, step=step, infl=1.8, kill=kill, iters=180, tropism=(0, 0, tropism),
            min_z=trunk_h * 0.8 if min_z is None else min_z, rng=rng)
    sk.finalize(tip_r=0.011, exp=2.3, trunk_n=len(trunk), root_r=root_r, gamma=gamma)
    bark = lin(bark_rgb)
    add_skeleton(p, sk, bark, whitewash=whitewash, flare=flare)
    tw, _ = twigs(p, rng, sk, twig_n, twig_len, bark * 1.1)
    zc = np.mean([c[2] for c, _, _ in crown])
    ztop = max(c[2] + r[2] for c, r, _ in crown)

    def col(base, rng):
        c = jitter_colors(rng, len(base), leaf_rgb, h=leaf_h, v=leaf_v)
        top = smoothstep(zc, ztop, base[:, 2])[:, None]
        c = c * (1 + top_light * top)
        if red_frac > 0:
            # bàng trước Tết: lá già chuyển đỏ cam, vàng
            pick = rng.uniform(0, 1, len(base)) < red_frac
            reds = np.array([lin((150, 42, 24)), lin((176, 72, 26)), lin((196, 120, 36)), lin((168, 150, 52))])
            c[pick] = reds[rng.integers(0, 4, pick.sum())] * np.exp(rng.normal(0, 0.15, (pick.sum(), 1)))
        return c

    cx = np.mean([c for c, _, _ in crown], axis=0)
    leaf_cloud(p, rng, tw, leaves_per, leaf_rad, leaf_len, leaf_w, col, shape=shape, center=cx, trans=trans,
               spec=spec, clump=clump, clump_lo=0.3, clump_hi=0.55, up_bias=up_bias, droop=droop, seed=seed)
    p.prune(rng, lo=prune[0], hi=prune[1])
    return p


def tree_xacu(seed=3):
    """Xà cừ: thân cao thẳng, vỏ xám nâu bong vảy, tán to dày xanh sẫm,
    gốc quét vôi trắng như cây ven quốc lộ."""
    rng = np.random.default_rng(seed + 100)
    crown = [((0, 0, 8.6), (4.4, 3.8, 2.8), 3000)]
    for k in range(7):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(1.5, 3.2)
        crown.append(((math.cos(a) * r, math.sin(a) * r * 0.8, rng.uniform(7.0, 10.0)),
                      tuple(rng.uniform(1.4, 2.2, 3)), 450))
    p = broad_tree(seed, 4.6, crown, 0, 0.34, (98, 90, 80), (50, 74, 36), 0.13, 0.06, whitewash=1.1,
                   min_z=3.0, twig_n=5)
    return p, dict(bark_tex={MAT_BARK: bark_fn(seed)})


def tree_sau(seed=11):
    """Sấu: tán tròn rậm như cái nấm, lá xanh bóng, thân xám sáng có bạnh
    gốc, quét vôi trắng."""
    rng = np.random.default_rng(seed + 100)
    crown = [((0, 0, 6.9), (4.2, 3.9, 2.9), 3200)]
    for k in range(8):
        a = rng.uniform(0, math.tau)
        crown.append(((math.cos(a) * 2.6, math.sin(a) * 2.2, rng.uniform(6.0, 8.3)),
                      tuple(rng.uniform(1.4, 2.0, 3)), 380))
    p = broad_tree(seed, 3.4, crown, 0, 0.30, (120, 116, 106), (44, 78, 34), 0.15, 0.065, whitewash=0.9,
                   min_z=2.4, twig_n=5, leaves_per=24, clump=0.45, flare=0.8, lean=(-0.15, 0.05),
                   leaf_h=0.06, spec=0.35)
    return p, dict(bark_tex={MAT_BARK: bark_fn(seed, scale=0.8, fissure=0.35, flake=0.4)})


def tree_keo(seed=21):
    """Keo lá tràm: nhiều thân tách thấp, tán thưa lổn nhổn, lá lưỡi liềm
    xanh xám ô liu — loại cây trồng dọc đường đèo, đồi."""
    rng = np.random.default_rng(seed + 100)
    stems = [(0.9, (-1.3, 0.3, 4.2)), (1.2, (1.4, -0.2, 4.8))]
    crown = [((-1.6, 0.2, 5.6), (2.3, 2.0, 1.8), 900), ((1.6, 0, 6.4), (2.4, 2.2, 1.8), 1000),
             ((0.2, 0.3, 7.0), (2.0, 2.0, 1.2), 500)]
    for k in range(6):
        a = rng.uniform(0, math.tau)
        crown.append(((math.cos(a) * 2.4, math.sin(a) * 1.8, rng.uniform(5.0, 7.0)),
                      tuple(rng.uniform(0.9, 1.5, 3)), 220))
    p = broad_tree(seed, 3.0, crown, 0, 0.22, (104, 96, 86), (62, 82, 42), 0.13, 0.03, shape='lance',
                   stems=stems, min_z=2.6, twig_n=6, leaves_per=40, clump=0.6, leaf_h=0.1, leaf_v=0.22,
                   lean=(0.3, 0.1), spec=0.12, droop=0.3, up_bias=0.3, kill=0.38, gamma=1.15, prune=(0.0, 0.06),
                   leaf_rad=0.22)
    return p, dict(bark_tex={MAT_BARK: bark_fn(seed, scale=1.3, fissure=0.45)})


def tree_bang(seed=31):
    """Bàng: thân thẳng, cành mọc tầng nằm ngang như mái chùa, lá to mọc
    thành hoa thị ở đầu cành; tháng Tết lá già đỏ cam lẫn xanh."""
    rng = np.random.default_rng(seed)
    p = Plant()
    top = 8.4
    zs = np.arange(0, top + 1e-6, 0.12)
    trunk = tilt_path(zs, (0.12, 0.05), wobble=0.06, seed=seed)
    tr = 0.28 * (1 - 0.8 * zs / top) + 0.03
    bark = lin((118, 112, 104))
    p.add_tube(trunk, tr * (1 + 0.5 * np.exp(-zs / 0.3)), bark, nfac=12)
    tiers = list(np.linspace(2.9, 7.4, 6) + rng.normal(0, 0.12, 6)) + [7.9]
    rosettes = []
    reds = [lin((150, 40, 24)), lin((178, 70, 26)), lin((198, 118, 36)), lin((150, 140, 50))]
    for ti, h in enumerate(tiers):
        nb = int(rng.integers(4, 6))
        a0 = rng.uniform(0, math.tau)
        j = int(np.argmin(np.abs(zs - h)))
        base = trunk[j]
        for b in range(nb):
            az = a0 + b * math.tau / nb + rng.normal(0, 0.25)
            L = np.interp(h, [tiers[0], tiers[-2], tiers[-1]], [4.4, 2.9, 1.2]) * rng.uniform(0.75, 1.15)
            el = math.radians(rng.uniform(10, 22))
            d = np.array([math.cos(az), math.sin(az), 0])
            s = np.linspace(0, L, max(4, int(L / 0.15)))
            path = base[None, :] + d[None, :] * s[:, None]
            # gốc cành vểnh lên rồi duỗi ngang ra ngọn
            path[:, 2] += np.tan(el) * L * 0.6 * (1 - np.exp(-s / (0.35 * L))) + 0.05 * s
            path[:, :2] += np.array([-d[1], d[0]])[None, :] * (0.15 * np.sin(s * 1.3 + az) * s / L)[:, None]
            r = np.interp(s, [0, L], [0.075 * (L / 4) ** 0.8 + 0.02, 0.012])
            p.add_tube(path, r, bark * 1.05, nfac=5)
            # cành con nằm ngang hai bên (rẽ tiếp một lần), hoa thị lá ở đầu
            ends = [path[-1], path[int(len(path) * 0.75)]]
            side = 1 if rng.uniform() < 0.5 else -1
            for sv in np.arange(0.22 * L, L - 0.08, 0.26):
                side = -side
                q0 = path[min(int(np.searchsorted(s, sv)), len(path) - 1)]
                dd = nrmz(d + np.array([-d[1], d[0], 0]) * side * rng.uniform(0.7, 1.5) +
                          np.array([0, 0, rng.uniform(0.0, 0.3)]))
                ln = rng.uniform(0.5, 1.2) * (1.15 - 0.4 * sv / L)
                q1 = q0 + dd * ln
                p.add_segments([q0], [q1], 0.022, 0.008, bark * 1.1, nfac=3)
                ends.extend([q1, q0 + dd * ln * 0.55])
                for _ in range(int(rng.integers(1, 3))):
                    dd2 = nrmz(dd + np.array([-dd[1], dd[0], 0]) * rng.choice([-1, 1]) * rng.uniform(0.6, 1.2) +
                               np.array([0, 0, 0.15]))
                    q_a = q0 + dd * ln * rng.uniform(0.3, 0.7)
                    q2 = q_a + dd2 * rng.uniform(0.3, 0.6)
                    p.add_segments([q_a], [q2], 0.012, 0.005, bark * 1.1, nfac=2)
                    ends.append(q2)
            rosettes.extend(ends)
    rosettes = np.array(rosettes)
    # hoa thị: 9..14 lá to xoè quanh đầu cành, gần như nằm ngang
    lb, la, ln_, cols = [], [], [], []
    for q in rosettes:
        k = int(rng.integers(10, 16))
        a0 = rng.uniform(0, math.tau)
        red_tip = rng.uniform() < 0.18
        for i in range(k):
            az = a0 + i * math.tau / k + rng.normal(0, 0.2)
            up = rng.uniform(0.1, 0.8)
            ax = np.array([math.cos(az), math.sin(az), up])
            lb.append(q + np.array([0, 0, 0.02]) + ax * 0.03)
            la.append(ax)
            ln_.append(np.array([-math.cos(az) * up, -math.sin(az) * up, 1.0]) + rng.normal(0, 0.25, 3))
            if red_tip and rng.uniform() < 0.5 or rng.uniform() < 0.06:
                cols.append(reds[int(rng.integers(0, 4))] * math.exp(rng.normal(0, 0.15)))
            else:
                cols.append(lin((58, 94, 38)) * np.exp(rng.normal(0, 0.18)) * np.array([1, 1 + rng.normal(0, 0.05), 1]))
    lb, la, ln_, cols = np.array(lb), np.array(la), np.array(ln_), np.array(cols)
    sz = rng.uniform(0.75, 1.15, len(lb))
    p.add_leaves(lb, la, ln_, 0.27 * sz, 0.15 * sz, cols, shape='obovate', bend=0.18,
                 alb_back=cols * np.array([1.2, 1.15, 0.95]), trans=0.35, spec=0.45, shin=24)
    return p, dict(bark_tex={MAT_BARK: bark_fn(seed, scale=1.1, fissure=0.4)})


def strips(plant, rng, base, dirs, length, width, alb, droop=0.2, nseg=4, side=None, taper=1.0, **kw):
    """Lá dài mảnh (lá tre, lá dừa, cỏ, lá kim): mỗi lá một đa giác cong võng."""
    base = np.asarray(base, np.float64)
    n = len(base)
    if n == 0:
        return
    d = nrmz(np.asarray(dirs, np.float64))
    if side is None:
        side = nrmz(np.cross(d, rng.normal(size=(n, 3))))
    side = nrmz(side - (side * d).sum(1, keepdims=True) * d)
    L = np.broadcast_to(np.asarray(length, np.float64), (n,))[:, None, None]
    W = np.broadcast_to(np.asarray(width, np.float64), (n,))[:, None, None]
    t = np.linspace(0, 1, nseg + 1)
    wprof = np.sin(np.clip(t * 0.92 + 0.08, 0, 1) * math.pi) ** 0.6 * (1 - t ** 2 * 0.3)
    wprof[-1] = 0.0
    wprof = wprof * taper + (1 - taper) * (1 - t)
    centre = base[:, None, :] + d[:, None, :] * t[None, :, None] * L + \
        np.array([0, 0, -1.0])[None, None, :] * (droop * t[None, :, None] ** 2) * L
    left = centre + side[:, None, :] * (wprof[None, :, None] * W * 0.5)
    right = centre - side[:, None, :] * (wprof[None, :, None] * W * 0.5)
    pts = np.concatenate([left, right[:, ::-1]], axis=1)
    nrm = np.cross(d, side)
    plant.add_polys(pts, nrm, alb, **kw)


def needles(plant, rng, base, dirs, length, width, alb, **kw):
    """Lá kim / sợi mảnh: tứ giác rất hẹp, quay bản rộng về phía người nhìn."""
    base = np.asarray(base, np.float64)
    n = len(base)
    if n == 0:
        return
    d = nrmz(np.asarray(dirs, np.float64))
    side = np.cross(d, VIEW[None, :])
    bad = np.linalg.norm(side, axis=1) < 1e-3
    side[bad] = np.array([1.0, 0, 0])
    side = nrmz(side)
    L = np.broadcast_to(np.asarray(length, np.float64), (n,))[:, None]
    W = np.broadcast_to(np.asarray(width, np.float64), (n,))[:, None]
    tip = base + d * L
    pts = np.stack([base + side * W * 0.5, tip + side * W * 0.15, tip - side * W * 0.15, base - side * W * 0.5], 1)
    nrm = nrmz(np.cross(d, side) + rng.normal(0, 0.4, (n, 3)))
    plant.add_polys(pts, nrm, alb, **kw)


def sweep(origin, d0, length, step, bend_fn):
    """Đường cong mọc từ [origin] theo hướng [d0], ngả dần xuống theo
    [bend_fn](t) (radian, t = 0..1). Trả về (điểm, tiếp tuyến, s)."""
    d0 = nrmz(np.asarray(d0, np.float64))
    hz = np.array([d0[0], d0[1], 0.0])
    hz = hz / max(np.linalg.norm(hz), 1e-6) if np.linalg.norm(hz) > 1e-6 else np.array([1.0, 0, 0])
    el0 = math.asin(np.clip(d0[2], -1, 1))
    n = max(2, int(length / step) + 1)
    s = np.linspace(0, length, n)
    el = el0 - np.array([bend_fn(t) for t in s / length])
    T = np.stack([np.cos(el) * hz[0], np.cos(el) * hz[1], np.sin(el)], 1)
    ds = np.diff(s, prepend=0)[:, None]
    P = np.asarray(origin, np.float64) + np.cumsum(T * ds, axis=0) - T[0] * 0
    P = np.concatenate([[np.asarray(origin, np.float64)], P[1:]])
    return P, T, s


def bamboo(seed=41, n_culms=34, height=9.5, spread=0.9, thorny=False, lean=0.0):
    """Lũy tre làng: bụi nhiều cây tre mọc chụm, thân ngả ra ngoài và cong
    vồng ở ngọn, cành nhỏ rủ, lá mác dài xếp thành chùm như lông chim."""
    rng = np.random.default_rng(seed)
    p = Plant()
    culm_cols = [lin((96, 124, 60)), lin((120, 134, 62)), lin((112, 118, 84)), lin((84, 112, 56))]
    lb, ld = [], []
    for i in range(n_culms):
        r = spread * math.sqrt(rng.uniform(0.02, 1))
        a = rng.uniform(0, math.tau)
        base = np.array([r * math.cos(a), r * math.sin(a) * 0.8, 0.0])
        out = np.array([math.cos(a), math.sin(a), 0.0])
        out = nrmz(out + np.array([lean, 0, 0]))
        H = height * rng.uniform(0.7, 1.05) * (1.05 - 0.25 * r / spread)
        th0 = math.radians(rng.uniform(2, 10) + 16 * r / spread)
        th1 = th0 + math.radians(rng.uniform(25, 70))
        s = np.arange(0, H, 0.12)
        th = th0 + (th1 - th0) * (s / H) ** 2.4
        T = np.stack([np.sin(th) * out[0], np.sin(th) * out[1], np.cos(th)], 1)
        P = base + np.cumsum(T * 0.12, axis=0) - T[0] * 0.12
        rad = 0.048 * (1 - 0.88 * (s / H) ** 1.3) + 0.003
        rad = rad * rng.uniform(0.8, 1.15)
        cc = culm_cols[int(rng.integers(0, 4))] * math.exp(rng.normal(0, 0.12))
        node_gap = rng.uniform(0.32, 0.42)

        def cfn(mid, s0=s, P0=P, cc=cc, ng=node_gap):
            ss = np.interp(mid[:, 2], P0[:, 2], s0)
            ph = np.mod(ss, ng) / ng
            node = (ph < 0.12)[:, None]
            low = smoothstep(1.6, 0.4, mid[:, 2])[:, None]
            sheath = lin((150, 126, 84))
            c = cc[None, :] * (1 - 0.35 * low) + sheath[None, :] * 0.35 * low
            return np.where(node, c * 0.62, c)
        p.add_tube(P, rad, cc, alb_fn=cfn, mat=MAT_CULM, nfac=4, spec=0.25)
        # cành nhỏ ở các mắt phía trên
        for sv in np.arange(H * rng.uniform(0.28, 0.4), H * 0.97, node_gap):
            j = int(sv / 0.12)
            if j >= len(P):
                break
            q0 = P[j]
            u = sv / H
            for _ in range(int(rng.integers(1, 3))):
                side = nrmz(np.cross(T[j], rng.normal(size=3)))
                dd = nrmz(side + out * 0.6 + np.array([0, 0, 0.25]))
                ln = (0.4 + 1.3 * math.sin(math.pi * min(u, 0.95))) * rng.uniform(0.5, 1.0)
                q1 = q0 + dd * ln * 0.5 + np.array([0, 0, -0.05 * ln])
                q2 = q0 + dd * ln + np.array([0, 0, -0.25 * ln])
                p.add_segments([q0, q1], [q1, q2], [0.007, 0.005], [0.005, 0.002], cc * 0.9, nfac=2,
                               mat=MAT_CULM)
                k = int(30 * ln + 8)
                tt = rng.uniform(0.25, 1.0, k)[:, None]
                pts = np.where(tt < 0.5, q0 + (q1 - q0) * tt * 2, q1 + (q2 - q1) * (tt - 0.5) * 2)
                lb.append(pts)
                ld.append(nrmz(dd[None, :] * 0.7 + rng.normal(0, 0.45, (k, 3)) + np.array([0, 0, -0.75])))
        # chùm lá ở ngọn
        k = 40
        tt = rng.uniform(0.82, 1.0, k)
        idx = np.clip((tt * (len(P) - 1)).astype(int), 0, len(P) - 1)
        lb.append(P[idx])
        ld.append(nrmz(T[idx] * 0.5 + rng.normal(0, 0.5, (k, 3)) + np.array([0, 0, -0.6])))
        if thorny:
            # tre gai: cành gai chằng chịt ở gốc
            for _ in range(14):
                z = rng.uniform(0.3, 2.4)
                j = min(int(z / 0.12), len(P) - 1)
                q0 = P[j]
                pts = [q0]
                d = nrmz(out + rng.normal(0, 0.6, 3))
                for _ in range(4):
                    d = nrmz(d + rng.normal(0, 0.7, 3))
                    pts.append(pts[-1] + d * rng.uniform(0.15, 0.35))
                pts = np.array(pts)
                p.add_segments(pts[:-1], pts[1:], 0.007, 0.004, lin((112, 100, 70)), nfac=2, mat=MAT_CULM)
                lb.append(pts[1:].repeat(3, axis=0) + rng.normal(0, 0.05, (12, 3)))
                ld.append(nrmz(rng.normal(0, 1, (12, 3)) + np.array([0, 0, -0.5])))
    lb = np.concatenate(lb)
    ld = np.concatenate(ld)
    n = len(lb)
    alb = jitter_colors(rng, n, (82, 112, 44), h=0.12, v=0.22)
    dry = rng.uniform(0, 1, n) < 0.07
    alb[dry] = jitter_colors(rng, dry.sum(), (168, 150, 84), h=0.1, v=0.15)
    L = rng.uniform(0.15, 0.24, n)
    strips(p, rng, lb, ld, L, L * 0.13, alb, droop=0.25, nseg=3, alb_back=alb * np.array([1.2, 1.18, 1.05]),
           trans=0.55, spec=0.12, shin=12)
    return p, dict(bark_tex={MAT_CULM: lambda x, z: 0.94 + 0.12 * fbm(x * 40, z * 2, seed=3, octaves=2)},
                   k_shadow=1.2)


def bamboo_1():
    return bamboo(41, n_culms=30, height=9.0, spread=0.8, lean=0.15)


def bamboo_2():
    return bamboo(43, n_culms=44, height=10.0, spread=1.15, thorny=True, lean=-0.2)


def banana_leaf(p, rng, top, az, el, L, W, age, petiole=0.35, droop=1.0, tear=0.5, dead=False):
    """Một tàu lá chuối: cuống + phiến hai nửa, rách thành dải theo gân, mép
    rách ngả nâu; lá già rủ nhiều hơn."""
    hz = np.array([math.cos(az), math.sin(az), 0.0])
    tot = petiole + L
    P, T, s = sweep(top, (math.cos(el) * hz[0], math.cos(el) * hz[1], math.sin(el)), tot, tot / 30,
                    lambda t: droop * (0.25 + 1.4 * age) * t ** 1.5)
    up = np.array([0, 0, 1.0])
    Sd = nrmz(np.cross(T, up) + 1e-6)
    Nb = nrmz(np.cross(Sd, T))
    u = np.clip((s - petiole) / L, 0, 1)
    wv = W * np.sin(np.clip(u, 0, 1) * math.pi * 0.98 + 0.02) ** 0.45 * (u > 0)
    wv[-1] = 0
    if dead:
        wv *= 0.55
    # màu
    if dead:
        base = lin((104, 82, 54)) * math.exp(rng.normal(0, 0.12))
    else:
        young = lin((112, 150, 56))
        mature = lin((60, 100, 38))
        base = young * (1 - age) + mature * age
        base = base * math.exp(rng.normal(0, 0.08))
    brown = lin((132, 104, 62))
    K = 4
    quads, norms, cols = [], [], []
    for side in (-1, 1):
        # vị trí rách: lá non gần như liền, lá già xé thành nhiều dải hẹp
        cuts = [0]
        uu = 0.04
        while uu < 1:
            uu += rng.uniform(0.025, 0.09) if rng.uniform() < tear else rng.uniform(0.15, 0.35)
            cuts.append(min(uu, 1.0))
        cuts = np.array(cuts)
        idx = np.clip((cuts * (len(s) - 1)).astype(int), 0, len(s) - 1)
        pet = int(np.searchsorted(s, petiole))
        for c in range(len(idx) - 1):
            i0, i1 = max(idx[c], pet), idx[c + 1]
            if i1 - i0 < 1:
                continue
            extra = rng.uniform(-0.1, 1.1) * tear * (0.3 + age)
            gap = 0.02 * tear
            dry = (dead or rng.uniform() < 0.25 + 0.6 * age * tear)
            cvar = math.exp(rng.normal(0, 0.05))
            for i in range(i0, i1):
                for j in range(K):
                    f0, f1 = j / K, (j + 1) / K

                    def pt(ii, f, ext=extra):
                        w = wv[ii]
                        # mép nửa lá võng xuống, dải rách rủ thêm
                        fold = 0.18 * f - (0.35 + ext) * f * f
                        g = gap * f if (ii == i0 or ii == i1) else 0
                        return P[ii] + Sd[ii] * side * f * w + Nb[ii] * fold * w + T[ii] * (g * (1 if ii == i0 else -1))
                    q = [pt(i, f0), pt(i + 1, f0), pt(i + 1, f1), pt(i, f1)]
                    quads.append(q)
                    nn = np.cross(q[2] - q[0], q[1] - q[3])
                    norms.append(nn * side)
                    col = base * (1.08 - 0.16 * f0) * cvar
                    if not dead:
                        # mép ngoài và chóp lá khô cháy nâu
                        bw = (0.85 if (dry and j == K - 1) else 0.0) + smoothstep(0.82, 1.0, u[i]) * age * 0.9
                        bw = min(bw, 1.0)
                        col = col * (1 - bw) + brown * bw
                    cols.append(col)
    q = np.array(quads)
    p.add_polys(q, np.array(norms), np.array(cols), alb_back=np.array(cols) * np.array([1.2, 1.18, 1.0]),
                trans=0.5 if not dead else 0.1, spec=0.18, shin=18)
    # gân giữa / cuống
    p.add_tube(P, np.full(len(P), 0.022) * (1 - 0.7 * s / tot), lin((150, 162, 96)) if not dead else base,
               nfac=3, mat=MAT_PLAIN, spec=0.2)


def banana_stem_tex(x, z):
    """Thân giả cây chuối: sọc dọc xanh, mảng nâu đen, bẹ khô bong."""
    n1 = fbm(x * 30, z * 1.2, seed=4, octaves=3)
    n2 = fbm(x * 8 + 3, z * 2.5, seed=8, octaves=3)
    streak = 0.85 + 0.3 * n1
    blotch = 1 - 0.45 * smoothstep(0.58, 0.72, n2)
    return streak * blotch


def banana_plant(p, rng, base, height, n_leaves=8, fruit=False, scale=1.0, lean=(0.0, 0.0)):
    stem_h = height * 0.52
    zs = np.linspace(0, stem_h, 24)
    path = np.stack([base[0] + lean[0] * (zs / stem_h) ** 1.5, base[1] + lean[1] * (zs / stem_h) ** 1.5, zs], 1)
    rad = (0.13 - 0.045 * zs / stem_h) * scale

    p.add_tube(path, rad, lin((98, 118, 56)), nfac=8, mat=MAT_STEM, spec=0.15)
    top = path[-1]
    ga = math.pi * (3 - math.sqrt(5))
    a0 = rng.uniform(0, math.tau)
    for k in range(n_leaves):
        age = 1 - k / max(n_leaves - 1, 1)  # k cuối là lá non nhất
        az = a0 + k * ga + rng.normal(0, 0.2)
        el = math.radians(78 - 60 * age + rng.normal(0, 6))
        L = height * 0.5 * rng.uniform(0.85, 1.1) * (0.75 + 0.25 * min(1.0, k / 2 + 0.3))
        banana_leaf(p, rng, top + np.array([0, 0, -0.05 * age]), az, el, L, 0.26 * scale * L / 1.7, age,
                    petiole=0.3 * scale, tear=0.35 + 0.6 * age)
    # lá khô rủ dọc thân
    for k in range(int(rng.integers(1, 3))):
        az = rng.uniform(0, math.tau)
        banana_leaf(p, rng, top + np.array([0, 0, -0.15 - 0.1 * k]), az, math.radians(-78), height * 0.36,
                    0.2 * scale, 1.0, petiole=0.1, droop=0.1, tear=0.95, dead=True)
    if fruit:
        # buồng chuối: cuống cong rủ, các nải quả xanh, bắp chuối tím đỏ ở cuối
        az = math.atan2(-0.8, 0.6)  # buồng quay về phía người nhìn cho thấy rõ
        P, T, s = sweep(top, (math.cos(az) * 0.6, math.sin(az) * 0.6, 0.5), 1.25, 0.05,
                        lambda t: 2.2 * t ** 1.2)
        p.add_tube(P, np.full(len(P), 0.03), lin((96, 112, 54)), nfac=4, mat=MAT_PLAIN)
        for h, sv in enumerate(np.linspace(0.22, 0.78, 8)):
            j = int(sv * (len(P) - 1))
            c = P[j]
            for f in range(12):
                ang = f / 12 * math.pi * 1.8 - math.pi * 0.9 + rng.normal(0, 0.1)
                rd = nrmz(np.cross(T[j], np.array([0, 0, 1.0])))
                rd2 = np.cross(T[j], rd)
                d = nrmz(rd * math.cos(ang) + rd2 * math.sin(ang) * 0.7 + np.array([0, 0, 0.9]) - T[j] * 0.2)
                a = c + d * 0.05
                b = c + d * 0.19 + np.array([0, 0, 0.05])
                p.add_segments([a], [b], 0.04, 0.028, lin((128, 150, 58)) * math.exp(rng.normal(0, 0.08)), nfac=4,
                               mat=MAT_PLAIN, spec=0.35)
        tip = P[-1]
        bud = [tip + T[-1] * t * 0.28 for t in np.linspace(0, 1, 7)]
        p.add_tube(bud, 0.08 * np.sin(np.linspace(0.25, 1.0, 7) * math.pi) ** 0.8 + 0.005, lin((112, 36, 52)),
                   nfac=6, mat=MAT_PLAIN, spec=0.5)


def banana_1():
    """Bụi chuối ba cây (một mẹ, hai con) rách lá như ngoài vườn."""
    rng = np.random.default_rng(51)
    p = Plant()
    banana_plant(p, rng, np.array([0.0, 0.0, 0.0]), 3.8, n_leaves=8, lean=(0.08, 0.0))
    banana_plant(p, rng, np.array([-0.55, 0.25, 0.0]), 2.6, n_leaves=6, scale=0.8, lean=(-0.2, 0.05))
    banana_plant(p, rng, np.array([0.5, -0.3, 0.0]), 1.5, n_leaves=4, scale=0.55, lean=(0.12, -0.05))
    return p, dict(k_shadow=0.7, bark_tex={MAT_STEM: banana_stem_tex})


def banana_2():
    """Cây chuối có buồng quả và bắp chuối, thêm cây con dưới gốc."""
    rng = np.random.default_rng(57)
    p = Plant()
    banana_plant(p, rng, np.array([0.0, 0.0, 0.0]), 3.5, n_leaves=7, fruit=True, lean=(0.25, -0.05))
    banana_plant(p, rng, np.array([-0.45, -0.2, 0.0]), 1.2, n_leaves=4, scale=0.5, lean=(-0.1, 0.0))
    return p, dict(k_shadow=0.7, bark_tex={MAT_STEM: banana_stem_tex})


def coconut(seed=61, height=10.5, lean=1.6, n_fronds=24):
    """Dừa: thân cong nghiêng có vết sẹo vòng, tàu lá kép lông chim rủ, chùm
    quả dưới tán, vài tàu khô rủ dọc thân."""
    rng = np.random.default_rng(seed)
    p = Plant()
    az = rng.uniform(-0.6, 0.6) + (0 if lean > 0 else math.pi)
    lean = abs(lean)
    zs = np.arange(0, height + 1e-6, 0.05)
    t = zs / height
    # cong chữ S nhẹ: gốc ngả rồi ngọn vươn thẳng lên đón nắng
    off = lean * (1.6 * t - 0.6 * t ** 2.2)
    path = np.stack([off * math.cos(az), off * math.sin(az) * 0.4, zs], 1)
    rad = 0.15 - 0.03 * t + 0.12 * np.exp(-zs / 0.25)
    gray = lin((132, 122, 108))

    def rfn(mid):
        ss = mid[:, 2]
        ring = (np.mod(ss, 0.11) < 0.03)[:, None]
        dark = smoothstep(2.5, 0.0, ss)[:, None] * 0.35
        c = gray[None, :] * (1 - dark) * (0.92 + 0.16 * fbm(ss * 0.8, ss * 0.1, seed=seed, octaves=2))[:, None]
        return np.where(ring, c * 0.7, c)
    p.add_tube(path, rad, gray, alb_fn=rfn, nfac=10, mat=MAT_STEM)
    top = path[-1]
    # bẹ lá xơ nâu ở cổ ngọn
    p.add_sphere(top + np.array([0, 0, -0.05]), 0.24, lin((106, 86, 58)), nlat=4, nlon=10, squash=1.3,
                 mat=MAT_PLAIN)
    ga = math.pi * (3 - math.sqrt(5))
    lb, ld, ll, lw, lc, lsd = [], [], [], [], [], []
    for k in range(n_fronds):
        age = k / (n_fronds - 1)  # 0: non (giữa, dựng đứng) → 1: già (rủ)
        a = k * ga + rng.normal(0, 0.15)
        el = math.radians(78 - 125 * age + rng.normal(0, 7))
        L = (3.0 + 1.5 * min(1, age * 2.5)) * rng.uniform(0.9, 1.08)
        dead = age > 0.93
        P, T, s = sweep(top + np.array([0, 0, 0.05]), (math.cos(el) * math.cos(a), math.cos(el) * math.sin(a),
                                                      math.sin(el)), L, 0.08,
                        lambda tt, ag=age: (0.35 + 1.2 * ag) * tt ** 1.4 if not dead else 0.3 * tt)
        if dead:
            P, T, s = sweep(top, (math.cos(a) * 0.25, math.sin(a) * 0.25, -0.97), L * 0.8, 0.08, lambda tt: 0.0)
        p.add_tube(P, 0.045 * (1 - 0.8 * s / L) + 0.006, lin((150, 140, 82)) if not dead else lin((112, 90, 60)),
                   nfac=3, mat=MAT_PLAIN, spec=0.2)
        up = np.array([0, 0, 1.0])
        for side in (-1, 1):
            sv = np.arange(0.12 * L, 0.985 * L, 0.05 if not dead else 0.07)
            j = np.clip((sv / L * (len(P) - 1)).astype(int), 0, len(P) - 1)
            Tj = T[j]
            Sd = nrmz(np.cross(Tj, up) + 1e-6)
            Nb = nrmz(np.cross(Sd, Tj))
            u = sv / L
            droopv = math.radians(42 + 28 * age) + rng.normal(0, 0.18, len(sv))
            if dead:
                droopv = droopv * 0 + math.radians(75)
            d = nrmz(Sd * side * np.cos(droopv)[:, None] * 1.0 + Tj * 0.55 - Nb * np.sin(droopv)[:, None] +
                     rng.normal(0, 0.08, (len(sv), 3)))
            lb.append(P[j] + Sd * side * 0.02)
            ld.append(d)
            ll.append((0.3 + 0.85 * np.sin(np.clip(u * 1.05, 0, 1) * math.pi) ** 0.7) * rng.uniform(0.85, 1.1, len(sv)) *
                      (0.7 if dead else 1.0))
            lw.append(np.full(len(sv), 0.034 if not dead else 0.018))
            lsd.append(np.cross(d, Nb))
            if dead:
                lc.append(jitter_colors(rng, len(sv), (128, 100, 64), h=0.05, v=0.12))
            else:
                young = np.array(lin((122, 134, 58)))
                old = np.array(lin((66, 92, 36)))
                c0 = young * max(0, 1 - age * 3) + old * min(1, age * 3)
                if age > 0.8:
                    c0 = c0 * 0.6 + lin((140, 128, 64)) * 0.4
                lc.append(np.clip(c0[None, :] * np.exp(rng.normal(0, 0.1, (len(sv), 1))), 0, 1))
    lb, ld = np.concatenate(lb), np.concatenate(ld)
    ll, lw, lc, lsd = np.concatenate(ll), np.concatenate(lw), np.concatenate(lc), np.concatenate(lsd)
    strips(p, rng, lb, ld, ll, lw, lc, droop=0.35, nseg=4, side=lsd, alb_back=lc * np.array([1.15, 1.12, 1.0]),
           trans=0.45, spec=0.3, shin=18)
    # chùm dừa
    nc = int(rng.integers(10, 16))
    cc = []
    for i in range(nc):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.22, 0.42)
        cc.append(top + np.array([math.cos(a) * r, -abs(math.sin(a)) * r, -rng.uniform(0.25, 0.7)]))
    cols = np.array([lin((92, 112, 40)), lin((150, 140, 52)), lin((112, 84, 46))])
    p.add_sphere(np.array(cc), rng.uniform(0.11, 0.14, nc), cols[rng.integers(0, 3, nc)] * 1.0, nlat=4, nlon=8,
                 mat=MAT_PLAIN, spec=0.35, squash=1.1)
    return p, dict(k_shadow=0.8, bark_tex={MAT_STEM: lambda x, z: 0.9 + 0.2 * fbm(x * 20, z * 3, seed=2, octaves=3)})


def palm_1():
    return coconut(61, height=9.5, lean=1.8, n_fronds=28)


def palm_2():
    return coconut(67, height=7.8, lean=-0.9, n_fronds=26)


def casuarina(seed=71, height=11.0, lean=0.3, sparse=0.0):
    """Phi lao: thân thẳng mảnh, cành vươn chếch lên rồi rủ, tán thưa hình
    nón méo, lá kim xám xanh rủ thành tua."""
    rng = np.random.default_rng(seed)
    p = Plant()
    th = height * 0.93
    zs = np.arange(0, th, 0.1)
    trunk = tilt_path(zs, (lean, 0.05), wobble=0.12, seed=seed)
    tr = 0.17 * (1 - zs / th) ** 0.9 + 0.012
    bark = lin((88, 78, 68))
    p.add_tube(trunk, tr * (1 + 0.4 * np.exp(-zs / 0.25)), bark, nfac=10)
    tb, td = [], []
    z = 1.8
    while z < th - 0.2:
        for _ in range(int(rng.integers(1, 3))):
            j = int(z / 0.1)
            q0 = trunk[min(j, len(trunk) - 1)]
            u = (z - 1.8) / (th - 1.8)
            L = (0.6 + 2.4 * (1 - u) ** 0.9) * rng.uniform(0.5, 1.25)
            if rng.uniform() < sparse:
                L *= 0.4
            a = rng.uniform(0, math.tau)
            el = math.radians(rng.uniform(25, 55))
            P, T, s = sweep(q0, (math.cos(el) * math.cos(a), math.cos(el) * math.sin(a), math.sin(el)), L, 0.12,
                            lambda t: 1.0 * t ** 1.3)
            p.add_tube(P, 0.03 * (1 - 0.8 * s / L) * (L / 2.5) ** 0.5 + 0.004, bark * 1.1, nfac=3)
            # tua lá dọc 3/4 ngoài của cành + nhánh con
            pts = [P[int(len(P) * f)] for f in np.linspace(0.3, 0.999, max(3, int(L / 0.1)))]
            for k in range(int(L * 2.5)):
                f = rng.uniform(0.3, 0.95)
                q = P[int(len(P) * f)]
                dd = nrmz(np.cross(T[int(len(P) * f)], rng.normal(size=3)) + np.array([0, 0, 0.3]))
                ln = rng.uniform(0.3, 0.7) * (1 - f * 0.5)
                q2 = q + dd * ln + np.array([0, 0, -0.1 * ln])
                p.add_segments([q], [q2], 0.006, 0.003, bark * 1.15, nfac=2)
                pts.extend([q + (q2 - q) * g for g in np.linspace(0.3, 1.0, 4)])
            for q in pts:
                n = int(rng.integers(18, 30))
                tb.append(np.repeat(q[None, :], n, axis=0) + rng.normal(0, 0.05, (n, 3)))
                td.append(nrmz(np.array([0, 0, -1.0]) * rng.uniform(0.6, 1.0, (n, 1)) + rng.normal(0, 0.4, (n, 3))))
        z += rng.uniform(0.16, 0.38)
    # ngọn
    for q in trunk[-12:]:
        n = 14
        tb.append(np.repeat(q[None, :], n, axis=0) + rng.normal(0, 0.06, (n, 3)))
        td.append(nrmz(rng.normal(0, 0.6, (n, 3)) + np.array([0, 0, 0.2])))
    tb, td = np.concatenate(tb), np.concatenate(td)
    n = len(tb)
    alb = jitter_colors(rng, n, (80, 98, 74), h=0.08, v=0.2)
    dry = rng.uniform(0, 1, n) < 0.08
    alb[dry] = jitter_colors(rng, dry.sum(), (122, 110, 84), h=0.05, v=0.15)
    needles(p, rng, tb, td, rng.uniform(0.2, 0.38, n), 0.011, alb, trans=0.3, spec=0.05,
            alb_back=alb * 1.1, area=np.full(n, 0.004))
    return p, dict(k_shadow=0.8, bark_tex={MAT_BARK: bark_fn(seed, scale=1.6, fissure=0.5)})


def casuarina_1():
    return casuarina(71, 11.0, 0.4)


def casuarina_2():
    return casuarina(77, 9.2, -0.6, sparse=0.25)


def pine(seed=81, height=13.0, mature=True):
    """Thông ba lá (Đà Lạt, đèo núi): thân nâu xám bong vảy đỏ, cành mọc
    vòng không đều, lá kim dài gom thành từng đám ở đầu cành; cây già tán
    dù lệch, cây non hình nón."""
    rng = np.random.default_rng(seed)
    p = Plant()
    th = height * 0.96
    zs = np.arange(0, th, 0.1)
    trunk = tilt_path(zs, (rng.uniform(-0.4, 0.4), 0.05), wobble=0.2, seed=seed)
    tr = 0.26 * (1 - zs / th) ** 0.8 + 0.02
    bark = lin((94, 70, 58))
    p.add_tube(trunk, tr * (1 + 0.4 * np.exp(-zs / 0.3)), bark, nfac=12)
    tufts, tdir = [], []
    z0 = height * (0.5 if mature else 0.1)
    # cành khô cụt ở thân dưới
    for z in np.arange(1.8, z0, rng.uniform(0.5, 0.9)):
        q0 = trunk[int(z / 0.1)]
        a = rng.uniform(0, math.tau)
        d = np.array([math.cos(a), math.sin(a), rng.uniform(-0.3, 0.1)])
        p.add_segments([q0], [q0 + d * rng.uniform(0.15, 0.5)], 0.025, 0.008, lin((96, 88, 80)), nfac=3)
    z = z0

    def pad(q, d, n):
        """Đám lá kim: vài chùm sát nhau ở đầu cành."""
        for _ in range(n):
            tufts.append(q + rng.normal(0, 0.12, 3) * np.array([1, 1, 0.6]))
            tdir.append(nrmz(d + np.array([0, 0, 0.7]) + rng.normal(0, 0.3, 3)))

    while z < th - 0.3:
        u = (z - z0) / (th - z0)
        nb = int(rng.integers(3, 6)) if mature else int(rng.integers(3, 6))
        a0 = rng.uniform(0, math.tau)
        q0 = trunk[min(int(z / 0.1), len(trunk) - 1)]
        for b in range(nb):
            a = a0 + b * math.tau / nb + rng.normal(0, 0.4)
            if mature:
                L = (0.9 + 2.7 * math.sin(math.pi * (0.1 + 0.8 * (1 - u))) ** 1.3) * rng.uniform(0.55, 1.2)
                el = math.radians(rng.uniform(20, 48))
                bend = lambda t: -0.35 * t + 0.25 * math.sin(t * math.pi)
            else:
                L = (0.4 + 2.8 * (1 - u) ** 1.1) * rng.uniform(0.75, 1.1)
                el = math.radians(rng.uniform(4, 22))
                bend = lambda t: 0.2 * math.sin(t * math.pi) - 0.25 * t ** 2
            P, T, s = sweep(q0, (math.cos(el) * math.cos(a), math.cos(el) * math.sin(a), math.sin(el)), L, 0.1, bend)
            P = P + np.cumsum(rng.normal(0, 0.03, P.shape), axis=0) * np.array([1, 1, 0.5])
            p.add_tube(P, 0.065 * (L / 3) ** 0.7 * (1 - 0.75 * s / L) + 0.008, bark * 0.95, nfac=4)
            pad(P[-1], T[-1], 12 if mature else 4)
            step = 0.17 if mature else 0.16
            for f in np.arange(0.3 if mature else 0.15, 0.95, step):
                j = int(f * (len(P) - 1))
                side = nrmz(np.cross(T[j], np.array([0, 0, 1.0]))) * rng.choice([-1, 1])
                dd = nrmz(side + T[j] * 0.9 + np.array([0, 0, 0.5 if mature else 0.1]))
                ln = rng.uniform(0.3, 0.9) * (1 - f * 0.4) * (1.0 if mature else 0.8)
                q1 = P[j] + dd * ln
                p.add_segments([P[j]], [q1], 0.016, 0.006, bark, nfac=2)
                pad(q1, dd, 7 if mature else 3)
                pad(P[j] + dd * ln * 0.5, dd, 2 if mature else 1)
        z += rng.uniform(0.45, 0.9) if mature else rng.uniform(0.45, 0.8)
    pad(trunk[-1], np.array([0, 0, 1.0]), 6)
    pad(trunk[-4], np.array([0, 0, 1.0]), 4)
    tufts, tdir = np.array(tufts), np.array(tdir)
    k = 40
    n = len(tufts) * k
    base = np.repeat(tufts, k, axis=0) + rng.normal(0, 0.025, (n, 3))
    ax = np.repeat(tdir, k, axis=0)
    d = nrmz(ax + rng.normal(0, 0.7, (n, 3)))
    alb = jitter_colors(rng, n, (42, 70, 40) if mature else (46, 76, 48), h=0.06, v=0.2)
    needles(p, rng, base, d, rng.uniform(0.18, 0.3, n), 0.009, alb, trans=0.25, spec=0.2, shin=20,
            alb_back=alb * 1.1, area=np.full(n, 0.0035))
    return p, dict(k_shadow=1.0, bark_tex={MAT_BARK: bark_fn(seed, scale=0.7, fissure=0.6, flake=0.5)})


def pine_1():
    return pine(81, 13.5, True)


def pine_2():
    return pine(87, 10.5, False)


def shrub(seed, center, radii, n_attr, leaf_rgb, leaf_len, leaf_w, leaves_per=16, twig_n=3, shape='ovate',
          stems=5, root_r=0.03, spec=0.3, clump=0.0, prune=(0.03, 0.18), bark_rgb=(92, 80, 64)):
    """Cây bụi nhiều thân mọc từ gốc, tán elipxôit."""
    rng = np.random.default_rng(seed)
    p = Plant()
    sk = Skeleton([(0, 0, 0.0), (0, 0, 0.06)])
    for k in range(stems):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.05, 0.3) * radii[0]
        tip = np.array([math.cos(a) * r, math.sin(a) * r * 0.7, radii[2] * 0.6])
        sk.add_path([tip * f for f in np.linspace(0.2, 1.0, 5)], 1)
    A = ellipsoid_points(rng, n_attr, center, radii, noise=0.25, seed=seed, flatten_bottom=-0.75)
    sk.grow(A, step=0.08, infl=0.6, kill=0.12, iters=160, tropism=(0, 0, 0.1), min_z=0.05, rng=rng, jitter=0.25)
    sk.finalize(tip_r=0.004, exp=2.3, trunk_n=2, root_r=root_r, gamma=1.2)
    bark = lin(bark_rgb)
    add_skeleton(p, sk, bark, flare=0.2)
    tw, _ = twigs(p, rng, sk, twig_n, 0.14, bark * 1.1, r0=0.004)

    def col(base, rng):
        c = jitter_colors(rng, len(base), leaf_rgb, h=0.08, v=0.2)
        return c * (1 + 0.25 * smoothstep(center[2], center[2] + radii[2], base[:, 2]))[:, None]
    leaf_cloud(p, rng, tw, leaves_per, 0.05, leaf_len, leaf_w, col, shape=shape, center=center, trans=0.35, spec=spec,
               clump=clump, seed=seed)
    p.prune(rng, lo=prune[0], hi=prune[1], vs=0.08)
    return p, rng


def bush_1():
    """Bụi dâm bụt (râm bụt) lá xanh bóng, lác đác hoa đỏ."""
    p, rng = shrub(91, (0, 0, 0.78), (0.72, 0.6, 0.58), 1600, (44, 82, 34), 0.085, 0.055, leaves_per=14)
    pts = ellipsoid_points(rng, 400, (0, 0, 0.8), (0.74, 0.62, 0.6))
    out = nrmz(pts - np.array([0, 0, 0.6]))
    front = (out[:, 1] < 0.3) & (np.linalg.norm((pts - np.array([0, 0, 0.8])) / np.array([0.74, 0.62, 0.6]), axis=1) > 0.8)
    pts, out = pts[front][:26], out[front][:26]
    n = len(pts)
    p.add_flowers(pts, nrmz(out + rng.normal(0, 0.4, (n, 3))), rng.uniform(0.05, 0.065, n),
                  jitter_colors(rng, n, (196, 28, 36), h=0.04, v=0.1), lin((120, 12, 28)), cup=0.35, rng=rng)
    return p, dict(vs=0.09, k_shadow=0.9, bark_tex={MAT_BARK: bark_fn(1, scale=3)})


def bush_2():
    """Hàng rào cây xén phẳng (chè tàu / duối) trước sân nhà quê."""
    rng = np.random.default_rng(93)
    p = Plant()
    hw, hd, hh = 1.3, 0.38, 1.05
    n = 52000
    q = rng.uniform(-1, 1, (n, 3))
    # điểm trên lớp vỏ hộp bo tròn, mặt trên hơi gồ ghề
    box = np.array([hw, hd, hh / 2])
    pos = q * box
    pos[:, 2] += hh / 2
    r = 0.18
    inner = np.clip(np.abs(pos - np.array([0, 0, hh / 2])), 0, box - r)
    d = np.abs(pos - np.array([0, 0, hh / 2])) - inner
    dist = np.linalg.norm(d, axis=1)
    bump = 0.06 * fbm(pos[:, 0] * 3, pos[:, 1] * 3 + pos[:, 2] * 2, seed=5, octaves=3)
    keep = (dist > r - 0.16) & (dist < r + bump) & (pos[:, 2] > 0.04 + 0.05 * bump / 0.06)
    pos = pos[keep]
    nrm_out = nrmz(np.sign(pos - np.array([0, 0, hh / 2])) * d[keep] + rng.normal(0, 0.05, pos.shape) + 1e-6)
    n = len(pos)
    axis = nrmz(rng.normal(size=(n, 3)) + nrm_out * 0.6)
    normal = nrmz(nrm_out * 0.8 + rng.normal(0, 0.6, (n, 3)) + np.array([0, 0, 0.4]))
    alb = jitter_colors(rng, n, (52, 86, 36), h=0.08, v=0.2)
    fresh = (pos[:, 2] > hh - 0.08) & (rng.uniform(0, 1, n) < 0.5)
    alb[fresh] = jitter_colors(rng, fresh.sum(), (110, 140, 52), h=0.08, v=0.15)
    p.add_leaves(pos, axis, normal, 0.05 * rng.uniform(0.8, 1.2, n), 0.03, alb, shape='ovate', bend=0.1,
                 alb_back=alb * 1.15, trans=0.3, spec=0.2)
    # thân gốc lộ ra dưới đáy
    for k in range(14):
        x = rng.uniform(-hw + 0.15, hw - 0.15)
        a = np.array([x, rng.uniform(-0.15, 0.15), 0.0])
        b = a + np.array([rng.normal(0, 0.08), rng.normal(0, 0.05), 0.15])
        p.add_segments([a], [b], 0.018, 0.012, lin((90, 78, 62)), nfac=4)
    return p, dict(vs=0.09, k_shadow=1.0)


def bush_3():
    """Bụi cỏ lau ven đường: lá dài cong rủ, bông lau trắng bạc phất phơ."""
    rng = np.random.default_rng(95)
    p = Plant()
    n = 900
    a = rng.uniform(0, math.tau, n)
    r = rng.uniform(0, 0.3, n) ** 0.8
    base = np.stack([np.cos(a) * r, np.sin(a) * r * 0.7, rng.uniform(0, 0.9, n) ** 2.2], 1)
    out = np.stack([np.cos(a), np.sin(a), np.zeros(n)], 1)
    d = nrmz(np.array([0, 0, 1.0]) + out * rng.uniform(0.15, 0.9, (n, 1)) + rng.normal(0, 0.18, (n, 3)))
    L = rng.uniform(0.5, 1.3, n) * (1 - 0.35 * base[:, 2])
    alb = jitter_colors(rng, n, (98, 120, 52), h=0.1, v=0.2)
    dry = rng.uniform(0, 1, n) < 0.25
    alb[dry] = jitter_colors(rng, dry.sum(), (160, 146, 96), h=0.06, v=0.12)
    strips(p, rng, base, d, L, 0.018, alb, droop=0.85, nseg=7, taper=0.4, alb_back=alb * 1.15, trans=0.45,
           spec=0.25, shin=14)
    # bông lau
    for k in range(13):
        a0 = rng.uniform(0, math.tau)
        b0 = np.array([math.cos(a0) * 0.1, math.sin(a0) * 0.07, 0])
        H = rng.uniform(1.45, 2.0)
        top = b0 + np.array([math.cos(a0) * 0.25 + rng.normal(0, 0.1), math.sin(a0) * 0.15, H])
        p.add_segments([b0], [top], 0.006, 0.003, lin((150, 140, 96)), nfac=2, mat=MAT_PLAIN)
        lean = nrmz(np.array([0.6 + rng.normal(0, 0.2), rng.normal(0, 0.3), 0.0]))
        m = 160
        t = rng.uniform(0, 1, (m, 1))
        sb = top + np.array([0, 0, -0.42]) * t + lean * 0.06 * t
        sd = nrmz(lean * 0.9 + np.array([0, 0, 0.35]) + rng.normal(0, 0.35, (m, 3)))
        c = jitter_colors(rng, m, (222, 216, 204), h=0.03, v=0.08)
        needles(p, rng, sb, sd, rng.uniform(0.08, 0.17, m), 0.006, c, trans=0.7, alb_back=c, mat=MAT_FLOWER)
    return p, dict(vs=0.1, k_shadow=0.7)


def flowering_tree(seed, ground_z, crown_c, crown_r, petal_rgb, eye_rgb, n_flowers, flower_r, bark_rgb,
                   trunk_h=0.6, root_r=0.07, leaf_frac=0.15, leaf_rgb=(110, 140, 60)):
    """Cây hoa Tết (đào, mai): cành khẳng khiu gấp khúc, hoa nở dày dọc cành."""
    rng = np.random.default_rng(seed)
    p = Plant()
    zs = np.linspace(ground_z, ground_z + trunk_h, 6)
    trunk = np.stack([0.05 * np.sin(zs * 5), 0.02 * zs, zs], 1)
    sk = Skeleton(trunk)
    A = ellipsoid_points(rng, 700, crown_c, crown_r, noise=0.35, seed=seed)
    sk.grow(A, step=0.11, infl=0.7, kill=0.2, iters=120, tropism=(0, 0, 0.2), min_z=ground_z + trunk_h * 0.5,
            rng=rng, jitter=0.4)
    sk.finalize(tip_r=0.004, exp=2.2, trunk_n=len(trunk), root_r=root_r, gamma=1.1, smooth=0)
    bark = lin(bark_rgb)
    add_skeleton(p, sk, bark, flare=0.4, flare_h=0.1)
    tw, _ = twigs(p, rng, sk, 2, 0.16, bark * 1.05, r0=0.004, up=0.4, droop=-0.05, spread=0.5)
    # hoa dọc cành nhỏ và cành con
    cand = np.array([sk.P[i] for i in range(len(sk.P)) if sk.r[i] < 0.02 and sk.P[i][2] > ground_z + trunk_h])
    pts = np.concatenate([cand, tw])
    idx = rng.integers(0, len(pts), n_flowers)
    fc = pts[idx] + rng.normal(0, 0.025, (n_flowers, 3))
    cen = np.asarray(crown_c, np.float64)
    nr = nrmz(fc - cen + rng.normal(0, 0.35, (n_flowers, 3)) * np.linalg.norm(crown_r) + np.array([0, -0.3, 0.3]))
    cols = jitter_colors(rng, n_flowers, petal_rgb, h=0.05, v=0.12)
    rr = flower_r * rng.uniform(0.7, 1.15, n_flowers)
    bud = rng.uniform(0, 1, n_flowers) < 0.2
    rr[bud] *= 0.45
    cols[bud] = cols[bud] * np.array([0.8, 0.55, 0.65])
    p.add_flowers(fc, nr, rr, cols, lin(eye_rgb), rng=rng, cup=0.3)
    nl = int(n_flowers * leaf_frac)
    li = rng.integers(0, len(pts), nl)
    lb = pts[li] + rng.normal(0, 0.02, (nl, 3))
    lc = jitter_colors(rng, nl, leaf_rgb, h=0.08, v=0.15)
    p.add_leaves(lb, nrmz(lb - cen + rng.normal(0, 0.5, (nl, 3))), nrmz(rng.normal(size=(nl, 3)) + np.array([0, 0, 1])),
                 0.055, 0.022, lc, shape='lance', alb_back=lc * 1.1, trans=0.4)
    return p, rng


def flower_peach_1():
    """Cây đào Bắc trồng đất: cành nâu đen gân guốc, hoa hồng phấn nở rộ,
    nụ hồng thẫm, lộc non xanh."""
    p, rng = flowering_tree(101, 0.0, (0, 0, 1.75), (1.05, 0.9, 0.85), (236, 146, 168), (190, 52, 92), 4200, 0.022,
                            (70, 58, 54), trunk_h=0.7, root_r=0.075)
    return p, dict(vs=0.12, k_shadow=0.6, bark_tex={MAT_BARK: bark_fn(3, scale=3, fissure=0.3)})


def flower_apricot_1():
    """Chậu mai vàng ngày Tết miền Nam: chậu sứ men lam, gốc mai xù xì,
    hoa vàng năm cánh nở kín cành."""
    pot_h = 0.5

    def pot_col(z, a):
        # chậu men nâu da lươn, viền vàng đồng ở miệng và chân
        band = 0.425 < z < 0.445 or 0.05 < z < 0.065
        return lin((176, 140, 70)) if band else lin((92, 48, 30))
    prof = [(0.2, 0.0), (0.24, 0.03), (0.3, 0.12), (0.33, 0.28), (0.32, 0.42), (0.35, 0.46), (0.36, pot_h),
            (0.3, pot_h)]
    p, rng = flowering_tree(103, pot_h - 0.02, (0, 0, 1.35), (0.8, 0.66, 0.55), (246, 196, 36), (204, 112, 24),
                            2000, 0.017, (88, 76, 66), trunk_h=0.32, root_r=0.075, leaf_frac=0.15,
                            leaf_rgb=(132, 128, 56))
    p.add_lathe(prof, (0, 0, 0), pot_col, nseg=32, spec=0.6, shin=60)
    # mặt đất trong chậu
    a = np.linspace(math.pi, math.tau, 20)
    soil = np.stack([np.cos(a) * 0.32, np.sin(a) * 0.32, np.full_like(a, pot_h - 0.01)], 1)
    p.add_polys(soil[None], np.array([[0, 0, 1.0]]), lin((70, 54, 40)), mat=MAT_PLAIN, two_sided=False)
    return p, dict(vs=0.1, k_shadow=0.6, bark_tex={MAT_BARK: bark_fn(4, scale=3, fissure=0.3)})


# =============================================================== Mặt tiền nhà
# Hệ toạ độ mặt đứng: x (m) từ mép trái, y (m) từ mặt đất lên; độ nhô h (m)
# hướng ra phía người nhìn (tường chính h = 0).
F_SUN = np.array([-0.42, 0.55, 0.72])
F_SUN /= np.linalg.norm(F_SUN)
F_SUN_E = 0.95   # cường độ nắng (tường phẳng đón nắng ≈ 1.0)
F_AMB = np.array([0.36, 0.38, 0.42])  # trời hơi lam trong bóng râm
M_WALL, M_TRIM, M_GLASS, M_METAL, M_WOOD, M_SIGN, M_PLANT, M_ROOF, M_FABRIC = 1, 2, 3, 4, 5, 6, 7, 8, 9


def font(name, px):
    files = {'paytone': 'PaytoneOne-Regular.ttf', 'bold': 'Manrope-ExtraBold.ttf', 'semi': 'Manrope-Bold.ttf'}
    return ImageFont.truetype(os.path.join(FONT_DIR, files[name]), max(6, int(px)))


def vn(s):
    """Chuẩn hoá chữ tiếng Việt về dạng dựng sẵn (NFC) để font vẽ đúng dấu."""
    return unicodedata.normalize('NFC', s)


class Facade:
    """Ảnh mặt đứng nhiều lớp: màu nền (tuyến tính), độ phủ, độ nhô, vật
    liệu, phần không chịu nắng (kính phản chiếu, lòng nhà tối)."""

    def __init__(self, w, h, ppm, ss=2, seed=0):
        self.w, self.h, self.ss = w, h, ss
        self.ppm = ppm * ss
        self.ppm_f = ppm
        self.W = int(round(w * ppm)) * ss
        self.H = int(round(h * ppm)) * ss
        self.alb = np.zeros((self.H, self.W, 3))
        self.a = np.zeros((self.H, self.W))
        self.hm = np.zeros((self.H, self.W))
        self.hlo = np.full((self.H, self.W), -50.0)  # đáy vật (vật treo lơ lửng: cờ, dây, đèn lồng)
        self.mat = np.zeros((self.H, self.W), np.uint8)
        self.unlit = np.zeros((self.H, self.W, 3))
        self.u = np.zeros((self.H, self.W))
        self.rng = np.random.default_rng(seed)
        self.seed = seed

    # ------------------------------------------------------------- vùng
    def box(self, x0, y0, x1, y1, pad=2):
        p = self.ppm
        c0 = max(0, int(math.floor(min(x0, x1) * p)) - pad)
        c1 = min(self.W, int(math.ceil(max(x0, x1) * p)) + pad)
        r0 = max(0, int(math.floor((self.h - max(y0, y1)) * p)) - pad)
        r1 = min(self.H, int(math.ceil((self.h - min(y0, y1)) * p)) + pad)
        if c1 <= c0 or r1 <= r0:
            return None
        return (slice(r0, r1), slice(c0, c1))

    def grid(self, sl):
        xs = (np.arange(sl[1].start, sl[1].stop) + 0.5) / self.ppm
        ys = self.h - (np.arange(sl[0].start, sl[0].stop) + 0.5) / self.ppm
        return np.meshgrid(xs, ys)

    def rect(self, x0, y0, x1, y1):
        sl = self.box(x0, y0, x1, y1)
        if sl is None:
            return None, None
        X, Y = self.grid(sl)
        p = self.ppm
        mx = np.clip(np.minimum(X - min(x0, x1), max(x0, x1) - X) * p + 0.5, 0, 1)
        my = np.clip(np.minimum(Y - min(y0, y1), max(y0, y1) - Y) * p + 0.5, 0, 1)
        return sl, mx * my

    def _pil(self, bbox, fn):
        """Vẽ mặt nạ bằng PIL trong khung [bbox] (m); [fn](draw, to_px)."""
        x0, y0, x1, y1 = bbox
        sl = self.box(x0, y0, x1, y1, pad=4)
        if sl is None:
            return None, None
        hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        im = Image.new('L', (ww, hh), 0)
        dr = ImageDraw.Draw(im)
        ox, oy = sl[1].start, sl[0].start

        def to_px(x, y):
            return (x * self.ppm - ox, (self.h - y) * self.ppm - oy)
        fn(dr, to_px)
        return sl, np.asarray(im, np.float64) / 255.0

    def poly(self, pts):
        xs = [q[0] for q in pts]
        ys = [q[1] for q in pts]
        return self._pil((min(xs), min(ys), max(xs), max(ys)),
                         lambda d, t: d.polygon([t(*q) for q in pts], fill=255))

    def ellipse(self, cx, cy, rx, ry):
        return self._pil((cx - rx, cy - ry, cx + rx, cy + ry),
                         lambda d, t: d.ellipse([t(cx - rx, cy + ry), t(cx + rx, cy - ry)], fill=255))

    def lines(self, pts, width):
        xs = [q[0] for q in pts]
        ys = [q[1] for q in pts]
        wpx = max(1, int(round(width * self.ppm)))
        return self._pil((min(xs) - width, min(ys) - width, max(xs) + width, max(ys) + width),
                         lambda d, t: d.line([t(*q) for q in pts], fill=255, width=wpx, joint='curve'))

    def text_mask(self, text, fname, cap_h, cx, cy, max_w=None, track=0.0):
        """Chữ canh giữa tại (cx, cy); [cap_h] chiều cao chữ hoa (m)."""
        text = vn(text)
        px = cap_h * self.ppm / 0.72
        f = font(fname, px)
        bb = f.getbbox(text)
        tw = bb[2] - bb[0]
        if max_w is not None and tw > max_w * self.ppm:
            f = font(fname, px * max_w * self.ppm / tw)
            bb = f.getbbox(text)
            tw = bb[2] - bb[0]
        th = bb[3] - bb[1]
        wm, hm_ = tw / self.ppm, th / self.ppm
        return self._pil((cx - wm / 2 - 0.05, cy - hm_ / 2 - 0.05, cx + wm / 2 + 0.05, cy + hm_ / 2 + 0.05),
                         lambda d, t: d.text((t(cx, cy)[0] - tw / 2 - bb[0], t(cx, cy)[1] - th / 2 - bb[1]), text,
                                             font=f, fill=255))

    # ------------------------------------------------------------- tô
    def paint(self, sm, col, h=None, mat=None, unlit=None, hadd=None, cover=True, thick=None):
        """Tô vùng [sm] = (slice, mặt nạ). [col]: màu tuyến tính (3,), mảng
        (h, w, 3) hoặc hàm (X, Y) → mảng. [h]: độ nhô (số hoặc mảng hoặc
        hàm). [unlit]: màu không chịu nắng (kính, lòng nhà)."""
        sl, m = sm
        if sl is None:
            return
        X = Y = None
        if callable(col) or callable(h) or callable(unlit):
            X, Y = self.grid(sl)
        c = col(X, Y) if callable(col) else np.broadcast_to(np.asarray(col, np.float64), m.shape + (3,))
        mm = m[..., None]
        self.alb[sl] = self.alb[sl] * (1 - mm) + c * mm
        if cover:
            self.a[sl] = np.maximum(self.a[sl], m)
        if h is not None:
            hv = h(X, Y) if callable(h) else h
            self.hm[sl] = self.hm[sl] * (1 - m) + hv * m
            # vật dày [thick] lơ lửng trước tường thì bóng đổ là hình chiếu,
            # không phải khối kéo dài tới tường
            lo = (hv - thick) if thick is not None else -50.0
            self.hlo[sl] = np.where(m > 0.5, lo, self.hlo[sl])
        if hadd is not None:
            self.hm[sl] = self.hm[sl] + (hadd(X, Y) if callable(hadd) else hadd) * m
        if mat is not None:
            self.mat[sl] = np.where(m > 0.5, mat, self.mat[sl])
        if unlit is not None:
            uc = unlit(X, Y) if callable(unlit) else np.broadcast_to(np.asarray(unlit, np.float64), m.shape + (3,))
            self.unlit[sl] = self.unlit[sl] * (1 - mm) + uc * mm
            self.u[sl] = self.u[sl] * (1 - m) + m
        else:
            self.u[sl] = self.u[sl] * (1 - m)

    def tex_noise(self, X, Y, sx, sy, seed, octaves=3):
        return fbm(X * sx, Y * sy, seed=seed + self.seed * 17, octaves=octaves)

    # -------------------------------------------------------- phong hoá
    def weather(self, amount=1.0, splash=1.0, seed=0):
        """Vệt nước mưa chảy dưới mọi gờ nhô (bậu cửa, ban công, mái hắt),
        loang ố, rêu và bùn bắn chân tường. Chỉ áp lên tường vữa."""
        wall = (self.mat == M_WALL).astype(np.float64)
        hm = self.hm
        above = np.vstack([np.full((1, self.W), -1.0), hm[:-1]])
        src = np.clip((above - hm) * 6, 0, 1) * np.maximum(wall, 0.5 * (self.mat == M_TRIM))
        # mép trên tường (đỉnh tường chắn mái)
        a_above = np.vstack([np.zeros((1, self.W)), self.a[:-1]])
        src = np.maximum(src, np.clip(self.a - a_above, 0, 1) * wall)
        decay = math.exp(-1.0 / (1.6 * self.ppm))
        streak = np.zeros_like(src)
        cur = np.zeros(self.W)
        for r in range(self.H):
            cur = np.maximum(src[r], cur * decay) * np.where(wall[r] > 0.5, 1.0, 0.94)
            streak[r] = cur
        X = (np.arange(self.W) + 0.5) / self.ppm
        cols = fbm(X * 7, np.full_like(X, 3.3), seed=seed + 5, octaves=4)
        cols = smoothstep(0.3, 0.75, cols)[None, :]
        Xg, Yg = np.meshgrid(X, self.h - (np.arange(self.H) + 0.5) / self.ppm)
        brk = 0.6 + 0.4 * fbm(Xg * 9, Yg * 0.8, seed=seed + 9, octaves=3)
        s = streak * cols * brk * amount
        dirt = lin((70, 66, 58))
        wall_t = wall + 0.5 * (self.mat == M_TRIM)
        self.alb = self.alb * (1 - 0.55 * s[..., None] * wall_t[..., None]) + dirt * 0.15 * (s * wall_t)[..., None]
        # bẩn chung: dưới thấp và trên đỉnh tường sẫm hơn
        g = 0.12 * (fbm(Xg * 0.7, Yg * 0.5, seed=seed + 13, octaves=3) - 0.3) * amount
        self.alb = self.alb * (1 - np.clip(g, 0, 1)[..., None] * wall[..., None])
        # chân tường: bùn bắn, rêu xanh đen
        sp = smoothstep(0.9, 0.0, Yg) * (0.6 + 0.4 * fbm(Xg * 5, Yg * 9, seed=seed + 2, octaves=3)) * splash
        moss = lin((60, 66, 48))
        k = (0.45 * sp * wall)[..., None]
        self.alb = self.alb * (1 - k) + moss * k * 0.6

    # ------------------------------------------------------------- ánh sáng
    def render(self, exposure=1.0):
        ss = self.ss
        hm = np.where(self.a > 0.02, self.hm, -20.0)
        # pháp tuyến từ bản đồ cao (làm mượt 1 px để mép vát mềm)
        hb = gblur(np.where(self.a > 0.02, self.hm, 0.0), 0.7)
        gy, gx = np.gradient(hb)
        dhdx = gx * self.ppm
        dhdy = -gy * self.ppm
        dhdx = np.clip(dhdx, -6, 6)
        dhdy = np.clip(dhdy, -6, 6)
        nn = np.stack([-dhdx, -dhdy, np.ones_like(dhdx)], -1)
        nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
        ndl = np.clip(nn @ F_SUN, 0, 1)
        # bóng đổ: tính ở độ phân giải cuối rồi phóng lại
        hs = hm.reshape(self.H // ss, ss, self.W // ss, ss).max(axis=(1, 3))
        hl = np.where(self.a > 0.02, self.hlo, -50.0).reshape(self.H // ss, ss, self.W // ss, ss).min(axis=(1, 3))
        hs_h = hs.copy()
        lp = math.hypot(F_SUN[0], F_SUN[1])
        ux, uy = F_SUN[0] / lp, -F_SUN[1] / lp
        rise = F_SUN[2] / lp
        span = float(np.max(hs_h) - np.min(np.where(hs_h > -19, hs_h, 0)))
        K = int(min(span / rise, 2.6) * self.ppm_f) + 2
        occ = np.zeros_like(hs)
        Hh, Ww = hs.shape
        pad = K + 2
        hp = np.pad(hs, pad, constant_values=-20.0)
        lp_ = np.pad(hl, pad, constant_values=-50.0)
        for k in range(1, K + 1):
            dx = int(round(k * ux))
            dy = int(round(k * uy))
            sh = hp[pad + dy:pad + dy + Hh, pad + dx:pad + dx + Ww]
            sl_ = lp_[pad + dy:pad + dy + Hh, pad + dx:pad + dx + Ww]
            dist = k / self.ppm_f
            zr = hs + dist * rise
            soft = 0.025 + dist * 0.12
            o = np.minimum((sh - zr) / soft, (zr - sl_) / soft)
            np.maximum(occ, o, out=occ)
        shadow = 1 - np.clip(occ, 0, 1)
        shadow = np.repeat(np.repeat(shadow, ss, 0), ss, 1)
        shadow = gblur(shadow, 0.6 * ss)
        # che khuất môi trường: chỗ lõm so với xung quanh thì tối
        cov = (self.a > 0.02).astype(np.float64)
        h0 = np.where(cov > 0, self.hm, 0.0)
        small = h0.reshape(self.H // ss, ss, self.W // ss, ss).mean(axis=(1, 3))
        cs = cov.reshape(self.H // ss, ss, self.W // ss, ss).mean(axis=(1, 3))
        # trung bình có trọng số độ phủ: nền trong suốt không tính là "tường"
        b1 = gblur(small * cs, 0.12 * self.ppm_f) / np.maximum(gblur(cs, 0.12 * self.ppm_f), 1e-3)
        b2 = gblur(small * cs, 0.45 * self.ppm_f) / np.maximum(gblur(cs, 0.45 * self.ppm_f), 1e-3)
        occl = np.clip(b1 - small, 0, None) * 2.2 + np.clip(b2 - small, 0, None) * 0.9
        ao = np.clip(1 - occl, 0.25, 1)
        ao = np.repeat(np.repeat(ao, ss, 0), ss, 1)
        skyf = 0.8 + 0.2 * nn[..., 1]
        E = F_SUN_E * (ndl * shadow)[..., None] / F_SUN[2] * 0.72 + F_AMB[None, None, :] * (ao * skyf)[..., None]
        lit = self.alb * E
        unl = self.unlit * (0.55 + 0.45 * shadow)[..., None] * (0.6 + 0.4 * ao)[..., None]
        col = lit * (1 - self.u[..., None]) + unl * self.u[..., None]
        srgb = np.clip(col * exposure, 0, 1) ** (1 / 2.2)
        rgba = np.concatenate([srgb, self.a[..., None]], -1)
        prem = rgba.copy()
        prem[..., :3] *= prem[..., 3:4]
        sm = downsample(prem, ss)
        al = sm[..., 3:4]
        rgb = np.where(al > 1e-4, sm[..., :3] / np.maximum(al, 1e-4), 0)
        out = np.concatenate([rgb, al], -1)
        return Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')


# ---------------------------------------------------------- Vật liệu phẳng
def plaster_fn(f, rgb, seed, rough=1.0, peel=0.0, repaint=0.0):
    """Tường vữa sơn nước: loang màu, sần, mảng sơn lại, chỗ bong lộ vữa xám."""
    base = lin(rgb)

    def fn(X, Y):
        n1 = fbm(X * 0.9, Y * 0.9, seed=seed, octaves=4)
        n2 = fbm(X * 7, Y * 7, seed=seed + 3, octaves=3)
        n3 = fbm(X * 30, Y * 30, seed=seed + 6, octaves=2)
        c = base[None, None, :] * (0.86 + 0.26 * n1 * rough)[..., None] * (0.95 + 0.1 * n2)[..., None] * \
            (0.97 + 0.06 * n3)[..., None]
        if repaint > 0:
            # mảng sơn dặm lại hơi lệch màu, hình chữ nhật méo
            rp = smoothstep(0.62, 0.64, fbm(np.floor(X * 1.2) * 0.7, np.floor(Y * 1.6) * 0.7, seed=seed + 9, octaves=1))
            c = c * (1 + repaint * 0.08 * rp)[..., None] * np.array([1.0, 1.0, 0.97])
        if peel > 0:
            pm = smoothstep(0.7, 0.73, fbm(X * 2.2, Y * 2.2, seed=seed + 11, octaves=4) + 0.08 * n3) * peel
            cem = lin((150, 146, 136)) * (0.85 + 0.3 * n2)[..., None]
            c = c * (1 - pm[..., None]) + cem * pm[..., None]
        return c
    return fn


def glass_fn(seed, x0, y0, x1, y1, curtain=None, dark=1.0):
    """Kính cửa sổ ban ngày: trong nhà tối, phản chiếu trời sáng phía trên và
    hàng cây / nhà đối diện tối phía dưới, có rèm (nếu có)."""
    def fn(X, Y):
        t = np.clip((Y - y0) / max(y1 - y0, 1e-3), 0, 1)
        sky = np.array([0.42, 0.50, 0.62])
        hor = fbm(X * 1.5, np.full_like(X, 2.0), seed=seed, octaves=3) * 0.5 + 0.05
        refl_dark = np.array([0.05, 0.06, 0.055])
        refl = sky[None, None, :] * smoothstep(hor - 0.08, hor + 0.08, t)[..., None] + \
            refl_dark[None, None, :] * (1 - smoothstep(hor - 0.08, hor + 0.08, t))[..., None]
        inside = np.array([0.012, 0.012, 0.013]) * dark
        c = inside[None, None, :] + refl * 0.38
        if curtain is not None:
            cm = smoothstep(0.35, 0.5, fbm(X * 2, Y * 0.4, seed=seed + 4, octaves=2))
            cc = lin(curtain) * 0.22 * (0.7 + 0.3 * np.cos(X * 40))[..., None]
            c = c * (1 - 0.7 * cm[..., None]) + (cc + refl * 0.35) * 0.7 * cm[..., None]
        return c
    return fn


# ---------------------------------------------------------- Chi tiết nhà
def louver_h(base, period=0.055, depth=0.025):
    """Độ nhô dạng lá sách (cửa chớp): mỗi nan nghiêng một chút."""
    return lambda X, Y: base + depth * (np.mod(Y, period) / period)


def window(f, x0, y0, x1, y1, frame=(214, 214, 206), grille=None, shutter=None, shutter_open=True, lintel=True,
           sill=True, curtain=None, recess=0.12, panes=2, wall_rgb=None, seed=0):
    """Cửa sổ: ô lõm, khung, kính phản chiếu; tuỳ chọn cửa chớp gỗ, khung
    sắt bảo vệ, ô văng che mưa phía trên, bậu cửa phía dưới."""
    w = x1 - x0
    f.paint(f.rect(x0, y0, x1, y1), lin((126, 122, 114)), h=-recess, mat=M_TRIM)
    fw = 0.05
    f.paint(f.rect(x0 + 0.02, y0 + 0.02, x1 - 0.02, y1 - 0.02), lin(frame), h=-recess + 0.03, mat=M_METAL)
    for i in range(panes):
        a = x0 + 0.02 + fw + i * (w - 0.04 - fw) / panes
        b = x0 + 0.02 + (i + 1) * (w - 0.04 - fw) / panes
        top_split = y1 - 0.02 - fw - 0.3 if (y1 - y0) > 1.2 else None
        if top_split:
            f.paint(f.rect(a, top_split + fw, b, y1 - 0.02 - fw), lin((10, 10, 10)), h=-recess,
                    unlit=glass_fn(seed + i + 7, a, top_split, b, y1), mat=M_GLASS)
        f.paint(f.rect(a, y0 + 0.02 + fw, b, top_split or (y1 - 0.02 - fw)), lin((10, 10, 10)), h=-recess,
                unlit=glass_fn(seed + i, a, y0, b, y1, curtain=curtain), mat=M_GLASS)
    if shutter is not None:
        sc = lin(shutter)
        if shutter_open:
            for (a, b) in ((x0 - w / 2, x0), (x1, x1 + w / 2)):
                f.paint(f.rect(a + 0.01, y0, b - 0.01, y1), sc, h=louver_h(0.03), mat=M_WOOD)
                f.paint(f.rect(a + 0.01, y0, b - 0.01, y1), sc * 0.9, h=None)
                for xx in (a + 0.01, b - 0.06):
                    f.paint(f.rect(xx, y0, xx + 0.05, y1), sc * 0.95, h=0.05)
        else:
            f.paint(f.rect(x0 + 0.03, y0 + 0.03, x1 - 0.03, y1 - 0.03), sc, h=louver_h(-recess + 0.04), mat=M_WOOD)
            f.paint(f.rect((x0 + x1) / 2 - 0.02, y0, (x0 + x1) / 2 + 0.02, y1), sc * 0.8, h=-recess + 0.07)
    if grille is not None:
        gc = lin(grille)
        bw = 0.016
        n = max(2, int(w / 0.12))
        for i in range(1, n):
            xx = x0 + i * w / n
            f.paint(f.rect(xx - bw / 2, y0, xx + bw / 2, y1), gc, h=0.04, mat=M_METAL)
        for yy in (y0 + 0.03, y0 + (y1 - y0) * 0.36, y0 + (y1 - y0) * 0.68, y1 - 0.03):
            f.paint(f.rect(x0, yy - bw / 2, x1, yy + bw / 2), gc, h=0.045, mat=M_METAL)
        # hoa văn vòng tròn giữa hai thanh ngang
        r = (y1 - y0) * 0.14
        for i in range(n):
            cx = x0 + (i + 0.5) * w / n
            cy = y0 + (y1 - y0) * 0.52
            rr = min(r, w / n * 0.42)
            sm_out = f.ellipse(cx, cy, rr, rr)
            sm_in = f.ellipse(cx, cy, rr - bw, rr - bw)
            if sm_out[0] is not None and sm_in[0] is not None and sm_out[0] == sm_in[0]:
                f.paint((sm_out[0], np.clip(sm_out[1] - sm_in[1], 0, 1)), gc, h=0.045, mat=M_METAL)
    if sill:
        sc = lin(wall_rgb) * 1.05 if wall_rgb else lin((200, 196, 186))
        f.paint(f.rect(x0 - 0.06, y0 - 0.07, x1 + 0.06, y0), sc, h=0.07, mat=M_TRIM)
    if lintel:
        sc = lin(wall_rgb) if wall_rgb else lin((200, 196, 186))
        f.paint(f.rect(x0 - 0.16, y1 + 0.02, x1 + 0.16, y1 + 0.11), sc, h=0.42, mat=M_TRIM)


def door(f, x0, y0, x1, y1, style='glass', col=(150, 96, 60), seed=0):
    """Cửa đi: gỗ pano, nhôm kính hay cửa xếp sắt."""
    f.paint(f.rect(x0 - 0.04, y0, x1 + 0.04, y1 + 0.04), lin((120, 116, 108)), h=-0.14, mat=M_TRIM)
    w = x1 - x0
    if style == 'wood':
        c = lin(col)

        def wood(k):
            return lambda X, Y: c[None, None, :] * k * (0.82 + 0.3 * fbm(X * 4, Y * 30, seed=seed, octaves=3))[..., None]
        f.paint(f.rect(x0, y0, x1, y1), wood(1.0), h=-0.12, mat=M_WOOD)
        n = 4 if w > 1.4 else 2
        for i in range(n):
            a = x0 + i * w / n + 0.07
            b = x0 + (i + 1) * w / n - 0.07
            for (p0, p1) in ((y0 + 0.15, y0 + (y1 - y0) * 0.42), (y0 + (y1 - y0) * 0.5, y1 - 0.15)):
                f.paint(f.rect(a, p0, b, p1), wood(0.8), h=-0.14)
                f.paint(f.rect(a + 0.035, p0 + 0.035, b - 0.035, p1 - 0.035), wood(0.95),
                        h=lambda X, Y, a=a, b=b, p0=p0, p1=p1: -0.135 + 0.012 * np.minimum(
                            np.minimum(X - a, b - X), np.minimum(Y - p0, p1 - Y)) / 0.1)
            f.paint(f.rect(x0 + (i + 1) * w / n - 0.008, y0, x0 + (i + 1) * w / n + 0.008, y1), c * 0.4, h=-0.13)
    elif style == 'glass':
        fc = lin((60, 58, 56))
        f.paint(f.rect(x0, y0, x1, y1), fc, h=-0.1, mat=M_METAL)
        n = 4 if w > 1.4 else 2
        for i in range(n):
            a = x0 + i * w / n + 0.05
            b = x0 + (i + 1) * w / n - 0.05
            f.paint(f.rect(a, y0 + 0.12, b, y1 - 0.05), lin((8, 8, 8)), h=-0.11,
                    unlit=glass_fn(seed + i, a, y0, b, y1, curtain=(220, 200, 170) if i % 2 == 0 else None), mat=M_GLASS)
    elif style == 'folding':
        c = lin(col)
        f.paint(f.rect(x0, y0, x1, y1), lin((14, 14, 14)), h=-0.2, unlit=lambda X, Y: np.full(X.shape + (3,), 0.012))
        n = int(w / 0.09)
        for i in range(n + 1):
            xx = x0 + i * w / n
            f.paint(f.rect(xx - 0.012, y0, xx + 0.012, y1), c, h=-0.05, mat=M_METAL)
        for k in range(int((y1 - y0) / 0.35) + 1):
            yy = y0 + k * 0.35
            pts = []
            for i in range(n + 1):
                pts.append((x0 + i * w / n, yy + (0.08 if i % 2 else 0)))
            f.paint(f.lines(pts, 0.012), c * 0.9, h=-0.06, mat=M_METAL)
        f.paint(f.rect(x0, y1 - 0.08, x1, y1), c * 0.8, h=-0.04)


def interior(f, x0, y0, x1, y1, kind, seed=0, light=1.0):
    """Lòng cửa hàng tối nhìn từ ngoài nắng: kệ hàng, đồ đạc mờ trong bóng,
    đèn tuýp trên trần. Vẽ bằng PIL rồi đưa vào lớp không chịu nắng."""
    rng = np.random.default_rng(seed)
    sl = f.box(x0, y0, x1, y1, pad=0)
    hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
    p = f.ppm
    im = Image.new('RGB', (ww, hh), (34, 32, 30))
    d = ImageDraw.Draw(im)

    def R(a, b, c, e, col):
        # toạ độ m tương đối góc dưới trái vùng
        d.rectangle([a * p, hh - max(c, e) * p, b * p, hh - min(c, e) * p], fill=tuple(int(v) for v in col))
    W_, H_ = x1 - x0, y1 - y0
    # tường sau + sàn gạch
    for k in range(12):
        t = k / 11
        R(0, W_, H_ * (1 - (k + 1) / 12), H_ * (1 - k / 12), (40 - 14 * t, 38 - 13 * t, 35 - 12 * t))
    R(0, W_, 0, 0.35, (70, 66, 60))
    for i in range(int(W_ / 0.4) + 1):
        R(i * 0.4, i * 0.4 + 0.01, 0, 0.35, (50, 48, 44))
    if kind == 'grocery':
        for row in range(4):
            yb = 0.45 + row * 0.5
            R(0.1, W_ - 0.1, yb - 0.04, yb, (90, 80, 66))
            x = 0.12
            while x < W_ - 0.2:
                bw = rng.uniform(0.08, 0.26)
                bh = rng.uniform(0.18, 0.42)
                col = [(200, 40, 40), (240, 200, 60), (40, 90, 170), (60, 140, 70), (230, 230, 220), (220, 120, 40),
                       (160, 30, 90)][int(rng.integers(0, 7))]
                R(x, x + bw, yb, yb + bh, [c * rng.uniform(0.45, 0.75) for c in col])
                x += bw + 0.02
        # tủ kính quầy hàng phía trước
        R(0.0, W_ * 0.45, 0.0, 0.95, (64, 70, 74))
        R(0.05, W_ * 0.45 - 0.05, 0.25, 0.9, (88, 96, 100))
        for k in range(10):
            R(0.08 + k * 0.17, 0.08 + k * 0.17 + 0.12, 0.3, 0.45, [(210, 60, 50), (230, 190, 70), (70, 120, 200)][k % 3])
        # thùng bia, két nước xếp ngoài
        for k in range(3):
            R(W_ * 0.6 + k * 0.42, W_ * 0.6 + k * 0.42 + 0.4, 0, 0.3 + 0.28 * (k % 2), (170, 40, 36))
    elif kind == 'food':
        R(0.2, W_ - 0.2, 1.5, 2.2, (140, 120, 90))  # bảng thực đơn
        for k in range(5):
            R(0.3, W_ - 0.3, 2.1 - k * 0.12, 2.1 - k * 0.12 + 0.03, (60, 40, 30))
        for k in range(3):
            cx = 0.5 + k * (W_ - 1.0) / 2
            R(cx - 0.4, cx + 0.4, 0.62, 0.68, (180, 170, 150))
            R(cx - 0.36, cx - 0.32, 0, 0.62, (120, 110, 100))
            R(cx + 0.32, cx + 0.36, 0, 0.62, (120, 110, 100))
            for sx in (-0.55, 0.45):
                R(cx + sx, cx + sx + 0.2, 0, 0.42, (200, 50, 40) if k % 2 == 0 else (40, 90, 170))
        # nồi nước dùng to ở cửa
        d.ellipse([W_ * 0.75 * p, hh - 1.2 * p, (W_ * 0.75 + 0.6) * p, hh - 0.75 * p], fill=(150, 150, 150))
        R(W_ * 0.75, W_ * 0.75 + 0.6, 0.0, 0.95, (130, 130, 128))
    elif kind == 'repair':
        R(0, W_, 0, 0.35, (40, 38, 34))
        for k in range(int(W_ / 0.55)):
            cx = 0.35 + k * 0.55
            d.ellipse([(cx - 0.25) * p, hh - 2.3 * p, (cx + 0.25) * p, hh - 1.8 * p], fill=(22, 22, 22))
            d.ellipse([(cx - 0.12) * p, hh - 2.17 * p, (cx + 0.12) * p, hh - 1.93 * p], fill=(44, 42, 40))
        # xe máy đang sửa (bóng tối)
        d.ellipse([0.4 * p, hh - 0.62 * p, 1.0 * p, hh - 0.02 * p], fill=(16, 16, 16))
        d.ellipse([1.5 * p, hh - 0.62 * p, 2.1 * p, hh - 0.02 * p], fill=(16, 16, 16))
        d.polygon([(0.7 * p, hh - 0.55 * p), (1.1 * p, hh - 0.95 * p), (1.7 * p, hh - 0.9 * p),
                   (1.9 * p, hh - 0.5 * p)], fill=(120, 30, 30))
        R(W_ - 1.2, W_ - 0.2, 0.0, 0.85, (70, 60, 52))
        for k in range(6):
            R(W_ - 1.15 + k * 0.16, W_ - 1.15 + k * 0.16 + 0.05, 0.9, 1.2, (110, 110, 112))
    elif kind == 'phone':
        R(0.1, W_ - 0.1, 0.0, 1.0, (70, 76, 80))
        R(0.15, W_ - 0.15, 0.55, 0.95, (200, 210, 214))
        for k in range(int((W_ - 0.4) / 0.18)):
            R(0.22 + k * 0.18, 0.22 + k * 0.18 + 0.1, 0.62, 0.82, (30, 30, 34))
        for k in range(3):
            R(0.3 + k * (W_ - 0.6) / 3, 0.3 + (k + 0.8) * (W_ - 0.6) / 3, 1.5, 2.3,
              [(230, 80, 40), (40, 120, 200), (240, 200, 40)][k])
    elif kind == 'hotel':
        R(0.3, W_ * 0.5, 0, 1.05, (120, 80, 50))
        R(0.3, W_ * 0.5, 1.0, 1.1, (150, 110, 70))
        R(W_ * 0.6, W_ - 0.3, 0.0, 2.4, (54, 46, 40))
        R(0.4, 1.0, 1.6, 2.2, (160, 140, 90))
    elif kind == 'material':
        for k in range(5):
            for j in range(3):
                R(0.2 + k * 0.62, 0.2 + k * 0.62 + 0.58, j * 0.22, j * 0.22 + 0.2, (190, 184, 170))
        for k in range(8):
            R(0.1, W_ - 0.4, 1.0 + k * 0.08, 1.0 + k * 0.08 + 0.06, (200, 200, 196) if k % 2 else (70, 110, 160))
        for k in range(4):
            R(W_ - 0.35, W_ - 0.1, 0.0, 1.8, (150, 100, 70))
    a = lin(np.asarray(im, np.float64)) * 0.22 * light
    # đèn tuýp trần
    yy = np.linspace(H_, 0, hh)[:, None]
    xx = np.linspace(0, W_, ww)[None, :]
    lamp = np.exp(-((yy - (H_ - 0.18)) / 0.05) ** 2) * (np.abs(xx - W_ * 0.5) < W_ * 0.3) * 3.0
    glow = np.exp(-((yy - (H_ - 0.18)) / 0.6) ** 2) * 0.05
    a = a + (lamp + glow)[..., None] * np.array([0.9, 0.95, 1.0]) * light
    # sâu vào trong tối dần ở mép trên (bóng của sàn tầng trên)
    a = a * (0.55 + 0.45 * smoothstep(H_, H_ * 0.4, yy))[..., None]
    sm = f.rect(x0, y0, x1, y1)
    if sm[0] is not None:
        sub = a[:sm[1].shape[0], :sm[1].shape[1]]
        if sub.shape[:2] != sm[1].shape:
            sub = np.pad(sub, ((0, sm[1].shape[0] - sub.shape[0]), (0, sm[1].shape[1] - sub.shape[1]), (0, 0)),
                         mode='edge')
        f.paint(sm, lin((10, 10, 10)), h=-1.5, unlit=sub, mat=M_GLASS)


def roller_shutter(f, x0, x1, y_bottom, y_top, col=(118, 126, 132), seed=0):
    """Cửa cuốn kéo lên một phần: lá thép gợn ngang, gỉ và bụi."""
    c = lin(col)

    def colfn(X, Y):
        n = fbm(X * 2, Y * 6, seed=seed, octaves=3)
        rust = smoothstep(0.62, 0.8, fbm(X * 5, Y * 1.5, seed=seed + 3, octaves=3))
        base = c[None, None, :] * (0.85 + 0.25 * n)[..., None]
        return base * (1 - 0.5 * rust[..., None]) + lin((120, 70, 40)) * 0.5 * rust[..., None]
    f.paint(f.rect(x0, y_bottom, x1, y_top), colfn, h=lambda X, Y: 0.02 + 0.012 * np.sin(Y * math.tau / 0.075),
            mat=M_METAL)
    f.paint(f.rect(x0, y_bottom, x1, y_bottom + 0.06), c * 0.6, h=0.04)
    # tay nắm
    for xx in (x0 + (x1 - x0) * 0.3, x0 + (x1 - x0) * 0.7):
        f.paint(f.rect(xx - 0.06, y_bottom + 0.02, xx + 0.06, y_bottom + 0.05), lin((60, 60, 60)), h=0.06)


def signboard(f, x0, y0, x1, y1, text, sub=None, bg=(24, 72, 160), fg=(255, 255, 255), sub_fg=None, h=0.22,
              border=(240, 200, 60), fname='paytone', seed=0, phone=None):
    """Biển hiệu tôn / bạt in: nền màu, viền, chữ chính to, dòng phụ nhỏ,
    phai màu và bụi bám mép dưới."""
    bgc = lin(bg)

    def bgfn(X, Y):
        t = (Y - y0) / max(y1 - y0, 1e-3)
        n = fbm(X * 3, Y * 3, seed=seed, octaves=3)
        dust = smoothstep(0.35, 0.0, t) * 0.25
        return bgc[None, None, :] * (0.9 + 0.12 * t + 0.1 * n)[..., None] * (1 - dust)[..., None]
    for k in range(2):
        bx = x0 + (x1 - x0) * (0.2 + 0.6 * k)
        f.paint(f.rect(bx - 0.03, y1, bx + 0.03, y1 + 0.18), lin((70, 70, 72)), h=h * 0.6, mat=M_METAL)
    f.paint(f.rect(x0, y0, x1, y1), bgfn, h=h, mat=M_SIGN)
    if border:
        bc = lin(border)
        for (a, b, c, d) in ((x0, y1 - 0.04, x1, y1), (x0, y0, x1, y0 + 0.04), (x0, y0, x0 + 0.04, y1),
                             (x1 - 0.04, y0, x1, y1)):
            f.paint(f.rect(a, b, c, d), bc, h=h + 0.01)
    hh = y1 - y0
    cy = y0 + hh * (0.64 if sub else 0.5)
    cap = hh * (0.36 if sub else 0.55)
    tm = f.text_mask(text, fname, cap, (x0 + x1) / 2, cy, max_w=(x1 - x0) * 0.86 - 0.5)
    # viền chữ tối cho nổi
    if tm[0] is not None:
        sl, m = tm
        out = np.clip(gblur(m, 0.06 * f.ppm / 2) * 3, 0, 1)
        f.paint((sl, out * 0.85), bgc * 0.35, h=h)
        # chữ in phản quang: giữ tươi cả khi nằm trong bóng ban công
        f.paint(tm, lin(fg), h=h + 0.004, unlit=lin(fg) * 1.45)
    if sub:
        line = sub if phone is None else f'{sub}  ·  ĐT: {phone}'
        f.paint(f.text_mask(line, 'bold', hh * 0.13, (x0 + x1) / 2, y0 + hh * 0.18, max_w=(x1 - x0) - 0.9),
                lin(sub_fg or fg), h=h + 0.004, unlit=lin(sub_fg or fg) * 1.3)


def leaves_blob(f, cx, cy, rx, ry, leaf_rgb, h0, n=None, leaf=0.06, flowers=None, flower_frac=0.0,
                fruits=None, hang=0.0, seed=0, flower_size=0.03):
    """Đám lá (chậu cây, giàn hoa giấy) vẽ từng lá nhỏ; độ nhô gồ theo
    dạng vòm nên tự đổ sáng ra khối. [hang] > 0: rủ xuống (hoa giấy)."""
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = cx - rx - leaf, cy - ry - leaf - hang, cx + rx + leaf, cy + ry + leaf
    sl = f.box(x0, y0, x1, y1, pad=2)
    if sl is None:
        return
    hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
    im = Image.new('RGB', (ww, hh), (0, 0, 0))
    hi = Image.new('F', (ww, hh), -9.0)
    al = Image.new('L', (ww, hh), 0)
    di, dh, da = ImageDraw.Draw(im), ImageDraw.Draw(hi), ImageDraw.Draw(al)
    p = f.ppm
    ox, oy = sl[1].start, sl[0].start
    if n is None:
        n = int(rx * ry * 4 / (leaf * leaf * 0.35) + hang * rx * 60)
    items = []
    for i in range(n):
        while True:
            u, v = rng.uniform(-1, 1, 2)
            if u * u + v * v < 1:
                break
        x = cx + u * rx
        y = cy + v * ry
        if hang > 0 and rng.uniform() < 0.35:
            y = cy - ry * 0.3 - rng.uniform(0, hang) * (1 - abs(u)) ** 0.5
        dome = math.sqrt(max(0, 1 - u * u - v * v))
        hgt = h0 + 0.25 * min(rx, 0.6) * dome + rng.uniform(0, 0.04)
        kind = 'leaf'
        r_ = rng.uniform()
        if flowers is not None and r_ < flower_frac:
            kind = 'flower'
        elif fruits is not None and r_ < flower_frac + 0.08:
            kind = 'fruit'
        items.append((hgt, x, y, kind))
    items.sort()
    lc = np.array(leaf_rgb, np.float64)
    for hgt, x, y, kind in items:
        px, py = x * p - ox, (f.h - y) * p - oy
        if kind == 'leaf':
            a = rng.uniform(0, math.pi)
            L = leaf * rng.uniform(0.7, 1.2) * p
            W = L * 0.45
            pts = [(px + math.cos(a) * L * c - math.sin(a) * W * s, py + math.sin(a) * L * c + math.cos(a) * W * s)
                   for c, s in ((-0.5, 0), (-0.1, 0.5), (0.5, 0), (-0.1, -0.5))]
            col = tuple(int(np.clip(v, 0, 255)) for v in lc * math.exp(rng.normal(0, 0.18)) * np.array([1, 1 + rng.normal(0, 0.05), 1]))
            di.polygon(pts, fill=col)
            dh.polygon(pts, fill=float(hgt))
            da.polygon(pts, fill=255)
        else:
            r = (flower_size if kind == 'flower' else 0.025) * p * rng.uniform(0.8, 1.2)
            base = flowers if kind == 'flower' else fruits
            col = tuple(int(np.clip(v, 0, 255)) for v in np.array(base) * math.exp(rng.normal(0, 0.1)))
            di.ellipse([px - r, py - r, px + r, py + r], fill=col)
            dh.ellipse([px - r, py - r, px + r, py + r], fill=float(hgt + 0.03))
            da.ellipse([px - r, py - r, px + r, py + r], fill=255)
    m = np.asarray(al, np.float64) / 255
    colarr = lin(np.asarray(im, np.float64))
    harr = np.asarray(hi, np.float64)
    f.paint((sl, m), colarr, h=np.where(m > 0, harr, 0), mat=M_PLANT)


def lantern(f, cx, y_top, r=0.17, h=0.5, string=0.25):
    """Đèn lồng đỏ Tết: dây treo, chóp vàng, thân đỏ có gân, tua rua."""
    f.paint(f.rect(cx - 0.006, y_top - string, cx + 0.006, y_top), lin((40, 30, 20)), h=h, thick=0.02)
    yc = y_top - string - r * 1.05
    f.paint(f.rect(cx - r * 0.45, yc + r * 0.95, cx + r * 0.45, yc + r * 1.12), lin((214, 168, 60)), h=h + 0.04)
    sm = f.ellipse(cx, yc, r, r * 1.0)
    if sm[0] is not None:
        X, Y = f.grid(sm[0])
        u = np.clip((X - cx) / r, -1, 1)
        v = np.clip((Y - yc) / r, -1, 1)
        dome = np.sqrt(np.clip(1 - u * u - v * v, 0, 1))
        ribs = 0.85 + 0.15 * np.cos(np.arcsin(u) * 8) ** 2
        col = lin((206, 24, 22))[None, None, :] * ribs[..., None]
        f.paint(sm, col, h=h + dome * r * 0.9, mat=M_FABRIC, thick=2 * r * 0.9)
    f.paint(f.rect(cx - r * 0.45, yc - r * 1.1, cx + r * 0.45, yc - r * 0.92), lin((214, 168, 60)), h=h + 0.04)
    for k in range(5):
        xx = cx + (k - 2) * r * 0.12
        f.paint(f.rect(xx - 0.006, yc - r * 1.1 - 0.16, xx + 0.006, yc - r * 1.1), lin((196, 30, 26)), h=h + 0.02)


def vn_flag(f, x_pole, y_pole, length=1.9, w=0.9, side=1, h=0.6):
    """Cờ đỏ sao vàng cắm chéo trên cán tre, vải gợn sóng."""
    ang = math.radians(35)
    x_end = x_pole + side * length * math.sin(ang) * 0.35
    y_end = y_pole + length * math.cos(ang)
    f.paint(f.lines([(x_pole, y_pole), (x_end, y_end)], 0.03), lin((150, 130, 90)), h=h, mat=M_WOOD, thick=0.06)
    fx0 = x_end - (0 if side > 0 else w * 1.3)
    fx1 = fx0 + w * 1.3 * 1
    if side < 0:
        fx0, fx1 = x_end - w * 1.3, x_end
    else:
        fx0, fx1 = x_end, x_end + w * 1.3
    fy1 = y_end - 0.03
    fy0 = fy1 - w * 0.85
    sm = f.poly([(fx0, fy1), (fx1, fy1 - 0.12), (fx1, fy0 - 0.12), (fx0, fy0)])
    if sm[0] is not None:
        X, Y = f.grid(sm[0])
        wave = lambda X, Y: h + 0.06 * np.sin((X - fx0) * 7.0) + 0.02 * np.sin((X - fx0) * 17 + Y * 3)
        f.paint(sm, lin((214, 24, 28)), h=wave, mat=M_FABRIC, thick=0.12)
        cx, cy = (fx0 + fx1) / 2, (fy0 + fy1) / 2 - 0.06
        R = w * 0.27
        star = []
        for k in range(10):
            rr = R if k % 2 == 0 else R * 0.382
            a = math.pi / 2 + k * math.pi / 5
            star.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        f.paint(f.poly(star), lin((252, 214, 40)), hadd=0.004)


def banner(f, x0, x1, y0, y1, text, h=0.1, seed=0):
    """Băng rôn vải đỏ chữ vàng."""
    c = lin((196, 22, 26))

    def colfn(X, Y):
        wr = 0.9 + 0.1 * np.sin((X - x0) * 9) * smoothstep(y0, y1, Y)
        return c[None, None, :] * wr[..., None] * (0.95 + 0.1 * fbm(X * 4, Y * 4, seed=seed, octaves=2))[..., None]
    f.paint(f.rect(x0, y0, x1, y1), colfn, h=lambda X, Y: h + 0.015 * np.sin((X - x0) * 9), mat=M_FABRIC)
    f.paint(f.text_mask(text, 'paytone', (y1 - y0) * 0.56, (x0 + x1) / 2, (y0 + y1) / 2, max_w=(x1 - x0) * 0.92),
            lin((250, 212, 64)), hadd=0.003)
    for xx in (x0 + 0.03, x1 - 0.03):
        for yy in (y0 + 0.03, y1 - 0.03):
            f.paint(f.ellipse(xx, yy, 0.025, 0.025), lin((200, 196, 186)), h=h + 0.02)


def pot(f, cx, y0, w, hgt, rgb=(150, 70, 40), h=0.3, band=None):
    """Chậu sành / sứ hình thang, bóng tròn theo bề ngang."""
    sm = f.poly([(cx - w / 2, y0 + hgt), (cx + w / 2, y0 + hgt), (cx + w * 0.36, y0), (cx - w * 0.36, y0)])
    if sm[0] is None:
        return
    X, Y = f.grid(sm[0])
    u = np.clip((X - cx) / (w / 2), -1, 1)
    c = lin(rgb)
    col = c[None, None, :] * np.ones(X.shape + (1,))
    if band:
        bm = ((Y > y0 + hgt * 0.62) & (Y < y0 + hgt * 0.8))[..., None]
        col = np.where(bm, lin(band)[None, None, :], col)
    f.paint(sm, col, h=h + np.sqrt(np.clip(1 - u * u, 0, 1)) * w * 0.4, mat=M_TRIM)
    f.paint(f.rect(cx - w / 2 - 0.02, y0 + hgt - 0.04, cx + w / 2 + 0.02, y0 + hgt), c * 1.1, h=h + w * 0.42)


def kumquat_pot(f, cx, y0, s=1.0, h=0.6, seed=0):
    """Chậu quất Tết: tán tròn lá xanh thẫm, quả cam vàng, treo phong bao đỏ."""
    pot(f, cx, y0, 0.55 * s, 0.42 * s, (120, 60, 36), h=h, band=(200, 170, 80))
    leaves_blob(f, cx, y0 + 0.42 * s + 0.45 * s, 0.42 * s, 0.45 * s, (46, 82, 38), h + 0.1, leaf=0.05,
                fruits=(236, 140, 30), flower_frac=0.0, seed=seed)
    leaves_blob(f, cx, y0 + 0.42 * s + 0.45 * s, 0.4 * s, 0.42 * s, (52, 90, 40), h + 0.12, leaf=0.05,
                n=60, fruits=(240, 150, 30), flowers=None, flower_frac=0.0, seed=seed + 1)
    rng = np.random.default_rng(seed)
    for k in range(int(rng.integers(14, 22))):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, 0.38 * s)
        x, y = cx + math.cos(a) * r, y0 + 0.87 * s + math.sin(a) * r
        f.paint(f.ellipse(x, y, 0.028 * s, 0.028 * s), lin((240, 140, 28)), h=h + 0.3)
    for k in range(5):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.1, 0.35 * s)
        x, y = cx + math.cos(a) * r, y0 + 0.85 * s + math.sin(a) * r
        f.paint(f.rect(x - 0.03, y - 0.09, x + 0.03, y), lin((200, 24, 30)), h=h + 0.32)
        f.paint(f.rect(x - 0.012, y - 0.06, x + 0.012, y - 0.035), lin((230, 190, 70)), hadd=0.003)


def peach_pot(f, cx, y0, s=1.0, h=0.6, seed=0):
    """Cành đào cắm chậu: cành nâu đen khẳng khiu, hoa hồng chi chít."""
    rng = np.random.default_rng(seed)
    pot(f, cx, y0, 0.5 * s, 0.4 * s, (60, 90, 120), h=h, band=(220, 214, 196))
    tips = []

    def branch(x, y, a, L, wdt, depth):
        x2, y2 = x + math.cos(a) * L, y + math.sin(a) * L
        f.paint(f.lines([(x, y), (x2, y2)], wdt), lin((60, 46, 40)), h=h + 0.15, mat=M_WOOD)
        tips.append((x2, y2))
        tips.append(((x + x2) / 2, (y + y2) / 2))
        if depth > 0:
            for da in (-0.5, 0.45):
                branch(x2, y2, a + da + rng.normal(0, 0.2), L * 0.68, wdt * 0.65, depth - 1)
    branch(cx, y0 + 0.4 * s, math.pi / 2 + rng.normal(0, 0.1), 0.55 * s, 0.035 * s, 3)
    for (x, y) in tips:
        for k in range(6):
            fx, fy = x + rng.normal(0, 0.06), y + rng.normal(0, 0.06)
            f.paint(f.ellipse(fx, fy, 0.025, 0.025), lin((240, 150, 172)) * math.exp(rng.normal(0, 0.1)),
                    h=h + 0.2 + rng.uniform(0, 0.05), mat=M_PLANT)


def ac_unit(f, cx, cy, h=0.38):
    """Cục nóng điều hoà treo tường: vỏ trắng ngà, lưới quạt tròn, giá sắt."""
    w, hh = 0.8, 0.55
    for xx in (cx - w * 0.35, cx + w * 0.35):
        f.paint(f.lines([(xx, cy - hh / 2 - 0.02), (xx, cy - hh / 2 - 0.2)], 0.03), lin((80, 80, 80)), h=h * 0.6)
    f.paint(f.rect(cx - w / 2 - 0.04, cy - hh / 2 - 0.04, cx + w / 2 + 0.04, cy - hh / 2), lin((90, 90, 90)), h=h)
    f.paint(f.rect(cx - w / 2, cy - hh / 2, cx + w / 2, cy + hh / 2), lin((214, 210, 196)), h=h, mat=M_METAL)
    fx = cx - w * 0.12
    for k, r in enumerate(np.linspace(0.22, 0.04, 7)):
        f.paint(f.ellipse(fx, cy, r, r), lin((60, 60, 60)) if k % 2 == 0 else lin((150, 150, 146)), h=h - 0.02)
    for k in range(8):
        yy = cy - hh * 0.35 + k * hh * 0.1
        f.paint(f.rect(cx + w * 0.2, yy, cx + w * 0.44, yy + 0.015), lin((130, 128, 120)), h=h - 0.01)


def water_tank(f, cx, y0, r=0.55, hgt=1.25, h=0.0):
    """Bồn nước inox đứng trên mái: thân trụ sáng bóng có đai, chân sắt."""
    f.paint(f.rect(cx - r * 0.9, y0, cx + r * 0.9, y0 + 0.25), lin((70, 70, 72)), h=h, mat=M_METAL)
    yb = y0 + 0.25
    sm = f.rect(cx - r, yb, cx + r, yb + hgt)
    X, Y = f.grid(sm[0])
    u = np.clip((X - cx) / r, -1, 1)
    refl = 0.35 + 0.5 * np.exp(-((u + 0.35) / 0.18) ** 2) + 0.25 * np.exp(-((u - 0.5) / 0.3) ** 2) - 0.15 * u
    bands = 1 - 0.25 * (np.abs(np.mod(Y - yb, hgt / 4) - hgt / 8) > hgt / 8 - 0.03)
    col = np.array([0.78, 0.8, 0.82])[None, None, :] * (refl * bands)[..., None] * 1.25
    f.paint(sm, col, h=h + np.sqrt(np.clip(1 - u * u, 0, 1)) * r, mat=M_METAL)
    sm = f.ellipse(cx, yb + hgt, r, r * 0.25)
    if sm[0] is not None:
        f.paint(sm, np.array([0.55, 0.57, 0.6]), h=h + r * 0.8)
    f.paint(f.rect(cx - 0.08, yb + hgt + r * 0.2, cx + 0.08, yb + hgt + r * 0.3), lin((60, 60, 60)), h=h + r)


def antenna(f, x, y0, hgt=2.2, h=0.0):
    f.paint(f.lines([(x, y0), (x, y0 + hgt)], 0.025), lin((90, 90, 92)), h=h, mat=M_METAL)
    for k, w in enumerate((0.9, 0.75, 0.6, 0.45)):
        yy = y0 + hgt - 0.1 - k * 0.22
        f.paint(f.lines([(x - w / 2, yy), (x + w / 2, yy)], 0.015), lin((100, 100, 102)), h=h)


def cables(f, x0, x1, ys, h=1.4, sag=0.35, seed=0):
    """Bó dây điện, dây cáp võng ngang mặt nhà (đổ bóng lên tường)."""
    rng = np.random.default_rng(seed)
    for y in ys:
        sg = sag * rng.uniform(0.6, 1.3)
        pts = [(x, y - sg * (1 - ((x - x0) / (x1 - x0) * 2 - 1) ** 2)) for x in np.linspace(x0, x1, 24)]
        f.paint(f.lines(pts, rng.uniform(0.012, 0.03)), lin((20, 20, 22)), h=h + rng.uniform(0, 0.4), cover=True,
                thick=0.04)


def balcony(f, x0, x1, yf, depth=1.0, rail='iron', rail_rgb=(40, 44, 46), slab_rgb=(220, 214, 200), seed=0,
            plants=None):
    """Ban công: mép sàn đúc nhô ra, lan can (sắt hoa / con tiện / tường
    lửng), chậu cây hoa giấy rủ xuống."""
    sc = lin(slab_rgb)
    rc = lin(rail_rgb)
    top = yf + 1.0
    if rail == 'iron':
        f.paint(f.rect(x0, yf + 0.02, x1, yf + 0.1), rc, h=depth - 0.02, mat=M_METAL)
        n = int((x1 - x0) / 0.11)
        for i in range(n + 1):
            xx = x0 + i * (x1 - x0) / n
            f.paint(f.rect(xx - 0.008, yf + 0.05, xx + 0.008, top), rc, h=depth - 0.02, mat=M_METAL)
        # dải hoa văn sóng
        for k in range(2):
            yy = yf + 0.62 + k * 0.12
            pts = [(x, yy + 0.04 * math.sin((x - x0) * 25)) for x in np.linspace(x0, x1, 120)]
            f.paint(f.lines(pts, 0.012), rc, h=depth - 0.015)
        f.paint(f.rect(x0, top - 0.05, x1, top), rc * 1.2, h=depth, mat=M_METAL)
    elif rail == 'baluster':
        f.paint(f.rect(x0, yf, x1, yf + 0.14), sc, h=depth - 0.02, mat=M_TRIM)
        n = int((x1 - x0) / 0.19)
        for i in range(n):
            cx = x0 + (i + 0.5) * (x1 - x0) / n
            prof = [(-0.035, yf + 0.14), (-0.06, yf + 0.3), (-0.04, yf + 0.42), (-0.03, yf + 0.55),
                    (-0.045, yf + 0.72), (-0.04, yf + 0.86)]
            pts = [(cx + a, b) for a, b in prof] + [(cx - a, b) for a, b in prof[::-1]]
            sm = f.poly(pts)
            if sm[0] is None:
                continue
            X, Y = f.grid(sm[0])
            u = np.clip((X - cx) / 0.06, -1, 1)
            f.paint(sm, sc * 0.97, h=depth - 0.06 + 0.06 * np.sqrt(np.clip(1 - u * u, 0, 1)), mat=M_TRIM)
        f.paint(f.rect(x0, top - 0.14, x1, top), sc, h=depth, mat=M_TRIM)
        f.paint(f.rect(x0, top - 0.02, x1, top + 0.02), sc * 1.05, h=depth + 0.04)
    elif rail == 'solid':
        f.paint(f.rect(x0, yf, x1, top), plaster_fn(f, slab_rgb, seed + 3), h=depth, mat=M_WALL)
        f.paint(f.rect(x0, top - 0.06, x1, top + 0.02), sc * 1.05, h=depth + 0.04, mat=M_TRIM)
    # mép sàn
    f.paint(f.rect(x0 - 0.05, yf - 0.16, x1 + 0.05, yf + 0.02), sc, h=depth + 0.05, mat=M_TRIM)
    f.paint(f.rect(x0 - 0.05, yf - 0.16, x1 + 0.05, yf - 0.13), sc * 0.8, h=depth + 0.06)
    if plants:
        for k, (px, kind) in enumerate(plants):
            if kind == 'bougainvillea':
                leaves_blob(f, px, top + 0.15, 0.55, 0.35, (52, 92, 40), depth + 0.1, leaf=0.05,
                            flowers=(212, 40, 128), flower_frac=0.45, hang=1.1, seed=seed + k, flower_size=0.028)
            elif kind == 'green':
                pot(f, px, top - 0.05, 0.32, 0.24, (150, 76, 46), h=depth + 0.05)
                leaves_blob(f, px, top + 0.4, 0.3, 0.25, (60, 104, 44), depth + 0.12, leaf=0.06, seed=seed + k)
            elif kind == 'kumquat':
                kumquat_pot(f, px, top - 0.15, s=0.7, h=depth + 0.05, seed=seed + k)


def parapet(f, x0, x1, y0, y1, wall_rgb, seed, style='plain', trim_rgb=(222, 216, 204)):
    """Tường chắn mái tầng thượng: phẳng, có ô thoáng, hoặc trán tường."""
    f.paint(f.rect(x0, y0, x1, y1), plaster_fn(f, wall_rgb, seed + 21, peel=0.3), h=0.0, mat=M_WALL)
    tc = lin(trim_rgb)
    f.paint(f.rect(x0 - 0.04, y1 - 0.08, x1 + 0.04, y1 + 0.02), tc, h=0.1, mat=M_TRIM)
    f.paint(f.rect(x0 - 0.02, y0, x1 + 0.02, y0 + 0.12), tc, h=0.08, mat=M_TRIM)
    if style == 'vents':
        n = int((x1 - x0) / 0.5)
        for i in range(n):
            a = x0 + 0.15 + i * (x1 - x0 - 0.3) / n
            b = a + (x1 - x0 - 0.3) / n - 0.12
            f.paint(f.rect(a, y0 + 0.3, b, y1 - 0.25), lin((40, 40, 40)), h=-0.15,
                    unlit=lambda X, Y: np.full(X.shape + (3,), 0.25), mat=M_TRIM)
            for k in range(3):
                xx = a + (k + 0.5) * (b - a) / 3
                f.paint(f.rect(xx - 0.03, y0 + 0.3, xx + 0.03, y1 - 0.25), tc * 0.95, h=-0.02)
    elif style == 'pediment':
        cx = (x0 + x1) / 2
        f.paint(f.poly([(x0 + 0.3, y1), (x1 - 0.3, y1), (cx, y1 + 0.75)]), plaster_fn(f, wall_rgb, seed + 22),
                h=0.0, mat=M_WALL)
        f.paint(f.lines([(x0 + 0.25, y1 + 0.02), (cx, y1 + 0.8), (x1 - 0.25, y1 + 0.02)], 0.08), tc, h=0.1,
                mat=M_TRIM)
        f.paint(f.ellipse(cx, y1 + 0.32, 0.17, 0.17), tc * 0.9, h=0.05)


def tile_roof(f, x0, x1, y_eave, y_ridge, inset=0.0, kind='clay', rgb=(166, 84, 54), seed=0, over=0.7,
              depth=2.6, fascia=True):
    """Mái nhìn từ phía trước: mái dốc ra xa nên càng lên cao càng lùi vào
    trong (độ nhô giảm), hàng ngói chồng mí đổ bóng, rêu mốc, bờ nóc."""
    pts = [(x0, y_eave), (x1, y_eave), (x1 - inset, y_ridge), (x0 + inset, y_ridge)]
    sm = f.poly(pts)
    if sm[0] is None:
        return
    rh = y_ridge - y_eave
    base = lin(rgb)
    if kind == 'clay':
        # ngói mũi hài / ngói vảy: hàng ngói chồng mí, mép dưới mỗi viên tròn
        course, tw = 0.1, 0.16

        def tile_uv(X, Y):
            ci = np.floor((Y - y_eave) / course)
            off = np.mod(ci, 2) * 0.5
            fx = np.mod(X / tw + off, 1)
            ti = np.floor(X / tw + off)
            # mép dưới viên ngói cong tròn: dịch hàng theo dạng vòm
            arc = 0.38 * (1 - np.sin(fx * math.pi))
            fr = np.mod((Y - y_eave) / course - arc, 1)
            ci2 = np.floor((Y - y_eave) / course - arc)
            return fx, fr, ci2, ti

        def hfn(X, Y):
            t = (Y - y_eave) / rh
            fx, fr, _, _ = tile_uv(X, Y)
            return over - t * depth + 0.028 * (1 - fr) ** 1.3 + 0.012 * np.sin(fx * math.pi)

        def cfn(X, Y):
            fx, fr, ci, ti = tile_uv(X, Y)
            hsh = np.sin(ci * 12.9898 + ti * 78.233 + seed) * 43758.5453
            hsh = hsh - np.floor(hsh)
            c = base[None, None, :] * (0.8 + 0.34 * hsh)[..., None] * (0.92 + 0.12 * fr)[..., None]
            lich = smoothstep(0.55, 0.78, fbm(X * 2.2, Y * 3.5, seed=seed, octaves=4))
            dark = lin((70, 62, 54))
            c = c * (1 - 0.45 * lich[..., None]) + dark * 0.45 * lich[..., None]
            t = (Y - y_eave) / rh
            moss = smoothstep(0.3, 0.0, t) * 0.3 * fbm(X * 4, Y * 4, seed=seed + 2, octaves=2)
            c = c * (1 - moss[..., None]) + lin((70, 74, 52)) * moss[..., None]
            return c
    else:
        def hfn(X, Y):
            t = (Y - y_eave) / rh
            return over - t * depth + 0.012 * np.sin(X * math.tau / 0.1)

        def cfn(X, Y):
            ridge = 0.5 + 0.5 * np.sin(X * math.tau / 0.1)
            rust = smoothstep(0.5, 0.8, fbm(X * 6, Y * 0.8, seed=seed, octaves=4))
            seam = (np.mod(X, 1.07) < 0.03)[..., None]
            c = base[None, None, :] * (0.85 + 0.25 * ridge)[..., None]
            c = c * (1 - 0.6 * rust[..., None]) + lin((122, 70, 42)) * 0.6 * rust[..., None]
            return np.where(seam, c * 0.8, c)
    f.paint(sm, cfn, h=hfn, mat=M_ROOF)
    # bờ nóc + bờ chảy (mái chéo)
    rc = base * 0.85 if kind == 'clay' else base * 0.7
    f.paint(f.rect(x0 + inset - 0.05, y_ridge - 0.08, x1 - inset + 0.05, y_ridge + 0.1), rc,
            h=over - depth + 0.25, mat=M_ROOF)
    if inset > 0.05:
        for (a, b) in (((x0, y_eave), (x0 + inset, y_ridge)), ((x1, y_eave), (x1 - inset, y_ridge))):
            f.paint(f.lines([a, b], 0.16), rc, h=lambda X, Y: over - (Y - y_eave) / rh * depth + 0.15, mat=M_ROOF)
    if fascia:
        f.paint(f.rect(x0 - 0.05, y_eave - 0.14, x1 + 0.05, y_eave + 0.02),
                lin((200, 196, 186)) if kind == 'clay' else base * 0.8, h=over + 0.05, mat=M_TRIM)


# ---------------------------------------------------------- Nhà ống phố
TOWN = {
    'house_town_1': dict(width=4.5, floors=3, wall=(234, 206, 140), shop='TẠP HOÁ', sub='Bánh kẹo - Bia - Nước ngọt',
                         phone='0912 345 678', bg=(196, 28, 34), fg=(255, 236, 140), interior='grocery', open=0.78,
                         shutter=(120, 128, 136), rails=['iron', 'iron'], rail_rgb=(36, 40, 44), roof='tank',
                         lanterns=2, flag=True, banner=None, pots=['kumquat'], seed=1, door='glass',
                         plants=[[(1.0, 'bougainvillea')], [(3.4, 'green')]]),
    'house_town_2': dict(width=4.2, floors=2, wall=(176, 206, 222), shop='CƠM PHỞ', sub='Cơm bình dân - Phở bò - Bia hơi',
                         phone='0988 246 135', bg=(232, 196, 40), fg=(176, 26, 26), interior='food', open=1.0,
                         shutter=(104, 120, 110), rails=['baluster'], roof='pediment', lanterns=2, flag=False,
                         banner='CHÚC MỪNG NĂM MỚI', pots=['peach'], seed=2, door='wood',
                         plants=[[(3.3, 'bougainvillea')]], awning=(36, 120, 70)),
    'house_town_3': dict(width=4.8, floors=4, wall=(232, 196, 186), shop='NHÀ NGHỈ', sub='Phòng đẹp - Điều hoà - Wifi',
                         phone='0903 111 222', bg=(28, 64, 140), fg=(255, 255, 255), interior='hotel', open=1.0,
                         shutter=(130, 130, 130), rails=['iron', 'glass', 'iron'], rail_rgb=(214, 210, 196),
                         roof='vents', lanterns=2, flag=True, banner=None, pots=['kumquat', 'kumquat'], seed=3,
                         door='glass', glass_front=True, ac=True, plants=[[(4.0, 'green')], [], [(1.0, 'bougainvillea')]]),
    'house_town_4': dict(width=4.4, floors=3, wall=(190, 214, 180), shop='SỬA XE MÁY', sub='Vá xe - Thay nhớt - Rửa xe',
                         phone='0977 868 686', bg=(20, 110, 70), fg=(255, 255, 255), interior='repair', open=1.0,
                         shutter=(96, 100, 104), rails=['iron', 'solid'], rail_rgb=(60, 90, 120), roof='mai_thai',
                         lanterns=0, flag=True, banner=None, pots=[], seed=4, door='folding', grimy=1.6, tires=True,
                         plants=[[(3.2, 'green')], []]),
    'house_town_5': dict(width=4.0, floors=3, wall=(238, 220, 206), shop='ĐIỆN THOẠI - SIM THẺ', sub='Sửa chữa - Phụ kiện - Nạp thẻ',
                         phone='0936 789 012', bg=(234, 92, 28), fg=(255, 255, 255), interior='phone', open=1.0,
                         shutter=(140, 140, 140), rails=['glass', 'iron'], rail_rgb=(50, 50, 52), roof='tank',
                         lanterns=2, flag=False, banner=None, pots=['peach'], seed=5, door='glass', glass_front=True,
                         ac=True, plants=[[], [(2.8, 'bougainvillea')]]),
    'house_town_6': dict(width=5.0, floors=2, wall=(212, 196, 150), shop='VẬT LIỆU XÂY DỰNG', sub='Xi măng - Sắt thép - Gạch ngói',
                         phone='0915 222 333', bg=(30, 60, 130), fg=(255, 220, 60), interior='material', open=1.0,
                         shutter=(110, 110, 112), rails=['solid'], rail_rgb=(60, 60, 60), roof='mai_thai', lanterns=0,
                         flag=True, banner='CHÚC MỪNG NĂM MỚI', pots=[], seed=6, door='wood', grimy=2.0, old=True,
                         plants=[[]], awning=(150, 156, 160)),
}


def tube_house(spec):
    """Nhà ống mặt phố: tầng trệt bán hàng (cửa cuốn kéo lên, lòng nhà tối,
    biển hiệu), các tầng trên có ban công lan can, cửa kính / cửa gỗ, ô văng;
    sân thượng có tường chắn, bồn nước, ăng-ten; trang trí Tết."""
    W = spec['width']
    nf = spec['floors']
    gf = 3.7
    fl = 3.3
    y_top = gf + (nf - 1) * fl
    extra = {'tank': 2.2, 'vents': 1.3, 'pediment': 2.0, 'mai_thai': 1.9}[spec['roof']]
    H = y_top + 1.1 + extra
    ppm = min(75, 900 / H)
    f = Facade(W, H, ppm, ss=2, seed=spec['seed'])
    sd = spec['seed'] * 31
    wall_rgb = spec['wall']
    old = spec.get('old', False)
    f.paint(f.rect(0, 0, W, y_top + 1.1), plaster_fn(f, wall_rgb, sd, peel=0.6 if old else 0.15, repaint=1.0),
            h=0.0, mat=M_WALL)
    # mép hai bên nhà giáp nhà hàng xóm: gờ trụ
    trim = tuple(min(255, int(c * 1.06)) for c in wall_rgb)
    for (a, b) in ((0, 0.22), (W - 0.22, W)):
        f.paint(f.rect(a, 0, b, y_top + 1.1), plaster_fn(f, trim, sd + 5, peel=0.3 if old else 0.0), h=0.06,
                mat=M_WALL)
    # ---------------- tầng trệt
    x0, x1 = 0.3, W - 0.3
    y_open = 2.62
    f.paint(f.rect(0, 0, W, 0.12), lin((150, 146, 138)), h=0.12, mat=M_TRIM)  # bậc thềm
    if spec.get('glass_front'):
        interior(f, x0, 0.12, x1, y_open, spec['interior'], seed=sd, light=1.4)
        door(f, x0, 0.12, x1, y_open, 'glass', seed=sd)
    else:
        interior(f, x0, 0.12, x1, y_open, spec['interior'], seed=sd)
        op = spec['open']
        if op < 1.0:
            roller_shutter(f, x0, x1, 0.12 + (y_open - 0.12) * op, y_open, spec['shutter'], seed=sd)
        else:
            roller_shutter(f, x0, x1, y_open - 0.18, y_open, spec['shutter'], seed=sd)
    f.paint(f.rect(x0 - 0.04, y_open, x1 + 0.04, y_open + 0.26), lin(spec['shutter']) * 0.8, h=0.16, mat=M_METAL)
    if spec.get('awning'):
        ac_ = lin(spec['awning'])
        ya = y_open + 0.26
        sm = f.poly([(0.05, ya), (W - 0.05, ya), (W - 0.05, ya - 0.55), (0.05, ya - 0.55)])

        def stripe(X, Y):
            st = (np.mod(X, 0.5) < 0.25)[..., None]
            c = np.where(st, ac_[None, None, :], lin((236, 232, 220))[None, None, :])
            return c * (0.85 + 0.15 * smoothstep(ya - 0.55, ya, Y))[..., None]
        f.paint(sm, stripe, h=lambda X, Y: 1.4 - (ya - Y) * 1.6, mat=M_FABRIC)
        # diềm lượn sóng
        for k in range(int(W / 0.25)):
            f.paint(f.ellipse(0.05 + (k + 0.5) * 0.25, ya - 0.55, 0.125, 0.07),
                    ac_ if (k % 2 == 0) else lin((236, 232, 220)), h=0.55)
    signboard(f, 0.12, 2.98, W - 0.12, 3.58, spec['shop'], spec['sub'], spec['bg'], spec['fg'], phone=spec['phone'],
              seed=sd)
    if spec.get('tires'):
        for k in range(3):
            cx = 0.45 + k * 0.48
            for j in range(3 - k % 2):
                f.paint(f.ellipse(cx, 0.32 + j * 0.24, 0.24, 0.13), lin((26, 26, 26)), h=0.45 + j * 0.01)
                f.paint(f.ellipse(cx, 0.32 + j * 0.24, 0.1, 0.05), lin((50, 48, 46)), h=0.44)
    # ---------------- các tầng trên
    rails = spec['rails']
    for k in range(1, nf):
        yf = gf + (k - 1) * fl
        rail = rails[(k - 1) % len(rails)]
        # vách sau ban công
        dw = min(2.2, W - 1.6)
        dx0 = (W - dw) / 2
        if spec['door'] == 'wood' or old:
            door(f, dx0, yf + 0.05, dx0 + dw, yf + 2.45, 'wood', col=(120, 84, 56), seed=sd + k)
        else:
            door(f, dx0, yf + 0.05, dx0 + dw, yf + 2.45, 'glass', seed=sd + k)
        f.paint(f.rect(dx0 - 0.15, yf + 2.5, dx0 + dw + 0.15, yf + 2.6), lin(trim), h=0.35, mat=M_TRIM)
        # ô cửa thoáng trên cửa đi
        for i in range(4):
            a = dx0 + i * dw / 4 + 0.05
            f.paint(f.rect(a, yf + 2.68, a + dw / 4 - 0.1, yf + 3.0), lin((50, 50, 50)), h=-0.12,
                    unlit=lambda X, Y: np.full(X.shape + (3,), 0.03), mat=M_TRIM)
            f.paint(f.rect(a + dw / 8 - 0.07, yf + 2.68, a + dw / 8 - 0.03, yf + 3.0), lin(trim), h=-0.06)
        if spec.get('ac') and k == nf - 1:
            ac_unit(f, 0.75, yf + 2.75)
        if rail == 'glass':
            # lan can kính cường lực (nhìn xuyên, hơi xanh, phản chiếu nhẹ) + tay vịn inox
            sl, m = f.rect(0.25, yf, W - 0.25, yf + 1.0)
            if sl is not None:
                X, Y = f.grid(sl)
                refl = glass_fn(sd + k, 0, yf, W, yf + 2.0)(X, Y) * 0.35
                tint = np.array([0.78, 0.86, 0.84])
                mm = m[..., None]
                f.alb[sl] = f.alb[sl] * (1 - mm) + f.alb[sl] * tint * mm
                f.unlit[sl] = f.unlit[sl] * (1 - mm) + (f.unlit[sl] * tint + refl) * mm
                f.u[sl] = np.maximum(f.u[sl], m * 0.35)
                f.hm[sl] = np.maximum(f.hm[sl], m * 0.2)
            for xx in np.linspace(0.27, W - 0.27, 4):
                f.paint(f.rect(xx - 0.02, yf, xx + 0.02, yf + 1.0), lin((190, 192, 196)), h=1.0, mat=M_METAL)
            f.paint(f.rect(0.25, yf + 0.98, W - 0.25, yf + 1.04), lin((190, 192, 196)), h=1.05, mat=M_METAL)
            f.paint(f.rect(0.2, yf - 0.16, W - 0.2, yf + 0.02), lin(trim), h=1.05, mat=M_TRIM)
            pl = spec['plants'][(k - 1) % len(spec['plants'])]
            for j, (px, kind) in enumerate(pl):
                if kind == 'bougainvillea':
                    leaves_blob(f, px, yf + 1.15, 0.55, 0.35, (52, 92, 40), 1.1, leaf=0.05, flowers=(212, 40, 128),
                                flower_frac=0.45, hang=1.1, seed=sd + j)
                else:
                    pot(f, px, yf + 1.0, 0.32, 0.24, (150, 76, 46), h=1.05)
                    leaves_blob(f, px, yf + 1.45, 0.3, 0.25, (60, 104, 44), 1.12, leaf=0.06, seed=sd + j)
        else:
            balcony(f, 0.2, W - 0.2, yf, 1.0, rail, spec.get('rail_rgb', (40, 44, 46)), trim, seed=sd + k,
                    plants=spec['plants'][(k - 1) % len(spec['plants'])])
        # đèn lồng dưới sàn ban công tầng trên
    # ---------------- sân thượng
    yp = y_top
    if spec['roof'] in ('tank', 'vents'):
        parapet(f, 0, W, yp, yp + 1.1, wall_rgb, sd, style='vents' if spec['roof'] == 'vents' else 'plain', trim_rgb=trim)
        if spec['roof'] == 'tank':
            water_tank(f, W * 0.68, yp + 0.6, r=0.5, hgt=1.15, h=-2.0)
            antenna(f, W * 0.22, yp + 1.1, 1.6, h=-1.0)
    elif spec['roof'] == 'pediment':
        parapet(f, 0, W, yp, yp + 1.1, wall_rgb, sd, style='pediment', trim_rgb=trim)
        water_tank(f, W * 0.8, yp + 0.8, r=0.42, hgt=1.0, h=-2.5)
    elif spec['roof'] == 'mai_thai':
        parapet(f, 0, W, yp, yp + 0.5, wall_rgb, sd, trim_rgb=trim)
        tile_roof(f, -0.0, W, yp + 0.5, yp + 1.75, inset=0.0, kind='clay', rgb=(170, 80, 50), seed=sd, over=0.45,
                  depth=1.6)
    # ---------------- Tết
    nl = spec['lanterns']
    if nl:
        yl = gf - 0.16
        for i in range(nl):
            lantern(f, 0.34 + (W - 0.68) * i / max(nl - 1, 1), yl, r=0.15, h=1.0 + 0.02 * i, string=0.08)
        if nf > 2:
            for i in range(nl):
                lantern(f, W * (0.25 + 0.5 * i / max(nl - 1, 1)), gf + fl - 0.16, r=0.15, h=1.0)
    if spec.get('banner') and nf >= 2:
        banner(f, 0.35, W - 0.35, gf + 0.32, gf + 0.82, spec['banner'], h=1.06, seed=sd)
    if spec['flag']:
        vn_flag(f, W - 0.45, gf + 0.9, length=1.7, w=0.8, side=-1, h=1.1)
    for i, kind in enumerate(spec['pots']):
        px = 0.55 if i == 0 else W - 0.55
        if kind == 'kumquat':
            kumquat_pot(f, px, 0.12, s=1.0, h=0.7, seed=sd + 40 + i)
        else:
            peach_pot(f, px, 0.12, s=1.0, h=0.7, seed=sd + 40 + i)
    cables(f, 0, W, [gf + 1.75 + 0.1 * k for k in range(3)], h=1.6, sag=0.2, seed=sd)
    f.weather(amount=spec.get('grimy', 1.0), splash=1.0, seed=sd)
    return f.render(), H


# ---------------------------------------------------------- Nhà quê một tầng
VILLAGE = {
    'house_village_1': dict(width=7.6, wall=(236, 204, 118), roof='clay', roof_rgb=(170, 86, 56), inset=1.3,
                            cols='round', col_rgb=(238, 232, 214), door='wood', door_rgb=(122, 70, 44),
                            shutter=(46, 110, 84), fence='lime', gate=(40, 44, 48), seed=11, flag='gate',
                            pots=['kumquat', 'kumquat']),
    'house_village_2': dict(width=7.0, wall=(152, 188, 214), roof='iron', roof_rgb=(150, 64, 50), inset=0.0,
                            cols='square', col_rgb=(230, 230, 222), door='folding', door_rgb=(70, 90, 110),
                            grille=(50, 60, 70), fence='breeze', gate=(30, 70, 120), seed=12, flag='pole',
                            pots=['peach']),
    'house_village_3': dict(width=8.0, wall=(238, 232, 214), roof='clay', roof_rgb=(150, 76, 52), inset=1.5,
                            cols='square', col_rgb=(224, 212, 186), door='wood', door_rgb=(140, 92, 54),
                            shutter=(120, 76, 50), fence='lime', gate=(150, 30, 30), seed=13, flag='pole',
                            shrine=True, pots=['kumquat']),
    'house_village_4': dict(width=6.6, wall=(214, 176, 112), roof='clay', roof_rgb=(128, 82, 62), inset=0.0,
                            cols='wood', col_rgb=(96, 66, 46), door='panels', door_rgb=(110, 74, 50),
                            shutter=None, fence='brick', gate=None, seed=14, flag=None, old=True, pots=[]),
}


def brick_fn(seed, rgb=(150, 78, 54), course=0.07, blen=0.23, mortar=(170, 162, 150), mortar_w=0.012):
    """Gạch thẻ đỏ để trần: mạch vữa, viên đậm nhạt, sứt mẻ, ố."""
    base = lin(rgb)
    mc = lin(mortar)

    def fn(X, Y):
        row = np.floor(Y / course)
        xo = X + (np.mod(row, 2)) * blen / 2
        col = np.floor(xo / blen)
        fy = np.mod(Y, course)
        fx = np.mod(xo, blen)
        mort = (fy < mortar_w) | (fx < mortar_w)
        hsh = np.sin(row * 12.9898 + col * 78.233 + seed) * 43758.5453
        hsh = hsh - np.floor(hsh)
        c = base[None, None, :] * (0.72 + 0.5 * hsh)[..., None] * (0.9 + 0.2 * fbm(X * 20, Y * 20, seed=seed, octaves=2))[..., None]
        soot = smoothstep(0.55, 0.8, fbm(X * 1.2, Y * 1.2, seed=seed + 4, octaves=4))
        c = c * (1 - 0.4 * soot[..., None])
        return np.where(mort[..., None], mc[None, None, :] * (0.8 + 0.3 * hsh)[..., None], c)

    def hfn(X, Y):
        row = np.floor(Y / course)
        xo = X + (np.mod(row, 2)) * blen / 2
        fy = np.mod(Y, course)
        fx = np.mod(xo, blen)
        return -0.008 * ((fy < mortar_w) | (fx < mortar_w))
    return fn, hfn


def column(f, cx, y0, y1, w, rgb, h, kind='round', seed=0):
    c = lin(rgb)
    if kind == 'wood':
        sm = f.rect(cx - w / 2, y0, cx + w / 2, y1)
        X, Y = f.grid(sm[0])
        u = np.clip((X - cx) / (w / 2), -1, 1)
        col = c[None, None, :] * (0.85 + 0.3 * fbm(X * 8, Y * 1.5, seed=seed, octaves=3))[..., None]
        f.paint(sm, col, h=h + np.sqrt(np.clip(1 - u * u, 0, 1)) * w / 2, mat=M_WOOD)
        f.paint(f.rect(cx - w * 0.75, y0, cx + w * 0.75, y0 + 0.12), lin((120, 116, 108)), h=h + 0.05, mat=M_TRIM)
        return
    f.paint(f.rect(cx - w * 0.8, y0, cx + w * 0.8, y0 + 0.22), c * 0.95, h=h + w * 0.3, mat=M_TRIM)
    f.paint(f.rect(cx - w * 0.75, y1 - 0.16, cx + w * 0.75, y1), c * 0.95, h=h + w * 0.3, mat=M_TRIM)
    sm = f.rect(cx - w / 2, y0 + 0.22, cx + w / 2, y1 - 0.16)
    if kind == 'round':
        X, Y = f.grid(sm[0])
        u = np.clip((X - cx) / (w / 2), -1, 1)
        f.paint(sm, plaster_fn(f, rgb, seed), h=h + np.sqrt(np.clip(1 - u * u, 0, 1)) * w / 2, mat=M_WALL)
    else:
        f.paint(sm, plaster_fn(f, rgb, seed), h=h + w / 2, mat=M_WALL)
        f.paint(f.rect(cx - w / 2, y0 + 0.22, cx - w / 2 + 0.03, y1 - 0.16), c * 1.05, h=h + w / 2 - 0.01)


def fence(f, x0, x1, gx0, gx1, kind, gate_rgb, h=4.5, height=1.25, seed=0, wall_rgb=(232, 228, 214)):
    """Tường rào trước sân: vôi trắng mốc / gạch hoa gió / gạch trần, hai trụ
    cổng có mũ, cổng sắt song chắn nhìn xuyên thấy sân."""
    segs = [(x0, gx0 - 0.35), (gx1 + 0.35, x1)] if gx0 is not None else [(x0, x1)]
    for (a, b) in segs:
        if b <= a:
            continue
        if kind == 'brick':
            fn, hfn = brick_fn(seed)
            f.paint(f.rect(a, 0, b, height), fn, h=lambda X, Y: h + hfn(X, Y), mat=M_WALL)
            f.paint(f.rect(a, height - 0.07, b, height), brick_fn(seed + 1, rgb=(140, 74, 52))[0], h=h + 0.04)
            continue
        f.paint(f.rect(a, 0, b, height), plaster_fn(f, wall_rgb, seed + 3, peel=0.5), h=h, mat=M_WALL)
        f.paint(f.rect(a - 0.02, height - 0.08, b + 0.02, height + 0.02), lin(wall_rgb) * 0.95, h=h + 0.06, mat=M_TRIM)
        if kind == 'breeze':
            # gạch hoa gió: ô vuông có hoa văn thủng, nhìn xuyên ra sau
            n = int((b - a - 0.2) / 0.3)
            if n <= 0:
                continue
            for i in range(n):
                cx = a + 0.1 + (i + 0.5) * (b - a - 0.2) / n
                for cy in (height - 0.28,):
                    f.paint(f.rect(cx - 0.13, cy - 0.13, cx + 0.13, cy + 0.13), lin((30, 34, 30)), h=h - 0.2,
                            unlit=lambda X, Y: np.full(X.shape + (3,), 0.08), mat=M_TRIM)
                    for (dx, dy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
                        f.paint(f.ellipse(cx + dx * 0.13, cy + dy * 0.13, 0.11, 0.11), lin(wall_rgb), h=h,
                                mat=M_WALL)
                    f.paint(f.ellipse(cx, cy, 0.04, 0.04), lin(wall_rgb), h=h)
    if gx0 is None:
        return
    for px in (gx0 - 0.2, gx1 + 0.2):
        f.paint(f.rect(px - 0.2, 0, px + 0.2, 1.85), plaster_fn(f, wall_rgb, seed + 7, peel=0.4) if kind != 'brick'
                else brick_fn(seed + 2)[0], h=h + 0.12, mat=M_WALL)
        f.paint(f.rect(px - 0.26, 1.85, px + 0.26, 1.97), lin((210, 206, 196)), h=h + 0.2, mat=M_TRIM)
        f.paint(f.poly([(px - 0.22, 1.97), (px + 0.22, 1.97), (px, 2.2)]), lin((160, 70, 48)), h=h + 0.15, mat=M_ROOF)
    if gate_rgb is not None:
        gc = lin(gate_rgb)
        f.paint(f.rect(gx0, 0.05, gx1, 0.12), gc, h=h, mat=M_METAL)
        f.paint(f.rect(gx0, 1.55, gx1, 1.62), gc, h=h, mat=M_METAL)
        f.paint(f.rect(gx0, 0.9, gx1, 0.95), gc, h=h, mat=M_METAL)
        f.paint(f.rect((gx0 + gx1) / 2 - 0.025, 0.05, (gx0 + gx1) / 2 + 0.025, 1.62), gc, h=h)
        n = int((gx1 - gx0) / 0.12)
        for i in range(n + 1):
            xx = gx0 + i * (gx1 - gx0) / n
            top = 1.62 + 0.15 * math.sin(math.pi * (i / n * 2 % 1.0))
            f.paint(f.rect(xx - 0.012, 0.05, xx + 0.012, top), gc, h=h, mat=M_METAL)
            f.paint(f.poly([(xx - 0.03, top), (xx + 0.03, top), (xx, top + 0.07)]), gc, h=h)


def shrine(f, cx, h=3.0):
    """Bàn thờ thiên ngoài sân: trụ xi măng, khám nhỏ mái ngói, bát hương."""
    f.paint(f.rect(cx - 0.09, 0, cx + 0.09, 1.45), lin((190, 186, 176)), h=h, mat=M_WALL)
    f.paint(f.rect(cx - 0.32, 1.45, cx + 0.32, 1.52), lin((200, 196, 186)), h=h + 0.05, mat=M_TRIM)
    f.paint(f.rect(cx - 0.28, 1.52, cx + 0.28, 1.98), lin((168, 28, 26)), h=h - 0.1, mat=M_TRIM)
    f.paint(f.rect(cx - 0.22, 1.56, cx + 0.22, 1.9), lin((40, 10, 8)), h=h - 0.2,
            unlit=lambda X, Y: np.full(X.shape + (3,), 0.02))
    f.paint(f.rect(cx - 0.09, 1.56, cx + 0.09, 1.66), lin((200, 160, 60)), h=h - 0.15)
    for k in range(3):
        xx = cx - 0.05 + k * 0.05
        f.paint(f.rect(xx - 0.004, 1.66, xx + 0.004, 1.82), lin((150, 40, 30)), h=h - 0.14)
    f.paint(f.poly([(cx - 0.4, 1.98), (cx + 0.4, 1.98), (cx + 0.24, 2.22), (cx - 0.24, 2.22)]), lin((166, 80, 52)),
            h=h + 0.1, mat=M_ROOF)
    f.paint(f.rect(cx - 0.26, 2.2, cx + 0.26, 2.25), lin((140, 70, 50)), h=h + 0.05)


def village_house(spec, keep=False):
    """Nhà cấp 4 quê: nền cao, hiên cột, mái ngói đỏ / tôn, cửa gỗ / cửa
    xếp, cửa sổ chớp; tường rào cổng sắt phía trước; cờ, bàn thờ thiên."""
    W = spec['width']
    sd = spec['seed'] * 31
    old = spec.get('old', False)
    y_eave, y_ridge = 3.25, 5.05
    H = 5.35 if spec.get('flag') != 'pole' else 7.4
    f = Facade(W, H, 112 if H < 6 else 95, ss=2, seed=spec['seed'])
    wall = spec['wall']
    plinth = 0.45
    # nền + tường hồi hai đầu
    f.paint(f.rect(0.15, 0, W - 0.15, plinth), lin((168, 162, 150)), h=1.9, mat=M_TRIM)
    f.paint(f.rect(0.15, plinth - 0.06, W - 0.15, plinth), lin((190, 182, 168)), h=1.95)
    f.paint(f.rect(0.15, plinth, W - 0.15, y_eave), plaster_fn(f, wall, sd, peel=0.7 if old else 0.25, repaint=1.0),
            h=0.0, mat=M_WALL)
    f.paint(f.rect(0.15, plinth, 0.55, y_eave), plaster_fn(f, wall, sd + 1, peel=0.4 if old else 0.1), h=1.9, mat=M_WALL)
    f.paint(f.rect(W - 0.55, plinth, W - 0.15, y_eave), plaster_fn(f, wall, sd + 2, peel=0.4 if old else 0.1), h=1.9,
            mat=M_WALL)
    # cửa chính + cửa sổ trên vách sau hiên
    cx = W / 2
    dw = 1.8 if spec['door'] != 'panels' else W - 2.2
    if spec['door'] == 'wood':
        door(f, cx - dw / 2, plinth, cx + dw / 2, plinth + 2.35, 'wood', col=spec['door_rgb'], seed=sd)
    elif spec['door'] == 'folding':
        door(f, cx - dw / 2, plinth, cx + dw / 2, plinth + 2.35, 'folding', col=spec['door_rgb'], seed=sd)
    else:
        # cửa bức bàn: nhiều cánh gỗ ghép, cánh giữa mở hé lộ trong nhà tối
        n = 6
        for i in range(n):
            a = cx - dw / 2 + i * dw / n
            b = a + dw / n
            if i in (2, 3):
                f.paint(f.rect(a, plinth, b, plinth + 2.4), lin((20, 16, 12)), h=-0.3,
                        unlit=lambda X, Y: np.full(X.shape + (3,), 0.018), mat=M_TRIM)
                continue
            door(f, a, plinth, b, plinth + 2.4, 'wood', col=spec['door_rgb'], seed=sd + i)
    if spec['door'] != 'panels':
        for sx in (-1, 1):
            wx = cx + sx * (dw / 2 + 0.55 + 0.55)
            window(f, wx - 0.55, plinth + 0.95, wx + 0.55, plinth + 2.25, frame=(90, 70, 50) if spec.get('shutter') else
                   (200, 200, 196), grille=spec.get('grille'), shutter=spec.get('shutter'), shutter_open=True,
                   lintel=False, sill=True, wall_rgb=wall, seed=sd + 3 + sx)
    # cột hiên + dầm
    ncol = 4
    xs = np.linspace(0.85, W - 0.85, ncol)
    for i, xx in enumerate(xs):
        column(f, xx, plinth, y_eave - 0.25, 0.26, spec['col_rgb'], 1.8, kind=spec['cols'], seed=sd + 10 + i)
    f.paint(f.rect(0.15, y_eave - 0.3, W - 0.15, y_eave), plaster_fn(f, wall, sd + 3), h=1.85, mat=M_WALL)
    # bậc tam cấp
    for k in range(3):
        f.paint(f.rect(cx - 1.1 - 0.15 * (2 - k), k * 0.15, cx + 1.1 + 0.15 * (2 - k), (k + 1) * 0.15),
                lin((176, 170, 158)) * (0.95 + 0.05 * k), h=2.6 - 0.3 * k, mat=M_TRIM)
    # mái
    tile_roof(f, 0.0, W, y_eave, y_ridge, inset=spec['inset'], kind=spec['roof'], rgb=spec['roof_rgb'], seed=sd,
              over=2.3, depth=4.2)
    # Tết + sân
    if spec.get('shrine'):
        shrine(f, W - 1.1, h=3.2)
    for i, kind in enumerate(spec.get('pots', [])):
        px = cx - 1.45 if i == 0 else cx + 1.45
        if kind == 'kumquat':
            kumquat_pot(f, px, plinth, s=0.95, h=2.0, seed=sd + 40 + i)
        else:
            peach_pot(f, px, plinth, s=1.1, h=2.0, seed=sd + 40 + i)
    if not old:
        for xx in (xs[1] - 0.6, xs[2] + 0.6):
            lantern(f, xx, y_eave - 0.3, r=0.16, h=2.25, string=0.1)
    gw = 2.6 if spec.get('gate') is not None else None
    if spec.get('table'):
        # bàn thờ / bàn tiếp khách ngoài hiên: bánh chưng, mâm ngũ quả
        tx = cx + 1.35
        f.paint(f.rect(tx - 0.55, plinth + 0.72, tx + 0.55, plinth + 0.78), lin((110, 60, 36)), h=1.2, mat=M_WOOD)
        for lx in (tx - 0.5, tx + 0.46):
            f.paint(f.rect(lx, plinth, lx + 0.04, plinth + 0.72), lin((90, 50, 30)), h=1.15, mat=M_WOOD)
        f.paint(f.rect(tx - 0.62, plinth + 0.78, tx + 0.62, plinth + 0.8), lin((190, 30, 30)), h=1.25)
        for k in range(2):
            bx = tx - 0.42 + k * 0.26
            f.paint(f.rect(bx - 0.11, plinth + 0.8, bx + 0.11, plinth + 0.94), lin((52, 96, 40)), h=1.3, mat=M_PLANT)
            f.paint(f.rect(bx - 0.11, plinth + 0.86, bx + 0.11, plinth + 0.875), lin((200, 196, 170)), h=1.31)
            f.paint(f.rect(bx - 0.008, plinth + 0.8, bx + 0.008, plinth + 0.94), lin((200, 196, 170)), h=1.31)
        f.paint(f.ellipse(tx + 0.3, plinth + 0.83, 0.26, 0.04), lin((200, 160, 60)), h=1.3)
        rng2 = np.random.default_rng(7)
        for k in range(14):
            fx = tx + 0.3 + rng2.uniform(-0.2, 0.2)
            fy = plinth + 0.86 + rng2.uniform(0, 0.16) * (1 - abs(fx - tx - 0.3) / 0.25)
            c = [(236, 140, 30), (240, 200, 50), (90, 140, 50), (200, 40, 40), (230, 220, 120)][k % 5]
            f.paint(f.ellipse(fx, fy, 0.045, 0.045), lin(c), h=1.32 + 0.01 * k, mat=M_PLANT)
    if spec.get('fence'):
        fence(f, 0.0, W, cx - gw / 2 if gw else None, cx + gw / 2 if gw else None, spec['fence'], spec.get('gate'),
              h=4.5, seed=sd, wall_rgb=(230, 226, 212))
    if spec.get('flag') == 'gate':
        vn_flag(f, cx + gw / 2 + 0.2, 1.97, length=1.4, w=0.7, side=1, h=4.8)
    elif spec.get('flag') == 'pole':
        px = 0.7
        f.paint(f.rect(px - 0.035, 0.0, px + 0.035, H - 0.15), lin((150, 140, 96)), h=4.0, mat=M_WOOD, thick=0.0)
        for k in range(int(H / 0.4)):
            f.paint(f.rect(px - 0.04, k * 0.4, px + 0.04, k * 0.4 + 0.03), lin((110, 100, 70)), h=4.01, thick=0.0)
        fy1 = H - 0.25
        sm = f.poly([(px + 0.03, fy1), (px + 1.25, fy1 - 0.1), (px + 1.25, fy1 - 0.88), (px + 0.03, fy1 - 0.8)])
        # cột cờ ngoài sân ở xa mặt nhà: không đổ bóng lên mái (bóng rơi xuống sân)
        f.paint(sm, lin((214, 24, 28)), h=lambda X, Y: 4.0 + 0.06 * np.sin((X - px) * 7), mat=M_FABRIC, thick=0.0)
        cxs, cys, R = px + 0.64, fy1 - 0.45, 0.22
        star = [(cxs + (R if k % 2 == 0 else R * 0.382) * math.cos(math.pi / 2 + k * math.pi / 5),
                 cys + (R if k % 2 == 0 else R * 0.382) * math.sin(math.pi / 2 + k * math.pi / 5)) for k in range(10)]
        f.paint(f.poly(star), lin((252, 214, 40)), hadd=0.004)
    f.weather(amount=1.6 if old else 1.0, splash=1.3, seed=sd)
    if keep:
        return f.render(), H, f
    return f.render(), H


def wall_side(kind, seed=0, size=512, tile_m=3.0):
    """Vân tường hồi lặp liền mạch 512×512 (phủ [tile_m] mét mỗi chiều)."""
    ppm = size / tile_m
    big = pfbm(size, size, 140, seed=seed + 1)
    mid = pfbm(size, size, 30, seed=seed + 2)
    fine = pfbm(size, size, 4, seed=seed + 3, octaves=3)
    # vệt nước chảy dọc lặp liền mạch: nhiễu dãn theo chiều dọc, mờ dần xuống dưới
    streak = pfbm(size, size, 120, seed=seed + 4, octaves=4, sx_ratio=0.08)
    streak = smoothstep(0.5, 0.9, streak) * (0.4 + 0.6 * pfbm(size, size, 80, seed=seed + 5))
    streak = gblur_wrap_x(streak, 1.5)
    if kind == 'brick':
        nc, nb = 40, 12  # 40 hàng gạch, 12 viên mỗi hàng trong một ô vân
        yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
        ch = size / nc
        bl = size / nb
        row = np.floor(yy / ch)
        xo = np.mod(xx + np.mod(row, 2) * bl / 2, size)
        col = np.floor(xo / bl)
        fy = np.mod(yy, ch)
        fx = np.mod(xo, bl)
        mw = 2.0
        mort = (fy < mw) | (fx < mw)
        hsh = np.sin(np.mod(row, nc) * 12.9898 + np.mod(col, nb) * 78.233 + seed) * 43758.5453
        hsh = hsh - np.floor(hsh)
        brick = lin((150, 80, 56))[None, None, :] * (0.72 + 0.5 * hsh)[..., None] * (0.88 + 0.24 * fine)[..., None]
        # vài viên sẫm cháy, vài viên vàng nhạt
        odd = np.sin(np.mod(row, nc) * 4.1 + np.mod(col, nb) * 9.7 + seed) * 999.0
        odd = odd - np.floor(odd)
        brick = np.where((odd < 0.06)[..., None], brick * 0.6, brick)
        brick = np.where((odd > 0.95)[..., None], brick * np.array([1.25, 1.2, 1.0]), brick)
        mc = lin((172, 164, 150))[None, None, :] * (0.8 + 0.3 * mid)[..., None]
        alb = np.where(mort[..., None], mc, brick)
        hm = -0.006 * mort + 0.002 * (fine - 0.5)
        alb = alb * (1 - 0.3 * streak)[..., None] * (1 - 0.25 * smoothstep(0.55, 0.85, big))[..., None]
    else:
        rgb = {'yellow': (226, 196, 120), 'cement': (160, 158, 150)}[kind]
        alb = lin(rgb)[None, None, :] * (0.88 + 0.24 * big)[..., None] * (0.95 + 0.1 * mid)[..., None] * \
            (0.96 + 0.08 * fine)[..., None]
        if kind == 'cement':
            mold = np.clip(streak * 0.8 + 0.5 * smoothstep(0.55, 0.9, big), 0, 1)
            alb = alb * (1 - 0.45 * mold)[..., None] + lin((44, 48, 40)) * 0.2 * mold[..., None]
            hm = (fine - 0.5) * 0.004
        else:
            peel = smoothstep(0.8, 0.83, pfbm(size, size, 16, seed=seed + 8))
            cem = lin((156, 152, 142)) * (0.85 + 0.3 * fine)[..., None]
            alb = alb * (1 - 0.35 * streak)[..., None]
            alb = alb * (1 - peel[..., None]) + cem * peel[..., None]
            hm = (fine - 0.5) * 0.002 - 0.003 * peel
    # đổ sáng nhẹ theo độ gồ (nắng chéo từ trên trái), lặp liền mạch
    gx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) / 2 * ppm
    gy = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) / 2 * ppm
    nn = np.stack([-gx, gy, np.ones_like(gx)], -1)
    nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
    ndl = np.clip(nn @ F_SUN, 0, 1) / F_SUN[2]
    col = alb * (0.75 * ndl + 0.3)[..., None]
    srgb = np.clip(col, 0, 1) ** (1 / 2.2)
    return Image.fromarray((srgb * 255 + 0.5).astype(np.uint8), 'RGB')


# ======================================================= Bầu trời toàn cảnh
# Ảnh trời 2048×512 phủ 180° phương vị (game lặp 2 lần quanh 360°) và độ
# cao 0°..40° → điểm ảnh gần vuông (11,4 px/° ngang, 12,8 px/° dọc).
SKY_W, SKY_H, SKY_SPAN, SKY_EL = 2048, 512, 180.0, 40.0


def lin_to_img(c, dither=True, seed=0):
    s = np.clip(c, 0, 1) ** (1 / 2.2) * 255
    if dither:
        s = s + np.random.default_rng(seed).uniform(-0.5, 0.5, s.shape)
    return np.clip(s + 0.5, 0, 255).astype(np.uint8)


def sky_gradient(el, stops):
    """Nội suy màu theo độ cao (độ) qua các mốc [(el, (r, g, b)), ...]."""
    els = np.array([e for e, _ in stops])
    cols = np.array([lin(c) for _, c in stops])
    out = np.stack([np.interp(el, els, cols[:, k]) for k in range(3)], -1)
    return out


def cloud_slab(ELG, PHI, h0, h1, scale, coverage, seed, steps=14, sigma=2.2, dmax=70.0, warp=0.6,
               tops=0.35, octaves=5, dmin=0.0):
    """Mây thể tích trong một lớp dày từ [h0] đến [h1] km: dò tia qua lớp,
    mật độ = nhiễu 2D trên mặt phẳng mây (toạ độ cực theo phương vị → lặp
    liền mạch), đỉnh vồng tròn, đáy phẳng. Trả về (độ phủ, độ cao tương
    đối trung bình trong mây 0..1 [đỉnh = 1], độ xa km)."""
    el = np.radians(np.maximum(ELG, 0.15))
    tn = np.tan(el)
    d0 = h0 / tn
    d1 = h1 / tn
    ok = d0 < dmax
    T = np.ones_like(ELG)
    acc_z = np.zeros_like(ELG)
    acc_d = np.zeros_like(ELG)
    acc_a = np.zeros_like(ELG)
    cphi, sphi = np.cos(PHI), np.sin(PHI)
    seg = np.sqrt((d1 - d0) ** 2 + (h1 - h0) ** 2) / steps
    jit = np.random.default_rng(seed + 99).uniform(0, 1, ELG.shape)
    for k in range(steps):
        t = (k + jit) / steps
        d = d0 + (d1 - d0) * t
        zn = t
        x = d * cphi / scale
        y = d * sphi / scale
        wx = fbm(x * 0.5 + 3.1, y * 0.5 - 1.7, seed=seed + 1, octaves=3)
        wy = fbm(x * 0.5 - 4.3, y * 0.5 + 2.9, seed=seed + 2, octaves=3)
        n = fbm(x + warp * wx, y + warp * wy, seed=seed, octaves=octaves)
        dens = np.clip((n - coverage - tops * zn ** 1.6) * 4.0, 0, 1)
        dens = dens * ok * smoothstep(dmax, dmax * 0.6, d)
        if dmin > 0:
            dens = dens * smoothstep(dmin * 0.5, dmin, d)
        a = 1 - np.exp(-sigma * dens * seg)
        w = T * a
        acc_z += w * zn
        acc_d += w * d
        acc_a += w
        T = T * (1 - a)
    alpha = gblur_wrap_x(1 - T, 0.8)
    z = gblur_wrap_x(acc_z, 0.8) / np.maximum(gblur_wrap_x(acc_a, 0.8), 1e-6)
    dist = acc_d / np.maximum(acc_a, 1e-6)
    return alpha, z, dist


def sky_image(kind, seed):
    rng = np.random.default_rng(seed)
    W, H = SKY_W, SKY_H
    el = (H - 0.5 - np.arange(H)) / H * SKY_EL
    ELG = np.repeat(el[:, None], W, axis=1)
    PHI = np.repeat((np.arange(W) / W * math.tau)[None, :], H, axis=0)  # 180° ảnh ↔ 360° mặt phẳng mây
    sun_x = W * 0.28
    dx = np.minimum(np.abs(np.arange(W) - sun_x), W - np.abs(np.arange(W) - sun_x)) / W * SKY_SPAN  # độ
    DX = np.repeat(dx[None, :], H, axis=0)
    if kind == 'day':
        # trời hanh mờ sương (Tết miền Bắc): chân trời trắng đục, lên cao xanh nhạt
        base = sky_gradient(ELG, [(0, (222, 226, 228)), (3, (212, 220, 228)), (10, (186, 204, 224)),
                                  (22, (152, 180, 214)), (40, (118, 154, 202))])
        glow = np.exp(-(DX / 55) ** 2) * smoothstep(5, 40, ELG) * 0.12
        base = base * (1 + glow[..., None] * np.array([1.0, 0.98, 0.9]))
        # mây ti mỏng trên cao
        ci = pfbm(H, W, 90, seed=seed + 5, sx_ratio=4.0)
        ci = smoothstep(0.55, 0.85, ci) * smoothstep(12, 30, ELG) * 0.18
        base = base * (1 - ci[..., None]) + lin((240, 242, 246)) * ci[..., None]
        a, z, dist = cloud_slab(ELG, PHI, 1.1, 2.3, 2.2, 0.56, seed, steps=18, sigma=3.0, tops=0.3, dmin=7.0)
        sun_side = 0.15 * np.exp(-(DX / 40) ** 2)
        lit = np.array([1.0, 0.985, 0.95]) * 1.02
        shade = np.array([0.50, 0.55, 0.64])
        L = np.clip(z ** 0.8 * 1.1 + sun_side, 0, 1)[..., None]
        cc = shade + (lit - shade) * L
        fz = (1 - np.exp(-dist / 28))[..., None]
        cc = cc * (1 - 0.75 * fz) + base * 0.75 * fz
        img = base * (1 - a[..., None]) + cc * a[..., None]
        haze = smoothstep(3.5, 0.0, ELG)[..., None] * 0.55
        img = img * (1 - haze) + lin((224, 226, 226)) * haze
    elif kind == 'dusk':
        base = sky_gradient(ELG, [(0, (252, 168, 92)), (2.5, (246, 150, 104)), (7, (226, 136, 132)),
                                  (14, (172, 120, 150)), (24, (108, 104, 152)), (40, (58, 70, 120))])
        glow = np.exp(-(DX / 30) ** 2) * np.exp(-ELG / 9)
        base = base + glow[..., None] * lin((255, 200, 120)) * 0.9
        a, z, dist = cloud_slab(ELG, PHI, 2.2, 3.0, 3.0, 0.52, seed, steps=14, sigma=3.5, tops=0.15, warp=0.9,
                                  dmin=12.0)
        # mặt trời đã lặn: đáy mây được hắt sáng cam hồng, đỉnh tím xám
        body = sky_gradient(ELG, [(0, (130, 88, 100)), (10, (104, 78, 104)), (40, (56, 54, 84))])
        rimc = lin((255, 156, 96)) * (0.55 + 1.1 * np.exp(-(DX / 45) ** 2))[..., None] * \
            smoothstep(40, 3, ELG)[..., None] + lin((214, 120, 140)) * 0.4
        under = np.clip(1 - z * 1.3, 0, 1)[..., None]
        cc = body * (1 - 0.75 * under) + rimc * 0.75 * under
        fz = (1 - np.exp(-dist / 40))[..., None]
        cc = cc * (1 - 0.6 * fz) + base * 0.6 * fz
        img = base * (1 - a[..., None]) + cc * a[..., None]
    else:  # night
        base = sky_gradient(ELG, [(0, (46, 46, 62)), (2, (34, 38, 58)), (8, (20, 26, 46)), (20, (10, 15, 32)),
                                  (40, (5, 8, 20))])
        # ánh đèn thị trấn hắt lên chân trời (vàng cam rất nhạt), loang theo phương vị
        town = (0.5 + 0.5 * pfbm(1, W, 200, seed=seed + 3)[0])[None, :] * np.exp(-ELG / 3.5)
        base = base + town[..., None] * lin((70, 52, 40)) * 0.8
        img = base.copy()
        # sao: dày hơn ở trên cao, mờ dần sát chân trời (khí quyển dày)
        n = 4200
        sx = rng.uniform(0, W, n)
        sy = rng.uniform(0, H, n)
        sel = rng.uniform(0, 1, n) < smoothstep(0.0, 18.0, (H - sy) / H * SKY_EL)
        sx, sy = sx[sel], sy[sel]
        mag = rng.pareto(2.0, len(sx)) * 0.1 + 0.025
        tint = np.array([[1.0, 0.9, 0.78], [0.82, 0.88, 1.0], [1.0, 1.0, 1.0]])[rng.integers(0, 3, len(sx))]
        star = np.zeros((H, W, 3))
        ix, iy = sx.astype(int), sy.astype(int)
        np.add.at(star, (iy, ix), tint * mag[:, None])
        big = mag > 0.3
        for k in np.flatnonzero(big):
            for ddx, ddy, w in ((1, 0, 0.3), (-1, 0, 0.3), (0, 1, 0.3), (0, -1, 0.3)):
                star[(iy[k] + ddy) % H, (ix[k] + ddx) % W] += tint[k] * mag[k] * w
        # dải Ngân Hà rất mờ
        band = np.exp(-((ELG - 26 - 8 * np.sin(PHI)) / 7) ** 2) * (0.5 + 0.5 * pfbm(H, W, 20, seed=seed + 7))
        img = img + band[..., None] * lin((40, 42, 56)) * 0.35
        ext = smoothstep(0, 12, ELG)[..., None]
        img = img + star * (0.25 + 0.75 * ext)
        a, z, dist = cloud_slab(ELG, PHI, 1.6, 2.2, 3.0, 0.58, seed, steps=12, sigma=3.0, tops=0.1, dmin=5.0)
        cc = lin((34, 34, 44)) * (0.7 + 0.8 * smoothstep(16, 0, ELG))[..., None] + \
            lin((60, 46, 38)) * smoothstep(8, 0, ELG)[..., None] * 0.6
        img = img * (1 - 0.85 * a[..., None]) + cc * 0.85 * a[..., None]
    return Image.fromarray(lin_to_img(img, seed=seed), 'RGB')


# ======================================================= Dải chân trời
# Ảnh 2048×256 phủ 90° phương vị (game lặp 4 lần quanh 360°) và độ cao
# 0°..10° (22,8 px/° ngang, 25,6 px/° dọc). Trong suốt phía trên bóng núi /
# hàng cây; lớp xa mờ dần (một phần trong suốt) để hợp với mọi màu trời.
HZ_W, HZ_H, HZ_SPAN, HZ_EL = 2048, 256, 90.0, 10.0


class Horizon:
    def __init__(self, seed):
        self.rgb = np.zeros((HZ_H, HZ_W, 3))
        self.a = np.zeros((HZ_H, HZ_W))
        self.rng = np.random.default_rng(seed)
        self.seed = seed
        self.ppd_x = HZ_W / HZ_SPAN
        self.ppd_y = HZ_H / HZ_EL
        self.Y = (HZ_H - 0.5 - np.arange(HZ_H))[:, None] * np.ones((1, HZ_W))  # px trên chân trời
        self.X = np.ones((HZ_H, 1)) * np.arange(HZ_W)[None, :]

    def deg_h(self, meters, km):
        """Chiều cao (px) của vật cao [meters] ở xa [km]."""
        return math.degrees(math.atan(meters / (km * 1000))) * self.ppd_y

    def deg_w(self, meters, km):
        return math.degrees(meters / (km * 1000)) * self.ppd_x

    def layer(self, top, col, alpha=1.0, haze=0.0, haze_col=(200, 210, 222), shade=None):
        """Phủ một lớp: mọi điểm dưới đường [top] (px, theo cột). [col]: màu
        tuyến tính (3,) hoặc mảng (H, W, 3)."""
        cov = np.clip(top[None, :] - self.Y + 0.5, 0, 1)
        c = np.broadcast_to(np.asarray(col, np.float64), (HZ_H, HZ_W, 3))
        if shade is not None:
            c = c * shade[..., None]
        hc = lin(haze_col)
        c = c * (1 - haze) + hc * haze
        a = cov * alpha
        self.rgb = self.rgb * (1 - a[..., None]) + c * a[..., None]
        self.a = 1 - (1 - self.a) * (1 - a)

    def crowns(self, n, km, h_range, w_range, base_px=0.0, seed=0, bamboo=0.0, palms=0.0, gap=0.0):
        """Đường viền hàng cây: tán tròn (vòm), bụi tre (vồng nhọn), cây cau
        (thân mảnh, tán nhỏ). Trả về (đỉnh px theo cột, bản đồ độ vồng)."""
        rng = np.random.default_rng(seed)
        top = np.full(HZ_W, base_px)
        xs = rng.uniform(0, HZ_W, n)
        for x in xs:
            if gap > 0 and noise_at(x, seed) < gap:
                continue
            r = rng.uniform()
            hm = rng.uniform(*h_range)
            wm = rng.uniform(*w_range)
            hp = self.deg_h(hm, km)
            wp = max(self.deg_w(wm, km), 2.0)
            for sh in (-HZ_W, 0, HZ_W):
                c = x + sh
                a, b = int(max(0, c - wp)), int(min(HZ_W, c + wp + 1))
                if b <= a:
                    continue
                t = (np.arange(a, b) - c) / wp
                if r < bamboo:
                    prof = hp * np.clip(1 - np.abs(t), 0, 1) ** 0.6 * (1 + 0.08 * np.sin(t * 25 + x))
                elif r < bamboo + palms:
                    prof = np.where(np.abs(t) < 0.06, hp * 0.9, 0) + hp * np.sqrt(np.clip(1 - ((t) / 0.35) ** 2, 0, 1)) * \
                        np.where(np.abs(t) < 0.35, 1, 0) * 0.25 + hp * 0.75 * (np.abs(t) < 0.35)
                    prof = np.where(np.abs(t) < 0.35, np.maximum(prof, 0), 0)
                else:
                    prof = hp * (0.72 + 0.28 * np.sqrt(np.clip(1 - t * t, 0, 1))) * np.sqrt(np.clip(1 - t ** 4, 0, 1))
                prof = prof + base_px
                top[a:b] = np.maximum(top[a:b], prof)
        return top

    def texture(self, scale, seed, lo=0.75, hi=1.2):
        n = pfbm(HZ_H, HZ_W, scale, seed=seed, octaves=4)
        return lo + (hi - lo) * n

    def image(self):
        out = np.concatenate([np.clip(self.rgb, 0, 1) ** (1 / 2.2), self.a[..., None]], -1)
        return Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def noise_at(x, seed):
    return 0.5 + 0.5 * math.sin(x * 0.0123 + seed) * math.cos(x * 0.0071 + seed * 2.1)


def ridge_profile(seed, base, amp, scale, octaves=5, ridged=True, mtn_frac=1.0):
    n = np.zeros(HZ_W)
    a = 1.0
    tot = 0
    for o in range(octaves):
        sc = scale / (2 ** o)
        if sc < 1:
            break
        v = noise1d(HZ_W, sc, seed=seed + o * 11)
        if ridged and o > 0:
            v = 1 - np.abs(v) * 2
        n += a * v
        tot += a
        a *= 0.5
    n = n / tot
    n = (n - n.min()) / max(n.max() - n.min(), 1e-9)
    return base + amp * n ** 1.3 * mtn_frac


def houses_row(hz, n, km, seed, w_range=(6, 12), h_range=(4, 8), tall=0.15, colors=None, base=0.0):
    """Mái nhà làng / nhà ống xa: khối tường + mái dốc / mái bằng."""
    rng = np.random.default_rng(seed)
    colors = colors or [((170, 92, 70), (214, 206, 190)), ((120, 110, 104), (226, 220, 206)),
                        ((150, 80, 60), (232, 214, 170)), ((96, 104, 112), (208, 214, 220))]
    for i in range(n):
        x = rng.uniform(0, HZ_W)
        wm = rng.uniform(*w_range)
        hm = rng.uniform(*h_range) * (rng.uniform(1.8, 3.0) if rng.uniform() < tall else 1.0)
        wp = hz.deg_w(wm, km)
        hp = hz.deg_h(hm, km)
        roof, wall = colors[int(rng.integers(0, len(colors)))]
        pitched = rng.uniform() < 0.65 and hm < 9
        rh = hz.deg_h(rng.uniform(1.2, 2.2), km) if pitched else 0
        for sh in (-HZ_W, 0, HZ_W):
            c = x + sh
            a, b = int(max(0, c - wp / 2)), int(min(HZ_W, c + wp / 2 + 1))
            if b <= a:
                continue
            ys = slice(int(max(0, HZ_H - base - hp)), HZ_H)
            cov = np.clip(np.minimum(np.arange(a, b) - (c - wp / 2), (c + wp / 2) - np.arange(a, b)) + 0.5, 0, 1)
            wl = lin(wall) * (0.85 if (i % 3 == 0) else 1.0)
            hz.rgb[ys, a:b] = hz.rgb[ys, a:b] * (1 - cov[None, :, None]) + wl * cov[None, :, None]
            hz.a[ys, a:b] = np.maximum(hz.a[ys, a:b], cov[None, :])
            # cửa sổ tối lấm tấm
            if hp > 6:
                for k in range(int(hp / 5)):
                    yy = int(HZ_H - base - hp + 2 + k * 5)
                    if 0 <= yy < HZ_H:
                        for xx in range(a + 1, b - 1, 3):
                            hz.rgb[yy, xx] *= 0.55
            if pitched:
                for j in range(int(rh) + 1):
                    yy = int(HZ_H - base - hp - j)
                    if yy < 0:
                        break
                    inset = j / max(rh, 1) * wp * 0.35
                    aa, bb = int(max(0, c - wp / 2 - 1 + inset)), int(min(HZ_W, c + wp / 2 + 1 - inset))
                    if bb > aa:
                        hz.rgb[yy, aa:bb] = lin(roof) * (1.1 - 0.3 * j / max(rh, 1))
                        hz.a[yy, aa:bb] = 1.0
            else:
                yy = int(HZ_H - base - hp)
                if 0 <= yy < HZ_H:
                    hz.rgb[yy, a:b] = lin(wall) * 1.15


def leafy_edge(top, amp, seed, scale=1.5):
    """Mép trên lởm chởm như tán lá nhìn xa."""
    n = noise1d(HZ_W, scale, seed) * 0.6 + noise1d(HZ_W, scale * 3, seed + 1) * 0.4
    return top + n * amp * (top > 0.5)


def foliage_shade(hz, top, depth_px, seed, contrast=1.0):
    """Đổ sáng hàng cây: sáng ở ngọn, tối dần xuống gốc; lốm đốm từng tán."""
    d = np.clip((top[None, :] - hz.Y) / max(depth_px, 1), 0, 1)
    n1 = pfbm(HZ_H, HZ_W, 3, seed=seed, octaves=3)
    n2 = pfbm(HZ_H, HZ_W, 10, seed=seed + 1, octaves=3)
    return (1.2 - 0.5 * d ** 0.7) * (1 + contrast * (0.35 * (n1 - 0.5) + 0.3 * (n2 - 0.5)))


def mountain_shade(hz, top, seed, amp_px):
    d = np.clip(top[None, :] - hz.Y, 0, None)
    tb = gblur_wrap_x(top[None, :], 3)[0]
    sl = (np.roll(tb, -1) - np.roll(tb, 1)) / 2
    ridge_light = np.clip(0.9 + sl * 0.5, 0.55, 1.35)[None, :]
    near_ridge = np.exp(-d / max(amp_px * 0.35, 3))
    rav = pfbm(HZ_H, HZ_W, 14, seed=seed, octaves=4, sx_ratio=0.25)
    fine = pfbm(HZ_H, HZ_W, 2.5, seed=seed + 1, octaves=2)
    lightv = ridge_light * near_ridge + (0.75 + 0.5 * rav) * (1 - near_ridge)
    return lightv * (0.88 + 0.24 * fine) * (1.05 - 0.2 * np.clip(d / max(amp_px, 1), 0, 1))


def horizon_delta(seed=201):
    """Đồng bằng Bắc Bộ: núi xa mờ, hàng cây, lũy tre, mái làng."""
    hz = Horizon(seed)
    haze = (204, 212, 222)
    m = ridge_profile(seed, 0, hz.deg_h(900, 28), 160, ridged=True)
    mask = smoothstep(0.3, 0.6, (noise1d(HZ_W, 260, seed + 3) + 1) / 2)
    hz.layer(m * mask + 0.5, lin((150, 164, 188)), alpha=0.55, haze=0.2, haze_col=haze,
             shade=mountain_shade(hz, m * mask, seed + 30, hz.deg_h(900, 28)))
    # hàng cây rất xa (liền dải, nhạt)
    t1 = hz.crowns(1100, 2.4, (9, 17), (6, 14), base_px=hz.deg_h(6, 2.4), seed=seed + 1, bamboo=0.3)
    t1 = leafy_edge(t1, 1.2, seed + 1)
    hz.layer(t1, lin((120, 140, 136)), alpha=0.85, haze=0.45, haze_col=haze, shade=foliage_shade(hz, t1, 20, seed + 1, 0.5))
    # làng: mái nhà lẫn cây, lũy tre
    houses_row(hz, 90, 1.6, seed + 2, base=0, h_range=(4, 7), tall=0.12)
    t2 = hz.crowns(600, 1.5, (8, 18), (5, 12), seed=seed + 4, bamboo=0.4, gap=0.3)
    t2 = leafy_edge(t2, 1.6, seed + 4)
    hz.layer(t2, lin((88, 110, 82)), alpha=0.95, haze=0.25, haze_col=haze, shade=foliage_shade(hz, t2, 30, seed + 4, 0.8))
    # lũy tre / vườn cây gần
    t3 = hz.crowns(330, 0.55, (9, 16), (5, 10), seed=seed + 5, bamboo=0.5, gap=0.45)
    t3 = leafy_edge(t3, 2.5, seed + 5)
    hz.layer(t3, lin((62, 86, 52)), alpha=1.0, haze=0.06, haze_col=haze, shade=foliage_shade(hz, t3, 60, seed + 5, 1.0))
    houses_row(hz, 8, 0.5, seed + 6, base=0, w_range=(7, 10), h_range=(4, 5), tall=0.0)
    return hz.image()


def horizon_mountain(seed=211):
    """Núi Tây Bắc / đèo Hải Vân: nhiều lớp núi chồng, xa nhạt lam, gần xanh
    thẫm rừng, sườn đón nắng sáng hơn, khe núi tối."""
    hz = Horizon(seed)
    haze = (200, 212, 226)
    layers = [(55, 1900, 0.78, (140, 156, 184), 0.6), (26, 1300, 0.6, (118, 138, 162), 0.8),
              (13, 800, 0.4, (92, 116, 120), 0.95), (6, 420, 0.22, (68, 94, 76), 1.0),
              (2.4, 150, 0.08, (52, 76, 48), 1.0)]
    for i, (km, hgt, hzv, col, alpha) in enumerate(layers):
        amp = hz.deg_h(hgt, km)
        prof = ridge_profile(seed + i * 7, amp * 0.2, amp, 300 / (1 + i * 0.4), ridged=True)
        prof = np.minimum(prof, HZ_H - 6)
        if i >= 3:
            prof = leafy_edge(prof, 1.0 + i * 0.5, seed + i)
        shade = mountain_shade(hz, prof, seed + i * 3, amp)
        hz.layer(prof, lin(col), alpha=alpha, haze=hzv, haze_col=haze, shade=shade)
    return hz.image()


def horizon_coast(seed=221):
    """Biển miền Trung: mũi núi xa mờ, đồi cát trắng, rặng phi lao, xóm chài."""
    hz = Horizon(seed)
    haze = (210, 218, 226)
    xx = np.arange(HZ_W) / HZ_W
    amp = hz.deg_h(900, 12)
    head = amp * np.exp(-((xx - 0.36) / 0.12) ** 2) * (0.8 + 0.2 * ridge_profile(seed, 0, 1, 60) ) + \
        amp * 0.45 * np.exp(-((xx - 0.52) / 0.06) ** 2)
    hz.layer(head + 0.3, lin((130, 150, 172)), alpha=0.7, haze=0.3, haze_col=haze,
             shade=mountain_shade(hz, head, seed, amp))
    dunes = 1.5 + (noise1d(HZ_W, 140, seed + 2) + 1) * hz.deg_h(7, 1.2)
    hz.layer(dunes, lin((222, 210, 180)), alpha=1.0, haze=0.12, haze_col=haze,
             shade=foliage_shade(hz, dunes, 10, seed + 2, 0.3))
    houses_row(hz, 16, 1.4, seed + 5, w_range=(6, 9), h_range=(3, 5), tall=0.0, base=4,
               colors=[((96, 110, 130), (214, 214, 206)), ((150, 80, 60), (230, 222, 200))])
    rng = np.random.default_rng(seed + 3)
    top = dunes.copy()
    gapm = (noise1d(HZ_W, 70, seed + 4) + 1) / 2
    for i in range(700):
        x = rng.uniform(0, HZ_W)
        if gapm[int(x) % HZ_W] < 0.3:
            continue
        hm = rng.uniform(10, 18)
        km = rng.uniform(0.45, 0.9)
        hp = hz.deg_h(hm, km)
        wp = hz.deg_w(rng.uniform(4, 7), km)
        for sh in (-HZ_W, 0, HZ_W):
            c = x + sh
            a, b = int(max(0, c - wp)), int(min(HZ_W, c + wp + 1))
            if b <= a:
                continue
            t = (np.arange(a, b) - c) / wp
            prof = dunes[a:b] + hp * np.clip(1 - np.abs(t) ** 1.6, 0, 1) ** 0.8
            top[a:b] = np.maximum(top[a:b], prof)
    top = leafy_edge(gblur_wrap_x(top[None, :], 1.2)[0], 2.0, seed + 3, 2.5)
    hz.layer(top, lin((80, 98, 82)), alpha=1.0, haze=0.1, haze_col=haze, shade=foliage_shade(hz, top, 50, seed + 3, 1.1))
    # chân rặng cây lộ cát
    hz.layer(dunes * 0.6, lin((214, 202, 174)), alpha=1.0, haze=0.08, haze_col=haze,
             shade=foliage_shade(hz, dunes * 0.6, 8, seed + 8, 0.3))
    return hz.image()


def horizon_city(seed=231):
    """Thị xã nhìn từ xa: nhà cao tầng mờ lam, dãy nhà ống, tháp nước, cột
    ăng-ten, vài vòm cây."""
    hz = Horizon(seed)
    rng = np.random.default_rng(seed)
    haze = (204, 212, 222)
    for i in range(34):
        km = rng.uniform(2.5, 6)
        x = rng.uniform(0, HZ_W)
        wp = hz.deg_w(rng.uniform(18, 40), km)
        hp = hz.deg_h(rng.uniform(40, 100), km)
        col = lin((158, 170, 188)) * rng.uniform(0.92, 1.08)
        for sh in (-HZ_W, 0, HZ_W):
            c = x + sh
            a, b = int(max(0, c - wp / 2)), int(min(HZ_W, c + wp / 2 + 1))
            if b <= a:
                continue
            ys = slice(int(HZ_H - hp), HZ_H)
            sub = hz.rgb[ys, a:b]
            shade = np.ones((sub.shape[0], b - a))
            shade[:, :max(1, (b - a) // 3)] = 1.12
            for k in range(0, sub.shape[0], 3):
                shade[k, :] *= 0.9
            for k in range(1, b - a, 3):
                shade[:, k] *= 0.95
            al = 0.75
            hz.rgb[ys, a:b] = sub * (1 - al) + col * shade[..., None] * al
            hz.a[ys, a:b] = 1 - (1 - hz.a[ys, a:b]) * (1 - al)
    t0 = hz.crowns(500, 2.0, (8, 14), (6, 12), seed=seed + 9, gap=0.2)
    hz.layer(leafy_edge(t0, 1, seed + 9), lin((120, 138, 132)), alpha=0.85, haze=0.45, haze_col=haze,
             shade=foliage_shade(hz, t0, 15, seed + 9, 0.5))
    houses_row(hz, 220, 1.1, seed + 2, w_range=(4, 9), h_range=(7, 15), tall=0.2,
               colors=[((200, 196, 186), (232, 220, 196)), ((120, 110, 104), (214, 222, 226)),
                       ((170, 92, 70), (236, 206, 160)), ((96, 104, 112), (220, 196, 196)),
                       ((140, 140, 136), (198, 214, 200))])
    for i in range(3):
        x = int(rng.uniform(10, HZ_W - 10))
        hp = int(hz.deg_h(rng.uniform(40, 55), 1.2))
        for k in range(hp):
            w = max(1, int((hp - k) / hp * 4))
            hz.rgb[HZ_H - k - 1, x - w // 2:x + w // 2 + 1] = lin((80, 84, 90))
            hz.a[HZ_H - k - 1, x - w // 2:x + w // 2 + 1] = 1
    for i in range(2):
        x = int(rng.uniform(40, HZ_W - 40))
        hp = int(hz.deg_h(30, 1.0))
        tw = int(hz.deg_w(10, 1.0))
        for k in range(int(hp * 0.7)):
            for lx in (x - tw // 3, x + tw // 3):
                hz.rgb[HZ_H - k - 1, lx] = lin((110, 112, 116))
                hz.a[HZ_H - k - 1, lx] = 1
        yy = HZ_H - hp
        hz.rgb[yy:yy + int(hp * 0.3), x - tw // 2:x + tw // 2] = lin((186, 188, 190))
        hz.rgb[yy:yy + int(hp * 0.3), x - tw // 2:x - tw // 6] = lin((210, 212, 214))
        hz.a[yy:yy + int(hp * 0.3), x - tw // 2:x + tw // 2] = 1
    t = hz.crowns(200, 0.6, (7, 13), (4, 9), seed=seed + 4, gap=0.55)
    t = leafy_edge(t, 2, seed + 4)
    hz.layer(t, lin((62, 86, 54)), alpha=1.0, haze=0.06, haze_col=haze, shade=foliage_shade(hz, t, 40, seed + 4))
    houses_row(hz, 60, 0.55, seed + 6, w_range=(4, 6), h_range=(7, 14), tall=0.1,
               colors=[((200, 196, 186), (236, 214, 170)), ((150, 80, 60), (214, 226, 230)),
                       ((120, 110, 104), (230, 200, 190)), ((110, 110, 110), (240, 232, 214))])
    return hz.image()


# ======================================================= Cổng chào Tết
def arch_tet():
    """Cổng chào đầu làng ngày Tết: hai trụ đỏ viền vàng có mũ mái cong, xà
    ngang chữ "CHÀO MỪNG VỀ QUÊ ĂN TẾT", đèn lồng, cành mai cành đào. Lòng
    cổng và phía trên trong suốt. Cổng rộng 26 m (mép ngoài hai trụ); ảnh có
    thêm lề [M] mỗi bên cho mũ trụ và cành hoa, giữa ảnh là giữa đường."""
    SPAN, H, M = 26.0, 8.0, 0.9
    W = SPAN + 2 * M
    f = Facade(W, H, 58, ss=2, seed=301)
    red = lin((188, 22, 24))
    gold = lin((232, 182, 58))
    pw = 1.5
    L, R = M, M + SPAN  # mép ngoài trụ trái / phải

    def redfn(X, Y):
        return red[None, None, :] * (0.9 + 0.15 * fbm(X * 2, Y * 2, seed=3, octaves=3))[..., None]
    for x0 in (L, R - pw):
        cx = x0 + pw / 2
        f.paint(f.rect(x0 - 0.1, 0, x0 + pw + 0.1, 0.7), plaster_fn(f, (176, 170, 160), 7), h=0.9, mat=M_TRIM)
        f.paint(f.rect(x0 - 0.15, 0.6, x0 + pw + 0.15, 0.72), lin((196, 190, 180)), h=0.95, mat=M_TRIM)
        f.paint(f.rect(x0, 0.72, x0 + pw, 6.2), redfn, h=0.75, mat=M_SIGN)
        for (a, b) in ((x0, x0 + 0.08), (x0 + pw - 0.08, x0 + pw)):
            f.paint(f.rect(a, 0.72, b, 6.2), gold, h=0.8)
        f.paint(f.rect(x0 + 0.18, 1.1, x0 + pw - 0.18, 4.6), gold, h=0.78)
        f.paint(f.rect(x0 + 0.24, 1.16, x0 + pw - 0.24, 4.54), red * 0.85, h=0.77)
        words = ['AN', 'KHANG', 'THỊNH', 'VƯỢNG'] if x0 == L else ['VẠN', 'SỰ', 'NHƯ', 'Ý']
        for k, wd in enumerate(words):
            f.paint(f.text_mask(wd, 'paytone', 0.27, cx, 4.1 - k * 0.8, max_w=pw - 0.55), gold, hadd=0.004)
        # mũ trụ: mái cong lợp ngói vàng, đầu đao vểnh
        f.paint(f.rect(x0 - 0.2, 6.2, x0 + pw + 0.2, 6.35), gold, h=0.95)
        f.paint(f.poly([(x0 - 0.55, 6.4), (x0 + pw + 0.55, 6.4), (x0 + pw + 0.15, 7.1), (x0 - 0.15, 7.1)]),
                lambda X, Y: lin((214, 164, 52))[None, None, :] * (0.85 + 0.2 * (np.mod(Y * 8, 1) > 0.25))[..., None],
                h=lambda X, Y: 1.1 - (Y - 6.4) * 0.5, mat=M_ROOF)
        for sx in (-1, 1):
            tip = (x0 - 0.75, 6.75) if sx < 0 else (x0 + pw + 0.75, 6.75)
            base = (x0 - 0.4, 6.4) if sx < 0 else (x0 + pw + 0.4, 6.4)
            f.paint(f.lines([base, ((base[0] + tip[0]) / 2, 6.45), tip], 0.12), gold, h=1.1)
        f.paint(f.ellipse(cx, 7.25, 0.22, 0.22), lin((240, 200, 70)), h=1.0)
    # xà ngang + biển chữ
    y0, y1 = 5.0, 6.55
    f.paint(f.rect(L + pw - 0.1, y0, R - pw + 0.1, y1), redfn, h=0.85, mat=M_SIGN)
    for (a, b, c, d) in ((L + pw, y1 - 0.1, R - pw, y1), (L + pw, y0, R - pw, y0 + 0.1)):
        f.paint(f.rect(a, b, c, d), gold, h=0.9)
    # mề đay vàng hai đầu xà
    for sx in (L + pw + 1.0, R - pw - 1.0):
        cy = (y0 + y1) / 2
        f.paint(f.ellipse(sx, cy, 0.5, 0.5), gold, h=0.92)
        f.paint(f.ellipse(sx, cy, 0.42, 0.42), red * 0.9, h=0.91)
        for k in range(5):
            a = math.pi / 2 + k * math.tau / 5
            f.paint(f.ellipse(sx + math.cos(a) * 0.15, cy + math.sin(a) * 0.15, 0.12, 0.12), gold, h=0.95)
        f.paint(f.ellipse(sx, cy, 0.07, 0.07), lin((210, 110, 30)), h=0.97)
    cx = W / 2
    tm = f.text_mask('CHÀO MỪNG VỀ QUÊ ĂN TẾT', 'paytone', 0.82, cx, (y0 + y1) / 2 - 0.02, max_w=SPAN - 2 * pw - 3.4)
    if tm[0] is not None:
        sl, m = tm
        f.paint((sl, np.clip(gblur(m, 2.0) * 2.5, 0, 1) * 0.8), red * 0.4)
        f.paint(tm, lin((252, 214, 72)), hadd=0.01)
    # chóp giữa: bông mai vàng lớn + chữ XUÂN
    f.paint(f.poly([(cx - 2.2, y1), (cx + 2.2, y1), (cx + 1.2, y1 + 0.75), (cx - 1.2, y1 + 0.75)]), redfn, h=0.85,
            mat=M_SIGN)
    f.paint(f.lines([(cx - 2.2, y1 + 0.02), (cx - 1.2, y1 + 0.77), (cx + 1.2, y1 + 0.77), (cx + 2.2, y1 + 0.02)], 0.09),
            gold, h=0.9)
    for k in range(5):
        a = math.pi / 2 + k * math.tau / 5
        f.paint(f.ellipse(cx + math.cos(a) * 0.32, y1 + 0.38 + math.sin(a) * 0.26, 0.22, 0.2), lin((250, 206, 50)),
                h=0.95)
    f.paint(f.ellipse(cx, y1 + 0.38, 0.13, 0.12), lin((210, 110, 30)), h=1.0)
    f.paint(f.rect(cx - 0.8, y1 + 0.85, cx + 0.8, y1 + 1.3), red, h=0.85)
    f.paint(f.rect(cx - 0.8, y1 + 0.85, cx + 0.8, y1 + 0.89), gold, h=0.86)
    f.paint(f.text_mask('XUÂN', 'paytone', 0.28, cx, y1 + 1.07, max_w=1.4), gold, h=0.9)
    # đèn lồng dưới xà
    for k in range(6):
        lx = L + pw + 1.8 + k * (SPAN - 2 * pw - 3.6) / 5
        lantern(f, lx, y0, r=0.38, h=1.0, string=0.2)
    # cành mai (trái) và cành đào (phải) vắt ở hai đầu xà
    rng = np.random.default_rng(5)
    for side, petal in ((0, (248, 200, 40)), (1, (240, 150, 176))):
        x_attach = L + pw - 0.2 if side == 0 else R - pw + 0.2
        tips = []

        def br(x, y, a, ln, wdt, depth):
            x2, y2 = x + math.cos(a) * ln, y + math.sin(a) * ln
            f.paint(f.lines([(x, y), (x2, y2)], wdt), lin((70, 50, 40)), h=1.05, mat=M_WOOD)
            tips.extend([(x2, y2), ((x + x2) / 2, (y + y2) / 2)])
            if depth:
                for da in (-0.45, 0.4):
                    br(x2, y2, a + da + rng.normal(0, 0.15), ln * 0.7, wdt * 0.7, depth - 1)
        base_a = math.radians(25) if side == 0 else math.radians(155)
        br(x_attach, y1 + 0.1, base_a, 1.0, 0.08, 3)
        br(x_attach, y0 + 0.2, -base_a if side == 0 else math.radians(205), 0.85, 0.07, 3)
        for (x, y) in tips:
            for k in range(9):
                fx, fy = x + rng.normal(0, 0.12), min(y + rng.normal(0, 0.12), H - 0.1)
                f.paint(f.ellipse(fx, fy, 0.05, 0.05), lin(petal) * math.exp(rng.normal(0, 0.1)),
                        h=1.1 + rng.uniform(0, 0.05), mat=M_PLANT)
                f.paint(f.ellipse(fx, fy, 0.016, 0.016), lin((200, 100, 30)) if side == 0 else lin((190, 60, 100)),
                        hadd=0.01)
    return f.render(), H


# ======================================================= Danh mục + xuất
def save_png(im, path):
    im.save(path, optimize=True)


VEG = {
    # tên file: (hàm dựng, chiều cao ảnh px, loại)
    'tree_broad_1': (tree_bang, 600, 'tree_broad'),
    'tree_broad_2': (tree_xacu, 620, 'tree_broad'),
    'tree_broad_3': (tree_keo, 580, 'tree_broad'),
    'tree_broad_4': (tree_sau, 600, 'tree_broad'),
    'tree_bamboo_1': (bamboo_1, 600, 'bamboo'),
    'tree_bamboo_2': (bamboo_2, 620, 'bamboo'),
    'banana_1': (banana_1, 420, 'banana'),
    'banana_2': (banana_2, 420, 'banana'),
    'palm_coconut_1': (palm_1, 640, 'palm'),
    'palm_coconut_2': (palm_2, 600, 'palm'),
    'tree_casuarina_1': (casuarina_1, 620, 'casuarina'),
    'tree_casuarina_2': (casuarina_2, 560, 'casuarina'),
    'tree_pine_1': (pine_1, 640, 'pine'),
    'tree_pine_2': (pine_2, 600, 'pine'),
    'bush_1': (bush_1, 300, 'bush'),
    'bush_2': (bush_2, 300, 'hedge'),
    'bush_3': (bush_3, 360, 'grass'),
    'flower_peach_1': (flower_peach_1, 440, 'flower_tree'),
    'flower_apricot_1': (flower_apricot_1, 400, 'flower_tree'),
}
SKIES = {'sky_day': 'day', 'sky_dusk': 'dusk', 'sky_night': 'night'}
HORIZONS = {'horizon_delta': horizon_delta, 'horizon_mountain': horizon_mountain, 'horizon_coast': horizon_coast,
            'horizon_city': horizon_city}
ALL = list(VEG) + list(TOWN) + list(VILLAGE) + ['wall_side_1', 'wall_side_2', 'wall_side_3'] + list(SKIES) + \
    list(HORIZONS) + ['arch_tet']


def build_one(args):
    """Dựng một hình, ghi file, trả về (tên, mục scenery.json)."""
    name, out = args
    t0 = time.time()
    path = os.path.join(out, name + '.png')
    if name in VEG:
        fn, px, kind = VEG[name]
        plant, kw = fn()
        im, h = plant.render(px, **kw)
        save_png(im, path)
        meta = {'h_m': round(float(h), 2), 'kind': kind}
    elif name in TOWN:
        im, h = tube_house(TOWN[name])
        save_png(im, path)
        meta = {'h_m': round(float(h), 2), 'kind': 'house_town', 'floors': TOWN[name]['floors'],
                'facade_w_m': TOWN[name]['width']}
    elif name in VILLAGE:
        im, h = village_house(VILLAGE[name])
        save_png(im, path)
        meta = {'h_m': round(float(h), 2), 'kind': 'house_village', 'facade_w_m': VILLAGE[name]['width']}
    elif name.startswith('wall_side_'):
        kind, seed = {'wall_side_1': ('yellow', 401), 'wall_side_2': ('cement', 402),
                      'wall_side_3': ('brick', 403)}[name]
        im = wall_side(kind, seed=seed)
        save_png(im, path)
        meta = {'kind': 'wall_tile', 'tile_m': 3.0, 'material': {'yellow': 'plaster_yellow',
                                                                  'cement': 'plaster_cement',
                                                                  'brick': 'brick'}[kind]}
    elif name in SKIES:
        im = sky_image(SKIES[name], seed={'day': 1, 'dusk': 2, 'night': 3}[SKIES[name]])
        save_png(im, path)
        meta = {'kind': 'sky', 'span_deg': SKY_SPAN, 'el_deg': [0.0, SKY_EL], 'tile_x': True}
    elif name in HORIZONS:
        im = HORIZONS[name]()
        save_png(im, path)
        meta = {'kind': 'horizon', 'span_deg': HZ_SPAN, 'el_deg': [0.0, HZ_EL], 'tile_x': True}
    elif name == 'arch_tet':
        im, h = arch_tet()
        save_png(im, path)
        meta = {'h_m': round(float(h), 2), 'kind': 'arch', 'span_m': 26.0,
                'note': 'mép ngoài hai trụ rộng 26 m; ảnh có lề 0.9 m mỗi bên'}
    else:
        raise KeyError(name)
    w, hh = im.size
    if 'h_m' in meta:
        meta['w_m'] = round(meta['h_m'] * w / hh, 2)
    meta['px'] = [w, hh]
    print(f'  {name:20s} {w}x{hh}  {os.path.getsize(path) / 1024:.0f} KB  {time.time() - t0:.1f}s', flush=True)
    return name, meta


def _padw(im, w):
    out = Image.new('RGBA', (w, im.height), (250, 250, 248, 255))
    out.paste(im, ((w - im.width) // 2, 0))
    return out


def contact_sheet(out, names, meta, path):
    """Tấm xem nhanh: mỗi hình trên nền trời / ô caro, kèm tên và cỡ."""
    cells = []
    for n in names:
        p = os.path.join(out, n + '.png')
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert('RGBA')
        k = meta.get(n, {}).get('kind', '')
        if k in ('sky', 'horizon'):
            tw = 900
            im2 = im.resize((tw, int(im.height * tw / im.width)), Image.LANCZOS)
            if k == 'horizon':
                bg = Image.new('RGBA', im2.size, (184, 200, 220, 255))
                bg.alpha_composite(im2)
                im2 = bg
            # lặp hai lần để kiểm tra mối nối
            both = Image.new('RGBA', (im2.width * 2, im2.height))
            both.paste(im2, (0, 0))
            both.paste(im2, (im2.width, 0))
            cells.append((n, both.resize((tw, int(both.height / 2)), Image.LANCZOS) if False else both))
            continue
        th = 300
        if k == 'wall_tile':
            t = Image.new('RGBA', (im.width * 2, im.height))
            t.paste(im, (0, 0))
            t.paste(im, (im.width, 0))
            im = t
        sc = th / im.height
        im2 = im.resize((max(1, int(im.width * sc)), th), Image.LANCZOS)
        bg = Image.new('RGBA', im2.size, (190, 206, 224, 255))
        bg.alpha_composite(im2)
        cells.append((n, bg))
    pad = 12
    W = 1900
    lab_w = 150
    cells = [(n, im if im.width >= lab_w else _padw(im, lab_w)) for n, im in cells]
    rows, row, x = [], [], 0
    for n, im in cells:
        if x + im.width > W and row:
            rows.append(row)
            row, x = [], 0
        row.append((n, im))
        x += im.width + pad
    if row:
        rows.append(row)
    H = sum(max(i.height for _, i in r) + 30 for r in rows) + pad
    sheet = Image.new('RGB', (W, H), (250, 250, 248))
    d = ImageDraw.Draw(sheet)
    fnt = font('semi', 14)
    y = pad
    for r in rows:
        x = pad
        rh = max(i.height for _, i in r)
        for n, im in r:
            sheet.paste(im.convert('RGB'), (x, y + rh - im.height))
            m = meta.get(n, {})
            lab = n + (f"  {m['h_m']}m" if 'h_m' in m else '')
            d.text((x, y + rh + 4), lab, fill=(40, 40, 40), font=fnt)
            x += im.width + pad
        y += rh + 30
    sheet.save(path)


def main():
    out = OUT
    sheet = None
    args = sys.argv[1:]
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet = args[i + 1]
        args = args[:i] + args[i + 2:]
    names = [a for a in args if not a.startswith('-')] or ALL
    bad = [n for n in names if n not in ALL]
    if bad:
        sys.exit(f'Không có hình: {bad}')
    os.makedirs(out, exist_ok=True)
    t0 = time.time()
    print(f'Dựng {len(names)} hình → {out}')
    # hình nặng chạy trước cho các nhân CPU bận đều
    heavy = ['tree_broad_2', 'tree_broad_4', 'tree_broad_3', 'tree_bamboo_2', 'tree_pine_2', 'tree_casuarina_1']
    order = sorted(names, key=lambda n: (n not in heavy, ALL.index(n)))
    with mp.Pool(min(8, os.cpu_count() or 4)) as pool:
        results = pool.map(build_one, [(n, out) for n in order], chunksize=1)
    js = os.path.join(out, 'scenery.json')
    meta = {}
    if os.path.exists(js):
        with open(js) as fh:
            meta = json.load(fh)
    for n, m in results:
        meta[n] = m
    meta = {k: meta[k] for k in sorted(meta, key=lambda k: ALL.index(k) if k in ALL else 999)}
    with open(js, 'w') as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    total = sum(os.path.getsize(os.path.join(out, n + '.png')) for n in meta if os.path.exists(os.path.join(out, n + '.png')))
    print(f'Xong {len(results)} hình trong {time.time() - t0:.0f}s; tổng {total / 1e6:.1f} MB')
    if sheet:
        contact_sheet(out, list(meta), meta, sheet)
        print('Tấm xem nhanh:', sheet)


if __name__ == '__main__':
    main()
