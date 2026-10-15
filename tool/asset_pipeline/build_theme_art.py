"""Vân mặt đất + cây cối / đồ vật nhìn từ trên xuống cho các bản đồ theo vùng.

Ba kiểu cảnh mới (ngoài đồng bằng Bắc Bộ sẵn có):
- Duyên hải miền Trung: cát trắng, cát ướt, biển, bọt sóng, bụi cây khô ven
  biển, hàng phi lao, thúng chai, xương rồng, đá.
- Đèo núi (Hải Vân / Tây Bắc): vách đá xẻ, rừng rậm dưới thung lũng, thông,
  ruộng bậc thang, tảng đá.
- Miền Tây sông nước: kênh rạch nước phù sa có lục bình, dừa nước, dừa,
  xoài, tre, xuồng ba lá.

Không cần ảnh nguồn hay Blender: mọi thứ dựng bằng "bản đồ độ cao 2,5D".
Mỗi hình là một khung vẽ có bộ đệm độ cao (z-buffer): lá, tàu dừa, cành,
tán cây, gợn cát, phiến đá… là các khối nguyên thuỷ (vòm elip, dải lá thon có
gân gấp chữ V, ống tròn) được "đóng dấu" kèm pháp tuyến giải tích, màu, độ
bóng, độ trong của lá. Sau đó đổ sáng gần với vật lý:
- nắng cùng hướng tây bắc như các hình xe (SUN của build_vehicles_3d.py),
- bóng đổ mềm trong chính bản đồ độ cao (dò tia ngược về phía mặt trời),
- che khuất môi trường (AO) theo đường chân trời 8 hướng,
- trời bán cầu, ánh xuyên lá, phản xạ nắng (lá bóng, mặt nước),
rồi tone-map ACES như các hình xe 3D, vẽ to gấp SS lần rồi thu nhỏ cho mịn.
Vân lặp liền mạch: khung vẽ "cuộn" (wrap) nên khối nguyên thuỷ, bóng đổ và AO
đều vòng qua mép ảnh.

Hình lẻ (cây, thuyền, đá) có nền trong suốt và KHÔNG nướng bóng đổ xuống đất
(game tự vẽ bóng theo hình). Vì game xoay cây ngẫu nhiên, phần đổ sáng theo
hướng nắng trên toàn tán được giữ nhẹ; chiều sâu chủ yếu đến từ bóng tự đổ
trong tán và AO (trông đúng ở mọi góc xoay).

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_theme_art.py              # tất cả
    python tool/asset_pipeline/build_theme_art.py sand palm    # chỉ vài mục
    python tool/asset_pipeline/build_theme_art.py --out DIR    # xuất ra chỗ khác
    python tool/asset_pipeline/build_theme_art.py --list       # liệt kê mục
"""
import math
import os
import sys
import time

import numpy as np
from PIL import Image

OUT = 'assets/images'

# Nắng: cùng hướng với build_vehicles_3d.py (x sang phải ảnh, y xuống dưới
# ảnh, z hướng lên trời) → nắng chiếu từ phía trên - bên trái ảnh.
SUN = np.array([-0.42, -0.58, 0.70])
SUN /= np.linalg.norm(SUN)
SUN_COL = np.array([1.0, 0.95, 0.86]) * 2.9
SKY_IRR = np.array([0.52, 0.62, 0.82]) * 0.95
GROUND_IRR = np.array([0.30, 0.28, 0.25]) * 0.55
EXPOSURE = 0.62
HALF = SUN + np.array([0.0, 0.0, 1.0])
HALF /= np.linalg.norm(HALF)


def lin(rgb):
    """Màu sRGB 0..255 → tuyến tính."""
    return (np.asarray(rgb, np.float64) / 255.0) ** 2.2


def tonemap(c):
    """ACES (giống build_vehicles_3d.py) → sRGB 0..1."""
    c = np.maximum(c, 0) * EXPOSURE
    a, b, cc, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    t = np.clip((c * (a * c + b)) / (c * (cc * c + d) + e), 0, 1)
    return t ** (1 / 2.2)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ================================================================ Nhiễu
def periodic_noise(h, w, sigma, seed):
    """Nhiễu mượt lặp liền mạch (lọc Gauss trong miền tần số), 0..1."""
    r = np.random.default_rng(seed)
    white = r.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    kernel = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * kernel))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def fbm_noise(h, w, sigmas, seed, weights=None):
    """Cộng nhiều tầng nhiễu lặp liền mạch, chuẩn hoá về 0..1."""
    weights = weights or [0.5 ** i for i in range(len(sigmas))]
    out = sum(wt * (periodic_noise(h, w, s, seed + 17 * i) - 0.5) for i, (s, wt) in enumerate(zip(sigmas, weights)))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def sample_wrap(img, x, y):
    """Lấy mẫu song tuyến tính có cuộn mép (img 2D hoặc 3D)."""
    h, w = img.shape[:2]
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    x0 %= w
    y0 %= h
    x1, y1 = (x0 + 1) % w, (y0 + 1) % h
    if img.ndim == 3:
        fx, fy = fx[..., None], fy[..., None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy)
            + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


def shift(a, dx, dy, wrap, fill):
    """b[y, x] = a[y + dy, x + dx] (dịch nguyên điểm ảnh)."""
    if wrap:
        return np.roll(a, (-dy, -dx), axis=(0, 1))
    h, w = a.shape[:2]
    out = np.full_like(a, fill)
    ys, yd = (slice(dy, h), slice(0, h - dy)) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
    xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    if abs(dx) < w and abs(dy) < h:
        out[yd, xd] = a[ys, xs]
    return out


def blur(a, sigma, wrap=True):
    """Làm mờ Gauss bằng FFT (cuộn mép); không cuộn thì đệm rồi cắt."""
    if sigma <= 0:
        return a
    if not wrap:
        p = int(sigma * 3) + 2
        pad = [(p, p), (p, p)] + [(0, 0)] * (a.ndim - 2)
        return blur(np.pad(a, pad, mode='edge'), sigma, True)[p:-p, p:-p]
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    if a.ndim == 3:
        return np.stack([np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * k)) for c in range(a.shape[2])], -1)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * k))


def poisson_disk(w, h, r, rng, k=24, wrap=True, limit=100000):
    """Rải điểm cách đều ngẫu nhiên (Bridson), khoảng cách tối thiểu r."""
    cell = r / math.sqrt(2)
    gw, gh = int(math.ceil(w / cell)), int(math.ceil(h / cell))
    grid = -np.ones((gh, gw), int)
    pts = []

    def ok(x, y):
        gx, gy = int(x / cell), int(y / cell)
        for j in range(gy - 2, gy + 3):
            for i in range(gx - 2, gx + 3):
                if wrap:
                    jj, ii = j % gh, i % gw
                elif not (0 <= j < gh and 0 <= i < gw):
                    continue
                else:
                    jj, ii = j, i
                q = grid[jj, ii]
                if q >= 0:
                    dx = abs(pts[q][0] - x)
                    dy = abs(pts[q][1] - y)
                    if wrap:
                        dx, dy = min(dx, w - dx), min(dy, h - dy)
                    if dx * dx + dy * dy < r * r:
                        return False
        return True

    first = (rng.uniform(0, w), rng.uniform(0, h))
    pts.append(first)
    grid[int(first[1] / cell), int(first[0] / cell)] = 0
    active = [0]
    while active and len(pts) < limit:
        idx = active[rng.integers(len(active))]
        px, py = pts[idx]
        for _ in range(k):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(r, 2 * r)
            x, y = px + math.cos(a) * d, py + math.sin(a) * d
            if wrap:
                x, y = x % w, y % h
            elif not (0 <= x < w and 0 <= y < h):
                continue
            if ok(x, y):
                pts.append((x, y))
                grid[int(y / cell) % gh, int(x / cell) % gw] = len(pts) - 1
                active.append(len(pts) - 1)
                break
        else:
            active.remove(idx)
    return pts


# ====================================================== Khung vẽ cao độ
FOLIAGE, WOOD, GROUND, ROCK, WATER, CLOTH = 1, 2, 3, 4, 5, 6


