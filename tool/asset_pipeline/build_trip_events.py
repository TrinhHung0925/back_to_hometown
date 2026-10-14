"""Hình cho các tình huống dọc đường (xăng, lốp, mưa, chốt CSGT), nhìn từ trên
xuống, đổ sáng theo khối như xe trong game (dùng chung bộ vẽ của
build_vehicles.py):

- Người lái xe máy mặc áo mưa cánh dơi (nilon trong, trùm cả đầu xe).
- CSGT đứng / đang vẫy gậy, súng bắn tốc độ trên chân máy, cọc tiêu, bàn
  làm việc, xe máy CSGT dựng.
- Kệ xăng lẻ đóng chai, máy bơm hơi, chậu nước thử săm, can xăng.
- Biển tam giác cảnh báo, lốp dự phòng, con đội (kích xe).
- Nhân viên cây xăng, thợ vá xe.

Chạy từ thư mục gốc:
    .venv/bin/python tool/asset_pipeline/build_trip_events.py
"""
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_vehicles import (  # noqa: E402
    CX,
    Canvas,
    H,
    W,
    ellipse,
    line,
    poly,
    rrect,
    scooter,
    shade_rgb,
)
from build_roadside import parked_scooter  # noqa: E402

OUT = 'assets/images'


# ------------------------------------------------------------ Áo mưa
def raincoat_rider(body, helmet, jacket, pants, coat):
    """Xe máy người chơi, người lái trùm áo mưa cánh dơi: tấm nilon trong phủ
    từ đầu xe ra sau lưng, mũ bảo hiểm thò qua lỗ đầu."""
    base = scooter(body, helmet, jacket, pants)
    c = Canvas(W, H)
    c.shape(poly([(CX - 15, 22), (CX + 15, 22), (CX + 22, 44), (CX + 23, 78), (CX + 18, 104),
                  (CX - 18, 104), (CX - 23, 78), (CX - 22, 44)]), coat, puff=9, gloss=1.4, alpha=0.78)
    # Nếp nhăn nilon.
    for x in (-12, -4, 5, 13):
        c.shape(line([(CX + x, 30), (CX + x * 1.3, 98)], 1.2), shade_rgb(coat, 0.75), flat=True, alpha=0.35)
    c.shape(ellipse(CX, 68, 8.6, 9.6), helmet, puff=6, gloss=1.2)
    c.shape(ellipse(CX, 61.5, 6.4, 3.2), (30, 34, 40), puff=2, gloss=1.0)
    c.shape(lambda d, s: d.ellipse([(CX - 10) * s, (58) * s, (CX + 10) * s, (79) * s], outline=255, width=int(1.6 * s)),
            shade_rgb(coat, 0.8), flat=True, alpha=0.9)
    over = c.image()
    base.alpha_composite(over)
    return base


# ------------------------------------------------------------- CSGT
UNIFORM = (196, 210, 62)  # áo phản quang vàng chanh
CAP = (92, 98, 70)  # mũ kê-pi màu rêu


def officer(wave=False, radar=False):
    """CSGT nhìn từ trên: mũ kê-pi, vai áo phản quang, hai tay; [wave] tay phải
    giơ gậy chỉ huy trắng sọc đỏ, [radar] hai tay cầm súng bắn tốc độ."""
    c = Canvas(64, 64)
    cx, cy = 26, 32
    for side in (-1, 1):
        c.shape(ellipse(cx + side * 4, cy + 9, 3.2, 4.6), (64, 72, 52), puff=2)
    if wave:
        c.shape(line([(cx + 10, cy), (cx + 22, cy - 6), (cx + 30, cy - 12)], 5), shade_rgb(UNIFORM, 0.92), puff=2)
        c.shape(line([(cx + 29, cy - 12), (cx + 46, cy - 26)], 2.6), (245, 245, 245), puff=1, gloss=0.5)
        for k in range(3):
            t = 0.25 + k * 0.25
            x0, y0 = cx + 29 + 17 * t, cy - 12 - 14 * t
            c.shape(line([(x0 - 1.5, y0 + 1.2), (x0 + 1.5, y0 - 1.2)], 2.8), (214, 40, 40), flat=True)
        c.shape(ellipse(cx - 11, cy + 2, 3.2, 6), shade_rgb(UNIFORM, 0.92), puff=2)
    elif radar:
        for side in (-1, 1):
            c.shape(line([(cx + side * 10, cy + 1), (cx + side * 5, cy - 9)], 5), shade_rgb(UNIFORM, 0.92), puff=2)
        c.shape(rrect(cx - 4, cy - 20, cx + 4, cy - 8, 2), (40, 42, 46), puff=1.5, gloss=0.8)
        c.shape(ellipse(cx, cy - 20, 3.4, 2), (120, 180, 220), puff=1, gloss=1.2)
    else:
        for side in (-1, 1):
            c.shape(ellipse(cx + side * 11, cy + 2, 3.2, 6), shade_rgb(UNIFORM, 0.92), puff=2)
    c.shape(ellipse(cx, cy + 1, 12, 7.5), UNIFORM, puff=4, gloss=0.6)
    # Sọc phản quang bạc trên vai.
    c.shape(rrect(cx - 11, cy - 1, cx + 11, cy + 1.4, 1), (230, 232, 236), flat=True, alpha=0.85)
    c.shape(ellipse(cx, cy - 1, 7.4, 7.6), CAP, puff=4, gloss=0.6)
    c.shape(ellipse(cx, cy - 1, 4.2, 4.4), shade_rgb(CAP, 1.15), puff=2, gloss=0.4)
    c.shape(lambda d, s: d.ellipse([(cx - 7.4) * s, (cy - 8.6) * s, (cx + 7.4) * s, (cy + 6.6) * s], outline=255, width=int(1.4 * s)),
            (200, 40, 40), flat=True)
    c.shape(rrect(cx - 5, cy - 10.5, cx + 5, cy - 7, 2), (30, 32, 30), puff=1, gloss=0.8)  # lưỡi trai
    return c.image()


