# Nghiệm thu Phase 0 — Bridge Ricoh Theta X → V4L2

**Trạng thái:** ✅ Đạt (đã triển khai & xác nhận live trên máy Ubuntu `livo-monitor`)  
**Phạm vi:** Chỉ Khâu 0 trong [`plan.md`](../plan.md) — đưa luồng LIVE của Theta X thành node capture V4L2 để app đọc được.  
**Không thuộc Phase 0:** remap dual-viewport, AprilTag, debounce, lookup JSON, cấu hình shutter/ISO, đo latency tối ưu.

---

## 1. Mục tiêu Phase 0

Theta X **không** cung cấp `/dev/videoX` capture native trên Linux (kernel chỉ thấy `/dev/media*`). Live stream là **H.264** qua USB khi camera ở chế độ LIVE (`05ca:2717`).

Phase 0 giải quyết đúng một việc:

> Cắm Theta X (LIVE) → tự động (hoặc thủ công) có **`/dev/video1`** chứa frame **I420 3840×1920 @ ~30 fps** để `v4l2src` / OpenCV mở được.

---

## 2. Kiến trúc đã triển khai

```text
[Ricoh Theta X]  LIVE USB 05ca:2717  (H.264 4K)
        │
        ▼  libuvc-theta (build vào /usr/local)
[gst_loopback]   = symlink → gst_viewer (libuvc-theta-sample, đã patch)
        │  decodebin → autovideoconvert → I420
        │  → v4l2sink device=/dev/video1 qos=false sync=false
        ▼
[/dev/video1]    v4l2loopback  card_label=ThetaX
        │
        ▼
  App / gst-launch / VLC   ← điểm giao tiếp Phase sau
```

**Lưu ý decode:** H.264 được giải mã **bên trong** `gst_loopback` (`decodebin`). Node `/dev/video1` đã là raw I420 — app Phase sau **không** cần `vaapijpegdec` / MJPEG. Tối ưu VA-API H.264 (bỏ loopback) là tùy chọn sau, chưa làm.

---

## 3. Artifact trong repo

Thư mục: [`scripts/setup-node-camera-theta/`](../../scripts/setup-node-camera-theta/)

| File | Vai trò đã triển khai |
|------|------------------------|
| `theta.conf` | Cấu hình trung tâm: `THETA_VIDEO_NR=1`, `THETA_CARD_LABEL=ThetaX`, USB VID/PID LIVE `05ca:2717`, path `/opt/theta`, `THETA_DAEMON=1` |
| `install.sh` | One-shot Ubuntu: apt deps, clone/build libuvc-theta + sample, gọi patch, modprobe loopback cố định `video_nr`, cài udev + enable systemd, copy script ổn định sang `/opt/theta/bin/` |
| `apply-patches.sh` | Vá sample: thêm PID Theta X `0x2717`, `v4l2sink` → `/dev/video${THETA_VIDEO_NR}`, `qos=false`, `THETA_DAEMON` (keywait sleep vô hạn cho systemd) |
| `start-loopback.sh` | Đảm bảo node loopback tồn tại → đợi USB LIVE → `exec gst_loopback` |
| `status.sh` | Kiểm tra nhanh: USB LIVE vs `0373`, `/dev/videoN`, binary, systemd |
| `udev/99-theta-x.rules` | `add` PID `2717` → `SYSTEMD_WANTS=theta-loopback`; `remove` → stop service |
| `systemd/theta-loopback.service` | Service `Type=simple`, restart on-failure; `ExecStart` override trỏ `/opt/theta/bin/start-loopback.sh` |
| `README.md` | Hướng dẫn cài, vận hành, troubleshooting; số liệu đối chiếu máy thật |

Sau `install.sh`, runtime ổn định nằm ở **`/opt/theta/`** (không phụ thuộc clone repo trên máy chạy).

**Upstream dùng:**

- https://github.com/ricohapi/libuvc-theta  
- https://github.com/ricohapi/libuvc-theta-sample  

---

## 4. Cấu hình đã chốt (máy `livo-monitor`)

| Tham số | Giá trị | Ý nghĩa |
|---------|---------|---------|
| Node capture cho app | `/dev/video1` | `THETA_VIDEO_NR=1` |
| Nhãn V4L2 | `ThetaX` | `card_label` khi `modprobe v4l2loopback` |
| Pixel format | `YU12` / caps `I420` | Planar YUV 4:2:0 (cùng họ) |
| Độ phân giải | `3840 × 1920` | Equirectangular 4K dual-fisheye stitch |
| Framerate | `30000/1001` ≈ 29.97 fps | Khớp ~30 fps trong plan |
| USB LIVE | `05ca:2717` | Điều kiện bắt buộc để `gst_loopback` thấy camera |
| USB chưa LIVE | `05ca:0373` | Camera/MTP — script **cố ý không** start loopback |