class Canvas:
    """Bộ đệm độ cao + màu + pháp tuyến. Toạ độ theo điểm ảnh ĐẦU RA (đơn vị
    u); bên trong vẽ to gấp [ss] lần. z cũng tính bằng u (cao lên trời)."""

    def __init__(self, w, h, ss=3, wrap=False, floor=-1e9):
        self.w, self.h, self.ss, self.wrap = w, h, ss, wrap
        W, H = w * ss, h * ss
        self.floor = floor
        self.z = np.full((H, W), floor, np.float32)
        self.alb = np.zeros((H, W, 3), np.float32)
        self.nrm = np.zeros((H, W, 3), np.float32)
        self.nrm[..., 2] = 1
        self.gloss = np.zeros((H, W), np.float32)   # độ bóng (phản xạ nắng)
        self.trans = np.zeros((H, W), np.float32)   # ánh xuyên lá
        self.mat = np.zeros((H, W), np.uint8)
        self.cov = np.zeros((H, W), bool)

    # -------------------------------------------------------------- Vẽ
    def put(self, x0, y0, x1, y1, fn):
        """Gọi fn(X, Y) trên lưới điểm ảnh con trong hộp [x0, x1]×[y0, y1] (u).
        fn trả về (mask, z, alb, nrm(3 mảng), gloss, trans, mat) hoặc None.
        Điểm nào cao hơn điểm đang có thì ghi đè (z-buffer)."""
        ss = self.ss
        W, H = self.w * ss, self.h * ss
        if self.wrap:
            offs = [(ox, oy) for ox in (-self.w, 0, self.w) for oy in (-self.h, 0, self.h)]
        else:
            offs = [(0, 0)]
        for ox, oy in offs:
            ix0 = max(int(math.floor((x0 + ox) * ss)), 0)
            ix1 = min(int(math.ceil((x1 + ox) * ss)) + 1, W)
            iy0 = max(int(math.floor((y0 + oy) * ss)), 0)
            iy1 = min(int(math.ceil((y1 + oy) * ss)) + 1, H)
            if ix0 >= ix1 or iy0 >= iy1:
                continue
            Y, X = np.mgrid[iy0:iy1, ix0:ix1].astype(np.float32)
            X = (X + 0.5) / ss - ox
            Y = (Y + 0.5) / ss - oy
            res = fn(X, Y)
            if res is None:
                continue
            m, z, alb, nrm, gloss, trans, mat = res
            sub_z = self.z[iy0:iy1, ix0:ix1]
            upd = m & (z > sub_z)
            if not upd.any():
                continue
            sub_z[upd] = np.broadcast_to(z, upd.shape)[upd]
            sa = self.alb[iy0:iy1, ix0:ix1]
            sa[upd] = np.broadcast_to(alb, upd.shape + (3,))[upd]
            sn = self.nrm[iy0:iy1, ix0:ix1]
            nx, ny, nz = nrm
            ln = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9
            for c, comp in enumerate((nx / ln, ny / ln, nz / ln)):
                sc = sn[..., c]
                sc[upd] = np.broadcast_to(comp, upd.shape)[upd]
            for arr, val in ((self.gloss, gloss), (self.trans, trans), (self.mat, mat)):
                s = arr[iy0:iy1, ix0:ix1]
                s[upd] = np.broadcast_to(val, upd.shape)[upd]
            self.cov[iy0:iy1, ix0:ix1] |= upd

    def dome(self, cx, cy, rx, ry, z0, hgt, alb, ang=0.0, gloss=0.0, trans=0.0, mat=FOLIAGE,
             wob=None, alb_fn=None, flat=1.0, tilt=(0.0, 0.0)):
        """Vòm nửa elip (tán lá, khóm, quả, đá tròn). [wob] = (biên độ, seed)
        làm méo viền theo góc; [alb_fn](q, X, Y) cho màu theo vị trí."""
        r = max(rx, ry) * (1.3 if wob else 1.0)
        ca, sa = math.cos(ang), math.sin(ang)
        if wob:
            amp, seed = wob
            rr = np.random.default_rng(seed)
            ph = rr.uniform(0, math.tau, 6)
            ks = [2, 3, 4, 5, 7, 9]

        def fn(X, Y):
            dx, dy = X - cx, Y - cy
            u = (dx * ca + dy * sa) / rx
            v = (-dx * sa + dy * ca) / ry
            q = u * u + v * v
            if wob:
                th = np.arctan2(v, u)
                e = 1.0 + sum(amp / k ** 0.6 * np.sin(k * th + ph[i]) for i, k in enumerate(ks)) * 0.5
                q = q / (e * e)
            m = q < 1
            if not m.any():
                return None
            s = np.sqrt(np.clip(1 - q, 0.0, 1))
            z = z0 + hgt * s
            g = hgt / np.maximum(s, 0.12)
            # đạo hàm z theo u, v rồi quay về X, Y
            dzu = -g * u / rx
            dzv = -g * v / ry
            dzx = (dzu * ca - dzv * sa) * flat + tilt[0]
            dzy = (dzu * sa + dzv * ca) * flat + tilt[1]
            if tilt[0] or tilt[1]:
                z = z + tilt[0] * dx + tilt[1] * dy
            a = alb if alb_fn is None else alb_fn(q, X, Y)
            return m, z, a, (-dzx, -dzy, np.ones_like(z)), gloss, trans, mat
        self.put(cx - r, cy - r, cx + r, cy + r, fn)

    def strip(self, a, b, w0, w1, alb, prof='taper', fold=0.0, round_=0.0, gloss=0.0, trans=0.0,
              mat=FOLIAGE, alb_fn=None, cap=True):
        """Dải thẳng từ a=(x,y,z) tới b: lá thon ('leaf'), thuôn đều ('taper'),
        lá mác ('lance'). [fold] = độ dốc gấp chữ V hai bên gân giữa (gân cao
        hơn mép khi > 0); [round_] = độ phồng tròn (cành, ống tre, mạn thuyền).
        [alb_fn](t, s) → màu theo vị trí dọc t ∈ 0..1 / ngang s ∈ −1..1."""
        ax, ay, az = a
        bx, by, bz = b
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        if L < 1e-3:
            L = 1e-3
        ux, uy = dx / L, dy / L
        dzdl = (bz - az) / L
        wm = max(w0, w1)
        ext = wm if cap else 0.0

        def fn(X, Y):
            px, py = X - ax, Y - ay
            t = (px * ux + py * uy) / L
            s = -px * uy + py * ux
            if prof == 'leaf':      # bầu ở giữa, nhọn hai đầu
                wid = w0 * np.clip(np.sin(np.pi * np.clip(t, 0, 1)), 0, 1) ** 0.75
            elif prof == 'lance':   # lá mác: rộng ở 1/3 gốc, mũi dài nhọn
                tc = np.clip(t, 0, 1)
                wid = w0 * np.clip(np.where(tc < 0.3, np.clip(np.sin(np.minimum(tc, 0.3) / 0.3 * np.pi / 2), 0, 1) ** 0.6,
                                            (1 - tc) / 0.7), 0, 1) ** 0.9
            elif prof == 'base':    # nửa gốc lá: thắt ở cuống rồi nở ra
                wid = w0 * np.clip(np.clip(t, 0, 1) / 0.3, 0.15, 1) ** 0.6
            elif prof == 'end':     # nửa ngọn lá: thon dần tới mũi nhọn
                wid = w0 * np.clip(1 - np.clip(t, 0, 1), 0, 1) ** 0.65
            else:                   # thuôn đều, đầu tròn
                wid = w0 + (w1 - w0) * np.clip(t, 0, 1)
            if prof == 'taper' and cap:
                # bo tròn hai đầu
                tt = np.where(t < 0, -t * L, np.where(t > 1, (t - 1) * L, 0.0))
                inside = (tt * tt + s * s) < wid * wid
            else:
                inside = (t >= 0) & (t <= 1) & (np.abs(s) < wid)
            m = inside & (wid > 0.02)
            if not m.any():
                return None
            wsafe = np.maximum(wid, 1e-3)
            q = np.clip(s / wsafe, -1, 1)
            zc = az + (bz - az) * np.clip(t, 0, 1)
            if round_ > 0:
                rr = np.sqrt(np.clip(1 - q * q, 0.02, 1))
                z = zc + round_ * wsafe * rr
                dzds = -round_ * q / rr
            else:
                z = zc - fold * np.abs(s)
                dzds = -fold * np.sign(s)
            dzx = dzdl * ux - dzds * uy
            dzy = dzdl * uy + dzds * ux
            al = alb if alb_fn is None else alb_fn(np.clip(t, 0, 1), q)
            return m, z, al, (-dzx, -dzy, np.ones_like(z)), gloss, trans, mat
        self.put(min(ax, bx) - ext - wm, min(ay, by) - ext - wm, max(ax, bx) + ext + wm, max(ay, by) + ext + wm, fn)

    def path(self, pts, widths, alb, **kw):
        """Đường cong = chuỗi dải thuôn (cành, sống lá, cọng tre)."""
        for i in range(len(pts) - 1):
            self.strip(pts[i], pts[i + 1], widths[i], widths[i + 1], alb, prof='taper', **kw)

    def field(self, zfield, alb, gloss=0.0, trans=0.0, mat=GROUND, mask=None):
        """Phủ cả khung bằng một trường độ cao (mặt đất). zfield/alb ở độ phân
        giải trong (h·ss, w·ss)."""
        H, W = self.z.shape
        m = np.ones((H, W), bool) if mask is None else mask
        upd = m & (zfield > self.z)
        self.z[upd] = zfield[upd]
        self.alb[upd] = np.broadcast_to(alb, (H, W, 3))[upd]
        gy, gx = np.gradient(zfield * self.ss)
        if self.wrap:
            gx = (np.roll(zfield, -1, 1) - np.roll(zfield, 1, 1)) * 0.5 * self.ss
            gy = (np.roll(zfield, -1, 0) - np.roll(zfield, 1, 0)) * 0.5 * self.ss
        n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        self.nrm[upd] = n[upd]
        self.gloss[upd] = np.broadcast_to(gloss, (H, W))[upd]
        self.trans[upd] = np.broadcast_to(trans, (H, W))[upd]
        self.mat[upd] = mat
        self.cov |= upd

    def grid(self):
        """Toạ độ (X, Y) theo u của mọi điểm ảnh con."""
        H, W = self.z.shape
        Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
        return (X + 0.5) / self.ss, (Y + 0.5) / self.ss

    # --------------------------------------------------------- Đổ sáng
    def shadow(self, max_len, pen=0.05, z=None):
        """Bóng đổ mềm trong bản đồ độ cao: đi ngược về phía mặt trời, chỗ nào
        có điểm cao hơn tia nắng thì bị che (nửa tối rộng dần theo khoảng
        cách)."""
        ss = self.ss
        z = self.z if z is None else z
        d = SUN[:2] / np.linalg.norm(SUN[:2])
        tan_e = SUN[2] / np.linalg.norm(SUN[:2])
        vis = np.ones_like(z)
        n = int(max_len * ss)
        t = 1.0
        while t <= n:
            ox, oy = int(round(t * d[0])), int(round(t * d[1]))
            zs = shift(z, ox, oy, self.wrap, self.floor)
            tu = t / ss
            diff = zs - (z + tu * tan_e)
            wdt = pen * tu + 0.35
            vis = np.minimum(vis, np.clip(0.5 - diff / (2 * wdt), 0, 1))
            t += 1.0 if t < 24 else (2.0 if t < 96 else 3.0)
        return vis * vis * (3 - 2 * vis)

    def ao(self, radius, dirs=8, z=None):
        """Che khuất môi trường theo đường chân trời (horizon-based AO)."""
        ss = self.ss
        z = self.z if z is None else z
        occ = np.zeros_like(z)
        steps = []
        t = 1.0
        while t <= radius * ss:
            steps.append(t)
            t = t * 1.45 + 0.6
        for k in range(dirs):
            a = (k + 0.5) / dirs * math.tau
            ca, sa = math.cos(a), math.sin(a)
            best = np.zeros_like(z)
            for t in steps:
                ox, oy = int(round(t * ca)), int(round(t * sa))
                if ox == 0 and oy == 0:
                    continue
                zs = shift(z, ox, oy, self.wrap, self.floor)
                best = np.maximum(best, (zs - z) / (t / ss))
            occ += best / np.sqrt(1 + best * best)
        return 1 - occ / dirs

    def render(self, shadow_len=60, pen=0.05, ao_rad=12, ao_amt=1.0, wrap_light=0.25,
               shadow_floor=0.0, trans_col=(0.55, 0.62, 0.12), sun_dir_mix=1.0, spec_pow=40,
               sky_spec=0.08, bg=None, water=None):
        """Đổ sáng → (rgb sRGB 0..1, alpha) ở độ phân giải đầu ra. [water](col,
        vis, ao, mask) tô lại các điểm mặt nước (vật liệu WATER)."""
        n = self.nrm
        # Đổ sáng dịu theo hướng nắng (cây bị xoay ngẫu nhiên): pha giữa nắng
        # thật và nắng gần đỉnh đầu.
        sun_l = SUN * sun_dir_mix + np.array([0, 0, 1.0]) * (1 - sun_dir_mix)
        sun_l /= np.linalg.norm(sun_l)
        ndl_raw = n[..., 0] * sun_l[0] + n[..., 1] * sun_l[1] + n[..., 2] * sun_l[2]
        wl = wrap_light
        ndl = np.clip((ndl_raw + wl) / (1 + wl), 0, 1)
        vis = self.shadow(shadow_len, pen) if shadow_len > 0 else np.ones_like(self.z)
        vis = shadow_floor + (1 - shadow_floor) * vis
        ao = self.ao(ao_rad) if ao_rad > 0 else np.ones_like(self.z)
        ao = 1 - ao_amt * (1 - ao)
        hemi = 0.5 + 0.5 * n[..., 2]
        amb = (SKY_IRR * hemi[..., None] + GROUND_IRR * (1 - hemi)[..., None]) * ao[..., None]
        alb = self.alb
        col = alb * (SUN_COL * (ndl * vis)[..., None] + amb)
        # ánh xuyên lá: lá mỏng được nắng rọi từ phía sau / lá trên che
        tr = self.trans * (0.35 + 0.65 * vis) * np.clip(1 - ndl_raw * 0.5, 0, 1.5)
        col += alb * np.array(trans_col) * SUN_COL * tr[..., None] * 0.35
        # phản xạ nắng (Blinn-Phong) + trời
        nh = np.clip(n[..., 0] * HALF[0] + n[..., 1] * HALF[1] + n[..., 2] * HALF[2], 0, 1)
        spec = self.gloss * nh ** spec_pow * vis * (spec_pow + 8) / 25
        col += SUN_COL * spec[..., None] * 0.35
        col += SKY_IRR * (self.gloss * sky_spec * ao)[..., None]
        if water is not None:
            wm = self.mat == WATER
            if wm.any():
                col = water(col, vis, ao, wm)
        rgb = tonemap(col)
        cov = self.cov.astype(np.float32)
        if bg is not None:
            rgb = np.where(self.cov[..., None], rgb, bg)
            cov = np.ones_like(cov)
        return self.down(rgb, cov)

    def down(self, rgb, cov):
        ss = self.ss
        h, w = self.h, self.w
        pre = (rgb * cov[..., None]).reshape(h, ss, w, ss, 3).mean((1, 3))
        a = cov.reshape(h, ss, w, ss).mean((1, 3))
        out = np.where(a[..., None] > 1e-4, pre / np.maximum(a[..., None], 1e-4), 0)
        return out, a


def to_image(rgb, alpha=None):
    """rgb sRGB 0..1 (+ alpha 0..1) → ảnh PIL."""
    c = np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8)
    if alpha is None:
        return Image.fromarray(c)
    a = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([c, a]))


def save_jpg(img, name):
    img.convert('RGB').save(f'{OUT}/{name}.jpg', quality=86, optimize=True)


def save_png(img, name):
    if img.mode == 'RGBA' and not name.startswith('tex_'):
        a = np.asarray(img)[..., 3]
        if max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max()) > 24:
            print(f'  ! {name}: hình chạm mép ảnh', flush=True)
    img.save(f'{OUT}/{name}.png', optimize=True)


def jit(rng, rgb, amt=0.08):
    """Màu tuyến tính lệch ngẫu nhiên nhẹ (độ sáng + sắc)."""
    base = lin(rgb)
    k = 1 + rng.uniform(-amt, amt)
    hue = 1 + rng.uniform(-amt * 0.5, amt * 0.5, 3)
    return base * k * hue


def mix(a, b, t):
    return np.asarray(a) * (1 - t) + np.asarray(b) * t


_ACES_C = np.linspace(0, 12, 6000)
_ACES_T = tonemap(_ACES_C / EXPOSURE)


def look(rgb):
    """Albedo tuyến tính để một mặt phẳng nằm ngang, nắng chiếu đủ, hiện ra
    đúng màu sRGB [rgb] sau đổ sáng + tone-map (giúp chỉnh màu theo ảnh thật)."""
    t = np.asarray(rgb, np.float64) / 255.0
    c = np.interp(t, _ACES_T, _ACES_C)
    E = SUN_COL * SUN[2] + SKY_IRR
    return c / EXPOSURE / E


def add_detail(cv, sigma, alb_amt, bump, seed, mats=(FOLIAGE,)):
    """Vân lá li ti: loang màu + gồ ghề pháp tuyến cho các điểm thuộc [mats]."""
    H, W = cv.z.shape
    nz = periodic_noise(H, W, sigma, seed)
    nz = (nz - nz.mean()) / (nz.std() + 1e-9)
    m = np.isin(cv.mat, mats) & cv.cov
    k = np.clip(1 + alb_amt * nz, 0.3, 2.0)
    cv.alb[m] *= k[m][:, None]
    if bump:
        gx = (np.roll(nz, -1, 1) - np.roll(nz, 1, 1)) * 0.5
        gy = (np.roll(nz, -1, 0) - np.roll(nz, 1, 0)) * 0.5
        n = cv.nrm.copy()
        n[..., 0] -= bump * gx
        n[..., 1] -= bump * gy
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        cv.nrm[m] = n[m]


# ===================================================== Vân: rừng, đá núi
def tex_forest():
    """Tán rừng nhiệt đới nhìn từ trên cao: tán cây sát nhau kiểu súp lơ, mỗi
    tán một sắc xanh (xanh đậm, xanh lam, ô liu, vàng chanh, vài cây lá non đỏ
    đồng), cây vượt tán cao đổ bóng xuống cây thấp, khe giữa tán tối sâu."""
    S = 512
    cv = Canvas(S, S, ss=2, wrap=True)
    rng = np.random.default_rng(101)
    X, Y = cv.grid()
    # Tầng dưới tán: bụi rậm thấp, tối.
    under = fbm_noise(*cv.z.shape, [24, 8, 3], seed=5)
    cv.field(under * 10.0, lin((34, 48, 30)) * (0.7 + 0.6 * under[..., None]), mat=FOLIAGE, trans=0.3)
    palette = [((54, 78, 46), 5), ((66, 90, 50), 5), ((82, 102, 56), 3), ((56, 82, 64), 3),
               ((92, 108, 60), 2), ((76, 84, 54), 2), ((104, 116, 66), 1), ((100, 86, 64), 0.4),
               ((46, 66, 46), 3)]
    cols = [lin(c) for c, _ in palette]
    wts = np.array([w for _, w in palette], float)
    wts /= wts.sum()
    pts = poisson_disk(S, S, 30, rng)
    for (x, y) in pts:
        R = rng.uniform(20, 38)
        if rng.random() < 0.08:
            R *= 1.45  # cây vượt tán
        top = rng.uniform(18, 40) + R * 0.7
        base = cols[rng.choice(len(cols), p=wts)] * rng.uniform(0.85, 1.12)
        hgt = R * 0.55
        z0 = top - hgt
        cv.dome(x, y, R, R * rng.uniform(0.85, 1.1), z0 - 4, hgt, base * 0.8, ang=rng.uniform(0, 3.14),
                wob=(0.35, int(rng.integers(1 << 30))), trans=0.4)
        nb = int(10 + R * R / 26)
        for _ in range(nb):
            rho = R * 0.92 * math.sqrt(rng.random())
            a = rng.uniform(0, math.tau)
            bx, by = x + math.cos(a) * rho, y + math.sin(a) * rho
            r = R * rng.uniform(0.2, 0.36) * (1.1 - 0.3 * rho / R)
            zs = z0 + hgt * math.sqrt(max(0.0, 1 - (rho / R) ** 2))
            c = base * rng.uniform(0.82, 1.18) * (1 + rng.uniform(-0.06, 0.06, 3))
            cv.dome(bx, by, r, r * rng.uniform(0.8, 1.1), zs - r * 0.55, r * 0.75, c,
                    ang=rng.uniform(0, 3.14), wob=(0.5, int(rng.integers(1 << 30))), trans=0.5)
    add_detail(cv, 0.9, 0.22, 2.2, seed=7)
    add_detail(cv, 2.5, 0.12, 1.5, seed=8)
    rgb, _ = cv.render(shadow_len=70, pen=0.06, ao_rad=18, ao_amt=1.0, wrap_light=0.3, sun_dir_mix=1.0)
    save_jpg(to_image(rgb), 'tex_forest')


# ================================================================ Dừa
def frond_frame(T):
    """Hệ trục của một điểm trên sống lá: T (tiếp tuyến 3D) → S ngang, U lên."""
    T = T / np.linalg.norm(T)
    S = np.array([-T[1], T[0], 0.0])
    ns = np.linalg.norm(S)
    S = S / ns if ns > 1e-6 else np.array([1.0, 0.0, 0.0])
    U = np.cross(S, T)
    if U[2] < 0:
        U = -U
    return T, S, U


