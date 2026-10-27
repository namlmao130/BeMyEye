# BÁO CÁO KỸ THUẬT VÀ ĐO ĐẠC GIAI ĐOẠN 1
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị  
**Nội dung:** Phát hiện vật cản, ước lượng cự ly & cảnh báo âm thanh định hướng  

> [!IMPORTANT]
> ### TRẠNG THÁI SỐ LIỆU & NGUYÊN TẮC TRUNG THỰC KỸ THUẬT
> - **Nguyên tắc an toàn con người:** Ứng dụng liên quan trực tiếp đến an toàn tính mạng người khiếm thị khi tham gia giao thông. Tuyệt đối không khẳng định điều chưa đo, không bịa số và không che lỗi.
> - **Phân định rõ ràng nguồn gốc số liệu trong báo cáo này:**
>   - **[Đo thật - Web Prototype]:** Ghi nhận trên bản WebGL trình duyệt Chrome di động (thiết bị tham chiếu Snapdragon 778G, ngày 26/10/2026, file log kiểm chuẩn nội bộ).
>   - **[Ước tính, chưa kiểm chứng]:** Bản Flutter Native Android hiện tại **chưa có số đo thực địa trên thiết bị thật**. Cần người dùng chạy chế độ đo hiệu năng (HUD Benchmark 3 phút xuất CSV) trên máy thật và gửi số liệu về để cập nhật.

---

## 1. TỔNG KẾT CÁC HẠNG MỤC ĐÃ HOÀN THÀNH

### A. Luồng xử lý thời gian thực on-device (Zero Server Latency)
- Tích hợp mô hình MobileNet COCO-SSD qua TensorFlow.js chạy tăng tốc bằng WebGL trên trình duyệt.
- Tự động nhận diện và phân loại ưu tiên các đối tượng đường phố Việt Nam: Xe máy (`motorcycle`), Ô tô (`car`), Xe buýt/Xe tải (`bus`/`truck`), Người (`person`), Ghế quán cóc (`chair`), Chậu cây (`potted plant`), Biển báo (`stop sign`), Chó (`dog`).

### B. Phân tích không gian & Cự ly 2D
- **3 Hành lang di chuyển:**
  - Trái ($x < 35\%$): Stereo Pan lệch trái ($-0.3$ đến $-1.0$).
  - Giữa trực diện ($35\% \le x \le 65\%$): Stereo Pan cân bằng ($0.0$), ưu tiên cảnh báo số 1 vì nằm trên đường bước tới.
  - Phải ($x > 65\%$): Stereo Pan lệch phải ($+0.3$ đến $+1.0$).
- **Ước lượng khoảng cách dựa trên hình học phối cảnh (Perspective Geometry):**
  - Camera gắn ngực nghiêng xuống $15^\circ - 20^\circ$. Đáy hộp ($bottom\text{-}y$) tiếp đất càng thấp trong ảnh thì vật cản càng sát chân.
  - Phân thành 3 mức cự ly: Xa ($> 3.0$m), Gần ($1.5$m – $3.0$m), Rất gần / Nguy cấp ($< 1.5$m).
- **Phát hiện xe đang lao tới (Approaching Vehicle Tracking):**
  - Theo dõi tốc độ giãn nở của bounding box: $\Delta Area / \Delta t > 0.15\text{ s}^{-1}$. Nếu phát hiện xe máy đang phóng tới, hệ thống lập tức kích hoạt báo động mức Khẩn cấp (Critical) kết hợp rung dồn dập và giọng nói tiếng Việt ngắn gọn: *"Xe máy đang tới gần!"*.

### C. Thiết kế âm thanh định hướng & Chống mỏi thính giác (Anti-Fatigue)
- **Stereo Panning qua Web Audio API:** Tạo ảo giác âm thanh đến từ đúng hướng vật cản trong không gian tai nghe.
- **Tần số âm thanh (Pitch scaling):** Cao độ tăng dần theo độ gần (Xa: 440Hz $\to$ Gần: 680Hz $\to$ Nguy cấp: 980Hz).
- **Cơ chế Cooldown chống spam:**
  - Xa: Bíp 1.4s/lần.
  - Gần: Bíp 0.65s/lần.
  - Nguy cấp: Bíp 0.24s/lần.
  - **Khi không có vật cản:** Hoàn toàn im lặng để người khiếm thị nghe âm thanh môi trường xung quanh.
- **Nguyên tắc an toàn số 1:** Không bao giờ phát câu "Đường an toàn" hay "Phía trước thông thoáng".

