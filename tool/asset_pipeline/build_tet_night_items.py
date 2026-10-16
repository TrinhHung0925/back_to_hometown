"""Hình cho đêm 30 Tết và trời rét miền Bắc (vẽ bằng code, cùng bộ đổ sáng
theo khối của build_menu_items.py):

- img_item_ruou.png: be rượu gốm và chén rượu mừng xuân (thực đơn quán).
- img_item_gang_tay.png: đôi găng tay len (bán ở quán, cây xăng, xăng lẻ).
- tex_frost.png: vân sương muối lặp liền mạch (phủ lên ruộng, bờ cỏ lúc
  rạng sáng trời rét), trắng xanh, loang lổ, lấm tấm tinh thể băng.

Chạy từ thư mục gốc:
    .venv/bin/python tool/asset_pipeline/build_tet_night_items.py
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_vehicles import Canvas, ellipse, line, poly, rrect, shade_rgb  # noqa: E402

OUT = 'assets/images'
S = 64


def ruou():
    """Be rượu sành nâu men bóng, nút lá chuối; chén sứ trắng hoa lam đầy
    rượu trong."""
    c = Canvas(S, S)
    jug = (122, 70, 40)
    # thân be: bầu tròn, cổ thon
    c.shape(ellipse(24, 38, 16, 17), jug, puff=7, gloss=1.2)
    c.shape(rrect(19, 10, 29, 24, 3), shade_rgb(jug, 0.95), puff=3, gloss=1.0)
    c.shape(ellipse(24, 10, 6.5, 2.6), shade_rgb(jug, 1.15), puff=1.5, gloss=1.0)
    # nút lá chuối buộc lạt
    c.shape(poly([(19, 9), (29, 9), (27, 2), (21, 2)]), (96, 140, 70), puff=2, gloss=0.4)
    c.shape(line([(19, 9.5), (29, 9.5)], 1.6), (200, 170, 110), flat=True)
    # nhãn đỏ dán giữa bầu
    c.shape(rrect(16, 32, 32, 44, 2), (196, 30, 34), puff=2, gloss=0.6)
    c.shape(rrect(18.5, 34.5, 29.5, 41.5, 1), (240, 200, 90), flat=True, alpha=0.85)
    # chén sứ: miệng loe, chân nhỏ, rượu trong ánh vàng nhạt
    porcelain = (242, 244, 246)
    c.shape(poly([(36, 40), (60, 40), (55, 54), (41, 54)]), porcelain, puff=4, gloss=1.3)
    c.shape(rrect(43, 53, 53, 57, 1.5), shade_rgb(porcelain, 0.9), puff=1.5, gloss=0.8)
    c.shape(ellipse(48, 40, 12, 3.2), (226, 214, 160), puff=1.5, gloss=1.6, alpha=0.95)
    for x in (41, 48, 55):
        c.shape(line([(x - 2, 45), (x + 1, 49)], 1.4), (60, 100, 180), flat=True, alpha=0.8)
    c.shape(line([(38.5, 42.5), (57.5, 42.5)], 1.0), (60, 100, 180), flat=True, alpha=0.7)
    return c.image()


def gang_tay():
    """Đôi găng tay len đỏ đô sọc trắng, cổ chun xám (chiếc sau nằm chéo)."""
    rnd = random.Random(7)
    c = Canvas(S, S)
    wool = (178, 34, 44)

    def glove(dx, dy, rot, color):
        def pt(x, y):
            a = rot
            x, y = x - 26, y - 34
            return (26 + dx + x * math.cos(a) - y * math.sin(a), 34 + dy + x * math.sin(a) + y * math.cos(a))
        palm = [pt(14, 30), pt(36, 30), pt(37, 50), pt(13, 50)]
        c.shape(poly(palm), color, puff=5, gloss=0.3, rough=0.05)
        for i, x in enumerate((15.5, 21.5, 27.5, 33)):
            top = 12 if i in (1, 2) else 15
            c.shape(line([pt(x, 31), pt(x, top)], 5.6), color, puff=2.5, gloss=0.3, rough=0.05)
        c.shape(line([pt(13, 40), pt(5, 30)], 6), color, puff=2.5, gloss=0.3, rough=0.05)
        # cổ chun sọc
        c.shape(poly([pt(13, 49), pt(37, 49), pt(37, 58), pt(13, 58)]), (150, 150, 156), puff=2, rough=0.06)
        for y in (51, 54.5):
            c.shape(line([pt(13.5, y), pt(36.5, y)], 1.0), (110, 110, 116), flat=True, alpha=0.7)
        # sọc trắng ngang mu bàn tay, mũi len
        c.shape(line([pt(14, 41), pt(36, 41)], 2.2), (240, 236, 228), flat=True, alpha=0.9)
        for _ in range(26):
            x, y = rnd.uniform(14, 36), rnd.uniform(16, 48)
            c.shape(line([pt(x, y), pt(x + 1.2, y + 1.6)], 0.8), shade_rgb(color, 0.72), flat=True, alpha=0.5)

    glove(8, 2, 0.32, shade_rgb(wool, 0.9))
    glove(-4, -2, -0.12, wool)
    return c.image()


def frost_tile(size=256, seed=11):
    """Vân sương muối lặp liền mạch: lớp băng mỏng loang theo vệt (lọc nhiễu
    trắng bằng FFT nên khớp mép), thêm hạt tinh thể lấm tấm lấp lánh."""
    rng = np.random.default_rng(seed)

    def periodic_noise(scale):
        n = rng.normal(0, 1, (size, size))
        f = np.fft.fftfreq(size)
        fx, fy = np.meshgrid(f, f)
        r = np.sqrt(fx * fx + fy * fy)
        spec = np.fft.fft2(n) * np.exp(-(r * scale) ** 2)
        out = np.real(np.fft.ifft2(spec))
        return (out - out.mean()) / (out.std() + 1e-9)

    big = periodic_noise(22)
    mid = periodic_noise(9)
    fine = periodic_noise(3)
    cover = 0.55 * big + 0.3 * mid + 0.15 * fine
    cover = 1 / (1 + np.exp(-3.2 * (cover + 0.15)))  # loang: chỗ dày chỗ mỏng
    alpha = 0.16 + 0.76 * cover
    # hạt tinh thể: chấm sáng nhỏ, có hạt kéo thành vệt kim băng ngắn
    sparkle = np.zeros((size, size))
    for _ in range(1400):
        x, y = rng.integers(0, size, 2)
        k = rng.uniform(0.4, 1.0)
        sparkle[y, x] = max(sparkle[y, x], k)
        if rng.random() < 0.35:
            dx, dy = rng.choice([(1, 0), (0, 1), (1, 1), (1, -1)])
            for t in range(1, rng.integers(2, 4)):
                sparkle[(y + dy * t) % size, (x + dx * t) % size] = max(sparkle[(y + dy * t) % size, (x + dx * t) % size], k * 0.7)
    alpha = np.clip(alpha + 0.35 * sparkle, 0, 1)
    tint = np.clip(0.5 + 0.5 * mid, 0, 1)[..., None]
    white = np.array([238, 244, 250], np.float64)
    blue = np.array([206, 222, 238], np.float64)
    rgb = blue * (1 - tint) + white * tint
    rgb = np.clip(rgb + 18 * sparkle[..., None], 0, 255)
    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = rgb.astype(np.uint8)
    out[..., 3] = (alpha * 255).astype(np.uint8)
    return Image.fromarray(out)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    ruou().save(f'{out}/img_item_ruou.png', optimize=True)
    gang_tay().save(f'{out}/img_item_gang_tay.png', optimize=True)
    frost_tile().save(f'{out}/tex_frost.png', optimize=True)
    print('done')
