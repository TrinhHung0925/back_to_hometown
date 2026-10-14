"""Dựng hình xe tả thực nhìn từ trên xuống (mũi xe hướng lên trên).

- Ô tô con, bán tải, xe tải: bộ "Topdown vehicle sprites" của UnLuckY Studio
  (miễn phí, dùng thương mại được — xem Read Me trong gói), đổi màu bằng code.
- Xe máy có người lái, xe khách, xe container: vẽ bằng code. Mỗi khối (mũ
  bảo hiểm, áo, tay, yên, thân xe…) được đổ sáng theo "độ phồng" của chính nó
  (làm mờ mặt nạ thành bản đồ độ cao → pháp tuyến → ánh sáng từ tây bắc) nên
  trông có khối như ảnh chụp.

Cần numpy + pillow:
    .venv/bin/python tool/asset_pipeline/build_vehicles.py
"""
import colorsys
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

UNLUCKY = 'asset_source/veh_unlucky/extracted/Topdown_vehicle_sprites_pack'
OUT = 'assets/images'
SS = 4  # vẽ to gấp 4 rồi thu nhỏ cho mép mịn

LIGHT = np.array([-0.42, -0.58, 0.70])
LIGHT /= np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0, 0, 1.0])
HALF /= np.linalg.norm(HALF)


