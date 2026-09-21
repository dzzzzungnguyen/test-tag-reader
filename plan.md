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
| **Camera**          | **Ricoh Theta X** (bắt buộc)                                  | Live stream qua UVC 4K ($3840 \times 1920$) @ 30fps. Cảm biến Rolling Shutter.          |
| **Phần cứng xử lý** | Laptop Intel Core Ultra 7 165U, 16GB RAM                      | Không GPU rời. Khai thác iGPU qua Intel VA-API / QSV và CPU đa nhân.                    |
| **Hệ điều hành**    | Ubuntu Linux                                                  | GStreamer + V4L2 backend + Python/C++ (`pupil-apriltags`).                              |


---



### 2. Thiết lập Vật lý & Thiết bị (Physical Setup)

- **Hướng đặt Camera:**
- Xoay thân Ricoh Theta X sao cho **2 thấu kính chĩa trực diện sang 2 bên vách hầm** (thấu kính trước nhìn vách phải, thấu kính sau nhìn vách trái).
- *Mục đích:* Tránh hoàn toàn việc mép nối ghép ảnh (*stitching seam*) rơi vào bức tường có tag. Đưa mục tiêu vào vùng quang học nét nhất ở tâm thấu kính.
- **Gá đặt:** Giá hít capo 3 điểm, tích hợp ngàm chống rung vi mô.
- **Cấu hình thông số ghi hình (Camera Shutter Priority):**
- Thiết lập tốc độ màn trập tối thiểu **$1/250\text{s}$** (khuyến nghị $1/500\text{s}$) để triệt tiêu vệt nhòe chuyển động (*motion blur*) khi xe chạy $5.55\text{ m/s}$.
- Chấp nhận nâng ISO tự động để bù sáng.

---



### 3. Kiến trúc Pipeline Xử lý (Data Processing Pipeline)

Hệ thống được thiết kế dạng đa luồng phi đồng bộ để đảm bảo không trễ khung hình và tối ưu hóa điện năng tiêu thụ trên CPU Ultra 7.

```
       [Ricoh Theta X] (4K UVC Stream @ 30 FPS)
              │ (USB-C 3.1)
              ▼
    [Thread 1: Ingestion & HW Decode]
       • GStreamer + V4L2 + VA-API (vaapijpegdec)
       • Buffer: queue max-size=1 drop=true (Zero Latency)
              │
              ▼ (Frame Throttling: Lấy 10–12 FPS)
    [Thread 2: Dual-Viewport Rectification]
       • Cắt & nắn phẳng 2 vùng nhìn: Trái (90°) và Phải (270°)
       • Triển khai qua cv::remap (Ma trận tính sẵn một lần)
       • Output: 2 ảnh phối cảnh phẳng (Rectilinear) 1280x720
              │
              ▼
    [Thread 3: AprilTag Core Detection]
       • pupil-apriltags (tagStandard41h12)
       • Quét xen kẽ: Frame chẵn (vách trái) / Frame lẻ (vách phải)
       • Tham số: quad_decimate=1.0, refine_edges=1
              │
              ▼ (Tag Detected)
    [Thread 4: Filtering & Event Dispatcher]
       • Time-based Debounce Filter (khóa 6 giây chống spam)
       • Lookup Hash Map: ID -> Text String
       • Output: In text ra màn hình / ghi log hành trình

```

---



### 4. Chi tiết các Khâu Kỹ thuật Cốt lõi



#### Khâu 1: Lấy luồng & Giải mã phần cứng (Ingestion)

- Sử dụng pipeline GStreamer gọi trực tiếp backend `v4l2src` kết hợp plugin phần cứng `vaapijpegdec` của Intel iGPU.
- Ép kích thước hàng đợi `queue max-size-buffers=1 drop=true` để loại bỏ độ trễ tích lũy; thuật toán sẽ luôn xử lý khung hình mới nhất tại thời điểm thực tế.



#### Khâu 2: Nắn phối cảnh 2 mạn sườn (Dual-Viewport Rectification)

- Tag bị cong dạng hình học trên ảnh $360^\circ$ sẽ khiến thuật toán nhận diện biên vuông (*quad detection*) thất bại.
- Thay vì nắn toàn bộ ảnh $360^\circ$, hệ thống chỉ tính toán phép chiếu phối cảnh (Gnomonic/Pinhole Projection) cho hai góc nhìn:
- Khung nhìn 1: Trục ngang yaw $= 90^\circ$, pitch $= 0^\circ$, FOV $\approx 70^\circ$.
- Khung nhìn 2: Trục ngang yaw $= 270^\circ$, pitch $= 0^\circ$, FOV $\approx 70^\circ$.
- Tạo sẵn 2 cặp ma trận tọa độ `(map_x, map_y)` kích thước $1280 \times 720$ ngay khi khởi tạo chương trình. Quá trình runtime chỉ gọi `cv::remap`, thời gian xử lý $< 3\text{ms}$/frame.



#### Khâu 3: Nhận diện tối ưu (`pupil-apriltags`)

- Chạy luồng quét ở tần suất $10 - 12\text{ FPS}$ (tương đương mỗi bên vách được quét $5 - 6\text{ FPS}$). Với thời gian lướt qua một tag từ $1.5 - 2.0\text{ giây}$, hệ thống có từ $8 - 12$ cơ hội đọc thành công trên mỗi tag.
- Thiết lập `quad_decimate = 1.0` để giữ trọn vẹn mật độ điểm ảnh của từng bit dữ liệu (khoảng $\approx 3.2\text{ pixels/bit}$).



#### Khâu 4: Hậu xử lý và Logic xuất dữ liệu

- **Bảng tra cứu (Lookup Dictionary):** Nạp sẵn file JSON/YAML chứa 100 cặp key-value dạng `{ID_int: "Text_str"}`.
- **Bộ lọc chống trùng (Debounce):** Khi một tag được giải mã, hệ thống in text ra console/log, sau đó tạm thời bỏ qua ID này trong cửa sổ thời gian 6 giây tiếp theo, tránh ghi nhận lặp lại hàng chục lần khi xe đi ngang qua vị trí dán.

---



### 5. Kế hoạch Triển khai (Next Steps)

1. **Giai đoạn 1 (Bench Test - 1 ngày):**

- Kết nối Theta X với Ubuntu, chạy thử lệnh GStreamer kiểm tra tính tương thích của pipeline giải mã cứng qua `vaapijpegdec`.
- Tạo 1 tag in mẫu khổ A3 (`tagStandard41h12`), đặt cách 6m trong phòng để đo kiểm thời gian giải mã và độ nhạy của hàm `remap`.

1. **Giai đoạn 2 (Module Coding - 2 ngày):**

- Hiện thực hóa mã nguồn đa luồng: Ingestion, Rectification, Detection, Debounce/Lookup.

1. **Giai đoạn 3 (Field Test trong hầm - 1 ngày):**

- Gắn camera lên capo xe, test thực tế ở dải tốc độ $15 - 25\text{ km/h}$ với thông số phơi sáng cố định để tinh chỉnh Shutter Speed tối ưu.

