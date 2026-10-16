"""Hình cho chế độ "Chở cả nhà về quê": vợ ngồi sau, con nhỏ ngồi ghế phụ
phía trước người lái. Dùng lại bộ dò tia SDF của build_vehicles_3d.py (xe
nhìn từ trên), build_traffic_3d.py (tư thế người ngồi sau) và
build_driver_props.py (người đứng nhìn thẳng, chân dung).

Ghi ra:
    assets/images/img_scooter_family.png            xe số chở vợ + con (mũi lên trên,
                                                    cùng khung 64 × 150 với xe người chơi)
    assets/images/img_scooter_family_raincoat.png   cả nhà trùm áo mưa cánh dơi (bé thò
                                                    đầu ra khỏi áo mưa của bố)
    assets/images/img_shadow_scooter_family*.png    bóng đổ theo dáng xe
    assets/images/img_portrait_wife.png             chân dung vợ (thẻ lời nói trên HUD)
    assets/images/img_portrait_kid.png              chân dung bé (bình thường, hơi quấy)
    assets/images/img_portrait_kid_happy.png        bé cười toe
    assets/images/img_portrait_kid_cry.png          bé mếu máo khóc nhè
    assets/images/img_portrait_kid_sleep.png        bé ngủ say
    assets/images/img_item_bim_bim.png              gói bim bim (thực đơn quán)
    assets/images/img_item_hop_sua.png              hộp sữa có ống hút
    assets/images/driver/family_wife_1/2.png        vợ xuống xe vẫy chào, xách túi quà
    assets/images/driver/family_son_1/2.png         bé chạy ùa vào nhà (cảnh về tới nhà)
    assets/images/driver/player_moto_family_side.png  xe máy chở cả nhà nhìn ngang (chạy vào ngõ)

Chạy từ thư mục gốc (cần numpy + pillow):
    python tool/asset_pipeline/build_family_art.py                     # tất cả
    python tool/asset_pipeline/build_family_art.py scooter raincoat    # chọn nhóm
    python tool/asset_pipeline/build_family_art.py --out DIR --zoom 3  # xem thử phóng to
Nhóm: scooter, raincoat, portraits, items, figures, sides.
"""
import math
import os
import random
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_vehicles_3d as v3  # noqa: E402
import build_traffic_3d as t3  # noqa: E402
import build_driver_props as dp  # noqa: E402
import build_driver_views as dv  # noqa: E402
import build_menu_items as mi  # noqa: E402
from build_vehicles import ellipse, line, poly, rrect, shade_rgb  # noqa: E402
from build_vehicles_3d import Mat, Obj, capsule, ellipsoid, fabric, lin, rbox, smin  # noqa: E402

OUT = 'assets/images'

# ================================================================ Màu áo
# Người lái giữ nguyên áo vàng mũ đỏ như xe một mình.
WIFE = dict(helmet=(236, 122, 160), jacket=(232, 220, 200), pants=(46, 50, 70), hair=(30, 24, 20))
WIFE_SCARF = (176, 36, 58)
KID_HELMET = (250, 204, 48)
KID_JACKET = (78, 152, 222)
KID_PANTS = (56, 66, 104)

# ======================================================= Bé ngồi phía trước
# Ghế phụ gắn trên khung xe, ngay trước yên: bé ngồi kẹp giữa hai đùi bố,
# chồm người về trước, hai tay vịn đầu xe. Tư thế dựng theo cỡ người lớn
# quanh hông bé rồi thu nhỏ [KID_SCALE] lần, đặt hông ở [KID_HIP]. Đầu trẻ
# con to so với người nên mũ thu nhỏ ít hơn ([KID_HELMET_SCALE]).
KID_SCALE = 0.6
KID_HELMET_SCALE = 0.74
KID_HIP = (0.0, 0.56, 0.77)
KID_POSE = t3.Pose(head=(0.0, -0.33, 0.77), shoulder=(0.155, -0.21, 0.50), elbow=(0.21, -0.36, 0.33),
                   wrist=(0.165, -0.49, 0.37), palm=(0.16, -0.53, 0.365), hip=(0.0, 0.0, 0.0),
                   knee=(0.15, -0.26, -0.07), foot=(0.135, -0.30, -0.44))


