"""Billboard cho chốt kiểm tra nồng độ cồn đêm 30 Tết (góc nhìn ghế lái và
bảng thổi nồng độ cồn): CSGT cầm máy đo nồng độ cồn, CSGT vẫy gậy chỉ huy
phát sáng, biển "KIỂM TRA NỒNG ĐỘ CỒN", đèn chiếu sáng dã chiến.

Dùng lại bộ dựng của build_driver_props.py (cùng vật liệu, cùng máy ảnh, cùng
người CSGT), ghi ảnh vào assets/images/driver và gộp vào props.json. Chạy từ
thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_tet_night_props.py
    python tool/asset_pipeline/build_tet_night_props.py --only police_sign_alcohol
    python tool/asset_pipeline/build_tet_night_props.py --out DIR --sheet sheet.png
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_driver_props as bdp  # noqa: E402
from build_driver_props import (  # noqa: E402
    Mat, Obj, add, capsule, cyl, draw_center, ellipsoid, placed, plate, police_fig, police_parts, rbox, rot_mat,
    unit)

# Người CSGT trên bảng thổi nồng độ cồn hiện to: dựng nét gấp đôi.
OFFICER_PPM = 340.0


# ------------------------------------------------------------ Máy đo cồn
def breathalyzer_parts():
    """Máy đo nồng độ cồn cầm tay: thân đen nhám, viền cao su vàng hai bên,
    màn LCD xanh sáng, hàng phím, ống thổi nhựa trắng cắm trên đỉnh chĩa về
    phía người thổi. Gốc toạ độ ở đáy máy, trục máy dựng đứng."""
    hw, hd, hh = 0.038, 0.019, 0.094

    def body(p):
        return rbox(p, (0, 0, hh), (hw, hd, hh), 0.012)

    def pick(p, n):
        x, y, z = p
        front = n[1] < -0.7
        screen = front & (np.abs(x) < hw * 0.70) & (z > hh * 1.12) & (z < hh * 1.72)
        keys = front & (np.abs(x) < hw * 0.62) & (z > hh * 0.62) & (z < hh * 0.98) & (np.abs(np.abs(x) - hw * 0.3) < hw * 0.22)
        bumper = np.abs(x) > hw * 0.80
        return np.where(screen, 2, np.where(bumper, 1, np.where(keys, 3, 0))).astype(np.int32)

    mats = [
        Mat((34, 36, 40), rough=0.45, spec=0.6, coat=0.3),
        Mat((236, 184, 26), rough=0.55, spec=0.4),
        Mat((150, 214, 120), rough=0.08, spec=1.0, coat=1.0, emit=0.75),
        Mat((96, 100, 108), rough=0.3, spec=0.7),
    ]
    parts = [Obj('breath_body', body, mats, pick=pick)]
    a = (0.0, -0.004, 2 * hh - 0.006)
    b = (0.0, -0.085, 2 * hh + 0.045)
    parts.append(Obj('mouthpiece', lambda p: capsule(p, a, b, 0.011), Mat((246, 246, 242), rough=0.22, spec=0.9, coat=0.6)))
    return parts


def p_police_breath():
    """CSGT đứng cạnh cửa xe, tay phải đưa máy đo nồng độ cồn ra trước ngang
    ngực (ống thổi chĩa về phía người lái), tay kia buông."""
    f = police_fig()
    s = f.s
    f.arm('l', (-0.215 * s, -0.10, 1.09 * s), (-0.10, -0.33, 1.15 * s), (0.3, -0.85, 0.35))
    f.arm('r', (0.215 * s, 0.03, 1.10 * s), (0.17 * s, -0.04, 0.90 * s), (-0.25, -0.2, -1))
    parts = police_parts(f, seed=37)
    w = f.j['wr_l']
    parts += placed(breathalyzer_parts(), w[0] + 0.035, w[1] - 0.045, w[2] - 0.05, R=rot_mat('x', 0.28))
    return parts


def baton_glow(a, b, r=0.018):
    """Gậy chỉ huy giao thông phát sáng (đèn LED đỏ trong ống nhựa trong),
    chuôi đen."""
    ax_ = np.array(a, np.float64)
    bv = np.array(b, np.float64) - ax_
    L = np.linalg.norm(bv)

    def pick(p, n):
        t = ((p[0] - ax_[0]) * bv[0] + (p[1] - ax_[1]) * bv[1] + (p[2] - ax_[2]) * bv[2]) / (L * L)
        return (t < 0.22).astype(np.int32)

    return [Obj('baton_glow', lambda p: capsule(p, a, b, r),
                [Mat((255, 64, 36), rough=0.15, spec=0.9, coat=0.9, emit=1.5), Mat((28, 28, 30), rough=0.5)], pick=pick)]


def p_police_baton():
    """CSGT giơ cao gậy phát sáng vẫy xe vào kiểm tra (ban đêm)."""
    f = police_fig()
    s = f.s
    f.arm('l', (-0.33 * s, -0.04, 1.52 * s), (-0.40 * s, -0.10, 1.80 * s), (-0.25, -0.1, 1))
    f.arm('r', (0.215 * s, 0.03, 1.10 * s), (0.17 * s, -0.04, 0.90 * s), (-0.25, -0.2, -1))
    parts = police_parts(f, seed=39)
    w = f.j['wr_l']
    a = add(w, unit((-0.25, -0.1, 1)), 0.03)
    b = add(w, unit((-0.5, -0.22, 1)), 0.60)
    parts += baton_glow(a, b)
    return parts


# ------------------------------------------------------------------ Biển
def police_sign_alcohol():
    """Biển đứng chốt kiểm tra nồng độ cồn: bảng xanh viền trắng, đầu đỏ, chữ
    vàng, trên giá chữ A; hai đèn quay vàng trên đỉnh giá."""
    w, h = 1200, 700
    img = Image.new('RGBA', (w, h), (24, 70, 160, 255))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((14, 14, w - 15, h - 15), radius=26, outline=(255, 255, 255), width=12)
    d.rectangle((14, 14, w - 15, 196), fill=(200, 30, 34))
    draw_center(d, 'CẢNH SÁT GIAO THÔNG', 'xbold', (60, 40, w - 60, 176), (255, 255, 255))
    draw_center(d, 'KIỂM TRA', 'paytone', (120, 222, w - 120, 352), (255, 230, 70))
    draw_center(d, 'NỒNG ĐỘ CỒN', 'paytone', (60, 352, w - 60, 512), (255, 230, 70))
    draw_center(d, 'ĐỀ NGHỊ DỪNG XE', 'xbold', (120, 548, w - 120, 650), (255, 255, 255))
    parts = [plate('board', 'rect', (0, 0.0, 1.05), (1.20, 0.70), img, thick=0.012)]

    def frame(p):
        x, y, z = p
        q = (np.abs(x) - 0.52, y, z)
        front = capsule(q, (0, 0.03, 1.40), (0, 0.03, 0.0), 0.02)
        back = capsule(q, (0, 0.06, 1.40), (0, 0.55, 0.0), 0.02)
        bar = capsule(p, (-0.52, 0.30, 0.35), (0.52, 0.30, 0.35), 0.015)
        return np.minimum(np.minimum(front, back), bar)
    parts.append(Obj('frame', frame, Mat((200, 202, 206), rough=0.3, metal=0.9)))
    for x in (-0.52, 0.52):
        parts.append(Obj('beacon', (lambda x: lambda p: ellipsoid(p, (x, 0.03, 1.46), (0.045, 0.045, 0.06)))(x),
                         Mat((255, 170, 30), rough=0.15, spec=0.9, coat=0.8, emit=1.1)))
    return parts, []


# ------------------------------------------------------------ Đèn chiếu
def flood_light():
    """Đèn chiếu sáng dã chiến: chân ba càng, cột ống inox, thanh ngang với
    hai pha LED trắng chĩa xuống mặt đường."""
    parts = []
    top = 2.25
    y0 = 0.35

    def legs(p):
        d = None
        for k in range(3):
            a = k * 2 * math.pi / 3 + math.pi / 2
            foot = (0.5 * math.cos(a), y0 + 0.5 * math.sin(a), 0.0)
            c = capsule(p, (0.0, y0, 0.72), foot, 0.016)
            d = c if d is None else np.minimum(d, c)
        return d
    parts.append(Obj('legs', legs, Mat((52, 54, 58), rough=0.4, metal=0.7)))
    parts.append(Obj('mast', lambda p: cyl(p, (0.0, y0), 0.024, 0.65, top + 0.02), Mat((196, 198, 202), rough=0.25, metal=0.9)))
    parts.append(Obj('bar', lambda p: capsule(p, (-0.34, y0, top), (0.34, y0, top), 0.02), Mat((60, 62, 66), rough=0.4, metal=0.7)))
    for x in (-0.22, 0.22):
        def housing(p, x=x):
            return rbox(p, (x, y0 - 0.02, top + 0.12), (0.15, 0.05, 0.11), 0.015)

        def pick(p, n, x=x):
            lens = (n[1] < -0.6) & (np.abs(p[0] - x) < 0.125) & (np.abs(p[2] - top - 0.12) < 0.085)
            return lens.astype(np.int32)
        parts.append(Obj('lamp', housing, [Mat((44, 46, 50), rough=0.35, metal=0.5),
                                           Mat((255, 250, 236), rough=0.05, spec=1.0, coat=1.0, emit=1.8)], pick=pick))
    return parts, []


def _p(fn):
    return lambda: (fn(), [])


bdp.reg('tet_night', 'police_officer_breath', _p(p_police_breath), OFFICER_PPM, 'police')
bdp.reg('tet_night', 'police_officer_baton', _p(p_police_baton), bdp.PERSON_PPM, 'police', glow=5)
bdp.reg('tet_night', 'police_sign_alcohol', police_sign_alcohol, 180, 'police', ss=3, glow=3)
bdp.reg('tet_night', 'flood_light', flood_light, 150, 'police', ss=3, glow=7)

NAMES = ['police_officer_breath', 'police_officer_baton', 'police_sign_alcohol', 'flood_light']

if __name__ == '__main__':
    args = list(sys.argv[1:])
    if '--only' not in args:
        args += ['--only', *NAMES]
    bdp.main(args)
