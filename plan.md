## Kế hoạch Kỹ thuật: Hệ thống Quét & Đọc AprilTag Realtime

Tài liệu này tổng hợp bối cảnh vận hành, các thông số ràng buộc vật lý, và kiến trúc giải pháp kỹ thuật hoàn chỉnh cho bài toán nhận diện AprilTag trong hầm giao thông.

---

### 1. Bối cảnh & Điều kiện Vận hành (Operational Context)

| Yếu tố              | Thông số / Hiện trạng                                         | Đánh giá & Ràng buộc kỹ thuật                                                           |
| ------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Phương tiện**     | Ô tô di chuyển trong hầm                                      | Tốc độ $\approx 20\text{ km/h}$ ($5.55\text{ m/s}$). Rung lắc cơ học khi di chuyển.     |
| **Không gian**      | Hầm rộng $\approx 14\text{m}$, hoàn thiện, đủ sáng            | Xe chạy giữa làn $\to$ khoảng cách từ capo tới vách hầm khoảng **$6.0 - 6.5\text{m}$**. |
| **Hành trình**      | Chạy 2 chiều (vào hầm và quay đầu ra)                         | Vách có tag sẽ đổi từ bên này sang bên đối diện tùy hướng di chuyển.                    |
| **Mục tiêu (Tag)**  | Khổ A3 ($29 \times 29\text{ cm}$ vùng mã), dán phẳng áp tường | Dán ngang tầm mắt camera. Mật độ: $50\text{m}$/tag ($\approx 9$ giây/tag).              |
| **Payload**         | $\approx 100$ chuỗi text ngắn ($< 10$ ký tự)                  | Dùng bảng tra cứu (Lookup table): Ánh xạ `Tag ID` $\to$ `String`.                       |
| **Chuẩn Tag**       | `tagStandard41h12`                                            | Lưới $9 \times 9$, sửa lỗi Hamming 12, tối đa 2.115 IDs.                                |
| **Camera**          | **Ricoh Theta X** (bắt buộc)                                  | Live stream UVC H.264 4K ($3840 \times 1920$) @ $\approx 30$ fps. Rolling shutter.      |
| **Phần cứng xử lý** | Laptop Intel Core Ultra 7 165U, 16GB RAM                      | Không GPU rời. Khai thác iGPU qua Intel VA-API / QSV và CPU đa nhân.                    |
| **Hệ điều hành**    | Ubuntu Linux                                                  | libuvc-theta + GStreamer + V4L2 loopback + Python/C++ (`pupil-apriltags`).              |

---

### 2. Thiết lập Vật lý & Thiết bị (Physical Setup)

- **Hướng đặt Camera:**
  - Xoay thân Ricoh Theta X sao cho **2 thấu kính chĩa trực diện sang 2 bên vách hầm** (thấu kính trước nhìn vách phải, thấu kính sau nhìn vách trái).
  - *Mục đích:* Tránh mép stitching rơi vào bức tường có tag. Đưa mục tiêu vào vùng quang học nét nhất ở tâm thấu kính.
- **Gá đặt:** Giá hít capo 3 điểm, tích hợp ngàm chống rung vi mô.
- **Cấu hình phơi sáng:** Shutter tối thiểu **$1/250\text{s}$** (khuyến nghị $1/500\text{s}$); ISO tự động bù sáng.

---

### 3. Kiến trúc Pipeline Xử lý (Data Processing Pipeline)

Theta X **không** expose `/dev/videoX` capture thật — kernel chỉ thấy `/dev/media*`. Luồng H.264 đi qua **libuvc-theta**. Để app V4L2/OpenCV dùng được, đổ vào **v4l2loopback** cố định `/dev/video1`.

```
       [Ricoh Theta X] LIVE (USB 05ca:2717, H.264 4K @ ~30 FPS)
              │ libuvc-theta
              ▼
    [gst_loopback]  decodebin → I420 → v4l2sink
              │
              ▼
    [/dev/video1]  v4l2loopback (card_label=ThetaX)   ← node “capture” cho app
              │
              ▼
    [Thread 1: Ingestion]
       • v4l2src device=/dev/video1  (hoặc đọc thẳng appsink sau decode)
       • HW decode ưu tiên VA-API H.264 (vaapih264dec / vah264dec) — KHÔNG dùng vaapijpegdec
       • queue max-size-buffers=1 leaky=downstream
              │
              ▼ (throttle 10–12 FPS)
    [Thread 2: Dual-Viewport Rectification]
       • remap 2 view: yaw 90° / 270°, FOV ≈ 70° → 1280×720
              │
              ▼
    [Thread 3: AprilTag] pupil-apriltags tagStandard41h12
              │
              ▼
    [Thread 4: Debounce 6s + lookup ID→text]
```

**Upstream:**
- https://github.com/ricohapi/libuvc-theta
- https://github.com/ricohapi/libuvc-theta-sample

