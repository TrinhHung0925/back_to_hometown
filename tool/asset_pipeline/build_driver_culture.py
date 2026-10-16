"""Hình cho cổng chào tỉnh và nhà quê dựng khối 3D ở góc nhìn ghế lái.

Dùng chung bộ vẽ mặt đứng có độ nhô (Facade: bản đồ cao → bóng đổ, che khuất)
của build_driver_scenery.py. Xuất ra assets/images/driver/ kèm culture.json
(game nạp cùng scenery.json, props.json):

Cổng chào tỉnh (game ghép thành khối 3D thật: trụ hộp, xà, mái dốc):
- gate_panel: mặt biển xà ngang sơn son, khung vàng chạm mây, mề đay hai đầu;
  giữa để trống — game viết tên tỉnh lúc chạy ("THANH HOÁ / KÍNH CHÀO QUÝ
  KHÁCH", mặt sau "HẸN GẶP LẠI QUÝ KHÁCH").
- gate_pillar_l / _r: mặt trụ (câu đối đỏ chữ vàng), gate_pillar_side: mặt
  hông trụ; gate_base: bệ đá; gate_dragons: lưỡng long chầu nhật trên nóc;
  gate_lantern: đèn lồng lớn; gate_finial: bầu hồ lô trên chóp mũ trụ.

Nhà quê (cấp 4, có hiên, sân, tường rào) — mái ngói / mái tôn game dựng bằng
mặt phẳng nghiêng thật, nên ảnh ở đây chỉ có phần tường:
- house3d_body_N: mặt tiền tới chân mái (nền cao, hiên cột, cửa, đèn lồng,
  chậu quất, chậu đào); house3d_fence_N: tường rào + cổng sắt (nhìn xuyên
  qua song cổng), house3d_side_N: vân tường hồi cùng màu (lặp liền mạch);
  house3d_flagpole: cột cờ tre ngoài sân; house3d_shrine: bàn thờ thiên.

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_driver_culture.py            # tất cả
    python tool/asset_pipeline/build_driver_culture.py gate_panel # chọn vài hình
"""
import json
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_driver_scenery as S  # noqa: E402
from build_driver_scenery import (  # noqa: E402
    M_FABRIC, M_METAL, M_PLANT, M_ROOF, M_SIGN, M_TRIM, M_WALL, M_WOOD, Facade, column, door, fbm, fence, gblur,
    kumquat_pot, lantern, lin, pfbm, peach_pot, plaster_fn, shrine, smoothstep, vn_flag, window)

OUT = S.OUT

RED = (182, 24, 26)
GOLD = (232, 182, 58)


def redfn(seed=3, rgb=RED):
    red = lin(rgb)

    def fn(X, Y):
        lac = 0.9 + 0.14 * fbm(X * 1.6, Y * 1.6, seed=seed, octaves=3)
        streak = 0.97 + 0.04 * fbm(X * 0.4, Y * 9, seed=seed + 1, octaves=2)
        return red[None, None, :] * (lac * streak)[..., None]
    return fn


def goldfn(seed=5):
    gold = lin(GOLD)

    def fn(X, Y):
        return gold[None, None, :] * (0.86 + 0.24 * fbm(X * 6, Y * 6, seed=seed, octaves=2))[..., None]
    return fn


def gold_frame(f, x0, y0, x1, y1, w=0.07, h=0.12):
    """Khung nẹp vàng nổi hai lớp quanh ô chữ nhật."""
    g = goldfn()
    for (a, b, c, d) in ((x0, y0, x1, y0 + w), (x0, y1 - w, x1, y1), (x0, y0, x0 + w, y1), (x1 - w, y0, x1, y1)):
        f.paint(f.rect(a, b, c, d), g, h=h, mat=M_TRIM)
    i = w * 1.8
    for (a, b, c, d) in ((x0 + i, y0 + i, x1 - i, y0 + i + 0.025), (x0 + i, y1 - i - 0.025, x1 - i, y1 - i),
                         (x0 + i, y0 + i, x0 + i + 0.025, y1 - i), (x1 - i - 0.025, y0 + i, x1 - i, y1 - i)):
        f.paint(f.rect(a, b, c, d), g, h=h - 0.04, mat=M_TRIM)


def cloud_scroll(f, cx, cy, r, sx=1, sy=1, h=0.12):
    """Hoa văn mây cuộn (vân mây) ở góc khung: ba vòng xoắn nối nhau."""
    g = goldfn(7)
    for k, (dx, dy, rr) in enumerate(((0, 0, 1.0), (1.25, 0.25, 0.7), (2.15, 0.05, 0.5))):
        x, y = cx + sx * dx * r, cy + sy * dy * r
        R = rr * r
        pts = []
        for i in range(40):
            t = i / 39 * 1.75 * math.tau
            q = R * (1 - t / (1.75 * math.tau) * 0.85)
            pts.append((x + sx * math.cos(t) * q, y + sy * math.sin(t) * q))
        f.paint(f.lines(pts, 0.022 + 0.01 * (2 - k)), g, h=h, mat=M_TRIM)


