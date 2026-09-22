# Phase 1 — Kế hoạch triển khai (Bench kỹ thuật)

**Trạng thái:** ⏳ Code/module đã có trong repo; bench trên Ubuntu chưa chạy  
**Phụ thuộc:** Phase 0 ✅ — `/dev/video1` live I420 3840×1920 @ ~30 fps  
**Detector:** [`vendor/apriltag`](../../vendor/apriltag) (AprilRobotics) — không dùng `pupil-apriltags`  
**Deliverable cuối:** [`phase-1-nghiem-thu.md`](./phase-1-nghiem-thu.md) đã điền số liệu + kết luận PASS/FAIL  
**Checklist vận hành:** [`checklist-bench.md`](./checklist-bench.md)

---

## 1. Mục tiêu

Chứng minh trên Ubuntu + Theta X thật:

1. Từ equirect `/dev/video1` có thể **remap** 2 viewport (yaw 90° / 270°) ra ảnh phối cảnh phẳng.
2. Trên viewport đó, **AprilTag `tagStandard41h12` khổ A3** đọc được ở khoảng **~6 m** (điều kiện **tĩnh**).
3. Phần mềm **log thời gian xử lý** từng khâu (đọc frame / remap / detect) và FPS hữu dụng — đủ để đánh giá loopback có chấp nhận được cho Phase 2 hay không.

**Không thuộc Phase 1:** debounce, lookup JSON, pipeline đa luồng production, pan mô phỏng tốc độ xe, tinh chỉnh shutter field (Phase 2 / 3).

---

## 2. Quyết định đã chốt (với chủ dự án)

| # | Câu hỏi | Quyết định |
|---|---------|------------|
| 1 | Địa điểm | Phòng đủ dài (~6 m) |
| 2 | Tag | Đã có `tagStandard41h12` in A3 |
| 3 | “Latency” | **Log thời gian xử lý trong phần mềm** (không bắt buộc đo flash/clap end-to-end phần cứng) |
| 4 | Stack | Python + OpenCV + **`vendor/apriltag`** (build CMake + Python wrap chính thức) |
| 5 | Gắn camera | Đã setup đúng plan (2 lens hướng 2 bên) |
| 6 | Pass detect | **Tĩnh @ ~6 m** là đủ đóng Phase 1 |
| 7 | Tài liệu | Đầy đủ trong `docs/phase-1/` |
| 8 | Module | Package sạch `src/tag_reader/` — Phase 2 dùng lại |
| 9 | Output detect | **ID + debug** (`hamming`, `decision_margin`/`margin`, corners, center) |
| 10 | CPU detector | `nthreads` ≥ 2 (lib tự đa luồng) |
| 11 | Source AprilTag | Giữ trong `vendor/apriltag` (không sửa thuật toán) |

---

## 3. Phạm vi kỹ thuật

### Trong scope

| Hạng mục | Chi tiết |
|----------|----------|
| Input | `/dev/video1` (hoặc `THETA_VIDEO_NR` nếu khác) |
| Remap | Gnomonic; yaw **90°** (right) và **270°** (left); pitch **0°**; FOV ≈ **70°**; output **1280×720**; precompute `map_x/map_y` |
| Detector | Build từ **`vendor/apriltag`**; family **`tagStandard41h12`**; `quad_decimate=1.0`; `refine_edges=1` |
| Logging | ms: grab / remap / detect / total; FPS; ID + debug fields |
| Preview | Cửa sổ OpenCV (equirect thu nhỏ + viewport) |
| Doc | Checklist + nghiệm thu |

### Ngoài scope

- Debounce 6 s, file lookup JSON  
- Pipeline Thread 1–4 production  
- Bỏ loopback / ép VA-API H.264 (chỉ ghi nhận nếu `t_total` cao → đề xuất Phase 2)  
- Field hầm / 20 km/h  

---

## 4. Các bước triển khai (thứ tự)