class Canvas:
    """Ảnh RGBA (float) để chồng các khối đã đổ sáng."""

    def __init__(self, w, h):
        self.w, self.h = w * SS, h * SS
        self.rgb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)

    def mask(self, draw_fn):
        img = Image.new('L', (self.w, self.h), 0)
        draw_fn(ImageDraw.Draw(img), SS)
        return np.asarray(img, np.float32) / 255

    def shape(self, draw_fn, color, puff=6.0, gloss=0.0, rough=0.0, flat=False, alpha=1.0):
        """Vẽ một khối: [puff] độ phồng (px ảnh nhỏ), [gloss] độ bóng."""
        m = self.mask(draw_fn)
        if m.max() == 0:
            return m
        base = np.array(color, np.float32) / 255
        if flat:
            col = np.broadcast_to(base, m.shape + (3,))
        else:
            h = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(puff * SS)), np.float32) / 255
            gy, gx = np.gradient(h)
            k = 6.0 * SS
            n = np.stack([-gx * k, -gy * k, np.ones_like(h)], axis=-1)
            n /= np.linalg.norm(n, axis=-1, keepdims=True)
            diff = np.clip(n @ LIGHT, 0, 1)
            spec = np.clip(n @ HALF, 0, 1) ** 40 * gloss
            col = base * (0.38 + 0.78 * diff)[..., None] + spec[..., None]
            if rough > 0:
                noise = np.random.default_rng(len(self.a)).normal(0, rough, m.shape)
                col = col * (1 + noise[..., None])
        a = m * alpha
        self.rgb = self.rgb * (1 - a[..., None]) + col * a[..., None]
        self.a = np.clip(self.a + a * (1 - self.a), 0, 1)
        return m

    def image(self):
        out = np.zeros((self.h, self.w, 4), np.uint8)
        out[..., :3] = np.clip(self.rgb * 255, 0, 255).astype(np.uint8)
        out[..., 3] = np.clip(self.a * 255, 0, 255).astype(np.uint8)
        img = Image.fromarray(out)
        return img.resize((self.w // SS, self.h // SS), Image.LANCZOS)


def ellipse(cx, cy, rx, ry):
    return lambda d, s: d.ellipse([(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s], fill=255)


def rrect(x0, y0, x1, y1, r):
    return lambda d, s: d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s], radius=r * s, fill=255)


def poly(points):
    return lambda d, s: d.polygon([(x * s, y * s) for x, y in points], fill=255)


def line(points, width):
    return lambda d, s: d.line([(x * s, y * s) for x, y in points], fill=255, width=int(width * s), joint='curve')


def shade_rgb(rgb, f):
    return tuple(max(0, min(255, int(c * f))) for c in rgb)


# ------------------------------------------------------------ Xe máy
W, H = 64, 150  # khung ảnh xe máy (mũi xe ở trên)
CX = W / 2


def scooter(body, helmet, jacket, pants, passenger=None, cargo=None, visor=(30, 34, 40), skin=(214, 168, 130), police=False):
    c = Canvas(W, H)
    # Bánh trước / sau thò ra khỏi thân xe.
    c.shape(rrect(CX - 4.5, 4, CX + 4.5, 26, 4), (26, 26, 28), puff=2, gloss=0.2)
    c.shape(rrect(CX - 5, 118, CX + 5, 145, 4), (26, 26, 28), puff=2, gloss=0.2)
    # Thân xe: đầu xe, sàn để chân, đuôi xe.
    c.shape(poly([(CX - 9, 12), (CX + 9, 12), (CX + 11, 30), (CX + 9, 44), (CX - 9, 44), (CX - 11, 30)]), body, puff=4, gloss=0.5)
    c.shape(rrect(CX - 10, 42, CX + 10, 74, 3), (52, 54, 58), puff=1.5)
    c.shape(poly([(CX - 11, 70), (CX + 11, 70), (CX + 12, 104), (CX + 9, 128), (CX - 9, 128), (CX - 12, 104)]), body, puff=5, gloss=0.5)
    c.shape(rrect(CX - 6, 124, CX + 6, 130, 2), (200, 30, 30), puff=1, gloss=0.4)  # đèn hậu
    c.shape(ellipse(CX, 13, 6, 3), (245, 245, 235), puff=1.5, gloss=0.8)  # đèn pha
    # Yên xe (một phần lộ ra sau lưng người lái).
    c.shape(rrect(CX - 8, 66, CX + 8, 118, 7), (30, 30, 32), puff=4, gloss=0.25)
    if cargo == 'box':
        c.shape(rrect(CX - 13, 100, CX + 13, 132, 3), (186, 150, 100), puff=3, rough=0.05)
        c.shape(rrect(CX - 13, 114, CX + 13, 117, 1), (120, 90, 60), flat=True)
    elif cargo == 'sack':
        c.shape(ellipse(CX, 116, 15, 15), (214, 206, 182), puff=7, rough=0.06)
    # Chân người lái (đùi hướng về trước, hai bên sàn xe).
    for side in (-1, 1):
        c.shape(rrect(CX + side * 12 - 4, 52, CX + side * 12 + 4, 80, 4), pants, puff=3)
        c.shape(rrect(CX + side * 11 - 3.5, 44, CX + side * 11 + 3.5, 54, 3), (40, 40, 44), puff=2)  # dép/giày
    # Người ngồi sau.
    if passenger:
        p_helmet, p_jacket = passenger
        for side in (-1, 1):
            c.shape(rrect(CX + side * 13 - 4, 86, CX + side * 13 + 4, 106, 4), shade_rgb(p_jacket, 0.6), puff=3)
        c.shape(ellipse(CX, 104, 14, 9), p_jacket, puff=7, rough=0.03)
        c.shape(ellipse(CX, 98, 7.6, 8), p_helmet, puff=5, gloss=0.9)
    if cargo == 'peach':
        peach_branch(c, CX, 112)
    elif cargo == 'kumquat':
        kumquat_tree(c, CX, 112, 17)
    # Thân người lái: vai, áo, tay vươn tới tay lái.
    c.shape(ellipse(CX, 76, 15, 10), jacket, puff=7, rough=0.03)
    for side in (-1, 1):
        c.shape(line([(CX + side * 12, 72), (CX + side * 15, 56), (CX + side * 14, 34)], 6.2), jacket, puff=3, rough=0.03)
    # Ghi-đông, tay nắm, gương chiếu hậu.
    c.shape(rrect(CX - 17, 31, CX + 17, 35, 2), (48, 50, 54), puff=1.5, gloss=0.4)
    for side in (-1, 1):
        c.shape(line([(CX + side * 13, 30), (CX + side * 18, 20)], 1.6), (70, 72, 76), puff=1)
        c.shape(ellipse(CX + side * 19, 18, 4, 2.6), (60, 62, 66), puff=1.5, gloss=0.8)
        c.shape(ellipse(CX + side * 14, 33.5, 3.2, 3.2), skin, puff=2)  # bàn tay
    # Mũ bảo hiểm: kính chắn phía trước, có điểm sáng.
    c.shape(ellipse(CX, 68, 8.6, 9.6), helmet, puff=6, gloss=1.2)
    c.shape(ellipse(CX, 61.5, 6.4, 3.2), visor, puff=2, gloss=1.0)
    if police:
        c.shape(rrect(CX - 2, 60, CX + 2, 78, 1), (40, 70, 160), flat=True, alpha=0.9)
    return c.image()


def peach_branch(c, x, y):
    """Cành đào Tết: cành nâu toả ra, điểm hoa hồng."""
    rnd = random.Random(int(x * 13 + y))
    branches = []
    for i in range(6):
        ang = -math.pi / 2 + (i - 2.5) * 0.42 + rnd.uniform(-0.1, 0.1)
        ln = rnd.uniform(18, 26)
        pts = [(x, y + 8), (x + math.cos(ang) * ln * 0.5, y + 8 + math.sin(ang) * ln * 0.5 + 18),
               (x + math.cos(ang) * ln, y + 8 + math.sin(ang) * ln + 26)]
        branches.append(pts)
        c.shape(line(pts, 1.6), (92, 60, 40), puff=1)
    for pts in branches:
        for t in np.linspace(0.3, 1, 5):
            px = pts[0][0] + (pts[2][0] - pts[0][0]) * t + rnd.uniform(-3, 3)
            py = pts[0][1] + (pts[2][1] - pts[0][1]) * t + rnd.uniform(-3, 3)
            col = rnd.choice([(244, 150, 180), (236, 120, 160), (250, 190, 205)])
            c.shape(ellipse(px, py, 3, 3), col, puff=1.5, gloss=0.3)


def kumquat_tree(c, x, y, r):
    """Cây quất: tán tròn xanh đậm lấm tấm quả cam."""
    rnd = random.Random(int(x * 7 + y))
    c.shape(ellipse(x, y, r, r), (46, 104, 44), puff=r * 0.5, rough=0.12)
    for _ in range(int(r * 1.4)):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0, r * 0.8)
        c.shape(ellipse(x + math.cos(a) * d, y + math.sin(a) * d, 2.2, 2.2), (246, 150, 30), puff=1, gloss=0.6)


