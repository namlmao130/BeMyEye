---
name: realtime-vision-pipeline
description: >-
  Sử dụng skill này khi phát triển, gỡ lỗi hoặc tối ưu hóa pipeline camera thời gian thực,
  tiền xử lý ảnh LUT YUV420, suy luận TFLite SSD MobileNet, cấu hình phần cứng NNAPI/GPU/CPU delegate,
  quản lý bộ đệm zero-allocation và tối ưu hóa FPS cho ứng dụng Be My Eyes VN trên Android/Flutter.
---

# Realtime Vision Pipeline & TFLite Optimization Skill

Skill này đóng vai trò cẩm nang hướng dẫn kỹ thuật toàn diện cho luồng xử lý thị giác máy tính thời gian thực (Camera -> Preprocess -> TFLite -> Pipeline Watchdog) trên thiết bị di động.

---

## 1. Kiến trúc luồng xử lý (Camera-to-Inference)

```
[CameraImage (YUV420)]
         │
         ▼
[Bảng tra LUT (precomputed Look-Up Tables)]
         │  (Biến đổi tọa độ & ánh xạ 0-copy, 2-4ms)
         ├───────────────────────────────┐
         ▼                               ▼
[Uint8List 300x300 RGB]        [Uint8List 160x120 Luma]
(Input Tensor TFLite)           (GroundPlaneAnalyzer)
         │                               │
         ▼                               ▼
[TFLite SSD MobileNet]          [Phân tích mặt đất]
(NNAPI/GPU/CPU, 25-45ms)         (Throttled ~6Hz)
         │                               │
         └───────────────┬───────────────┘
                         ▼
             [SpatialThreatAnalyzer]
```

---

## 2. Các nguyên tắc tối ưu hóa hiệu năng bắt buộc

### 2.1. Tiền xử lý ảnh bằng LUT (Look-Up Table)
- **Vấn đề:** Chuyển đổi YUV420 sang RGB 300x300 dùng phép chia và phép kẹp số thực (clamp) trên từng pixel tốn ~80ms.
- **Giải pháp:** Sử dụng bảng tra cứu tọa độ tĩnh đã tính toán trước (`_lutRot0`, `_lutRot90`, `_lutRot180`, `_lutRot270` trong `camera_pipeline_service.dart`).
- **Quy tắc:**
  - Không bao giờ thực hiện phép chia hay gọi `clamp()` trong vòng lặp pixel.
  - Sử dụng buffer cố định tái sử dụng (`_rgb300Buffer`, `_luma160Buffer`), tuyệt đối không tạo mới `Uint8List` mỗi khung hình để tránh GC churn.

### 2.2. Zero-Copy In-Place vs Isolate Serialization
- **Bài học quan trọng:** Việc dùng `compute(preprocessCameraFrame, ...)` gây độ trễ serialize/deserialize 1.4 MB dữ liệu qua port giữa các Isolate tốn 40-70ms.
- **Quy tắc:** Với thuật toán LUT chỉ tốn 2-4ms, hãy chạy in-place ngay trên luồng chính hoặc luồng phụ liên tục với buffer cố định, loại bỏ hoàn toàn chi phí sao chép bộ nhớ.

### 2.3. Cấu hình TFLite Interpreter & Bộ tăng tốc phần cứng
Tệp nguồn: [`flutter_app/lib/services/detector_service.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/detector_service.dart)

- **Thứ tự Delegate:**
  1. **GPU Delegate:** Thử nghiệm đầu tiên nếu tương thích.
  2. **Android NNAPI (`useNnApiForAndroid = true`):** Tối ưu vượt trội cho các mô hình lượng tử hóa int8/uint8 trên chip MediaTek, Snapdragon, Tensor.
  3. **CPU Fallback:** Sử dụng `threads = 2` (không dùng quá nhiều luồng gây nghẽn UI và tăng nhiệt).
- **Bộ đệm đầu ra tái sử dụng (Zero-Allocation Output):**
  - Tensors đầu ra của SSD MobileNet:
    - Boxes: `Float32List(40)` (1x10x4)
    - Classes: `Float32List(10)` (1x10)
    - Scores: `Float32List(10)` (1x10)
    - Count: `Float32List(1)` (1)
  - Khởi tạo mảng đầu ra một lần duy nhất lúc khởi động mô hình, truyền cùng buffer vào `interpreter.runForMultipleInputs()`.

### 2.4. Khắc phục lệch nhãn COCO SSD (`kLabelOffset`)
- Mô hình SSD MobileNet trả chỉ số lớp bắt đầu từ `0`.
- File `assets/models/labelmap.txt` chứa dòng đầu tiên là `???` (chỉ số 0 trong chuẩn COCO 91 lớp).
- **Quy tắc:** Khi ánh xạ class index sang nhãn, bắt buộc sử dụng:
  ```dart
  final int labelIdx = classIndex + kLabelOffset; // kLabelOffset = 1
  ```
  Luôn kiểm tra biên: `if (labelIdx >= 0 && labelIdx < labels.length)`.

---

## 3. Pipeline Watchdog & Trạng thái an toàn

Tệp nguồn: [`flutter_app/lib/services/camera_pipeline_service.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/camera_pipeline_service.dart)

Hệ thống quản lý trạng thái máy tự động `PipelineStatus`:
- `demo`: Khi mô hình chưa nạp xong hoặc pipeline chưa khởi động.
- `starting`: Đang yêu cầu quyền camera và khởi động cảm biến.
- `running`: Chỉ chuyển sang trạng thái này khi `detector.isReady == true` VÀ nhận được khung hình camera trong vòng **1.5 giây**.
- `failed`: Tự động khóa chế độ dẫn đường khi:
  1. Người dùng từ chối quyền Camera.
  2. Watchdog phát hiện mất tín hiệu khung hình quá 1.5 giây.
  3. Xảy ra $\ge 5$ lỗi suy luận AI liên tiếp.
  4. Báo lỗi bằng giọng nói tiếng Việt to rõ: *"Mất tín hiệu camera, đừng dùng ứng dụng để dẫn đường"*.

---

## 4. Các bước kiểm tra & Xác thực
Mỗi khi chỉnh sửa luồng xử lý ảnh:
1. Chạy test kiểm thử hiệu năng và bộ đệm:
   ```bash
   flutter test test/perf_optimization_test.dart
   ```
2. Chạy test xác thực mô hình thật với ảnh xe buýt:
   ```bash
   flutter test test/nv12_item1_bus_test.dart
   ```
3. Chạy test Watchdog và trạng thái an toàn:
   ```bash
   flutter test test/nv12_item2_pipeline_status_test.dart
   ```