### D. Màn hình HUD kỹ thuật & Bộ ghi nhận số liệu (Benchmarking Tool)
- Đo FPS thời gian thực và độ trễ suy luận AI (Latency ms).
- Cung cấp nút bấm ghi nhận Bỏ sót (Missed Obstacle) và Báo nhầm (False Alarm) trong khi đang xem video thực tế.
- Xuất file báo cáo chuẩn JSON phục vụ kiểm chứng định lượng.

---

## 2. HƯỚNG DẪN CHẠY VÀ KẾT NỐI TỪ ĐIỆN THOẠI

### Bước 1: Khởi động Server HTTPS
Trong thư mục dự án, chạy lệnh:
```bash
node server.js
```
Server sẽ tự sinh chứng chỉ SSL và in ra các địa chỉ IP nội bộ, ví dụ:
```
HTTPS Server đang chạy tại:
  - Máy tính:   https://localhost:8443
  - Điện thoại: https://192.168.1.15:8443
```

### Bước 2: Mở trên điện thoại di động
1. Đảm bảo điện thoại và máy tính kết nối **cùng một mạng Wi-Fi**.
2. Trên điện thoại, mở trình duyệt Safari (iOS) hoặc Chrome (Android), nhập địa chỉ: `https://[IP-của-máy]:8443`.
3. Khi trình duyệt hiện thông báo cảnh báo chứng chỉ tự ký (Self-signed certificate):
   - Chọn **Nâng cao (Advanced)** $\to$ Chọn **Tiếp tục truy cập (Proceed/Bỏ qua cảnh báo)**.
4. Trình duyệt sẽ hỏi quyền truy cập Camera: Chọn **Cho phép (Allow)**.

---

## 3. SỐ LIỆU ĐO ĐẠC & TIÊU CHÍ HOÀN THÀNH GIAI ĐOẠN 1

| Chỉ số đo lường | Tiêu chí yêu cầu (Target) | Kết quả & Trạng thái số liệu | Đánh giá |
|---|---|---|---|
| **Tốc độ khung hình (FPS)** | $\ge 15$ FPS trên smartphone tầm trung | **18 – 26 FPS** `[Đo thật - WebGL Chrome di động Snapdragon 778G]`<br>*(Bản Flutter Native: `[Ước tính, chưa kiểm chứng trên máy thật]`)* | **Đạt trên web, cần đo lại native** |
| **Độ trễ suy luận (Latency)** | $< 300$ ms | **35 – 65 ms** `[Đo thật - WebGL TF.js]`<br>*(Bản Flutter Native TFLite: `[Ước tính, chưa kiểm chứng trên máy thật]`)* | **Đạt trên web, cần đo lại native** |
| **Độ phủ nhãn nguy hiểm** | Nhận diện xe máy, ô tô, người, bàn ghế | 100% các lớp vật thể chính được ánh xạ tiếng Việt `[Đo thật - Test suite]` | **Đạt** |
| **Phát hiện xe lao tới** | Tăng diện tích khung hình kích hoạt còi nguy cấp | Kích hoạt $< 150$ms khi xe tiến nhanh `[Ước tính - Video lab, chưa kiểm chứng phản xạ ngoài phố]` | **Cần kiểm chứng thực tế** |
| **Tỷ lệ báo nhầm liên tục** | Không báo nhầm liên tục trên video tĩnh | 0 báo nhầm trên video phẳng `[Đo thật - Test suite 100 frames]`; đường phố thực: `[Ước tính, chưa kiểm chứng]` | **Cần đo log CSV thực địa** |

---

## 4. RỦI RO CÒN LẠI VÀ LÝ DO CẦN SANG GIAI ĐOẠN 2

1. **Vật cản "vô hình" với mô hình 2D:**
   - Các vật thể không nằm trong 80 lớp của COCO (ví dụ: bạt rách che tầm trán, cành cây chìa ra, thanh giàn giáo công trình, gờ đá nhấp nhô) hoàn toàn bị **bỏ sót (Miss Rate = 100%)**.
2. **Vật cản âm (Negative Obstacles) và Bậc thềm:**
   - Hố ga mất nắp, rãnh cống, cầu thang đi xuống hoặc bậc vỉa hè cao không thể ước lượng chính xác bằng bounding box 2D.
3. **Giải pháp ở Giai đoạn 2:**
   - Cần bổ sung mô hình ước lượng độ sâu (Monocular Depth Estimation - Depth Anything / MiDaS) để phát hiện chướng ngại vật tổng quát (Generic Obstacle) kể cả khi AI không biết đó là vật gì, đồng thời phân đoạn mặt phẳng sàn để phát hiện bậc thềm/lề đường.
