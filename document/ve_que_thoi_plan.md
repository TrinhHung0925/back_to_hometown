# Plan: "Về Quê Thôi!"

> Ngày lập: 14/10/2026 · Trạng thái: **đang làm** — các câu ở mục 9 tạm chốt theo đề xuất
> Công nghệ: Flutter + Flame, kiến trúc GetX theo `flutter_architecture.md`
>
> **Các ý đã chốt (cập nhật 14/10):**
> - **Chỉ làm màn hình ngang.**
> - **Cách về quê:** tự lái xe hoặc đi xe khách. **Làm tự lái xe trước**, xe khách để sau.
> - **Lên lộ trình bằng bản đồ:** chọn điểm xuất phát, điểm đến, loại xe (xe máy / ô tô) → vẽ đường đi → đo quãng đường và ước tính thời gian chơi (ví dụ 100 km ≈ 5 phút).
> - **Đường không thẳng mãi:** có khúc cong, có ngã tư đèn xanh đèn đỏ, có trạm thu phí.
> - Đường **2 chiều 4 làn**, **ít xe thôi**: có xe cùng chiều, xe ngược chiều, xe vượt từ phía sau, nhiều tình huống.
> - **Điều khiển:** cụm nút kiểu game MOBA (ga, phanh, còi, đèn); **cần lái để ngón tay đặt lên liên tục**, kéo để đổi hướng.
> - **Chat khi đang chơi:** gõ chữ thì tin nhắn hiện lên phía trên màn hình.
> - **Đâm xe thì công an tới:** nộp phạt, hoặc bỏ chạy. Chạy chậm bị bắt thì chuyến đi kết thúc.
> - **Thua khi:** hết giờ, bị công an bắt, hoặc gặp tai nạn.

---

## 1. Game là gì

Bạn lên lộ trình về quê trên bản đồ Việt Nam, chọn đi xe máy hay ô tô, rồi tự lái qua từng chặng: phố phường, ngã tư đèn đỏ, quốc lộ, trạm thu phí. Phải ga, phanh, bóp còi, bật đèn và đánh lái để né xe cùng chiều lẫn ngược chiều, nhặt lì xì, và về tới nhà trước giao thừa. Quẹt xe hay vượt đèn đỏ thì công an tới: nộp phạt cho yên, hay liều bỏ chạy? Đâm mạnh là tai nạn, chuyến về quê dừng ở đó. Game chơi màn hình ngang, nhìn từ trên xuống, theo phong cách pixel art.

---

## 2. Luồng màn hình

```
Splash → Menu ─┬─ Về quê → Chọn cách về ─┬─ Tự lái xe → Lên lộ trình (bản đồ) → Chặng 1 → Trạm dừng nghỉ → Chặng 2 → … → Về tới nhà
               │                          └─ Đi xe khách (hiện nút "Sắp có", chưa làm)
               └─ Tiếp tục chuyến đi (nếu đang có chuyến dở)
```

- **Menu:** Về quê, Tiếp tục chuyến đi (chỉ hiện khi đang có chuyến dở), kỷ lục, bật/tắt âm thanh.
- **Chọn cách về:** hai thẻ "Tự lái xe" và "Đi xe khách". Thẻ xe khách hiện nhãn "Sắp có" và chưa bấm được.
- **Lên lộ trình:** xem mục 3.
- **Trạm dừng nghỉ giữa các chặng:** hiện đã tới đâu, còn bao nhiêu km, còn mấy giờ tới giao thừa; nút "Đi tiếp" và "Nghỉ, chơi sau". Tiến độ được lưu ở đây.
- **Về tới nhà:** màn kết quả cả chuyến, chấm sao.

---

## 3. Lên lộ trình bằng bản đồ

### Màn hình
- **Bên trái (khoảng 2/3 màn):** bản đồ Việt Nam, kéo và phóng to được. Các tỉnh/thành có thể chọn được đánh dấu bằng chấm trên bản đồ.
- **Bên phải:** ô **Điểm xuất phát**, ô **Điểm đến** (chạm chấm trên bản đồ, hoặc gõ tìm theo tên), và nút chọn **Xe máy / Ô tô**.
- Chọn đủ 3 thứ là **đường đi được vẽ ngay lên bản đồ**, kèm thông tin:
  - Quãng đường, ví dụ 295 km.
  - Thời gian lái thực tế ước tính, ví dụ khoảng 6 giờ, và thời gian chơi, ví dụ khoảng 15 phút, chia 4 chặng.
  - Trên đường đi qua: các thành phố, số trạm thu phí, có đi cao tốc hay không.
- Đổi loại xe thì đường vẽ lại, vì **xe máy không được đi cao tốc**: xe máy đi quốc lộ, ô tô ưu tiên cao tốc.
- Nút **Xuất phát** để bắt đầu chặng 1.

### Quy đổi thời gian
- **Thời gian chơi tính theo quãng đường và loại đường.** Mốc gốc: 100 km quốc lộ ≈ 5 phút chơi. Cao tốc nhanh hơn, nội thành chậm hơn. Tỷ lệ này để trong `game_config.dart` để chỉnh.
- **Chia chặng:** mỗi chặng khoảng 3–5 phút (60–100 km), ưu tiên cắt ở các thành phố trên đường. Chuyến dài thì có nhiều chặng. Ví dụ TP.HCM → Hà Nội khoảng 1.700 km, tức khoảng 85 phút chơi, sẽ chia thành hơn 20 chặng và có thể chơi trong nhiều lần.
- **Giờ xuất phát tính ngược từ giao thừa:** thời gian cho phép = thời gian ước tính × 1,25. Ví dụ chuyến 6 tiếng thì xuất phát lúc 16:30 chiều 30 Tết, phải về trước 24:00. Chuyến rất dài thì xuất phát từ 29 Tết.
- Đồng hồ trong game chạy theo giờ trong ngày, nên **trời tối dần theo giờ thật của chuyến đi**: chuyến dài xuất phát ban ngày, về cuối mới tối và mới cần bật đèn.

### Bản đồ: đề xuất làm bản đồ vẽ sẵn, chạy offline
- **Cách làm:**
  - Một ảnh bản đồ Việt Nam vẽ kiểu pixel art.
  - Một danh sách khoảng 20–30 điểm phổ biến, có toạ độ trên ảnh.
  - Các đoạn đường nối giữa các điểm, mỗi đoạn có số km, loại đường (quốc lộ / cao tốc / nội thành) và vị trí trạm thu phí.
  - Game tự tìm đường ngắn nhất trên mạng lưới này.
- **Vì sao không dùng bản đồ thật (Google Maps, OpenStreetMap):**
  - Cần mạng, cần khoá API, có thể tốn phí khi nhiều người chơi.
  - Đường thật quá chi tiết, trong khi gameplay chỉ cần quãng đường, loại đường và vị trí trạm thu phí.
  - Bản đồ vẽ sẵn hợp phong cách pixel art hơn.
- **Số km lấy theo khoảng cách thật,** nhập tay một lần và đối chiếu với Google Maps. Trên màn hình ghi rõ là "ước tính".
- **Điểm chọn nên là thành phố/thị xã** (Vinh, Thanh Hoá, Huế…) chứ không phải tên tỉnh, để không vướng chuyện tên tỉnh đã đổi sau đợt sáp nhập năm 2025.
- Dữ liệu điểm và đường nối viết thẳng bằng Dart trong `lib/resource/`, không cần file JSON hay thư mục asset mới.

---

## 4. Luật chơi khi lái

### Xe máy và ô tô

| | Xe máy | Ô tô |
|---|---|---|
| Đường đi | Chỉ quốc lộ, không được đi cao tốc | Ưu tiên cao tốc, về nhanh hơn |
| Trạm thu phí | Đi làn xe máy sát lề, không mất phí, nhưng làn hẹp | Phải trả phí bằng lì xì |
| Đánh lái | Nhạy | Nặng hơn |
| Tăng tốc | Nhanh | Chậm hơn |
| Tốc độ tối đa | Thấp hơn | Cao hơn |
| Kích thước | Nhỏ, lách được khe giữa hai xe | To, khó lách |
| Chở quà | Ít, chất sau yên; mỗi món ảnh hưởng tay lái rõ | Nhiều, để cốp và buộc nóc; mỗi món ảnh hưởng ít |
| Khi bị công an đuổi | Luồn lách tốt | Chạy nhanh hơn khi đường thoáng |

