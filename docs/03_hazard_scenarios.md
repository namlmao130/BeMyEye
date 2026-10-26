# DANH SÁCH TÌNH HUỐNG NGUY HIỂM TRÊN ĐƯỜNG PHỐ VIỆT NAM
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị  
**Xếp hạng:** Theo mức độ rủi ro thương tật / an toàn tính mạng giảm dần

---

## BẢNG TỔNG HỢP VÀ PHÂN TÍCH KỸ THUẬT COMPUTER VISION

| Thứ hạng | Tình huống nguy hiểm | Hậu quả nếu sót | Độ khó kỹ thuật CV trên di động | Hướng xử lý khả thi |
|---|---|---|---|---|
| **#1** | **Xe máy đang di chuyển** (lao lên vỉa hè, chạy ngược chiều, cua gấp từ hẻm) | Chấn thương nặng, nguy cơ tử vong do vận tốc va chạm lớn. | **Rất cao**: Cần FPS cao (>= 15-20), độ trễ < 200ms. Thuật toán tracking phải tính được tốc độ giãn nở của bounding box (vật đang tiến lại gần). | Ưu tiên số 1 trong mô hình Object Detection (YOLO / MobileNet). Báo còi khẩn cấp ngắt mọi âm thanh khác. |
| **#2** | **Vật cản ngang tầm đầu / ngực** (cành cây chìa ra, bạt che quán hạ thấp, gương xe tải, xích treo) | Va đập rách trán, chấn thương mắt, ngực. *Gậy trắng hoàn toàn không chạm tới.* | **Cực cao**: Mô hình nhận diện COCO 2D không có nhãn "bạt che rách" hay "cành cây". Dây xích, thanh kim loại rất mảnh (thin structures) dễ biến mất sau resize. | Cần mô hình Depth Estimation (Giai đoạn 2) hoặc phát hiện bề mặt bất thường ở nửa trên khung hình. Gậy trắng không bảo vệ được vùng này! |
| **#3** | **Hố ga mất nắp, rãnh cống hở, hố công trình** (Vật cản âm - Negative Obstacles) | Bước hụt, gãy chân, rơi xuống cống nguy kịch. | **Cực cao**: 2D Bounding Box gần như vô dụng. Vùng hố tối màu rất dễ bị nhầm với bóng râm của cây/tòa nhà hoặc ngược lại (báo nhầm liên tục). | Cần phân đoạn mặt phẳng sàn (Plane Segmentation) hoặc Depth estimation kết hợp gậy trắng. Nhắc nhở người dùng: *Gậy trắng là chốt chặn chính cho hố.* |
| **#4** | **Bậc tam cấp lấn vỉa hè, lề đường cao (Curb) đi xuống** | Vấp ngã, chấn thương khớp gối, cổ chân. | **Cao**: Mặt bậc tam cấp thường cùng màu gạch với vỉa hè. Khi trời nắng gắt bị mất bóng đổ (washout). | Phân tích viền dốc (edge detection) và mô hình depth đơn thị sai (Monocular depth). |
| **#5** | **Vật cản tĩnh chiếm lối đi** (xe máy dựng kín vỉa hè, bàn ghế nhựa quán cóc, chậu cây) | Vấp ngã, bầm tím cẳng chân; buộc người dùng phải đi xuống lòng đường. | **Trung bình**: Các class này (motorcycle, chair, potted plant) có sẵn trong COCO dataset. Nhận diện khá chuẩn nếu đủ sáng. | Bounding box 2D kết hợp ước lượng khoảng cách dựa vào tọa độ đáy hộp (bottom-y of bounding box). |
| **#6** | **Rào chắn công trình tạm bợ, thanh giàn giáo thô** | Xước da, va đập mạnh. | **Cao**: Thanh sắt mảnh, lưới công trình màu xanh tiệp màu nền. | Cảnh báo vùng chướng ngại vật tổng thể (Generic obstacle). |
| **#7** | **Động vật thả rông (chó giữ nhà ở hẻm)** | Bị cắn, hoảng loạn tinh thần. | **Trung bình**: COCO có class "dog", nhưng chó ở hẻm VN thường nằm khuất bóng râm hoặc lao ra nhanh. | Báo âm thanh ngắn: "Có động vật bên [hướng]". |

---

## CHIẾN LƯỢC PHÂN TẦNG CẢNH BÁO (TIERED ALERT SYSTEM)

1. **Mức 1 - Khẩn cấp (Critical / Collision Imminent):**
   - Áp dụng: Xe máy tiến lại gần < 2.5m, vật cản tầm đầu cách < 1.5m.
   - Đầu ra: Âm báo bíp dồn dập tần số cao + Rung điện thoại mạnh. Lập tức ngắt lời dẫn đường GPS.
2. **Mức 2 - Cảnh báo chú ý (Warning):**
   - Áp dụng: Xe máy đỗ, bàn ghế, người đi ngược chiều cách 2m - 4m nằm trong hành lang di chuyển (hành lang giữa ±30°).
   - Đầu ra: Tiếng bíp định hướng stereo pan (Trái/Giữa/Phải). Tần suất vừa phải (1 lần/giây).
3. **Mức 3 - Thông tin tham khảo (Info / Peripheral):**
   - Áp dụng: Vật cản ở xa (> 4m) hoặc nằm ở rìa ngoài góc nhìn không cản đường đi.
   - Đầu ra: Không phát âm thanh hoặc chỉ hiển thị log trên màn hình debug để tránh gây quá tải thính giác (Auditory fatigue).
