---
name: spatial-threat-analysis
description: >-
  Sử dụng skill này khi phát triển, hiệu chuẩn hoặc gỡ lỗi các thuật toán phân tích không gian 3D,
  mô hình camera pin-hole, bù góc nghiêng điện thoại (tilt pitch angle), phát hiện chướng ngại vật mặt đất (hố sụt, bậc bước xuống),
  vật cản treo cao (bạt che ngang trán), hồi quy tuyến tính phát hiện vật thể đang lao tới (approaching), và cân bằng điểm nguy cơ (threat score).
---

# Spatial Threat Analysis & Obstacle Decision Engine

Skill này hướng dẫn chi tiết các nguyên tắc toán học, mô hình hình học và thuật toán ra quyết định cảnh báo nguy hiểm trong không gian thực tế đường phố Việt Nam.

---

## 1. Mô hình Hình học Camera & Bù góc nghiêng (Tilt Angle Compensation)

Tệp nguồn: [`flutter_app/lib/services/spatial_analyzer.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/spatial_analyzer.dart)

### 1.1. Ước lượng khoảng cách hệ mét
- Điện thoại được quy ước đeo trước ngực người dùng ở độ cao mặc định $h = 1.35\text{ m}$ (`kDefaultMountHeightMeters`).
- Vị trí chân của vật thể trong ảnh ($bottomY \in [0.0, 1.0]$) được chuyển đổi sang khoảng cách thực tế phía trước theo mô hình Pin-hole và mặt đất phẳng.

### 1.2. Quy ước dấu bù góc nghiêng (Tilt Angle)
- Khi người dùng đi bộ, điện thoại đeo ngực thường chúc nhẹ xuống mặt đường ($\theta > 0$, ví dụ $+10^\circ$).
- **Quy tắc dấu:** Khi camera chúc xuống, mặt đất trong ảnh bị đẩy lên cao hơn, do đó ngưỡng $bottomY$ để nhận diện vật thể "nguy cấp / ở sát chân" phải **giảm đi**:
  ```dart
  final double tiltOffset = sin(tiltAngleRad) * kTiltCorrectionFactor;
  final double adjustedCriticalBottomY = kCriticalBottomY - tiltOffset; // DẤU TRỪ BẮT BUỘC
  ```
- *Lưu ý an toàn:* Không được đảo thành dấu cộng vì sẽ khiến vật thể ở rất xa bị nhận nhầm là sát chân, gây cảnh báo hoảng loạn liên tục.

---

## 2. Hồi quy tuyến tính phát hiện "Đang tới gần" (`isApproaching`)

Tệp nguồn: [`flutter_app/lib/services/spatial_analyzer.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/spatial_analyzer.dart)

### 2.1. Vấn đề rung lắc hộp bao (Bounding Box Jitter)
- Bộ phát hiện SSD MobileNet thường có độ nhiễu diện tích hộp bao $\pm 10–20\%$ giữa các khung hình liên tiếp. Nếu chỉ so sánh $area_t > area_{t-1}$, một vật tĩnh (như cột điện, ghế đá) sẽ liên tục bị báo là "xe máy đang lao tới".

### 2.2. Thuật toán Hồi quy Tuyến tính (Linear Regression)
Chỉ đánh dấu `isApproaching = true` khi thỏa mãn đồng thời:
1. **Chủng loại:** Chỉ áp dụng cho danh mục phương tiện giao thông (`category == 'vehicle'`, ví dụ `motorcycle`, `bicycle`, `bus`, `car`). Vật tĩnh tuyệt đối không kích hoạt `isApproaching`.
2. **Kích thước mẫu:** Lưu vết lịch sử mẫu hộp bao trong cửa sổ trượt: $\ge 5$ mẫu (`kMinApproachingSamples`).
3. **Khoảng thời gian tối thiểu:** Thời gian trôi qua giữa mẫu đầu và mẫu cuối $\ge 0.30\text{ giây}$ (`kMinApproachingTimeWindowSec`).
4. **Hệ số xác định tương quan ($R^2$):** Đánh giá độ khớp đường thẳng tăng diện tích:
   $$R^2 \ge 0.50 \quad (\text{kApproachingR2Threshold})$$