# Bảng màu người đi xe máy Việt: mũ, áo khoác chống nắng, quần.
HELMETS = [(220, 40, 40), (245, 245, 245), (40, 90, 190), (250, 200, 40), (30, 30, 34), (240, 130, 170), (60, 160, 90), (150, 150, 155)]
JACKETS = [(60, 110, 200), (230, 230, 230), (210, 60, 90), (90, 90, 96), (240, 150, 60), (60, 150, 140), (150, 80, 160), (200, 190, 160)]
PANTS = [(40, 50, 80), (30, 30, 34), (110, 100, 90), (60, 70, 90)]
BODIES = [(200, 30, 36), (235, 235, 235), (30, 30, 34), (40, 90, 170), (150, 155, 160), (130, 30, 40), (240, 200, 60)]


def build_scooters():
    rnd = random.Random(3)
    # Xe của người chơi: mũ đỏ, áo vàng, xe đỏ — dễ nhận ra giữa dòng xe.
    scooter((210, 32, 36), (226, 36, 36), (245, 196, 40), (40, 50, 80)).save(f'{OUT}/img_scooter_player.png', optimize=True)
    scooter((235, 235, 235), (245, 245, 245), (40, 64, 120), (30, 34, 50), police=True).save(f'{OUT}/img_scooter_police.png', optimize=True)
    cargos = [None, None, None, 'box', 'sack', 'peach', 'kumquat', None, 'peach', None]
    for i in range(10):
        passenger = (rnd.choice(HELMETS), rnd.choice(JACKETS)) if i in (1, 4, 7, 9) else None
        img = scooter(rnd.choice(BODIES), rnd.choice(HELMETS), rnd.choice(JACKETS), rnd.choice(PANTS),
                      passenger=passenger, cargo=cargos[i])
        img.save(f'{OUT}/img_scooter_ai_{i + 1}.png', optimize=True)


