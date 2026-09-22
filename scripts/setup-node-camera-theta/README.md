# Setup node camera Theta (Ricoh Theta X → `/dev/videoX`)

Script cài và tự động hoá bridge **Ricoh Theta X (LIVE)** sang node V4L2 ảo trên **Ubuntu Linux**.

Theta X **không** có `/dev/video` capture thật — chỉ `/dev/media*`. Pipeline thực tế:

```text
Theta LIVE (USB 05ca:2717, H.264)
    → libuvc-theta + gst_loopback
    → v4l2loopback
    → /dev/video1  (mặc định; card_label=ThetaX)   ← app mở node này
```

Upstream:

- https://github.com/ricohapi/libuvc-theta
- https://github.com/ricohapi/libuvc-theta-sample

> Chạy toàn bộ script trên máy Ubuntu có camera. Không dùng để cài trên Windows.

---

## Đã đối chiếu trên `livo-monitor`

Khi `gst_loopback` đang đẩy frame, máy này có:

```bash
v4l2-ctl -d /dev/video1 --list-formats-ext
# YU12 (Planar YUV 4:2:0), Discrete 3840x1920, 29.970 fps

gst-launch-1.0 v4l2src device=/dev/video1 ! fakesink -v
# caps: video/x-raw, format=I420, width=3840, height=1920, framerate=30000/1001
```

| Tham chiếu | Script / README | Thực tế máy | Kết luận |
|------------|-----------------|-------------|----------|
| Node capture | `/dev/video1` (`THETA_VIDEO_NR=1`) | `/dev/video1` | Khớp |
| Pixel format | `I420` trong `gst_loopback` patch | `YU12` / caps `I420` | Khớp (cùng Planar 4:2:0) |
| Độ phân giải | 4K equirectangular | `3840×1920` | Khớp |
| FPS | ~30 | `30000/1001` ≈ 29.97 | Khớp |
| USB LIVE `05ca:2717` | `theta.conf` + udev | `05ca:2717` (sau khi bật LIVE) | Khớp — `0373` = chưa LIVE |

> Trước đây mặc định `video42` — **sai với máy này**. Đã đổi về `1`.

### USB product ID (Theta X) — quan trọng

| `lsusb` | Chế độ | `gst_loopback` / libuvc |
|---------|--------|-------------------------|
| `05ca:0373` | Camera / MTP (mặc định khi cắm) | **Không** — báo `THETA not found` |
| `05ca:2717` | **LIVE streaming** (UVC H.264) | **Có** — đúng PID script đang dùng |

Trên `livo-monitor` vừa đo: `05ca:0373` → camera **chưa** ở LIVE. Cần bật live streaming trên thân máy (hoặc setting auto-switch to streaming khi USB), rút/cắm lại nếu cần, rồi:

```bash
lsusb -d 05ca:
# kỳ vọng: ID 05ca:2717 Ricoh Co., Ltd RICOH THETA X
```

udev + `theta-loopback.service` chỉ kích hoạt khi thấy `2717` — **không** đụng `0373`. Đúng thiết kế.

---

## Cấu trúc

```text
scripts/setup-node-camera-theta/
├── README.md
├── theta.conf                ← số video, USB ID, đường dẫn /opt/theta
├── install.sh
├── apply-patches.sh
├── start-loopback.sh
├── status.sh
├── udev/99-theta-x.rules
└── systemd/theta-loopback.service
```

Sau `install.sh`, bản chạy ổn định nằm ở `/opt/theta/`.

---

## Cấu hình (`theta.conf`)

| Key | Mặc định | Ý nghĩa |
|-----|----------|---------|
| `THETA_VIDEO_NR` | `1` | Node `/dev/video1` (đúng với livo-monitor hiện tại) |
| `THETA_CARD_LABEL` | `ThetaX` | Nhãn trong `v4l2-ctl --list-devices` |
| `THETA_USB_PID_LIVE` | `2717` | Product ID khi camera LIVE |
| `THETA_PREFIX` | `/opt/theta` | Thư mục build/install |

Nếu trên máy khác loopback không phải `video1`, đổi `THETA_VIDEO_NR` **trước** `install.sh`, rồi rebuild/`apply-patches.sh` để `v4l2sink` trỏ đúng device. App cũng phải mở cùng path.

Cách nhận đúng số node:

```bash
v4l2-ctl --list-devices
# tìm dòng Dummy / v4l2loopback / ThetaX → /dev/videoN

v4l2-ctl -d /dev/videoN --list-formats-ext
# kỳ vọng YU12 3840x1920 @ ~30fps khi gst_loopback đang chạy
```

---

## Cài một lần (Ubuntu)

```bash
cd scripts/setup-node-camera-theta
# xác nhận THETA_VIDEO_NR trong theta.conf
sudo ./install.sh
./status.sh
```

`install.sh` sẽ:

1. Cài gói build + GStreamer + `v4l2loopback-dkms`
2. Clone / build 2 repo Ricoh vào `/opt/theta`
3. Patch: PID `0x2717`, `v4l2sink` → `/dev/video${THETA_VIDEO_NR}`, `THETA_DAEMON`
4. Nạp module loopback với `video_nr` cố định
5. Cài udev + enable `theta-loopback.service`

---

## Vận hành

1. Bật **LIVE** trên Theta X.
2. Cắm USB — udev start `theta-loopback`.
3. App đọc **`/dev/video1`** (hoặc số trong `theta.conf`).

```bash
sudo ./start-loopback.sh
# hoặc
sudo systemctl start theta-loopback

./status.sh
lsusb -d 05ca:2717
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video1 --list-formats-ext
gst-launch-1.0 v4l2src device=/dev/video1 ! fakesink -v
# hoặc xem hình:
gst-launch-1.0 v4l2src device=/dev/video1 ! videoconvert ! autovideosink sync=false
```

---

## Node nào là “capture”?

| Device | Vai trò |
|--------|---------|
| `/dev/media*` (RICOH THETA X) | Media controller — **không** dùng với `v4l2src` |
| `/dev/video1` (v4l2loopback / `ThetaX`) | Node capture **đúng** trên livo-monitor khi loopback đã feed |
| Webcam / capture khác | Node khác trong `v4l2-ctl --list-devices` — **không** trỏ `v4l2sink` vào đây |

`gst_loopback` báo *not an output device* → `v4l2sink` đang trỏ nhầm node không phải loopback.

---

## Lỗi thường gặp

| Triệu chứng | Xử lý |
|-------------|--------|
| `THETA not found` | Chưa LIVE (`05ca:0373`) hoặc chưa patch PID `0x2717` |
| `lsusb` = `05ca:0373` | Camera mode — bật LIVE tới khi ra `05ca:2717` |
| Chỉ `/dev/media*` cho Theta | Bình thường — cần loopback |
| Service thoát ngay | Thiếu `THETA_DAEMON`; `journalctl -u theta-loopback -e` |
| Sai số video | `THETA_VIDEO_NR` ≠ node thật → sửa conf, patch lại, `modprobe` lại |
| Không có format trên device | `gst_loopback` chưa chạy / chưa feed |

---

## Liên quan dự án

- [`docs/plan.md`](../../docs/plan.md) — Khâu 0 (bridge) + Khâu 1 (ingestion qua `/dev/video1`).
- [`docs/phase-0/phase-0-nghiem-thu.md`](../../docs/phase-0/phase-0-nghiem-thu.md) — nghiệm thu Phase 0 (đã triển khai gì, pass criteria).