def radar_tripod():
    """Súng bắn tốc độ đặt trên chân máy ba chân."""
    c = Canvas(40, 40)
    for a in ((8, 32), (32, 32), (20, 6)):
        c.shape(line([(20, 20), a], 1.6), (60, 62, 66), puff=0.8)
    c.shape(rrect(13, 14, 27, 26, 2.5), (36, 38, 42), puff=2, gloss=0.9)
    c.shape(ellipse(20, 14, 5, 2.6), (90, 170, 220), puff=1, gloss=1.4)
    c.shape(rrect(17, 22, 23, 25, 1), (220, 60, 50), flat=True)
    return c.image()


def traffic_cone():
    """Cọc tiêu (nón giao thông) nhìn từ trên: đế vuông đen, thân cam, vạch
    phản quang trắng."""
    c = Canvas(26, 26)
    c.shape(rrect(2, 2, 24, 24, 3), (34, 34, 36), puff=1.5)
    c.shape(ellipse(13, 13, 9, 9), (240, 110, 30), puff=4, gloss=0.6)
    c.shape(lambda d, s: d.ellipse([7 * s, 7 * s, 19 * s, 19 * s], outline=255, width=int(2.4 * s)), (245, 245, 245), flat=True)
    c.shape(ellipse(13, 13, 2.6, 2.6), (250, 140, 60), puff=1, gloss=0.8)
    return c.image()


def police_table():
    """Bàn làm việc gấp của chốt: khăn xanh, sổ biên bản, bộ đàm."""
    c = Canvas(56, 32)
    c.shape(rrect(2, 2, 54, 30, 2), (40, 92, 160), puff=2, gloss=0.3, rough=0.03)
    c.shape(rrect(8, 8, 26, 24, 1), (240, 238, 228), puff=1, gloss=0.3)
    for y in (11, 14, 17, 20):
        c.shape(rrect(10, y, 24, y + 0.8, 0.3), (120, 120, 130), flat=True)
    c.shape(rrect(34, 10, 40, 22, 1.5), (30, 30, 32), puff=1.5, gloss=0.8)
    c.shape(rrect(44, 8, 50, 14, 1), (200, 40, 40), puff=1)
    return c.image()


def parked_police():
    """Xe máy CSGT dựng chân chống: trắng, sọc xanh, hộp đựng đồ sau."""
    img = parked_scooter((236, 236, 236))
    c = Canvas(W, H)
    c.shape(rrect(CX - 2, 72, CX + 2, 126, 1), (40, 70, 160), flat=True, alpha=0.9)
    c.shape(rrect(CX - 11, 112, CX + 11, 136, 3), (236, 236, 236), puff=3, gloss=0.8)
    c.shape(rrect(CX - 9, 120, CX + 9, 123, 1), (40, 70, 160), flat=True)
    c.shape(ellipse(CX, 12, 4, 2), (60, 110, 230), puff=1, gloss=1.2)
    img.alpha_composite(c.image())
    return img


