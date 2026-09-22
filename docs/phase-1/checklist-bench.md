# Phase 1 — Checklist bench (Ubuntu)

Dùng trên máy có Theta X + Phase 0 đã cài. Đánh dấu `[x]` khi xong.  
Kế hoạch: [`README.md`](./README.md) · Nghiệm thu: [`phase-1-nghiem-thu.md`](./phase-1-nghiem-thu.md)

---

## A. Điều kiện tiên quyết (Phase 0)

- [ ] Theta X bật **LIVE** — `lsusb -d 05ca:2717` OK (không phải `0373`)
- [ ] Service / loopback chạy — `systemctl status theta-loopback` hoặc `scripts/setup-node-camera-theta/status.sh`
- [ ] Node đúng — `v4l2-ctl --list-devices` → `ThetaX` → `/dev/video1` (hoặc số đã conf)
- [ ] Có hình — `gst-launch-1.0 v4l2src device=/dev/video1 ! videoconvert ! autovideosink sync=false`
- [ ] Format — `v4l2-ctl -d /dev/video1 --list-formats-ext` → YU12/I420 `3840x1920` @ ~30

**Nếu fail A:** dừng Phase 1, sửa theo `scripts/setup-node-camera-theta/README.md`.

---

## B. Setup vật lý

- [ ] Camera gắn đúng hướng: 2 lens hướng 2 bên (đã chốt: đã setup)
- [ ] Tag `tagStandard41h12` in A3, phẳng, không bóng mạnh / không nhăn
- [ ] Khoảng cách camera → tag đo được ≈ **6.0–6.5 m** (ghi số thực vào nghiệm thu)
- [ ] Tag ngang tầm mắt / tâm thấu kính phía tường đang test
- [ ] Ánh sáng phòng đủ nhìn rõ tag bằng mắt (ghi chú nếu tối)

Khoảng cách đo thực tế: `________ m`  
Bên tường / viewport dự kiến (`left`=yaw 270° / `right`=yaw 90°): `________`

---

## C. Phần mềm bench

### C1. Deps hệ thống + build `vendor/apriltag`

```bash
sudo apt-get install -y build-essential cmake ninja-build \
  python3-dev python3-numpy python3-opencv python3-pip \
  libopencv-dev

cd /path/to/test-tag-reader
chmod +x scripts/build-vendor-apriltag.sh
./scripts/build-vendor-apriltag.sh

source .local/apriltag-env.sh
python3 -c "from apriltag import apriltag; print('apriltag OK')"
```

- [ ] `build-vendor-apriltag.sh` thành công
- [ ] `from apriltag import apriltag` OK sau `source .local/apriltag-env.sh`

### C2. Runtime Python (OpenCV)

```bash
# hệ thống python3-opencv thường đủ; nếu thiếu:
pip3 install --user -r scripts/phase-1-bench/requirements.txt
```

- [ ] OpenCV import được: `python3 -c "import cv2; print(cv2.__version__)"`

### C3. Chạy bench

```bash
cd /path/to/test-tag-reader
source .local/apriltag-env.sh
export PYTHONPATH="$(pwd)/src:${PYTHONPATH}"

# Preview + log (cả hai viewport):
python3 scripts/phase-1-bench/run_bench.py --device /dev/video1 --side both

# Chỉ một bên đang có tag:
python3 scripts/phase-1-bench/run_bench.py --device /dev/video1 --side right
# hoặc --side left

# Headless / SSH (không cửa sổ):
python3 scripts/phase-1-bench/run_bench.py --no-preview --json-log | tee /tmp/phase1-bench.jsonl

# Thoát preview: phím q hoặc Esc
```

- [ ] Script mở đúng `/dev/videoN`
- [ ] Remap 1280×720, yaw 90° / 270°, FOV ≈ 70°
- [ ] Detector: `tagStandard41h12`, `decimate=1.0`, `refine_edges`, `nthreads` ≥ 2
- [ ] Log có: `t_grab_ms`, `t_remap_ms`, `t_detect_ms`, `t_total_ms`, fps, ids (+ margin trong JSON/debug overlay)
- [ ] Preview thấy equirect + viewport (trừ khi `--no-preview`)

Lệnh chạy đã dùng:

```text
# dán lệnh thật sau khi bench
```

---

## D. Căn chỉnh hình học

- [ ] Mở preview viewport ứng với bên có tag (`--side left|right`)
- [ ] Tag nằm trong khung, gần giữa theo phương ngang
- [ ] Cạnh tag nhìn **gần thẳng / gần vuông**
- [ ] Nếu lệch: đổi side; chỉnh `--fov` / `--yaw-left` / `--yaw-right`; ghi giá trị cuối

Tham số cuối cùng:

| Tham số | Giá trị |
|---------|---------|
| Device | `/dev/video____` |
| `--side` | |
| Yaw L / R | |
| Pitch | `0` |
| FOV (°) | |
| Viewport size | `1280 x 720` (hoặc khác: ____) |

---

## E. Bài đo tĩnh (pass chính)

Thời lượng đề xuất: **30–60 giây**, camera + tag **đứng yên**.

- [ ] Chạy bench, ghi log (`tee` hoặc copy console)
- [ ] Không che tag, không đi qua trước camera
- [ ] Copy đoạn log tiêu biểu vào nghiệm thu
- [ ] Đếm:
  - Frames xử lý: `________`
  - Frames có detect đúng ID: `________`
  - Hit rate %: `________`
  - ID quan sát: `________`
- [ ] Thống kê thời gian (ms):

| Metric | avg | max | ghi chú |
|--------|-----|-----|---------|
| t_grab | | | |
| t_remap | | | |
| t_detect | | | |
| t_total | | | |
| FPS vòng lặp | | | |

- [ ] Quan sát chủ quan: nét / blur / nhiễu ISO (1–2 câu)

---

## F. Đóng phase

- [ ] Điền đủ [`phase-1-nghiem-thu.md`](./phase-1-nghiem-thu.md)
- [ ] Kết luận PASS / FAIL theo tiêu chí P1–P5 trong [`README.md`](./README.md)
- [ ] Nếu PASS: ghi đề xuất Phase 2 (giữ loopback hay ưu tiên tối ưu decode)
- [ ] Nếu FAIL: ghi nguyên nhân chính + bước xử lý tiếp

Người chạy bench: `________`  
Ngày: `________`  
Máy (hostname): `________`