def pinnate_frond(cv, rng, origin, az, length, e0, curl, sweep, lmax, n_leaf, alpha, hang,
                  leaf_col, rib_col, wid=1.7, fold=0.7, gap=0.06, tip_col=None, gloss=0.15,
                  trans=0.6, rib_w=(2.6, 0.7), leaf_start=0.08, leaf_droop=0.35, curve_l=0.0):
    """Tàu lá kép lông chim (dừa, dừa nước, cau): sống lá uốn vòng cung, lá
    chét hai bên rủ xuống thành hình chữ V nhìn từ trên."""
    ox, oy, oz = origin
    npt = 16
    pts = [(ox, oy, oz)]
    tans = []
    x, y, z = ox, oy, oz
    seg = length / (npt - 1)
    for k in range(1, npt):
        t = (k - 0.5) / (npt - 1)
        phi = e0 - curl * t ** 1.4
        th = az + sweep * t
        T = np.array([math.cos(phi) * math.cos(th), math.cos(phi) * math.sin(th), math.sin(phi)])
        tans.append(T)
        x, y, z = x + T[0] * seg, y + T[1] * seg, z + T[2] * seg
        pts.append((x, y, z))
    tans.append(tans[-1])
    widths = [rib_w[0] + (rib_w[1] - rib_w[0]) * k / (npt - 1) for k in range(npt)]
    cv.path(pts, widths, rib_col, round_=0.55, gloss=0.1, mat=FOLIAGE)
    P = np.array(pts)
    for side in (-1, 1):
        for j in range(n_leaf):
            t = leaf_start + (0.985 - leaf_start) * (j + rng.uniform(-0.3, 0.3)) / n_leaf
            if rng.random() < gap:
                continue
            f = t * (npt - 1)
            i0 = min(int(f), npt - 2)
            fr = f - i0
            p = P[i0] * (1 - fr) + P[i0 + 1] * fr
            T, S, U = frond_frame(tans[min(i0, len(tans) - 1)])
            ll = lmax * (0.32 + 0.68 * math.sin(math.pi * min(1.0, 0.18 + t * 1.05)) ** 0.8) * rng.uniform(0.85, 1.1)
            a = alpha + rng.uniform(-0.12, 0.12)
            hb = hang * (0.7 + 0.6 * t) + rng.uniform(-0.12, 0.12)
            D = math.cos(a) * T + math.sin(a) * (math.cos(hb) * S * side - math.sin(hb) * U)
            D /= np.linalg.norm(D)
            # lá chét cong rủ: hai đoạn, đoạn ngoài cắm xuống thêm
            mid = p + D * ll * 0.55
            D2 = D + np.array([0, 0, -leaf_droop]) + S * side * curve_l + T * abs(curve_l)
            D2 /= np.linalg.norm(D2)
            end = mid + D2 * ll * 0.45
            c = leaf_col * rng.uniform(0.86, 1.14) * (1 + rng.uniform(-0.05, 0.05, 3))
            tc = c if tip_col is None else tip_col

            def afn2(tt, q, c=c, tc=tc):
                k = (tt ** 2)[..., None]
                return c * (1 - k) + tc * k
            w = wid * rng.uniform(0.85, 1.15)
            cv.strip(tuple(p), tuple(mid), w, w, c, prof='base', fold=fold, gloss=gloss, trans=trans, cap=False)
            cv.strip(tuple(mid - D2 * 0.3), tuple(end), w, w, c, prof='end', fold=fold, gloss=gloss, trans=trans, alb_fn=afn2, cap=False)
    return P


def coconut_palm(seed, n_fr=24, reach=124, droop=1.0, leaf=(84, 106, 48), young=(108, 124, 58),
                 nuts=((84, 112, 40), (100, 118, 42)), dead=3, gap=0.05, size=256):
    """Ngọn dừa nhìn từ trên: 20–26 tàu lá xếp xoắn ốc (góc vàng), tàu non
    dựng đứng ở giữa, tàu già rủ thấp, vài tàu khô nâu dưới cùng; chùm dừa
    xanh lấp ló quanh nõn. Lá chét hẹp, rủ xuống hai bên sống lá nên nhìn từ
    trên thấy khe hở giữa các lá chét."""
    S = size
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    cx = cy = S / 2
    # Đầu thân + bẹ lá (xơ nâu)
    cv.dome(cx, cy, 12, 12, -36, 16, lin((84, 68, 46)), mat=WOOD)
    # Tàu khô nâu rủ sát thân
    for k in range(dead):
        az = rng.uniform(0, math.tau)
        pinnate_frond(cv, rng, (cx + 4 * math.cos(az), cy + 4 * math.sin(az), -24), az, reach * 0.6,
                      math.radians(-20), math.radians(45), rng.uniform(-0.3, 0.3), reach * 0.16, 26,
                      math.radians(50), math.radians(60), lin((120, 94, 60)), lin((132, 106, 68)),
                      wid=1.1, fold=0.5, gap=0.35, tip_col=lin((100, 80, 52)), gloss=0.0, trans=0.1)
    # Chùm dừa
    nb = int(rng.integers(3, 6))
    for b in range(nb):
        az = b / nb * math.tau + rng.uniform(-0.4, 0.4)
        d0 = rng.uniform(9, 13)
        bx, by = cx + math.cos(az) * d0, cy + math.sin(az) * d0
        col = lin(nuts[rng.integers(len(nuts))])
        for _ in range(int(rng.integers(5, 10))):
            a2 = rng.uniform(0, math.tau)
            r2 = rng.uniform(0, 6.0)
            nr = rng.uniform(3.0, 3.6)
            c = col * rng.uniform(0.85, 1.15)
            cv.dome(bx + math.cos(a2) * r2, by + math.sin(a2) * r2, nr, nr * rng.uniform(0.85, 1.0),
                    -14 - r2 * 0.6 - rng.uniform(0, 3), nr, c, ang=a2, gloss=0.35, trans=0.0, mat=WOOD)
    # Tàu xanh: i = 0 non nhất (giữa, dựng đứng), lớn dần là tàu già.
    golden = math.pi * (3 - math.sqrt(5))
    rot = rng.uniform(0, math.tau)
    lc, yc = lin(leaf), lin(young)
    for i in range(n_fr):
        age = i / (n_fr - 1)
        az = rot + i * golden + rng.uniform(-0.12, 0.12)
        L = reach * rng.uniform(0.92, 1.05) * (0.55 + 0.45 * min(1.0, age * 3.0))
        e0 = math.radians(68 - 80 * age ** 0.8)
        curl = math.radians(40 + 45 * age) * droop
        col = mix(yc, lc, min(1.0, age * 2.2)) * (1 - 0.15 * age)
        tip = col * np.array([1.25, 1.05, 0.75]) if age > 0.45 else col
        rib = col * np.array([1.55, 1.4, 1.15])
        lmax = L * 0.23
        o = (cx + math.cos(az) * 3.5, cy + math.sin(az) * 3.5, -10 * age - 1)
        pinnate_frond(cv, rng, o, az, L, e0, curl, rng.choice([-1, 1]) * rng.uniform(0.15, 0.5), lmax, 36,
                      math.radians(rng.uniform(42, 56)), math.radians(30 + 28 * age), col, rib,
                      wid=1.05, fold=0.9, gap=gap + 0.05 * age, tip_col=tip, gloss=0.12, trans=0.5,
                      leaf_droop=0.5 + 0.35 * age, rib_w=(2.2, 0.6), curve_l=-0.25)
    add_detail(cv, 0.8, 0.10, 0.6, seed=seed + 3)
    rgb, a = cv.render(shadow_len=120, pen=0.03, ao_rad=10, ao_amt=0.8, wrap_light=0.15,
                       sun_dir_mix=0.8, shadow_floor=0.08, trans_col=(0.45, 0.5, 0.15))
    return to_image(rgb, a)


def palms_coconut():
    specs = [dict(seed=11), dict(seed=12, n_fr=22, leaf=(92, 110, 50), young=(116, 128, 60), droop=1.15,
                                  nuts=((128, 110, 46), (96, 116, 42))),
             dict(seed=13, n_fr=26, leaf=(82, 104, 48), reach=120, gap=0.09, dead=4)]
    for k, sp in enumerate(specs):
        save_png(coconut_palm(**sp), f'img_palm_coconut_{k + 1}')


# ============================================================ Dừa nước
def nipa_clump(seed, n_ros=3, size=256, spread=34):
    """Bụi dừa nước ven kênh nhìn từ trên: không thân, mỗi gốc một hoa thị
    6–9 tàu lá mọc thẳng từ bùn rồi vươn dài, uốn cong ở ngọn; lá chét cứng,
    bóng, xếp dày, ít rủ (khác lá dừa mềm rủ). Nhiều gốc mọc chen thành bụi."""
    S = size
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c0 = S / 2
    base_ang = rng.uniform(0, math.tau)
    centres = []
    for k in range(n_ros):
        a = base_ang + k / n_ros * math.tau + rng.uniform(-0.4, 0.4)
        d = 0 if k == 0 else spread * rng.uniform(0.7, 1.1)
        centres.append((c0 + math.cos(a) * d * 0.9, c0 + math.sin(a) * d * 0.6))
    lc = look((96, 118, 50))
    for k, (cx, cy) in enumerate(centres):
        # bẹ lá nâu ở gốc
        cv.dome(cx, cy, 7, 7, -64, 6, look((96, 78, 52)), mat=WOOD)
        nf = int(rng.integers(10, 14))
        rot = rng.uniform(0, math.tau)
        for i in range(nf):
            age = i / max(nf - 1, 1)
            az = rot + i * 2.4 + rng.uniform(-0.2, 0.2)
            # hướng ra ngoài bụi nhiều hơn vào trong
            ox, oy = cx - c0, cy - c0
            if math.hypot(ox, oy) > 1:
                out = math.atan2(oy, ox)
                az = out + math.atan2(math.sin(az - out), math.cos(az - out)) * 0.75
            L = rng.uniform(106, 128) * (0.85 if k else 1.0)
            e0 = math.radians(rng.uniform(52, 66) - 16 * age)
            curl = math.radians(rng.uniform(50, 66) + 22 * age)
            col = lc * (1.12 - 0.25 * age) * rng.uniform(0.9, 1.1)
            dead = rng.random() < 0.04
            if dead:
                col = look((136, 110, 68))
            rib = col * np.array([1.15, 1.1, 0.95])
            pinnate_frond(cv, rng, (cx, cy, -62), az, L, e0, curl, rng.uniform(-0.2, 0.2), L * 0.15, 40,
                          math.radians(rng.uniform(52, 62)), math.radians(12 + 14 * age), col, rib,
                          wid=1.25, fold=0.6, gap=0.04 if not dead else 0.3, tip_col=col * np.array([1.12, 1.02, 0.8]),
                          gloss=0.5, trans=0.45, leaf_start=0.22, leaf_droop=0.15, rib_w=(2.6, 0.7), curve_l=-0.1)
    add_detail(cv, 0.8, 0.08, 0.5, seed=seed + 3)
    rgb, a = cv.render(shadow_len=130, pen=0.03, ao_rad=10, ao_amt=0.8, wrap_light=0.15,
                       sun_dir_mix=0.8, shadow_floor=0.08, trans_col=(0.45, 0.5, 0.15), spec_pow=30)
    return to_image(rgb, a)


def palms_nipa():
    save_png(nipa_clump(21, n_ros=3), 'img_palm_nipa_1')
    save_png(nipa_clump(22, n_ros=3, spread=30), 'img_palm_nipa_2')


# ============================================================== Phi lao
def casuarina(seed, size=192, R=84, col=(80, 98, 72), dry=0.05):
    """Phi lao nhìn từ trên: tán tròn hơi nhọn ở giữa (cây dáng tháp) gồm
    nhiều tầng cụm lá xốp; mặt cụm có thớ mảnh toả ra ngoài như lông tơ (vô số
    cành con dạng lá kim rủ xuống), mép cụm tua tủa sợi lá rủ, màu xanh xám,
    vài chỗ ngả nâu khô; kẽ hở tối lộ cành."""
    S = size
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c = S / 2
    base = look(col)
    clumps = []
    # cụm lá: đỉnh ở giữa, các tầng toả ra ngoài thấp dần
    for (px, py) in poisson_disk(2 * R, 2 * R, 11, rng, wrap=False):
        x, y = px - R + c, py - R + c
        rr = math.hypot(x - c, y - c) / R
        th = math.atan2(y - c, x - c)
        edge = 1 + 0.1 * math.sin(3 * th + seed) + 0.06 * math.sin(7 * th + 2 * seed)
        if rr > edge * 0.86:
            continue
        r = rng.uniform(9, 15) * (1.15 - 0.35 * rr)
        z = -30 * rr ** 1.3 - rng.uniform(0, 6)
        clumps.append((x, y, r, z, th))
    for (x, y, r, z, th) in clumps:
        tc = base * rng.uniform(0.85, 1.15) * (1 + rng.uniform(-0.05, 0.05, 3))
        if rng.random() < dry:
            tc = mix(tc, look((134, 118, 86)), 0.7)
        cv.dome(x, y, r, r * rng.uniform(0.8, 1.0), z - r * 0.5, r * 0.6, tc, ang=th,
                wob=(0.5, int(rng.integers(1 << 30))), trans=0.45)
        # sợi lá rủ ở mép cụm
        for _ in range(int(r * 2.2)):
            a = th + rng.normal(0, 1.3)
            sx, sy = x + math.cos(a) * r * 0.7, y + math.sin(a) * r * 0.7
            L = rng.uniform(4, 8)
            sz = z - r * 0.15
            cc = tc * rng.uniform(0.9, 1.2)
            cv.strip((sx, sy, sz), (sx + math.cos(a) * L, sy + math.sin(a) * L, sz - L * 0.7), 0.45, 0.12, cc,
                     prof='taper', round_=0.5, trans=0.6, cap=False)
    # thớ lông tơ: nhiễu kéo dài theo hướng toả ra từ tâm cây
    X, Y = cv.grid()
    ang = np.arctan2(Y - c, X - c)
    rad = np.hypot(X - c, Y - c)
    tex = periodic_noise(256, 256, 0.9, seed + 7)
    strand = sample_wrap(tex, ((ang / math.tau) % 1) * 256 * 3, rad * 1.1)
    strand = (strand - strand.mean()) / (strand.std() + 1e-6)
    m = cv.mat == FOLIAGE
    cv.alb[m] *= np.clip(1 + 0.22 * strand[m], 0.4, 1.6)[:, None]
    gx = np.gradient(strand, axis=1)
    gy = np.gradient(strand, axis=0)
    cv.nrm[..., 0] -= gx * 0.5 * m
    cv.nrm[..., 1] -= gy * 0.5 * m
    cv.nrm /= np.linalg.norm(cv.nrm, axis=-1, keepdims=True)
    add_detail(cv, 0.7, 0.10, 0.5, seed=seed + 5)
    rgb, a = cv.render(shadow_len=50, pen=0.05, ao_rad=8, ao_amt=0.9, wrap_light=0.3,
                       sun_dir_mix=0.75, shadow_floor=0.15, trans_col=(0.4, 0.5, 0.2))
    return to_image(rgb, a)


def trees_casuarina():
    specs = [dict(seed=31, R=78), dict(seed=32, R=76, col=(88, 104, 76)), dict(seed=33, R=80, col=(72, 92, 68), dry=0.1)]
    for k, sp in enumerate(specs):
        save_png(casuarina(**sp), f'img_tree_casuarina_{k + 1}')


# ================================================================ Thông
def needle_tuft(cv, rng, x, y, z, r, col, n=None, up=0.4):
    """Túm lá thông: lá kim toả hình sao từ đầu cành, giữa vểnh lên."""
    n = n or int(18 + r * 2.2)
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        el = rng.uniform(-0.6, up + 0.6)
        L = r * rng.uniform(0.6, 1.0)
        h = L * math.cos(el)
        p2 = (x + math.cos(a) * h, y + math.sin(a) * h, z + L * math.sin(el))
        cc = col * rng.uniform(0.85, 1.18)
        cv.strip((x, y, z), p2, 0.38, 0.14, cc, prof='taper', round_=0.5, gloss=0.15, trans=0.35, cap=False)


