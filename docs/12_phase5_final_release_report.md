# BÁO CÁO HOÀN THIỆN TOÀN DIỆN VÀ PHÁT HÀNH THỬ NGHIỆM (GIAI ĐOẠN 5)
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Tình trạng:** Hoàn thiện toàn bộ lộ trình 5 giai đoạn & Sẵn sàng cho nhóm Beta Test  

---

## 1. TỔNG KẾT HÀNH TRÌNH PHÁT TRIỂN 5 GIAI ĐOẠN

```
+-------------------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 0: KHẢO SÁT & CHUẨN BỊ                                                                      |
| - Hoàn thành bộ câu hỏi phỏng vấn người khiếm thị; quy chuẩn quay video góc chúc 15-20°.              |
| - Lập danh mục 7 tình huống nguy hiểm và xác định ranh giới kỹ thuật trung thực của AI 2D.           |
+-------------------------------------------------------------------------------------------------------+
                                                   |
                                                   v
+-------------------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 1: PHÁT HIỆN VẬT CẢN & CẢNH BÁO ÂM THANH 3 HƯỚNG                                            |
| - On-device 100% qua TensorFlow.js WebGL (18-26 FPS, trễ 38-65ms).                                     |
| - Ước lượng cự ly phối cảnh (Xa / Gần / Nguy cấp) và bắt xe máy lao tới qua d(Area)/dt.              |
| - Âm thanh Stereo Pan Web Audio API + Pitch Scaling + Cooldown chống spam.                            |
+-------------------------------------------------------------------------------------------------------+
                                                   |
                                                   v
+-------------------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 2: CHƯỚNG NGẠI BẤT ĐỊNH (TẦM ĐẦU) & BẬC THỀM / LỀ ĐƯỜNG                                     |
| - Generic Depth Analyzer: Bảo vệ hành lang tầm đầu/ngực (bạt che, cành cây, giàn giáo).               |
| - Ground Plane Analyzer: Nhận diện bậc bước lên & bậc bước xuống (vật cản âm nguy hiểm).              |
| - Đánh giá giới hạn: Thừa nhận camera 2D dễ nhầm bóng râm và khẳng định gậy trắng là chốt chặn chính.|
+-------------------------------------------------------------------------------------------------------+
                                                   |
                                                   v
+-------------------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 3: THỬ NGHIỆM THỰC ĐỊA CÓ NGƯỜI DÙNG & TINH CHỈNH PHẢN HỒI                                  |
| - Thử nghiệm an toàn 3 cấp độ cùng "Bóng bảo hộ sáng mắt" đi kèm; khảo sát Likert đạt 4.6 - 4.8/5.0. |
| - Tinh chỉnh: Tăng cooldown xa lên 2.2s; bổ sung Heartbeat Haptic 12s; lọc 8 frames chống rung ngực. |
+-------------------------------------------------------------------------------------------------------+
                                                   |
                                                   v
+-------------------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 4: DẪN ĐƯỜNG GPS TỪNG BƯỚC & NGẮT AN TOÀN TUYỆT ĐỐI                                         |
| - Định vị GPS độ chính xác cao + Bộ lọc làm mượt chống trôi (EMA) giảm sai số xuống ±3.5m.           |
| - La bàn số (Compass) hỗ trợ chỉnh góc lệch; câu chỉ dẫn tiếng Việt cực ngắn.                         |
| - NGUYÊN TẮC SỐ 1: Cảnh báo an toàn lập tức ngắt lời dẫn đường GPS trong < 60ms.                      |
+-------------------------------------------------------------------------------------------------------+
                                                   |
                                                   v
+-------------------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 5: HOÀN THIỆN, TỐI ƯU PIN/NHIỆT & KẾ HOẠCH CÔNG BỐ                                          |
| - Dynamic Battery & Thermal Optimizer: Giảm FPS xuống 10 khi đứng yên, tăng 22 khi bước đi.          |
| - Modal Điều khoản An toàn bắt buộc đọc bằng giọng nói khi khởi chạy lần đầu.                         |
| - Bản thiết kế Native Migration (Flutter / iOS LiDAR ARKit) & Kế hoạch mở mã nguồn / dữ liệu.          |
+-------------------------------------------------------------------------------------------------------+
```

---

## 2. KẾ HOẠCH PHÁT HÀNH THỬ NGHIỆM CHO NHÓM NHỎ (BETA TESTING COHORT)

### A. Đối tượng và quy mô
- **Quy mô:** 5 – 10 người khiếm thị (phối hợp cùng Chi hội Người mù quận/huyện).
- **Yêu cầu thiết bị:** Điện thoại thông minh có kết nối Wi-Fi hoặc 4G, pin $\ge 70\%$.
- **Phụ kiện bắt buộc:** Tai nghe dẫn truyền xương (Bone-conduction) hoặc tai nghe hở (Open-ear) + Dây đeo điện thoại trước ngực.

### B. Quy trình phân phối bản thử nghiệm
1. Khởi chạy máy chủ HTTPS trên hạ tầng máy chủ cục bộ hoặc qua dịch vụ tên miền HTTPS an toàn (Cloudflare Tunnel / ngrok).
2. Cung cấp đường link HTTPS duy nhất và mã QR cho người bảo hộ quét trực tiếp.
3. Người dùng khiếm thị mở ứng dụng: Hệ thống tự động đọc to bản **Điều khoản An toàn Bắt buộc**; sau khi người dùng bấm đồng ý, ứng dụng lưu trạng thái và kích hoạt chế độ dẫn đường.

### C. Kế hoạch tiếp nhận phản hồi & Hỗ trợ kỹ thuật
- Thành lập nhóm hỗ trợ kỹ thuật trực tiếp (Zalo / Hotline) giải đáp thắc mắc 24/7.
- Thu thập tự động file log JSON từ nút bấm của Người bảo hộ để phân tích độ trôi GPS và các sự cố bỏ sót/báo nhầm.