```text
[A] Chuẩn bị vật lý + Phase 0 live
        ↓
[B] Build vendor/apriltag + chạy scripts/phase-1-bench
        ↓
[C] Căn chỉnh: tag @ ~6 m trong tâm viewport; kiểm hình remap vuông
        ↓
[D] Chạy bài tĩnh: ghi log ms + tỷ lệ frame detect được + ID
        ↓
[E] Điền nghiệm thu + kết luận giữ loopback / rủi ro cho Phase 2
```

| Bước | Việc làm | Kết quả kỳ vọng |
|------|----------|-----------------|
| **A** | LIVE `05ca:2717`, loopback chạy, có hình; tag A3 @ ~6 m | Checklist A pass |
| **B** | `scripts/build-vendor-apriltag.sh` rồi `run_bench.py` | Log ms + detect |
| **C** | Preview: cạnh tag gần thẳng | Tag rõ trong 1280×720 |
| **D** | Stand still 30–60 s | Hit rate ≥ 80% |
| **E** | Điền [`phase-1-nghiem-thu.md`](./phase-1-nghiem-thu.md) | PASS/FAIL có số |

---

## 5. Tiêu chí PASS / FAIL

| ID | Tiêu chí | PASS | FAIL |
|----|----------|------|------|
| P1 | Stream `/dev/video1` ổn trong lúc bench | Có hình, không đứt liên tục | Mất loopback / không mở device |
| P2 | Remap cho ảnh phẳng hữu dụng | Operator xác nhận tag gần vuông trên viewport | Tag vẫn méo nặng / ngoài FOV |
| P3 | Detect tĩnh @ ~6 m | Cùng một ID đúng, hit **≥ 80%** frame trong cửa sổ đo | Không detect / hit thấp sau căn chỉnh |
| P4 | Log thời gian xử lý | Có ms: grab / remap / detect / total | Không có số liệu ms |
| P5 | Tài liệu | Checklist + nghiệm thu điền đủ | Thiếu số / thiếu kết luận |

**Ghi chú “latency”:** đo path phần mềm (grab→remap→detect). Nếu `t_total` thường **> ~80–100 ms** khi nhắm 10–12 FPS xử lý → ghi nợ tối ưu Phase 2; **không tự FAIL** nếu P3 đạt.

---

## 6. Metric cần ghi

- Khoảng cách (m), viewport L/R, FOV, yaw  
- `quad_decimate`, `refine_edges`, `nthreads`  
- `t_grab` / `t_remap` / `t_detect` / `t_total` (avg + max)  
- FPS; frames; hit rate; ID; margin/hamming tiêu biểu  
- Ánh sáng / blur cảm nhận  

---

## 7. Cấu trúc thư mục

```text
vendor/apriltag/              ← upstream AprilRobotics (không sửa detector)
scripts/build-vendor-apriltag.sh
scripts/phase-1-bench/
├── run_bench.py
└── requirements.txt
src/tag_reader/
├── __init__.py
├── rectify.py                ← dual-viewport Gnomonic
├── detector.py               ← wrapper vendor Python API
└── timing.py
docs/phase-1/
├── README.md                 ← file này
├── checklist-bench.md
└── phase-1-nghiem-thu.md
```

---

## 8. Rủi ro

| Rủi ro | Xử lý bench |
|--------|-------------|
| Tag lệch bên viewport | Đổi `--side left|right` / yaw |
| Ánh sáng / blur | Tăng sáng; chỉnh shutter Theta thủ công |
| Build Python wrap fail | Cài `python3-dev` `python3-numpy`; xem script build |
| OpenCV `t_grab` cao | Ghi nhận; thử buffer nhỏ / GStreamer sau |
| Sai family | Đúng `tagStandard41h12` |

---

## 9. Việc tiếp theo

1. Trên Ubuntu: chạy build vendor + checklist.  
2. Điền nghiệm thu.  
3. PASS → Phase 2 (debounce + JSON + module hoá pipeline).

---

## 10. Tham chiếu

- [`../plan.md`](../plan.md)  
- [`../phase-0/phase-0-nghiem-thu.md`](../phase-0/phase-0-nghiem-thu.md)  
- [`../../scripts/setup-node-camera-theta/README.md`](../../scripts/setup-node-camera-theta/README.md)  
- [`../../vendor/apriltag/README.md`](../../vendor/apriltag/README.md)  