# ================================================================ Cổng chào
PANEL_W, PANEL_H = 13.5, 2.0


def gate_panel():
    """Mặt biển xà ngang: sơn son, khung vàng chạm mây, mề đay hai đầu; giữa
    trống để game viết chữ."""
    f = Facade(PANEL_W, PANEL_H, 150, ss=2, seed=501)
    W, H = PANEL_W, PANEL_H
    f.paint(f.rect(0, 0, W, H), redfn(11), h=0.0, mat=M_SIGN)
    # gờ trên / dưới sơn son đậm, khung vàng
    f.paint(f.rect(0, 0, W, 0.16), redfn(12, (140, 18, 20)), h=0.06, mat=M_TRIM)
    f.paint(f.rect(0, H - 0.16, W, H), redfn(13, (140, 18, 20)), h=0.06, mat=M_TRIM)
    gold_frame(f, 0.22, 0.2, W - 0.22, H - 0.2, w=0.075, h=0.13)
    # mây cuộn bốn góc khung
    for (cx, cy, sx, sy) in ((0.62, H - 0.6, 1, -1), (W - 0.62, H - 0.6, -1, -1), (0.62, 0.6, 1, 1), (W - 0.62, 0.6, -1, 1)):
        cloud_scroll(f, cx, cy, 0.17, sx, sy)
    # mề đay vàng hai đầu: vòng tròn, hoa mai năm cánh
    gold = lin(GOLD)
    for mx in (1.45, W - 1.45):
        cy = H / 2
        f.paint(f.ellipse(mx, cy, 0.52, 0.52), goldfn(9), h=0.16, mat=M_TRIM)
        f.paint(f.ellipse(mx, cy, 0.44, 0.44), redfn(14, (160, 20, 22)), h=0.15)
        f.paint(f.ellipse(mx, cy, 0.37, 0.37), goldfn(10), h=0.155)
        f.paint(f.ellipse(mx, cy, 0.33, 0.33), redfn(15), h=0.15)
        for k in range(5):
            a = math.pi / 2 + k * math.tau / 5
            f.paint(f.ellipse(mx + math.cos(a) * 0.14, cy + math.sin(a) * 0.14, 0.11, 0.11), lin((250, 206, 60)), h=0.2)
        f.paint(f.ellipse(mx, cy, 0.07, 0.07), lin((214, 110, 30)), h=0.22)
    # đinh tán vàng dọc gờ
    for k in range(int(W / 0.6)):
        x = 0.3 + k * 0.6
        for y in (0.08, H - 0.08):
            f.paint(f.ellipse(x, y, 0.035, 0.035), gold, h=0.09)
    return f.render(), H


def gate_pillar(words):
    """Mặt trụ cổng (từ mặt bệ lên tới mũ trụ, cao 8,9 m): trát đá rửa vàng
    ngà, gờ chỉ ngang, ô câu đối sơn son chữ vàng, đấu đỡ mũ trụ trên cùng."""
    W, H = 1.62, 8.9
    f = Facade(W, H, 100, ss=2, seed=511 + len(words[0]))
    stone = (222, 206, 168)
    f.paint(f.rect(0, 0, W, H), plaster_fn(f, stone, 31, rough=0.7), h=0.0, mat=M_WALL)
    # chân trụ và các gờ chỉ ngang
    trim = lin((236, 222, 188))
    for (y0, y1, hh) in ((0, 0.35, 0.08), (0.35, 0.42, 0.05), (H - 1.05, H - 0.95, 0.06), (H - 0.32, H, 0.1)):
        f.paint(f.rect(0, y0, W, y1), trim * (0.95 + 0.05 * hh), h=hh, mat=M_TRIM)
    # ô câu đối
    py0, py1 = 0.75, 6.4
    f.paint(f.rect(0.16, py0, W - 0.16, py1), redfn(21), h=-0.04, mat=M_SIGN)
    gold_frame(f, 0.16, py0, W - 0.16, py1, w=0.06, h=0.03)
    n = len(words)
    step = (py1 - py0 - 0.9) / n
    for k, wd in enumerate(words):
        cy = py1 - 0.6 - (k + 0.5) * step
        tm = f.text_mask(wd, 'paytone', 0.34 if len(wd) <= 4 else 0.27, W / 2, cy, max_w=W - 0.55)
        if tm[0] is not None:
            sl, m = tm
            f.paint((sl, np.clip(gblur(m, 1.6) * 2.2, 0, 1) * 0.7), lin((90, 10, 10)))
            f.paint(tm, lin((252, 214, 72)), hadd=0.012)
    # hoa văn chữ thọ tròn phía trên ô câu đối
    f.paint(f.ellipse(W / 2, py1 + 0.75, 0.36, 0.36), goldfn(23), h=0.06, mat=M_TRIM)
    f.paint(f.ellipse(W / 2, py1 + 0.75, 0.29, 0.29), redfn(24), h=0.05)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        f.paint(f.ellipse(W / 2 + math.cos(a) * 0.15, py1 + 0.75 + math.sin(a) * 0.15, 0.07, 0.07), lin((250, 206, 60)), h=0.08)
    # đấu đỡ mũ trụ: ba khối nhô dần
    for k, (w, y0) in enumerate(((W - 0.2, H - 0.95), (W - 0.1, H - 0.7), (W, H - 0.48))):
        f.paint(f.rect((W - w) / 2, y0, (W + w) / 2, y0 + 0.2), redfn(25 + k, (150, 22, 24)), h=0.12 + 0.06 * k, mat=M_TRIM)
        f.paint(f.rect((W - w) / 2, y0 + 0.17, (W + w) / 2, y0 + 0.2), goldfn(), h=0.14 + 0.06 * k)
    f.weather(amount=0.6, splash=0.8, seed=41)
    return f.render(), H