def pine(seed, size=192, R=84, col=(56, 84, 60), tip=(100, 120, 72)):
    """Thông ba lá (Đà Lạt, Tây Bắc) nhìn từ trên: cành toả theo tầng từ
    ngọn, tầng dưới dài hơn; lá kim mọc thành túm hình sao ở đầu cành, xanh
    đậm ngả lam, chồi non sáng hơn; tán thưa, lộ cành nâu."""
    S = size
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c = S / 2
    base, tipc = look(col), look(tip)
    wood = look((98, 76, 56))
    needle_tuft(cv, rng, c, c, 0, 9, mix(base, tipc, 0.5), n=50, up=0.9)
    n_whorl = 7
    for w in range(n_whorl):
        t = (w + 1) / n_whorl
        zt = -8 - t * 70
        nb = int(rng.integers(5, 8))
        rot = rng.uniform(0, math.tau)
        for b in range(nb):
            a = rot + b / nb * math.tau + rng.uniform(-0.3, 0.3)
            L = R * (0.3 + 0.7 * t ** 0.8) * rng.uniform(0.75, 1.05)
            if rng.random() < 0.15 and w < n_whorl - 1:
                continue
            bend = rng.uniform(-0.25, 0.25)
            pts = []
            for k in range(5):
                s = k / 4
                aa = a + bend * s
                pts.append((c + math.cos(aa) * L * s, c + math.sin(aa) * L * s, zt + L * 0.18 * s - L * 0.12 * s * s))
            cv.path(pts, [2.0, 1.6, 1.2, 0.9, 0.6], wood, round_=0.6, mat=WOOD)
            # túm lá dọc nửa ngoài cành + cành con
            for k in range(int(4 + L / 8)):
                s = 0.97 if k == 0 else rng.uniform(0.3, 1.0)
                aa = a + bend * s + (rng.normal(0, 0.35) if k else 0.0)
                d = L * s
                px, py = c + math.cos(aa) * d, c + math.sin(aa) * d
                pz = zt + L * 0.18 * s - L * 0.12 * s * s + rng.uniform(0, 4)
                cc = mix(base, tipc, rng.uniform(0, 0.5) * s) * rng.uniform(0.85, 1.15)
                needle_tuft(cv, rng, px, py, pz, rng.uniform(7, 12), cc)
    add_detail(cv, 0.7, 0.10, 0.4, seed=seed + 5)
    rgb, a = cv.render(shadow_len=80, pen=0.05, ao_rad=10, ao_amt=0.8, wrap_light=0.3,
                       sun_dir_mix=0.75, shadow_floor=0.18, trans_col=(0.35, 0.45, 0.2))
    return to_image(rgb, a)


def trees_pine():
    specs = [dict(seed=41), dict(seed=42, R=78, col=(60, 88, 62)), dict(seed=43, R=88, col=(50, 78, 58), tip=(92, 112, 68))]
    for k, sp in enumerate(specs):
        save_png(pine(**sp), f'img_tree_pine_{k + 1}')


# ================================================================== Tre
def bamboo(seed, size=224, n_culm=64, reach=70, col=(116, 142, 60)):
    """Bụi tre nhìn từ trên: các cây tre mọc từ gốc bụi vươn chéo ra ngoài và
    uốn cong rủ ngọn; cành nhỏ ở nửa ngoài mang những xoè lá mác mảnh, xanh
    vàng, trong mờ; giữa bụi thấy ngọn thân tre xanh vàng và lá khô."""
    S = size
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c = S / 2
    base = look(col)
    culm_col = look((150, 150, 80))
    cv.dome(c, c, 14, 14, -90, 6, look((112, 96, 64)), mat=WOOD)   # lá khô ở gốc
    for i in range(n_culm):
        a = rng.uniform(0, math.tau)
        L = reach * rng.uniform(0.75, 1.1)
        e0 = math.radians(rng.uniform(64, 82))
        curl = math.radians(rng.uniform(90, 130))
        x0, y0 = c + math.cos(a) * rng.uniform(0, 10), c + math.sin(a) * rng.uniform(0, 10)
        pts = [(x0, y0, -90.0)]
        x, y, z = pts[0]
        nseg = 14
        H = L * 1.3
        for k in range(1, nseg + 1):
            t = (k - 0.5) / nseg
            phi = e0 - curl * t ** 1.5
            aa = a + 0.2 * math.sin(i + t * 2)
            x += math.cos(phi) * math.cos(aa) * H / nseg
            y += math.cos(phi) * math.sin(aa) * H / nseg
            z += math.sin(phi) * H / nseg
            pts.append((x, y, z))
        ws = [max(0.3, 1.6 * (1 - k / nseg)) for k in range(nseg + 1)]
        cv.path(pts, ws, culm_col * rng.uniform(0.85, 1.1), round_=0.7, gloss=0.3, mat=WOOD)
        # cành + xoè lá
        for k in range(3, nseg + 1):
            px, py, pz = pts[k]
            for _ in range(int(rng.integers(2, 4))):
                ba = a + rng.normal(0, 1.6)
                bl = rng.uniform(3, 14)
                px2, py2 = px + math.cos(ba) * bl, py + math.sin(ba) * bl
                nl = int(rng.integers(5, 9))
                for j in range(nl):
                    la = ba + (j - nl / 2) * 0.45 + rng.normal(0, 0.25)
                    ll = rng.uniform(8, 13)
                    lz = pz - ll * rng.uniform(0.1, 0.5)
                    cc = base * rng.uniform(0.75, 1.2) * (1 + rng.uniform(-0.07, 0.07, 3))
                    if rng.random() < 0.04:
                        cc = look((170, 150, 90))
                    q = (px2, py2, pz - bl * 0.2)
                    cv.strip(q, (q[0] + math.cos(la) * ll, q[1] + math.sin(la) * ll, lz), 1.5, 0.0, cc,
                             prof='lance', fold=0.25, trans=0.7, gloss=0.15, cap=False)
    add_detail(cv, 0.7, 0.08, 0.4, seed=seed + 5)
    rgb, a = cv.render(shadow_len=110, pen=0.04, ao_rad=10, ao_amt=0.9, wrap_light=0.25,
                       sun_dir_mix=0.75, shadow_floor=0.12, trans_col=(0.5, 0.55, 0.15))
    return to_image(rgb, a)


def bamboo_tops():
    save_png(bamboo(51), 'img_bamboo_top_1')
    save_png(bamboo(52, n_culm=54, reach=66, col=(104, 134, 58)), 'img_bamboo_top_2')


# ================================================================ Xoài
def leaf_rosette(cv, rng, x, y, z, nrm, n, L, W, col, gloss=0.5, droop=0.3, prof='lance', fold=0.35, spin=0.0):
    """Chùm lá toả ở đầu cành (xoài, cây gỗ lá to), nằm theo mặt tán."""
    nx, ny, nz = nrm
    for i in range(n):
        a = spin + i / n * math.tau + rng.uniform(-0.45, 0.45)
        ll = L * rng.uniform(0.7, 1.1)
        dx, dy = math.cos(a), math.sin(a)
        # rủ theo mặt tán: dốc xuống theo hướng pháp tuyến nghiêng
        dz = -(dx * nx + dy * ny) / max(nz, 0.3) * ll - droop * ll
        cc = col * rng.uniform(0.8, 1.2) * (1 + rng.uniform(-0.05, 0.05, 3))
        cv.strip((x, y, z), (x + dx * ll, y + dy * ll, z + dz), W * rng.uniform(0.85, 1.1), 0.0, cc,
                 prof=prof, fold=fold, gloss=gloss, trans=0.4, cap=False)


def mango(seed, size=192, R=84, col=(52, 82, 38), flush=0.0, flowers=0.0):
    """Cây xoài nhìn từ trên: tán tròn dày, kín, xanh sẫm bóng; lá mác mọc
    thành chùm hoa thị ở đầu cành bám theo mặt tán; vài chùm lộc non nâu đỏ
    hoặc chùm hoa xoài vàng kem (mùa Tết)."""
    S = size
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c = S / 2
    base = look(col)
    Hc = R * 0.55

    def surf(x, y):
        rr = min(1.0, math.hypot(x - c, y - c) / R)
        return Hc * math.sqrt(max(0.0, 1 - rr * rr)), rr
    # lõi tán tối (che lỗ hở)
    cv.dome(c, c, R * 0.8, R * 0.8, -6, Hc * 0.8, base * 0.45, wob=(0.2, seed), trans=0.2)
    pts = poisson_disk(2 * R, 2 * R, 6.0, rng, wrap=False)
    order = rng.permutation(len(pts))
    for i in order:
        px, py = pts[i]
        x, y = px - R + c, py - R + c
        th = math.atan2(y - c, x - c)
        edge = R * (1 + 0.07 * math.sin(3 * th + seed) + 0.05 * math.sin(5 * th + 2 * seed))
        if math.hypot(x - c, y - c) > edge * 0.96:
            continue
        z, rr = surf(x, y)
        z += rng.uniform(-3, 3)
        g = Hc / max(math.sqrt(max(1e-3, 1 - rr * rr)), 0.25) / R
        nrm = np.array([(x - c) / R * g, (y - c) / R * g, 1.0])
        nrm /= np.linalg.norm(nrm)
        cc = base * rng.uniform(0.85, 1.15)
        if rng.random() < flush:
            cc = mix(base, look((132, 92, 62)), 0.45) * rng.uniform(0.9, 1.15)
        leaf_rosette(cv, rng, x, y, z, nrm, int(rng.integers(6, 9)), rng.uniform(8, 10.5), 2.5, cc, gloss=0.35,
                     prof='leaf', fold=0.2, spin=rng.uniform(0, math.tau))
        if rng.random() < flowers:
            for _ in range(int(rng.integers(10, 18))):
                fx, fy = x + rng.normal(0, 1.6), y + rng.normal(0, 1.6)
                cv.dome(fx, fy, 0.9, 0.9, z + rng.uniform(1.5, 5), 0.6, look((214, 200, 140)) * rng.uniform(0.85, 1.1),
                        trans=0.3)
    add_detail(cv, 0.7, 0.08, 0.4, seed=seed + 5)
    rgb, a = cv.render(shadow_len=60, pen=0.05, ao_rad=10, ao_amt=0.85, wrap_light=0.25,
                       sun_dir_mix=0.75, shadow_floor=0.15, trans_col=(0.4, 0.45, 0.12), spec_pow=30)
    return to_image(rgb, a)


def trees_mango():
    save_png(mango(61, flush=0.08), 'img_tree_mango_1')
    save_png(mango(62, R=80, col=(56, 84, 40), flowers=0.22), 'img_tree_mango_2')


# ============================================================ Thúng chai
def oar(cv, a, b, blade_len, blade_w, col, z_blade=None):
    """Mái chèo: cán tròn từ a tới b, bản chèo dẹt ở đầu b."""
    ax, ay, az = a
    bx, by, bz = b
    L = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / L, (by - ay) / L
    k = 1 - blade_len / L
    m = (ax + (bx - ax) * k, ay + (by - ay) * k, az + (bz - az) * k)
    cv.strip(a, m, 1.3, 1.3, col, round_=0.8, gloss=0.25, mat=WOOD)
    cv.strip(m, (bx, by, bz if z_blade is None else z_blade), blade_w * 0.5, blade_w, col * 0.92, prof='taper',
             round_=0.15, gloss=0.25, mat=WOOD)


def basket_boat(seed, variant):
    """Thúng chai (thuyền thúng) nhìn từ trên: lòng thúng tròn đan nong mắt
    cáo bằng tre, quét dầu rái / hắc ín sẫm bóng; vành cạp tre to buộc mây /
    dây nhựa từng đoạn; trong thúng có mái chèo, lưới, phao, thùng, ván ngồi.
    Đường kính ~2 m."""
    S = 192
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c = S / 2
    Ro = 84.0
    rim_w = 7.0
    Ri = Ro - rim_w
    D = 36.0
    X, Y = cv.grid()
    dx, dy = X - c, Y - c
    r = np.hypot(dx, dy)
    # lòng thúng
    q = np.clip(r / Ri, 0, 1)
    z_in = -D * (1 - q ** 2.2) ** 0.8
    pitch = 4.2
    u = (dx + dy) / math.sqrt(2) / pitch
    v = (dx - dy) / math.sqrt(2) / pitch
    over = ((np.floor(u) + np.floor(v * 0.5)) % 2) < 1
    fu, fv = u - np.floor(u), v - np.floor(v)
    bump = np.where(over, np.sin(np.pi * fu), np.sin(np.pi * fv)) * 0.6
    gap = np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv)) < 0.06
    z_in = z_in + bump - gap * 0.5
    if variant == 1:
        coat = look((50, 40, 32))
        bamboo_c = look((96, 74, 50))
        worn = smoothstep(0.62, 0.8, periodic_noise(S * 3, S * 3, 9, seed))
    else:
        coat = look((64, 50, 36))
        bamboo_c = look((136, 104, 66))
        worn = smoothstep(0.45, 0.7, periodic_noise(S * 3, S * 3, 9, seed))
    weave = np.where(over, 1.0, 0.86)[..., None] * (0.9 + 0.2 * np.where(over, fv, fu)[..., None])
    alb = mix(coat, bamboo_c, worn[..., None]) * weave
    alb = alb * (1 - 0.5 * gap[..., None])
    gloss = (1 - worn) * 0.55
    inside = r < Ri + 0.5
    cv.field(z_in.astype(np.float32), alb, gloss=gloss, mat=WOOD, mask=inside)
    # vành cạp
    rr = (r - (Ro - rim_w / 2)) / (rim_w / 2)
    z_rim = 3.2 * np.sqrt(np.clip(1 - rr * rr, 0, 1))
    th = np.arctan2(dy, dx)
    lash = (np.cos(th * 60) > 0.55) & (np.abs(rr) < 0.95)
    if variant == 1:
        rim_c = look((54, 96, 150))       # vành sơn xanh
        tie_c = look((214, 212, 200))     # dây buộc trắng
    else:
        rim_c = look((140, 112, 74))      # tre mộc
        tie_c = look((70, 56, 40))
    grain = 0.88 + 0.24 * sample_wrap(periodic_noise(64, 512, 1.5, seed + 1), r * 0.0 + rr * 20 + 32, th / math.tau * 512 * 3)
    ralb = np.where(lash[..., None], tie_c, rim_c * grain[..., None])
    rim_m = np.abs(rr) < 1
    cv.field((z_rim + np.where(lash, 0.5, 0)).astype(np.float32), ralb, gloss=0.25, mat=WOOD, mask=rim_m)
    # vòng tre gia cố bên trong vành
    ri2 = Ri - 3
    ring = np.abs(r - ri2) < 1.2
    cv.field((-D * (1 - (ri2 / Ri) ** 2.2) ** 0.8 + 1.8 * np.sqrt(np.clip(1 - ((r - ri2) / 1.2) ** 2, 0, 1))).astype(np.float32),
             np.broadcast_to(look((120, 96, 64)), (S * 3, S * 3, 3)), gloss=0.2, mat=WOOD, mask=ring)
    if variant == 1:
        # đống lưới cước xanh + phao
        for _ in range(70):
            a = rng.uniform(-1.2, 1.2) + 2.2
            d = rng.uniform(0, 48)
            px, py = c + math.cos(a) * d * 0.9, c + math.sin(a) * d
            rad = rng.uniform(6, 13)
            zb = float(-D * (1 - (min(d, Ri) / Ri) ** 2.2) ** 0.8)
            col = look((52, 110, 96)) if rng.random() < 0.7 else look((60, 92, 140))

            def net_fn(qq, XX, YY, col=col):
                m = (np.sin(XX * 3.1) * np.sin(YY * 3.1) > 0.55)
                return col * np.where(m, 1.35, 0.85)[..., None] * np.ones_like(qq)[..., None]
            cv.dome(px, py, rad, rad * rng.uniform(0.6, 1.0), zb + 4 + rng.uniform(0, 8), rad * 0.45, col,
                    ang=rng.uniform(0, 3.14), wob=(0.6, int(rng.integers(1 << 30))), alb_fn=net_fn, gloss=0.2, mat=CLOTH)
        for _ in range(9):
            a = rng.uniform(1.0, 3.4)
            d = rng.uniform(20, 55)
            px, py = c + math.cos(a) * d, c + math.sin(a) * d
            zb = float(-D * (1 - (min(d, Ri) / Ri) ** 2.2) ** 0.8)
            fc = look((236, 236, 228)) if rng.random() < 0.6 else look((226, 110, 40))
            cv.dome(px, py, 3.6, 2.4, zb + 14, 2.0, fc, ang=rng.uniform(0, 3.14), gloss=0.4, mat=CLOTH)
        oar(cv, (c - 62, c + 40, -6), (c + 70, c - 52, -4), 40, 13, look((150, 116, 76)))
    else:
        # ván ngồi ngang + xô nhựa đỏ + cuộn dây + vũng nước đọng
        a = 0.35
        ux, uy = math.cos(a), math.sin(a)
        cv.strip((c - ux * 74, c - uy * 74, -9), (c + ux * 74, c + uy * 74, -9), 6.5, 6.5, look((150, 120, 84)),
                 round_=0.12, gloss=0.15, mat=WOOD)
        bx, by = c - 26, c + 30
        br = 13
        zb = float(-D * (1 - (math.hypot(26, 30) / Ri) ** 2.2) ** 0.8)
        rb = np.hypot(X - bx, Y - by)
        bucket = rb < br
        zbk = np.where(rb > br - 1.6, zb + 26, zb + 6)
        balb = np.where((rb > br - 1.6)[..., None], look((196, 48, 40)), look((150, 34, 30)))
        cv.field(zbk.astype(np.float32), balb, gloss=0.5, mat=CLOTH, mask=bucket)
        cx2, cy2 = c + 30, c - 26
        for k in range(46):
            t = k / 46 * math.tau * 3.2
            rr2 = 4 + k * 0.22
            cv.dome(cx2 + math.cos(t) * rr2, cy2 + math.sin(t) * rr2, 1.5, 1.5, -24 + k * 0.02, 1.2,
                    look((196, 168, 112)), mat=CLOTH)
        oar(cv, (c - 40, c - 60, -4), (c + 44, c + 58, -6), 38, 12, look((132, 100, 64)))
    add_detail(cv, 0.7, 0.10, 0.3, seed=seed + 3, mats=(WOOD,))
    rgb, a = cv.render(shadow_len=60, pen=0.04, ao_rad=10, ao_amt=0.9, wrap_light=0.1, sun_dir_mix=0.9,
                       spec_pow=40, sky_spec=0.2)
    return to_image(rgb, a)


