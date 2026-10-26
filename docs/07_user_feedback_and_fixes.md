# BÁO CÁO PHẢN HỒI THỬ NGHIỆM VÀ TINH CHỈNH KỸ THUẬT GIAI ĐOẠN 3
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Đối tượng thử nghiệm:** 3 người khiếm thị (02 người mù hoàn toàn, 01 người nhìn mờ nhận biết sáng/tối)  
**Địa điểm:** Khuôn viên nội bộ và 01 tuyến vỉa hè tại Hà Nội / TP.HCM  

---

## 1. TỔNG HỢP PHẢN HỒI THỰC TẾ CỦA NGƯỜI DÙNG

| Tiêu chí khảo sát | Điểm trung bình (1 - 5) | Nhận xét chi tiết từ người tham gia |
|---|---|---|
| **Độ hữu ích âm thanh Stereo Pan** | **4.6 / 5.0** | Rất tự nhiên. Người dùng hình dung ngay vật cản lệch trái hay phải mà không cần nghe câu thoại dài dòng. |
| **Bảo vệ tầm đầu / ngực** | **4.8 / 5.0** | *Được đánh giá cao nhất.* Đã giúp người dùng khựng lại kịp thời trước 02 bạt che quán trà đá hạ thấp mà gậy trắng không chạm tới. |
| **Không che âm thanh xung quanh** | **4.3 / 5.0** | Khi dùng tai nghe truyền xương, người dùng vẫn nghe rõ tiếng xe máy lưu thông phía sau lưng. |
| **Mỏi mệt thính giác ban đầu** | **3.2 / 5.0 (Cần cải thiện)** | Khi đi qua đoạn vỉa hè có nhiều bàn ghế và xe máy đỗ dài dằng dặc, app bíp liên tục gây căng thẳng đầu óc. |
| **Cảm giác bất an khi app im lặng** | **3.0 / 5.0 (Cần cải thiện)** | Khi đường thoáng, app im lặng khiến người dùng hoang mang tự hỏi: *"Máy có bị treo hoặc tắt nguồn không?"*. |

---

## 2. BA VẤN ĐỀ KỸ THUẬT PHÁT HIỆN & GIẢI PHÁP ĐÃ TINH CHỈNH

### Vấn đề 1: Bị "Spam" âm thanh khi vỉa hè chật chội
- **Hiện tượng:** Vỉa hè Việt Nam luôn có xe máy đỗ dọc lề. Dù xe ở xa (> 3.5m) và nằm sát mép ngoài, app vẫn bíp chu kỳ 1.4s khiến người dùng bị quá tải thính giác.
- **Giải pháp kỹ thuật đã sửa:**
  - Tăng khoảng thời gian Cooldown vùng xa từ **1.4s lên 2.2s**.
  - Áp dụng **Vùng mù ngoại vi (Peripheral Deadzone Filter):** Vật cản nằm ở góc ngoài cùng (Trái $< 18\%$ hoặc Phải $> 82\%$) và không di chuyển sẽ bị giảm mức ưu tiên để không phát bíp liên tục.

### Vấn đề 2: Người dùng lo sợ app bị đơ khi im lặng $\to$ Thêm "Nhịp đập giữ liên lạc" (Heartbeat Pulse)
- **Hiện tượng:** Khi không có vật cản, app im lặng tuyệt đối. Người khiếm thị cảm thấy mất kết nối và không biết app còn sống không.
- **Giải pháp kỹ thuật đã sửa:**
  - Bổ sung cơ chế **Heartbeat Haptic Pulse:** Nếu trong vòng **12 giây** hoàn toàn không có cảnh báo nào, điện thoại sẽ **rung nhẹ 1 nhịp siêu ngắn (35ms)**.
  - Tác dụng: Báo cho người dùng biết "Tôi vẫn đang quan sát và bảo vệ bạn", giúp giải tỏa tâm lý lo âu mà không hề phát ra âm thanh làm phiền thính giác.

### Vấn đề 3: Rung lắc lồng ngực làm góc camera chao đảo
- **Hiện tượng:** Khi bước đi với dây đeo ngực, nhịp chân (~1.8 bước/giây) làm lồng ngực lắc lư làm mép mặt đất giật lên xuống, khiến `GroundPlaneAnalyzer` đôi lúc nhận diện nhầm bóng râm thành bậc bước xuống.
- **Giải pháp kỹ thuật đã sửa:**
  - Nâng bộ lọc làm mượt qua thời gian (Temporal Filter) lên **8 frames**, đòi hỏi mép bậc thềm phải xuất hiện ổn định ở ít nhất 4 frames liên tiếp mới được kích hoạt cảnh báo.
  - Bổ sung công cụ thanh công cụ nổi dành cho người đi kèm (Sighted Companion Toolbar) để bấm ghi nhận và kiểm chứng tại chỗ.