def gate_pillar_side():
    W, H = 1.62, 8.9
    f = Facade(W, H, 100, ss=2, seed=521)
    stone = (216, 200, 162)
    f.paint(f.rect(0, 0, W, H), plaster_fn(f, stone, 33, rough=0.7), h=0.0, mat=M_WALL)
    trim = lin((236, 222, 188))
    for (y0, y1, hh) in ((0, 0.35, 0.08), (0.35, 0.42, 0.05), (H - 1.05, H - 0.95, 0.06), (H - 0.32, H, 0.1)):
        f.paint(f.rect(0, y0, W, y1), trim, h=hh, mat=M_TRIM)
    # ô lõm trát vữa, hai đường chỉ dọc
    f.paint(f.rect(0.22, 0.8, W - 0.22, H - 1.4), plaster_fn(f, (206, 188, 150), 34), h=-0.05, mat=M_WALL)
    for x in (0.22, W - 0.25):
        f.paint(f.rect(x, 0.8, x + 0.03, H - 1.4), trim, h=0.0)
    for k, (w, y0) in enumerate(((W - 0.2, H - 0.95), (W - 0.1, H - 0.7), (W, H - 0.48))):
        f.paint(f.rect((W - w) / 2, y0, (W + w) / 2, y0 + 0.2), redfn(35 + k, (150, 22, 24)), h=0.12 + 0.06 * k, mat=M_TRIM)
        f.paint(f.rect((W - w) / 2, y0 + 0.17, (W + w) / 2, y0 + 0.2), goldfn(), h=0.14 + 0.06 * k)
    f.weather(amount=0.7, splash=0.8, seed=43)
    return f.render(), H


def gate_base():
    """Mặt bệ đá granite chân trụ (2,2 × 1,1 m): mặt băm, gờ vát, băng chạm."""
    W, H = 2.2, 1.1
    f = Facade(W, H, 120, ss=2, seed=531)

    def granite(X, Y):
        base = lin((150, 146, 140))
        n = fbm(X * 9, Y * 9, seed=7, octaves=3)
        speck = smoothstep(0.72, 0.8, fbm(X * 40, Y * 40, seed=8, octaves=2))
        c = base[None, None, :] * (0.85 + 0.25 * n)[..., None]
        return c * (1 - 0.35 * speck)[..., None] + lin((210, 206, 200)) * 0.25 * speck[..., None]
    f.paint(f.rect(0, 0, W, H), granite, h=0.0, mat=M_WALL)
    f.paint(f.rect(0, H - 0.12, W, H), lambda X, Y: granite(X, Y) * 1.12, h=0.06, mat=M_TRIM)
    f.paint(f.rect(0.12, 0.25, W - 0.12, H - 0.3), lambda X, Y: granite(X, Y) * 0.92, h=-0.03)
    for k in range(5):
        cx = 0.3 + k * (W - 0.6) / 4
        f.paint(f.ellipse(cx, (H - 0.05) / 2, 0.1, 0.1), lambda X, Y: granite(X, Y) * 1.1, h=0.0)
    f.paint(f.rect(0, 0, W, 0.08), lambda X, Y: granite(X, Y) * 0.75, h=0.02)
    return f.render(), H


