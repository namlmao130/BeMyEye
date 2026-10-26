# KIẾN TRÚC CHUYỂN ĐỔI NATIVE APP (FLUTTER / SWIFT / KOTLIN)
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  
**Giai đoạn:** Giai đoạn 5 - Hoàn thiện & Định hướng Native

---

## 1. SO SÁNH WEB PWA VS NATIVE APP

| Tiêu chí kỹ thuật | Web App (Đã hoàn thành ở GĐ 1-4) | Native App (Mục tiêu Giai đoạn 5) |
|---|---|---|
| **Cài đặt & Truy cập** | Mở ngay bằng link HTTPS, không cần cài đặt | Tải qua TestFlight (iOS) hoặc file APK (Android) |
| **Quyền cảm biến** | Bị hạn chế (không đọc được LiDAR, rung haptic hạn chế trên iOS Safari) | Toàn quyền truy cập phần cứng sâu nhất |
| **Đo độ sâu (Depth)** | Monocular 2D (dễ nhầm bóng râm thành mép bậc) | **LiDAR mây điểm 3D (ARKit) / ARCore Depth:** Triệt tiêu hoàn toàn nhầm bóng râm |
| **Mô hình AI** | TensorFlow.js WebGL (18-22 FPS, 35-50ms) | **CoreML / TFLite GPU NPU:** Tăng lên 30-45 FPS, độ trễ < 15ms |
| **Tiêu hao năng lượng** | Khá cao do WebGL và trình duyệt tiêu tốn tài nguyên | Tối ưu hóa NPU/Metal/Vulkan, tiết kiệm thêm 40% pin |
| **Hoạt động ngầm** | Dừng khi tắt màn hình hoặc chuyển tab | Có thể chạy nền một phần (Background Location & Audio) |

---

## 2. THIẾT KẾ KIẾN TRÚC NATIVE ĐỀ XUẤT

```
+-------------------------------------------------------------------+
|               GIAO DIỆN NGƯỜI DÙNG TIẾP CẬN (UI/UX)               |
|      Flutter (Cross-platform) HOẶC SwiftUI / Jetpack Compose      |
|  - Tương thích 100% với VoiceOver (iOS) & TalkBack (Android)      |
|  - Chế độ màn hình tối tuyệt đối (OLED Pure Black Mode)           |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|               TẦNG CẢM BIẾN & THỊ GIÁC (CAMERA & NPU)             |
|                                                                   |
|  [Hệ sinh thái Apple (iOS)]         [Hệ sinh thái Android]        |
|  - AVFoundation (Camera 60 FPS)     - CameraX / NDK Camera        |
|  - ARKit + LiDAR Point Cloud         - ARCore Depth API            |
|  - CoreML + YOLOv8-Nano NPU         - TFLite + GPU/NNAPI Delegate |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                  BỘ NÃO ĐIỀU PHỐI (SHARED ENGINE)                 |
|  - Spatial Analyzer (3 Hành lang & Bounding Box Expansion Tracking)|
|  - Ground Plane 3D Mesh Analyzer (Phát hiện bậc thềm & hố ga)    |
|  - Cooldown & Hysteresis Decision Engine                          |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|               TẦNG PHẢN HỒI ÂM THANH & RUNG XÚC GIÁC              |
|  - Spatial Audio (AVAudioEngine / AAudio / Oboe 3D Audio)        |
|  - CoreHaptics (iOS Haptic Engine) / VibrationEffect (Android)    |
|  - Local Neural TTS tiếng Việt offline                            |
+-------------------------------------------------------------------+
```

---

## 3. LỘ TRÌNH TRIỂN KHAI NATIVE

1. **Giai đoạn Native MVP (4 tuần):**  
   - Viết bằng **Flutter** dùng plugin `camera`, `flutter_tflite`, và `flutter_sound`.
   - Giữ nguyên toàn bộ logic đã kiểm chứng ở bản Web (`SpatialAnalyzer`, `AlertDecisionEngine`, `NavigationEngine`).
2. **Giai đoạn Tối ưu hóa Phần cứng chuyên sâu (iOS Swift Pro):**  
   - Viết một module Swift độc quyền cho dòng iPhone Pro (iPhone 12 Pro $\to$ iPhone 16 Pro) để đọc trực tiếp dữ liệu lưới 3D từ cảm biến **LiDAR**.
   - Báo chính xác độ sâu của hố sụt mất nắp và bậc tam cấp tới từng centimet, bất chấp trời tối hay bóng râm chói chang.