**Tự động hoá (Ubuntu):** xem `scripts/setup-node-camera-theta/` (+ `README.md`) — `install.sh`, `start-loopback.sh`, udev + systemd. Không cài trên máy Windows dev.

---

### 4. Chi tiết các Khâu Kỹ thuật Cốt lõi

#### Khâu 0: Bridge camera → V4L2 (bắt buộc trước ingestion)

| Bước | Việc làm |
|------|----------|
| 1 | Camera **LIVE** (`lsusb` → `05ca:2717`; nếu thấy `05ca:0373` thì vẫn đang camera/MTP mode) |
| 2 | `v4l2loopback` tạo `/dev/video1` (`card_label=ThetaX`) |
| 3 | `gst_loopback` (sample đã patch PID X + device 42) đẩy frame vào node đó |
| 4 | App mở `/dev/video1` — **đây là “capture stream” dùng được**, không phải `/dev/media*` của Theta |

Cài một lần trên Ubuntu:

```bash
cd scripts/setup-node-camera-theta
sudo ./install.sh          # clone, build, patch, udev, systemd
./status.sh                # kiểm tra USB / video1 / service
# cắm Theta LIVE → service tự start; hoặc:
sudo ./start-loopback.sh
```

Sau đó test nhanh:

```bash
v4l2-ctl --list-devices
gst-launch-1.0 v4l2src device=/dev/video1 ! videoconvert ! autovideosink sync=false
```

#### Khâu 1: Lấy luồng & Giải mã (Ingestion)

- **Không** dùng `v4l2src` trực tiếp lên device USB của Theta (không có).
- **Không** dùng `vaapijpegdec` — live stream là **H.264**, không phải MJPEG.
- Đường chuẩn V4L2: `v4l2src device=/dev/video1 ! ...` (frame đã decode sẵn I420 từ `gst_loopback`).
- Đường tối ưu latency (tùy chọn sau): `thetauvcsrc` / pipeline GStreamer bỏ loopback; decode VA-API `vaapih264dec`/`vah264dec` trên iGPU Ultra 7.
- `queue max-size-buffers=1 leaky=downstream` để luôn giữ frame mới nhất.

#### Khâu 2: Nắn phối cảnh 2 mạn sườn (Dual-Viewport Rectification)

- Tag cong trên equirectangular làm hỏng quad detection.
- Chỉ chiếu Gnomonic cho hai góc: yaw $= 90^\circ$ và $270^\circ$, pitch $= 0^\circ$, FOV $\approx 70^\circ$.
- Precompute `(map_x, map_y)` $1280\times720$; runtime chỉ `cv::remap` ($< 3\text{ms}$/frame).

#### Khâu 3: Nhận diện (`pupil-apriltags`)

- Quét $10$–$12$ FPS tổng (mỗi vách $5$–$6$ FPS). Tag hiện $1.5$–$2.0\text{s}$ → khoảng $8$–$12$ cơ hội đọc.
- `quad_decimate=1.0`, `refine_edges=1`.

#### Khâu 4: Hậu xử lý

- Lookup JSON/YAML `{ID: text}`.
- Debounce 6 giây / ID chống spam khi xe lướt ngang.

---

### 5. Kế hoạch Triển khai (Next Steps)

1. **Giai đoạn 1 (Bench — Ubuntu):**  
   - Copy `scripts/setup-node-camera-theta` sang máy Ubuntu → `sudo ./install.sh`.  
   - Xác nhận `/dev/video1` có hình (`gst-launch` / VLC).  
   - Đo latency loopback; nếu cao quá cho AprilTag → cân nhắc bỏ loopback, đọc GStreamer trực tiếp.  
   - Tag A3 mẫu, khoảng 6 m, test `remap` + detect.

2. **Giai đoạn 2 (Module coding):**  
   Ingestion (`/dev/video1`), rectification, detection, debounce/lookup.

3. **Giai đoạn 3 (Field test hầm):**  
   $15$–$25\text{ km/h}$, tinh chỉnh shutter.

---

### 6. Ghi chú vận hành / lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp |
|-------------|------------------------|
| `THETA not found` | Camera chưa LIVE (`lsusb` còn `05ca:0373` thay vì `2717`), hoặc sample chưa patch PID `0x2717` |
| `lsusb` ra `05ca:0373` | Bình thường khi chưa bật LIVE — không phải lỗi USB; bật live streaming rồi kiểm tra lại `2717` |
| `not an output device` | `v4l2sink` trỏ nhầm `/dev/video` thật (webcam) thay vì loopback |
| Chỉ thấy `/dev/media1` cho Theta | Bình thường — không có capture V4L2 native |
| Service start rồi thoát | Chưa patch `THETA_DAEMON` / keywait đọc EOF |
| Decode lỗi | Thiếu `gstreamer1.0-libav` / plugins ugly; hoặc VA-API chưa `vainfo` OK |