def gate_dragons():
    """Lưỡng long chầu nhật trên nóc mái: hai rồng men xanh vảy vàng uốn
    khúc, đầu ngóc về phía mặt trời lửa đỏ ở giữa; đuôi xoắn vút hai đầu."""
    W, H = 5.6, 1.6
    f = Facade(W, H, 110, ss=2, seed=541)
    gold = lin((236, 186, 60))
    cx = W / 2
    # mặt trời lửa: vành lửa vàng, đĩa đỏ
    for k in range(16):
        a = k * math.tau / 16 + 0.1
        ln = 0.44 if k % 2 == 0 else 0.34
        tip = (cx + math.cos(a) * ln, 0.66 + math.sin(a) * ln)
        b1 = (cx + math.cos(a - 0.2) * 0.2, 0.66 + math.sin(a - 0.2) * 0.2)
        b2 = (cx + math.cos(a + 0.2) * 0.2, 0.66 + math.sin(a + 0.2) * 0.2)
        f.paint(f.poly([b1, tip, b2]), gold, h=0.1, mat=M_TRIM)
    sm = f.ellipse(cx, 0.66, 0.24, 0.24)
    X, Y = f.grid(sm[0])
    dome = np.sqrt(np.clip(1 - ((X - cx) ** 2 + (Y - 0.66) ** 2) / 0.24 ** 2, 0, 1))
    f.paint(sm, lin((214, 40, 26)), h=0.14 + dome * 0.12, mat=M_TRIM)

    def scales(X, Y):
        g = lin((36, 116, 80))[None, None, :]
        sc = 0.82 + 0.3 * (np.sin(X * 60) * np.sin(Y * 60) > 0)
        return g * (sc * (0.9 + 0.2 * fbm(X * 8, Y * 8, seed=3, octaves=2)))[..., None]
    for side in (-1, 1):
        # thân rồng: ống tròn uốn sóng từ cổ (giữa) ra đuôi (ngoài), dày ở
        # thân, thon dần về đuôi; đóng dấu từng đốt tròn cho liền mạch
        n = 150
        pts, wid = [], []
        for i in range(n + 1):
            t = i / n
            x = cx + side * (0.66 + 1.9 * t)
            y = 0.5 + 0.2 * math.sin(t * math.tau * 1.15 + 0.9) + 0.5 * smoothstep(0.7, 1.0, t)
            pts.append((x, y))
            wid.append(0.075 + 0.07 * math.sin(math.pi * min(1.0, 0.25 + t * 0.9)))
        for i in range(0, n + 1, 2):
            x, y = pts[i]
            r = wid[i]
            f.paint(f.ellipse(x, y, r, r), scales, h=0.14 + 0.02 * i / n, mat=M_ROOF)
        # bụng vàng nhạt chạy dọc phía dưới thân
        for i in range(4, n - 6, 3):
            x, y = pts[i]
            f.paint(f.ellipse(x, y - wid[i] * 0.55, wid[i] * 0.55, wid[i] * 0.35), lin((230, 200, 110)), h=0.16)
        # vây lưng: tia lửa vàng nhọn dọc sống lưng
        for i in range(6, n - 4, 7):
            (x0, y0), (x1, y1) = pts[i], pts[i + 2]
            r = wid[i]
            f.paint(f.poly([(x0, y0 + r * 0.6), (x1, y1 + r * 0.6), ((x0 + x1) / 2 + side * 0.05, (y0 + y1) / 2 + r + 0.13)]),
                    gold, h=0.15)
        # chân rồng: hai móng vàng
        for i in (int(n * 0.22), int(n * 0.6)):
            x, y = pts[i]
            f.paint(f.lines([(x, y - wid[i] * 0.6), (x + side * 0.08, y - wid[i] - 0.12), (x + side * 0.16, y - wid[i] - 0.1)],
                            0.035), gold, h=0.17)
        # đuôi xoắn ở đầu ngoài
        tx, ty = pts[-1]
        curl = []
        for k in range(32):
            th = -math.pi / 2 + k / 31 * 4.2
            rr = 0.15 * (1 - k / 44)
            curl.append((tx + side * rr * math.cos(th), ty + 0.15 + rr * math.sin(th)))
        f.paint(f.lines(curl, 0.045), gold, h=0.16)
        for k in range(3):
            f.paint(f.poly([(tx, ty), (tx + side * (0.12 + 0.06 * k), ty + 0.12 + 0.1 * k), (tx + side * 0.05, ty + 0.05)]),
                    gold, h=0.15)
        # đầu rồng ngóc về mặt trời: đầu, mõm, hàm há, sừng, râu, bờm
        hx, hy = pts[0]
        hx -= side * 0.02
        f.paint(f.ellipse(hx, hy + 0.07, 0.17, 0.15), scales, h=0.2, mat=M_ROOF)
        f.paint(f.poly([(hx - side * 0.02, hy + 0.16), (hx - side * 0.24, hy + 0.12), (hx - side * 0.25, hy + 0.06),
                        (hx - side * 0.05, hy + 0.04)]), lin((44, 128, 90)), h=0.22, mat=M_ROOF)
        f.paint(f.poly([(hx - side * 0.04, hy - 0.0), (hx - side * 0.22, hy - 0.04), (hx - side * 0.2, hy - 0.1),
                        (hx - side * 0.02, hy - 0.06)]), lin((40, 116, 80)), h=0.21, mat=M_ROOF)
        f.paint(f.ellipse(hx - side * 0.08, hy + 0.13, 0.035, 0.03), lin((252, 236, 150)), h=0.26)
        for (dx, dy, ex, ey) in ((0.04, 0.2, 0.18, 0.42), (0.1, 0.18, 0.3, 0.36)):
            f.paint(f.lines([(hx + side * dx, hy + dy), (hx + side * (dx + ex) * 0.5, hy + ey * 0.8), (hx + side * ex, hy + ey)],
                            0.032), gold, h=0.24)
        f.paint(f.lines([(hx - side * 0.24, hy + 0.08), (hx - side * 0.34, hy + 0.2), (hx - side * 0.4, hy + 0.18)], 0.018), gold,
                h=0.25)
        f.paint(f.lines([(hx - side * 0.2, hy - 0.06), (hx - side * 0.3, hy - 0.2), (hx - side * 0.38, hy - 0.2)], 0.018), gold,
                h=0.25)
        for k in range(4):
            bx = hx + side * (0.1 + 0.05 * k)
            f.paint(f.poly([(bx, hy + 0.12), (bx + side * 0.08, hy + 0.12), (bx + side * 0.14, hy + 0.3 - 0.03 * k)]), gold, h=0.18)
    return f.render(), H


