"""Gà, vịt, chó chạy qua đường (nhìn từ trên xuống, đầu hướng lên trên —
cùng quy ước với ảnh xe). Dùng chung bộ vẽ đổ sáng theo khối của
build_vehicles.py. Mỗi con có khung "vỗ cánh / chạy" khi bị bóp còi.

Chạy từ thư mục gốc:
    .venv/bin/python tool/asset_pipeline/build_animals.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_vehicles import Canvas, ellipse, line, poly, rrect, shade_rgb  # noqa: E402

OUT = 'assets/images'
S = 48
CX = 24

BILL = (236, 158, 38)
FOOT = (226, 140, 40)


def _speckle(c, cx, cy, rx, ry, color, n, seed):
    rnd = random.Random(seed)
    for _ in range(n):
        x = cx + rnd.uniform(-rx, rx) * 0.8
        y = cy + rnd.uniform(-ry, ry) * 0.8
        if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 0.7:
            continue
        c.shape(ellipse(x, y, 0.9, 1.3), color, flat=True, alpha=0.55)


def duck(body, head, flap=False, speck=None, seed=1):
    """Vịt: thân bầu, đuôi nhọn, cổ ngắn, mỏ dẹt vàng cam."""
    c = Canvas(S, S)
    if flap:
        # Vỗ cánh chạy: hai cánh xoè rộng, lông cánh xoè từng nan.
        for side in (-1, 1):
            c.shape(poly([(CX + side * 5, 21), (CX + side * 21, 15), (CX + side * 23, 22), (CX + side * 18, 27), (CX + side * 7, 31)]),
                    shade_rgb(body, 0.92), puff=2.5, rough=0.05)
            for k in range(3):
                x = CX + side * (12 + k * 3.5)
                c.shape(line([(x, 19 + k), (x + side * 2, 26)], 0.7), shade_rgb(body, 0.7), flat=True, alpha=0.5)
    c.shape(poly([(CX - 4.5, 33), (CX + 4.5, 33), (CX, 41.5)]), shade_rgb(body, 0.86), puff=2)
    c.shape(ellipse(CX, 26.5, 7.6, 10.5), body, puff=5, gloss=0.25, rough=0.04)
    if not flap:
        for side in (-1, 1):
            c.shape(ellipse(CX + side * 4.6, 28.5, 3.2, 7.5), shade_rgb(body, 0.86), puff=2, rough=0.05)
    if speck:
        _speckle(c, CX, 27, 7, 10, speck, 26, seed)
    c.shape(ellipse(CX, 15.5, 4.2, 5), head, puff=2.5, gloss=0.5)
    # Mỏ dẹt, bè ra ở chóp (nhìn từ trên như cái thìa).
    c.shape(poly([(CX - 1.9, 12), (CX + 1.9, 12), (CX + 2.7, 8.2), (CX + 1.8, 6.6), (CX - 1.8, 6.6), (CX - 2.7, 8.2)]), BILL, puff=0.7, gloss=0.5)
    for side in (-1, 1):
        c.shape(ellipse(CX + side * 3.4, 15, 0.55, 0.65), (16, 14, 12), flat=True)
    return c.image()


def chicken(body, neck, tail, flap=False, comb=(214, 40, 36), seed=3):
    """Gà ta: thân tròn, đuôi cong lông dài sẫm, cổ vàng óng, mào đỏ."""
    c = Canvas(S, S)
    if flap:
        for side in (-1, 1):
            c.shape(poly([(CX + side * 5, 21), (CX + side * 19, 17), (CX + side * 21, 25), (CX + side * 7, 31)]),
                    shade_rgb(body, 0.9), puff=2.5, rough=0.06)
    # Đuôi: chùm lông cong hình lưỡi liềm, xoè quạt, sẫm màu ánh xanh.
    for k in range(4):
        x0 = CX - 2.4 + k * 1.6
        x1 = CX - 6 + k * 4.4
        c.shape(poly([(x0 - 1.8, 32), (x0 + 1.8, 32), (x1 + 2.2, 40), (x1 + 0.6, 44.5), (x1 - 1.4, 41)]), shade_rgb(tail, 1 + k * 0.08),
                puff=1.4, gloss=0.9)
    c.shape(ellipse(CX, 26, 7.2, 9.5), body, puff=5, gloss=0.2, rough=0.06)
    if not flap:
        for side in (-1, 1):
            c.shape(ellipse(CX + side * 4.4, 27.5, 3, 6.8), shade_rgb(body, 0.84), puff=2, rough=0.06)
    c.shape(ellipse(CX, 17, 4.6, 5.4), neck, puff=3, gloss=0.4, rough=0.05)
    c.shape(ellipse(CX, 13, 3.2, 3.6), neck, puff=2.5, gloss=0.3)
    c.shape(rrect(CX - 1.1, 9.5, CX + 1.1, 15.5, 1), comb, puff=1, gloss=0.5)
    c.shape(poly([(CX - 1.3, 10.2), (CX + 1.3, 10.2), (CX, 7)]), (232, 186, 70), puff=0.8)
    return c.image()


def dog(coat, frame=0, run=False):
    """Chó vàng ta: thân dài, đầu có tai vểnh, đuôi cong; [frame] đổi chân."""
    c = Canvas(S, S)
    dark = shade_rgb(coat, 0.72)
    # Chân thò ra hai bên thân (nhìn từ trên thấy bàn chân).
    spread = 2.5 if run else 0
    legs = [(-5.5, 16 - spread), (5.5, 16 + spread), (-5.5, 33 + spread), (5.5, 33 - spread)]
    if frame:
        legs = [(x, y + (2.5 if i in (0, 3) else -2.5)) for i, (x, y) in enumerate(legs)]
    for x, y in legs:
        c.shape(ellipse(CX + x, y, 2, 2.6), dark, puff=1.2)
    curl = 1 if frame == 0 else -1
    c.shape(line([(CX, 37), (CX + 3 * curl, 41), (CX + 1 * curl, 44.5)], 2.6), coat, puff=1.2, gloss=0.2)
    c.shape(ellipse(CX, 25.5, 6.4, 12), coat, puff=5, gloss=0.15, rough=0.05)
    c.shape(ellipse(CX, 27, 3.2, 8.5), shade_rgb(coat, 0.9), puff=3, alpha=0.6)
    for side in (-1, 1):
        c.shape(poly([(CX + side * 2.8, 10.5), (CX + side * 7, 8.5), (CX + side * 6, 14)]), dark, puff=1)
    c.shape(ellipse(CX, 11.5, 5.2, 5.4), coat, puff=3, gloss=0.2)
    c.shape(rrect(CX - 2.3, 4.6, CX + 2.3, 10, 2.2), shade_rgb(coat, 1.06), puff=1.4)
    c.shape(ellipse(CX, 5, 1.1, 0.8), (30, 24, 20), puff=0.5, gloss=0.6)
    return c.image()


def save(img, name):
    img.save(f'{OUT}/img_animal_{name}.png', optimize=True)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    # Vịt cỏ: nâu lốm đốm, đầu sẫm; vịt trắng mỏ vàng.
    save(duck((150, 118, 82), (70, 58, 44), speck=(84, 64, 44), seed=4), 'duck')
    save(duck((150, 118, 82), (70, 58, 44), flap=True, speck=(84, 64, 44), seed=4), 'duck_flap')
    save(duck((238, 236, 228), (244, 242, 236)), 'duck_white')
    save(duck((238, 236, 228), (244, 242, 236), flap=True), 'duck_white_flap')
    # Gà trống đỏ tía đuôi đen ánh xanh; gà mái nâu.
    save(chicken((168, 70, 32), (222, 150, 54), (26, 44, 40)), 'rooster')
    save(chicken((168, 70, 32), (222, 150, 54), (26, 44, 40), flap=True), 'rooster_flap')
    save(chicken((150, 104, 60), (172, 124, 72), (96, 64, 36), comb=(200, 60, 50)), 'hen')
    save(chicken((150, 104, 60), (172, 124, 72), (96, 64, 36), flap=True, comb=(200, 60, 50)), 'hen_flap')
    # Chó vàng: hai khung bước chân, khung chạy.
    save(dog((204, 150, 84), 0), 'dog_1')
    save(dog((204, 150, 84), 1), 'dog_2')
    save(dog((204, 150, 84), 0, run=True), 'dog_run')
    print('done')