# ------------------------------------------------- Xăng, lốp, sửa xe
def bottle_shelf(seed=4):
    """Kệ gỗ xăng lẻ: hai tầng chai thuỷ tinh đựng xăng (vàng / hồng), phễu."""
    rnd = random.Random(seed)
    c = Canvas(64, 34)
    c.shape(rrect(2, 2, 62, 32, 2), (150, 104, 62), puff=2, rough=0.08)
    c.shape(rrect(2, 16, 62, 18, 0.5), (110, 74, 42), flat=True)
    for row, y in enumerate((9, 25)):
        for i in range(6):
            x = 8 + i * 9.6
            liquid = rnd.choice([(236, 180, 60), (230, 120, 150), (240, 200, 90)])
            c.shape(ellipse(x, y, 4, 4), (200, 216, 222), puff=1.5, gloss=1.4, alpha=0.85)
            c.shape(ellipse(x, y, 3.3, 3.3), liquid, puff=2.5, gloss=1.6, alpha=0.95)
            c.shape(ellipse(x + 0.6, y + 0.6, 0.9, 0.9), (120, 96, 70), puff=0.5)
    return c.image()


def funnel():
    c = Canvas(20, 20)
    c.shape(ellipse(10, 10, 8, 8), (226, 60, 50), puff=3, gloss=0.8)
    c.shape(ellipse(10, 10, 2.6, 2.6), (40, 30, 30), puff=1)
    return c.image()


def jerrycan():
    """Can xăng nhựa đỏ, quai cầm, nắp vàng."""
    c = Canvas(26, 34)
    c.shape(rrect(3, 5, 23, 31, 3), (200, 36, 32), puff=4, gloss=0.8)
    c.shape(rrect(6, 2, 16, 9, 2), (180, 30, 28), puff=2)
    c.shape(rrect(8, 3.5, 14, 7, 1), (60, 30, 28), flat=True)
    c.shape(ellipse(19, 6, 3, 3), (240, 200, 40), puff=1.5, gloss=1)
    c.shape(line([(6, 14), (20, 28)], 1.4), (160, 26, 24), flat=True, alpha=0.6)
    c.shape(line([(20, 14), (6, 28)], 1.4), (160, 26, 24), flat=True, alpha=0.6)
    return c.image()


def compressor():
    """Máy bơm hơi tiệm vá xe: bình khí đỏ nằm ngang, mô-tơ, cuộn dây hơi."""
    c = Canvas(52, 34)
    c.shape(rrect(4, 8, 38, 26, 9), (204, 44, 36), puff=5, gloss=1.0)
    c.shape(rrect(30, 4, 46, 16, 3), (60, 62, 66), puff=3, gloss=0.6)
    c.shape(ellipse(38, 10, 3, 3), (180, 184, 190), puff=1, gloss=1.2)
    c.shape(lambda d, s: d.ellipse([34 * s, 18 * s, 50 * s, 32 * s], outline=255, width=int(2 * s)), (30, 30, 32), puff=1)
    return c.image()


def water_basin():
    """Chậu nhôm nước thử săm."""
    c = Canvas(34, 34)
    c.shape(ellipse(17, 17, 15, 15), (176, 182, 188), puff=4, gloss=1.2)
    c.shape(ellipse(17, 17, 12, 12), (110, 140, 150), puff=1, gloss=1.4)
    c.shape(lambda d, s: d.ellipse([9 * s, 10 * s, 25 * s, 24 * s], outline=255, width=int(3 * s)), (30, 30, 32), puff=1.5, alpha=0.9)
    return c.image()


def warning_triangle():
    """Biển tam giác phản quang đặt sau xe khi dừng bên lề."""
    c = Canvas(30, 28)
    c.shape(poly([(15, 2), (28, 25), (2, 25)]), (220, 36, 30), puff=2, gloss=0.8)
    c.shape(poly([(15, 9), (22, 21), (8, 21)]), (250, 230, 220), puff=1, gloss=0.4)
    c.shape(poly([(15, 12), (19.5, 19.5), (10.5, 19.5)]), (220, 36, 30), puff=1)
    return c.image()


def spare_tire():
    """Lốp dự phòng (bánh xe) đặt nằm bên cạnh xe."""
    c = Canvas(34, 34)
    c.shape(ellipse(17, 17, 15, 15), (30, 30, 32), puff=4, gloss=0.3)
    c.shape(ellipse(17, 17, 9, 9), (176, 180, 186), puff=2, gloss=1.2)
    for i in range(5):
        import math
        a = i * math.tau / 5
        c.shape(ellipse(17 + math.cos(a) * 5, 17 + math.sin(a) * 5, 1.3, 1.3), (90, 92, 96), puff=0.5)
    c.shape(ellipse(17, 17, 2.4, 2.4), (120, 122, 126), puff=1, gloss=1)
    return c.image()


