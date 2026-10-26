# BE MY EYES VN - FLUTTER NATIVE APPLICATION
**Trợ lý dẫn đường thời gian thực cho người khiếm thị trên đường phố Việt Nam**  
*(Phiên bản chuyển đổi Native từ Web MVP đã qua kiểm chứng thực địa)*

---

## 1. CẤU TRÚC DỰ ÁN FLUTTER

```
flutter_app/
├── pubspec.yaml                        # Danh sách dependencies & assets
├── android/app/src/main/AndroidManifest.xml # Quyền Camera, GPS, Rung
├── ios/Runner/Info.plist              # Quyền Camera, Location cho iOS
└── lib/
    ├── main.dart                      # Điểm khởi chạy & Theme đen OLED
    ├── models/
    │   ├── detection_result.dart      # Model Bounding Box, 3 hành lang & cự ly
    │   ├── ground_hazard.dart         # Model Bậc tam cấp & Bậc bước xuống (vật cản âm)
    │   └── waypoint.dart              # Model điểm mốc dẫn đường GPS
    ├── services/
    │   ├── detector_service.dart      # TFLite Interpreter (YOLO / MobileNet GPU)
    │   ├── spatial_analyzer.dart      # Phân tích 3 hành lang & tốc độ xe lao tới
    │   ├── ground_analyzer.dart       # Quét Sobel ngang & lọc 8 frames chống rung bước chân
    │   ├── alert_decision_engine.dart # Bộ não ưu tiên hiểm họa, Cooldown & Heartbeat
    │   ├── audio_haptics_service.dart # Bíp Stereo Pan, TTS tiếng Việt & Rung xúc giác
    │   ├── navigation_service.dart    # GPS làm mượt chống trôi + La bàn + Simulator
    │   └── battery_optimizer.dart     # Điều tiết FPS động (10 FPS đứng yên / 22 FPS bước đi)
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
- Android Studio (để chạy máy Android) hoặc Xcode trên macOS (để chạy iPhone).

### Bước 2: Tải gói phụ thuộc (Dependencies)
Mở terminal tại thư mục `flutter_app`:
```bash
cd flutter_app
flutter pub get
```

### Bước 3: Chuẩn bị tệp mô hình và âm thanh (Assets)
Tạo 2 thư mục sau và đặt file vào:
1. `assets/models/mobilenet_ssd.tflite` *(hoặc `yolov8n.tflite`)*
2. `assets/sounds/beep.wav` *(tệp âm thanh bíp ngắn 60ms)*

### Bước 4: Chạy trên thiết bị thật
Cắm điện thoại vào máy tính qua cáp USB và chạy lệnh:
```bash
# Kiểm tra thiết bị kết nối
flutter devices

# Chạy ứng dụng trên máy Android / iOS
flutter run -d <device-id>
```

---

## 3. CÁC NGUYÊN TẮC AN TOÀN ĐÃ ĐƯỢC ĐÓNG GÓI VÀO CODE NATIVE
1. **Tuyệt đối không thay thế gậy trắng:** Ứng dụng chỉ là giác quan phụ trợ tầm xa và tầm cao.
2. **Cơ chế ngắt an toàn tuyệt đối (Safety Preemption):** Bất cứ khi nào camera phát hiện xe máy lao tới hoặc bậc bước xuống, câu chỉ dẫn GPS lập tức bị ngắt trong $< 60$ms.
3. **Nhịp đập giữ liên lạc (Heartbeat Haptic Pulse):** Khẽ rung 35ms mỗi 12 giây im lặng để người dùng yên tâm app vẫn đang trông chừng.
4. **Tối ưu năng lượng:** Nền đen OLED tiết kiệm $50\%$ pin; tự hạ xuống 10 FPS khi đứng yên và tăng lên 22 FPS khi bước đi.