Cả hai xe đều phải về kịp được; khác nhau ở cách chơi: xe máy linh hoạt, ô tô chắc chắn.

### Con đường
- **Chỉ màn ngang.** Đường đi chung hướng từ trái sang phải.
- **2 chiều, 4 làn:**
  - 2 làn dưới là chiều của mình. Việt Nam đi bên phải, nên khi đi sang phải thì chiều của mình nằm ở nửa dưới.
  - 2 làn trên là chiều ngược lại. Giữa hai chiều có vạch phân cách, hai bên ngoài là vỉa hè và cảnh ven đường.
- **Đường thưa xe:**
  - Mỗi lúc chỉ có vài xe trên màn hình (khoảng 2–4), tính cả cùng chiều lẫn ngược chiều. Đủ để đường có sự sống mà không chen chúc.
  - Độ khó đến từ tình huống (đèn đỏ, trạm thu phí, xe vượt, xe ngược chiều lao tới), không đến từ mật độ xe.
  - Số xe tối đa để trong `game_config.dart`.
- **Người chơi được lấn sang làn ngược chiều** để vượt (trừ trên cao tốc), nhưng đâm trực diện xe ngược chiều gần như chắc chắn là tai nạn.

### Đường không thẳng mãi
- Con đường được **ghép từ các mảnh**: đoạn thẳng xen khúc cua trái, cua phải, cua chữ S; ngã tư và trạm thu phí luôn nằm trên đoạn thẳng.
- **Cua thật:** một khúc cua đổi hướng tới khoảng 80°, bán kính nhỏ nhất 430 ở quốc lộ. Phố chủ yếu thẳng và chỉ uốn nhẹ (ngã tư cần đường thẳng). Cao tốc cua rộng, êm. Hướng đường không lệch quá 75° so với hướng chung của tuyến, nên đường không bao giờ quay ngược lại hay tự cắt nhau.
- **Camera xoay theo đường:** camera bám theo hướng dây cung từ xe tới một điểm phía trước. Đoạn đường gần xe luôn nằm ngang màn hình; khúc cua phía trước uốn hẳn lên hoặc xuống, thấy rõ cua trái hay cua phải.
- **Vào cua phải bẻ lái:** xe bị văng ra phía ngoài khúc cua với lực tỉ lệ v² × độ cong. Cua phải thì văng sang trái, về phía làn ngược chiều; cua trái thì văng ra lề phải.
  - Chạy đúng tốc độ khuyên dùng thì bẻ lái giữ được làn.
  - Phóng nhanh thì kéo hết cần lái cũng không giữ nổi: xe tì vào mép đường (hoặc dải phân cách cao tốc), quệt lề, rung, rít lốp và mất tốc độ nhanh.
- **Cua gắt** (bán kính dưới 760, chỉ có ở quốc lộ):
  - Trước khúc cua của mỗi chiều có biển "chỗ ngoặt nguy hiểm" (tam giác vàng viền đỏ, mũi tên cua) kèm biển tốc độ khuyên dùng.
  - Dọc mép ngoài khúc cua có biển hướng cua vàng đen.
  - HUD hiện ô báo cua: mũi tên hướng cua, khoảng cách, tốc độ khuyên dùng. Ô chuyển đỏ khi đang chạy nhanh hơn mức khuyên.
  - Thông báo "Sắp vào cua gắt bên trái/phải — giảm tốc dưới … km/h".
- **Cảnh ven đường theo cua:** phía trong khúc cua, nhà nông hơn và thu hẹp dần về phía sau (lô đất hình thang); cua gắt quá thì chỉ trồng cây. Cây không mọc lấn qua tâm cong.
- **Mỗi loại đoạn đường một kiểu,** lấy theo lộ trình đã chọn:

| Loại đoạn | Ở đâu trên lộ trình | Cảnh | Đặc trưng |
|---|---|---|---|
| Nội thành | Đầu chuyến, cuối chuyến, khi đi qua thành phố | Nhà phố, hàng quán | Nhiều xe máy hơn một chút, ngã tư đèn xanh đèn đỏ, chạy chậm |
| Quốc lộ | Giữa các thành phố | Ruộng, cây, quán ven đường | Cong nhẹ, xe tải, xe khách, ổ gà, xe ngược chiều, trạm thu phí BOT |
| Cao tốc (chỉ ô tô) | Tuyến có cao tốc | Dải phân cách cứng, hàng rào | Gần như thẳng, chạy nhanh, không lấn được sang chiều ngược, trạm thu phí ở lối vào và lối ra |
| Đèo, đường làng | — | — | Để sau MVP |

### Đèn xanh đèn đỏ
- Có ở các ngã tư trong đoạn nội thành. Đèn có **số đếm ngược giây** như đèn thật ở Việt Nam.
- **Đèn đỏ:** phải dừng trước vạch. Xe ở đường ngang chạy cắt qua ngã tư từ mép trên và mép dưới màn hình.
- **Vượt đèn đỏ:** dù không đâm ai thì công an vẫn thổi còi. Đâm xe ở đường ngang thì tính như va chạm thường (nhẹ hay tai nạn tuỳ tốc độ).
- **Đèn vàng:** còn kịp thì đi, không kịp thì dừng.

### Trạm thu phí
- Có biển báo trước khi tới trạm. Mỗi làn có một buồng thu phí. Số làn giữ nguyên khi qua trạm để code đơn giản.
- **Ô tô:**
  - **Làn thu phí thường:** dừng hẳn ở buồng, trừ lì xì, barrier mở. Chắc ăn nhưng mất thời gian.
  - **Làn thu phí không dừng:** chỉ cần giảm xuống dưới tốc độ quy định, barrier tự mở. Nhanh hơn nhưng phải phanh cho chuẩn.
  - **Lao vào barrier** tính như va chạm: chậm thì công an tới, nhanh thì tai nạn.
- **Xe máy:** đi làn xe máy sát lề, không mất phí, nhưng làn hẹp.
- Không đủ lì xì trả phí thì bị giữ lại lâu hơn (mất thời gian).

### Điều khiển — cần lái bên trái, cụm nút kiểu MOBA bên phải

