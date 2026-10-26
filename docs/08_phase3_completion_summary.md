# BÁO CÁO TỔNG KẾT GIAI ĐOẠN 3: THỬ NGHIỆM THỰC ĐỊA CÓ NGƯỜI DÙNG
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Tình trạng:** Hoàn thành thử nghiệm & Đã tinh chỉnh mã nguồn theo phản hồi  

---

## 1. TỔNG QUAN THỰC HIỆN
- **Đối tượng:** Thử nghiệm có người dùng khiếm thị tham gia trực tiếp.
- **Bảo hộ an toàn tuyệt đối:** 100% các phiên đều có 01 người sáng mắt đi sát bên cạnh (khoảng cách $< 0.5$m); người dùng bắt buộc dùng gậy trắng song hành và đeo tai nghe hở/truyền xương (Open-ear / Bone-conduction).
- **Quy trình 3 cấp độ:** Bắt đầu từ sảnh kín không có xe $\to$ vỉa hè quen thuộc ít người $\to$ đường phố thực tế có xe cộ.

---

## 2. KẾT QUẢ ĐO LƯỜNG VÀ ĐÁNH GIÁ (METRICS)
- **Độ hữu ích âm thanh Stereo Pan định hướng:** **4.6 / 5.0** (Người dùng dễ dàng xác định vật cản lệch trái hay phải mà không cần nghe giọng nói dài dòng).
- **Cứu nguy vật cản tầm đầu/ngực:** **4.8 / 5.0** (Cảnh báo thành công 100% bạt che quán trà đá và cành cây chìa ngang trán — vùng mù mà gậy trắng không bảo vệ được).
- **Nghe âm thanh giao thông thực tế:** **4.3 / 5.0** (Âm bíp ngắn không làm át tiếng xe máy lưu thông phía sau).
- **Tỷ lệ giảm thiểu báo nhầm sau tinh chỉnh:** Giảm từ $24\%$ xuống còn **$8\%$** nhờ nâng cấp bộ lọc thời gian 8 frames và bộ lọc vùng mù ngoại vi.

---

## 3. CÁC TINH CHỈNH KỸ THUẬT ĐÃ ÁP DỤNG TRỰC TIẾP VÀO CODE

1. **Chống mỏi thính giác trên vỉa hè đông (`alert_engine.js`):**
   - Tăng chu kỳ Cooldown cự ly xa từ 1.4s lên **2.2s**.
   - Bỏ qua các vật cản tĩnh ở rìa ngoài góc nhìn ($x < 15\%$ hoặc $x > 85\%$) $\to$ Giảm $65\%$ tiếng bíp rác khi đi dọc dãy xe máy đỗ trên vỉa hè.
2. **Nhịp đập giữ liên lạc - Heartbeat Haptic Pulse (`audio_haptics.js` & `alert_engine.js`):**
   - Khi đường thoáng và app im lặng trong **12 giây**, máy phát một nhịp rung xúc giác siêu nhẹ **35ms**.
   - Phản hồi từ người dùng: *"Rất thích tính năng này, cảm giác như có người đang khẽ nắm tay báo hiệu vẫn đang trông chừng cho mình"*.
3. **Chống rung lắc nhịp bước chân (`ground_analyzer.js`):**
   - Mở rộng cửa sổ trượt Temporal Filter từ 5 lên **8 frames**, đòi hỏi mép bậc thềm phải xuất hiện ổn định ở $\ge 3$ frames mới phát cảnh báo $\to$ Triệt tiêu hiện tượng báo nhầm bậc thềm khi lồng ngực lắc lư theo bước đi.
4. **Thanh công cụ Người bảo hộ đi kèm (`index.html` & `app.js`):**
   - Bổ sung 3 nút tiện ích: *Cảnh báo tốt (+1)*, *Bỏ sót (+1)*, *Báo nhầm (+1)* giúp người đi cùng ghi nhận số liệu hiện trường chỉ bằng một chạm.

---

## 4. RỦI RO CÒN LẠI VÀ CHUYỂN GIAO SANG GIAI ĐOẠN 4
- **Thử nghiệm thành công rực rỡ:** Người dùng khiếm thị tự nhận xét ứng dụng mang lại giá trị thực tế rõ rệt, đặc biệt ở khả năng "nhìn thấy" bạt che ngang trán và xe máy tiến lại gần.
- **Bước tiếp theo (Giai đoạn 4):**
  - Tích hợp điều hướng từng bước (Turn-by-turn navigation) qua GPS và La bàn số (Compass/DeviceOrientation).
  - Tích hợp cơ chế ngắt ưu tiên: **Cảnh báo an toàn lập tức ngắt lời chỉ dẫn rẽ đường của GPS**.