def build_cargo():
    """Hàng Tết chở theo xe người chơi (vẽ đè lên yên sau / nóc xe)."""
    for name, fn in [('peach', lambda c: peach_branch(c, 32, 24)), ('kumquat', lambda c: kumquat_tree(c, 32, 32, 20)),
                     ('box', lambda c: c.shape(rrect(14, 16, 50, 48, 3), (186, 150, 100), puff=3, rough=0.05))]:
        c = Canvas(64, 64)
        fn(c)
        c.image().save(f'{OUT}/img_cargo_{name}.png', optimize=True)


# ----------------------------------------------------- Xe khách, xe tải
def coach(main, stripe, name):
    w, h = 66, 214
    c = Canvas(w, h)
    c.shape(rrect(3, 3, w - 3, h - 3, 9), main, puff=5, gloss=0.35)
    c.shape(rrect(5, 4, w - 5, 24, 7), (34, 46, 60), puff=2, gloss=1.0)  # kính lái
    c.shape(rrect(8, h - 14, w - 8, h - 5, 4), (40, 50, 60), puff=1.5, gloss=0.8)  # kính hậu
    for side in (3, w - 8):
        c.shape(rrect(side, 30, side + 5, h - 24, 2), stripe, flat=True)
    c.shape(rrect(17, 52, w - 17, 96, 4), (200, 204, 208), puff=3, gloss=0.4)  # cục điều hoà
    for y in (60, 70, 80, 90):
        c.shape(rrect(20, y, w - 20, y + 2, 1), (150, 154, 160), flat=True)
    for y in (120, 160):
        c.shape(rrect(24, y, w - 24, y + 16, 3), (170, 174, 178), puff=2, gloss=0.5)  # cửa thoát hiểm trên nóc
    c.image().save(f'{OUT}/{name}.png', optimize=True)


def container_truck(color, name):
    w, h = 62, 184
    c = Canvas(w, h)
    c.shape(rrect(6, 4, w - 6, 40, 6), color, puff=4, gloss=0.5)  # cabin
    c.shape(rrect(8, 5, w - 8, 15, 4), (34, 46, 60), puff=1.5, gloss=1.0)
    c.shape(rrect(3, 44, w - 3, h - 3, 2), (196, 120, 60), puff=2)  # thùng container
    for y in range(48, h - 6, 6):
        c.shape(rrect(4, y, w - 4, y + 2, 1), (160, 92, 46), flat=True)
    c.image().save(f'{OUT}/{name}.png', optimize=True)


# ------------------------------------------------------- Người chờ xe
def person(hat, shirt, bag, seed):
    """Người đứng chờ nhìn từ trên: đầu (nón lá / tóc / mũ), vai áo, tay,
    hành lý bên cạnh."""
    rnd = random.Random(seed)
    c = Canvas(48, 48)
    cx, cy = 22, 24
    if bag == 'suitcase':
        c.shape(rrect(32, 18, 44, 36, 2), rnd.choice([(60, 90, 160), (40, 40, 44), (170, 60, 50)]), puff=2, gloss=0.4)
    elif bag == 'sack':
        c.shape(ellipse(38, 30, 7, 8), (214, 206, 182), puff=4, rough=0.06)
    elif bag == 'peach':
        peach_branch(c, 38, 4)
    elif bag == 'kumquat':
        kumquat_tree(c, 38, 30, 8)
    for side in (-1, 1):
        c.shape(ellipse(cx + side * 10, cy + 3, 3.2, 6), shade_rgb(shirt, 0.92), puff=2)
    c.shape(ellipse(cx, cy + 2, 11, 7), shirt, puff=4, rough=0.03)
    if hat == 'nonla':
        c.shape(ellipse(cx, cy - 1, 10, 10), (228, 208, 152), puff=6, gloss=0.25, rough=0.04)
        for r in (3.5, 6.5, 9):
            c.shape(lambda d, s, r=r: d.ellipse([(cx - r) * s, (cy - 1 - r) * s, (cx + r) * s, (cy - 1 + r) * s], outline=255, width=int(0.5 * s)),
                    (190, 168, 110), flat=True, alpha=0.6)
    elif hat == 'cap':
        c.shape(ellipse(cx, cy - 1, 5.6, 6), rnd.choice([(200, 40, 40), (40, 60, 120), (240, 240, 240)]), puff=3, gloss=0.4)
        c.shape(rrect(cx - 4, cy - 10, cx + 4, cy - 5, 2), (60, 60, 64), puff=1)
    else:
        c.shape(ellipse(cx, cy - 1, 5.4, 6), (28, 24, 22), puff=3, gloss=0.5)
    return c.image()


