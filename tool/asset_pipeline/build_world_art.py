"""Dựng vật liệu + hình vẽ tả thực cho cảnh trong game (nhìn từ trên xuống).

Nguồn (đều CC0):
- Vân bề mặt Poly Haven: asphalt, gạch lát, cỏ, đất đỏ, sỏi, bê tông, mái ngói,
  mái tôn (asset_source/tex_polyhaven).
- Cây nhìn từ trên cao: Prime_8 "Realistic top-down trees" (asset_source/trees_prime8).
Phần còn lại (ruộng lúa, vạch sơn mòn, ổ gà, miếng vá, vết dầu, nắp cống,
bồn nước, cây chuối, bóng đổ) vẽ bằng code ở đây.

Cần numpy + pillow:
    .venv/bin/python tool/asset_pipeline/build_world_art.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

SRC = 'asset_source/tex_polyhaven'
TREES = 'asset_source/trees_prime8/extracted'
OUT = 'assets/images'
rng = np.random.default_rng(7)
random.seed(7)


def src(name):
    return Image.open(f'{SRC}/{name}_diff_2k.jpg').convert('RGB')


def save_jpg(img, name, size=512):
    img = img.resize((size, size), Image.LANCZOS)
    img.save(f'{OUT}/{name}.jpg', quality=86, optimize=True)


def save_png(img, name):
    img.save(f'{OUT}/{name}.png', optimize=True)


def tint(img, r, g, b):
    a = np.asarray(img, np.float32) * np.array([r, g, b], np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def periodic_noise(size, sigma, seed=None):
    """Nhiễu mượt lặp liền mạch (lọc Gauss trong miền tần số), giá trị 0..1."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    kernel = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * kernel))
    out -= out.min()
    return out / max(out.max(), 1e-9)


# ------------------------------------------------------------- Vân
def textures():
    asphalt = ImageEnhance.Color(src('aerial_asphalt_01')).enhance(0.55)
    asphalt = ImageEnhance.Brightness(asphalt).enhance(0.78)
    save_jpg(ImageEnhance.Contrast(asphalt).enhance(1.1), 'tex_asphalt')

    pavers = src('concrete_tiles_02')
    save_jpg(ImageEnhance.Brightness(pavers).enhance(1.12), 'tex_paving')
    # Gạch đỏ kiểu vỉa hè phố Việt: nhuộm sang đỏ gạch.
    red = tint(ImageEnhance.Color(pavers).enhance(0.2), 1.32, 0.86, 0.72)
    save_jpg(ImageEnhance.Brightness(red).enhance(1.05), 'tex_paving_red')

    grass = src('leafy_grass')
    grass = tint(ImageEnhance.Color(grass).enhance(1.35), 0.86, 1.08, 0.78)
    save_jpg(ImageEnhance.Brightness(grass).enhance(1.05), 'tex_grass')
    save_jpg(tint(ImageEnhance.Color(src('aerial_grass_rock')).enhance(1.1), 0.9, 1.04, 0.82), 'tex_grass_rough')
    save_jpg(src('red_laterite_soil_stones'), 'tex_laterite')
    save_jpg(src('brown_mud_leaves_01'), 'tex_verge')
    save_jpg(ImageEnhance.Brightness(src('rocky_trail')).enhance(0.95), 'tex_gravel')
    save_jpg(ImageEnhance.Brightness(src('concrete_floor_worn_001')).enhance(1.25), 'tex_concrete')
    save_jpg(src('clay_roof_tiles_02'), 'tex_roof_clay', size=384)
    save_jpg(src('corrugated_iron'), 'tex_roof_iron', size=384)
    paddy()
    paint_wear()


def paddy():
    """Ruộng lúa nhìn từ trên cao: thảm lúa xanh mọc theo hàng, kẽ hàng sẫm
    (nước/bùn lộ ra), màu loang theo từng mảng như ảnh vệ tinh."""
    size = 512
    grass = np.asarray(src('leafy_grass').resize((size, size), Image.LANCZOS), np.float32)
    lum = grass.mean(axis=2, keepdims=True) / 255
    rice = np.array((104, 146, 62), np.float32) * (0.7 + 0.6 * lum)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    # Hàng lúa hơi lượn (cấy tay), 32 hàng trong một ô vân để lặp liền mạch.
    wobble = 1.6 * np.sin(xx / size * math.tau * 3 + 0.7) + 1.0 * np.sin(xx / size * math.tau * 7)
    rows = 0.5 + 0.5 * np.cos((yy + wobble) / size * math.tau * 32)
    gap = np.clip((rows - 0.72) / 0.28, 0, 1) ** 1.5
    water = np.array((70, 86, 70), np.float32)
    patch = periodic_noise(size, 40, seed=11)
    tint = (0.88 + 0.24 * patch)[..., None]
    rgb = rice * tint * (1 - 0.55 * gap[..., None]) + water * 0.55 * gap[..., None]
    # Vài mảng lúa thưa lộ nước.
    sparse = np.clip((periodic_noise(size, 22, seed=12) - 0.72) / 0.2, 0, 1)[..., None]
    rgb = rgb * (1 - sparse * 0.45) + np.array((92, 110, 96)) * sparse * 0.45
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(f'{OUT}/tex_paddy.jpg', quality=86, optimize=True)


