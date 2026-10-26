# BẢN ĐẶC TẢ DỰ ÁN VÀ NGUYÊN TẮC KỸ THUẬT (PROJECT BLUEPRINT)
**Tên dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Vai trò:** Kỹ sư trưởng & Cố vấn sản phẩm  

---

## 1. NGUYÊN TẮC BẮT BUỘC (CARDINAL RULES)
1. **An toàn trên hết:** App là công cụ bổ trợ, KHÔNG BAO GIỜ thay thế gậy trắng hay người dẫn. Tuyệt đối không bao giờ phát câu "Đường an toàn" hay "Phía trước thông thoáng". Hệ thống chỉ thông báo những vật thể mà cảm biến chắc chắn phát hiện được.
2. **Xử lý on-device 100%:** Toàn bộ quá trình suy luận mô hình thị giác và tính toán âm thanh chạy trực tiếp trên thiết bị (không truyền video/ảnh lên đám mây nhằm bảo vệ quyền riêng tư và triệt tiêu độ trễ mạng).
3. **Ưu tiên âm thanh không xâm lấn:** Sử dụng tiếng bíp Stereo Pan (Trái - Giữa - Phải), tần số & cao độ tỷ lệ với độ gần. Giọng nói tiếng Việt ngắn gọn chỉ phát khi có nguy cơ va chạm khẩn cấp. Khuyến cáo người dùng dùng tai nghe truyền xương (Bone-conduction) hoặc loa ngoài, không bịt kín tai.
4. **Phân cấp cảnh báo & Kiểm soát tần suất (Cooldown):** Cảnh báo an toàn ngắt lời chỉ dẫn đường. Có cơ chế cooldown chống "spam" âm thanh gây hoảng loạn.
5. **Đo đạc định lượng rõ ràng:** Mọi giai đoạn phải ghi nhận FPS, Độ trễ (ms), Tỷ lệ bỏ sót (Miss Rate / False Negative), Tỷ lệ báo nhầm (False Positive).

---

## 2. KIẾN TRÚC KỸ THUẬT TỔNG THỂ

```
+-------------------------------------------------------------+
|                      CAMERA STREAM                          |
|             (WebRTC / getUserMedia, 30 FPS)                 |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|               MODULE THỊ GIÁC (ON-DEVICE)                  |
| - Giai đoạn 1: Object Detection (COCO-SSD / YOLO-Nano)      |
| - Giai đoạn 2: Depth Estimation & Monocular Ground Plane    |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|                 BỘ QUYẾT ĐỊNH CẢNH BÁO                      |
| - Phân vùng: Trái (0-35%), Giữa (35-65%), Phải (65-100%)    |
| - Ước lượng khoảng cách: Dựa vào bottom-y & kích thước bbox|
| - Phát hiện vật tiến tới: d(Area)/dt > Ngưỡng dãn nở        |
| - Bộ lọc chống spam (Cooldown & Hysteresis filter)          |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|            BỘ PHÁT TÍN HIỆU ÂM THANH & RUNG                 |
| - Web Audio API (StereoPannerNode + OscillatorNode)         |
| - Text-to-Speech (Web Speech API tiếng Việt ngắn gọn)       |
| - Navigator.vibrate (Haptic feedback)                       |
+-------------------------------------------------------------+
```

---

## 3. LỘ TRÌNH 5 GIAI ĐOẠN

- **Giai đoạn 0:** Khảo sát người dùng khiếm thị, hướng dẫn thu thập video đường phố VN, lập danh mục mối nguy hiểm. *(Đang thực hiện)*
- **Giai đoạn 1:** Web App phát hiện vật cản thời gian thực & cảnh báo âm thanh 3 hướng (Trái/Giữa/Phải). Đạt >= 15 FPS, trễ < 300ms.
- **Giai đoạn 2:** Ước lượng độ sâu cho vật cản bất định, phát hiện bậc thềm, lề đường, phân đoạn mặt đất.
- **Giai đoạn 3:** Thử nghiệm hiện trường cùng người khiếm thị có bảo hộ.
- **Giai đoạn 4:** Dẫn đường GPS từng bước kết hợp cơ chế ngắt an toàn.
- **Giai đoạn 5:** Tối ưu hóa, chuyển sang native app (nếu cần), công bố dữ liệu và sản phẩm.