def kid_head():
    hx, hy, hz = KID_POSE.head
    return (KID_HIP[0] + hx * KID_SCALE, KID_HIP[1] + hy * KID_SCALE, KID_HIP[2] + hz * KID_SCALE)


def scaled_helmet(color, center, k):
    """Mũ bảo hiểm trẻ em: mũ nửa đầu thu nhỏ [k] lần quanh [center]."""
    parts = v3.helmet_parts(color, (0.0, 0.0, 0.0))
    return dp.placed(parts, dx=center[0], dy=center[1], dz=center[2], scale=k)


def kid_rider_parts():
    body = [o for o in t3.person_parts(KID_POSE, KID_HELMET, KID_JACKET, KID_PANTS, seed=61)
            if o.name not in ('helmet', 'visor')]
    out = dp.placed(body, dx=KID_HIP[0], dy=KID_HIP[1], dz=KID_HIP[2], scale=KID_SCALE)
    # mũ bé: vàng tươi, tem trắng như mũ người lớn (nhìn từ trên vẫn nổi bật)
    out += scaled_helmet(KID_HELMET, kid_head(), KID_HELMET_SCALE)
    return out


def family_parts():
    parts = v3.bike_parts(v3.PLAYER_BODY) + v3.rider_parts(v3.PLAYER_HELMET, v3.PLAYER_JACKET, v3.PLAYER_PANTS)
    parts += t3.person_parts(t3.WAVE_PILLION, WIFE['helmet'], WIFE['jacket'], WIFE['pants'], hair=WIFE['hair'], seed=62)
    parts += kid_rider_parts()
    return parts


def build_scooter(out):
    return t3.save_ai(t3.moto_scene(family_parts(), ztop=1.80), out, 'img_scooter_family', 1.6)


def build_raincoat(out):
    """Bố trùm áo mưa xanh (bé chui bên trong, thò đầu ra), vợ trùm áo mưa
    hồng của mình phía sau."""
    t0 = time.time()
    under = v3.zoomed(t3.moto_scene(family_parts(), ztop=1.80))
    rgb_u, a_u, z_u = v3.render(under)
    dy = t3.WAVE_PILLION.head[1] - v3.HEAD[1]
    dz = t3.WAVE_PILLION.head[2] - v3.HEAD[2]
    coats = [v3.raincoat_obj((70, 150, 230))] + t3.shifted([v3.raincoat_obj((226, 110, 160))], dy=dy, dz=dz)
    coat = v3.zoomed(t3.moto_scene(coats, ztop=1.80))
    rgb_c, a_c, z_c = v3.render(coat)
    on = (a_c > 0) & (z_c > z_u)
    ac = np.where(on, a_c, 0.0)
    # ánh sáng xuyên qua nilon nhuốm màu áo đang trùm lên
    tint = 0.3 + 0.7 * rgb_c / np.maximum(rgb_c.max(-1, keepdims=True), 1e-6)
    alpha = ac + a_u * (1 - ac)
    pre = rgb_c * ac[..., None] + rgb_u * a_u[..., None] * (1 - ac)[..., None] * np.where(on[..., None], tint, 1.0)
    rgb = pre / np.maximum(alpha, 1e-6)[..., None]
    img = t3.save_ai(under, out, 'img_scooter_family_raincoat', 1.6, layers=(rgb, alpha))
    print(f'  (tổng {time.time() - t0:.1f}s)')
    return img