def lixi():
    """Phong bao lì xì đỏ in hoa văn vàng, có bóng sáng giấy bóng."""
    w, h, ss = 48, 68, 4
    big = Image.new('RGBA', (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius=4 * ss, fill=(196, 22, 28, 255))
    # Nắp phong bao (tam giác) và đường gấp.
    d.polygon([(0, 0), (w * ss, 0), (w * ss / 2, 22 * ss)], fill=(176, 16, 22, 255))
    d.line([(0, 0), (w * ss / 2, 22 * ss), (w * ss, 0)], fill=(230, 180, 60, 255), width=int(1.2 * ss))
    # Viền vàng + bông hoa mai 5 cánh in nhũ vàng.
    d.rounded_rectangle([3 * ss, 3 * ss, (w - 3) * ss, (h - 3) * ss], radius=3 * ss, outline=(232, 186, 70, 255), width=int(1.2 * ss))
    cx, cy = w * ss / 2, 43 * ss
    for k in range(5):
        a = k * math.tau / 5 - math.pi / 2
        px, py = cx + math.cos(a) * 6 * ss, cy + math.sin(a) * 6 * ss
        d.ellipse([px - 5 * ss, py - 5 * ss, px + 5 * ss, py + 5 * ss], fill=(240, 196, 70, 255))
    d.ellipse([cx - 3 * ss, cy - 3 * ss, cx + 3 * ss, cy + 3 * ss], fill=(200, 120, 30, 255))
    img = big.resize((w, h), Image.LANCZOS)
    a = np.asarray(img, np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    shine = np.exp(-(((xx - yy * 0.55) - 6) / 7) ** 2) * 55  # vệt bóng giấy chéo
    a[..., :3] = np.clip(a[..., :3] + shine[..., None], 0, 255)
    save_png(Image.fromarray(a.astype(np.uint8)), 'img_lixi')


def paint_wear():
    """Mặt nạ sơn vạch kẻ: trắng, độ phủ loang lổ và có chỗ tróc."""
    size = 256
    fine = periodic_noise(size, 1.2, seed=3)
    mid = periodic_noise(size, 6, seed=4)
    alpha = np.clip(0.62 + 0.45 * fine, 0, 1)
    alpha[mid > 0.78] *= 0.25  # mảng tróc sơn
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alpha * 255).astype(np.uint8)
    Image.fromarray(rgba).save(f'{OUT}/tex_paint.png', optimize=True)


# ----------------------------------------------------------- Hình lẻ
def blob_mask(size, radius, roughness, seed, squash=1.0):
    """Hình tròn méo (đường viền theo nhiễu cực), 0..1 có mép mềm."""
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = size / 2
    ang = np.arctan2((yy - cy) / squash, xx - cx)
    dist = np.hypot(xx - cx, (yy - cy) / squash)
    edge = np.full_like(ang, radius)
    for k in range(2, 9):
        edge += radius * roughness / k * np.sin(k * ang + r.uniform(0, math.tau))
    return np.clip((edge - dist) / 2.5, 0, 1)


def to_rgba(rgb, alpha):
    out = np.zeros(rgb.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


def crop_tex(name, size, scale=1.0):
    t = src(name)
    w = int(size * scale * 4)
    return np.asarray(t.crop((0, 0, w, w)).resize((size, size), Image.LANCZOS), np.float32)


def potholes():
    size = 128
    for k in range(3):
        mask = blob_mask(size, 40 - k * 5, 0.22, seed=10 + k, squash=0.75 + 0.12 * k)
        gravel = crop_tex('rocky_trail', size, 0.5) * 0.55
        # Lòng ổ gà tối dần vào giữa, có nước đọng ở đáy.
        yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
        depth = np.clip(1 - np.hypot(xx - size / 2, yy - size / 2) / (size * 0.38), 0, 1)
        rgb = gravel * (1 - 0.35 * depth[..., None])
        puddle = blob_mask(size, 15 - k * 3, 0.3, seed=20 + k)
        rgb = rgb * (1 - puddle[..., None] * 0.6) + np.array((60, 70, 76)) * puddle[..., None] * 0.6
        # Mép: nắng từ tây bắc → mép trên-trái tối (bóng), mép dưới-phải sáng.
        inner = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), np.float32) / 255
        shade = np.roll(np.roll(inner, 3, 0), 3, 1) - inner
        rgb = rgb + shade[..., None] * 140
        rim = np.clip(np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)), np.float32) / 255 - mask, 0, 1)
        broken = rim * (periodic_noise(size, 1.5, seed=30 + k) > 0.45)
        rgb = rgb * (1 - broken[..., None]) + np.array((128, 126, 122)) * broken[..., None]
        alpha = np.clip(mask + broken * 0.9, 0, 1)
        save_png(to_rgba(rgb, alpha), f'img_pothole_{k + 1}')


