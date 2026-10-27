---
name: field-testing-benchmarking
description: >-
  Sử dụng skill này khi tiến hành đo đạc thực địa, thực hiện chế độ Benchmark 3 phút xuất file log CSV,
  quản lý cấu hình ngưỡng tập trung thresholds.dart, hoặc kiểm tra tính trung thực của các số liệu hiệu năng.
---

# Field Testing, Benchmarking & Honesty Guidelines Skill

Skill này định nghĩa các tiêu chuẩn đo đạc thực địa, thu thập log hiệu năng và nguyên tắc đạo đức kỹ thuật bắt buộc của dự án "Be My Eyes VN".

---

## 1. Nguyên tắc Đạo đức & An toàn Kỹ thuật Bắt buộc

> [!CAUTION]
> **Đây là sản phẩm trợ năng liên quan trực tiếp đến tính mạng con người.** Tuyệt đối không được phép vi phạm các nguyên tắc sau:

1. **Tuyệt đối không tự bịa số liệu:**
   - Không được phép ghi bất kỳ con số hiệu năng nào (FPS, độ trễ ms, pin, tỷ lệ báo nhầm) vào `README.md` hay tài liệu dự án nếu chưa có log đo đạc thật từ thiết bị di động vật lý.
   - Luôn kèm theo banner cảnh báo:
     > *"TRẠNG THÁI SỐ LIỆU: Cần chạy trên thiết bị thật để có số liệu kiểm chứng, không tự khẳng định kết quả."*
2. **Tuyệt đối không nói "Đường an toàn":**
   - Ứng dụng **không bao giờ** được phát âm thanh hay thông báo câu *"Đường an toàn"*, *"Đường trống"* hay tương đương.
   - Lý do: Camera điện thoại có góc nhìn giới hạn, không thể nhìn thấy vật cản ngoài khung hình hoặc các rủi ro phát sinh tức thời.
3. **Lỗi phải "kêu to":**
   - Mọi thất bại (mất tín hiệu camera, từ chối quyền, không tải được mô hình) phải lập tức chặn chế độ dẫn đường và phát thông báo giọng nói tiếng Việt to rõ cảnh báo người dùng. Tuyệt đối không bao giờ âm thầm bỏ qua (`catch (_) {}`).

---

## 2. Quản lý Ngưỡng Tập trung (`lib/config/thresholds.dart`)

Tệp nguồn: [`flutter_app/lib/config/thresholds.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/config/thresholds.dart)

- **Quy tắc vàng:** **MỌI NGƯỠNG SỐ** (khoảng cách, tỷ lệ diện tích, thời gian cooldown, kích thước cửa sổ trượt, tần số âm thanh, thời lượng benchmark) đều phải gom về tệp `thresholds.dart`.
- Mỗi hằng số bắt buộc có:
  - Tên biến tiền tố `k...` rõ nghĩa.
  - Chú thích đơn vị đo cụ thể (`m`, `ms`, `sec`, `rad`, `Hz`, `score`).
  - Lý do khoa học hoặc thực địa giải thích tại sao chọn con số đó.
- Không được để xuất hiện các "con số ma thuật" (magic numbers) rải rác trong các file dịch vụ logic.

---

## 3. Hệ thống Đo đạc Benchmark 3 phút & Ghi log CSV

Tệp nguồn: [`flutter_app/lib/services/csv_logger.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/csv_logger.dart)

### 3.1. Chế độ Benchmark 3 phút (`startBenchmark`)
- Cho phép người kiểm thử thực địa bấm một nút duy nhất trên HUD để bắt đầu ghi nhận dữ liệu trong chính xác 180 giây (`kBenchmarkDurationSeconds = 180`).
- Khi kết thúc 3 phút, hệ thống tự động:
  - Dừng thu thập khung hình.
  - Tính toán các chỉ số thống kê trung thực: Frame count, Min/Max/Avg FPS, Độ trễ trung bình từng bước (Preprocess, Inference, Analysis, Total).
  - Tự động sao chép toàn bộ nội dung CSV kèm Banner cảnh báo vào Clipboard để gửi lại cho đội ngũ kỹ thuật.

### 3.2. Tối ưu hóa Hiệu năng: Tắt Log ở chế độ thường
- **Vấn đề:** Ghi log liên tục mỗi frame sinh ra 20–30 đối tượng chuỗi `DateTime` và dời mảng $O(N)$ trong RAM gây gián đoạn khung hình (lag).
- **Giải pháp:**
  - Ở chế độ dẫn đường bình thường: Ghi log CSV bị **tắt hoàn toàn** (`if (!isBenchmarkRunning && !isLoggingEnabled) return;`).
  - Chỉ kích hoạt thu thập khi người dùng nhấn bắt đầu phiên Benchmark.
  - Cấu trúc dữ liệu sử dụng `ListQueue` với thao tác `removeFirst()` đạt độ phức tạp $O(1)$.

---

## 4. Các bước kiểm tra & Xác thực
1. Kiểm tra tính năng Benchmark 3 phút và banner cảnh báo trung thực:
   ```bash
   flutter test test/nv12_item8_benchmark_test.dart
   ```
2. Kiểm tra tài liệu và banner trạng thái số liệu:
   ```bash
   flutter test test/nv12_item7_docs_banner_test.dart
   ```