# ================================================ Xe nhìn ngang (về nhà)
def family_side_model():
    """Xe máy của mình nhìn ngang như player_moto_side (túi đồ, cành đào sau
    baga) nhưng chở thêm vợ ngồi sau (khẩu trang hồng) và bé ngồi trước."""
    parts = v3.bike_parts(v3.PLAYER_BODY)
    parts += t3.person_parts(t3.WAVE_RIDER, v3.PLAYER_HELMET, v3.PLAYER_JACKET, v3.PLAYER_PANTS, gloves=dv.GLOVE, seed=7)
    parts += dv.moto_running_gear('so', 'silver', disc=True)
    parts += dv.face_parts(t3.WAVE_RIDER.head, dv.MASKS[0])
    parts += t3.person_parts(t3.WAVE_PILLION, WIFE['helmet'], WIFE['jacket'], WIFE['pants'], hair=WIFE['hair'], seed=62)
    parts += dv.face_parts(t3.WAVE_PILLION.head, dv.MASKS[3], name='face_wife')
    parts += kid_rider_parts()
    # mặt bé dưới mũ, khẩu trang xanh trẻ con
    face = dv.face_parts((0.0, 0.0, 0.0), (130, 200, 236), name='face_kid')
    head = kid_head()
    parts += dp.placed(face, dx=head[0], dy=head[1], dz=head[2], scale=KID_HELMET_SCALE)
    parts += dv.travel_bag_parts()
    parts += t3.peach_parts((0.0, 1.52, 0.95), (0.24, 0.12, 0.26), 0.85, seed=9, branches=6)
    dv.tag_moto(parts, ['59-X1', '268.79'], 'so')
    return dv.moto_model(parts, 'so', ztop=2.4)


def build_sides(out):
    t0 = time.time()
    dst = os.path.join(out, 'driver')
    os.makedirs(dst, exist_ok=True)
    img, info = dv.shoot(family_side_model(), 'side')
    img.save(f'{dst}/player_moto_family_side.png', optimize=True)
    print(f'player_moto_family_side: {img.size} {time.time() - t0:.1f}s')


# ===================================================== Người đứng (về nhà)
def fam_wife(frame):
    """Vợ ~30 tuổi: áo khoác dạ màu kem, tóc dài, một tay vẫy, một tay xách
    túi quà Tết đỏ."""
    f = dp.Fig(1.58, 'f')
    s = f.s
    dp.wave_arm(f, 'l', frame, high=1.05)
    f.arm('r', (0.20 * s, 0.03, 1.09 * s), (0.225 * s, -0.01, 0.86 * s))
    parts = dp.person(f, WIFE['jacket'], WIFE['pants'], kind='coat', zipper=False, skin='light', scarf=WIFE_SCARF,
                      hair=WIFE['hair'], hair_style='long', shoes=(60, 40, 36), seed=86)
    hand = dp.add(f.j['wr_r'], dp.unit(f.hand_dir['r']), 0.06)
    parts += dp.gift_bag(hand, color=(200, 26, 34), size=(0.12, 0.05, 0.14), seed=3)
    return parts


def fam_son(frame):
    """Bé trai ~5 tuổi áo phao xanh, chạy ùa vào nhà giang tay đòi bà bế
    (khung 2 nhún lên khỏi đất)."""
    f = dp.Fig(1.04, 'm', head=0.80)
    s = f.s
    up = 0.06 if frame else 0.0
    f.arm('l', (-0.24 * s, -0.06, 1.30 * s), (-0.30 * s, -0.14, (1.52 + up) * s), (-0.1, -0.2, 1))
    f.arm('r', (0.24 * s, -0.06, 1.30 * s), (0.30 * s, -0.14, (1.50 - up) * s), (0.1, -0.2, 1))
    lift = 0.0
    if frame == 1:
        lift = 0.07
        f.leg('l', (-0.10 * s, -0.10, 0.50 * s), (-0.09 * s, 0.08, 0.18 * s), (0, -0.8, -0.3))
    parts = dp.person(f, KID_JACKET, KID_PANTS, kind='jacket', puffy=0.016, collar=True, skin='kid',
                      hair_style='short', shoes=(220, 220, 226), seed=87)
    return dp.placed(parts, dz=lift) if lift else parts


def build_figures(out):
    dst = os.path.join(out, 'driver')
    os.makedirs(dst, exist_ok=True)
    for i in range(2):
        for name, fn in (('family_wife', fam_wife), ('family_son', fam_son)):
            img = dp.shoot(dst, f'{name}_{i + 1}', fn(i), dp.FAMILY_PPM, 'family', ss=3)
            print(f'    h_m={img.size[1] / dp.FAMILY_PPM:.3f}')