def gate_lantern():
    """Đèn lồng đỏ lớn treo dưới xà (dây treo, chóp vàng, tua rua dài)."""
    W, H = 0.95, 1.55
    f = Facade(W, H, 160, ss=2, seed=551)
    lantern(f, W / 2, H, r=0.38, h=0.4, string=0.18)
    # tua rua dài thêm, có nút vàng
    yb = H - 0.18 - 0.38 * 1.05 - 0.38 * 1.1
    f.paint(f.ellipse(W / 2, yb - 0.06, 0.05, 0.05), lin((230, 180, 60)), h=0.45)
    for k in range(9):
        x = W / 2 + (k - 4) * 0.018
        f.paint(f.rect(x - 0.006, yb - 0.52, x + 0.006, yb - 0.08), lin((200, 26, 24)), h=0.43)
    return f.render(), H


def gate_finial():
    """Bầu hồ lô vàng trên chóp mũ trụ, đế hoa sen."""
    W, H = 0.7, 1.1
    f = Facade(W, H, 160, ss=2, seed=561)
    gold = goldfn(13)
    cx = W / 2
    # đế hoa sen: các cánh nhọn
    for k in range(5):
        x = 0.1 + k * 0.125
        f.paint(f.poly([(x - 0.08, 0.05), (x + 0.08, 0.05), (x, 0.3)]), gold, h=0.1, mat=M_TRIM)
    f.paint(f.rect(0.12, 0.0, W - 0.12, 0.08), gold, h=0.12)

    def bulb(cy, r):
        sm = f.ellipse(cx, cy, r, r)
        if sm[0] is None:
            return
        X, Y = f.grid(sm[0])
        u = np.clip((X - cx) / r, -1, 1)
        v = np.clip((Y - cy) / r, -1, 1)
        dome = np.sqrt(np.clip(1 - u * u - v * v, 0, 1))
        f.paint(sm, gold, h=0.1 + dome * r, mat=M_METAL)
    bulb(0.45, 0.2)
    f.paint(f.rect(cx - 0.05, 0.62, cx + 0.05, 0.7), gold, h=0.18)
    bulb(0.82, 0.13)
    f.paint(f.poly([(cx - 0.03, 0.93), (cx + 0.03, 0.93), (cx, 1.08)]), gold, h=0.18)
    return f.render(), H


# ============================================================== Nhà quê 3D
# Nhà cấp 4: thân nhà cao tới chân mái (Y_EAVE), mái dựng trong game.
Y_EAVE = 3.25
VILLAGE3D = {
    1: dict(width=7.6, wall=(236, 204, 118), cols='round', col_rgb=(238, 232, 214), door='wood', door_rgb=(122, 70, 44),
            shutter=(46, 110, 84), fence='lime', gate=(40, 44, 48), seed=11, flag='gate', pots=['kumquat', 'kumquat'],
            side='plaster'),
    2: dict(width=7.0, wall=(152, 188, 214), cols='square', col_rgb=(230, 230, 222), door='folding', door_rgb=(70, 90, 110),
            grille=(50, 60, 70), fence='breeze', gate=(30, 70, 120), seed=12, flag='pole', pots=['peach'], side='plaster'),
    3: dict(width=8.0, wall=(238, 232, 214), cols='square', col_rgb=(224, 212, 186), door='wood', door_rgb=(140, 92, 54),
            shutter=(120, 76, 50), fence='lime', gate=(150, 30, 30), seed=13, flag='pole', shrine=True, pots=['kumquat'],
            table=True, side='plaster'),
    4: dict(width=6.6, wall=(214, 176, 112), cols='wood', col_rgb=(96, 66, 46), door='panels', door_rgb=(110, 74, 50),
            shutter=None, fence='brick', gate=None, seed=14, flag=None, old=True, pots=[], side='brick'),
    5: dict(width=7.2, wall=(126, 182, 168), cols='square', col_rgb=(232, 234, 226), door='wood', door_rgb=(60, 96, 140),
            shutter=(60, 96, 140), fence='breeze', gate=(36, 84, 70), seed=15, flag='gate', pots=['kumquat', 'peach'],
            side='plaster'),
    6: dict(width=7.4, wall=(236, 200, 186), cols='round', col_rgb=(244, 238, 228), door='glass', door_rgb=(80, 80, 80),
            grille=(160, 40, 40), fence='lime', gate=(170, 36, 36), seed=16, flag='pole', pots=['kumquat'], table=True,
            side='plaster'),
}


