# KỊCH BẢN VÀ QUY TRÌNH THỬ NGHIỆM AN TOÀN VỚI NGƯỜI KHIẾM THỊ
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Giai đoạn:** Giai đoạn 3 - Thử nghiệm thực địa có người dùng (User In-The-Loop Testing)

---

## 1. NGUYÊN TẮC AN TOÀN BẤT KHẢ XÂM PHẠM
1. **Luôn có "Bóng bảo hộ sáng mắt" (Sighted Safety Shadow):**  
   Mỗi người tham gia thử nghiệm luôn có 01 người sáng mắt đi kèm bên cạnh (khoảng cách không quá 0.5 mét), sẵn sàng can thiệp vật lý tức thì nếu có nguy cơ vấp ngã hoặc va chạm xe cộ.
2. **Không bao giờ bỏ gậy trắng:**  
   Người tham gia bắt buộc phải sử dụng gậy trắng định hướng như thói quen hằng ngày. App chỉ là giác quan phụ trợ tầm xa và tầm cao.
3. **Tuyệt đối không bịt tai (Open Ears Rule):**  
   Chỉ sử dụng tai nghe truyền xương (Bone-conduction), tai nghe hở (Open-ear) hoặc loa ngoài của điện thoại. Người dùng phải nghe rõ tiếng còi xe, tiếng động cơ thật phía sau.
4. **Dừng lại ngay khi mệt mỏi:**  
   Mỗi phiên thử nghiệm kéo dài tối đa 15–20 phút để tránh gây quá tải thính giác và căng thẳng thần kinh.

---

## 2. KỊCH BẢN THỬ NGHIỆM 3 CẤP ĐỘ

### Cấp độ 1: Khuôn viên khép kín (Controlled Environment - 15 phút)
- **Địa điểm:** Hành lang tòa nhà, sảnh chung cư hoặc sân trường học vắng người, không có xe cơ giới.
- **Vật cản bố trí:** Bàn ghế nhựa, thùng carton, cành cây/dây chăng tầm ngực.
- **Mục tiêu:**
  - Làm quen với âm thanh Stereo Pan (Trái / Giữa / Phải).
  - Kiểm tra độ thoải mái của dây đeo điện thoại trước ngực.
  - Xác nhận người dùng hiểu ý nghĩa các tiếng bíp khác nhau.

### Cấp độ 2: Vỉa hè quen thuộc, ít xe (Low-Traffic Sidewalk - 20 phút)
- **Địa điểm:** Tuyến vỉa hè quen thuộc gần nhà hoặc cơ sở của Hội người mù, mật độ người đi bộ thấp.
- **Hiểm họa tự nhiên:** Bậc tam cấp nhà dân, chậu cây cảnh, cây xanh đô thị, vỉa hè mấp mô.
- **Mục tiêu:**
  - Đánh giá khả năng cảnh báo sớm vật cản để người dùng chủ động né trước khi gậy trắng va vào.
  - Đo tỷ lệ báo nhầm trên bóng râm và hoa văn gạch lát vỉa hè.

### Cấp độ 3: Đường phố thực tế (Realistic Street - 15 phút, thận trọng tối đa)
- **Địa điểm:** Tuyến phố có xe máy đỗ trên vỉa hè, hẻm nhỏ có người đi bộ và xe máy lưu thông chậm.
- **Mục tiêu:**
  - Kiểm tra tính năng phát hiện xe máy lao tới ($\Delta Area / \Delta t$).
  - Đo mức độ ồn của phố xá có lấn át tiếng bíp hay không.

---

## 3. BẢNG QUAN SÁT CỦA NGƯỜI ĐI KÈM (OBSERVER CHECKLIST)
*(Người đi kèm sử dụng nút bấm nhanh trên giao diện để ghi nhận tức thì)*

| Thời điểm | Loại sự kiện | Tình huống thực tế | Phản ứng của người dùng | Kết luận (Đạt / Lỗi) |
|---|---|---|---|---|
| `Phút 02:15` | Cảnh báo xe máy | Xe máy đỗ lấn 2/3 vỉa hè bên phải | Nghe bíp bên phải, chủ động nghiêng gậy sang trái né mượt mà | Đạt |
| `Phút 05:40` | Vật cản ngang đầu | Bạt che quán trà đá hạ thấp ngang trán | Nghe bíp sắc bén 1100Hz, khựng lại và cúi đầu nhẹ | Đạt (Cứu nguy va chạm) |
| `Phút 08:12` | Báo nhầm | Bóng râm cây xà cừ đổ ngang đường | Nghe báo "Chú ý: bậc đi xuống!", dùng gậy quét kiểm tra không thấy | Báo nhầm (False Alarm) |
| `Phút 12:30` | Bỏ sót | Cành cây khô mảnh chìa ngang vai | App không kêu, gậy trắng không tới, người bảo hộ kịp kéo lại | Bỏ sót nguy hiểm (Missed) |

---

## 4. BẢNG CÂU HỎI ĐÁNH GIÁ SAU THỬ NGHIỆM (POST-TEST SURVEY)
*(Chấm điểm theo thang đo Likert 1–5: 1 = Rất kém/Rất khó chịu, 5 = Rất tốt/Rất hài lòng)*

1. **Định hướng âm thanh Stereo:** Tiếng bíp Trái / Giữa / Phải có giúp Anh/Chị hình dung vị trí vật cản không?  
   `[ 1 ]  [ 2 ]  [ 3 ]  [ 4 ]  [ 5 ]`
2. **Khả năng nghe môi trường:** Tiếng bíp của app có làm át tiếng còi xe hoặc tiếng xe máy phía sau không?  
   `[ 1: Rất chói tai ]  <----->  [ 5: Rất vừa phải, nghe rõ xung quanh ]`
3. **Mức độ mỏi mệt thính giác:** Sau 15 phút đi bộ, Anh/Chị có cảm thấy bị nhức đầu hoặc khó chịu vì tiếng bíp không?  
   `[ 1: Rất căng thẳng ]  <----->  [ 5: Dễ chịu, chấp nhận được ]`
4. **Vị trí đeo điện thoại trước ngực:** Dây đeo có bị lắc lư làm Anh/Chị khó chịu không?  
   `[ 1 ]  [ 2 ]  [ 3 ]  [ 4 ]  [ 5 ]`
5. **Độ tin cậy tổng thể:** So với việc chỉ dùng gậy trắng đơn thuần, việc có thêm app có làm Anh/Chị cảm thấy tự tin và an toàn hơn không?  
   `[ 1: Không giúp ích ]  <----->  [ 5: Rất yên tâm, hỗ trợ tốt ]`