def boats_basket():
    save_png(basket_boat(71, 1), 'img_boat_basket_1')
    save_png(basket_boat(72, 2), 'img_boat_basket_2')


# ========================================================== Xuồng ba lá
def conical_hat(cv, x, y, z, r, col=(222, 208, 170)):
    """Nón lá nhìn từ trên: chóp nón ở giữa, các vòng nan tre đồng tâm."""
    X, Y = cv.grid()
    d = np.hypot(X - x, Y - y)
    m = d < r
    zf = z - d * 0.62
    rings = 0.92 + 0.08 * np.cos(d * 2.4)
    ribs = 0.97 + 0.03 * np.cos(np.arctan2(Y - y, X - x) * 16)
    alb = look(col) * (rings * ribs)[..., None] * (0.9 + 0.1 * smoothstep(r, r - 1.5, d))[..., None]
    cv.field(zf.astype(np.float32), alb, gloss=0.15, mat=CLOTH, mask=m)


def sampan(seed, variant):
    """Xuồng ba lá miền Tây nhìn từ trên (mũi hướng lên trên ảnh): ba tấm ván
    (đáy + hai be) nhọn hai đầu, dài ~5 m, rộng ~1,1 m; be xuồng có nẹp, sườn
    gỗ ngang lòng, ván ngồi, sạp nhỏ ở mũi / lái. Kiểu 1: người đội nón lá
    ngồi chèo ở lái, chở chậu bông vạn thọ, giỏ bưởi đi chợ Tết. Kiểu 2: xuồng
    neo không người, nước đọng lòng xuồng, mái chèo, cuộn dây."""
    S = 256
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(seed)
    c = S / 2
    L = 226.0
    Wh = 25.0
    D = 11.0
    X, Y = cv.grid()
    t = (Y - c) / (L / 2)
    tc = np.clip(np.abs(t), 0, 1)
    hw = Wh * np.clip(1 - tc ** 2.4, 0, 1) ** 0.75
    s = X - c
    inside_hull = (np.abs(t) < 1) & (np.abs(s) < hw)
    sheer = 7.0 * t * t
    gw = 2.4
    inner_w = np.maximum(hw - gw, 0.01)
    # lòng xuồng: đáy phẳng, be nghiêng
    side = np.clip((inner_w - np.abs(s)) / (inner_w * 0.38), 0, 1)
    depth = D * np.clip(1 - tc ** 3, 0, 1)
    z_in = sheer - 1.5 - depth * side ** 0.8
    # vân gỗ theo chiều dọc + đường ghép ván (đáy | be)
    grain = sample_wrap(periodic_noise(256, 64, 1.2, seed), Y * 0.25, X * 3.0)
    seam = np.abs(np.abs(s) - inner_w * 0.62) < 0.45
    if variant == 1:
        wood = look((132, 100, 66))
        gun_c = look((44, 104, 136))
    else:
        wood = look((104, 80, 56))
        gun_c = look((70, 54, 40))
    walb = wood * (0.86 + 0.28 * grain[..., None]) * np.where(seam, 0.7, 1.0)[..., None]
    inside = inside_hull & (np.abs(s) < inner_w)
    cv.field(z_in.astype(np.float32), walb, gloss=0.12, mat=WOOD, mask=inside)
    # nẹp be (mép trên hai bên)
    gm = inside_hull & (np.abs(s) >= inner_w - 0.2)
    gq = (np.abs(s) - (hw - gw / 2)) / (gw / 2)
    z_g = sheer + 1.2 * np.sqrt(np.clip(1 - gq * gq, 0, 1))
    cv.field(z_g.astype(np.float32), gun_c * (0.9 + 0.2 * grain[..., None]), gloss=0.3, mat=WOOD, mask=gm)
    # sạp mũi và lái
    for sign in (-1, 1):
        dm = inside_hull & (t * sign > 0.8)
        cv.field((sheer + 0.6).astype(np.float32), wood * 1.08 * (0.9 + 0.2 * grain[..., None]), gloss=0.15, mat=WOOD, mask=dm)
    # sườn ngang + ván ngồi
    def hw_at(tt):
        return Wh * max(0.0, 1 - abs(tt) ** 2.4) ** 0.75
    for k in range(-6, 7):
        tt = k / 7.5
        y = c + tt * L / 2
        w = hw_at(tt) - gw
        if w < 3:
            continue
        zz = 7.0 * tt * tt - 1.5 - D * (1 - abs(tt) ** 3) + 1.4
        cv.strip((c - w, y, zz + 2), (c + w, y, zz + 2), 0.9, 0.9, wood * 0.82, round_=0.8, mat=WOOD)
    for tt in ((-0.45, 0.1, 0.55) if variant == 1 else (-0.4, 0.3)):
        y = c + tt * L / 2
        w = hw_at(tt) - 0.5
        cv.strip((c - w, y, 7 * tt * tt - 0.5), (c + w, y, 7 * tt * tt - 0.5), 4.2, 4.2, wood * 1.15, round_=0.12,
                 gloss=0.15, mat=WOOD)
    zb = -1.5 - D
    if variant == 1:
        # người chèo ở lái: thân áo, hai tay cầm chèo, nón lá
        py = c + 0.68 * L / 2
        cv.dome(c, py, 10.5, 7.5, zb + 10, 22, look((82, 92, 120)), mat=CLOTH)
        for sx in (-1, 1):
            cv.strip((c + sx * 8, py - 2, zb + 28), (c + sx * 5 + 6, py - 16, zb + 26), 2.3, 2.0, look((176, 124, 88)),
                     round_=0.8, mat=CLOTH)
        oar(cv, (c + 4, py - 34, zb + 40), (c + 46, py + 38, zb + 2), 36, 9, look((150, 118, 80)))
        conical_hat(cv, c, py - 1, zb + 48, 13.5)
        # chậu bông vạn thọ + giỏ bưởi giữa xuồng
        for (ox, oy) in ((-9, -0.05), (9, -0.08), (-9, 0.28), (9, 0.3), (0, -0.28)):
            px, pyy = c + ox, c + oy * L / 2
            cv.dome(px, pyy, 7.5, 7.5, zb + 2, 5, look((150, 72, 44)), gloss=0.3, mat=CLOTH)     # chậu sành
            for _ in range(16):
                fx, fy = px + rng.normal(0, 3.2), pyy + rng.normal(0, 3.2)
                fc = look((236, 160, 30)) if rng.random() < 0.7 else look((244, 196, 44))
                cv.dome(fx, fy, 2.4, 2.4, zb + 10 + rng.uniform(0, 3), 1.6, fc * rng.uniform(0.85, 1.1),
                        trans=0.3, mat=FOLIAGE)
            for _ in range(6):
                a = rng.uniform(0, math.tau)
                cv.strip((px, pyy, zb + 9), (px + math.cos(a) * 8, pyy + math.sin(a) * 8, zb + 6), 1.2, 0.0,
                         look((70, 110, 52)), prof='leaf', fold=0.3, mat=FOLIAGE)
        gx, gy = c, c - 0.62 * L / 2
        cv.dome(gx, gy, 11, 11, zb + 1, 6, look((150, 120, 76)), mat=WOOD)     # giỏ tre
        for _ in range(7):
            a, d = rng.uniform(0, math.tau), rng.uniform(0, 6)
            cv.dome(gx + math.cos(a) * d, gy + math.sin(a) * d, 4.2, 4.2, zb + 8 + rng.uniform(0, 3), 3.6,
                    look((168, 176, 70)) * rng.uniform(0.9, 1.1), gloss=0.3, mat=FOLIAGE)
    else:
        # nước đọng đáy xuồng + mái chèo + cuộn dây ở mũi
        pud = inside & (side > 0.98) & (np.abs(t) < 0.55)
        pn = periodic_noise(S * 3, S * 3, 12, seed)
        pud &= pn > 0.45
        cv.field(np.full(pud.shape, zb + 0.4, np.float32), np.broadcast_to(look((72, 66, 48)), pud.shape + (3,)),
                 gloss=0.9, mat=WOOD, mask=pud)
        oar(cv, (c - 6, c + 0.62 * L / 2, zb + 4), (c + 3, c - 0.2 * L / 2, zb + 2), 34, 9, look((140, 108, 72)))
        cx2, cy2 = c, c - 0.86 * L / 2
        for k in range(40):
            tt = k / 40 * math.tau * 2.8
            rr2 = 2 + k * 0.14
            cv.dome(cx2 + math.cos(tt) * rr2, cy2 + 4 + math.sin(tt) * rr2, 1.3, 1.3, 2.0 + 7.0 * 0.86 ** 2, 1.0,
                    look((180, 160, 110)), mat=CLOTH)
    add_detail(cv, 0.7, 0.08, 0.3, seed=seed + 3, mats=(WOOD,))
    rgb, a = cv.render(shadow_len=60, pen=0.06, ao_rad=8, ao_amt=0.6, wrap_light=0.15, sun_dir_mix=0.9,
                       spec_pow=40, sky_spec=0.2, shadow_floor=0.25)
    return to_image(rgb, a)


def boats_sampan():
    save_png(sampan(81, 1), 'img_boat_sampan_1')
    save_png(sampan(82, 2), 'img_boat_sampan_2')


# =================================================================== Đá
def boulder(cv, rng, cx, cy, rx, ry, hgt, cols, ang=0.0, seed=0, moss=0.2):
    """Tảng đá: vòm méo bị các mặt phẳng nghiêng cắt vát (cạnh sắc, mặt
    phẳng), nhám li ti, vân nứt, địa y loang, rêu ở chỗ khuất."""
    X, Y = cv.grid()
    ca, sa = math.cos(ang), math.sin(ang)
    dx, dy = X - cx, Y - cy
    u = (dx * ca + dy * sa) / rx
    v = (-dx * sa + dy * ca) / ry
    th = np.arctan2(v, u)
    wob = 1 + sum(rng.uniform(0.03, 0.09) / k ** 0.5 * np.sin(k * th + rng.uniform(0, 6.3)) for k in range(2, 7))
    q = np.hypot(u, v) / wob
    m = q < 1
    z = hgt * np.sqrt(np.clip(1 - q ** 2.6, 0, 1))
    # mặt vát: cắt bởi các mặt phẳng
    for _ in range(int(rng.integers(5, 9))):
        a = rng.uniform(0, math.tau)
        nx, ny = math.cos(a), math.sin(a)
        d0 = rng.uniform(0.25, 0.7) * max(rx, ry)
        slope = rng.uniform(0.6, 1.4) * hgt / max(rx, ry)
        plane = hgt * rng.uniform(0.75, 1.0) - slope * ((dx * nx + dy * ny) - d0 * 0) - slope * 0
        plane = hgt * rng.uniform(0.8, 1.05) - slope * (dx * nx + dy * ny - d0)
        z = np.minimum(z, np.maximum(plane, 0))
    z = blur(z, 1.2, wrap=False)
    H = z.shape[0]
    rough = fbm_noise(H, H, [1.0, 3.0, 8.0], seed=seed)
    z = z + rough * hgt * 0.06
    cr_f1, cr_f2 = worley(H, H, 48, seed=seed + 1)
    crack = (1 - smoothstep(0, 1.6, cr_f2 - cr_f1)) * smoothstep(0.5, 0.7, fbm_noise(H, H, [20], seed=seed + 2))
    z = z - crack * 1.5
    t1 = fbm_noise(H, H, [16, 5], seed=seed + 3)
    alb = mix(cols[0], cols[1], t1[..., None])
    alb *= (0.85 + 0.3 * fbm_noise(H, H, [0.6, 1.5], seed=seed + 4))[..., None]
    speck = rng.random((H, H))
    alb[speck < 0.02] *= 0.6
    alb[speck > 0.985] *= 1.25
    lichen = smoothstep(0.72, 0.8, fbm_noise(H, H, [2.0, 5], seed=seed + 5))
    alb = mix(alb, look((190, 188, 170)), (lichen * 0.6)[..., None])
    gy, gx = np.gradient(z)
    up = smoothstep(0.4, 0.0, np.hypot(gx, gy) * cv.ss / max(hgt / max(rx, ry), 0.2))
    mz = smoothstep(0.55, 0.75, fbm_noise(H, H, [6, 2], seed=seed + 6)) * moss * 2
    mzz = np.clip(mz * (0.4 + 0.6 * up), 0, 1)
    alb = mix(alb, look((86, 100, 52)), mzz[..., None])
    alb = alb * (1 - 0.35 * crack[..., None])
    cv.field(z.astype(np.float32), alb, gloss=0.08, mat=ROCK, mask=m)


def rocks():
    specs = [
        # đá granite xám hồng (đèo Hải Vân)
        dict(parts=[(80, 80, 62, 50, 46, 0.3)], cols=((150, 140, 134), (128, 122, 118)), moss=0.15),
        # đá vôi xám (Tây Bắc), rêu nhiều
        dict(parts=[(80, 82, 66, 46, 40, 1.2)], cols=((140, 140, 134), (104, 104, 100)), moss=0.45),
        # cụm 3 tảng nâu xám
        dict(parts=[(68, 72, 42, 34, 34, 0.5), (110, 98, 30, 24, 24, 2.0), (92, 124, 22, 17, 16, 0.9)],
             cols=((142, 128, 110), (118, 108, 96)), moss=0.2),
    ]
    for k, sp in enumerate(specs):
        cv = Canvas(160, 160, ss=3)
        rng = np.random.default_rng(90 + k)
        cols = [look(c) for c in sp['cols']]
        for j, (x, y, rx, ry, h, a) in enumerate(sp['parts']):
            boulder(cv, rng, x, y, rx, ry, h, cols, ang=a, seed=900 + 10 * k + j, moss=sp['moss'])
        rgb, al = cv.render(shadow_len=50, pen=0.05, ao_rad=10, ao_amt=0.9, wrap_light=0.1, sun_dir_mix=0.85)
        save_png(to_image(rgb, al), f'img_rock_{k + 1}')