def village_body(spec):
    """Mặt tiền nhà cấp 4 tới chân mái: nền cao, tường hồi hai đầu, hiên cột,
    dầm hiên, cửa chính + hai cửa sổ chớp, bậc tam cấp, đèn lồng, chậu Tết."""
    W = spec['width']
    sd = spec['seed'] * 31
    old = spec.get('old', False)
    # vẽ thêm một dải mái nhô ra phía trên (để mái hắt bóng xuống hiên),
    # xong thì cắt bỏ — game dựng mái thật
    H = Y_EAVE + 0.4
    f = Facade(W, H, 112, ss=2, seed=spec['seed'])
    wall = spec['wall']
    plinth = 0.45
    f.paint(f.rect(0.0, 0, W, plinth), S.lin((168, 162, 150)), h=1.9, mat=M_TRIM)
    f.paint(f.rect(0.0, plinth - 0.06, W, plinth), S.lin((190, 182, 168)), h=1.95)
    f.paint(f.rect(0.0, plinth, W, Y_EAVE), plaster_fn(f, wall, sd, peel=0.7 if old else 0.25, repaint=1.0), h=0.0, mat=M_WALL)
    f.paint(f.rect(0.0, plinth, 0.42, Y_EAVE), plaster_fn(f, wall, sd + 1, peel=0.4 if old else 0.1), h=1.9, mat=M_WALL)
    f.paint(f.rect(W - 0.42, plinth, W, Y_EAVE), plaster_fn(f, wall, sd + 2, peel=0.4 if old else 0.1), h=1.9, mat=M_WALL)
    cx = W / 2
    dw = 1.8 if spec['door'] != 'panels' else W - 2.2
    if spec['door'] in ('wood', 'folding', 'glass'):
        door(f, cx - dw / 2, plinth, cx + dw / 2, plinth + 2.35, spec['door'], col=spec['door_rgb'], seed=sd)
    else:
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
    ncol = 4
    xs = np.linspace(0.85, W - 0.85, ncol)
    for i, xx in enumerate(xs):
        column(f, xx, plinth, Y_EAVE - 0.25, 0.26, spec['col_rgb'], 1.8, kind=spec['cols'], seed=sd + 10 + i)
    # dầm hiên đỡ mái, gờ chỉ trên cùng; dải mái nhô ra (cắt bỏ sau)
    f.paint(f.rect(0.0, Y_EAVE - 0.32, W, Y_EAVE), plaster_fn(f, wall, sd + 3), h=1.85, mat=M_WALL)
    f.paint(f.rect(0.0, Y_EAVE - 0.34, W, Y_EAVE - 0.3), lin(wall) * 0.92, h=1.9, mat=M_TRIM)
    f.paint(f.rect(-0.2, Y_EAVE, W + 0.2, H), lin((120, 60, 40)), h=2.45, mat=M_ROOF)
    for k in range(3):
        f.paint(f.rect(cx - 1.1 - 0.15 * (2 - k), k * 0.15, cx + 1.1 + 0.15 * (2 - k), (k + 1) * 0.15),
                lin((176, 170, 158)) * (0.95 + 0.05 * k), h=2.6 - 0.3 * k, mat=M_TRIM)
    for i, kind in enumerate(spec.get('pots', [])):
        px = cx - 1.45 if i == 0 else cx + 1.45
        if kind == 'kumquat':
            kumquat_pot(f, px, plinth, s=0.95, h=2.0, seed=sd + 40 + i)
        else:
            peach_pot(f, px, plinth, s=1.1, h=2.0, seed=sd + 40 + i)
    if not old:
        for xx in (xs[1] - 0.6, xs[2] + 0.6):
            lantern(f, xx, Y_EAVE - 0.32, r=0.16, h=2.25, string=0.1)
    if spec.get('table'):
        tx = cx + (1.35 if not spec.get('pots') or len(spec['pots']) < 2 else 2.4)
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
    f.weather(amount=1.6 if old else 1.0, splash=1.3, seed=sd)
    im = f.render()
    cut = int(round(0.4 * f.ppm_f))
    return im.crop((0, cut, im.width, im.height)), Y_EAVE


def village_fence(spec):
    """Tường rào trước sân, cổng sắt giữa (song cổng nhìn xuyên), cờ cắm
    trên trụ cổng ngày Tết."""
    W = spec['width']
    sd = spec['seed'] * 31
    flag = spec.get('flag') == 'gate'
    H = 3.2 if flag else 2.3
    f = Facade(W, H, 112, ss=2, seed=spec['seed'] + 100)
    gw = 2.6 if spec.get('gate') is not None else None
    cx = W / 2
    fence(f, 0.0, W, cx - gw / 2 if gw else None, cx + gw / 2 if gw else None, spec['fence'], spec.get('gate'), h=0.3,
          seed=sd, wall_rgb=(230, 226, 212))
    if flag:
        vn_flag(f, cx + gw / 2 + 0.2, 1.97, length=1.4, w=0.7, side=1, h=0.6)
    f.weather(amount=1.2, splash=1.4, seed=sd + 1)
    return f.render(), H