def road_decals():
    # Miếng vá nhựa (mới hơn, tối hơn) — chữ nhật méo, viền keo.
    for k, (W, H) in enumerate([(150, 90), (110, 110), (200, 70)]):
        asphalt = np.asarray(src('aerial_asphalt_01').crop((300 * k, 0, 300 * k + W * 3, H * 3)).resize((W, H)), np.float32)
        rgb = asphalt.mean(axis=2, keepdims=True) * 0.62 + 6
        rgb = np.repeat(rgb, 3, axis=2)
        jag = periodic_noise(max(W, H), 3, seed=40 + k)[:H, :W]
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        edge = np.minimum.reduce([xx, yy, W - 1 - xx, H - 1 - yy]) - jag * 9
        alpha = np.clip(edge / 3, 0, 1) * 0.9
        seal = np.clip(1 - np.abs(edge - 1.5) / 1.5, 0, 1)
        rgb = rgb * (1 - seal[..., None] * 0.5)
        save_png(to_rgba(rgb, np.maximum(alpha, seal * 0.8)), f'img_road_patch_{k + 1}')
    # Vết dầu loang.
    for k in range(2):
        size = 96
        mask = blob_mask(size, 30, 0.7, seed=50 + k, squash=0.6)
        soft = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), np.float32) / 255
        noise = periodic_noise(size, 4, seed=60 + k)
        save_png(to_rgba(np.full((size, size, 3), 18.0), soft * (0.25 + 0.25 * noise)), f'img_oil_{k + 1}')
    manhole()
    drain()


