"""Danh sách mô hình GLB làm xe AI (ô tô, SUV, bán tải) và cách đặt vào game.

Mô hình lấy từ Objaverse (bản sao các mô hình Sketchfab, tất cả giấy phép
CC BY 4.0 — phải ghi công, xem CREDITS.md). Không commit tệp .glb (vài MB đến
chục MB mỗi tệp): fetch_models.py tải về thư mục models/ (đã gitignore).

Mỗi mục trong FLEET là một ảnh xe trong game:
    name    tên ảnh (img_<name>.png nhìn từ trên + driver/<name>_*.png ghế lái)
    model   khoá trong MODELS
    length  chiều dài (mét) mô hình được co về, cho khớp hộp va chạm của loại xe
    frame   (rộng, cao, mép mũi xe cách mép trên) điểm ảnh của ảnh nhìn từ trên
            — giữ đúng khung ảnh cũ nên không phải sửa code Dart
    turn    độ xoay thêm quanh trục đứng để mũi xe hướng lên đầu ảnh
    tint    (tuỳ chọn) đổi màu sơn: {match: regex tên vật liệu, color}
"""

# khoá: (uid Objaverse, đường dẫn tệp trong kho allenai/objaverse, tên, tác giả)
MODELS = {
    'explorer': ('40903b09601c4e15b97f8e43ca42d449', 'glbs/000-041', 'FPIU 2020 Version 2', 'David_Holiday'),
    'rx300': ('6f2f754c78794734b794237913ba97cc', 'glbs/000-080', 'Lexus RX300', 'David_Holiday'),
    'escalade': ('7c5516c76bd441d998af76e2240a2b8d', 'glbs/000-150', '2009 Cadillac Escalade', 'nekkantisrikar2007'),
    'vito': ('237d72410cab4732ab98446ded360ee6', 'glbs/000-138', "D3S MB Vito (W447) '14", 'DANZ | D3S DESIGN'),
    'dmax': ('ebb7ce30d778471184defaf0719cb3df', 'glbs/000-153', "The all new Isuzu D'Max 2021 Model.", 'MERCEDES TRUCKS LLC'),
    'coach_white': ('852a63f852584448a49d643ae944506e', 'glbs/000-056', 'Autobus ABCO', 'BgirlKittyEmo'),
    'coach_silver': ('60c006be9a834849895438f15d4927c0', 'glbs/000-009', 'Busscar Micruss', 'Red Fox / nokillnando'),
    'coach_blue': ('21262813724e401b88333d381c4626f7', 'glbs/000-106', 'Karosa C734', 'Jan Bláha'),
    'flatbed': ('bee50cc724a640328020bf31be85e91d', 'glbs/000-082', 'Truck(Textured)', 'Aegin'),
    'box_grey': ('bfdd04a15273482694e7319ca98fc468', 'glbs/000-113', 'IVECO Bus', 'Weitstern'),
    's10': ('5e77a057585d47309d2605934197669f', 'glbs/000-021', 'Chevrolet S10', 'David_Holiday'),
}

CAR_FRAME = (98, 214, 2.4)       # sedan / SUV / MPV: img_sedan_*.png, img_mini_van.png
PICKUP_FRAME = (111, 250, 1.0)   # bán tải: img_pickup_*.png
BUS_FRAME = (66, 214, 1.0)       # xe khách: img_bus_*.png (ppm riêng vì xe dài 8,5 m)
TRUCK_FRAME = (62, 184, 1.0)     # xe tải / container: img_truck.png, img_container_*.png


def explorer(name, color):
    """Explorer đổi màu sơn: vật liệu thân (ảnh Exterior_01 + màu trắng wire_115115115)."""
    return dict(name=name, model='explorer', length=4.45, frame=CAR_FRAME, turn=180,
                tint=dict(match=r'(Exterior_01|wire_115115115)$', color=color, dropMap=True, metalness=0.3, roughness=0.38))


FLEET = [
    dict(name='sedan_white', model='explorer', length=4.45, frame=CAR_FRAME, turn=180),
    dict(name='sedan_silver', model='rx300', length=4.45, frame=CAR_FRAME, turn=180),
    dict(name='sedan_black', model='escalade', length=4.55, frame=CAR_FRAME, turn=180),
    explorer('sedan_blue', '#2a4ea0'),
    explorer('sedan_brown', '#6b4a36'),
    explorer('sedan_gray', '#5f666d'),
    explorer('sedan_green', '#2f5f46'),
    dict(name='mini_van', model='vito', length=4.5, frame=CAR_FRAME, turn=0),
    # Bán tải: chở cây quất / cành đào / thùng hàng như ảnh cũ (hàng dựng bằng code, vị trí thùng theo từng xe).
    dict(name='pickup_blue', model='s10', length=5.1, frame=PICKUP_FRAME, turn=180,
         tint=dict(match=r'^material_(0|5|11|13)$', color='#1f4fb0'), cargo=dict(kind='kumquat', z=1.0, y=0.52, size=0.78, seed=61)),
    dict(name='pickup_white', model='s10', length=5.1, frame=PICKUP_FRAME, turn=180,
         cargo=dict(kind='peach', z=1.0, y=0.52, size=0.85, seed=62)),
    # Tên "gray" giữ nguyên cho khớp code; xe này màu cam nhạt (Isuzu D-Max).
    dict(name='pickup_gray', model='dmax', length=5.2, frame=PICKUP_FRAME, turn=180,
         cargo=dict(kind='boxes', z=1.55, y=0.86, size=1.0, seed=63)),
]

FLEET += [
    dict(name='bus_1', model='coach_white', length=8.5, frame=BUS_FRAME, top_ppm=25.0, turn=180),
    dict(name='bus_2', model='coach_silver', length=8.5, frame=BUS_FRAME, top_ppm=25.0, turn=180, squeeze=0.9),
    dict(name='bus_3', model='coach_blue', length=8.5, frame=BUS_FRAME, top_ppm=25.0, turn=180),
    dict(name='truck', model='flatbed', length=6.5, frame=TRUCK_FRAME, top_ppm=28.0, turn=180, squeeze=0.85),
    dict(name='container_1', model='flatbed', length=6.5, frame=TRUCK_FRAME, top_ppm=28.0, turn=180, squeeze=0.85,
         cargo=dict(kind='boxes', z=1.7, y=1.3, size=1.15, seed=71)),
    dict(name='container_2', model='box_grey', length=8.11, frame=TRUCK_FRAME, top_ppm=22.4, turn=180),
]
