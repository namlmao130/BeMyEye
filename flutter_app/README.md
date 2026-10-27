# BE MY EYES VN - FLUTTER NATIVE APPLICATION
**Trợ lý dẫn đường thời gian thực cho người khiếm thị trên đường phố Việt Nam**  
*(Phiên bản ứng dụng di động Flutter Native)*

> [!WARNING]
> **THÔNG BÁO VỀ TRẠNG THÁI HIỆN TẠI CỦA DỰ ÁN:**
> - **Bản Web (`public/`):** Đã hoàn thiện pipeline nhận diện thời gian thực qua webcam/camera trình duyệt bằng TensorFlow.js MobileNet SSD, phân tích không gian 3 hành lang và âm thanh Stereo Web Audio.
> - **Bản Flutter Native (`flutter_app/`):** Đang trong quá trình hoàn thiện kết nối luồng camera native (Nhiệm vụ 3). Khi cờ `kPipelineEnabled = false`, ứng dụng ở chế độ **"BẢN DEMO – CHƯA NHẬN DIỆN CAMERA"** và sẽ phát giọng nói cảnh báo khi bật. **Tuyệt đối không dùng bản demo để dẫn đường trên đường phố.**
> - **Hiệu năng & Kiểm chứng:** Mọi thông số về FPS, độ trễ xử lý (ms), tỷ lệ cảnh báo chính xác **chưa được đo đạc thực địa trên thiết bị Android/iOS thật**. Cần chạy trực tiếp trên máy thật và xuất dữ liệu đo (CSV) để thẩm định.

---

## 1. CẤU TRÚC DỰ ÁN FLUTTER

```
flutter_app/
├── pubspec.yaml                        # Danh sách dependencies & assets
├── android/app/src/main/AndroidManifest.xml # Quyền Camera, GPS, Rung
├── ios/Runner/Info.plist              # Quyền Camera, Location cho iOS
└── lib/
    ├── main.dart                      # Điểm khởi chạy & Theme đen OLED
    ├── config/
    │   └── thresholds.dart            # Toàn bộ ngưỡng cấu hình thuật toán, âm thanh & cờ pipeline
    ├── models/
    │   ├── detection_result.dart      # Model Bounding Box, 3 hành lang & cự ly
    │   ├── ground_hazard.dart         # Model Bậc tam cấp & Bậc bước xuống (vật cản âm)
    │   └── waypoint.dart              # Model điểm mốc dẫn đường GPS
    ├── services/
    │   ├── detector_service.dart      # TFLite Interpreter (MobileNet SSD lượng tử hóa)
    │   ├── spatial_analyzer.dart      # Phân tích 3 hành lang & tốc độ xe lao tới
    │   ├── ground_analyzer.dart       # Quét Sobel ngang & lọc 8 frames chống rung bước chân
    │   ├── alert_decision_engine.dart # Bộ não ưu tiên hiểm họa, Cooldown & Heartbeat
    │   ├── audio_haptics_service.dart # Bíp Stereo Pan, TTS tiếng Việt & Rung xúc giác
    │   ├── navigation_service.dart    # GPS làm mượt chống trôi + La bàn + Simulator
    │   └── battery_optimizer.dart     # Điều tiết FPS động theo chuyển động người dùng
    └── ui/
        ├── accessible_screen.dart     # Giao diện xúc giác 1 nút to cho người khiếm thị
        ├── developer_hud_screen.dart  # HUD kỹ thuật & Thanh công cụ Người bảo hộ
        └── widgets/
            └── safety_disclaimer_dialog.dart # Modal Điều khoản An toàn bắt buộc đọc bằng giọng nói
```

---

## 2. HƯỚNG DẪN CÀI ĐẶT & CHẠY ỨNG DỤNG

### Bước 1: Yêu cầu môi trường
- Đã cài đặt [Flutter SDK](https://flutter.dev/docs/get-started/install) phiên bản $\ge 3.0.0$.
- Android Studio với Android SDK Platform 34/36, Build-Tools và NDK.

### Bước 2: Tải gói phụ thuộc (Dependencies)
Mở terminal tại thư mục `flutter_app`:
```bash
cd flutter_app
flutter pub get
```

### Bước 3: Chuẩn bị tệp mô hình và âm thanh (Assets)
Đảm bảo các tệp sau đã có trong thư mục assets:
1. `assets/models/mobilenet_ssd.tflite`
2. `assets/models/labelmap.txt` (Từ điển 91 nhãn COCO)
3. `assets/sounds/beep.wav` (Tệp âm thanh bíp chuẩn hóa)

### Bước 4: Chạy trên thiết bị thật
Cắm điện thoại vào máy tính qua cáp USB và chạy lệnh:
```bash
# Kiểm tra thiết bị kết nối
flutter devices

# Chạy ứng dụng trên máy Android / iOS
flutter run -d <device-id>
```

---

## 3. CÁC NGUYÊN TẮC AN TOÀN BẮT BUỘC
1. **Tuyệt đối không thay thế gậy trắng:** Ứng dụng chỉ là giác quan phụ trợ tầm xa và tầm cao. Người khiếm thị bắt buộc phải luôn sử dụng gậy trắng khi di chuyển.
2. **Không bao giờ khẳng định "đường an toàn":** Ứng dụng im lặng chỉ biểu thị hệ thống chưa nhận diện thấy vật thể trong tầm nhìn cảm biến, tuyệt đối không đảm bảo đường đi hoàn toàn không có chướng ngại.
3. **Cơ chế ngắt an toàn tuyệt đối (Safety Preemption):** Bất cứ khi nào camera phát hiện xe máy lao tới hoặc bậc bước xuống, câu chỉ dẫn GPS lập tức bị ngắt.
4. **Nhịp đập giữ liên lạc (Heartbeat Haptic Pulse):** Khẽ rung 35ms mỗi 12 giây im lặng để người dùng yên tâm ứng dụng vẫn đang hoạt động bình thường.
5. **Xử lý on-device 100%:** Toàn bộ dữ liệu camera và cảm biến được xử lý cục bộ trên điện thoại, không truyền hình ảnh lên máy chủ đám mây nhằm đảm bảo quyền riêng tư.