# ================================================================ Chân dung
def _face_tint(fig, old, mode):
    """Vẽ lại nét mặt trên đầu SDF (chân dung nhìn gần):
    'cry'   bé khóc nhè: mắt nhắm tịt, mày chau, miệng méo há to, nước mắt
            chảy dài hai bên má, má đỏ ửng;
    'happy' bé cười toe: miệng há cười, má hồng;
    'sleep' bé ngủ: mắt nhắm cong xuống, miệng chúm chím;
    'smile' người lớn mỉm cười (khoé miệng cong lên)."""
    hx, hy, hz = fig.j['head']
    k = fig.hs
    ry = 0.095 * k
    ez = hz - 0.006 * k
    dark, lip, inner, tear = lin((40, 26, 24)), lin((176, 70, 72)), lin((92, 24, 30)), lin((214, 236, 250))
    tongue, teeth = lin((222, 110, 110)), lin((246, 242, 236))

    def tint(p, n, alb, idx):
        out = old(p, n, alb, idx)
        x, y, z = p
        front = (n[1] < -0.35) & (y < hy - ry * 0.55)
        ax = np.abs(x - hx)
        u = (ax - 0.030 * k) / (0.013 * k)
        mz = hz - 0.062 * k
        skin = alb * np.array([1.0, 0.92, 0.9])
        if mode in ('cry', 'sleep'):
            # mắt nhắm: xoá chấm mắt cũ bằng màu da rồi vẽ vệt cong
            old_eye = front & (u ** 2 + ((z - ez) / (0.009 * k)) ** 2 < 1)
            out = np.where(old_eye[:, None], skin, out)
            bend = 0.005 if mode == 'cry' else -0.004
            lid = front & (np.abs(u) < 1) & (np.abs(z - (ez + bend * k * (1 - u ** 2))) < 0.0034 * k)
            out = np.where(lid[:, None], dark, out)
        if mode in ('cry', 'happy', 'sleep', 'smile'):
            # xoá miệng mặc định (nét thẳng) trước khi vẽ miệng mới
            old_mouth = front & (ax < 0.02 * k) & (np.abs(z - (hz - 0.064 * k)) < 0.005 * k)
            out = np.where(old_mouth[:, None], skin, out)
        if mode == 'cry':
            bu = (ax - 0.031 * k) / (0.015 * k)
            brow = front & (np.abs(bu) < 1) & (np.abs(z - (ez + 0.024 * k - 0.006 * k * bu)) < 0.0032 * k)
            out = np.where(brow[:, None], alb * 0.4 + dark * 0.6, out)
            m = (ax / (0.024 * k)) ** 2 + ((z - mz) / (0.016 * k)) ** 2
            out = np.where((front & (m < 1.35))[:, None], alb * 0.3 + lip * 0.7, out)
            out = np.where((front & (m < 0.8))[:, None], inner, out)
            tz = ez - z
            tx = ax - (0.034 * k + 0.004 * k * np.sin(tz / k * 60))
            streak = front & (tz > 0.004 * k) & (tz < 0.055 * k) & (np.abs(tx) < 0.0055 * k)
            out = np.where(streak[:, None], out * 0.25 + tear * 0.9, out)
        elif mode == 'happy':
            # miệng cười hình chữ D: mép trên phẳng, mép dưới cong tròn
            w = 0.027 * k
            top = mz + 0.008 * k
            bot = top - 0.022 * k * np.sqrt(np.clip(1 - (ax / w) ** 2, 0, 1))
            mouth = front & (ax < w) & (z < top) & (z > bot)
            rim = front & (ax < w + 0.003 * k) & (z < top + 0.0028 * k) & (z > bot - 0.0028 * k)
            out = np.where(rim[:, None], alb * 0.3 + lip * 0.7, out)
            out = np.where(mouth[:, None], inner, out)
            out = np.where((mouth & (z > top - 0.004 * k))[:, None], teeth, out)
            out = np.where((mouth & (z < bot + 0.006 * k) & (ax < w * 0.6))[:, None], tongue, out)
        elif mode == 'sleep':
            m = (ax / (0.006 * k)) ** 2 + ((z - mz) / (0.005 * k)) ** 2
            out = np.where((front & (m < 1))[:, None], alb * 0.35 + lip * 0.65, out)
        elif mode == 'smile':
            w = 0.019 * k
            curve = mz + 0.002 * k + 0.0055 * k * (ax / w) ** 2
            smile = front & (ax < w) & (np.abs(z - curve) < 0.0024 * k)
            out = np.where(smile[:, None], alb * 0.35 + lip * 0.65, out)
        blush = 0.84 if mode == 'cry' else 0.9
        cheek = front & (((ax - 0.044 * k) / (0.022 * k)) ** 2 + ((z - hz + 0.035 * k) / (0.017 * k)) ** 2 < 1)
        return np.where(cheek[:, None], out * np.array([1.06, blush, blush - 0.02]), out)
    return tint