def build_people():
    shirts = [(200, 40, 40), (40, 90, 170), (240, 240, 236), (60, 140, 90), (230, 160, 60), (120, 70, 140), (90, 90, 96), (220, 120, 150)]
    hats = ['nonla', 'hair', 'cap', 'hair', 'nonla', 'cap', 'hair', 'nonla']
    bags = ['suitcase', 'sack', None, 'peach', 'suitcase', 'kumquat', None, 'sack']
    for i in range(8):
        person(hats[i], shirts[i], bags[i], 90 + i).save(f'{OUT}/img_person_{i + 1}.png', optimize=True)


# ----------------------------------------------------------- Ô tô con
def recolor(path, target, out, keep_dark=True):
    """Đổi màu sơn: pixel có độ bão hoà cao (sơn xe) đổi sang màu [target]
    giữ nguyên độ sáng tối; kính, lốp, đèn giữ nguyên."""
    img = Image.open(path).convert('RGBA')
    img = img.crop(img.getbbox())
    a = np.asarray(img, np.float32) / 255
    rgb, alpha = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    paint = sat > 0.35
    tr, tg, tb = (v / 255 for v in target)
    th, tl, ts = colorsys.rgb_to_hls(tr, tg, tb)
    lum = (mx + mn) / 2
    # Độ sáng theo ảnh gốc, chuẩn hoá quanh độ sáng màu đích.
    ref = np.median(lum[paint]) if paint.any() else 0.5
    new_l = np.clip(lum / max(ref, 1e-3) * tl, 0, 1)
    out_rgb = rgb.copy()
    hls_to_rgb = np.vectorize(colorsys.hls_to_rgb)
    r, g, b = hls_to_rgb(th, new_l[paint], ts)
    out_rgb[paint] = np.stack([r, g, b], -1)
    res = np.concatenate([out_rgb, alpha[..., None]], -1)
    Image.fromarray((np.clip(res, 0, 1) * 255).astype(np.uint8)).save(out, optimize=True)


def build_cars():
    sedan = f'{UNLUCKY}/Audi.png'
    colors = {
        'red': (200, 30, 36), 'white': (236, 236, 232), 'silver': (176, 180, 186), 'black': (40, 42, 46),
        'blue': (40, 80, 160), 'gray': (110, 114, 120), 'brown': (120, 80, 50), 'green': (40, 110, 80),
    }
    for name, rgb in colors.items():
        recolor(sedan, rgb, f'{OUT}/img_sedan_{name}.png')
    for name, rgb in {'blue': (40, 110, 180), 'white': (232, 232, 228), 'gray': (120, 124, 128)}.items():
        recolor(f'{UNLUCKY}/Mini_truck.png', rgb, f'{OUT}/img_pickup_{name}.png')
    for name in ('Mini_van', 'truck', 'Ambulance'):
        img = Image.open(f'{UNLUCKY}/{name}.png').convert('RGBA')
        img.crop(img.getbbox()).save(f'{OUT}/img_{name.lower()}.png', optimize=True)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    build_scooters()
    build_cargo()
    coach((240, 240, 236), (210, 50, 40), 'img_bus_1')
    coach((250, 250, 248), (40, 110, 190), 'img_bus_2')
    coach((236, 120, 40), (250, 250, 250), 'img_bus_3')
    coach((200, 28, 32), (246, 196, 60), 'img_bus_player')
    build_people()
    container_truck((40, 90, 170), 'img_container_1')
    container_truck((220, 220, 216), 'img_container_2')
    build_cars()
    print('done')