# ============================================================ Xương rồng
def cactus():
    """Bụi xương rồng bà (vợt) trên cát ven biển: các bẹ dẹt hình bầu dục
    mọc chồng lên nhau nghiêng đủ hướng, xanh lơ có phấn, chấm gai trắng xếp
    đều, vài trái đỏ tía ở mép bẹ, bẹ già dưới gốc ngả nâu xám."""
    S = 160
    cv = Canvas(S, S, ss=3)
    rng = np.random.default_rng(95)
    c = S / 2
    pads = []
    # bẹ gốc toả ra, bẹ trên mọc từ mép bẹ dưới
    for i in range(7):
        a = i / 7 * math.tau + rng.uniform(-0.3, 0.3)
        pads.append((c + math.cos(a) * 18, c + math.sin(a) * 18, a, 0, 6.0))
    k = 0
    while k < len(pads) and len(pads) < 34:
        x, y, a, lvl, z = pads[k]
        k += 1
        if lvl >= 3:
            continue
        for _ in range(int(rng.integers(1, 3))):
            a2 = a + rng.normal(0, 0.7)
            d = rng.uniform(14, 20)
            nx, ny = x + math.cos(a2) * d, y + math.sin(a2) * d
            if math.hypot(nx - c, ny - c) > 62:
                continue
            pads.append((nx, ny, a2, lvl + 1, z + rng.uniform(8, 16)))
    for (x, y, a, lvl, z) in sorted(pads, key=lambda p: p[4]):
        L, W = rng.uniform(13, 17), rng.uniform(9, 12)
        # bẹ dựng nghiêng: nhìn từ trên thấy hẹp lại theo cos(góc dựng)
        phi = rng.uniform(0.2, 1.25)
        side = rng.choice([-1, 1])
        wv = W * math.cos(phi)
        sl = math.tan(phi) * 0.8 * side
        nx, ny = -math.sin(a), math.cos(a)            # trục ngắn của bẹ
        tx, ty = nx * sl, ny * sl
        old = lvl == 0 and rng.random() < 0.6
        col = look((112, 110, 84)) if old else look((76, 106, 62)) * rng.uniform(0.88, 1.12)

        def pad_fn(qq, XX, YY, col=col, x=x, y=y):
            # chấm gai: lưới chéo đều trên bẹ
            g = (np.sin((XX - x) * 1.7 + (YY - y) * 0.9) * np.sin((XX - x) * -0.9 + (YY - y) * 1.7)) > 0.9
            rim = smoothstep(0.75, 1.0, qq)[..., None]
            base = col * (1.0 - 0.25 * rim)
            return np.where(g[..., None], look((206, 200, 172)), base)
        cv.dome(x, y, L, max(wv, 2.2), z, 3.2, col, ang=a, gloss=0.3, mat=FOLIAGE, tilt=(tx, ty), alb_fn=pad_fn, flat=0.8)
        if not old and rng.random() < 0.45:
            for _ in range(int(rng.integers(1, 4))):
                fa = a + rng.uniform(-0.5, 0.5)
                fx, fy = x + math.cos(fa) * L * 0.95, y + math.sin(fa) * L * 0.95
                cv.dome(fx, fy, 3.0, 2.3, z + tx * (fx - x) + ty * (fy - y) + 1, 2.4, look((150, 40, 70)),
                        ang=fa, gloss=0.35, mat=FOLIAGE)
    rgb, al = cv.render(shadow_len=60, pen=0.04, ao_rad=8, ao_amt=0.9, wrap_light=0.15, sun_dir_mix=0.8,
                        shadow_floor=0.1)
    save_png(to_image(rgb, al), 'img_cactus_1')


# ======================================================= Vân: cát, biển
def desat(rgb, k):
    """Giảm độ rực màu (k < 1) quanh độ sáng."""
    g = (rgb * np.array([0.3, 0.59, 0.11])).sum(-1, keepdims=True)
    return g + (rgb - g) * k


def grass_tuft(cv, rng, x, y, z0, r, cols, n=None, w=0.55, rise=0.6, trans=0.5, mat=FOLIAGE):
    """Búi cỏ: lá mảnh mọc toả từ gốc, vươn lên rồi gục ra ngoài."""
    n = n or int(8 + r * 1.6)
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        L = r * rng.uniform(0.45, 1.0)
        up = L * rise * rng.uniform(0.5, 1.0)
        p0 = (x + math.cos(a) * r * 0.08, y + math.sin(a) * r * 0.08, z0)
        p1 = (x + math.cos(a) * L * 0.5, y + math.sin(a) * L * 0.5, z0 + up)
        a2 = a + rng.uniform(-0.35, 0.35)
        p2 = (p1[0] + math.cos(a2) * L * 0.5, p1[1] + math.sin(a2) * L * 0.5, z0 + up * rng.uniform(0.2, 0.7))
        col = cols[rng.integers(len(cols))] * rng.uniform(0.8, 1.2)
        ww = w * rng.uniform(0.8, 1.2)
        cv.strip(p0, p1, ww, ww * 0.85, col, prof='taper', fold=0.4, trans=trans, mat=mat, cap=False)
        cv.strip(p1, p2, ww * 0.85, 0.05, col, prof='taper', fold=0.4, trans=trans, mat=mat, cap=False)


def ripple_field(h, w, cycles, seed, warp=2.5, ang_noise=0.6):
    """Gợn cát do gió: sóng lệch (sườn đón gió thoải, sườn khuất dốc), uốn
    lượn và đứt đoạn, lặp liền mạch (số gợn trên một ô là số nguyên)."""
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32)
    wx = (fbm_noise(h, w, [w / 10, w / 30], seed) - 0.5) * warp
    wy = (fbm_noise(h, w, [w / 8, w / 24], seed + 1) - 0.5) * ang_noise
    ph = (Y / h) * cycles + wx + wy * (X / w - 0.5) * 0  # dịch pha theo nhiễu
    ph = ph + (fbm_noise(h, w, [w / 6], seed + 2) - 0.5) * 3.0
    u = ph - np.floor(ph)
    prof = np.where(u < 0.72, u / 0.72, (1 - u) / 0.28)  # răng cưa lệch
    prof = prof * prof * (3 - 2 * prof)
    return prof


def tex_sand():
    """Cát trắng ven biển miền Trung: gợn gió uốn lượn, chỗ phẳng chỗ gợn,
    hạt khoáng sẫm li ti, vụn vỏ sò trắng, vài búi cỏ khô lưa thưa."""
    S, ss = 512, 2
    cv = Canvas(S, S, ss=ss, wrap=True)
    H = S * ss
    rng = np.random.default_rng(201)
    rip = ripple_field(H, H, 34, seed=21, warp=3.0)
    rip2 = ripple_field(H, H, 52, seed=29, warp=4.0)
    amp = smoothstep(0.3, 0.75, fbm_noise(H, H, [90, 30], seed=22))
    amp2 = smoothstep(0.45, 0.8, fbm_noise(H, H, [70, 25], seed=26))
    dune = fbm_noise(H, H, [160, 60], seed=23)
    z = dune * 6.0 + rip * 2.0 * (0.12 + 0.88 * amp) + rip2 * 0.8 * amp2 * (1 - amp)
    grain = fbm_noise(H, H, [0.7, 2.0], seed=24)
    tone = fbm_noise(H, H, [60, 20], seed=25)
    base = mix(look((200, 184, 150)), look((214, 200, 168)), tone[..., None])
    alb = base * (0.86 + 0.28 * grain[..., None])
    # hạt khoáng sẫm và vụn vỏ trắng
    speck = rng.random((H, H))
    alb[speck < 0.010] *= 0.62
    alb[(speck > 0.996)] = lin((240, 236, 226))
    # cát hơi sẫm ở rãnh gợn (hạt nặng đọng lại)
    alb *= (0.9 + 0.1 * rip)[..., None]
    cv.field(z, alb, mat=GROUND)
    cols = [look(c) for c in ((214, 194, 140), (196, 178, 126), (172, 166, 112), (222, 206, 156), (150, 152, 96))]
    for (x, y) in poisson_disk(S, S, 170, rng)[:4]:
        zz = 6.0 * float(sample_wrap(dune, np.array([x * ss]), np.array([y * ss]))[0])
        grass_tuft(cv, rng, x, y, zz, rng.uniform(20, 30), cols, n=32, w=0.5, rise=0.25, trans=0.4)
    rgb, _ = cv.render(shadow_len=20, pen=0.05, ao_rad=6, ao_amt=0.4, wrap_light=0.0, shadow_floor=0.3)
    save_jpg(to_image(desat(rgb, 0.9)), 'tex_sand')


def tex_sand_wet():
    """Cát ướt sát mép nước: phẳng, sẫm, hơi bóng ánh trời; vệt sóng rút
    (đường cát mịn sáng hơn chạy song song bờ — trục x), rãnh nước rút nhỏ,
    lỗ bọt khí, vụn vỏ sò, gợn rất mờ."""
    S, ss = 512, 2
    cv = Canvas(S, S, ss=ss, wrap=True)
    H = S * ss
    rng = np.random.default_rng(301)
    Y = np.mgrid[0:H, 0:H][0].astype(np.float32)
    rip = ripple_field(H, H, 22, seed=31, warp=2.0)
    dune = fbm_noise(H, H, [50, 18], seed=33)
    # rãnh nước rút: rãnh mảnh uốn lượn chạy dọc trục y (xuôi dốc ra biển)
    rill_ph = fbm_noise(H, H, [6, 20], seed=34) * 9 + np.mgrid[0:H, 0:H][1] / H * 40
    rill = np.exp(-((rill_ph - np.round(rill_ph)) / 0.07) ** 2) * smoothstep(0.55, 0.8, fbm_noise(H, H, [60], seed=35))
    z = dune * 1.2 + rip * 0.3 * smoothstep(0.4, 0.8, fbm_noise(H, H, [80], seed=36)) - rill * 0.12
    grain = fbm_noise(H, H, [0.7, 2.0], seed=37)
    tone = fbm_noise(H, H, [40, 14], seed=38)
    alb = mix(look((134, 120, 96)), look((150, 136, 108)), tone[..., None]) * (0.9 + 0.2 * grain[..., None])
    # vệt sóng rút: đường cong song song bờ, cát mịn sáng + bọt khô
    wob = (fbm_noise(H, H, [H / 8, H / 30], seed=39) - 0.5) * 60
    for k, (yy, amt) in enumerate(((0.18, 0.12), (0.47, 0.16), (0.78, 0.10))):
        d = ((Y + wob * (1 + k * 0.3)) / H - yy) * H / ss
        d = d - np.round(d / S) * S
        line = np.exp(-(d / 1.2) ** 2) * (0.5 + 0.5 * smoothstep(0.3, 0.7, fbm_noise(H, H, [10], seed=40 + k)))
        band = smoothstep(-14, 0, d) * smoothstep(1, 0, d)
        alb *= (1 + amt * line - 0.05 * band)[..., None]
    puddle = smoothstep(0.3, 0.12, dune)
    alb *= (1 - 0.1 * puddle)[..., None]
    speck = rng.random((H, H))
    alb[speck < 0.006] *= 0.6
    alb[speck > 0.9975] = look((214, 208, 194))
    gloss = 0.15 + 0.1 * puddle
    cv.field(z, alb, gloss=gloss, mat=GROUND)
    # lỗ bọt khí: chấm tối nhỏ
    for (x, y) in poisson_disk(S, S, 9, rng)[:500]:
        if rng.random() < 0.5:
            cv.dome(x, y, 0.55, 0.55, float(sample_wrap(dune, np.array([x * ss]), np.array([y * ss]))[0]) * 1.5 - 0.6,
                    0.3, look((80, 72, 60)), mat=GROUND)
    rgb, _ = cv.render(shadow_len=8, pen=0.05, ao_rad=4, ao_amt=0.5, wrap_light=0.0, spec_pow=60,
                       sky_spec=0.15)
    save_jpg(to_image(desat(rgb, 0.92)), 'tex_sand_wet')


def wave_height(X, Y, period, comps, seed):
    """Mặt sóng = tổng các sóng sin có véc-tơ sóng nguyên trên ô (lặp liền
    mạch). comps = [(số sóng, bước sóng min, max, hướng tb, độ lệch hướng,
    biên độ/bước sóng)]. Trả về (h, dh/dx, dh/dy)."""
    rng = np.random.default_rng(seed)
    h = np.zeros_like(X)
    hx = np.zeros_like(X)
    hy = np.zeros_like(X)
    for n, lmin, lmax, d0, dspread, steep in comps:
        for _ in range(n):
            lam = math.exp(rng.uniform(math.log(lmin), math.log(lmax)))
            th = d0 + rng.normal(0, dspread)
            m = round(period / lam * math.cos(th))
            k = round(period / lam * math.sin(th))
            if m == 0 and k == 0:
                continue
            lam2 = period / math.hypot(m, k)
            amp = steep * lam2 / math.tau * rng.uniform(0.5, 1.0)
            ph = rng.uniform(0, math.tau)
            arg = math.tau * (m * X + k * Y) / period + ph
            h += amp * np.sin(arg)
            c = amp * np.cos(arg) * math.tau / period
            hx += c * m
            hy += c * k
    return h, hx, hy