def manhole():
    size, ss = 64, 4
    big = Image.new('RGBA', (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = size * ss / 2
    r = size * ss / 2 - 2 * ss
    d.ellipse([c - r, c - r, c + r, c + r], fill=(96, 92, 88, 255))
    r2 = r - 4 * ss
    d.ellipse([c - r2, c - r2, c + r2, c + r2], fill=(58, 56, 54, 255))
    for k in range(-4, 5):
        y = c + k * 5 * ss
        half = math.sqrt(max(0, r2 * r2 - (y - c) ** 2)) - 3 * ss
        if half > 0:
            d.line([(c - half, y), (c + half, y)], fill=(80, 77, 73, 255), width=2 * ss)
    big = big.resize((size, size), Image.LANCZOS)
    save_png(big, 'img_manhole')


def drain():
    w, h, ss = 60, 22, 4
    big = Image.new('RGBA', (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius=3 * ss, fill=(110, 108, 104, 255))
    d.rectangle([3 * ss, 3 * ss, (w - 3) * ss, (h - 3) * ss], fill=(28, 28, 28, 255))
    for x in range(6, w - 4, 5):
        d.rectangle([x * ss, 3 * ss, (x + 2) * ss, (h - 3) * ss], fill=(92, 90, 86, 255))
    save_png(big.resize((w, h), Image.LANCZOS), 'img_drain')


def shadow_blob():
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dist = np.hypot(xx - size / 2, yy - size / 2) / (size / 2)
    alpha = np.clip(1 - dist, 0, 1) ** 1.6
    save_png(to_rgba(np.zeros((size, size, 3)), alpha), 'img_shadow')
    # Bóng chữ nhật mềm cho xe: kéo giãn theo chiều dài khi vẽ.
    w, h = 64, 128
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = np.clip((np.abs(xx - w / 2) - (w / 2 - 14)) / 14, 0, 1)
    dy = np.clip((np.abs(yy - h / 2) - (h / 2 - 14)) / 14, 0, 1)
    alpha = np.clip(1 - np.hypot(dx, dy), 0, 1) ** 1.5
    save_png(to_rgba(np.zeros((h, w, 3)), alpha), 'img_shadow_box')


def water_tanks():
    # Bồn inox nằm ngang trên mái nhà.
    w, h = 96, 40
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = (yy - h / 2) / (h / 2)
    shine = 150 + 95 * np.exp(-((t + 0.25) / 0.35) ** 2) - 40 * np.clip(t, 0, 1)
    rgb = np.repeat(shine[..., None], 3, axis=2) * np.array((0.98, 1.0, 1.03))
    for x in (w * 0.22, w * 0.5, w * 0.78):
        band = np.exp(-((xx - x) / 1.3) ** 2)
        rgb = rgb * (1 - 0.25 * band[..., None])
    ex = np.clip(1 - np.maximum(0, np.abs(xx - w / 2) - (w / 2 - h / 2)) ** 2 / (h / 2) ** 2 - t * t, 0, 1)
    alpha = np.clip(ex * 6, 0, 1)
    save_png(to_rgba(rgb, alpha), 'img_water_tank')
    # Bồn đứng (nhìn thấy nắp tròn).
    size = 56
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dist = np.hypot(xx - size / 2 + 6, yy - size / 2 + 6) / (size / 2)
    rgb = np.repeat((235 - 90 * np.clip(dist, 0, 1.3))[..., None], 3, axis=2)
    lid = np.hypot(xx - size / 2, yy - size / 2) < size * 0.17
    rgb[lid] = rgb[lid] * 0.82
    alpha = np.clip((size / 2 - np.hypot(xx - size / 2, yy - size / 2)) / 1.5, 0, 1)
    save_png(to_rgba(rgb, alpha), 'img_water_tank_round')


def banana():
    """Cây chuối nhìn từ trên: tàu lá dài toả ra, gốc tối ngọn sáng, có gân
    giữa, mép rách; vẽ từng lá bằng mặt nạ rồi tô vân cỏ cho thật."""
    size = 200
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    leafy = crop_tex('leafy_grass', size, 0.6) / 255
    for k in range(2):
        r = random.Random(70 + k)
        rgb = np.zeros((size, size, 3), np.float32)
        alpha = np.zeros((size, size), np.float32)
        c = size / 2
        leaves = 8 + k
        order = list(range(leaves))
        r.shuffle(order)
        for i in order:
            ang = i / leaves * math.tau + r.uniform(-0.2, 0.2)
            length = r.uniform(0.38, 0.49) * size
            width = r.uniform(0.085, 0.11) * size
            ux, uy = math.cos(ang), math.sin(ang)
            along = (xx - c) * ux + (yy - c) * uy
            across = -(xx - c) * uy + (yy - c) * ux
            t = np.clip(along / length, 0, 1)
            half = width * np.clip(np.sin(np.pi * np.clip(t * 1.1, 0, 1)), 0, 1) ** 0.6
            # Vết rách: dải hẹp cắt ngang lá.
            tear = np.sin(along * 0.9 + r.uniform(0, 6)) > 0.93
            inside = (along > 2) & (along < length) & (np.abs(across) < half) & ~(tear & (np.abs(across) > 3))
            m = inside.astype(np.float32)
            base = np.array((0.30, 0.56, 0.20)) + r.uniform(-0.04, 0.04)
            shade = 0.6 + 0.55 * t  # gốc lá tối (khuất), ngọn sáng
            side = np.where(across > 0, 1.0, 0.82)  # nửa lá xa nắng tối hơn
            col = base * (shade * side)[..., None] * (0.75 + 0.5 * leafy)
            rib = (np.abs(across) < 1.6) & inside
            col[rib] = np.array((0.72, 0.80, 0.45))
            edge = inside & (np.abs(across) > half - 1.5)
            col[edge] *= 0.7
            rgb = rgb * (1 - m[..., None]) + col * 255 * m[..., None]
            alpha = np.maximum(alpha, m)
        img = to_rgba(rgb, alpha).filter(ImageFilter.SMOOTH)
        save_png(img, f'img_banana_{k + 1}')


def trees():
    names = sorted(os.listdir(TREES))
    for k, name in enumerate(names):
        img = Image.open(f'{TREES}/{name}').convert('RGBA')
        img = ImageEnhance.Color(img).enhance(1.08)
        save_png(img, f'img_tree_{k + 1:02d}')
    return len(names)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    textures()
    lixi()
    potholes()
    road_decals()
    shadow_blob()
    water_tanks()
    banana()
    print('trees', trees())
