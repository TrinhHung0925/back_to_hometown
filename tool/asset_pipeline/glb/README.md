# Dựng ảnh xe từ mô hình GLB thật

Xe AI trên đường (ô tô, SUV, xe đa dụng, bán tải) dựng từ mô hình GLB thật bằng
three.js chạy trong Chrome không đầu (cùng cách dựng mô hình 3D của app bones_ograns),
thay cho bản dò tia SDF tự vẽ (nhìn "giả"). Xe người chơi, xe máy, xe khách, xe tải
vẫn là ảnh cũ.

```sh
python3 tool/asset_pipeline/glb/fetch_models.py     # tải GLB về models/ (1 lần, ~50 MB)
(cd tool/asset_pipeline/glb && npm install)           # puppeteer-core (1 lần)
python3 tool/asset_pipeline/build_glb_vehicles.py            # dựng tất cả
python3 tool/asset_pipeline/build_glb_vehicles.py pickup_blue mini_van   # chọn vài xe
```

Cần Google Chrome (đặt `CHROME=...` nếu ở chỗ khác), node 20+, python với numpy + pillow.

- `glb_fleet.py`: xe nào dùng mô hình nào, độ dài, xoay mũi xe (`turn`), đổi màu sơn (`tint`), hàng Tết (`cargo`).
- `page.html` + `render.mjs`: dựng ảnh thô (nhìn từ trên + 13 góc ghế lái, ngẩng 7°, 80 điểm ảnh/mét).
- `../build_glb_vehicles.py`: thu nhỏ siêu mẫu, cắt khung, ghi ảnh, bóng đổ, `billboards.json`, `vehicle_lamps.json`.
- `vendor/three`: three.js r186 (MIT) chép từ bones_ograns.
- `CREDITS.md`: ghi công tác giả mô hình (CC BY 4.0) — bắt buộc khi phát hành.