def water_shade(hx, hy, body, sky_top=(0.30, 0.46, 0.78), sky_hor=(0.80, 0.86, 0.94), glint=1.0,
                glint_pow=900, irr=None, vis=None):
    """Màu mặt nước tuyến tính: thân nước (tán xạ dưới mặt) + phản chiếu trời
    theo Fresnel + vệt nắng lấp lánh."""
    n = np.stack([-hx, -hy, np.ones_like(hx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    nz = n[..., 2]
    rz = 2 * nz * nz - 1
    F = 0.02 + 0.98 * (1 - nz) ** 5
    t = smoothstep(0.0, 1.0, np.clip(rz, 0, 1)) ** 0.6
    sky = np.array(sky_hor) * (1 - t[..., None]) + np.array(sky_top) * t[..., None]
    E = SUN_COL * SUN[2] + SKY_IRR if irr is None else irr
    v = 1.0 if vis is None else vis[..., None]
    col = body * E * (0.35 + 0.65 * v) * (1 - F[..., None]) + sky * F[..., None] * 1.6
    nh = np.clip((n * HALF).sum(-1), 0, 1)
    col += SUN_COL * (glint * nh ** glint_pow * (glint_pow / 40))[..., None] * v
    return col


def tex_sea():
    """Mặt biển xanh lam ngọc: sóng lừng dài chạy vào bờ (trục +y của ảnh)
    chồng sóng gió ngắn lệch hướng và gợn lăn tăn. Sườn sóng quay về phía
    nắng / chân trời sáng hơn, đỉnh sóng sáng + ngả xanh ngọc (nắng xuyên qua
    nước), vài vệt nắng lấp lánh. Lặp liền mạch nên game có thể cho trôi."""
    S, ss = 512, 2
    H = S * ss
    Y, X = np.mgrid[0:H, 0:H].astype(np.float32)
    X, Y = (X + 0.5) / ss, (Y + 0.5) / ss
    h, hx, hy = wave_height(X, Y, S, [(12, 70, 170, math.pi / 2, 0.15, 0.08),
                                      (28, 20, 60, math.pi / 2 + 0.25, 0.45, 0.06),
                                      (40, 5, 14, 0.0, 1.8, 0.018)], seed=401)
    tone = fbm_noise(H, H, [60, 20], seed=402)
    body = mix(look((26, 84, 104)), look((34, 100, 112)), tone[..., None])
    n = np.stack([-hx, -hy, np.ones_like(hx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    slope = (n * SUN).sum(-1) - SUN[2]
    crest = np.clip(h / (np.abs(h).max() * 0.55), -1, 1)
    E = SUN_COL * SUN[2] + SKY_IRR
    col = body * E * (1 + 1.1 * slope + 0.16 * crest)[..., None]
    col += look((40, 150, 140)) * E * 0.10 * np.clip(crest, 0, 1)[..., None]
    # phản chiếu trời (Fresnel) + lấp lánh thưa
    nz = n[..., 2]
    F = 0.02 + 0.98 * (1 - nz) ** 5
    col += np.array([0.5, 0.62, 0.85]) * F[..., None] * 1.4
    nh = np.clip((n * HALF).sum(-1), 0, 1)
    col += SUN_COL * (nh ** 3000 * 30)[..., None]
    rgb = tonemap(col).reshape(S, ss, S, ss, 3).mean((1, 3))
    save_jpg(to_image(desat(rgb, 0.95)), 'tex_sea')


def worley(w, h, cell, seed):
    """Nhiễu tế bào (Worley) lặp liền mạch hai chiều, mỗi ô lưới [cell] điểm
    ảnh một hạt ngẫu nhiên. Trả về (F1, F2) = khoảng cách tới hạt gần nhất,
    gần nhì (điểm ảnh)."""
    rng = np.random.default_rng(seed)
    gw, gh = w // cell, h // cell
    jx = rng.uniform(0, 1, (gh, gw))
    jy = rng.uniform(0, 1, (gh, gw))
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (X // cell).astype(int), (Y // cell).astype(int)
    f1 = np.full((h, w), 1e9, np.float32)
    f2 = np.full((h, w), 1e9, np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = cx + ox, cy + oy
            px = (nx + jx[ny % gh, nx % gw]) * cell
            py = (ny + jy[ny % gh, nx % gw]) * cell
            d = np.hypot(X - px, Y - py)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            f1 = np.where(closer, d, f1)
    return f1, f2


def tex_foam():
    """Dải bọt sóng ven bờ (RGBA 512×128, lặp theo chiều ngang). Mép DƯỚI
    ảnh là phía bờ cát: viền bọt trắng dày của lớp nước đánh lên bờ (lượn
    sóng), sau đó là màng bọt ren lỗ chỗ, kéo thành vệt song song bờ, mỏng
    dần ra phía biển (mép TRÊN); thêm một dải bọt của con sóng vỡ phía ngoài.
    Sát mép dưới là màng nước mỏng gần như trong suốt."""
    W, Hh = 512, 128
    ss = 2
    w, h = W * ss, Hh * ss
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32)
    Xu, Yu = X / ss, Y / ss

    def aniso(sigma, seed, k=4):
        """Nhiễu kéo dài k lần theo trục x (vẫn lặp liền mạch theo x)."""
        n = periodic_noise(h, w // k, sigma, seed)
        return sample_wrap(n, X / k, Y)

    # đường mép nước lượn theo x
    edge = 100 + (fbm_noise(64, w, [w / 14, w / 40], seed=501)[0] - 0.5) * 22
    d = Yu - edge[None, :]                               # >0: phía bờ
    # ren bọt: Worley bị bóp méo, hai cỡ, độ dày gân thay đổi theo nhiễu
    wx = (aniso(10, 510) - 0.5) * 18
    wy = (aniso(10, 511) - 0.5) * 10
    f1, f2 = worley(w, h, 16, seed=502)
    e1 = sample_wrap(f2 - f1, X + wx, Y + wy)
    f1b, f2b = worley(w, h, 8, seed=503)
    e2 = sample_wrap(f2b - f1b, X - wx * 0.6, Y + wy * 0.6)
    dens = aniso(14, 512)
    thr1 = (1.0 + 5.0 * dens) * ss
    lace = 1 - smoothstep(thr1 * 0.4, thr1, e1)
    lace2 = 1 - smoothstep(0.6 * ss, 1.8 * ss, e2)
    patch = smoothstep(0.55, 0.85, aniso(6, 513))      # mảng bọt dày
    fine = fbm_noise(h, w, [1.0, 3.0], seed=504)
    # viền bọt chính ngay sau mép nước
    rim = np.exp(-((d + 4) / 4.5) ** 2) + 0.55 * np.exp(-((d + 11) / 5) ** 2) * (0.4 + 0.6 * lace)
    rim *= 0.7 + 0.5 * smoothstep(0.3, 0.7, aniso(4, 505, k=2))
    # màng bọt ren phía biển, thưa dần + đứt thành vệt
    prof = smoothstep(-90, -12, d) * smoothstep(2, -6, d)
    streak = smoothstep(0.3, 0.65, aniso(8, 514, k=6))
    sheet_a = prof * (0.25 + 0.75 * streak) * np.maximum(lace * 0.9, np.maximum(lace2 * 0.45, patch * 0.8))
    # dải sóng vỡ phía ngoài
    brk = 26 + (fbm_noise(64, w, [w / 10], seed=506)[0] - 0.5) * 18
    db = Yu - brk[None, :]
    breaker = np.exp(-(db / 6) ** 2) * smoothstep(0.35, 0.7, aniso(12, 507, k=3))
    breaker_a = breaker * (0.4 + 0.6 * np.maximum(lace, lace2))
    # màng nước mỏng tràn lên cát (phía bờ), gần như trong suốt
    film = smoothstep(16, 0, d) * smoothstep(-2, 2, d) * 0.16
    alpha = np.clip(np.maximum.reduce([rim * (0.7 + 0.3 * fine), sheet_a, breaker_a]), 0, 1)
    alpha = np.maximum(alpha, film)
    alpha *= smoothstep(0, 10, Yu) * smoothstep(Hh, Hh - 4, Yu)
    # màu: trắng, chỗ bọt mỏng hơi xanh nhạt; mép dưới bọt dày hơi xám (bóng)
    thick = np.clip(alpha, 0, 1)
    col = mix(np.array([0.78, 0.88, 0.90]), np.array([0.97, 0.98, 0.98]), thick[..., None] ** 0.7)
    col = col * (0.92 + 0.08 * fine[..., None])
    a = alpha.reshape(Hh, ss, W, ss).mean((1, 3))
    c = (col * alpha[..., None]).reshape(Hh, ss, W, ss, 3).mean((1, 3)) / np.maximum(a[..., None], 1e-4)
    save_png(to_image(c, a), 'tex_foam')


def worley_full(w, h, cell, seed):
    """Như worley() nhưng trả thêm chỉ số + toạ độ hạt gần nhất (để mỗi tế
    bào một mặt phẳng / màu riêng)."""
    rng = np.random.default_rng(seed)
    gw, gh = w // cell, h // cell
    jx = rng.uniform(0.1, 0.9, (gh, gw))
    jy = rng.uniform(0.1, 0.9, (gh, gw))
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (X // cell).astype(int), (Y // cell).astype(int)
    f1 = np.full((h, w), 1e9, np.float32)
    f2 = np.full((h, w), 1e9, np.float32)
    nid = np.zeros((h, w), int)
    npx = np.zeros((h, w), np.float32)
    npy = np.zeros((h, w), np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = cx + ox, cy + oy
            gx, gy = nx % gw, ny % gh
            px = (nx + jx[gy, gx]) * cell
            py = (ny + jy[gy, gx]) * cell
            d = np.hypot(X - px, Y - py)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            f1 = np.where(closer, d, f1)
            nid = np.where(closer, gy * gw + gx, nid)
            npx = np.where(closer, px, npx)
            npy = np.where(closer, py, npy)
    return f1, f2, nid, npx, npy


# ============================================================ Vân: kênh
def hyacinth(cv, rng, x, y, z0=0.0, r=7.0, flower=False):
    """Một cụm lục bình: lá tròn bóng xếp hoa thị, cuống phồng, đôi khi có
    chùm hoa tím nhạt ở giữa."""
    n = int(rng.integers(6, 10))
    a0 = rng.uniform(0, math.tau)
    for i in range(n):
        a = a0 + i / n * math.tau + rng.uniform(-0.3, 0.3)
        d = r * rng.uniform(0.35, 0.6)
        lx, ly = x + math.cos(a) * d, y + math.sin(a) * d
        lr = r * rng.uniform(0.38, 0.5)
        c = look((72, 106, 40)) * rng.uniform(0.8, 1.2) * (1 + rng.uniform(-0.06, 0.06, 3))
        # cuống phồng nối vào giữa
        cv.strip((x, y, z0 + r * 0.25), (lx, ly, z0 + r * 0.35), r * 0.12, r * 0.14, look((92, 120, 60)),
                 round_=0.8, gloss=0.3, mat=FOLIAGE)
        cv.dome(lx, ly, lr, lr * 0.85, z0 + r * 0.3 + rng.uniform(0, r * 0.1), r * 0.22, c, ang=a, gloss=0.6,
                trans=0.5, mat=FOLIAGE, flat=0.7)
    if flower:
        for _ in range(int(rng.integers(6, 12))):
            fx, fy = x + rng.normal(0, r * 0.12), y + rng.normal(0, r * 0.12)
            cv.dome(fx, fy, r * 0.11, r * 0.11, z0 + r * 0.55, r * 0.08, look((178, 156, 206)) * rng.uniform(0.9, 1.1),
                    gloss=0.1, trans=0.3, mat=FOLIAGE)


def tex_canal():
    """Nước kênh rạch miền Tây: nước phù sa đục nâu - xanh rêu, gợn lăn tăn
    và vệt dòng chảy dọc kênh (trục x), ánh trời mờ; vài đám lục bình trôi (có
    bóng đổ xuống nước), lá khô, bọt li ti."""
    S, ss = 512, 2
    H = S * ss
    cv = Canvas(S, S, ss=ss, wrap=True)
    rng = np.random.default_rng(601)
    X, Y = cv.grid()
    tone = fbm_noise(H, H, [50, 16], seed=602)
    silt = fbm_noise(H, H, [12, 4], seed=603)
    body = mix(look((80, 80, 54)), look((98, 88, 58)), tone[..., None])
    body = body * (0.95 + 0.1 * silt[..., None])
    cv.field(np.zeros((H, H), np.float32), body, mat=WATER)
    # lá khô / cành nhỏ trôi
    for _ in range(16):
        x, y = rng.uniform(0, S, 2)
        a = rng.uniform(0, math.tau)
        L = rng.uniform(4, 9)
        cv.strip((x, y, 0.15), (x + math.cos(a) * L, y + math.sin(a) * L, 0.15), L * 0.2, 0,
                 look((116, 92, 56)) * rng.uniform(0.8, 1.2), prof='leaf', fold=0.1, mat=WOOD)
    # đám lục bình (kéo dài theo dòng chảy)
    for (cx, cy) in poisson_disk(S, S, 170, rng)[:4]:
        k = int(rng.integers(4, 18))
        for j in range(k):
            t = rng.normal(0, 1, 2) * np.array([22, 9]) * (k / 10) ** 0.5
            hyacinth(cv, rng, cx + t[0], cy + t[1], 0.0, rng.uniform(9, 13), flower=rng.random() < 0.1)
    add_detail(cv, 0.7, 0.10, 0.6, seed=604)
    _, hx, hy = wave_height(X, Y, S, [(20, 25, 90, 0.0, 0.5, 0.03), (40, 5, 16, 0.0, 2.0, 0.025)], seed=605)
    # vệt dòng chảy: dải mảnh sáng/tối kéo dài theo x
    flow = periodic_noise(H, H // 8, 3, seed=606)
    flow = sample_wrap(flow, (X * ss) / 8, Y * ss)
    E = SUN_COL * SUN[2] + SKY_IRR

    def water(col, vis, ao, wm):
        n = np.stack([-hx, -hy, np.ones_like(hx)], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        slope = (n * SUN).sum(-1) - SUN[2]
        w = cv.alb * E * (0.4 + 0.6 * vis[..., None]) * (1 + 0.9 * slope + 0.08 * (flow - 0.5))[..., None]
        F = 0.02 + 0.98 * (1 - n[..., 2]) ** 5
        w += np.array([0.42, 0.48, 0.56]) * F[..., None] * 1.2 * (0.5 + 0.5 * vis[..., None])
        nh = np.clip((n * HALF).sum(-1), 0, 1)
        w += SUN_COL * (nh ** 3000 * 18 * vis)[..., None]
        col[wm] = w[wm]
        return col
    rgb, _ = cv.render(shadow_len=16, pen=0.05, ao_rad=6, ao_amt=0.7, wrap_light=0.2, water=water)
    save_jpg(to_image(desat(rgb, 0.92)), 'tex_canal')


# ========================================================= Vân: vách đá
def tex_rock():
    """Vách đá xẻ / taluy núi nhìn từ trên: đá khối nứt theo thớ thành các
    mặt phẳng nghiêng lệch nhau (ba cỡ khối chồng lên nhau → gờ, bậc, mặt vát
    sáng tối khác nhau), khe nứt lớn sâu tối chỗ có chỗ liền, đá vụn kẹt
    trong khe, rêu và cỏ mọc trong kẽ, địa y loang trắng, vệt gỉ nâu."""
    S, ss = 512, 2
    H = S * ss
    cv = Canvas(S, S, ss=ss, wrap=True)
    rng = np.random.default_rng(701)
    Y, X = np.mgrid[0:H, 0:H].astype(np.float32)

    def rel(a, b):
        d = a - b
        return d - np.round(d / H) * H

    z = np.zeros((H, H), np.float32)
    edges = []
    for k, (cell, tilt, lift, warp) in enumerate(((128, 0.34, 9.0, 40), (64, 0.22, 1.6, 22), (32, 0.12, 0.4, 10))):
        wx = (fbm_noise(H, H, [cell / 2, cell / 6], seed=730 + k) - 0.5) * warp
        wy = (fbm_noise(H, H, [cell / 2, cell / 6], seed=740 + k) - 0.5) * warp
        f1, f2, nid, px, py = worley_full(H, H, cell, seed=750 + k)
        n = (H // cell) ** 2
        tx = rng.normal(0, tilt, n)
        ty = rng.normal(0, tilt, n)
        hh = rng.uniform(0, lift, n)
        # tra theo toạ độ đã bóp méo (lấy hạt gần nhất của điểm lân cận)
        xi = ((X + wx) % H).astype(int)
        yi = ((Y + wy) % H).astype(int)
        cid = nid[yi, xi]
        cpx, cpy = px[yi, xi], py[yi, xi]
        z += hh[cid] + (tx[cid] * rel(X, cpx) + ty[cid] * rel(Y, cpy)) / ss * (0.5 if k == 0 else 0.4)
        edges.append((f2 - f1)[yi, xi])
    # mép khối bị phong hoá tròn cạnh
    z = blur(z, 3.0).astype(np.float32)
    # khe nứt lớn: chỉ một phần cạnh khối lớn, rộng hẹp thay đổi
    keep = smoothstep(0.45, 0.62, fbm_noise(H, H, [50], seed=760))
    cw = (1.5 + 4.0 * fbm_noise(H, H, [30], seed=761)) * ss
    crack1 = (1 - smoothstep(0, cw, edges[0])) * keep
    crack2 = (1 - smoothstep(0, 0.8 * ss, edges[1])) * smoothstep(0.62, 0.75, fbm_noise(H, H, [24], seed=762))
    z -= crack1 * 8 + crack2 * 1.2
    z += fbm_noise(H, H, [1.0, 3.0, 8.0], seed=763) * 1.6
    # màu
    t1 = fbm_noise(H, H, [50, 14], seed=715)
    t2 = fbm_noise(H, H, [10, 3], seed=716)
    grey, brown, dark = look((134, 130, 122)), look((142, 124, 102)), look((104, 102, 96))
    alb = mix(grey, brown, smoothstep(0.4, 0.75, t1)[..., None] * 0.75)
    alb = mix(alb, dark, smoothstep(0.55, 0.85, t2)[..., None] * 0.5)
    alb *= (0.85 + 0.3 * fbm_noise(H, H, [0.7, 2.0], seed=717))[..., None]
    rust = smoothstep(0.66, 0.86, fbm_noise(H, H, [16, 5], seed=718))
    alb = mix(alb, look((152, 112, 76)), (rust * 0.45)[..., None])
    lichen = smoothstep(0.72, 0.82, fbm_noise(H, H, [2.5, 6], seed=719)) * (1 - crack1)
    alb = mix(alb, look((184, 182, 166)), (lichen * 0.6)[..., None])
    low = smoothstep(3, -3, z - blur(z, 24))       # chỗ lõm, chân bậc
    moss_n = fbm_noise(H, H, [3, 10], seed=720)
    moss = np.clip(crack1 * 1.3 + crack2 * 0.4 + low * 0.8, 0, 1) * smoothstep(0.38, 0.62, moss_n)
    moss = np.maximum(moss, smoothstep(0.74, 0.9, fbm_noise(H, H, [14, 5], seed=721)) * 0.85)
    alb = mix(alb, look((78, 92, 50)) * (0.8 + 0.4 * moss_n[..., None]), moss[..., None])
    cv.field(z.astype(np.float32), alb, mat=ROCK)
    cv.mat[moss > 0.5] = FOLIAGE
    # đá vụn trong khe lớn
    for _ in range(700):
        x, y = rng.uniform(0, S, 2)
        i, j = int(y * ss) % H, int(x * ss) % H
        if crack1[i, j] < 0.3:
            continue
        r = rng.uniform(0.9, 3.2)
        cv.dome(x, y, r, r * rng.uniform(0.6, 1.0), z[i, j] - r * 0.1, r * 0.8,
                mix(grey, brown, rng.uniform(0, 0.6)) * rng.uniform(0.75, 1.15), ang=rng.uniform(0, 3.14),
                wob=(0.7, int(rng.integers(1 << 30))), mat=ROCK, flat=1.4)
    # cỏ mọc trong kẽ
    cols = [look(c) for c in ((96, 116, 58), (122, 130, 70), (140, 128, 84))]
    n = 0
    while n < 40:
        x, y = rng.uniform(0, S, 2)
        i, j = int(y * ss) % H, int(x * ss) % H
        if crack1[i, j] < 0.5 and moss[i, j] < 0.6:
            continue
        grass_tuft(cv, rng, x, y, z[i, j], rng.uniform(5, 11), cols, w=0.45, rise=0.7)
        n += 1
    add_detail(cv, 0.8, 0.12, 0.8, seed=722)
    rgb, _ = cv.render(shadow_len=30, pen=0.06, ao_rad=10, ao_amt=1.0, wrap_light=0.1)
    save_jpg(to_image(desat(rgb, 0.9)), 'tex_rock')


# ====================================================== Vân: bụi ven biển
def shrub(cv, rng, x, y, z0, r, cols, n=None, gloss=0.1, dry=0.0):
    """Bụi cây thấp: chùm vòm nhỏ chen nhau, cao ở giữa, mép lởm chởm."""
    n = n or int(6 + r * r / 4)
    base = cols[rng.integers(len(cols))]
    for _ in range(n):
        rho = r * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        rr = r * rng.uniform(0.22, 0.42) * (1.1 - 0.4 * rho / r)
        zz = z0 + r * 0.55 * math.sqrt(max(0.0, 1 - (rho / r) ** 2))
        c = base * rng.uniform(0.8, 1.2) * (1 + rng.uniform(-0.06, 0.06, 3))
        if rng.random() < dry:
            c = look((132, 112, 80)) * rng.uniform(0.8, 1.1)
        cv.dome(x + math.cos(a) * rho, y + math.sin(a) * rho, rr, rr * rng.uniform(0.75, 1.0), zz - rr * 0.4, rr * 0.7,
                c, ang=rng.uniform(0, 3.14), wob=(0.55, int(rng.integers(1 << 30))), gloss=gloss, trans=0.45)


def creeper(cv, rng, x, y, z0, length, col):
    """Dây rau muống biển bò trên cát: thân mảnh lượn, lá tròn xẻ đôi."""
    a = rng.uniform(0, math.tau)
    px, py = x, y
    for k in range(int(length / 3)):
        a += rng.normal(0, 0.25)
        nx, ny = px + math.cos(a) * 3, py + math.sin(a) * 3
        cv.strip((px, py, z0 + 0.3), (nx, ny, z0 + 0.3), 0.3, 0.3, look((120, 100, 70)), round_=0.6, mat=FOLIAGE)
        if k % 2 == 0:
            side = 1 if k % 4 == 0 else -1
            lx = nx + math.cos(a + side * 1.2) * 2.2
            ly = ny + math.sin(a + side * 1.2) * 2.2
            lr = rng.uniform(1.6, 2.3)
            cv.dome(lx, ly, lr, lr * 0.85, z0 + 0.4, 0.8, col * rng.uniform(0.85, 1.15), ang=a, gloss=0.45, trans=0.4)
        px, py = nx, ny


def tex_scrub():
    """Đất cát khô ven biển miền Trung: cát xám vàng lẫn lá mục, bụi cây thấp
    mọc thành đám to nhỏ không đều (xanh xám, ô liu, vài cành khô nâu), cỏ
    khô lưa thưa, dây rau muống biển bò trên cát."""
    S, ss = 512, 2
    H = S * ss
    cv = Canvas(S, S, ss=ss, wrap=True)
    rng = np.random.default_rng(801)
    rip = ripple_field(H, H, 30, seed=802, warp=3.0)
    dune = fbm_noise(H, H, [100, 40], seed=803)
    z = dune * 5 + rip * 0.6 * smoothstep(0.5, 0.8, fbm_noise(H, H, [60], seed=804))
    tone = fbm_noise(H, H, [40, 12], seed=805)
    litter = smoothstep(0.5, 0.8, fbm_noise(H, H, [2, 8], seed=806))
    alb = mix(look((184, 168, 134)), look((166, 152, 120)), tone[..., None])
    alb = alb * (0.86 + 0.28 * fbm_noise(H, H, [0.7, 2], seed=807))[..., None]
    alb = mix(alb, look((118, 102, 78)), (litter * 0.45)[..., None])
    speck = rng.random((H, H))
    alb[speck < 0.01] *= 0.65
    cv.field(z, alb, mat=GROUND)
    dens = fbm_noise(H, H, [70, 25], seed=809)

    def zat(x, y):
        return 5.0 * float(sample_wrap(dune, np.array([x * ss]), np.array([y * ss]))[0])

    def dat(x, y):
        return float(sample_wrap(dens, np.array([x * ss]), np.array([y * ss]))[0])
    cols = [look(c) for c in ((86, 100, 66), (100, 108, 72), (74, 88, 62), (112, 114, 80), (92, 96, 60))]
    dry_cols = [look(c) for c in ((176, 156, 110), (160, 146, 100), (132, 132, 86))]
    for (x, y) in poisson_disk(S, S, 14, rng):
        d = dat(x, y)
        p = rng.random()
        if p < smoothstep(0.42, 0.7, d) * 0.9:
            # bụi: vài khóm nhỏ chen nhau thành đám méo
            r = rng.uniform(5, 12) * (0.7 + 0.6 * d)
            for _ in range(int(rng.integers(1, 4))):
                ox, oy = rng.normal(0, r * 0.5, 2)
                shrub(cv, rng, x + ox, y + oy, zat(x, y), r * rng.uniform(0.6, 1.0), cols, dry=0.1)
        elif p < 0.35 + 0.3 * d:
            grass_tuft(cv, rng, x, y, zat(x, y), rng.uniform(5, 10), dry_cols, n=14, w=0.4, rise=0.5, trans=0.3)
    for _ in range(6):
        x, y = rng.uniform(0, S, 2)
        creeper(cv, rng, x, y, zat(x, y), rng.uniform(40, 90), look((80, 112, 56)))
    add_detail(cv, 0.8, 0.14, 0.9, seed=808)
    rgb, _ = cv.render(shadow_len=26, pen=0.05, ao_rad=8, ao_amt=0.9, wrap_light=0.2)
    save_jpg(to_image(desat(rgb, 0.9)), 'tex_scrub')


# ===================================================== Vân: ruộng bậc thang
def tex_terrace():
    """Ruộng bậc thang vùng núi mùa Tết: các bậc uốn theo đường đồng mức,
    bờ đất đắp có cỏ ở mép ngoài, vách bậc dốc phủ cỏ; mỗi bậc chia thửa bằng
    bờ ngang, mỗi thửa một kiểu: nước đổ ải loang ánh trời, gốc rạ vàng xám,
    đất cày nâu, mạ xanh non. Đồng mức chạy theo trục x, bậc thấp dần theo
    chiều +y (ô lặp liền mạch: 8 bậc mỗi ô)."""
    S, ss = 512, 2
    H = S * ss
    M = 40  # lề thêm trên/dưới để bóng đổ ở mép ảnh tính đúng, sau đó cắt bỏ
    Hc = S + 2 * M
    cv = Canvas(S, Hc, ss=ss, wrap=True)
    rng = np.random.default_rng(901)
    X, Y = cv.grid()
    K = 8
    step = 7.0
    yy = Y - M
    wv = sample_wrap(fbm_noise(H, H, [H / 5, H / 14], seed=902), X * ss, yy * ss) - 0.5
    wv2 = sample_wrap(fbm_noise(H, H, [H / 3], seed=903), X * ss, yy * ss) - 0.5
    wv3 = sample_wrap(fbm_noise(H, H, [H / 20], seed=909), X * ss, yy * ss) - 0.5
    phi = yy / S * K + wv * 1.0 + wv2 * 0.8 + wv3 * 0.35
    idx = np.floor(phi)
    fr = phi - idx
    gy, gx = np.gradient(phi)
    gmag = np.hypot(gx, gy) * ss + 1e-6          # pha / u
    # Bậc cao dần theo +y: vách bậc quay về phía nắng (lên trên ảnh).
    rw = 8.0 * gmag                              # vách dốc ~8 u
    t_riser = smoothstep(0, rw, fr)              # 0 ở chân vách → 1 ở mặt ruộng
    z = (idx - 1) * step + t_riser * step
    bund = np.exp(-((fr - rw * 1.15) / (1.2 * gmag)) ** 2)   # gờ bờ ở mép ngoài thửa (đỉnh vách)
    z = z + bund * 0.9
    # chia thửa: mỗi bậc n thửa (bờ ngang lệch theo bậc), loại thửa theo bảng
    ik = (idx % K).astype(int)
    nplot = rng.integers(2, 6, K)
    off = rng.uniform(0, 1, K)
    xs = X / S * nplot[ik] + off[ik] + wv * 0.4
    plot = np.floor(xs).astype(int) % nplot[ik]
    xfr = xs - np.floor(xs)
    table = rng.choice(4, (K, 8), p=[0.25, 0.45, 0.2, 0.1])     # 0 nước, 1 rạ, 2 đất cày, 3 mạ
    kind = table[ik, plot]
    cross = np.exp(-(np.minimum(xfr, 1 - xfr) * S / np.maximum(nplot[ik], 1) / 0.9) ** 2)
    z = z + cross * 0.8 * t_riser
    tone = sample_wrap(fbm_noise(H, H, [30, 8], seed=905), X * ss, yy * ss)
    grain = sample_wrap(fbm_noise(H, H, [0.8, 2.5], seed=906), X * ss, yy * ss)
    blot = sample_wrap(fbm_noise(H, H, [6, 2], seed=908), X * ss, yy * ss)
    water = mix(look((96, 94, 82)), look((82, 82, 72)), tone[..., None])
    water = mix(water, look((140, 126, 92)), smoothstep(0.62, 0.8, blot)[..., None] * 0.7)   # rạ nhô khỏi nước
    rows = 0.5 + 0.5 * np.cos(phi * 70 + wv * 4)
    stubble = mix(look((150, 136, 98)), look((132, 120, 88)), (rows * 0.35 + tone * 0.65)[..., None])
    stubble = mix(stubble, look((112, 120, 74)), smoothstep(0.6, 0.85, blot)[..., None] * 0.6)   # cỏ mọc lại
    ploughed = mix(look((122, 100, 76)), look((98, 82, 64)), (0.5 + 0.5 * np.sin(phi * 55 + wv * 9))[..., None])
    seedling = mix(look((104, 126, 70)), look((88, 108, 62)), tone[..., None]) * (0.85 + 0.25 * rows[..., None])
    alb = np.select([(kind == k)[..., None] for k in range(4)], [water, stubble, ploughed, seedling])
    alb = alb * (0.9 + 0.2 * tone[..., None])
    alb = alb * (0.88 + 0.24 * grain[..., None])
    grass = mix(look((84, 100, 54)), look((112, 116, 68)), grain[..., None])
    grass = grass * (0.8 + 0.4 * sample_wrap(fbm_noise(H, H, [1.5, 4], seed=910), X * ss, yy * ss))[..., None]
    on_riser = 1 - t_riser
    alb = mix(alb, grass, np.clip(on_riser * 1.3, 0, 1)[..., None])
    edge = np.clip(bund + cross * t_riser, 0, 1)
    alb = mix(alb, mix(look((128, 112, 84)), grass, 0.55), (edge * 0.9)[..., None])
    gloss = np.where(kind == 0, 0.3, 0.0) * t_riser * (1 - edge)
    cv.field(z.astype(np.float32), alb, gloss=gloss, mat=GROUND)
    cv.mat[(kind == 0) & (t_riser > 0.99) & (edge < 0.3)] = WATER       # mặt nước phẳng, không gồ ghề
    add_detail(cv, 0.8, 0.08, 0.5, seed=907, mats=(GROUND,))
    rgb, _ = cv.render(shadow_len=30, pen=0.05, ao_rad=8, ao_amt=0.8, wrap_light=0.1, sky_spec=0.15)
    rgb = rgb[M:M + S]
    save_jpg(to_image(desat(rgb, 0.9)), 'tex_terrace')


# ================================================================ main
ITEMS = {
    'sand': tex_sand,
    'sand_wet': tex_sand_wet,
    'sea': tex_sea,
    'foam': tex_foam,
    'canal': tex_canal,
    'rock': tex_rock,
    'forest': tex_forest,
    'scrub': tex_scrub,
    'terrace': tex_terrace,
    'coconut': palms_coconut,
    'nipa': palms_nipa,
    'casuarina': trees_casuarina,
    'pine': trees_pine,
    'bamboo': bamboo_tops,
    'mango': trees_mango,
    'basket': boats_basket,
    'sampan': boats_sampan,
    'boulders': rocks,
    'cactus': cactus,
}

if __name__ == '__main__':
    args = sys.argv[1:]
    if '--out' in args:
        i = args.index('--out')
        OUT = args[i + 1]
        del args[i:i + 2]
    if '--list' in args:
        print(' '.join(ITEMS))
        sys.exit(0)
    os.makedirs(OUT, exist_ok=True)
    bad = [a for a in args if a not in ITEMS]
    if bad:
        sys.exit(f'không có mục: {bad}; chọn trong: {" ".join(ITEMS)}')
    todo = [k for k in ITEMS if not args or k in args]
    for k in todo:
        t0 = time.time()
        ITEMS[k]()
        print(f'{k:12s} {time.time() - t0:6.1f}s', flush=True)
