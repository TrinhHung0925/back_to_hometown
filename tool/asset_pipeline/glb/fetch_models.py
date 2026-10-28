"""Tải các mô hình GLB trong glb_fleet.MODELS về models/ (bỏ qua tệp đã có).
    python tool/asset_pipeline/glb/fetch_models.py
"""
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_fleet import MODELS

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = 'https://huggingface.co/datasets/allenai/objaverse/resolve/main'


def path_of(key):
    return os.path.join(HERE, 'models', f'{key}.glb')


if __name__ == '__main__':
    os.makedirs(os.path.join(HERE, 'models'), exist_ok=True)
    for key, (uid, folder, *_rest) in MODELS.items():
        dst = path_of(key)
        if os.path.exists(dst):
            continue
        print('tải', key, uid, flush=True)
        urllib.request.urlretrieve(f'{BASE}/{folder}/{uid}.glb', dst)