def village_side(spec, size=512, tile_m=3.0):
    """Vân tường hồi cùng màu mặt tiền (lặp liền mạch 3 × 3 m): vữa sơn loang,
    vệt nước chảy, mảng bong lộ vữa; nhà cổ thì gạch trần."""
    if spec.get('side') == 'brick':
        return S.wall_side('brick', seed=400 + spec['seed'], size=size, tile_m=tile_m)
    seed = 410 + spec['seed']
    big = pfbm(size, size, 140, seed=seed + 1)
    mid = pfbm(size, size, 30, seed=seed + 2)
    fine = pfbm(size, size, 4, seed=seed + 3, octaves=3)
    streak = pfbm(size, size, 120, seed=seed + 4, octaves=4, sx_ratio=0.08)
    streak = smoothstep(0.5, 0.9, streak) * (0.4 + 0.6 * pfbm(size, size, 80, seed=seed + 5))
    streak = S.gblur_wrap_x(streak, 1.5)
    rgb = tuple(int(c * 0.96) for c in spec['wall'])
    alb = lin(rgb)[None, None, :] * (0.88 + 0.24 * big)[..., None] * (0.95 + 0.1 * mid)[..., None] * \
        (0.96 + 0.08 * fine)[..., None]
    peel = smoothstep(0.8, 0.83, pfbm(size, size, 16, seed=seed + 8))
    cem = lin((156, 152, 142)) * (0.85 + 0.3 * fine)[..., None]
    alb = alb * (1 - 0.35 * streak)[..., None]
    alb = alb * (1 - peel[..., None]) + cem * peel[..., None]
    col = alb * 1.02
    srgb = np.clip(col, 0, 1) ** (1 / 2.2)
    return Image.fromarray((srgb * 255 + 0.5).astype(np.uint8), 'RGB')


def flagpole():
    """Cột cờ tre cắm ngoài sân, cờ đỏ sao vàng bay."""
    W, H = 1.5, 7.2
    f = Facade(W, H, 90, ss=2, seed=571)
    px = 0.12
    f.paint(f.rect(px - 0.04, 0.0, px + 0.04, H - 0.1), lin((160, 148, 100)), h=0.3, mat=M_WOOD)
    for k in range(int(H / 0.4)):
        f.paint(f.rect(px - 0.045, k * 0.4, px + 0.045, k * 0.4 + 0.03), lin((112, 102, 70)), h=0.31)
    fy1 = H - 0.2
    sm = f.poly([(px + 0.04, fy1), (px + 1.32, fy1 - 0.1), (px + 1.32, fy1 - 0.92), (px + 0.04, fy1 - 0.84)])
    f.paint(sm, lin((214, 24, 28)), h=lambda X, Y: 0.35 + 0.06 * np.sin((X - px) * 7), mat=M_FABRIC)
    cxs, cys, R = px + 0.68, fy1 - 0.47, 0.23
    star = [(cxs + (R if k % 2 == 0 else R * 0.382) * math.cos(math.pi / 2 + k * math.pi / 5),
             cys + (R if k % 2 == 0 else R * 0.382) * math.sin(math.pi / 2 + k * math.pi / 5)) for k in range(10)]
    f.paint(f.poly(star), lin((252, 214, 40)), hadd=0.004)
    return f.render(), H


def shrine_board():
    W, H = 0.9, 2.3
    f = Facade(W, H, 160, ss=2, seed=581)
    shrine(f, W / 2, h=0.2)
    return f.render(), H


# ============================================= Tường hông nhà phố lộ ra
def wall_window(seed, shutter=None):
    """Cửa sổ nhỏ trên tường hông nhà ống (khung sắt bảo vệ, kính, ô văng)."""
    W, H = 1.5, 1.75
    f = Facade(W, H, 120, ss=2, seed=seed)
    window(f, 0.25, 0.25, W - 0.25, H - 0.35, frame=(200, 200, 196), grille=(46, 50, 54) if shutter is None else None,
           shutter=shutter, shutter_open=False, lintel=True, sill=True, wall_rgb=(196, 190, 176), seed=seed)
    return f.render(), H


AD_TEXTS = [
    ('KHOAN CẮT BÊ TÔNG', '0912 345 678', (196, 28, 30)),
    ('HÚT BỂ PHỐT - THÔNG CỐNG', '0988 111 222', (24, 70, 160)),
    ('CHO THUÊ MẶT BẰNG', 'LH: 0903 456 789', (196, 28, 30)),
    ('SƠN NƯỚC - CHỐNG THẤM', '0977 555 999', (20, 110, 60)),
]