def worker(cap, shirt, seed):
    """Người làm việc nhìn từ trên: mũ lưỡi trai / tóc, áo đồng phục, hai tay
    chìa ra phía trước (đang làm)."""
    c = Canvas(48, 48)
    cx, cy = 24, 25
    for side in (-1, 1):
        c.shape(ellipse(cx + side * 4, cy + 9, 3, 4.5), (46, 52, 70), puff=2)
    for side in (-1, 1):
        c.shape(line([(cx + side * 10, cy + 1), (cx + side * 8, cy - 10)], 5), shade_rgb(shirt, 0.92), puff=2)
        c.shape(ellipse(cx + side * 8, cy - 11, 2.4, 2.4), (214, 168, 130), puff=1.5)
    c.shape(ellipse(cx, cy + 1, 12, 7.5), shirt, puff=4, rough=0.03)
    if cap:
        c.shape(ellipse(cx, cy - 1, 6, 6.4), cap, puff=3, gloss=0.4)
        c.shape(rrect(cx - 4.5, cy - 10, cx + 4.5, cy - 5, 2), shade_rgb(cap, 0.7), puff=1)
    else:
        c.shape(ellipse(cx, cy - 1, 5.6, 6.2), (28, 24, 22), puff=3, gloss=0.5)
    return c.image()


def crouching_driver(head, shirt, helmet=False):
    """Người lái ngồi xổm cạnh bánh xe (thay lốp): lưng cong, hai tay chìa ra."""
    c = Canvas(48, 48)
    cx, cy = 24, 27
    for side in (-1, 1):
        c.shape(ellipse(cx + side * 7, cy + 6, 4, 5), (40, 50, 80), puff=2)
    for side in (-1, 1):
        c.shape(line([(cx + side * 9, cy), (cx + side * 6, cy - 12)], 5.4), shade_rgb(shirt, 0.92), puff=2)
    c.shape(ellipse(cx, cy, 12, 9), shirt, puff=5, rough=0.03)
    if helmet:
        c.shape(ellipse(cx, cy - 6, 7.4, 8), head, puff=5, gloss=1.2)
    else:
        c.shape(ellipse(cx, cy - 6, 5.6, 6.2), head, puff=3, gloss=0.5)
    return c.image()


def car_jack():
    c = Canvas(30, 16)
    c.shape(rrect(2, 4, 28, 12, 2), (200, 40, 36), puff=2, gloss=0.6)
    c.shape(rrect(10, 1, 20, 15, 1.5), (60, 62, 66), puff=1.5, gloss=0.8)
    return c.image()


def save(img, name):
    img.save(f'{OUT}/{name}.png', optimize=True)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    save(raincoat_rider((210, 32, 36), (226, 36, 36), (245, 196, 40), (40, 50, 80), (70, 150, 230)), 'img_scooter_player_raincoat')
    rnd = random.Random(8)
    coats = [(230, 120, 170), (60, 160, 230), (250, 210, 60), (90, 190, 110)]
    for i in range(4):
        save(raincoat_rider(rnd.choice([(200, 30, 36), (235, 235, 235), (30, 30, 34), (40, 90, 170)]),
                            rnd.choice([(245, 245, 245), (40, 90, 190), (30, 30, 34)]), (90, 90, 96), (40, 50, 80), coats[i]),
             f'img_scooter_ai_raincoat_{i + 1}')
    save(officer(), 'img_police_officer')
    save(officer(wave=True), 'img_police_officer_wave')
    save(officer(radar=True), 'img_police_officer_radar')
    save(radar_tripod(), 'img_radar_tripod')
    save(traffic_cone(), 'img_traffic_cone')
    save(police_table(), 'img_police_table')
    save(parked_police(), 'img_scooter_police_parked')
    save(bottle_shelf(), 'img_bottle_shelf')
    save(funnel(), 'img_funnel')
    save(jerrycan(), 'img_jerrycan')
    save(compressor(), 'img_compressor')
    save(water_basin(), 'img_water_basin')
    save(warning_triangle(), 'img_warning_triangle')
    save(spare_tire(), 'img_spare_tire')
    save(car_jack(), 'img_car_jack')
    save(worker((200, 36, 32), (40, 90, 170), 1), 'img_attendant')
    save(worker((40, 40, 44), (90, 96, 104), 2), 'img_mechanic')
    save(worker(None, (220, 120, 150), 3), 'img_seller')
    save(crouching_driver((226, 36, 36), (245, 196, 40), helmet=True), 'img_driver_moto_crouch')
    save(crouching_driver((30, 26, 24), (236, 238, 240)), 'img_driver_car_crouch')
    print('done')
