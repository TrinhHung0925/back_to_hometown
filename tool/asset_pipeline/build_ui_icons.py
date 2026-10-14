"""Chuẩn bị icon/nút điều khiển cho game.

- Lấy nút, cần lái, icon từ Kenney Mobile Controls (CC0), bản Large (2×).
- Đế cần lái chỉ giữ mũi tên lên/xuống (cần lái của game chỉ kéo dọc).
- Tự vẽ icon còi và đèn pha theo phong cách icon trắng của Kenney
  (gói Kenney không có hai icon này).

Chạy từ thư mục gốc project:
    python3 -E tool/asset_pipeline/build_ui_icons.py
"""
import os
import shutil

from PIL import Image, ImageDraw

SRC = 'asset_source/kenney_mobile_controls/extracted/Sprites'
OUT = 'assets/icons'
LARGE = 'Large (2×)'

COPY = [
    ('Style H', 'button_circle.png', 'ic_button_circle.png'),
    ('Style H', 'joystick_circle_nub_b.png', 'ic_joystick_nub.png'),
    ('Icons', 'icon_pedal.png', 'ic_pedal_gas.png'),
    ('Icons', 'icon_pedal_brake.png', 'ic_pedal_brake.png'),
    ('Icons', 'icon_talk.png', 'ic_chat.png'),
    ('Icons', 'icon_pause.png', 'ic_pause.png'),
    ('Icons', 'icon_play.png', 'ic_play.png'),
    ('Icons', 'icon_arrow_rotate.png', 'ic_retry.png'),
    ('Icons', 'icon_menu.png', 'ic_menu.png'),
    ('Icons', 'icon_star.png', 'ic_star.png'),
    ('Icons', 'icon_sound.png', 'ic_sound_on.png'),
    ('Icons', 'icon_sound_disabled.png', 'ic_sound_off.png'),
    ('Icons', 'icon_search.png', 'ic_search.png'),
    ('Icons', 'icon_crosshair.png', 'ic_target.png'),
    ('Icons', 'icon_size_smaller.png', 'ic_zoom_out.png'),
    ('Icons', 'icon_cross.png', 'ic_close.png'),
    ('Icons', 'icon_checkmark.png', 'ic_check.png'),
    ('Icons', 'icon_money.png', 'ic_money.png'),
    ('Icons', 'icon_arrow.png', 'ic_arrow.png'),
]

# Màu icon Kenney: trắng, đáy hơi ngả xanh xám.
TOP = (255, 255, 255, 255)
BOTTOM = (214, 228, 233, 255)


def vertical_pad():
    """Đế cần lái: xoá mũi tên trái/phải, giữ mũi tên lên/xuống."""
    pad = Image.open(os.path.join(SRC, 'Style H', LARGE, 'joystick_circle_pad_a.png')).convert('RGBA')
    w, h = pad.size
    fill = pad.getpixel((w // 2, h // 2))
    draw = ImageDraw.Draw(pad)
    for cx in (int(w * 0.17), int(w * 0.83)):
        draw.rectangle([cx - 14, h // 2 - 16, cx + 14, h // 2 + 16], fill=fill)
    pad.save(os.path.join(OUT, 'ic_joystick_pad.png'), optimize=True)


def gradient_fill(mask):
    """Tô mask bằng dải màu trắng → xanh xám nhạt như icon Kenney."""
    w, h = mask.size
    grad = Image.new('RGBA', (w, h))
    for y in range(h):
        t = y / (h - 1)
        color = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(4))
        ImageDraw.Draw(grad).line([(0, y), (w, y)], fill=color)
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def save_icon(draw_fn, name, size=96, ss=4):
    big = size * ss
    mask = Image.new('L', (big, big), 0)
    draw_fn(ImageDraw.Draw(mask), big)
    mask = mask.resize((size, size), Image.LANCZOS)
    gradient_fill(mask).save(os.path.join(OUT, name), optimize=True)


def draw_horn(d, s):
    u = s / 96
    # Cuống kèn + loa kèn loe ra bên phải, nét đậm như icon Kenney.
    d.rounded_rectangle([4 * u, 36 * u, 26 * u, 60 * u], radius=5 * u, fill=255)
    d.polygon([(22 * u, 37 * u), (58 * u, 12 * u), (58 * u, 84 * u), (22 * u, 59 * u)], fill=255)
    d.rounded_rectangle([54 * u, 8 * u, 66 * u, 88 * u], radius=6 * u, fill=255)
    # Hai sóng âm.
    for r in (12, 24):
        box = [70 * u - r * u, 48 * u - r * u - 4 * u, 70 * u + r * u + 4 * u, 48 * u + r * u + 4 * u]
        d.arc(box, start=-55, end=55, fill=255, width=int(8 * u))


def draw_headlight(d, s):
    u = s / 96
    # Đèn hình chữ D quay sang phải + 4 tia sáng.
    d.pieslice([30 * u, 10 * u, 94 * u, 86 * u], start=-90, end=90, fill=255)
    d.rectangle([54 * u, 10 * u, 63 * u, 86 * u], fill=255)
    for y in (18, 37, 56, 75):
        d.rounded_rectangle([2 * u, (y - 5) * u, 44 * u, (y + 5) * u], radius=5 * u, fill=255)


def draw_swap(d, s):
    u = s / 96
    # Hai mũi tên ngược chiều: lên bên trái, xuống bên phải.
    for x, up in ((30, True), (66, False)):
        tip, tail = (8, 88) if up else (88, 8)
        d.rounded_rectangle([(x - 6) * u, min(tip, tail) * u + (14 if up else 0) * u,
                             (x + 6) * u, max(tip, tail) * u - (0 if up else 14) * u], radius=5 * u, fill=255)
        head = 30 if up else -30
        d.polygon([(x * u, tip * u), ((x - 20) * u, (tip + head) * u), ((x + 20) * u, (tip + head) * u)], fill=255)


def main():
    os.makedirs(OUT, exist_ok=True)
    for folder, src, dst in COPY:
        shutil.copyfile(os.path.join(SRC, folder, LARGE, src), os.path.join(OUT, dst))
    vertical_pad()
    save_icon(draw_horn, 'ic_horn.png')
    save_icon(draw_headlight, 'ic_headlight.png')
    save_icon(draw_swap, 'ic_swap.png')
    print('done')


if __name__ == '__main__':
    main()
