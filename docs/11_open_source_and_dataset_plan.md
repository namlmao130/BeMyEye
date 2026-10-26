# KẾ HOẠCH MỞ MÃ NGUỒN VÀ BỘ DỮ LIỆU ĐƯỜNG PHỐ VIỆT NAM
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Mục tiêu:** Đóng góp phi lợi nhuận cho cộng đồng khiếm thị và các nhà nghiên cứu AI tại Việt Nam  

---

## 1. GIẤY PHÉP MÃ NGUỒN MỞ (OPEN SOURCE LICENSE)
- **Giấy phép đề xuất:** **MIT License** hoặc **Apache License 2.0**.
- **Điều khoản đặc biệt (Safety & Ethical Clause):**
  - Bắt buộc giữ nguyên tuyên bố miễn trừ trách nhiệm an toàn (Safety Disclaimer) trong mọi bản phân phối phái sinh.
  - Tuyệt đối nghiêm cấm việc quảng cáo phần mềm có khả năng "thay thế gậy trắng" hoặc "đảm bảo an toàn tuyệt đối".

---

## 2. QUY TRÌNH ẨN DANH HÓA BỘ DỮ LIỆU (DATASET ANONYMIZATION PIPELINE)
Để bảo vệ quyền riêng tư cá nhân theo quy định pháp luật Việt Nam (Nghị định 13/2023/NĐ-CP về bảo vệ dữ liệu cá nhân), 100% video thực tế trước khi tải lên kho mở (Hugging Face / Zenodo / GitHub) bắt buộc phải trải qua đường ống tự động 3 bước:

```
[Video gốc quay trên phố]
           |
           v
+-----------------------------------------------------------+
| Bước 1: Phát hiện và Làm mờ Khuôn mặt (Face Blurring)     |
| - Sử dụng mô hình RetinaFace / MediaPipe Face Detection   |
| - Áp dụng Gaussian Blur (bán kính kernel = 35) lên khuôn  |
|   mặt của toàn bộ người đi đường, chủ quán cóc.           |
+-----------------------------------------------------------+
           |
           v
+-----------------------------------------------------------+
| Bước 2: Phát hiện và Che mờ Biển số xe (Plate Blurring)   |
| - Sử dụng mô hình phát hiện biển số YOLO-License-Plate    |
|   kết hợp OCR (PaddleOCR).                                |
| - Áp dụng Mosaic / Blackout lên biển số xe máy và ô tô.   |
+-----------------------------------------------------------+
           |
           v
+-----------------------------------------------------------+
| Bước 3: Hậu kiểm thủ công (Human-in-the-Loop Audit)       |
| - Người phụ trách xem tua lại 100% thời lượng video để    |
|   đảm bảo không còn bất kỳ thông tin định danh cá nhân    |
|   hoặc số nhà nhạy cảm nào bị bỏ sót.                     |
+-----------------------------------------------------------+
           |
           v
[Bộ dữ liệu an toàn công bố công khai]
```

---

## 3. CẤU TRÚC BỘ DỮ LIỆU CÔNG BỐ (VIETNAMESE SIDEWALK HAZARDS DATASET)
- **Quy mô mục tiêu:** 50 clips ngắn (tổng ~60 phút), độ phân giải 1080p @ 30 FPS.
- **Phân loại nhãn sự kiện:**
  - `motorcycle_on_sidewalk`: Xe máy lưu thông hoặc lấn chiếm vỉa hè.
  - `low_hanging_awning`: Bạt che, dù quán cóc hạ thấp ngang tầm đầu.
  - `ground_curb_step`: Bậc tam cấp, lề đường cao, gờ đá mấp mô.
  - `pothole_drain`: Miệng cống thoát nước, hố công trình tạm bợ.
- **Định dạng file:** Video MP4 (H.264) kèm tệp chú thích JSON / COCO Format.