def _scene_bg(side, kind):
    """Nền nhoè phía sau chân dung: đường quê ngày Tết (bầu trời, hàng cây,
    ruộng, mặt đường) — giống cảnh nhìn qua vai người ngồi trên xe."""
    bg = Image.new('RGB', (side, side), (180, 210, 236))
    d = ImageDraw.Draw(bg)
    for yy in range(side):
        t = yy / side
        if t < 0.55:
            c = (int(150 + 70 * t), int(190 + 50 * t), int(236 - 10 * t))
        elif t < 0.72:
            c = (int(96 - 30 * (t - 0.55)), int(140 - 20 * (t - 0.55)), int(70 - 10 * (t - 0.55)))
        else:
            c = (int(120 + 20 * (t - 0.72)), int(120 + 20 * (t - 0.72)), int(124 + 16 * (t - 0.72)))
        d.line([(0, yy), (side, yy)], fill=c)
    rnd = random.Random(5 if kind == 'wife' else 9)
    for _ in range(14):
        x = rnd.uniform(0, side)
        r = rnd.uniform(0.05, 0.11) * side
        d.ellipse((x - r, side * 0.52 - r, x + r, side * 0.52 + r * 0.6), fill=(60 + rnd.randint(0, 30), 110 + rnd.randint(0, 30), 60))
    # vài cành đào hồng ven đường
    for _ in range(9):
        x = rnd.uniform(0, side)
        y = rnd.uniform(0.32, 0.5) * side
        r = rnd.uniform(0.02, 0.04) * side
        d.ellipse((x - r, y - r, x + r, y + r), fill=(240, 150, 180))
    bg = bg.filter(ImageFilter.GaussianBlur(side / 34))
    a = np.asarray(bg, np.float64)
    yy, xx = np.mgrid[0:side, 0:side] / side
    vig = 1 - 0.25 * (((xx - 0.5) ** 2 + (yy - 0.5) ** 2) / 0.5)
    a = np.clip(a * vig[..., None], 0, 255).astype(np.uint8)
    return Image.fromarray(a).convert('RGBA')