Chia hai tay giống game MOBA: **tay trái đặt liên tục trên cần lái**, **tay phải bấm cụm nút**. Mỗi nút có icon và chữ nhỏ bên dưới, nền bán trong suốt.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Hà Nội ●━━━━━━○ Phủ Lý  còn 42 km  21:35  lì xì 12 quà 3 [CHAT] [II]│
│              « Sắp về tới nhà rồi mẹ ơi!! »   ← tin nhắn chat       │
│ ░░░░░░░░░░░░░░░░░░░ vỉa hè / cảnh ven đường ░░░░░░░░░░░░░░░░░░░░░░░ │
│  ◄       làn ngược chiều                                (ĐÈN)       │
│                    ◄     làn ngược chiều                            │
│ ══════════════════════════ vạch giữa ════════════(CÒI)═════════════ │
│          làn chiều mình  [XE]          ►                            │
│          làn chiều mình                      (PHANH)    ╭──────╮    │
│ ░░░╭───╮░░░░░░░░░░░░░░░░░░░░ vỉa hè ░░░░░░░░░░░░░░░░░░░ │  GA  │    │
│    │ ◉ │ ← cần lái                                      ╰──────╯    │
│    ╰───╯                                                            │
└─────────────────────────────────────────────────────────────────────┘
```
*(Minh hoạ vị trí, tỷ lệ chưa chính xác. Thanh trên cùng là tiến trình chặng: điểm đầu → điểm cuối chặng, có icon ngã tư, trạm thu phí sắp tới.)*

**Cần lái — góc dưới bên trái:**
- Ngón cái trái đặt lên và giữ liên tục. **Kéo lên** thì xe đánh lái lên phía trên màn hình (sang trái theo hướng đi), **kéo xuống** thì xuống dưới (sang phải theo hướng đi).
- Kéo càng xa thì đánh lái càng gắt. Để núm ở giữa hoặc thả tay ra thì xe đi thẳng theo đường.
- Xe di chuyển liên tục chứ không nhảy từng làn, nên xe máy lách được khe giữa hai xe.
- **Cần lái nổi:** chạm chỗ nào trong vùng dưới-trái thì cần lái hiện ra ở đó, nên không phải nhìn xuống tìm nút.
- **Vì sao để bên trái chứ không ở trong cụm nút bên phải:** ngón cái đã đặt liên tục trên cần lái thì không bấm được ga, phanh. Để chung một góc thì không thể vừa lái vừa phanh. Chia hai tay giống cách game MOBA để cần di chuyển bên trái, nút kỹ năng bên phải.

**Cụm nút — góc dưới bên phải (như ảnh tham khảo):**

| Nút | Vị trí | Cách dùng | Tác dụng |
|---|---|---|---|
| **Ga** | Nút to nhất, sát góc dưới bên phải | Giữ | Tăng tốc. **Nhả ga thì xe trôi chậm dần** (muốn giữ tốc độ phải giữ ga). Vòng sáng quanh nút là đồng hồ tốc độ, chuyển đỏ khi đang ở tốc độ mà đâm vào là thành tai nạn |
| **Phanh** | Vòng cung, bên trái-dưới nút ga | Giữ | Giảm tốc mạnh, có thể dừng hẳn (cần cho đèn đỏ và trạm thu phí). Thả ra thì xe trôi chậm dần như nhả ga |
| **Còi** | Vòng cung, phía trên-trái nút ga | Bấm | Xin đường. Có hiệu ứng hồi chiêu quét tròn như skill MOBA |
| **Đèn** | Vòng cung, phía trên nút ga | Bấm để bật/tắt | Nhìn rõ đường khi trời tối. Nút sáng lên khi đang bật |

- Nhả ga thì xe trôi chậm dần (khoảng 4 giây từ tốc độ thường về 0), nên ngón cái phải vẫn chuyển nhanh sang còi, đèn được mà không mất hết tốc độ; muốn chạy đều thì phải giữ ga.
- Ga và phanh cùng giữ thì phanh được ưu tiên.

**Góc trên bên phải:** nút **Chat** và nút **Tạm dừng**.

### Xe không đứng yên
- Vị trí xe trên màn hình đi theo tốc độ: chạy chậm thì xe lùi về khoảng 15% chiều ngang (tính từ trái), chạy nhanh thì nhích tới khoảng 45%.
- Phanh thì xe lùi lại và xe phía sau vượt lên. Phanh dùng để dừng đèn đỏ, vào trạm thu phí, chờ khoảng trống, hoặc né chướng ngại ngay trước mặt.
- **Vì sao không chạy chậm suốt cho an toàn:** đồng hồ đếm ngược tới giao thừa.

### Còi và đèn
- **Còi — xin đường:** xe ngay phía trước mũi xe sẽ bật xi-nhan rồi dạt sang làn bên cạnh nếu có chỗ. Xe máy và ô tô con thường nhường; xe tải, xe khách có khi không nhường mà bóp còi lại. Bấm xong phải chờ khoảng 2 giây mới bấm tiếp được.
- **Đèn — trời tối theo giờ của chuyến đi:** khi trời tối, không bật đèn thì chỉ thấy một đoạn ngắn trước mũi xe; bật đèn thì có chùm sáng chiếu xa phía trước. Xe khác cũng bật đèn nên vẫn thấy được đèn của chúng từ xa.

### Chat khi đang chơi
- Bấm nút **Chat** ở góc trên bên phải thì **game tạm dừng** (bàn phím ở màn ngang che gần hết màn hình) và hiện ô nhập chữ.
- Gửi xong thì tin nhắn **hiện ở phía trên màn hình**, ngay dưới HUD, khoảng 4 giây rồi mờ dần. Game chạy tiếp.
- Tin nhắn chỉ hiện trên máy của người chơi: không gửi đi đâu, không lưu lại.
- Nếu sau này cho người khác cùng xem (chơi chung, chế độ xe khách) thì cần máy chủ và bộ lọc từ ngữ.

### Va chạm, tai nạn và công an

**Ổ gà** không phải va chạm với ai: xe xóc mạnh, khựng nhẹ và rơi 1 món quà.

**Va chạm với xe khác hoặc barrier** được chia theo **tốc độ chênh lệch lúc đâm**:

| Mức | Khi nào | Hậu quả |
|---|---|---|
| **Va chạm nhẹ** | Quẹt, hoặc đâm khi chênh lệch tốc độ thấp (ví dụ chạm đuôi xe cùng chiều khi đang chạy gần bằng tốc độ) | Dừng lại giải quyết, công an tới |
| **Tai nạn** | Đâm mạnh: đâm trực diện xe ngược chiều, hoặc đâm khi chênh lệch tốc độ lớn | **Thua ngay: "Tai nạn — không về được quê"** |

- Ngưỡng chênh lệch để trong `game_config.dart`.
- Vòng tốc độ quanh nút ga chuyển đỏ khi đang ở tốc độ nguy hiểm. Nhờ vậy người chơi hiểu vì sao lần này chỉ bị phạt còn lần kia lại là tai nạn.

**Vượt đèn đỏ (không đâm ai)** cũng làm công an tới.

**Khi công an tới:**
1. Xe dừng hẳn. Công an đi xe máy tới từ phía sau, hú còi, đèn nháy.
2. Game tạm dừng và hiện 2 lựa chọn:

| Lựa chọn | Điều xảy ra |
|---|---|
| **Nộp phạt** | Trừ lì xì và mất thời gian giải quyết, rồi đi tiếp. Va chạm ở làn ngược chiều thì phạt nặng hơn vì đi sai làn. Không đủ lì xì thì nộp hết số đang có và bị giữ lại lâu hơn. |
| **Chạy** | Bắt đầu rượt đuổi khoảng 10 giây. Công an bám từ mép trái, trên màn hình có thanh khoảng cách. Phải giữ tốc độ cao và không đâm thêm xe nào. Kéo giãn đủ khoảng cách thì **thoát, không mất gì**. Chạy chậm hoặc đâm thêm xe khiến công an áp sát thì **bị bắt: chuyến đi kết thúc, "Không về được quê"**. |

- Chạy gắn với các cơ chế khác: chở nặng thì tăng tốc chậm nên khó thoát hơn; ô tô chạy nhanh hơn trên đường thoáng, xe máy luồn lách tốt hơn. Đang chạy trốn mà đâm mạnh thì vẫn là tai nạn.
- Về kỹ thuật, công an là "người đuổi ảo": chỉ là một con số khoảng cách, và hình xe công an chỉ hiện ở mép trái khi đã áp sát. Không phải làm AI cho xe công an luồn lách giữa các xe.

### Các tình huống trên đường

| Tình huống | Mô tả | Làm ở |
|---|---|---|
| Xe chạy chậm cùng chiều | Xe tải, xe ba gác chở đồ đi chậm hơn mình, phải vượt hoặc phanh theo | P1 |
| Xe ngược chiều | Chạy ở 2 làn trên, lao tới rất nhanh vì tốc độ cộng dồn | P1 |
| Ổ gà | Nằm yên trên đường | P1 |
| Ngã tư đèn xanh đèn đỏ | Xem mục riêng ở trên | P2 |
| Trạm thu phí | Xem mục riêng ở trên | P2 |
| Xe vượt từ phía sau | Xe khách, ô tô nhanh hơn mình, vượt lên từ mép trái. Có mũi tên cảnh báo ở mép trái làn đó + tiếng còi trước khoảng 1,5 giây | P3 |
| Xe máy chuyển làn | Xe khác bật xi-nhan khoảng 1 giây rồi tạt sang làn bên cạnh | P3 |
| Xe chở cành đào, cây quất | Hàng cồng kềnh, chiếm rộng hơn 1 làn | P3 |
| Xe khách ngược chiều vượt ẩu | Lấn hẳn sang làn của mình | P5 |
| "Xi-nhan trái rẽ phải" | Bật xi-nhan một đằng, rẽ một nẻo | P5 |
| Tắc đường | Đoạn ngắn xe đông bất thường; xe máy lách được, ô tô phải phanh chờ hoặc liều lấn làn ngược chiều | P5 |
| Đàn vịt, chó chạy qua đường | Băng ngang đường từ vỉa hè, ở đoạn đường làng | P5 |
| Mưa, đường trơn | Phanh ăn kém hơn, đánh lái bị trượt | P5 |

### Kịch bản dọc đường: quán ven đường, buồn ngủ, quay đầu, xăng, lốp, mưa, CSGT

Đường về quê dịp Tết ngoài đời: lái liền mấy tiếng thì mỏi, buồn ngủ; ven quốc lộ cứ một đoạn lại có quán nước. Ai cũng từng tấp vào uống cốc trà đá, hay lỡ quán thì quay đầu lại. Game làm đúng như vậy.

**Quán ven đường**
- Quốc lộ cứ 1–2,6 km có một quán; trong phố cứ 0,7–1,5 km có quán trà đá vỉa hè. Cao tốc không có quán, chỉ có trạm dừng nghỉ (cây xăng bên phải).
- Khoảng 6/10 quán nằm bên phải chiều về, số còn lại ở bên kia đường.
- Quán không đặt sát ngã tư, trạm thu phí, điểm đón khách. Nhà, cây, cột điện tự né khu quán.
- Các kiểu quán (vẽ từ trên xuống, đổ bóng theo khối như xe):

| Quán | Cảnh | Thực đơn (lì xì · tỉnh táo · phút) |
|---|---|---|
| Trà đá | Ghế nhựa đỏ/xanh, bàn thấp có cốc trà đá, ô dù, bình đá, thùng đá | Cốc trà đá (1 · +18 · 5′), Đĩa hướng dương (1 · +8 · 10′), Ngồi nghỉ chân (0 · +10 · 12′) |
| Nước mía | Máy ép mía inox, bó mía, bạt xanh | Cốc nước mía (1 · +24 · 6′), Nước mía tắc (2 · +32 · 7′) |
| Cà phê võng | Hàng võng dưới mái bạt, tài xế nằm nghỉ | Cà phê đen đá (2 · +45 · 10′), Bạc xỉu (2 · +38 · 10′), Nằm võng chợp mắt (1 · +75 · 30′) |
| Bánh mì | Xe bánh mì kính, ô dù | Bánh mì pate (2 · +20 · 8′), Xôi xéo (2 · +22 · 10′) |
| Cơm bình dân | Tủ kính khay thức ăn, mái bạt, nhiều bàn | Suất cơm (3 · +35 · 20′), Trà đá miễn phí (0 · +10 · 4′) |
| Tiệm vá xe | Lốp xếp chồng, máy bơm hơi, chậu nước thử săm, mái bạt, bàn trà | Vá / thay săm, lốp (xem mục Thủng lốp) + Cốc trà đá (1 · +18 · 5′) |
| Cây xăng | Sân bê tông, mái che viền đỏ xanh, hai đảo bơm, cửa hàng mái bằng, trụ giá | Đổ xăng (xem mục Xăng) |
| Xăng lẻ | Kệ gỗ chai xăng, phễu, can, bà bán xăng ngồi dưới ô | Một chai xăng (chỉ xe máy) |

- Mỗi quán có tên chủ quán: "Quán trà đá Cô Ba", "Cà phê võng Út Hiền"…
- Khách ngồi sẵn trên ghế. Xe máy của khách dựng ở lề, mũi xe chĩa vào quán.
- Biển hiệu đọc xuôi theo chiều đi của phía quán.

**Ghé quán**
1. Đi chậm sát lề phải, dừng hẳn trước quán (trong khoảng ±95). Nút **Ghé quán** hiện lên.
2. Bấm nút: xe tấp hẳn vào lề và tắt máy; xe máy đổi sang hình xe dựng không người.
3. Người lái xuống xe, đi bộ vào ngồi ghế (ở quán cà phê võng thì nằm võng). Camera phóng to và dời sang để quán nằm ở nửa phải màn hình.
4. Bảng quán hiện bên trái:
   - biển quán, tên quán, số lì xì
   - chuyện trò đổi dần mỗi ~4 giây
   - thực đơn có nút **Gọi**
   - thanh tỉnh táo, giờ trong game
   - nút **Lên đường**
5. Dựng xe tốn sẵn 2 phút; mỗi món tốn thêm số phút của món đó. Đồng hồ giao thừa không chạy theo thời gian thật lúc ngồi quán, chỉ cộng theo món đã gọi.
6. **Chuyện ở quán** vừa cho không khí Tết vừa có tin thật về đoạn đường phía trước:
   - còn bao nhiêu cây tới trạm thu phí
   - có cua gắt
   - sắp vào phố hay lên cao tốc
   - còn bao xa về tới nơi
   - trời tối nhớ bật đèn
   - "mắt đỏ hết rồi kìa" khi đang buồn ngủ
7. Lên đường: người lái đi ra xe, xe nổ máy và lăn bánh ra làn.

**Tỉnh táo, ngủ gật**
- **Mức tỉnh táo:** vào chặng ở 82/100. Khi đang chạy, mỗi giây chơi tụt 0,24; ban đêm tụt nhanh gấp 1,7. Một chặng khoảng 5 phút chơi, tức là lái liền chừng 2 tiếng.
- **Dưới 45:** thông báo "Bắt đầu buồn ngủ rồi…", mép màn hình tối dần, ô tỉnh táo trên HUD chuyển vàng.
- **Dưới 25 — ngủ gật:** cứ 5–15 giây (càng thấp càng dày) mí mắt khép lại khoảng 0,9 giây, dưới 10 thì khoảng 1,35 giây. Lúc đó tay lái không ăn, xe tự dạt ngang 60 u/s. Gật trúng lúc có xe bên cạnh là tai nạn.
- **Ô tỉnh táo trên HUD:** cốc cà phê + phần trăm, đổi xanh → vàng → đỏ.
- **Nhắc ghé quán:** khi tỉnh táo dưới 60 (hoặc vài quán đầu chặng), game báo trước "Quán … bên phải phía trước".

**Quay đầu**
- **Khi nào được quay:** đi chậm dưới khoảng 15 km/h thì nút **Quay đầu** hiện lên. Không quay được trên cao tốc (dải phân cách) và trong trạm thu phí.
- **Cú quay:** xe cua một nửa vòng tròn về bên trái, sang làn ngoài cùng của chiều kia. Camera xoay theo nên chiều đang đi luôn hướng sang phải màn hình.
- **Đủ chỗ quay theo loại xe:**
  - xe máy quay gọn ở đâu cũng được
  - ô tô phải tấp sát lề phải, nếu không thì báo "Chưa đủ chỗ"
  - xe khách chỉ quay được ở ngã tư, nhờ có thêm chỗ của đường ngang
- **Xe khác:** xe hai chiều thấy mình đang quay chắn ngang thì phanh nếu còn kịp, quá gần thì đâm.
- **Đi ngược:**
  - Mọi thứ tính theo chiều đang đi:
    - cần lái
    - lực văng khi vào cua (cua phải của đường thành cua trái)
    - vạch dừng đèn đỏ của chiều kia
    - xe cùng chiều mới
    - lì xì, ổ gà rơi trên làn của mình
    - biển báo cua của chiều kia
  - HUD có nhãn "Đang đi ngược về …".
  - Đi qua trạm thu phí theo chiều ngược không mất phí.
  - Không có xe vượt từ phía sau, không đón khách.
- **Giới hạn:** chỉ đi ngược tối đa khoảng 3 km so với chỗ xa nhất đã tới; đường và cảnh phía sau trong khoảng đó được giữ lại nguyên vẹn. Quá giới hạn thì báo "Quay lại xa quá rồi — quay đầu về quê thôi!".
- **Dùng để làm gì:** quay lại quán vừa chạy lỡ, hoặc sang quán bên kia đường.

**Xăng**
- Bình xăng hiện trên HUD (cột bơm + vạch + %), mang từ chặng này sang chặng sau. Chuyến mới bắt đầu với 42–70% bình vì đi vội chưa kịp đổ đầy.
- Đầy bình chạy được: xe máy 140 km, ô tô 420 km, xe khách 560 km (ở tốc độ thường). Chạy nhanh và chở nặng tốn hơn.
- **Dưới 12%:** đèn báo xăng nháy đỏ, game báo còn chừng bao nhiêu km. HUD bên phải hiện chỗ đổ xăng gần nhất ("Cây xăng 2,4 km"); xe máy tính cả xăng lẻ.
- **Dưới 3,5%:** máy khục khặc, thỉnh thoảng mất ga một nhịp.
- **Hết hẳn:** xe trôi rồi đứng. Các nút hiện ra:
  - **Nghiêng xe** (xe máy, mỗi lần cạn một lần): dồn được chừng 3 km xăng.
  - **Dắt bộ** (xe máy): người lái xuống dắt xe đi bên cạnh, giữ Ga để đẩy, tối đa ~12 km/h.
  - **Gọi xăng / Gọi cứu hộ:** xe ôm hoặc xe cứu hộ chạy tới đỗ sau xe, đổ một can (+20% bình). Xe máy 2 lì xì + 15 phút; ô tô 4 lì xì, xe khách 6 lì xì + 25 phút. Không đủ tiền thì đưa hết, chờ thêm 10 phút.
- **Cây xăng:** quốc lộ 8–14 km một cây, phố 5–8 km, cao tốc 22–32 km (trạm dừng nghỉ).
  - Dừng sát lề trước cây xăng → nút **Đổ xăng**. Xe lượn vào đỗ cạnh đảo bơm, mái che mờ đi để thấy cột bơm, nhân viên ra tận xe.
  - Bảng cột bơm có màn LED số lít, phần trăm bình chạy lên khi bơm. Chọn **Đổ 1 lì xì** hoặc **Đổ đầy bình**. Một lì xì được 50% bình xe máy, 20% ô tô, 14% xe khách.
- **Xăng lẻ:** kệ chai xăng ven quốc lộ, 2,5–5 km một kệ, chỉ bán cho xe máy: 1 lì xì một chai (+25%), đắt hơn cây xăng.
- **Trạm dừng nghỉ giữa các chặng** có nút **Đổ đầy** (giá như cây xăng, mất 5 phút).

**Thủng lốp, đinh tặc**
- **Đinh tặc:**
  - Quốc lộ cứ 18–34 km có một bãi đinh rải trên một làn. Đinh lấp lánh dưới nắng, có bãi người dân dựng biển viết tay "CÓ ĐINH! ĐI CHẬM".
  - Cán qua thì xì lốp: xe máy 80%, ô tô 60%, xe khách 50%.
  - Ngay sau bãi đinh có tiệm vá xe "VÁ XE 24H" chặn đầu, giá gấp đôi, chủ tiệm than "đoạn này đinh nhiều lắm".
- **Sập ổ gà** khi đang phóng nhanh (trên 1,25 lần tốc độ thường): 15% xì lốp.
- **Lốp xẹp:**
  - Tiếng xì hơi, xe khựng.
  - Tốc độ tối đa còn 45% tốc độ thường; xe bị kéo lệch về một bên, thân xe lắc lắc.
  - HUD hiện lốp đỏ "Xẹp" và tiệm vá xe gần nhất.
- **Nát săm:** chạy lốp xẹp quá 1,5 km thì nát săm: chỉ còn cách thay, xe còn chậm hơn.
- **Tiệm vá xe** (quốc lộ 4–7 km, phố 3–5 km):
  - Xe máy: vá săm 1 lì xì · 12 phút, thay săm 2 lì xì · 8 phút.
  - Ô tô, xe khách: vá lốp 2 · 15 phút, thay lốp 5 · 12 phút.
  - Thợ ra tận xe làm; người lái ngồi bàn uống trà.
- **Lốp dự phòng** (ô tô, xe khách): tấp sát lề phải → **Thay lốp** (15 phút, xe khách 25 phút).
  - Thẻ việc tích dần từng bước: bật đèn khẩn cấp → đặt biển tam giác sau xe → kích xe, tháo lốp → lắp lốp dự phòng.
  - Trên đường: đèn khẩn cấp nháy, biển tam giác, con đội, người lái ngồi xổm cạnh bánh.
  - Thay rồi thì hết lốp dự phòng; vá ở tiệm thì có lại.
- **Gọi thợ vá lưu động:** 3 lì xì · 20 phút, dùng được ở bất cứ đâu (số điện thoại dán trên cột điện).

**Mưa**
- **Mưa theo vùng:**
  - Miền Bắc dịp Tết: 55% chặng có mưa. Phần nhiều là mưa phùn (hạt nhỏ, trời mù mù, có khi hai đợt); 30% là mưa rào.
  - Miền Nam mùa khô: 15% chặng có một cơn mưa trái mùa.
- **Mưa theo giờ trong game:** to dần rồi ngớt dần. Ngồi quán lâu thì có thể chờ tạnh. Tạnh rồi đường còn ướt thêm 20 phút.
- **Hình ảnh:**
  - Hạt mưa xiên trên màn hình (xe chạy nhanh thì hạt như hắt ngược), mưa rào hạt dài, mưa phùn lấm tấm.
  - Hạt rơi toé vòng tròn trên mặt đất; mặt đường ướt sẫm, loang vệt sáng.
  - Xe chạy bắn bụi nước phía sau. Trời tối hơn (mưa rào gần như phải bật đèn), mưa phùn thêm lớp sương.
  - Người đi xe máy trùm áo mưa cánh dơi đủ màu. Quán đông người vào trú, xe dựng kín lề.
  - Có tiếng mưa rơi.
- **Đường trơn:**
  - Phanh ăn còn 74%, lực văng khi vào cua mạnh hơn; tốc độ khuyên dùng ở biển cua tự hạ xuống.
  - Đường đọng vũng nước: lao qua nhanh (trên 0,8 lần tốc độ thường) thì trượt nước, tay lái không ăn ~0,5 giây.
- **Xe máy không có áo mưa:**
  - Ướt dần (HUD hiện giọt nước + %).
  - Ướt sũng thì lạnh run: tay lái run, tỉnh táo tụt gần gấp đôi.
  - Mua **áo mưa cánh dơi** (1 lì xì) ở bất cứ quán / cây xăng nào; mặc vào thì hình người lái trùm áo mưa.

**Chốt CSGT, phạt nguội**
- **Chốt trên quốc lộ:** 45 km một chốt, đặt ở đoạn thẳng, xa trạm thu phí.
  - Bãi đất bên lề, lều bạt sọc xanh trắng chữ CSGT, bàn làm việc, hai xe máy CSGT dựng, hàng cọc tiêu.
  - Cán bộ đứng bắn tốc độ ở hai đầu chốt, một người cầm gậy chỉ huy.
- **Biển báo:** 750 trước chốt có biển hạn chế tốc độ (50 hoặc 60 km/h) kèm biển phụ "KIỂM SOÁT"; quanh chốt có biển cấm quay đầu. HUD bên phải hiện biển tốc độ và quãng tới súng bắn tốc độ, nền đỏ khi đang quá tốc độ.
- **Quá tốc độ** (vượt quá 3 km/h) qua súng bắn tốc độ:
  - Còi "toét toét", cán bộ bước ra vẫy gậy. HUD hiện băng đỏ "CSGT vẫy — DỪNG XE!" kèm số mét.
  - Dừng trong 650 thì bị lập biên bản: phạt 4 lì xì, giữ 12 phút. Không dừng thì CSGT nổ máy đuổi theo (rượt đuổi như bỏ chạy).
- **Quay đầu trong vùng cấm quanh chốt** (±950): quay xong là bị gọi vào, phạt 3 lì xì, giữ 10 phút.
- **Biên bản vi phạm:** băng phản quang vàng chanh, tờ giấy kẻ dòng, dấu đỏ "ĐÃ GHI".
  - Ghi lỗi, tốc độ đo được / tốc độ cho phép, nơi vi phạm (km thứ mấy đoạn nào), mức phạt.
  - Chọn **Nộp phạt** hoặc **Bỏ chạy!**. Va chạm và vượt đèn đỏ cũng dùng biên bản này.
- **Camera phạt nguội:** 40% ngã tư trong phố có biển cấm quay đầu. Quay đầu ở đó thì vài giây sau báo "Camera phạt nguội", trừ 3 lì xì.

**Giao diện**
- **Thanh trên cùng:**
  - lộ trình, đồng hồ hai dòng (giờ + còn bao lâu tới giao thừa)
  - lì xì + hàng chở chung một ô
  - cụm tình trạng xe: xăng, tỉnh táo; lốp hỏng và mưa / áo mưa chỉ hiện khi có chuyện. Mức thấp thì nháy; nhiều mục quá thì tự thu nhỏ cho vừa.
- **Cột "đường phía trước"** bên phải, dưới nút tạm dừng: CSGT vẫy, đèn giao thông, cua gắt, biển tốc độ, cây xăng / tiệm vá gần nhất.
- **Nút tình huống:** hai dòng (tên + giá / thời gian) có icon tròn màu. Nhiều nút thì xếp thành hai hàng.
- **Bảng quán:** mái hiên sọc theo màu quán, mỗi món có hình minh hoạ vẽ riêng (cốc trà đá, nước mía, phin cà phê, bánh mì, xôi, đĩa cơm, áo mưa, vòi bơm, chai xăng, săm, lốp…).
  - Chuyện trò hiện thành bong bóng thoại nổi trên cảnh quán.
  - Cây xăng có màn hình cột bơm LED và đồng hồ bình E–F.
- **Bộ icon** vẽ bằng code, cùng một kiểu: cốc, cột bơm, chai, lốp, cờ lê, điện thoại, áo mưa, mây mưa, còi…

**Làm tiếp sau**
- Tắc đường ngày 28 Tết: xe đứng im cả km, len lỏi xe máy.
- Sương mù sáng sớm ở đèo; trời rét làm xe khó nổ máy.
- Đổ xăng nhầm / xăng pha, kẹt xe ở trạm thu phí giờ cao điểm.

### Vật phẩm, thắng thua
- **Vật phẩm:** lì xì để cộng điểm, trả phí cầu đường và nộp phạt. Quà Tết (bánh chưng, giỏ quà, cành đào) thì được chất lên xe. Lì xì và quà được mang theo qua các chặng.
- **Cơ chế chở đồ Tết:** mỗi món quà làm xe đánh lái nặng hơn, tăng tốc chậm hơn và phanh ăn kém hơn. Chở càng nhiều thì về tới nhà được càng nhiều điểm, nhưng xe càng khó lái và càng khó chạy thoát công an. Xe máy chịu ảnh hưởng nhiều hơn ô tô.
- **Thắng:** về tới nhà trước giao thừa. Điểm tính từ lì xì còn lại, số quà chở về và thời gian còn dư, chấm 1–3 sao. Thành tích lưu theo từng tuyến (điểm đi → điểm đến) và loại xe.
- **Thua** khi xảy ra một trong ba:
  - **Hết giờ:** quá giao thừa mà chưa về tới nhà.
  - **Bị công an bắt** khi bỏ chạy.
  - **Tai nạn:** đâm mạnh vào xe khác hoặc barrier.
- Thua ở giữa một chuyến dài thì chơi lại thế nào: xem mục 9, câu 2.

---

## 5. Ghép vào kiến trúc hiện có

Flame lo phần lái xe. Flutter + GetX lo menu, bản đồ lên lộ trình, trạm dừng nghỉ, HUD, cần lái, cụm nút, chat và các màn phủ lên game, đúng chuẩn `flutter_architecture.md`.

```
lib/
├── game/                            # toàn bộ Flame, không phụ thuộc GetX
│   ├── ve_que_game.dart             # FlameGame + HasCollisionDetection, camera, vòng lặp
│   ├── game_config.dart             # mọi con số cân bằng: tỷ lệ km→phút, số xe tối đa, ngưỡng tai nạn, mức phạt, phí…
│   ├── vehicle_spec.dart            # thông số xe máy / ô tô
│   ├── run_state.dart               # trạng thái chặng đang chơi: km, giờ, tốc độ, lì xì, quà, sự cố
│   ├── components/
│   │   ├── road_piece.dart              # mảnh đường: thẳng, cong lên, cong xuống, ngã tư, trạm thu phí
│   │   ├── player_vehicle.dart          # xe người chơi: ga, phanh, đánh lái liên tục, bám cong, chồng quà
│   │   ├── vehicle_component.dart       # xe AI: cùng/ngược chiều, đường ngang, xi-nhan, phản ứng còi
│   │   ├── traffic_light_component.dart # đèn xanh/vàng/đỏ có đếm ngược
│   │   ├── toll_booth_component.dart    # buồng thu phí, barrier, làn không dừng
│   │   ├── police_component.dart        # xe công an
│   │   ├── warning_indicator.dart       # mũi tên cảnh báo xe vượt từ phía sau
│   │   ├── darkness_layer.dart          # trời tối theo giờ + chùm đèn
│   │   ├── pothole_component.dart       # ổ gà
│   │   └── collectible_component.dart   # lì xì / quà
│   └── managers/
│       ├── road_builder.dart            # sinh các mảnh đường theo loại đoạn của chặng
│       ├── traffic_manager.dart         # sinh xe (thưa), xe AI không tự đâm nhau, luôn chừa đường thoát
│       ├── incident_manager.dart        # phân loại va chạm nhẹ / tai nạn; công an → nộp phạt / rượt đuổi
│       └── difficulty_manager.dart      # tăng nhẹ độ khó, vẫn giữ đường thưa
├── model/
│   ├── place.dart                   # điểm trên bản đồ: tên, toạ độ trên ảnh
│   ├── road_link.dart               # đoạn nối 2 điểm: km, loại đường, vị trí trạm thu phí
│   └── trip.dart                    # chuyến đi: lộ trình, các chặng, tiến độ, giờ xuất phát
├── resource/
│   └── vn_route_data.dart           # danh sách điểm + đường nối (nhập tay)
├── service/
│   ├── route_service.dart           # tìm đường, ước tính thời gian, chia chặng
│   └── local_service.dart           # thêm LocalKey: currentTrip, records, totalLixi, soundOn
└── screen/
    ├── home/             # menu: Về quê, Tiếp tục chuyến đi, kỷ lục, âm thanh
    ├── choose_mode/      # Tự lái xe / Đi xe khách (Sắp có)
    ├── plan_trip/        # bản đồ: chọn điểm đi, điểm đến, loại xe → vẽ đường, ước tính thời gian
    ├── rest_stop/        # trạm dừng nghỉ giữa các chặng, lưu tiến độ
    └── game/             # game_controller + game_view (GameWidget + HUD, Tạm dừng, Kết quả)
        ├── steering_stick.dart     # cần lái nổi góc dưới bên trái
        ├── action_buttons.dart     # cụm nút kiểu MOBA góc dưới bên phải
        ├── chat_overlay.dart       # ô nhập chat, dải hiện tin nhắn phía trên
        └── incident_overlay.dart   # bảng chọn Nộp phạt / Chạy, thanh khoảng cách khi rượt đuổi
