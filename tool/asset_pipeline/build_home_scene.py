"""Cảnh về tới nhà chiều / đêm 30 Tết (nền cho đoạn phim kết thúc chuyến đi).

Dựng giả 3D bằng phép chiếu phối cảnh: mặt nhà, tường rào cổng, tường nhà
hàng xóm là các mặt phẳng (vẽ bằng bộ vẽ mặt đứng của build_driver_scenery.py
rồi uốn phối cảnh), cây là ảnh đứng, mặt ngõ / sân gạch là mặt đất chiếu
từng điểm ảnh. Mắt cao 1,6 m, nhìn chéch 3/4 từ ngoài ngõ vào cổng.

Ghi:
    assets/images/img_home_day.jpg    chiều 30 Tết, nắng vàng thấp, sương mỏng
    assets/images/img_home_night.jpg  đêm giao thừa: đèn lồng, cửa sổ sáng, dây đèn
    assets/images/home_scene.json     mốc toạ độ cho game (mặt đất, chỗ xe dừng,
                                      chỗ người nhà đứng, vùng trời bắn pháo hoa)

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_home_scene.py
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_driver_scenery as S  # noqa: E402

ROOT = S.ROOT
IMG = os.path.join(ROOT, 'assets', 'images')
DRV = os.path.join(IMG, 'driver')
W, H = 2200, 1000
F = 1350.0          # tiêu cự (px)
CX, CY = 1100.0, 560.0   # tâm ảnh, đường chân trời
EYE = 1.6
# Hàng rào nhà: đường thẳng mặt đất đi từ gần-trái ra xa-phải.
ANG = math.radians(28)
U = np.array([math.cos(ANG), 0.0, math.sin(ANG)])      # dọc hàng rào
N = np.array([-math.sin(ANG), 0.0, math.cos(ANG)])     # hướng vào sân
P0 = np.array([-5.2, 0.0, 4.6])                         # gốc hàng rào (t = 0)
GATE_T = (6.6, 9.4)                                     # khoảng cổng trên hàng rào
FENCE_T = (3.2, 17.0)
HOUSE_D = 5.0                                           # sân sâu (m)
HOUSE_T0 = 4.4


def P(t, d=0.0, y=0.0):
    return P0 + U * t + N * d + np.array([0, y, 0])


def proj(p):
    x, y, z = p
    return CX + F * x / z, CY - F * (y - EYE) / z


def homography(src, dst):
    """Hệ số PIL PERSPECTIVE (ảnh ra → ảnh nguồn) từ 4 cặp điểm."""
    A, b = [], []
    for (sx, sy), (dx, dy) in zip(src, dst):
        A.append([dx, dy, 1, 0, 0, 0, -sx * dx, -sx * dy])
        A.append([0, 0, 0, dx, dy, 1, -sy * dx, -sy * dy])
        b += [sx, sy]
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()


def plane_img(img, t0, t1, d, y0, y1):
    """Uốn ảnh mặt đứng [img] lên mặt phẳng dọc hàng rào (t0..t1, cách d,
    cao y0..y1) → ảnh RGBA cỡ khung hình."""
    w, h = img.size
    dst = [proj(P(t0, d, y1)), proj(P(t1, d, y1)), proj(P(t1, d, y0)), proj(P(t0, d, y0))]
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    co = homography(src, dst)
    return img.transform((W, H), Image.PERSPECTIVE, co, Image.BICUBIC)


def billboard(canvas, img, base, h_m, flip=False):
    x, y = proj(base)
    s = F / base[2]
    hh = int(h_m * s)
    ww = int(img.width * hh / img.height)
    im = img.resize((max(1, ww), max(1, hh)), Image.LANCZOS)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(im, (int(x - ww / 2), int(y - hh)))


def tex(name, size=None):
    im = Image.open(os.path.join(IMG, name)).convert('RGB')
    return np.asarray(im, np.float64) / 255.0


def ground_and_sky(sky_name, night):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    out = np.zeros((H, W, 3))
    # trời: lấy từ ảnh toàn cảnh (180° / 0..40°)
    sky = np.asarray(Image.open(os.path.join(DRV, sky_name)).convert('RGB'), np.float64) / 255
    az = np.degrees(np.arctan2(xx - CX, F)) + 40
    el = np.degrees(np.arctan2(CY - yy, np.hypot(F, xx - CX)))
    u = (np.mod(az, 180) / 180 * sky.shape[1]).astype(int) % sky.shape[1]
    v = np.clip(((40 - el) / 40 * sky.shape[0]).astype(int), 0, sky.shape[0] - 1)
    out[:] = sky[v, u]
    # đất: chiếu điểm ảnh xuống mặt đất
    g = yy > CY + 1
    Z = np.where(g, F * EYE / np.maximum(yy - CY, 1e-3), 1)
    X = (xx - CX) * Z / F
    t = (X - P0[0]) * U[0] + (Z - P0[2]) * U[2]
    d = (X - P0[0]) * N[0] + (Z - P0[2]) * N[2]
    conc = tex('tex_concrete.jpg')
    brick = tex('tex_paving_red.jpg')
    grass = tex('tex_grass_rough.jpg')
    verge = tex('tex_verge.jpg')

    def samp(tx, a, b, scale):
        hh, ww = tx.shape[:2]
        iu = (np.mod(a / scale, 1) * ww).astype(int) % ww
        iv = (np.mod(b / scale, 1) * hh).astype(int) % hh
        return tx[iv, iu]
    lane = samp(conc, t, d, 2.5) * 0.95
    # vệt bánh xe sẫm, ố nước
    lane = lane * (0.88 + 0.12 * S.fbm(t * 0.6, d * 0.6, seed=3, octaves=3))[..., None]
    yard = samp(brick, t, d, 1.6)
    edge = samp(grass, t, d, 1.2) * np.array([0.9, 1.0, 0.8])
    dirt = samp(verge, t, d, 1.5)
    col = lane
    col = np.where(((d > -0.6) & (d < 0))[..., None], edge * 0.8 + dirt * 0.2, col)
    col = np.where(((d < -4.4))[..., None], dirt * 0.7 + edge * 0.3, col)
    col = np.where((d >= 0)[..., None], yard, col)
    # bóng mờ chân tường, xa thì nhạt (sương)
    col = col * (1 - 0.25 * np.exp(-np.abs(d) / 0.5))[..., None]
    fog = np.clip((Z - 8) / 60, 0, 1)[..., None]
    haze = np.array([0.85, 0.78, 0.66]) if not night else np.array([0.08, 0.09, 0.14])
    col = col * (1 - fog) + haze * fog
    out = np.where(g[..., None], col, out)
    return out


def build(night):
    base = ground_and_sky('sky_night.png' if night else 'sky_dusk.png', night)
    if not night:
        day = np.asarray(Image.open(os.path.join(DRV, 'sky_day.png')).convert('RGB'), np.float64) / 255
        # chiều muộn: trộn trời ngày với trời hoàng hôn, giữ vùng trên trong
        sky_d = ground_and_sky('sky_day.png', False)
        mix = np.clip((np.arange(H)[:, None] / CY), 0, 1)[..., None] * 0.55
        base = np.where((np.arange(H)[:, None] < CY)[..., None], sky_d * (1 - mix) + base * mix, base)
        del day
    bg = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8), 'RGB').convert('RGBA')
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))  # lớp vật thể (để biết đâu là trời)
    # cây làng phía sau nhà
    far = [('tree_broad_4.png', P(2.0, 14, 0), 9.7, False), ('tree_bamboo_1.png', P(9.0, 16, 0), 7.8, True),
           ('tree_broad_2.png', P(15.0, 13, 0), 11.4, True), ('tree_broad_3.png', P(-3.0, 12, 0), 8.5, False),
           ('tree_bamboo_2.png', P(20.0, 9, 0), 8.7, False), ('palm_coconut_2.png', P(12.0, 11, 0), 10.5, True)]
    for name, pos, hm, fl in sorted(far, key=lambda e: -e[1][2]):
        billboard(canvas, Image.open(os.path.join(DRV, name)).convert('RGBA'), pos, hm, fl)
    # nhà (mặt đứng không có rào) — đặt lùi sau sân
    spec = dict(S.VILLAGE['house_village_1'])
    spec.update(fence=None, gate=None, flag=None, table=True, pots=['kumquat', 'kumquat'])
    himg, hh, fac = S.village_house(spec, keep=True)
    hw = spec['width']
    canvas.alpha_composite(plane_img(himg, HOUSE_T0, HOUSE_T0 + hw, HOUSE_D, 0, hh))
    # mặt nạ cửa kính / vải (để thắp sáng ban đêm)
    def mat_mask(m):
        mk = (fac.mat == m).astype(np.float64) * fac.a
        mk = mk.reshape(fac.H // fac.ss, fac.ss, fac.W // fac.ss, fac.ss).mean(axis=(1, 3))
        im = Image.fromarray((mk * 255).astype(np.uint8), 'L').resize(himg.size)
        return np.asarray(plane_img(im.convert('RGBA'), HOUSE_T0, HOUSE_T0 + hw, HOUSE_D, 0, hh))[..., 0] / 255.0
    glass = mat_mask(S.M_GLASS) if night else None
    fabric = mat_mask(S.M_FABRIC) if night else None
    # cây đào trong sân cạnh cổng
    peach = Image.open(os.path.join(DRV, 'flower_peach_1.png')).convert('RGBA')
    pp = P(GATE_T[1] + 0.9, 1.2, 0)
    billboard(canvas, peach, pp, 2.9)
    # tường rào + cổng mở
    fence_img, fence_h, lan_pos = fence_facade()
    canvas.alpha_composite(plane_img(fence_img, FENCE_T[0], FENCE_T[1], 0.0, 0, fence_h))
    # tường nhà hàng xóm dọc ngõ bên trái + lũy tre sau tường
    for k, (name, t, hm, fl) in enumerate([('tree_bamboo_2.png', -1.0, 8.6, False), ('tree_bamboo_1.png', 1.5, 7.6, True),
                                           ('tree_bamboo_2.png', -4.5, 8.4, True)]):
        billboard(canvas, Image.open(os.path.join(DRV, name)).convert('RGBA'), P(t, 1.6, 0), hm, fl)
    nb = neighbour_wall()
    canvas.alpha_composite(plane_img(nb, -9.0, FENCE_T[0], 0.0, 0, 2.1))
    obj_a = np.asarray(canvas, np.float64)[..., 3] / 255.0
    bg.alpha_composite(canvas)
    img = np.asarray(bg.convert('RGB'), np.float64) / 255.0
    if not night:
        # nắng chiều vàng, sương mỏng, tối góc nhẹ
        img = img * np.array([1.07, 1.0, 0.86])
        yy, xx = np.mgrid[0:H, 0:W]
        glow = np.exp(-((xx - 300) ** 2 / 900 ** 2 + (yy - CY) ** 2 / 300 ** 2))[..., None]
        img = img * (1 - 0.18 * glow) + np.array([1.0, 0.82, 0.55]) * 0.18 * glow
        vig = 1 - 0.18 * (((xx - CX) / CX) ** 2 + ((yy - 500) / 600) ** 2)[..., None]
        img = np.clip(img * vig, 0, 1)
    else:
        yy, xx = np.mgrid[0:H, 0:W]
        skym = ((yy < CY) & (obj_a < 0.5))[..., None]
        ska = ((yy < CY) * (1 - obj_a))[..., None]
        sky = np.asarray(Image.fromarray((ground_and_sky('sky_night.png', True) * 255).astype(np.uint8)),
                         np.float64) / 255
        lit = (img ** 2.2) * np.array([0.07, 0.08, 0.14])
        # ánh sáng ấm hắt ra từ nhà và cổng
        gx, gy = proj(P(sum(GATE_T) / 2, 2.0, 1.2))
        pool = np.exp(-((xx - gx) ** 2 / 700 ** 2 + (yy - gy - 120) ** 2 / 260 ** 2))[..., None]
        lit = lit + (img ** 2.2) * np.array([1.0, 0.62, 0.30]) * 0.35 * pool
        win = np.clip(gaussian(glass, 1.5) * 1.3, 0, 1)
        lit = lit * (1 - win[..., None]) + np.array([1.0, 0.66, 0.32]) * 0.85 * win[..., None]
        lit = lit + np.array([1.0, 0.6, 0.25]) * gaussian(glass, 30)[..., None] * 0.35
        # đèn lồng: thân đỏ rực, quầng sáng
        red = gaussian(fabric, 1)
        lit = lit * (1 - red[..., None]) + np.array([1.0, 0.18, 0.06]) * 1.2 * red[..., None]
        lit = lit + np.array([1.0, 0.35, 0.12]) * gaussian(fabric, 25)[..., None] * 0.6
        for (lx, ly) in lan_pos:
            r = 45
            lit = lit + np.array([1.0, 0.4, 0.15]) * 0.5 * np.exp(-((xx - lx) ** 2 + (yy - ly) ** 2) / (2 * r * r))[..., None]
            lit = lit + np.array([1.0, 0.3, 0.1]) * 0.9 * np.exp(-((xx - lx) ** 2 + (yy - ly) ** 2) / (2 * 9 * 9))[..., None]
        # dây đèn nháy trên cây đào
        rng = np.random.default_rng(3)
        pa = np.asarray(peach, np.float64)[..., 3]
        x0, y0 = proj(pp)
        s = F / pp[2]
        ph = 2.9 * s
        pw = peach.width * ph / peach.height
        ys, xs = np.nonzero(pa[: int(pa.shape[0] * 0.75)] > 200)
        sel = rng.choice(len(xs), 160, replace=False)
        dots = np.zeros((H, W))
        cols = np.zeros((H, W, 3))
        palette = np.array([[1.0, 0.85, 0.5], [1.0, 0.3, 0.3], [0.4, 1.0, 0.5], [0.5, 0.7, 1.0], [1.0, 0.9, 0.3]])
        for i in sel:
            X = int(x0 - pw / 2 + xs[i] * pw / peach.width)
            Y = int(y0 - ph + ys[i] * ph / peach.height)
            if 0 <= X < W and 0 <= Y < H:
                dots[Y, X] = 1
                cols[Y, X] = palette[i % 5]
        core = np.stack([gaussian(cols[..., c], 1.2) for c in range(3)], -1) * 9
        halo = np.stack([gaussian(cols[..., c], 6) for c in range(3)], -1) * 60
        lit = lit + core + halo * 0.5
        lit = lit * (1 - ska) + (sky ** 2.2) * ska
        del skym
        img = np.clip(lit, 0, 1) ** (1 / 2.2)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')


def gaussian(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(r))
    return np.asarray(im, np.float64) / 255.0


def fence_facade():
    """Tường rào vôi + trụ cổng câu đối đỏ, băng rôn, đèn lồng, cổng sắt mở."""
    Lm = FENCE_T[1] - FENCE_T[0]
    Hm = 3.4
    f = S.Facade(Lm, Hm, 70, ss=2, seed=77)
    g0, g1 = GATE_T[0] - FENCE_T[0], GATE_T[1] - FENCE_T[0]
    S.fence(f, 0.0, Lm, g0, g1, 'lime', None, h=0.0, seed=5, wall_rgb=(232, 226, 210))
    red = S.lin((196, 26, 28))
    gold = S.lin((246, 206, 70))
    for px, words in ((g0 - 0.2, ['PHÚC', 'LỘC', 'THỌ']), (g1 + 0.2, ['AN', 'KHANG', 'VƯỢNG'])):
        f.paint(f.rect(px - 0.13, 0.35, px + 0.13, 1.75), red, h=0.2, mat=S.M_FABRIC)
        for k, wd in enumerate(words):
            f.paint(f.text_mask(wd, 'paytone', 0.1, px, 1.5 - k * 0.42, max_w=0.22), gold, hadd=0.003)
        f.paint(f.rect(px - 0.03, 1.97, px + 0.03, 2.9), S.lin((60, 60, 64)), h=0.15, mat=S.M_METAL)
    f.paint(f.rect(g0 - 0.3, 2.35, g1 + 0.3, 2.85), red, h=0.18, mat=S.M_FABRIC)
    f.paint(f.text_mask('CHÚC MỪNG NĂM MỚI', 'paytone', 0.26, (g0 + g1) / 2, 2.6, max_w=g1 - g0 + 0.3), gold,
            hadd=0.003)
    lan = []
    for lx in (g0 + 0.35, g1 - 0.35):
        S.lantern(f, lx, 2.35, r=0.17, h=0.3, string=0.08)
        lan.append((lx, 2.35 - 0.08 - 0.18))
    # hai cánh cổng sắt mở áp vào trong (nhìn xiên: dải hẹp)
    for gx, sgn in ((g0 + 0.05, 1), (g1 - 0.05, -1)):
        a, b = sorted((gx, gx + sgn * 0.35))
        f.paint(f.rect(a, 0.05, b, 1.7), S.lin((40, 44, 50)), h=0.6, mat=S.M_METAL)
        for k in range(6):
            xx = a + (k + 0.5) * (b - a) / 6
            f.paint(f.rect(xx - 0.008, 0.1, xx + 0.008, 1.65), S.lin((90, 96, 104)), h=0.62)
    f.weather(amount=1.0, splash=1.2, seed=9)
    img = f.render()
    # vị trí đèn lồng trong khung hình
    pos = [proj(P(FENCE_T[0] + x, 0.0, y)) for x, y in lan]
    return img, Hm, pos


def neighbour_wall():
    """Tường xi măng nhà hàng xóm, rêu mốc, mũ tường."""
    Lm = FENCE_T[0] + 9.0
    f = S.Facade(Lm, 2.1, 60, ss=2, seed=88)
    f.paint(f.rect(0, 0, Lm, 2.0), S.plaster_fn(f, (168, 164, 154), 3, peel=0.3), h=0.0, mat=S.M_WALL)
    f.paint(f.rect(-0.05, 1.92, Lm + 0.05, 2.1), S.lin((150, 146, 138)), h=0.08, mat=S.M_TRIM)
    for k in range(int(Lm / 3)):
        x = 1.5 + k * 3
        f.paint(f.rect(x - 0.15, 0, x + 0.15, 2.0), S.plaster_fn(f, (176, 172, 162), 4), h=0.06, mat=S.M_WALL)
    f.weather(amount=1.8, splash=1.6, seed=4)
    return f.render()


def meta():
    gc = sum(GATE_T) / 2
    gx, gy = proj(P(gc, -1.3, 0))
    z = P(gc, -1.3, 0)[2]
    vx, vy = proj(P(gc - 3.0, -1.6, 0))
    spots = []
    for t, d in ((gc - 0.9, 0.6), (gc - 0.3, 1.4), (gc + 0.3, 0.9), (gc + 0.9, 1.6), (gc + 1.2, 0.3)):
        x, y = proj(P(t, d, 0))
        spots.append([int(round(x)), int(round(y))])
    return {
        'ground_y': int(round(gy)),
        'px_per_m': round(F / z, 1),
        'vehicle_stop_x': int(round(vx)),
        'vehicle_stop_y': int(round(vy)),
        "vehicle_px_per_m": round(F / P(gc - 3.0, -1.6, 0)[2], 1),
        'family_spots': spots,
        'sky_rect': [0, 0, W, 350],
        'gate_x': int(round(gx)),
        'note': 'khung 2200x1000; mặt đất trước cổng ở ground_y; xe vào từ mép trái dọc ngõ',
    }


def main():
    for night, name in ((False, 'img_home_day.jpg'), (True, 'img_home_night.jpg')):
        im = build(night)
        im.save(os.path.join(IMG, name), quality=86, optimize=True)
        print(name, os.path.getsize(os.path.join(IMG, name)) // 1024, 'KB')
    with open(os.path.join(IMG, 'home_scene.json'), 'w') as fh:
        json.dump(meta(), fh, ensure_ascii=False, indent=1)
    print(json.dumps(meta(), ensure_ascii=False))


if __name__ == '__main__':
    main()
