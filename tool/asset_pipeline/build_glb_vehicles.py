"""Xe AI (sedan / SUV, đa dụng, bán tải) dựng từ mô hình GLB thật bằng three.js
chạy trong Chrome không đầu — thay cho bản dò tia SDF tự vẽ (xe nhìn "giả").
Quy trình giống tool/asset_pipeline/glb/README.md:

    python tool/asset_pipeline/glb/fetch_models.py      # tải GLB (1 lần)
    (cd tool/asset_pipeline/glb && npm install)           # puppeteer-core (1 lần)
    python tool/asset_pipeline/build_glb_vehicles.py            # tất cả
    python tool/asset_pipeline/build_glb_vehicles.py pickup_blue mini_van   # chọn vài xe

Ghi đè (giữ nguyên tên tệp, kích thước khung và hướng mũi xe lên trên như ảnh cũ
nên không phải sửa code Dart; chỉ ảnh của các xe liệt kê trong glb/glb_fleet.py):
    assets/images/img_<xe>.png                 nhìn từ trên xuống
    assets/images/img_shadow_<xe>.png          bóng đổ theo dáng xe
    assets/images/driver/<xe>_{rear,front,side,l25..r145}.png   góc nhìn ghế lái
    assets/images/driver/billboards.json, vehicle_lamps.json    điểm đất và đèn
Cần numpy + pillow + node 20+ + Google Chrome.
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, 'glb'))
import build_vehicles_3d as v3  # noqa: E402  (hàm bóng đổ dùng chung)
from glb_fleet import FLEET  # noqa: E402
from fetch_models import path_of  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
IMAGES = os.path.join(ROOT, 'assets', 'images')
DRIVER = os.path.join(IMAGES, 'driver')
RAW = os.path.join(HERE, 'glb', 'raw')
SS = 3          # số mẫu mỗi chiều trên một điểm ảnh (ảnh ghế lái)
SS_TOP = 4      # như trên, ảnh nhìn từ trên
ELEV = 7.0      # góc ngẩng máy ảnh ghế lái (độ), như build_driver_views.BB_ELEV
PPM = 80.0      # điểm ảnh / mét của ảnh ghế lái
PAD = 3
VIEWS = {'rear': 0, 'front': 180, 'side': 90}
for _a in (25, 50, 75, 115, 145):
    VIEWS[f'l{_a}'] = _a
    VIEWS[f'r{_a}'] = -_a
TOP_PPM = 47.0  # build_vehicles_3d.CAR_PPM
SHADOW_SIGMA = 2.2


def load_premul(path, ss):
    """PNG thô (siêu mẫu) → (rgb premultiplied float, alpha float) rồi thu nhỏ [ss] lần."""
    im = np.asarray(Image.open(path).convert('RGBA'), np.float32) / 255.0
    a = im[..., 3]
    pre = im[..., :3] * a[..., None]
    H, W = a.shape
    return pre, a, W // ss, H // ss


def downsample(pre, a, w, h, ss):
    p = pre.reshape(h, ss, w, ss, 3).mean((1, 3))
    al = a.reshape(h, ss, w, ss).mean((1, 3))
    rgb = np.where(al[..., None] > 1e-4, p / np.maximum(al[..., None], 1e-4), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(al * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


def write_jobs(entries):
    from glb_fleet import MODELS  # noqa: F401
    jobs = []
    for e in entries:
        w, h, nose = e['frame']
        jobs.append({
            'name': e['name'], 'glb': path_of(e['model']), 'length': e['length'], 'turn': e.get('turn', 0),
            'tint': e.get('tint'), 'lampSpec': e.get('lamps', {}), 'cargo': e.get('cargo'),
            'top': {'w': w, 'h': h, 'ppm': TOP_PPM, 'noseY': nose},
            'yaws': sorted(set(VIEWS.values())),
        })
    spec = {'out': RAW, 'ss': SS, 'elev': ELEV, 'ppm': PPM, 'jobs': jobs}
    # ảnh nhìn từ trên dùng SS_TOP: render.mjs nhận ss chung nên chạy hai lượt
    return spec


def run_render(entries):
    spec = write_jobs(entries)
    os.makedirs(RAW, exist_ok=True)
    # Lượt 1: ảnh nhìn từ trên (ss = SS_TOP, không có góc ghế lái)
    top_spec = dict(spec, ss=SS_TOP, jobs=[dict(j, yaws=[]) for j in spec['jobs']], out=os.path.join(RAW, 'top'))
    # Lượt 2: góc ghế lái (ss = SS, không cần ảnh trên)
    view_spec = dict(spec, out=os.path.join(RAW, 'view'), jobs=[dict(j, top=None) for j in spec['jobs']])
    for name, s in (('top', top_spec), ('view', view_spec)):
        path = os.path.join(RAW, f'jobs_{name}.json')
        with open(path, 'w') as f:
            json.dump(s, f)
        subprocess.run(['node', os.path.join(HERE, 'glb', 'render.mjs'), path], check=True, cwd=os.path.join(HERE, 'glb'))


def build_top(e):
    pre, a, w, h = load_premul(os.path.join(RAW, 'top', f'{e["name"]}_top.png'), SS_TOP)
    img = downsample(pre, a, w, h, SS_TOP)
    img.save(os.path.join(IMAGES, f'img_{e["name"]}.png'), optimize=True)
    v3.shadow_png(a, w, h, SHADOW_SIGMA).save(os.path.join(IMAGES, f'img_shadow_{e["name"]}.png'), optimize=True)
    return img


def build_views(e, meta, boards, lamps):
    name = e['name']
    entry = {}
    lamp_entry = {}
    for view, yaw in VIEWS.items():
        pre, a, w, h = load_premul(os.path.join(RAW, 'view', f'{name}_v{yaw}.png'), SS)
        img = downsample(pre, a, w, h, SS)
        al = np.asarray(img)[..., 3]
        ys, xs = np.nonzero(al > 0)
        W, H = img.size
        left, right = xs.min(), W - 1 - xs.max()
        cut = int(max(0, min(left, right) - PAD))
        top = int(max(0, ys.min() - PAD))
        bottom = int(min(H, ys.max() + 1 + 2))
        img = img.crop((cut, top, W - cut, bottom))
        img.save(os.path.join(DRIVER, f'{name}_{view}.png'), optimize=True)
        m = meta['views'][str(yaw)]
        gx, gy = m['ground']
        entry[view] = {'w': int(img.size[0]), 'h': int(img.size[1]), 'center_ground': [round(gx - cut, 1), round(gy - top, 1)]}
        if view != 'side':
            kind = 'tail' if abs(yaw) < 90 else 'head'
            pts = [[round(l['p'][0] - cut, 1), round(l['p'][1] - top, 1)] for l in m['lamps'] if l['kind'] == kind and l['vis']]
            lamp_entry[view] = sorted(pts)
    dims = meta['dims']
    entry['length_m'] = round(dims['L'], 3)
    entry['width_m'] = round(dims['W'], 3)
    boards[name] = entry
    lamps[name] = lamp_entry


def main(names):
    entries = [e for e in FLEET if not names or e['name'] in names]
    if not entries:
        sys.exit('không có xe nào tên ' + ' '.join(names))
    run_render(entries)
    boards_path = os.path.join(DRIVER, 'billboards.json')
    lamps_path = os.path.join(DRIVER, 'vehicle_lamps.json')
    boards = json.load(open(boards_path))
    lamps = json.load(open(lamps_path))
    for e in entries:
        build_top(e)
        meta = json.load(open(os.path.join(RAW, 'view', f'{e["name"]}.json')))
        build_views(e, meta, boards, lamps)
        print('xong', e['name'], flush=True)
    # Ghi ra chuỗi trước để lỗi giữa chừng không làm hỏng tệp cũ.
    boards_txt = json.dumps(boards, indent=1)
    lamps_txt = json.dumps(dict(sorted(lamps.items())), indent=1)
    with open(boards_path, 'w') as f:
        f.write(boards_txt)
    with open(lamps_path, 'w') as f:
        f.write(lamps_txt)


if __name__ == '__main__':
    main(sys.argv[1:])