```

### Màn ngang và kích thước
- **Khoá màn ngang ở native.** Bước setup base đã khoá dọc trong `AndroidManifest.xml` và `Info.plist`; giờ đổi sang chỉ ngang (cả xoay trái lẫn xoay phải). Việc này đi ngược quy tắc "luôn cố định xoay dọc" trong `flutter_architecture.md`, nhưng là cố ý vì đây là game ngang.
- **ScreenUtil:** đổi kích thước thiết kế từ 390×884 (dọc) sang 884×390 (ngang). Toàn bộ app đều dựng theo khung ngang.
- **Camera:**
  - Chiều cao vừa đủ 4 làn + vỉa hè; chiều ngang là tầm nhìn phía trước.
  - Camera bám theo xe hơi trễ. Theo hướng đi, vị trí xe trên màn hình lệch theo tốc độ, tạo cảm giác xe nhích lên khi tăng tốc. Camera xoay mượt theo hướng đường (xem "Đường không thẳng mãi").
  - Máy dài (điện thoại) nhìn xa hơn máy gần vuông (iPad). Trên iPad, camera thu nhỏ để vẫn đủ tầm nhìn tối thiểu.
- **Ngón tay và nút che một phần đường:**
  - Cụm nút bên phải che phía xa của đường, đúng chỗ xe mới xuất hiện. Nút bán trong suốt, vòng cung gom sát góc. Khi tính "luôn có đường thoát", xe chỉ được coi là người chơi đã thấy khi đã ra khỏi vùng bị che.
  - Cần lái và ngón cái trái che góc dưới-trái. Vùng cần lái chỉ nằm trên vỉa hè dưới cùng, và đường được đặt lệch lên trên một chút.
- **Tai thỏ/Dynamic Island ở cạnh trái hoặc phải** khi cầm ngang, nên HUD, cần lái và cụm nút phải chừa vùng an toàn hai bên.
- **Status bar:** game ngang thường ẩn hẳn status bar. Tài liệu `hide_top_and_bottom_navigator_bar.md` hiện chỉ làm status bar trong suốt, nên đề xuất ở P0 mở rộng `MainActivity.kt` để ẩn luôn status bar.

### Bản đồ
- Màn lên lộ trình dùng `InteractiveViewer` để kéo và phóng to ảnh bản đồ. Các điểm là widget đặt theo toạ độ; đường đi vẽ bằng `CustomPainter`.
- Ảnh bản đồ to nên phải có `cacheWidth` theo cỡ hiển thị, đúng quy tắc ảnh trong `flutter_architecture.md`.
- Chuyến đang dở lưu vào `LocalService` (`currentTrip`) mỗi khi tới trạm dừng nghỉ.

### Xe AI và tính công bằng
- Đường thưa xe nên dễ đảm bảo công bằng hơn: số xe trên màn hình bị giới hạn trong `game_config.dart`.
- Xe AI cùng làn không tự đâm nhau: xe nhanh phía sau sẽ giảm tốc theo xe chậm phía trước, hoặc chuyển làn có xi-nhan. Xe AI cũng dừng đèn đỏ.
- Mọi lúc luôn phải có ít nhất một đường thoát, có tính đến tốc độ hiện tại, tốc độ đánh lái và quãng phanh của loại xe đang chơi.
- Xe vượt từ phía sau, xe chuyển làn, đèn sắp chuyển đỏ luôn có báo trước. Người chơi chỉ bị phạt hoặc gặp tai nạn vì thứ họ đã kịp thấy. Điều này càng quan trọng vì tai nạn là thua ngay.

### Các quy tắc khác
- **Nối game với GetX:** `GameController` giữ đối tượng game và đưa giá trị Rx cho HUD dùng qua `Obx`. Game chỉ đẩy giá trị khi số hiển thị thật sự đổi, nên HUD không bị dựng lại mỗi frame.
- **Các màn và overlay Flutter** (menu, chọn cách về, bản đồ, trạm dừng nghỉ, chat, bảng Nộp phạt/Chạy, Tạm dừng, Kết quả) vẫn dùng `AppText`, `AppColors`, `CupertinoButton` và icon PNG.
- **Cần lái** là cử chỉ kéo nên dùng `GestureDetector`/`Listener`, đúng ngoại lệ "các cử chỉ khác vẫn dùng GestureDetector" trong tài liệu kiến trúc.
- **Cụm nút ga, phanh, còi, đèn không dùng `CupertinoButton`** mà dùng `Listener`, bắt ngay lúc ngón tay chạm xuống. `CupertinoButton` chỉ chạy khi nhấc tay ra, chậm khoảng 0,1 giây, đủ để đâm xe. Đây là ngoại lệ cố ý so với `flutter_architecture.md`. Icon các nút vẫn là PNG.
- **Bàn phím khi chat:** bàn phím mở ra sẽ kéo thanh điều hướng Android hiện theo; `MainActivity.kt` (theo tài liệu ẩn thanh điều hướng) đã tự ẩn lại khi bàn phím đóng.
- **Đường dẫn ảnh:** vẫn khai báo trong `Img`. Flame mặc định tự thêm tiền tố `assets/images/`, nên sẽ đặt `images.prefix = ''` để dùng thẳng `Img.xxx`.
- **Âm thanh:** cần thêm thư mục `assets/audio/` vì `flame_audio` đọc file ở đó. Đây là thư mục nằm ngoài 3 thư mục chuẩn trong tài liệu kiến trúc.
- **Hiệu năng:** mảnh đường, xe và vật thể ra khỏi màn hình thì xoá ngay. Vùng va chạm nhỏ hơn hình vẽ khoảng 15–20%.
- **Package:** `flame ^1.38.2` và `flame_audio ^2.12.2`. Đã chạy thử `flutter pub add --dry-run` (thêm thử, không cài thật) và cả hai đều tương thích với Flutter 3.47 của project. Bản đồ vẽ sẵn và chat không cần thêm package nào.

---

## 6. Các giai đoạn

### P0 — Setup (khoảng 1 ngày)
- Thêm package, tạo `lib/game/`, thêm `AppPage.game`, đổi Home thành menu.
- Khoá màn ngang ở native, đổi kích thước thiết kế ScreenUtil sang 884×390, ẩn status bar.
- ✅ **Xong khi:** app mở lên ở màn ngang, từ menu vào được màn game trống và quay về được.

### P1 — Lái xe cơ bản bằng hình khối (9–11 ngày) — *giai đoạn quan trọng nhất*
- Chưa dùng art: xe chỉ là hình chữ nhật màu, nút chỉ là hình tròn có chữ.
- **Đường ghép từ mảnh, có khúc cong ngay từ đầu.** Nếu làm đường thẳng trước rồi mới thêm cong thì phải viết lại phần đường, va chạm và camera.
- Cần lái nổi bên trái; ga và phanh bên phải chạy thật. Còi, đèn, chat chưa có tác dụng.
- Chỉ xe máy, nhưng thông số đã tách ra `vehicle_spec.dart`.
- Xe thưa, có cả cùng chiều và ngược chiều; ổ gà.
- Phân loại va chạm nhẹ / tai nạn; công an bản đơn giản (bảng chọn, rượt đuổi với thanh khoảng cách).
- Chơi một chặng quốc lộ cố định khoảng 3 phút, có đích và đồng hồ; đủ 3 cách thua.
- Viết unit test cho phần logic: luôn có đường thoát, xe AI không tự đâm nhau, xe bám cong khi cần lái ở giữa, tốc độ theo ga/phanh, phân loại va chạm, kết quả rượt đuổi.
- ✅ **Xong khi:**
  - Chơi trọn được một chặng và tự trả lời được câu "có vui không?". Nếu chưa vui thì sửa luật chơi ngay ở bước này.
  - Đã chơi thử trên máy thật để xem cách cầm hai tay (cần lái trái, cụm nút phải) có thoải mái không.
  - Đã kiểm tra tai nạn không xảy ra "oan", và công an không xuất hiện quá dày.

### P2 — Lộ trình, bản đồ, đèn đỏ, trạm thu phí, ô tô (12–15 ngày)
- Màn chọn cách về (Tự lái xe / Đi xe khách "Sắp có").
- Màn lên lộ trình: bản đồ (ảnh tạm), chọn điểm đi, điểm đến, loại xe; vẽ đường; hiện quãng đường và thời gian ước tính.
- Dữ liệu khoảng 20–30 điểm và các đường nối; tìm đường ngắn nhất; xe máy không đi cao tốc.
- Sinh chặng từ lộ trình theo loại đoạn đường (nội thành, quốc lộ, cao tốc); giờ xuất phát tính ngược từ giao thừa; thanh tiến trình chặng trên HUD.
- Ngã tư đèn xanh đèn đỏ có xe đường ngang; trạm thu phí có làn thường, làn không dừng, làn xe máy.
- Ô tô với thông số riêng.
- Trạm dừng nghỉ giữa các chặng, lưu tiến độ, nút "Tiếp tục chuyến đi" ở menu.
- ✅ **Xong khi:** chọn Hà Nội → Vinh bằng xe máy và bằng ô tô thì thấy hai đường khác nhau trên bản đồ; chơi hết các chặng, gặp đèn đỏ và trạm thu phí; thoát app giữa chừng rồi chơi tiếp được.

### P3 — Còi, đèn, chat, thêm tình huống, chở đồ, hoàn thiện vòng chơi (9–11 ngày)
- **Còi:** xe phía trước nhường đường hoặc bóp còi lại, nút có hồi chiêu quét tròn. **Đèn:** trời tối theo giờ của chuyến đi, bật đèn để nhìn xa.
- **Chat:** nút chat, ô nhập, tin nhắn hiện phía trên màn hình rồi mờ dần.
- Thêm các tình huống: xe vượt từ phía sau, xe máy chuyển làn có xi-nhan, xe chở cành đào/cây quất.
- Quà chất lên xe làm xe khó lái hơn; ổ gà làm rơi quà.
- Làm đẹp sự cố công an và tai nạn: còi hú, đèn xanh đỏ nhấp nháy, chậm hình lúc đâm xe.
- HUD đầy đủ, màn tạm dừng, màn kết quả chấm sao, lưu thành tích theo tuyến và loại xe.
- ✅ **Xong khi:** chơi trọn một chuyến từ lúc chọn lộ trình tới lúc về nhà, hai loại xe cho cảm giác khác nhau rõ.

### P4 — Art + âm thanh = MVP
- **Nguồn art (đã chốt):** không thuê, không vẽ tay. Lấy asset miễn phí giấy phép CC0, phần còn thiếu thì Claude tự vẽ bằng code. Danh sách nguồn và giấy phép ghi ở `document/asset_credits.md`.
  - **Xe:** gói Racing Pack của Kenney (CC0), nhìn từ trên xuống, có ô tô nhiều kiểu và xe máy.
  - **Cần lái, nút, icon:** gói Mobile Controls của Kenney (CC0), kiểu "Style H" (tròn, nền tối bán trong suốt).
  - **Tự vẽ bằng code** (gói miễn phí không có): mặt đường và vạch kẻ (vẽ theo khúc cong), vỉa hè, cảnh ven đường, lì xì, bánh chưng, cành đào, cây quất, đèn giao thông, trạm thu phí, xe công an, icon còi và đèn, bản đồ Việt Nam.
  - Phong cách theo Kenney: phẳng, viền đậm, màu tươi. **Không làm pixel art nữa**, để mọi thứ đồng bộ với bộ xe.
  - SpriteLab (tạo sprite bằng AI) cần đăng nhập và thao tác trên web nên Claude không dùng trực tiếp được.
- Thay hình khối bằng art:
  - **Bản đồ Việt Nam** cho màn lên lộ trình.
  - **Mảnh đường** cho từng loại đoạn: thẳng, cong lên, cong xuống, ngã tư có cột đèn, trạm thu phí, cầu; cảnh ven đường cho nội thành, quốc lộ, cao tốc.
  - Xe người chơi: xe máy (đồ chất sau yên) và ô tô (đồ buộc trên nóc). 4–5 loại xe AI và xe công an.
  - Cần lái, icon cụm nút điều khiển, hình cho màn chọn cách về.
- Hiệu ứng làm xe "sống": nghiêng xe khi đánh lái, nảy lên khi qua ổ gà, đèn phanh đỏ, vệt gió/khói khi tăng tốc, xi-nhan nhấp nháy, rung màn hình khi đâm xe, hạt sáng khi nhặt lì xì.
- Âm thanh: tiếng máy xe máy và ô tô, tiếng phanh, còi của mình và còi xe khác, còi hú công an, tiếng barrier, tiếng nhặt lì xì, tiếng va chạm, nhạc nền, nhạc dồn dập khi bị đuổi. Lấy từ gói âm thanh CC0 của Kenney; tiếng máy, còi, còi hú và nhạc nền thì Claude tự tổng hợp bằng code (không vướng bản quyền).
- Đo RAM trên một máy Android yếu theo cách trong `flutter_architecture.md`.
- ✅ **Xong khi:** đã cho 5–10 người chơi thử và ghi lại họ bị kẹt hay thấy chán ở đâu.

### P5 — Sau MVP (chọn dần theo phản hồi)
- **Chế độ đi xe khách** (chưa thiết kế luật chơi).
- Đoạn đèo (cua gắt, chạy nhanh là văng) và đường làng (đường nhỏ, vịt, chó).
- Các tình huống còn lại trong bảng ở mục 4; chốt kiểm tra nồng độ cồn.
- Đèn pha/cốt: pha nhìn xa hơn nhưng làm chói xe ngược chiều.
- "Phạt nguội" (tuỳ chọn): chạy thoát nhưng cuối chuyến có thể nhận giấy phạt nguội. Hiện plan vẫn giữ đúng ý "chạy thoát thì không sao cả".
- Chat cho người khác cùng thấy (cần máy chủ và lọc từ ngữ).
- Nâng cấp xe ở trạm dừng nghỉ, mở khoá thêm xe, thêm điểm trên bản đồ.
- Sự kiện vui: mẹ gọi "bao giờ con về?". Cảnh đoàn tụ khi về tới nhà. Quảng cáo có thưởng.

---

## 7. Mốc thời gian

Claude code liên tục, nên không áp dụng ước lượng "một người làm toàn thời gian" của bản plan trước. **Mục tiêu: khoảng 4 ngày làm việc liên tục** cho toàn bộ P0–P4.

| Ngày | Việc |
|---|---|
| 1 | P0 + P1: setup, màn ngang, đường cong, cần lái, ga/phanh, xe AI, va chạm, công an |
| 2 | P2: chọn cách về, bản đồ lên lộ trình, chia chặng, đèn đỏ, trạm thu phí, ô tô, trạm dừng nghỉ |
| 3 | P3: còi, đèn và trời tối, chat, thêm tình huống, chở đồ, HUD, kết quả |
| 4 | P4: thay art và âm thanh, đánh bóng, sửa lỗi |

Chơi thử trên máy thật và chỉnh cân bằng vẫn cần người chơi (bạn) tham gia sau mỗi ngày.

> Phạm vi MVP chốt theo plan này. Ý mới đưa vào P5, trừ khi bỏ bớt một thứ khác.

---

## 8. Rủi ro thấy trước

- **Art là chỗ dễ tắc nhất:** bản đồ, các mảnh đường cong, ngã tư, trạm thu phí, hai loại xe người chơi, nhiều loại xe AI, xe công an, cần lái và icon cụm nút. P1–P3 làm bằng hình khối để không phải chờ art.
- **Đường cong làm mọi thứ phức tạp hơn:** đánh lái, va chạm, camera, sinh xe đều phải tính theo đường cong. Vì vậy làm ngay từ P1.
- **Tai nạn là thua ngay, nên rất dễ thấy "oan".** Người chơi phải luôn hiểu vì sao mình thua:
  - Vòng tốc độ đổi đỏ ở tốc độ nguy hiểm.
  - Xe nào lao tới cũng phải được báo trước.
  - Ngưỡng tai nạn chỉnh được trong `game_config.dart`.
  - Chơi thử kỹ ở P1.
- **Thua ở chuyến dài rất nặng tay.** TP.HCM → Hà Nội khoảng 85 phút chơi; tai nạn ở chặng gần cuối mà phải đi lại từ đầu thì người chơi sẽ bỏ game. Cần chốt cách chơi lại (mục 9, câu 2).
- **Dữ liệu khoảng cách nhập tay có thể sai.** Đối chiếu với Google Maps khi nhập, và ghi rõ "ước tính" trên màn hình.
- **Chủ đề công an và bỏ chạy khá nhạy cảm,** nhất là nếu phát hành ở Việt Nam, nơi game phải tuân thủ quy định về nội dung. Cách giảm rủi ro:
  - Vẽ công an kiểu hoạt hình; không dùng quân hàm, phù hiệu, biển số hay màu đồng phục giống thật.
  - Giữ giọng hài hước, không bạo lực; tai nạn chỉ thể hiện bằng xe móp và khói, không có người bị thương.
  - Hỏi bên phát hành hoặc người am hiểu pháp lý trước khi đưa lên store Việt Nam.
- **Hai tay che màn hình.** Ngón cái trái che góc dưới-trái, cụm nút phải che phía xa bên phải. Đã tính trong bố cục (mục 5), nhưng phải kiểm tra trên máy thật ở P1, nhất là máy màn nhỏ.
- **Cụm nút và cần lái sát mép dưới.** Trên iOS, vuốt lên từ mép dưới sẽ về màn hình chính, mà cần lái lại là cử chỉ kéo lên/xuống. Cách xử lý:
  - Chừa khoảng cách với mép dưới.
  - Trên iOS, bật chế độ "vuốt hai lần mới thoát" bằng một chút code native.
  - Chặn cử chỉ quay lại ở màn game bằng `PopScope`.
- **Trời tối phải vẽ đẹp mà không nặng máy.** Thử lớp tối + chùm đèn trên máy yếu ngay từ P3.
- **Bản quyền nhạc.** Các bài nhạc Tết quen thuộc đều có bản quyền, nên phải dùng nhạc tự làm hoặc nhạc miễn phí bản quyền.

---

## 9. Các câu đã chốt

1. **Art:** dùng asset miễn phí CC0 (Kenney), phần thiếu thì Claude tự vẽ bằng code; phong cách phẳng giống Kenney thay cho pixel art. *(người dùng chốt)*
2. **Thua ở giữa chuyến dài:** được chơi lại từ trạm dừng nghỉ gần nhất. *(tạm theo đề xuất)*
3. **Phát hành:** làm đủ như plan trong khoảng 4 ngày; thị trường phát hành chưa chốt. *(người dùng chốt thời gian)*
4. **Bản đồ:** bản đồ vẽ sẵn, chạy offline. *(tạm theo đề xuất)*
5. **Vị trí cần lái:** góc dưới bên trái cho tay trái. *(tạm theo đề xuất)*
6. **Tin nhắn chat:** hiện ở phía trên màn hình. *(tạm theo đề xuất)*

Các mục "tạm theo đề xuất" đổi được bất cứ lúc nào, chỉ cần báo.
