"""Đồ quán ven đường nhìn từ trên xuống, đổ sáng theo khối như xe trong game
(dùng chung bộ vẽ của build_vehicles.py):

- Ghế nhựa đỏ / xanh, bàn thấp có cốc trà đá, bình đá, thùng đá, ô dù.
- Máy ép mía, bó mía, võng (trống / có người nằm), xe bánh mì, khay cơm.
- Lốp xe xếp chồng (tiệm vá xe), cột bơm xăng.
- Xe máy dựng không người lái (người lái xuống ngồi quán), xe máy của khách.
- Người lái đi bộ: xe máy (mũ đỏ, áo vàng như trên xe), ô tô (tóc, áo sơ mi).

Chạy từ thư mục gốc:
    .venv/bin/python tool/asset_pipeline/build_roadside.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_vehicles import (  # noqa: E402
    BODIES,
    CX,
    HELMETS,
    Canvas,
    H,
    W,
    ellipse,
    line,
    poly,
    rrect,
    shade_rgb,
)

OUT = 'assets/images'


# ------------------------------------------------------------ Xe dựng
def parked_scooter(body, helmet=None):
    """Xe máy dựng chân chống, không người lái; mũ bảo hiểm để trên yên."""
    c = Canvas(W, H)
    c.shape(rrect(CX - 4.5, 4, CX + 4.5, 26, 4), (26, 26, 28), puff=2, gloss=0.2)
    c.shape(rrect(CX - 5, 118, CX + 5, 145, 4), (26, 26, 28), puff=2, gloss=0.2)
    c.shape(poly([(CX - 9, 12), (CX + 9, 12), (CX + 11, 30), (CX + 9, 44), (CX - 9, 44), (CX - 11, 30)]), body, puff=4, gloss=0.5)
    c.shape(rrect(CX - 10, 42, CX + 10, 74, 3), (52, 54, 58), puff=1.5)
    c.shape(poly([(CX - 11, 70), (CX + 11, 70), (CX + 12, 104), (CX + 9, 128), (CX - 9, 128), (CX - 12, 104)]), body, puff=5, gloss=0.5)
    c.shape(rrect(CX - 6, 124, CX + 6, 130, 2), (200, 30, 30), puff=1, gloss=0.4)
    c.shape(ellipse(CX, 13, 6, 3), (245, 245, 235), puff=1.5, gloss=0.8)
    c.shape(rrect(CX - 8, 66, CX + 8, 118, 7), (30, 30, 32), puff=4, gloss=0.35)
    # Chân chống nghiêng ra bên trái.
    c.shape(line([(CX - 10, 92), (CX - 19, 98)], 2), (60, 62, 66), puff=1)
    c.shape(rrect(CX - 17, 31, CX + 17, 35, 2), (48, 50, 54), puff=1.5, gloss=0.4)
    for side in (-1, 1):
        c.shape(line([(CX + side * 13, 30), (CX + side * 18, 20)], 1.6), (70, 72, 76), puff=1)
        c.shape(ellipse(CX + side * 19, 18, 4, 2.6), (60, 62, 66), puff=1.5, gloss=0.8)
        c.shape(rrect(CX + side * 15 - 2.5, 30, CX + side * 15 + 2.5, 36, 1.5), (34, 34, 36), puff=1)
    if helmet:
        c.shape(ellipse(CX, 86, 9, 10), helmet, puff=6, gloss=1.2)
        c.shape(ellipse(CX, 79, 6.6, 3.2), (30, 34, 40), puff=2, gloss=1.0)
    return c.image()


# ---------------------------------------------------------- Người lái
def driver(head, shirt, pants, helmet=False):
    """Người lái đi bộ nhìn từ trên: đầu (mũ bảo hiểm / tóc), vai, hai tay."""
    c = Canvas(48, 48)
    cx, cy = 24, 24
    for side in (-1, 1):
        c.shape(ellipse(cx + side * 4, cy + 9, 3, 4.5), pants, puff=2)
    for side in (-1, 1):
        c.shape(ellipse(cx + side * 11, cy + 2, 3.2, 6.5), shade_rgb(shirt, 0.92), puff=2)
    c.shape(ellipse(cx, cy + 1, 12, 7.5), shirt, puff=4, rough=0.03)
    if helmet:
        c.shape(ellipse(cx, cy - 1, 7.4, 8), head, puff=5, gloss=1.2)
        c.shape(ellipse(cx, cy - 7, 5.4, 2.6), (30, 34, 40), puff=2, gloss=1.0)
    else:
        c.shape(ellipse(cx, cy - 1, 5.6, 6.2), head, puff=3, gloss=0.5)
    return c.image()


# ------------------------------------------------------------ Đồ quán
def stool(color):
    """Ghế nhựa thấp: mặt vuông bo góc, khe cầm ở giữa."""
    c = Canvas(26, 26)
    c.shape(rrect(2, 2, 24, 24, 6), shade_rgb(color, 0.8), puff=2)
    c.shape(rrect(3.5, 3.5, 22.5, 22.5, 5), color, puff=3, gloss=0.7)
    c.shape(rrect(9, 11.5, 17, 14.5, 1.5), shade_rgb(color, 0.45), flat=True)
    return c.image()


def low_table(top, glasses, seed):
    """Bàn thấp: mặt bàn, cốc trà đá (nước vàng, đá trắng), đĩa hướng dương."""
    rnd = random.Random(seed)
    c = Canvas(44, 44)
    c.shape(rrect(3, 3, 41, 41, 4), top, puff=2.5, gloss=0.3, rough=0.03)
    if rnd.random() < 0.6:
        c.shape(ellipse(14, 30, 7, 7), (236, 236, 230), puff=1.5, gloss=0.6)
        for _ in range(9):
            c.shape(ellipse(14 + rnd.uniform(-4, 4), 30 + rnd.uniform(-4, 4), 1.2, 0.8), (40, 36, 30), puff=0.5)
    spots = [(12, 12), (30, 12), (31, 30), (22, 21), (12, 30)]
    for x, y in spots[:glasses]:
        c.shape(ellipse(x, y, 4.6, 4.6), (210, 220, 224), puff=1, gloss=1.2, alpha=0.9)
        c.shape(ellipse(x, y, 3.6, 3.6), (196, 128, 40), puff=1.5, gloss=0.8)
        for _ in range(2):
            c.shape(rrect(x - 1.6 + rnd.uniform(-1, 1), y - 1.6 + rnd.uniform(-1, 1), x + 0.8, y + 0.8, 0.5), (246, 248, 250), puff=0.5, gloss=1.0)
    return c.image()


def tea_jug():
    """Bình đá to (đỏ cam, nắp tròn, vòi rót)."""
    c = Canvas(34, 34)
    c.shape(ellipse(17, 17, 14, 14), (226, 72, 38), puff=6, gloss=0.8)
    c.shape(ellipse(17, 17, 7, 7), (236, 236, 228), puff=3, gloss=0.9)
    c.shape(rrect(26, 15, 33, 19, 1.5), (60, 60, 64), puff=1)
    c.shape(rrect(9, 3, 25, 7, 2), (60, 60, 64), puff=1)
    return c.image()


def cooler():
    """Thùng đá xốp trắng, nắp xanh, quai cầm."""
    c = Canvas(48, 32)
    c.shape(rrect(2, 2, 46, 30, 4), (236, 238, 240), puff=3, rough=0.03)
    c.shape(rrect(5, 5, 43, 27, 3), (54, 120, 196), puff=3, gloss=0.6)
    c.shape(rrect(16, 13, 32, 19, 3), (34, 80, 140), puff=1)
    return c.image()


def umbrella(a, b):
    """Ô dù quán nước: 8 múi hai màu xen kẽ, núm ở giữa."""
    r = 46
    c = Canvas(r * 2 + 4, r * 2 + 4)
    cx = cy = r + 2
    for i in range(8):
        a0 = i * math.tau / 8
        a1 = (i + 1) * math.tau / 8
        pts = [(cx, cy)] + [(cx + math.cos(a0 + (a1 - a0) * k / 6) * r, cy + math.sin(a0 + (a1 - a0) * k / 6) * r) for k in range(7)]
        c.shape(poly(pts), a if i % 2 == 0 else b, puff=10, gloss=0.25)
    c.shape(ellipse(cx, cy, 3.5, 3.5), (220, 220, 220), puff=1.5, gloss=1.0)
    return c.image()


def cane_press():
    """Máy ép mía inox: thân hộp, bánh đà, cửa ra mía."""
    c = Canvas(56, 40)
    c.shape(rrect(3, 6, 42, 36, 3), (196, 200, 206), puff=3, gloss=1.0)
    c.shape(rrect(8, 12, 30, 30, 2), (160, 166, 172), puff=2, gloss=0.8)
    c.shape(ellipse(47, 21, 8, 15), (90, 94, 100), puff=3, gloss=0.6)
    c.shape(ellipse(47, 21, 3, 5), (196, 200, 206), puff=1.5, gloss=1.0)
    c.shape(rrect(14, 3, 24, 8, 1.5), (60, 140, 70), puff=1)
    return c.image()


def cane_bundle(seed):
    """Bó mía dựng ngả ra: thân tím xanh có đốt."""
    rnd = random.Random(seed)
    c = Canvas(84, 30)
    for i in range(7):
        y = 6 + i * 3 + rnd.uniform(-1, 1)
        col = rnd.choice([(96, 52, 90), (120, 70, 100), (110, 140, 70)])
        c.shape(rrect(4 + rnd.uniform(0, 6), y - 1.6, 80 - rnd.uniform(0, 8), y + 1.6, 1.5), col, puff=1.5, gloss=0.5)
        for x in range(14, 78, 12):
            c.shape(rrect(x, y - 1.8, x + 1.2, y + 1.8, 0.5), shade_rgb(col, 0.6), flat=True)
    c.shape(rrect(38, 3, 42, 27, 1), (180, 150, 90), puff=1)
    return c.image()


def hammock(color, person=None):
    """Võng lưới căng giữa hai cột (dọc ảnh), có thể có người nằm."""
    c = Canvas(34, 96)
    c.shape(line([(17, 3), (17, 14)], 1.2), (90, 80, 70), puff=0.5)
    c.shape(line([(17, 82), (17, 93)], 1.2), (90, 80, 70), puff=0.5)
    c.shape(poly([(17, 12), (29, 30), (30, 66), (17, 84), (4, 66), (5, 30)]), color, puff=6, rough=0.05)
    for k in range(5):
        y = 26 + k * 10
        c.shape(line([(7, y), (27, y)], 0.8), shade_rgb(color, 0.7), flat=True, alpha=0.6)
    if person:
        head, shirt = person
        c.shape(ellipse(17, 52, 9, 16), shirt, puff=5)
        for side in (-1, 1):
            c.shape(ellipse(17 + side * 4, 70, 3, 7), (50, 56, 80), puff=2)
        c.shape(ellipse(17, 33, 5.4, 6), head, puff=3, gloss=0.5)
    return c.image()


def bread_cart():
    """Xe bánh mì: khung đỏ, nóc kính thấy ổ bánh vàng."""
    c = Canvas(66, 40)
    c.shape(rrect(2, 2, 64, 38, 3), (196, 36, 32), puff=3, gloss=0.6)
    c.shape(rrect(7, 7, 59, 33, 2), (210, 226, 232), puff=1.5, gloss=1.4, alpha=0.85)
    rnd = random.Random(5)
    for i in range(6):
        x = 13 + (i % 3) * 16
        y = 13 + (i // 3) * 13
        c.shape(ellipse(x + rnd.uniform(-1, 1), y, 7, 3.6), (214, 152, 66), puff=2.5, gloss=0.5)
    return c.image()


def food_tray():
    """Tủ kính cơm bình dân: các khay thức ăn nhiều màu."""
    c = Canvas(70, 40)
    c.shape(rrect(2, 2, 68, 38, 3), (180, 186, 192), puff=3, gloss=0.8)
    colors = [(206, 120, 50), (90, 150, 60), (230, 210, 150), (170, 60, 40), (240, 190, 60), (110, 80, 60)]
    for i, col in enumerate(colors):
        x = 6 + (i % 3) * 21
        y = 6 + (i // 3) * 15
        c.shape(rrect(x, y, x + 18, y + 12, 2), (226, 230, 232), puff=1, gloss=0.8)
        c.shape(rrect(x + 2, y + 2, x + 16, y + 10, 2), col, puff=2, rough=0.08)
    return c.image()


def tire_stack():
    """Lốp xe cũ xếp chồng ở tiệm vá xe."""
    c = Canvas(44, 44)
    for x, y in [(16, 16), (28, 18), (20, 28)]:
        c.shape(ellipse(x, y, 11, 11), (34, 34, 36), puff=4, gloss=0.3)
        c.shape(ellipse(x, y, 5, 5), (70, 66, 60), puff=1)
    return c.image()


def gas_pump():
    """Cột bơm xăng: thân trắng sọc đỏ, màn hình, vòi."""
    c = Canvas(30, 40)
    c.shape(rrect(3, 3, 27, 37, 3), (240, 240, 238), puff=3, gloss=0.6)
    c.shape(rrect(3, 15, 27, 21, 1), (206, 36, 32), puff=1)
    c.shape(rrect(8, 6, 22, 12, 1), (40, 60, 70), puff=1, gloss=1.0)
    c.shape(line([(25, 28), (29, 34)], 1.6), (30, 30, 32), puff=0.5)
    return c.image()


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    parked_scooter((210, 32, 36), helmet=(226, 36, 36)).save(f'{OUT}/img_scooter_parked.png', optimize=True)
    rnd = random.Random(21)
    for i in range(3):
        parked_scooter(rnd.choice(BODIES), helmet=rnd.choice(HELMETS) if i != 1 else None).save(
            f'{OUT}/img_scooter_parked_{i + 1}.png', optimize=True)
    driver((226, 36, 36), (245, 196, 40), (40, 50, 80), helmet=True).save(f'{OUT}/img_driver_moto.png', optimize=True)
    driver((30, 26, 24), (236, 238, 240), (50, 56, 70)).save(f'{OUT}/img_driver_car.png', optimize=True)
    stool((214, 40, 40)).save(f'{OUT}/img_stool_red.png', optimize=True)
    stool((40, 100, 200)).save(f'{OUT}/img_stool_blue.png', optimize=True)
    low_table((214, 182, 130), 3, 1).save(f'{OUT}/img_table_1.png', optimize=True)
    low_table((60, 120, 190), 2, 2).save(f'{OUT}/img_table_2.png', optimize=True)
    tea_jug().save(f'{OUT}/img_tea_jug.png', optimize=True)
    cooler().save(f'{OUT}/img_cooler.png', optimize=True)
    umbrella((210, 40, 40), (240, 240, 236)).save(f'{OUT}/img_umbrella_red.png', optimize=True)
    umbrella((40, 100, 190), (240, 240, 236)).save(f'{OUT}/img_umbrella_blue.png', optimize=True)
    umbrella((60, 140, 80), (236, 200, 60)).save(f'{OUT}/img_umbrella_green.png', optimize=True)
    cane_press().save(f'{OUT}/img_cane_press.png', optimize=True)
    cane_bundle(3).save(f'{OUT}/img_cane_bundle.png', optimize=True)
    hammock((60, 140, 90)).save(f'{OUT}/img_hammock_1.png', optimize=True)
    hammock((200, 60, 60), person=((28, 24, 22), (90, 120, 190))).save(f'{OUT}/img_hammock_2.png', optimize=True)
    hammock((60, 100, 190), person=((28, 24, 22), (230, 230, 226))).save(f'{OUT}/img_hammock_3.png', optimize=True)
    bread_cart().save(f'{OUT}/img_bread_cart.png', optimize=True)
    food_tray().save(f'{OUT}/img_food_tray.png', optimize=True)
    tire_stack().save(f'{OUT}/img_tire_stack.png', optimize=True)
    gas_pump().save(f'{OUT}/img_gas_pump.png', optimize=True)
    print('done')