def portrait(parts, fig, path, kind, size=256, ppm=1100.0, top=0.17, bottom=0.46, dx=0.0):
    """Chân dung (ảnh đục) như ảnh mẹ ở thẻ cuộc gọi, cắt sát mặt để còn
    nhận ra nét mặt khi thu nhỏ thành ảnh tròn trên HUD."""
    hx, hy, hz = fig.j['head']
    parts = [o for o in parts if o.name not in ('lower', 'shoes')]
    view = dp.View(parts, ppm, ss=3, catch=0.0, eye=hz, front=0.0)
    rgb, alpha, emit = dp.render(view)
    W, H = view.w, view.h
    img = dp.finish(view, rgb, alpha, emit)
    full = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    full.paste(img, ((W - img.width) // 2, H - img.height))
    side = int((top + bottom) * fig.hs * ppm)
    y0 = H - int((hz + top * fig.hs) * ppm)
    cx = W // 2 + int(dx * ppm)
    crop = full.crop((cx - side // 2, y0, cx - side // 2 + side, y0 + side))
    bg = _scene_bg(side, kind)
    bg.alpha_composite(crop)
    out = bg.convert('RGB').resize((size, size), Image.LANCZOS)
    out.save(path, optimize=True)
    print(f'{os.path.basename(path)}: {size}x{size}', flush=True)
    return out


def _set_face(parts, fig, mode):
    for o in parts:
        if o.name == 'head':
            o.tint = _face_tint(fig, o.tint, mode)


def build_portraits(out):
    t0 = time.time()
    f = dp.Fig(1.58, 'f')
    s = f.s
    # tay phải vén tóc, tay trái thả
    f.arm('r', (0.25 * s, -0.08, 1.16 * s), (0.13 * s, -0.06, 1.42 * s), (-0.3, 0.1, 1))
    wife = dp.person(f, WIFE['jacket'], WIFE['pants'], kind='coat', zipper=False, skin='light', scarf=WIFE_SCARF,
                     hair=WIFE['hair'], hair_style='long', seed=86)
    _set_face(wife, f, 'smile')
    portrait(wife, f, f'{out}/img_portrait_wife.png', 'wife', top=0.15, bottom=0.25)
    # bé: bình thường (hơi quấy), cười toe, khóc nhè, ngủ
    for mode in (None, 'happy', 'cry', 'sleep'):
        k = dp.Fig(1.04, 'm', head=0.80)
        kid = dp.person(k, KID_JACKET, KID_PANTS, kind='jacket', puffy=0.016, collar=True, skin='kid', hair_style='short',
                        seed=87)
        if mode:
            _set_face(kid, k, mode)
        portrait(kid, k, f'{out}/img_portrait_kid{"_" + mode if mode else ""}.png', 'kid', top=0.155, bottom=0.18)
    print(f'  chân dung: {time.time() - t0:.0f}s')


# ================================================================ Món ăn
def bim_bim():
    """Gói bim bim phồng căng: túi nilon cam bóng, mép răng cưa trên dưới,
    hình ngôi sao vàng và mấy miếng snack in trên mặt túi."""
    c = mi.Canvas(mi.S, mi.S)
    bag = (236, 104, 40)
    c.shape(poly([(14, 10), (50, 10), (54, 32), (50, 56), (14, 56), (10, 32)]), bag, puff=9, gloss=1.5)
    for y in (8, 56):
        pts = [(13 + i * 3, y + (2 if i % 2 else -2) * (1 if y > 30 else -1)) for i in range(13)]
        c.shape(line(pts, 2.2), shade_rgb(bag, 0.85), puff=1, gloss=0.6)
    star = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 11 if i % 2 == 0 else 5
        star.append((32 + math.cos(a) * r, 28 + math.sin(a) * r))
    c.shape(poly(star), (252, 214, 60), puff=2, gloss=0.8)
    for x, y in ((22, 44), (32, 47), (42, 43)):
        c.shape(ellipse(x, y, 5, 3.2), (246, 196, 96), puff=2, gloss=0.6)
    c.shape(rrect(16, 13, 20, 50, 2), (255, 255, 255), flat=True, alpha=0.3)
    return c.image()


def hop_sua():
    """Hộp sữa giấy nhỏ: thân trắng, dải xanh lá, nắp xanh dương, ống hút
    gập cắm trên nóc."""
    c = mi.Canvas(mi.S, mi.S)
    c.shape(line([(36, 4), (38, 10), (38, 20)], 2.6), (240, 80, 90), puff=1, gloss=0.8)
    c.shape(poly([(18, 18), (46, 18), (46, 58), (18, 58)]), (246, 246, 242), puff=6, gloss=1.1)
    c.shape(poly([(18, 18), (46, 18), (42, 12), (22, 12)]), (64, 128, 214), puff=3, gloss=1.2)
    c.shape(rrect(18, 36, 46, 47, 1), (80, 176, 90), puff=2, gloss=0.8)
    c.shape(ellipse(32, 28, 7, 5), (64, 128, 214), puff=2, gloss=0.8)
    c.shape(ellipse(32, 28, 3.2, 2.2), (255, 255, 255), flat=True)
    c.shape(rrect(20, 20, 23, 55, 1.5), (255, 255, 255), flat=True, alpha=0.45)
    return c.image()


def build_items(out):
    for name, fn in (('bim_bim', bim_bim), ('hop_sua', hop_sua)):
        fn().save(f'{out}/img_item_{name}.png', optimize=True)
        print(f'img_item_{name}')


BUILDERS = {
    'scooter': build_scooter,
    'raincoat': build_raincoat,
    'portraits': build_portraits,
    'items': build_items,
    'figures': build_figures,
    'sides': build_sides,
}


if __name__ == '__main__':
    args = sys.argv[1:]
    out = OUT
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    if '--zoom' in args:
        i = args.index('--zoom')
        v3.ZOOM = int(args[i + 1])
        args = args[:i] + args[i + 2:]
    os.makedirs(out, exist_ok=True)
    for k in (args or list(BUILDERS)):
        BUILDERS[k](out)
