"""Icon minh hoạ cho thực đơn quán, cây xăng, tiệm vá xe (nhìn nghiêng, đổ
sáng theo khối như hình trong game — dùng chung bộ vẽ của build_vehicles.py).

Chạy từ thư mục gốc:
    .venv/bin/python tool/asset_pipeline/build_menu_items.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_vehicles import Canvas, ellipse, line, poly, rrect, shade_rgb  # noqa: E402

OUT = 'assets/images'
S = 64

GLASS = (214, 230, 236)
ICE = (246, 250, 252)


def glass(c, liquid, top=14, bottom=58, rnd=None, ice=3, tall=False):
    """Cốc thuỷ tinh nhìn nghiêng: miệng rộng, đáy hẹp, nước, đá viên."""
    rnd = rnd or random.Random(1)
    x0, x1 = (18, 46) if tall else (14, 50)
    b0, b1 = (21, 43) if tall else (18, 46)
    c.shape(poly([(x0, top), (x1, top), (b1, bottom), (b0, bottom)]), GLASS, puff=4, gloss=1.4, alpha=0.6)
    level = top + 8
    c.shape(poly([(x0 + 2, level), (x1 - 2, level), (b1 - 1.5, bottom - 2), (b0 + 1.5, bottom - 2)]), liquid, puff=5, gloss=1.0, alpha=0.92)
    for _ in range(ice):
        x = rnd.uniform(x0 + 6, x1 - 12)
        y = rnd.uniform(level - 2, level + 12)
        c.shape(rrect(x, y, x + 9, y + 9, 2), ICE, puff=2, gloss=1.4, alpha=0.85)
    c.shape(rrect(x0 + 3, top + 3, x0 + 6, bottom - 6, 1.5), (255, 255, 255), flat=True, alpha=0.35)
    c.shape(ellipse((x0 + x1) / 2, top, (x1 - x0) / 2, 2.4), shade_rgb(GLASS, 1.05), puff=1, gloss=1.2, alpha=0.7)


def straw(c, color=(230, 60, 60)):
    c.shape(line([(38, 4), (32, 40)], 3), color, puff=1, gloss=0.6)


def tra_da():
    c = Canvas(S, S)
    glass(c, (200, 130, 40), rnd=random.Random(3))
    return c.image()


def nuoc_mia(tac=False):
    c = Canvas(S, S)
    straw(c, (60, 170, 90))
    glass(c, (214, 214, 120), rnd=random.Random(5), tall=True)
    if tac:
        c.shape(ellipse(46, 16, 7, 7), (240, 160, 30), puff=3, gloss=0.8)
        c.shape(ellipse(46, 16, 4.6, 4.6), (250, 210, 90), puff=2, gloss=0.6)
    return c.image()


def ca_phe(milk=False):
    c = Canvas(S, S)
    liquid = (200, 150, 100) if milk else (70, 40, 24)
    glass(c, liquid, top=22, rnd=random.Random(7), ice=2)
    # Phin nhôm đặt trên miệng cốc.
    c.shape(rrect(20, 4, 44, 20, 3), (190, 194, 200), puff=4, gloss=1.4)
    c.shape(rrect(16, 18, 48, 23, 2), (176, 180, 186), puff=2, gloss=1.2)
    c.shape(ellipse(32, 5, 10, 2.4), (150, 154, 160), puff=1, gloss=1)
    if milk:
        c.shape(rrect(17, 46, 47, 56, 3), (240, 232, 214), puff=3, alpha=0.9)
    return c.image()


def huong_duong():
    rnd = random.Random(9)
    c = Canvas(S, S)
    c.shape(ellipse(32, 44, 26, 10), (236, 236, 230), puff=4, gloss=0.8)
    c.shape(ellipse(32, 40, 20, 8), (226, 226, 220), puff=2)
    for _ in range(26):
        x = rnd.uniform(16, 48)
        y = rnd.uniform(30, 44)
        a = rnd.uniform(0, math.pi)
        dx, dy = math.cos(a) * 3, math.sin(a) * 1.4
        c.shape(line([(x - dx, y - dy), (x + dx, y + dy)], 2.4), (36, 32, 30), puff=0.8, gloss=0.6)
    return c.image()


def ghe_nhua():
    c = Canvas(S, S)
    red = (214, 40, 40)
    c.shape(rrect(12, 18, 52, 26, 3), red, puff=3, gloss=0.9)
    for x in (16, 44):
        c.shape(poly([(x - 2, 24), (x + 6, 24), (x + 4, 56), (x, 56)]), shade_rgb(red, 0.85), puff=2, gloss=0.5)
    c.shape(rrect(22, 36, 42, 40, 1), shade_rgb(red, 0.7), puff=1)
    return c.image()


def vong():
    c = Canvas(S, S)
    c.shape(line([(6, 14), (58, 14)], 2), (110, 90, 70), puff=0.6)
    c.shape(poly([(8, 16), (56, 16), (50, 40), (32, 50), (14, 40)]), (60, 140, 90), puff=6, rough=0.04)
    for k in range(4):
        y = 22 + k * 6
        c.shape(line([(12 + k * 2, y), (52 - k * 2, y)], 1), (40, 100, 64), flat=True, alpha=0.6)
    c.shape(ellipse(26, 30, 6, 5), (28, 24, 22), puff=3, gloss=0.5)
    c.shape(ellipse(38, 34, 10, 6), (90, 120, 190), puff=4)
    return c.image()


def banh_mi():
    c = Canvas(S, S)
    c.shape(ellipse(32, 36, 28, 13), (216, 150, 64), puff=8, gloss=0.7)
    c.shape(poly([(8, 34), (56, 30), (54, 38), (10, 42)]), (120, 160, 70), puff=2)
    c.shape(poly([(10, 36), (54, 32), (52, 37), (12, 40)]), (200, 90, 80), puff=2)
    for x in (18, 30, 42):
        c.shape(line([(x - 4, 28), (x + 4, 24)], 2), (240, 200, 130), flat=True, alpha=0.8)
    return c.image()


def xoi():
    c = Canvas(S, S)
    c.shape(poly([(6, 40), (32, 56), (58, 40), (32, 30)]), (60, 140, 70), puff=4, gloss=0.6)
    c.shape(ellipse(32, 38, 20, 11), (240, 210, 100), puff=6, rough=0.08)
    c.shape(ellipse(32, 34, 12, 6), (250, 236, 180), puff=4, rough=0.06)
    for x, y in ((24, 30), (36, 31), (30, 36)):
        c.shape(ellipse(x, y, 3, 1.6), (180, 110, 60), puff=1)
    return c.image()


def com():
    rnd = random.Random(2)
    c = Canvas(S, S)
    c.shape(ellipse(32, 42, 29, 13), (236, 238, 240), puff=5, gloss=1.0)
    c.shape(ellipse(22, 38, 13, 8), (250, 250, 246), puff=5, rough=0.06)
    c.shape(ellipse(42, 40, 10, 6), (170, 90, 50), puff=4, gloss=0.8)
    for _ in range(6):
        x = rnd.uniform(34, 52)
        c.shape(line([(x, 30), (x + 3, 40)], 1.6), (60, 140, 60), puff=0.8)
    return c.image()


def ao_mua():
    c = Canvas(S, S)
    coat = (70, 150, 230)
    c.shape(ellipse(32, 14, 9, 9), coat, puff=4, gloss=1.2, alpha=0.9)
    c.shape(poly([(22, 18), (42, 18), (58, 52), (32, 58), (6, 52)]), coat, puff=8, gloss=1.4, alpha=0.86)
    for x in (22, 32, 42):
        c.shape(line([(32 + (x - 32) * 0.4, 22), (x, 54)], 1.2), shade_rgb(coat, 0.7), flat=True, alpha=0.4)
    return c.image()


def voi_xang():
    """Cò bơm xăng đỏ với ống cao su đen."""
    c = Canvas(S, S)
    c.shape(line([(52, 60), (52, 36), (44, 26)], 5), (30, 30, 32), puff=2, gloss=0.4)
    c.shape(poly([(18, 18), (46, 22), (46, 34), (30, 34), (26, 46), (18, 46)]), (214, 40, 36), puff=6, gloss=1.0)
    c.shape(line([(18, 22), (4, 18)], 5), (190, 194, 200), puff=2, gloss=1.4)
    c.shape(rrect(28, 34, 34, 42, 2), (40, 40, 44), puff=1)
    return c.image()


def chai_xang():
    c = Canvas(S, S)
    c.shape(rrect(26, 4, 38, 14, 2), (200, 60, 50), puff=2, gloss=0.8)
    c.shape(poly([(26, 14), (38, 14), (38, 20), (46, 28), (46, 58), (18, 58), (18, 28), (26, 20)]), GLASS, puff=5, gloss=1.4, alpha=0.65)
    c.shape(poly([(19.5, 32), (44.5, 32), (44.5, 56.5), (19.5, 56.5)]), (236, 176, 60), puff=5, gloss=1.2, alpha=0.95)
    c.shape(rrect(22, 22, 25, 52, 1), (255, 255, 255), flat=True, alpha=0.4)
    return c.image()


def sam(patch=False):
    """Săm xe (ruột) cuộn tròn; [patch]: có miếng vá."""
    c = Canvas(S, S)
    c.shape(lambda d, s: d.ellipse([8 * s, 10 * s, 56 * s, 54 * s], outline=255, width=int(9 * s)), (40, 40, 44), puff=4, gloss=0.6)
    c.shape(rrect(46, 26, 52, 34, 1.5), (190, 194, 200), puff=1.5, gloss=1)
    if patch:
        c.shape(ellipse(19, 44, 7, 6), (220, 120, 40), puff=2, gloss=0.6)
        c.shape(ellipse(19, 44, 3.6, 3), (240, 170, 90), puff=1)
    return c.image()


def lop(new=False):
    c = Canvas(S, S)
    c.shape(ellipse(32, 32, 27, 27), (30, 30, 32), puff=6, gloss=0.4)
    for i in range(16):
        a = i * math.tau / 16
        c.shape(line([(32 + math.cos(a) * 21, 32 + math.sin(a) * 21), (32 + math.cos(a) * 26, 32 + math.sin(a) * 26)], 2.4),
                (56, 56, 60), flat=True)
    c.shape(ellipse(32, 32, 15, 15), (182, 186, 192), puff=4, gloss=1.4)
    c.shape(ellipse(32, 32, 5, 5), (110, 112, 118), puff=2, gloss=1)
    if new:
        c.shape(rrect(40, 4, 60, 14, 3), (40, 170, 90), puff=2, gloss=0.8)
    else:
        c.shape(line([(14, 14), (22, 20)], 3), (196, 200, 206), puff=1, gloss=1.2)
    return c.image()


def save(img, name):
    img.save(f'{OUT}/img_item_{name}.png', optimize=True)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    save(tra_da(), 'tra_da')
    save(nuoc_mia(), 'nuoc_mia')
    save(nuoc_mia(tac=True), 'nuoc_mia_tac')
    save(ca_phe(), 'ca_phe')
    save(ca_phe(milk=True), 'bac_xiu')
    save(huong_duong(), 'huong_duong')
    save(ghe_nhua(), 'ghe_nhua')
    save(vong(), 'vong')
    save(banh_mi(), 'banh_mi')
    save(xoi(), 'xoi')
    save(com(), 'com')
    save(ao_mua(), 'ao_mua')
    save(voi_xang(), 'voi_xang')
    save(chai_xang(), 'chai_xang')
    save(sam(patch=True), 'va_sam')
    save(sam(), 'thay_sam')
    save(lop(), 'va_lop')
    save(lop(new=True), 'thay_lop')
    print('done')