5. **Độ dốc tương đối:** Hệ số góc chuẩn hóa $Slope_{rel} \ge 0.35/\text{s}$ (`kApproachingMinSlopePerSec`).
6. **Bù tốc độ đi bộ:** Lấy vận tốc GPS/cảm biến từ `NavigationService`, nâng ngưỡng dốc theo tốc độ bước đi của người dùng để tránh báo nhầm do chính người dùng đi lại gần vật thể.

---

## 3. Phân tích Mặt đất & Bậc bước xuống (Ground Plane Analysis)

Tệp nguồn: [`flutter_app/lib/services/ground_plane_analyzer.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/ground_plane_analyzer.dart)

- **Đặc trưng:** Phát hiện bậc thang bước xuống (step-down drop-off) và hố ga/vũng nước qua dải gradient độ sáng luma đột ngột ở 1/3 góc dưới khung hình ($160 \times 120$ luma buffer).
- **Điều tiết chu kỳ (Throttling):** Không chạy phân tích mặt đất trên từng khung hình 30 FPS. Chỉ chạy với tần số ~6.2 Hz (chu kỳ 160ms `kGroundIntervalNormalMs`), tiết kiệm 70% tải CPU.
- **Bộ lọc thời gian (Temporal Filter):** Cần mép bậc xuất hiện ổn định ở $\ge 3$ khung liên tiếp để tránh báo nhầm khi lồng ngực lắc lư theo bước chân.

---

## 4. Cân bằng Điểm Nguy cơ (Threat Scoring Balancing)

Tệp nguồn: [`flutter_app/lib/services/alert_decision_engine.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/alert_decision_engine.dart)

Bảng phân bổ điểm số ưu tiên an toàn:

| Loại chướng ngại vật | Khoảng cách / Trạng thái | Điểm nguy cơ (`ThreatScore`) | Ưu tiên |
| :--- | :--- | :--- | :--- |
| **Xe cộ đang lao tới (Approaching)** | Khoảng cách gần ($< 2.5\text{m}$) | **180** | Cực kỳ nguy cấp |
| **Bậc bước xuống / Hố sâu nguy hiểm** | Độ tin cậy cao ($\ge 0.8$) | **160** | Cực kỳ nguy cấp |
| **Xe cộ tĩnh / Phương tiện** | Ở sát phía trước ($< 1.5\text{m}$) | **125** | Nguy cấp cao |
| **Người đi bộ (Pedestrian)** | Ở sát phía trước ($< 1.5\text{m}$) | **105** | Nguy cấp |
| **Vật cản mặt đất thường** | Độ tin cậy trung bình ($< 0.8$) | **100** | Cảnh báo vừa |
| **Bạt che ngang trán (Umbrella)** | Ở độ cao đầu người ($y \in [0.1, 0.45]$) | **95** | Cảnh báo va đầu |

> [!IMPORTANT]
> **Quy tắc vàng cân bằng điểm số:** Vật cản mặt đất độ tin cậy trung bình (confidence < 0.8) phải luôn có điểm **thấp hơn** phương tiện giao thông và người đi bộ ở cự ly gần để tránh tình trạng cảnh báo mặt đường che lấp một chiếc xe máy đang ở ngay phía trước.

---

## 5. Các bước kiểm tra & Xác thực
1. Kiểm tra bù góc nghiêng:
   ```bash
   flutter test test/nv12_item4_tilt_test.dart
   ```
2. Kiểm tra bộ lọc tiếp cận hồi quy tuyến tính:
   ```bash
   flutter test test/nv12_item3_approaching_test.dart
   ```
3. Kiểm tra tính điểm nguy cơ:
   ```bash
   flutter test test/nv12_item5_threat_score_test.dart
   ```
