# Nghiệm thu Phase 1 — Bench remap + AprilTag tĩnh

**Trạng thái:** ⏳ Chưa bench (mẫu trống — điền khi chạy)  
**Kế hoạch:** [`README.md`](./README.md)  
**Checklist:** [`checklist-bench.md`](./checklist-bench.md)  
**Phụ thuộc:** [`../phase-0/phase-0-nghiem-thu.md`](../phase-0/phase-0-nghiem-thu.md) ✅

---

## 1. Phạm vi đã nghiệm thu (khi PASS)

Phase 1 xác nhận:

- Đọc live từ `/dev/video*` (loopback Phase 0).
- Remap dual-viewport (hoặc viewport bên có tag) cho ảnh phẳng dùng được.
- Detect **tĩnh** tag A3 `tagStandard41h12` @ ~6 m.
- Phần mềm **log ms** các khâu xử lý (grab / remap / detect / total) và **debug detect** (hamming, margin, corners).

**Không** nghiệm thu trong phase này: debounce, lookup JSON, đa luồng production, chạy xe / pan tốc độ cao, shutter tối ưu hầm.

---

## 2. Quyết định chốt trước bench

| Hạng mục | Giá trị |
|----------|---------|
| Địa điểm | Phòng đủ dài |
| Tag | `tagStandard41h12` in A3 (đã có) |
| Latency | Log thời gian xử lý phần mềm |
| Stack | Python + OpenCV + `vendor/apriltag` (AprilRobotics) |
| Camera mount | Đã setup 2 lens ra 2 bên |
| Pass detect | Tĩnh @ ~6 m |
| Doc | Đầy đủ trong `docs/phase-1/` |
| Detector source | `vendor/apriltag` — không `pupil-apriltags` |
| Output detect | ID + hamming + margin + corners + center |
| Module | `src/tag_reader/` tái dùng Phase 2 |

---

## 3. Môi trường bench (điền)

| Trường | Giá trị |
|--------|---------|
| Ngày | |
| Người chạy | |
| Hostname Ubuntu | |
| Device V4L2 | `/dev/video` |
| USB LIVE | `05ca:2717` □ có □ không |
| Khoảng cách đo (m) | |
| Viewport / yaw dùng | |
| FOV (°) | |
| Output remap | `____ × ____` |
| Family / params | `vendor/apriltag` · `tagStandard41h12` · `quad_decimate=` · `refine_edges=` · `nthreads=` |
| Lệnh chạy script | |

---

## 4. Kết quả tiêu chí

| ID | Tiêu chí | Kết quả | Ghi chú |
|----|----------|---------|---------|
| P1 | Stream ổn | □ PASS □ FAIL | |
| P2 | Remap hữu dụng (tag gần vuông) | □ PASS □ FAIL | |
| P3 | Detect tĩnh hit ≥ 80% | □ PASS □ FAIL | hit = ____ % |
| P4 | Có log ms xử lý | □ PASS □ FAIL | |
| P5 | Doc + checklist hoàn tất | □ PASS □ FAIL | |

**Kết luận Phase 1:** □ **PASS** □ **FAIL**

---

## 5. Số liệu đo (điền từ log)

### 5.1 Detect

| Metric | Giá trị |
|--------|---------|
| Thời lượng đo (s) | |
| Frames xử lý | |
| Frames có tag đúng ID | |
| Hit rate (%) | |
| ID(s) quan sát | |
| False ID (nếu có) | |

### 5.2 Thời gian xử lý phần mềm (ms)

| Khâu | avg | max |
|------|-----|-----|
| grab | | |
| remap | | |
| detect | | |
| total / frame | | |
| FPS vòng lặp | | |

### 5.3 Quan sát hình ảnh

- Độ nét / blur:
- Ánh sáng / nhiễu:
- Ghi chú khác:

---

## 6. Đánh giá loopback cho Phase 2

Dựa trên `t_total` và FPS thực tế (không phải đo flash quang học):

| Đánh giá | Chọn |
|----------|------|
| Loopback + decode hiện tại **đủ** để vào Phase 2 module hoá | □ |
| Cần ưu tiên tối ưu sớm (queue leaky / VA-API / bỏ loopback) nhưng Phase 1 vẫn PASS detect | □ |
| Không đủ — phải xử lý trước khi Phase 2 | □ |

Lý do ngắn:

---

## 7. Việc làm sau Phase 1

Nếu **PASS**:

- [ ] Mở Phase 2: ingestion + remap + detect + debounce + JSON → console  
- [ ] Mang theo tham số yaw/FOV/viewport đã chốt ở trên  

Nếu **FAIL**:

- [ ] Nguyên nhân gốc:
- [ ] Hành động sửa (vật lý / tham số / phần mềm):
- [ ] Ngày re-test dự kiến:

---

## 8. Artifact đính kèm (tuỳ chọn)

Liệt kê path log / ảnh chụp viewport nếu lưu trong repo hoặc ngoài máy:

```text
# ví dụ:
# logs/phase-1-bench-YYYYMMDD.txt
# docs/phase-1/assets/viewport-r.png
```

---

## 9. Tham chiếu

- [`README.md`](./README.md) — kế hoạch & tiêu chí  
- [`checklist-bench.md`](./checklist-bench.md) — quy trình chạy  
- [`../plan.md`](../plan.md) — Khâu 2–3  
