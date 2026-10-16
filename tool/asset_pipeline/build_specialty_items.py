"""Icon món đặc sản các tỉnh cho bảng quán (cùng kiểu với
build_menu_items.py: nhìn nghiêng, đổ sáng theo khối).

Mỗi món dựng từ vài khối cơ bản có tham số: bát nước dùng (phở, bún bò, bánh
đa cua, mì Quảng…), đĩa (bánh cuốn, cơm tấm, bánh khọt…), gói lá (nem chua,
bánh gai, bánh tét), kẹo bánh (cu đơ, kẹo dừa, bánh pía…), trái cây, đồ uống.

Chạy từ thư mục gốc:
    .venv/bin/python tool/asset_pipeline/build_specialty_items.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_menu_items import S, ca_phe, glass, save  # noqa: E402
from build_vehicles import Canvas, ellipse, line, poly, rrect, shade_rgb  # noqa: E402

WHITE = (240, 240, 236)
GREEN = (70, 150, 70)
LEAF = (66, 132, 58)


def rnd(seed):
    return random.Random(seed)


# ------------------------------------------------------------ khối cơ bản
def bowl(c, rim=(236, 238, 240), band=(60, 110, 180)):
    """Bát sứ nhìn nghiêng: thân cong, chân bát, viền xanh."""
    c.shape(poly([(5, 33), (59, 33), (50, 53), (14, 53)]), rim, puff=6, gloss=1.0)
    c.shape(rrect(22, 52, 42, 57, 2), shade_rgb(rim, 0.9), puff=2, gloss=0.6)
    c.shape(poly([(8, 38), (56, 38), (55, 41), (9, 41)]), band, flat=True, alpha=0.75)


def broth(c, color, y=33, rx=26, ry=7):
    c.shape(ellipse(32, y, rx, ry), color, puff=3, gloss=1.2)


def noodles(c, color, seed, n=7, y=31, thick=1.6, span=20):
    r = rnd(seed)
    for _ in range(n):
        x = r.uniform(32 - span, 32 + span - 8)
        pts = [(x + k * 2.2, y + math.sin(k * 1.3 + x) * 1.6 + r.uniform(-1.5, 1.5)) for k in range(5)]
        c.shape(line(pts, thick), color, puff=0.8, gloss=0.6)


def toppings(c, items, seed):
    """[(màu, số miếng, rx, ry)] rải trên mặt bát / đĩa."""
    r = rnd(seed)
    for (col, n, rx, ry) in items:
        for _ in range(n):
            x, y = r.uniform(14, 50), r.uniform(26, 34)
            c.shape(ellipse(x, y, rx, ry), col, puff=2, gloss=0.6)


def herbs(c, seed, n=8, color=GREEN):
    r = rnd(seed)
    for _ in range(n):
        x, y = r.uniform(12, 52), r.uniform(25, 33)
        a = r.uniform(0, math.pi)
        c.shape(line([(x, y), (x + math.cos(a) * 4, y - math.sin(a) * 2.5)], 1.6), color, puff=0.6)


def chili(c, seed, n=4):
    r = rnd(seed)
    for _ in range(n):
        x, y = r.uniform(14, 50), r.uniform(27, 34)
        c.shape(ellipse(x, y, 1.6, 1.4), (220, 40, 30), puff=0.8, gloss=1.0)


def noodle_bowl(seed, soup, noodle, tops, herb=True, chilis=0, band=(60, 110, 180), extra=None):
    c = Canvas(S, S)
    bowl(c, band=band)
    broth(c, soup)
    noodles(c, noodle, seed)
    toppings(c, tops, seed + 1)
    if herb:
        herbs(c, seed + 2)
    if chilis:
        chili(c, seed + 3, chilis)
    if extra:
        extra(c)
    return c.image()


def plate(c, y=46, rx=29, ry=10, color=(238, 240, 242)):
    c.shape(ellipse(32, y, rx, ry), color, puff=5, gloss=1.0)
    c.shape(ellipse(32, y - 1.5, rx - 6, ry - 3.5), shade_rgb(color, 0.97), puff=2)


def dip(c, x=50, y=40, sauce=(200, 120, 60)):
    c.shape(ellipse(x, y, 8, 5), WHITE, puff=3, gloss=1.0)
    c.shape(ellipse(x, y - 1.5, 6, 2.6), sauce, puff=1.5, gloss=1.2)


def lettuce(c, x, y, seed, n=3):
    r = rnd(seed)
    for _ in range(n):
        c.shape(ellipse(x + r.uniform(-4, 4), y + r.uniform(-2, 2), 6, 3.5), (110, 180, 80), puff=3, rough=0.05)


# ----------------------------------------------------------------- bát
def pho():
    return noodle_bowl(1, (210, 160, 96), (246, 244, 236), [((150, 80, 70), 4, 4.5, 2.2)], extra=lambda c: c.shape(
        ellipse(46, 30, 3, 2), (240, 230, 160), puff=1))


def bun_bo():
    return noodle_bowl(2, (214, 92, 40), (244, 240, 230), [((150, 76, 60), 3, 4.5, 2.4), ((236, 200, 170), 1, 5, 3)], chilis=3)


def bun_ca():
    return noodle_bowl(3, (232, 188, 70), (246, 244, 236), [((236, 214, 170), 4, 3.6, 2.2)], chilis=2)


def bun_cha():
    def extra(c):
        for (x, y) in ((24, 30), (34, 31), (42, 29)):
            c.shape(ellipse(x, y, 4.5, 3), (110, 60, 36), puff=2.5, gloss=0.6, rough=0.06)
        for (x, y) in ((18, 32), (47, 32)):
            c.shape(ellipse(x, y, 3, 1.6), (240, 160, 60), puff=1)
    c = Canvas(S, S)
    bowl(c, band=(140, 60, 40))
    broth(c, (214, 160, 100))
    extra(c)
    herbs(c, 4, n=4)
    return c.image()


def banh_da_cua():
    return noodle_bowl(5, (196, 116, 64), (150, 66, 40), [((170, 110, 60), 5, 3.4, 2.4), ((214, 200, 170), 2, 3.6, 2)],
                       band=(150, 40, 40))


def mi_quang():
    def extra(c):
        c.shape(ellipse(46, 25, 9, 5), (226, 196, 140), puff=2, gloss=0.4)
        r = rnd(9)
        for _ in range(8):
            c.shape(ellipse(r.uniform(40, 53), r.uniform(23, 27), 0.6, 0.6), (40, 30, 26), flat=True)
        for (x, y) in ((20, 31), (28, 29)):
            c.shape(ellipse(x, y, 3.8, 2.2), (240, 120, 70), puff=1.5, gloss=0.8)
        r = rnd(10)
        for _ in range(7):
            c.shape(ellipse(r.uniform(14, 40), r.uniform(29, 34), 1.2, 1), (200, 150, 90), puff=0.6)
    return noodle_bowl(6, (220, 150, 60), (240, 204, 80), [], extra=extra)


def cao_lau():
    return noodle_bowl(7, (180, 120, 60), (214, 164, 70), [((170, 70, 50), 4, 4.5, 2.2), ((236, 210, 160), 3, 2, 1.6)])


def hu_tieu():
    return noodle_bowl(8, (228, 200, 140), (248, 246, 240), [((240, 120, 80), 3, 3.6, 2.0), ((120, 60, 50), 2, 3, 1.8)])


def bun_nuoc_leo():
    return noodle_bowl(9, (190, 160, 90), (246, 244, 236), [((220, 200, 160), 3, 4, 2.2), ((180, 90, 50), 2, 3.6, 2)])


def banh_canh():
    return noodle_bowl(10, (222, 186, 130), (240, 236, 220), [((236, 210, 160), 4, 3.8, 2.2)])


def chao(color=(238, 226, 196), tops=None, seed=11, chilis=0):
    c = Canvas(S, S)
    bowl(c)
    broth(c, color, ry=7.5)
    toppings(c, tops or [((200, 150, 70), 2, 7, 1.6)], seed)
    herbs(c, seed + 1, n=6)
    if chilis:
        chili(c, seed + 2, chilis)
    return c.image()


def chao_luon():
    return chao((232, 196, 110), [((110, 70, 40), 5, 4.5, 1.4)], seed=12, chilis=3)


def chao_canh():
    return noodle_bowl(13, (214, 140, 70), (236, 228, 210), [((236, 214, 170), 3, 4, 2.4)], chilis=2)


def thang_co():
    return noodle_bowl(14, (120, 70, 40), (120, 70, 40), [((150, 90, 60), 5, 4, 2.6), ((90, 50, 40), 3, 3, 2)], chilis=3,
                       band=(40, 40, 44))


def banh_cuon_canh():
    def extra(c):
        for (x, y) in ((22, 31), (32, 29), (42, 31)):
            c.shape(rrect(x - 6, y - 2.5, x + 6, y + 2.5, 2.5), (246, 244, 236), puff=2, gloss=0.8, alpha=0.95)
        c.shape(ellipse(28, 33, 4, 2.4), (250, 210, 80), puff=1.5, gloss=0.8)
    return noodle_bowl(15, (226, 200, 150), (246, 244, 236), [], extra=extra, herb=True)


def pho_kho():
    c = Canvas(S, S)
    bowl(c, band=(160, 50, 40))
    broth(c, (130, 80, 50))
    noodles(c, (230, 220, 200), 16, n=9)
    toppings(c, [((150, 80, 60), 3, 3.6, 2)], 17)
    herbs(c, 18, n=5)
    c.shape(ellipse(52, 46, 9, 6), WHITE, puff=3, gloss=1.0)
    c.shape(ellipse(52, 44, 7, 2.8), (210, 170, 110), puff=1.5, gloss=1.2)
    return c.image()


# ---------------------------------------------------------------- đĩa
def mien():
    c = Canvas(S, S)
    plate(c)
    noodles(c, (214, 190, 150), 20, n=14, y=40, thick=1.4)
    toppings(c, [((70, 50, 40), 4, 2.6, 1.6), ((190, 110, 60), 3, 3, 1.6)], 21)
    herbs(c, 22, n=5)
    return c.image()


def mi_xao():
    c = Canvas(S, S)
    plate(c)
    noodles(c, (238, 220, 170), 23, n=14, y=40, thick=1.6)
    toppings(c, [((140, 70, 50), 4, 4, 2), ((80, 150, 60), 4, 4, 1.8)], 24)
    return c.image()


def banh_tam_bi():
    c = Canvas(S, S)
    plate(c)
    noodles(c, (246, 244, 236), 25, n=14, y=40, thick=2.2)
    r = rnd(26)
    for _ in range(10):
        x, y = r.uniform(18, 46), r.uniform(36, 42)
        c.shape(line([(x, y), (x + 4, y - 1)], 1.0), (230, 200, 150), puff=0.5)
    c.shape(ellipse(32, 38, 10, 3), (250, 250, 244), puff=2, alpha=0.8)
    herbs(c, 27, n=5)
    return c.image()


def banh_cuon():
    c = Canvas(S, S)
    plate(c)
    for (x, y) in ((22, 42), (30, 39), (38, 42)):
        c.shape(rrect(x - 7, y - 4, x + 7, y + 4, 4), (246, 244, 238), puff=4, gloss=0.9, alpha=0.95)
    r = rnd(28)
    for _ in range(14):
        c.shape(ellipse(r.uniform(16, 44), r.uniform(36, 42), 0.9, 0.8), (150, 90, 40), puff=0.5)
    c.shape(ellipse(44, 38, 5, 2.4), (220, 200, 160), puff=2)
    dip(c, 52, 34, (210, 150, 80))
    return c.image()


def com_tam():
    c = Canvas(S, S)
    plate(c)
    c.shape(ellipse(24, 40, 12, 7), (250, 250, 246), puff=5, rough=0.05)
    c.shape(ellipse(40, 41, 10, 4.5), (120, 56, 30), puff=3, gloss=0.8, rough=0.05)
    c.shape(ellipse(40, 34, 6, 4), (250, 248, 240), puff=2, gloss=0.6)
    c.shape(ellipse(40, 34, 3, 2.4), (250, 190, 50), puff=1.5, gloss=1.0)
    c.shape(ellipse(50, 44, 4, 2.4), (130, 190, 90), puff=1.5)
    herbs(c, 29, n=4)
    return c.image()


def round_cakes(color, top, seed, tray=None):
    c = Canvas(S, S)
    if tray:
        c.shape(ellipse(32, 46, 29, 10), tray, puff=4, gloss=0.4)
    else:
        plate(c)
    for row, y in enumerate((44, 38)):
        for k in range(4 - row):
            x = 15 + k * 11 + row * 5.5
            c.shape(ellipse(x, y, 5.2, 3.4), color, puff=3, gloss=0.8)
            if top:
                c.shape(ellipse(x, y - 1, 2.6, 1.6), top, puff=1.5, gloss=0.8)
    herbs(c, seed, n=4)
    return c.image()


def banh_khot():
    return round_cakes((230, 170, 60), (240, 110, 70), 30)


def banh_can():
    return round_cakes((236, 226, 200), (250, 196, 60), 31, tray=(150, 90, 60))


def banh_beo():
    c = Canvas(S, S)
    for (x, y) in ((16, 44), (30, 46), (44, 44), (23, 36), (38, 36), (52, 37)):
        c.shape(ellipse(x, y, 7, 3.6), WHITE, puff=3, gloss=1.0)
        c.shape(ellipse(x, y - 1, 5, 2.2), (240, 236, 220), puff=1.5)
        c.shape(ellipse(x, y - 1.4, 2.4, 1.2), (236, 110, 60), puff=1)
    return c.image()


def cuon():
    c = Canvas(S, S)
    plate(c)
    for (x, y) in ((20, 42), (30, 39), (40, 42)):
        c.shape(rrect(x - 6, y - 4, x + 6, y + 4, 4), (250, 248, 240), puff=3, gloss=1.2, alpha=0.75)
        c.shape(rrect(x - 4, y - 2, x + 4, y + 2, 2), (230, 150, 140), puff=1, alpha=0.6)
        c.shape(rrect(x - 4, y - 0.5, x + 4, y + 2.4, 2), (100, 170, 80), puff=1, alpha=0.6)
    dip(c, 52, 36, (160, 110, 70))
    return c.image()


def nem_nuong():
    c = Canvas(S, S)
    plate(c)
    for k in range(3):
        y = 36 + k * 4
        c.shape(line([(10, y + 2), (52, y - 2)], 1.0), (200, 170, 120), flat=True)
        for j in range(4):
            x = 16 + j * 9
            c.shape(ellipse(x, y + 1.5 - j * 0.4, 3.6, 2.6), (170, 70, 46), puff=2, gloss=0.7, rough=0.06)
    dip(c, 52, 46, (220, 150, 90))
    return c.image()


def goi_la():
    c = Canvas(S, S)
    plate(c)
    r = rnd(32)
    greens = [(70, 140, 60), (110, 170, 70), (60, 110, 50), (140, 180, 80), (90, 120, 60)]
    for k in range(10):
        x, y = r.uniform(12, 50), r.uniform(34, 44)
        c.shape(ellipse(x, y, r.uniform(4, 6), r.uniform(2.2, 3.4)), greens[k % 5], puff=2, rough=0.05)
    for (x, y) in ((24, 36), (38, 37)):
        c.shape(ellipse(x, y, 3.6, 2), (240, 130, 90), puff=1.5, gloss=0.8)
    return c.image()


def patties(color, shape='round', seed=33, dark=None):
    c = Canvas(S, S)
    plate(c)
    pts = ((20, 44), (32, 46), (44, 44), (26, 38), (38, 38))
    for (x, y) in pts:
        if shape == 'round':
            c.shape(ellipse(x, y, 6, 3.6), color, puff=3, gloss=0.6, rough=0.08)
        else:
            c.shape(rrect(x - 5, y - 3.5, x + 5, y + 3.5, 1), color, puff=3, gloss=0.6, rough=0.08)
        if dark:
            c.shape(ellipse(x - 1, y - 1, 2.6, 1.2), dark, puff=1, alpha=0.6)
    lettuce(c, 50, 38, seed, 2)
    return c.image()


def cha_muc():
    return patties((214, 160, 70), 'round', 34, dark=(170, 110, 40))


def nem_cua_be():
    return patties((214, 140, 50), 'square', 35, dark=(160, 90, 30))


def be_chao():
    return patties((150, 80, 44), 'round', 36, dark=(110, 50, 30))


def com_chay():
    c = Canvas(S, S)
    plate(c)
    for (x, y) in ((20, 42), (34, 44), (28, 37), (42, 38)):
        c.shape(rrect(x - 7, y - 4, x + 7, y + 4, 2), (230, 180, 90), puff=3, gloss=0.4, rough=0.12)
    c.shape(ellipse(32, 38, 12, 4), (150, 80, 40), puff=2, gloss=1.0, alpha=0.85)
    herbs(c, 37, n=4)
    return c.image()


def vit_quay():
    c = Canvas(S, S)
    plate(c)
    c.shape(ellipse(30, 38, 16, 8), (150, 60, 30), puff=6, gloss=1.4)
    c.shape(ellipse(44, 35, 6, 4), (130, 50, 26), puff=3, gloss=1.2)
    c.shape(ellipse(26, 35, 8, 3), (190, 90, 40), puff=2, gloss=1.4, alpha=0.6)
    lettuce(c, 50, 44, 38, 2)
    return c.image()


def ca_kho():
    c = Canvas(S, S)
    c.shape(poly([(10, 30), (54, 30), (50, 54), (14, 54)]), (70, 46, 34), puff=6, gloss=0.5, rough=0.05)
    c.shape(ellipse(32, 30, 23, 6), (90, 60, 44), puff=2)
    c.shape(ellipse(32, 30, 20, 4.6), (120, 60, 30), puff=2, gloss=1.4)
    for (x, y) in ((24, 29), (36, 30), (44, 29)):
        c.shape(rrect(x - 5, y - 2.4, x + 5, y + 2.4, 2), (90, 40, 22), puff=2, gloss=1.2)
    chili(c, 39, 3)
    for k in range(3):
        c.shape(line([(20 + k * 8, 24), (22 + k * 8, 18)], 1.2), (230, 230, 230), flat=True, alpha=0.3)
    return c.image()


def ca_thinh():
    c = Canvas(S, S)
    plate(c)
    for (x, y) in ((22, 42), (34, 44), (28, 37), (40, 38)):
        c.shape(ellipse(x, y, 7, 3.4), (214, 190, 140), puff=3, rough=0.15)
    lettuce(c, 48, 44, 40, 2)
    dip(c, 52, 36, (200, 60, 40))
    return c.image()


def cua():
    c = Canvas(S, S)
    plate(c)
    red = (214, 70, 40)
    for side in (-1, 1):
        for k in range(3):
            c.shape(line([(32 + side * 10, 40 + k * 2), (32 + side * 20, 44 + k * 3)], 2), red, puff=1, gloss=0.6)
        c.shape(ellipse(32 + side * 17, 32, 5, 3.6), red, puff=2.5, gloss=1.0)
        c.shape(line([(32 + side * 8, 37), (32 + side * 14, 33)], 2.4), red, puff=1)
    c.shape(ellipse(32, 39, 13, 7.5), red, puff=5, gloss=1.2)
    for x in (28, 36):
        c.shape(ellipse(x, 33, 1.2, 1.2), (30, 20, 20), flat=True)
    return c.image()


def muc_nuong():
    c = Canvas(S, S)
    plate(c)
    for (x, y, a) in ((24, 41, 0.2), (38, 41, -0.2)):
        c.shape(ellipse(x, y, 9, 4), (236, 210, 170), puff=3, gloss=0.6)
        for k in range(4):
            c.shape(line([(x - 6 + k * 3.5, y - 3), (x - 5 + k * 3.5, y + 3)], 0.9), (150, 80, 40), flat=True, alpha=0.7)
    dip(c, 52, 34, (210, 60, 40))
    return c.image()


def banh_trang():
    c = Canvas(S, S)
    for k in range(4):
        c.shape(ellipse(28, 44 - k * 2.2, 22, 8), (238, 232, 214), puff=3, gloss=0.6, rough=0.04)
    c.shape(ellipse(28, 36, 20, 6), (244, 238, 222), puff=2)
    r = rnd(41)
    for _ in range(30):
        c.shape(ellipse(r.uniform(12, 44), r.uniform(33, 39), 1.4, 0.5), (220, 210, 190), flat=True, alpha=0.6)
    c.shape(ellipse(50, 30, 8, 3), (240, 200, 190), puff=2)
    c.shape(ellipse(50, 30, 5.5, 1.4), (200, 120, 110), puff=1)
    lettuce(c, 50, 40, 42, 2)
    return c.image()


def banh_trang_nuong():
    c = Canvas(S, S)
    plate(c)
    c.shape(poly([(10, 44), (54, 44), (32, 30)]), (226, 170, 80), puff=4, gloss=0.4, rough=0.1)
    r = rnd(43)
    for _ in range(9):
        c.shape(ellipse(r.uniform(20, 44), r.uniform(37, 42), 2, 1.2), (250, 200, 60), puff=1)
        c.shape(ellipse(r.uniform(20, 44), r.uniform(37, 42), 1.2, 0.8), (90, 160, 60), puff=0.6)
    return c.image()


def thit_gac_bep():
    c = Canvas(S, S)
    plate(c)
    r = rnd(44)
    for k in range(7):
        x = 14 + k * 5
        c.shape(rrect(x, 34 + r.uniform(-1, 2), x + 4, 46, 1.5), (120, 44, 30), puff=2, gloss=0.6, rough=0.1)
    dip(c, 52, 36, (200, 120, 60))
    return c.image()


def lap_xuong():
    c = Canvas(S, S)
    plate(c)
    for k in range(3):
        y = 37 + k * 4
        c.shape(rrect(12, y - 2.6, 48, y + 2.6, 2.6), (180, 50, 40), puff=2.5, gloss=1.4)
        for j in range(6):
            c.shape(ellipse(16 + j * 6, y, 0.9, 0.9), (240, 200, 190), flat=True, alpha=0.7)
    return c.image()


def tam_giac_mach():
    c = Canvas(S, S)
    plate(c)
    for k in range(3):
        c.shape(ellipse(30, 44 - k * 4, 16, 5), (130, 90, 110), puff=3, gloss=0.4, rough=0.08)
    c.shape(ellipse(30, 35, 14, 4), (150, 104, 120), puff=2)
    for (x, y) in ((24, 34), (34, 35)):
        c.shape(ellipse(x, y, 1.6, 1.2), (240, 160, 190), puff=1)
    c.shape(ellipse(50, 42, 6, 3), (230, 170, 60), puff=2, gloss=1.2)
    return c.image()


# ------------------------------------------------------------ gói, kẹo
def parcels(leaf, string=(214, 40, 40), inner=None, n=3, seed=50, tall=False):
    c = Canvas(S, S)
    plate(c, color=(230, 226, 214))
    spots = ((20, 40), (40, 40), (30, 32)) if n == 3 else ((30, 38),)
    for (x, y) in spots:
        hw = 9 if not tall else 8
        hh = 7 if not tall else 9
        c.shape(rrect(x - hw, y - hh, x + hw, y + hh, 2), leaf, puff=4, gloss=0.6, rough=0.05)
        for k in range(3):
            c.shape(line([(x - hw + 2 + k * 6, y - hh), (x - hw + 3 + k * 6, y + hh)], 0.8), shade_rgb(leaf, 0.8), flat=True,
                    alpha=0.6)
        c.shape(line([(x - hw, y), (x + hw, y)], 1.2), string, puff=0.6)
        c.shape(line([(x, y - hh), (x, y + hh)], 1.2), string, puff=0.6)
    if inner:
        c.shape(rrect(44, 44, 56, 52, 2), inner, puff=2, gloss=0.6)
    return c.image()


def nem_chua():
    return parcels(LEAF, inner=(230, 120, 110))


def banh_gai():
    return parcels((40, 34, 30), string=(200, 170, 110), inner=(30, 26, 24))


def banh_phu_the():
    return parcels((120, 190, 110), string=(214, 40, 40), inner=(150, 210, 140))


def tet_roll(rice):
    c = Canvas(S, S)
    plate(c, color=(230, 226, 214))
    c.shape(rrect(8, 28, 44, 46, 9), LEAF, puff=5, gloss=0.5, rough=0.05)
    for x in (16, 26, 36):
        c.shape(line([(x, 28), (x, 46)], 1.4), (200, 180, 120), puff=0.6)
    c.shape(ellipse(48, 38, 9, 9), LEAF, puff=3)
    c.shape(ellipse(48, 38, 7.6, 7.6), rice, puff=3, gloss=0.3)
    c.shape(ellipse(48, 38, 4, 4), (230, 190, 70), puff=2)
    c.shape(ellipse(48, 38, 1.8, 1.8), (210, 90, 50), puff=1)
    return c.image()


def banh_tet():
    return tet_roll((246, 244, 236))


def banh_tet_cam():
    return tet_roll((120, 60, 120))


def com_vong():
    c = Canvas(S, S)
    c.shape(poly([(4, 40), (32, 56), (60, 40), (32, 28)]), (70, 130, 80), puff=4, gloss=0.5)
    r = rnd(51)
    c.shape(ellipse(32, 38, 18, 8), (150, 196, 90), puff=5, rough=0.1)
    for _ in range(40):
        c.shape(ellipse(r.uniform(18, 46), r.uniform(33, 42), 1.2, 0.7), (120, 170, 70), flat=True, alpha=0.7)
    c.shape(line([(20, 50), (44, 50)], 1), (200, 60, 50), flat=True)
    return c.image()


def com_lam():
    c = Canvas(S, S)
    plate(c)
    for k, (x, y) in enumerate(((14, 42), (20, 36))):
        c.shape(rrect(x, y - 4, x + 34, y + 4, 4), (120, 150, 70) if k else (140, 160, 80), puff=3, gloss=0.6)
        for j in range(3):
            c.shape(line([(x + 8 + j * 10, y - 4), (x + 8 + j * 10, y + 4)], 1.2), (90, 110, 50), flat=True)
        c.shape(ellipse(x + 34, y, 3, 4), (246, 244, 236), puff=1.5)
    return c.image()


def candy_bars(color, wrap=None, seed=52, sandwich=None, dots=None):
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    r = rnd(seed)
    for k, (x, y) in enumerate(((14, 40), (28, 42), (42, 40), (21, 33), (35, 33))):
        if sandwich:
            c.shape(rrect(x - 1, y - 4.5, x + 13, y + 4.5, 1), sandwich, puff=1.5, alpha=0.9)
        c.shape(rrect(x, y - 3.5, x + 12, y + 3.5, 1.2), color, puff=2.5, gloss=1.0)
        if wrap:
            c.shape(rrect(x + 3, y - 3.6, x + 9, y + 3.6, 0.5), wrap, flat=True, alpha=0.85)
        if dots:
            for _ in range(5):
                c.shape(ellipse(x + r.uniform(1, 11), y + r.uniform(-2.5, 2.5), 0.9, 0.7), dots, flat=True)
    return c.image()


def cu_do():
    return candy_bars((150, 80, 40), sandwich=(246, 238, 220), dots=(230, 210, 170))


def keo_dua():
    return candy_bars((236, 226, 200), wrap=(60, 140, 90))


def keo_lac():
    return candy_bars((196, 130, 60), dots=(236, 200, 150))


def me_xung():
    return candy_bars((170, 100, 50), wrap=(220, 50, 40), dots=(240, 230, 210))


def banh_dau_xanh():
    c = Canvas(S, S)
    c.shape(rrect(8, 30, 56, 54, 3), (200, 40, 40), puff=4, gloss=0.6)
    c.shape(rrect(10, 26, 54, 32, 2), (230, 190, 70), puff=2, gloss=0.8)
    for k in range(3):
        for j in range(2):
            x, y = 15 + k * 13, 34 + j * 9
            c.shape(rrect(x, y, x + 10, y + 7, 1), (200, 200, 206), puff=1.5, gloss=1.4)
            c.shape(rrect(x + 1.5, y + 1, x + 8.5, y + 6, 1), (240, 210, 110), puff=1.5)
    return c.image()


def banh_pia():
    c = Canvas(S, S)
    plate(c)
    c.shape(ellipse(26, 40, 14, 7), (236, 206, 150), puff=5, gloss=0.6, rough=0.06)
    c.shape(ellipse(26, 37, 4, 2), (200, 50, 50), flat=True, alpha=0.8)
    c.shape(poly([(38, 44), (54, 44), (52, 34), (40, 34)]), (240, 214, 160), puff=3, rough=0.06)
    c.shape(ellipse(46, 40, 5, 3.4), (240, 200, 90), puff=2)
    c.shape(ellipse(46, 40, 2.4, 1.8), (230, 140, 40), puff=1)
    return c.image()


def banh_cay():
    c = Canvas(S, S)
    plate(c)
    cols = [(214, 60, 50), (236, 200, 90), (90, 160, 80), (246, 240, 228), (214, 60, 50)]
    for k, col in enumerate(cols):
        x = 12 + k * 8
        c.shape(rrect(x, 34, x + 7, 46, 1), col, puff=2, gloss=0.6, rough=0.08)
    return c.image()


def banh_da():
    c = Canvas(S, S)
    c.shape(ellipse(32, 38, 26, 13), (226, 196, 140), puff=6, gloss=0.4, rough=0.06)
    r = rnd(53)
    for _ in range(50):
        c.shape(ellipse(r.uniform(12, 52), r.uniform(30, 46), 0.9, 0.6), (40, 34, 30), flat=True, alpha=0.8)
    for _ in range(8):
        c.shape(ellipse(r.uniform(14, 50), r.uniform(30, 46), 2.4, 1.4), (200, 150, 90), flat=True, alpha=0.4)
    return c.image()


def thot_not():
    c = Canvas(S, S)
    plate(c)
    for (x, y) in ((20, 42), (32, 44), (44, 42), (26, 36), (38, 36)):
        c.shape(ellipse(x, y, 6, 3.6), (196, 140, 60), puff=3, gloss=0.8)
        c.shape(ellipse(x, y - 1.6, 4, 1.6), (220, 170, 80), puff=1)
    return c.image()


def nuts(color, shape='round', seed=54, cone=None):
    c = Canvas(S, S)
    if cone:
        c.shape(poly([(12, 30), (52, 30), (32, 58)]), cone, puff=4, gloss=0.4)
    else:
        bowl(c, rim=(150, 100, 60), band=(120, 80, 50))
    r = rnd(seed)
    for _ in range(16):
        x, y = r.uniform(16, 48), r.uniform(22, 32)
        if shape == 'round':
            c.shape(ellipse(x, y, 4, 3.2), color, puff=2, gloss=1.4)
        else:
            a = r.uniform(0, math.pi)
            c.shape(line([(x - math.cos(a) * 3, y - math.sin(a) * 2), (x, y + 1.5), (x + math.cos(a) * 3, y - math.sin(a) * 2)], 2.8),
                    color, puff=1.5, gloss=0.6)
    return c.image()


def hat_de():
    return nuts((110, 60, 36), 'round', 55, cone=(200, 180, 140))


def hat_dieu():
    return nuts((236, 210, 160), 'curve', 56)


def che_long_nhan():
    c = Canvas(S, S)
    glass(c, (236, 220, 170), rnd=random.Random(57), ice=0)
    r = rnd(58)
    for _ in range(7):
        x, y = r.uniform(20, 42), r.uniform(28, 52)
        c.shape(ellipse(x, y, 3, 3), (250, 246, 236) if r.random() < 0.5 else (230, 200, 140), puff=1.5, gloss=1.0, alpha=0.9)
    return c.image()


# -------------------------------------------------------------- trái cây
def fruit(color, r_=14, seed=60, shade=None, cut=None, cut_in=None):
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    c.shape(ellipse(26, 36, r_, r_ * 0.95), color, puff=8, gloss=0.9, rough=0.04)
    c.shape(ellipse(26, 36 - r_ * 0.95, 2, 2), (90, 110, 50), puff=1)
    if cut:
        c.shape(ellipse(46, 42, 10, 6), cut, puff=3)
        if cut_in:
            c.shape(ellipse(46, 41, 7, 4), cut_in, puff=2, gloss=0.6)
    return c.image()


def buoi():
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    c.shape(ellipse(26, 34, 16, 15), (170, 196, 70), puff=8, gloss=0.8, rough=0.04)
    c.shape(ellipse(26, 19, 2.4, 2), (90, 110, 50), puff=1)
    for k in range(3):
        x = 42 + k * 5
        c.shape(poly([(x - 4, 46), (x + 4, 46), (x, 36)]), (240, 150, 140), puff=2.5, gloss=1.0)
    return c.image()


def cam():
    return fruit((170, 170, 50), 13, 61, cut=(240, 160, 40), cut_in=(250, 190, 70))


def thanh_long():
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    c.shape(ellipse(24, 36, 13, 11), (220, 50, 110), puff=7, gloss=1.0)
    for (x, y, a) in ((14, 30, -0.8), (24, 25, -1.6), (33, 30, -2.4), (18, 40, -0.4), (30, 41, -2.7)):
        c.shape(line([(x, y), (x + math.cos(a) * 5, y + math.sin(a) * 5)], 2.2), (110, 170, 60), puff=1)
    c.shape(ellipse(46, 42, 10, 7), (220, 50, 110), puff=3)
    c.shape(ellipse(46, 41, 8.4, 5.6), (246, 244, 236), puff=2)
    r = rnd(62)
    for _ in range(20):
        c.shape(ellipse(r.uniform(40, 52), r.uniform(37, 45), 0.5, 0.5), (20, 20, 20), flat=True)
    return c.image()


def nho():
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    r = rnd(63)
    for row in range(5):
        for k in range(5 - row):
            x = 20 + k * 6 + row * 3 + r.uniform(-1, 1)
            y = 26 + row * 5
            c.shape(ellipse(x, y, 3.6, 3.6), (120, 50, 110) if (k + row) % 3 else (150, 180, 70), puff=2, gloss=1.4)
    c.shape(line([(32, 22), (34, 14)], 1.6), (100, 80, 40), puff=0.6)
    return c.image()


def khom():
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    for k in range(5):
        a = -math.pi / 2 + (k - 2) * 0.35
        c.shape(line([(24, 24), (24 + math.cos(a) * 12, 24 + math.sin(a) * 12)], 3), (60, 130, 60), puff=1.5)
    c.shape(ellipse(24, 38, 11, 14), (220, 170, 50), puff=7, gloss=0.6)
    for k in range(5):
        c.shape(line([(15, 30 + k * 4), (33, 34 + k * 4)], 0.8), (150, 100, 30), flat=True, alpha=0.6)
    c.shape(ellipse(46, 44, 9, 5), (250, 220, 80), puff=3, gloss=0.8)
    return c.image()


def dua():
    c = Canvas(S, S)
    c.shape(line([(38, 6), (34, 28)], 3), (230, 60, 60), puff=1, gloss=0.6)
    c.shape(ellipse(32, 38, 17, 18), (110, 170, 70), puff=8, gloss=0.9)
    c.shape(ellipse(32, 24, 9, 4), (240, 236, 210), puff=2)
    c.shape(ellipse(32, 24, 5, 2), (220, 220, 200), puff=1)
    return c.image()


# ------------------------------------------------------------ đồ uống
def che_xanh():
    c = Canvas(S, S)
    # ấm tích + chén chè xanh
    c.shape(ellipse(22, 40, 14, 12), (226, 228, 222), puff=6, gloss=1.2)
    c.shape(line([(8, 38), (2, 30)], 3), (226, 228, 222), puff=1.5, gloss=1)
    c.shape(rrect(17, 26, 27, 30, 2), (210, 212, 206), puff=2, gloss=1)
    c.shape(line([(14, 30), (22, 22), (30, 30)], 1.6), (120, 90, 60), puff=0.6)
    c.shape(poly([(38, 40), (58, 40), (54, 52), (42, 52)]), (240, 240, 236), puff=4, gloss=1.2)
    c.shape(ellipse(48, 40, 10, 3), (170, 190, 60), puff=1.5, gloss=1.4)
    return c.image()


def ca_phe_phin():
    return ca_phe()


def sua():
    c = Canvas(S, S)
    c.shape(rrect(14, 10, 30, 16, 2), (40, 110, 200), puff=2, gloss=1.0)
    c.shape(poly([(14, 16), (30, 16), (32, 24), (32, 56), (12, 56), (12, 24)]), (246, 246, 240), puff=5, gloss=1.2)
    c.shape(rrect(12, 32, 32, 44, 1), (60, 140, 90), flat=True, alpha=0.8)
    glass(c, (248, 246, 236), rnd=random.Random(64), ice=0, tall=True)
    return c.image()


def chuoi():
    """Nải chuối ngự quả nhỏ vàng ươm, cuống xanh."""
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    for k in range(5):
        y = 28 + k * 3.6
        col = (236, 196 + k * 4, 60)
        c.shape(line([(16, y - 2), (32, y + 4), (50, y - 4)], 5.2), col, puff=2.5, gloss=0.9)
        c.shape(ellipse(50.5, y - 4.5, 1.4, 1.4), (90, 70, 40), flat=True)
    c.shape(rrect(10, 24, 17, 44, 3), (130, 150, 70), puff=2, gloss=0.4)
    return c.image()


def khoai_deo():
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    r = rnd(70)
    for k in range(7):
        x = 12 + k * 6
        c.shape(rrect(x, 32 + r.uniform(-2, 2), x + 5, 46, 2), (214, 120, 60), puff=2, gloss=1.0, rough=0.06)
    return c.image()


def vu_sua():
    c = Canvas(S, S)
    plate(c, color=(232, 228, 216))
    c.shape(ellipse(26, 36, 13, 12.5), (110, 160, 90), puff=8, gloss=1.2)
    c.shape(ellipse(26, 23.5, 2, 2), (90, 70, 40), puff=1)
    c.shape(ellipse(46, 42, 9, 6), (150, 120, 160), puff=3)
    c.shape(ellipse(46, 41, 7, 4.4), (246, 240, 236), puff=2, gloss=0.6)
    c.shape(ellipse(46, 41, 2, 1.6), (120, 80, 60), puff=1)
    return c.image()


ICONS = {
    'ds_chuoi': chuoi, 'ds_khoai_deo': khoai_deo, 'ds_vu_sua': vu_sua,
    'ds_pho': pho, 'ds_bun_bo': bun_bo, 'ds_bun_ca': bun_ca, 'ds_bun_cha': bun_cha, 'ds_banh_da_cua': banh_da_cua,
    'ds_mi_quang': mi_quang, 'ds_cao_lau': cao_lau, 'ds_hu_tieu': hu_tieu, 'ds_bun_nuoc_leo': bun_nuoc_leo,
    'ds_banh_canh': banh_canh, 'ds_chao': chao, 'ds_chao_luon': chao_luon, 'ds_chao_canh': chao_canh, 'ds_thang_co': thang_co,
    'ds_banh_cuon_canh': banh_cuon_canh, 'ds_pho_kho': pho_kho, 'ds_mien': mien, 'ds_mi_xao': mi_xao,
    'ds_banh_tam_bi': banh_tam_bi, 'ds_banh_cuon': banh_cuon, 'ds_com_tam': com_tam, 'ds_banh_khot': banh_khot,
    'ds_banh_can': banh_can, 'ds_banh_beo': banh_beo, 'ds_cuon': cuon, 'ds_nem_nuong': nem_nuong, 'ds_goi_la': goi_la,
    'ds_cha_muc': cha_muc, 'ds_nem_cua_be': nem_cua_be, 'ds_be_chao': be_chao, 'ds_com_chay': com_chay,
    'ds_vit_quay': vit_quay, 'ds_ca_kho': ca_kho, 'ds_ca_thinh': ca_thinh, 'ds_cua': cua, 'ds_muc_nuong': muc_nuong,
    'ds_banh_trang': banh_trang, 'ds_banh_trang_nuong': banh_trang_nuong, 'ds_thit_gac_bep': thit_gac_bep,
    'ds_lap_xuong': lap_xuong, 'ds_banh_tam_giac_mach': tam_giac_mach, 'ds_nem_chua': nem_chua, 'ds_banh_gai': banh_gai,
    'ds_banh_phu_the': banh_phu_the, 'ds_banh_tet': banh_tet, 'ds_banh_tet_cam': banh_tet_cam, 'ds_com_vong': com_vong,
    'ds_com_lam': com_lam, 'ds_cu_do': cu_do, 'ds_keo_dua': keo_dua, 'ds_keo_lac': keo_lac, 'ds_me_xung': me_xung,
    'ds_banh_dau_xanh': banh_dau_xanh, 'ds_banh_pia': banh_pia, 'ds_banh_cay': banh_cay, 'ds_banh_da': banh_da,
    'ds_thot_not': thot_not, 'ds_hat_de': hat_de, 'ds_hat_dieu': hat_dieu, 'ds_che_long_nhan': che_long_nhan,
    'ds_buoi': buoi, 'ds_cam': cam, 'ds_thanh_long': thanh_long, 'ds_nho': nho, 'ds_khom': khom, 'ds_dua': dua,
    'ds_che_xanh': che_xanh, 'ds_ca_phe_phin': ca_phe_phin, 'ds_sua': sua,
}


if __name__ == '__main__':
    names = sys.argv[1:] or list(ICONS)
    for n in names:
        save(ICONS[n](), n)
    print(f'done {len(names)}')
