"""Tải ô độ cao (Terrain Tiles trên AWS Open Data, định dạng Terrarium) để
dựng nền địa hình bản đồ ở màn lên lộ trình. Mỗi mức phóng to của bản đồ game
lấy độ cao từ một mức ô khác nhau (xem map_common.LEVELS).

Nguồn: https://registry.opendata.aws/terrain-tiles/ — dữ liệu SRTM, GMTED2010,
ETOPO1 (public domain). Ghi công: "Terrain Tiles — Mapzen / AWS Open Data".

Chạy từ thư mục gốc project:
    python3 -E tool/route_data/fetch_terrain.py
"""
import os
import subprocess

from map_common import LEVELS, TERRAIN_DIR, terrain_tile_range


def main():
    os.makedirs(TERRAIN_DIR, exist_ok=True)
    for level in LEVELS:
        zoom = level['terrain_zoom']
        xs, ys = terrain_tile_range(level)
        fetched = 0
        for x in xs:
            for y in ys:
                path = f'{TERRAIN_DIR}/{zoom}_{x}_{y}.png'
                if os.path.exists(path) and os.path.getsize(path) > 0:
                    continue
                url = f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{zoom}/{x}/{y}.png'
                subprocess.run(['curl', '-sS', '--max-time', '60', '-o', path, url], check=True)
                fetched += 1
        print(f'zoom {zoom}: {len(xs)} x {len(ys)} ô, tải mới {fetched}')


if __name__ == '__main__':
    main()
