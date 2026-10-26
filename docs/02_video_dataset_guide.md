# HƯỚNG DẪN QUAY VIDEO THỰC TẾ & CHUẨN BỊ DATASET KIỂM THỬ
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị tại Việt Nam  
**Giai đoạn:** Giai đoạn 0 - Chuẩn bị dữ liệu kiểm thử thực tế

---

## 1. MỤC TIÊU CỦA TẬP DỮ LIỆU
Mô hình AI thị giác máy tính huấn luyện trên bộ dữ liệu COCO hay dữ liệu nước ngoài thường thất bại nghiêm trọng trên đường phố Việt Nam vì:
- Xe máy lưu thông dày đặc, đa dạng chủng loại (xe số, xe ga, xe chở hàng cồng kềnh, xe kéo).
- Vỉa hè bị chiếm dụng làm bãi đỗ xe máy, quán cóc, chậu cây, biển hiệu đứng.
- Mặt đường gồ ghề, nắp cống mấp mô, bậc tam cấp nhà dân lấn chiếm vỉa hè.
- Điều kiện ánh sáng phức tạp: chênh sáng mạnh giữa bóng râm của bạt che và nắng gắt ban trưa.

Tập video này dùng để:
1. Đánh giá độ trễ và FPS thực tế của web app.
2. Đo tỷ lệ phát hiện (Recall / Miss rate) trên các vật cản nguy hiểm.
3. Đo tỷ lệ báo nhầm (False Positives) gây quấy rầy người dùng.

---

## 2. THIẾT BỊ VÀ THIẾT LẬP KỸ THUẬT KHI QUAY

### A. Thiết bị quay
- Dùng chính điện thoại mục tiêu (hoặc điện thoại có camera tương đương với nhóm người dùng dự kiến).
- Thông số quay đề xuất:
  - **Độ phân giải:** Full HD (1080p) hoặc HD (720p). *Lưu ý: Web app thường chỉ resize ảnh vào 320x320 hoặc 640x640.*
  - **Tốc độ khung hình (FPS):** 30 FPS chuẩn.
  - **Khóa lấy nét (AF Lock) & Khóa phơi sáng (AE Lock):** Nên để phơi sáng tự động giống thực tế người dùng khi cầm máy.

### B. Vị trí và góc máy (Ergonomics)
- **Vị trí:** Gắn trước ngực (bằng dây đeo ngực chest-strap điện thoại) hoặc cầm tay ngang tầm ức người đi bộ.
- **Góc nghiêng:** Chúc xuống đất một góc khoảng **15° - 20°**.
  - *Lý do:* Góc này đảm bảo nhìn thấy mặt đất cách chân 2m - 5m (để phát hiện bậc thềm, rãnh hố) đồng thời vẫn thấy vật cản tầm ngực/đầu (biển báo, bạt che, người đi ngược chiều).
- **Cách di chuyển:** Bước đi với tốc độ tự nhiên của người khiếm thị (~0.8 - 1.0 m/s). **KHÔNG** dùng gimbal chống rung; phải giữ nguyên độ rung lắc tự nhiên của bước chân để kiểm tra độ ổn định của bounding box.

---

## 3. DANH SÁCH 5 BỐI CẢNH BẮT BUỘC CẦN QUAY (Mỗi clip 60-90 giây)

| Mã Clip | Bối cảnh | Mục tiêu kiểm thử | Điều kiện ánh sáng |
|---|---|---|---|
| **VID_01** | Vỉa hè bị chiếm dụng bàn ghế, xe máy đỗ | Khả năng tách biệt nhiều vật thể đan xen; phát hiện lối đi hẹp còn lại | Ánh sáng ban ngày, bóng râm |
| **VID_02** | Xe máy chạy ngược chiều hoặc lao lên vỉa hè | Khả năng phát hiện vật cản tiến nhanh (Bounding box phóng to đột ngột) | Ban ngày ngoài trời |
| **VID_03** | Hẻm nhỏ có cành cây, bạt che tầm ngực/đầu | Kiểm tra vật cản tầm cao (gậy trắng không tới được) | Chênh sáng nắng - bóng râm |
| **VID_04** | Đoạn đường có bậc tam cấp lồi lõm, lề đường cao | Kiểm tra độ sâu và phân đoạn mặt đất (dùng cho Giai đoạn 2) | Ban ngày, bề mặt gạch hoa văn |
| **VID_05** | Ngã tư đông đúc, chuẩn bị qua đường | Khả năng lọc nhiễu khi xung quanh có quá nhiều xe cộ ở xa | Chiều tà / ánh sáng chói |

---

## 4. QUY TRÌNH GÁN NHÃN SƠ BỘ (GROUND TRUTH)
Không cần gán nhãn từng frame cho toàn bộ video (tốn hàng ngàn giờ). Hãy gán nhãn sự kiện then chốt (Event-level Ground Truth):
1. **Timestamp bắt đầu và kết thúc sự kiện:** Ví dụ: `00:14 - 00:18: Xe máy chạy tới phía trước cách 3m`.
2. **Loại vật cản:** Xe máy, người đi bộ, bàn ghế, bậc thềm, cành cây chìa ra.
3. **Vị trí tương đối:** Trái (Left) / Giữa (Center) / Phải (Right).
4. **Khoảng cách ước lượng:** Xa (> 3m), Gần (1.5 - 3m), Nguy cấp (< 1.5m).

File nhãn lưu dưới định dạng bảng đơn giản (CSV hoặc JSON) trong thư mục `dataset/labels.json`.