def wall_ad(k):
    """Chữ quảng cáo sơn tay trên tường hông (nền vôi trắng, chữ đỏ / xanh,
    sơn bạc màu, vệt mưa)."""
    title, phone, ink = AD_TEXTS[k]
    W, H = 4.2, 1.6
    f = Facade(W, H, 110, ss=2, seed=600 + k)
    f.paint(f.rect(0.0, 0.0, W, H), plaster_fn(f, (236, 232, 222), 610 + k, peel=0.5), h=0.0, mat=M_WALL)
    tm = f.text_mask(title, 'bold', 0.36, W / 2, H * 0.64, max_w=W - 0.35)
    if tm[0] is not None:
        sl, m = tm
        X, Y = f.grid(sl)
        fade = 0.75 + 0.25 * fbm(X * 3, Y * 3, seed=620 + k, octaves=3)
        f.paint((sl, m * np.clip(fade, 0, 1)), lin(ink), hadd=0.002)
    tm = f.text_mask(phone, 'bold', 0.3, W / 2, H * 0.26, max_w=W - 1.0)
    if tm[0] is not None:
        f.paint(tm, lin((30, 30, 32)), hadd=0.002)
    f.weather(amount=1.3, splash=0.0, seed=630 + k)
    return f.render(), H


# ================================================================ Danh mục
ITEMS = {
    'gate_panel': (gate_panel, {'kind': 'gate_panel', 'text_box': [0.19, 0.16, 0.81, 0.84]}),
    'gate_pillar_l': (lambda: gate_pillar(['AN', 'KHANG', 'THỊNH', 'VƯỢNG']), {'kind': 'gate_pillar'}),
    'gate_pillar_r': (lambda: gate_pillar(['VẠN', 'SỰ', 'NHƯ', 'Ý']), {'kind': 'gate_pillar'}),
    'gate_pillar_side': (gate_pillar_side, {'kind': 'gate_pillar'}),
    'gate_base': (gate_base, {'kind': 'gate_base'}),
    'gate_dragons': (gate_dragons, {'kind': 'gate_ornament'}),
    'gate_lantern': (gate_lantern, {'kind': 'lantern'}),
    'gate_finial': (gate_finial, {'kind': 'finial'}),
    'house3d_flagpole': (flagpole, {'kind': 'flagpole'}),
    'house3d_shrine': (shrine_board, {'kind': 'shrine'}),
    'wall_window_1': (lambda: wall_window(641), {'kind': 'wall_decal'}),
    'wall_window_2': (lambda: wall_window(642, shutter=(70, 110, 90)), {'kind': 'wall_decal'}),
}
for _k in range(len(AD_TEXTS)):
    ITEMS[f'wall_ad_{_k + 1}'] = ((lambda k=_k: wall_ad(k)), {'kind': 'wall_decal'})
for _n, _spec in VILLAGE3D.items():
    ITEMS[f'house3d_body_{_n}'] = ((lambda sp=_spec: village_body(sp)), {'kind': 'house3d_body', 'eave_m': Y_EAVE,
                                                                        'facade_w_m': _spec['width']})
    ITEMS[f'house3d_fence_{_n}'] = ((lambda sp=_spec: village_fence(sp)), {'kind': 'house3d_fence',
                                                                          'facade_w_m': _spec['width']})
    ITEMS[f'house3d_side_{_n}'] = ((lambda sp=_spec: village_side(sp)), {'kind': 'wall_tile', 'tile_m': 3.0})


def build_one(args):
    name, out = args
    t0 = time.time()
    fn, meta = ITEMS[name]
    res = fn()
    meta = dict(meta)
    if isinstance(res, tuple):
        im, h = res
        meta['h_m'] = round(float(h), 3)
    else:
        im = res
    path = os.path.join(out, name + '.png')
    im.save(path, optimize=True)
    w, hh = im.size
    if 'h_m' in meta:
        meta['w_m'] = round(meta['h_m'] * w / hh, 3)
    meta['px'] = [w, hh]
    print(f'  {name:22s} {w}x{hh}  {os.path.getsize(path) / 1024:.0f} KB  {time.time() - t0:.1f}s', flush=True)
    return name, meta


def main():
    out = OUT
    args = sys.argv[1:]
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    names = [a for a in args if not a.startswith('-')] or list(ITEMS)
    bad = [n for n in names if n not in ITEMS]
    if bad:
        sys.exit(f'Không có hình: {bad}')
    os.makedirs(out, exist_ok=True)
    t0 = time.time()
    with mp.Pool(min(8, os.cpu_count() or 4)) as pool:
        results = pool.map(build_one, [(n, out) for n in names], chunksize=1)
    js = os.path.join(out, 'culture.json')
    meta = {}
    if os.path.exists(js):
        with open(js) as fh:
            meta = json.load(fh)
    for n, m in results:
        meta[n] = m
    meta = {k: meta[k] for k in sorted(meta, key=lambda k: list(ITEMS).index(k) if k in ITEMS else 999)}
    with open(js, 'w') as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    print(f'Xong {len(results)} hình trong {time.time() - t0:.0f}s')


if __name__ == '__main__':
    main()