> Trước đây từng mặc định `video42` — **sai với máy này**, đã chuẩn hoá về `1` trong conf + patch + doc.

---

## 5. Tiêu chí nghiệm thu & kết quả

| # | Tiêu chí | Cách kiểm | Kết quả |
|---|----------|-----------|---------|
| A | Camera ở LIVE | `lsusb -d 05ca:` → `2717` | ✅ Đạt khi bật LIVE |
| B | Có node loopback đúng số | `v4l2-ctl --list-devices` → `ThetaX` → `/dev/video1` | ✅ |
| C | Node có format stream | `v4l2-ctl -d /dev/video1 --list-formats-ext` → YU12 3840×1920 @ ~30 | ✅ |
| D | Pipeline đọc được frame | `gst-launch-1.0 v4l2src device=/dev/video1 ! fakesink -v` (hoặc `videoconvert ! autovideosink`) | ✅ caps I420 3840×1920 |
| E | Cài đặt lặp lại được | `sudo ./install.sh` trên Ubuntu + README | ✅ Script đủ trong repo |
| F | Tự động khi cắm LIVE | udev + `theta-loopback.service` | ✅ Đã cài trong `install.sh` |

**Kết luận nghiệm thu:** Phase 0 **PASS**. App Phase sau được phép mặc định mở **`/dev/video1`** (hoặc giá trị `THETA_VIDEO_NR` nếu máy khác đổi conf trước install).

---

## 6. Quy trình vận hành đã có

### Cài một lần (Ubuntu)

```bash
cd scripts/setup-node-camera-theta
# xác nhận THETA_VIDEO_NR trong theta.conf (mặc định 1)
sudo ./install.sh
./status.sh
```

### Mỗi lần dùng

1. Bật **LIVE** trên Theta X (đến khi `lsusb` ra `05ca:2717`).
2. Cắm USB — udev start `theta-loopback` (hoặc `sudo systemctl start theta-loopback` / `sudo ./start-loopback.sh`).
3. Xác nhận hình:

```bash
./status.sh
v4l2-ctl -d /dev/video1 --list-formats-ext
gst-launch-1.0 v4l2src device=/dev/video1 ! videoconvert ! autovideosink sync=false
```

---

## 7. Những gì **chưa** làm (ngoài Phase 0)

Ghi rõ để tránh nhầm “đã xong hệ thống AprilTag”:

| Hạng mục | Trạng thái |
|----------|------------|
| Dual-viewport remap (yaw 90° / 270°) | Code: `src/tag_reader/rectify.py` — chờ bench Ubuntu |
| `vendor/apriltag` / `tagStandard41h12` | Code: `src/tag_reader/detector.py` — chờ bench Ubuntu |
| Debounce 6s + lookup JSON ID→text | Chưa |
| Module đa luồng ingestion app | Chưa |
| Đo latency loopback / tối ưu bỏ loopback + VA-API H.264 | Chưa (todo Giai đoạn 1 còn lại) |
| Cấu hình shutter 1/250–1/500 + ISO | Chưa (thao tác trên camera/app Theta) |
| Bench tag A3 @ 6 m | Chưa |

---

## 8. Rủi ro / nợ kỹ thuật đã biết

1. **Decode trong `decodebin`:** có thể chạy CPU/libav chứ chưa ép `vaapih264dec`. Chấp nhận cho Phase 0; tối ưu iGPU Ultra 7 để sau.
2. **Số node `/dev/videoN` máy-dependent:** máy khác nếu `1` bị chiếm, phải đổi `THETA_VIDEO_NR` **trước** `install.sh`, chạy lại patch/build, và app phải cùng path.
3. **Bắt buộc LIVE `2717`:** quên bật LIVE → `THETA not found` / service fail — đây là hành vi đúng, không phải bug USB.
4. **Doc cũ:** mọi chỗ còn nhắc `video42` / MJPEG / `vaapijpegdec` cho đường chính là **lỗi thời** — đã chuẩn hoá về `/dev/video1` + H.264 → I420 qua loopback trong `plan.md` và README.

---

## 9. Bước tiếp theo (sau Phase 0)

Theo [`plan.md`](../plan.md) §5:

1. **Phase 1 — Bench:** xem [`../phase-1/README.md`](../phase-1/README.md) (tài liệu đã chốt; script/bench chưa chạy).  
2. **Phase 2:** code pipeline đọc `/dev/video1` → dual remap → AprilTag → debounce + JSON → console/log.

---

## 10. Tham chiếu chéo

| Tài liệu | Nội dung |
|----------|----------|
| [`plan.md`](../plan.md) | Kế hoạch kỹ thuật đầy đủ; Khâu 0–4 |
| [`scripts/setup-node-camera-theta/README.md`](../../scripts/setup-node-camera-theta/README.md) | Chi tiết cài đặt & troubleshooting vận hành |
