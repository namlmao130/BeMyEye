# BE MY EYES VN - FLUTTER NATIVE APPLICATION
**Trợ lý dẫn đường thời gian thực cho người khiếm thị trên đường phố Việt Nam**  
*(Phiên bản ứng dụng di động Flutter Native)*

> [!NOTE]
> **TIẾN ĐỘ & TRẠNG THÁI HIỆN TẠI (NV3 ĐÃ HOÀN THÀNH):**
> - **Luồng Camera Native (`kPipelineEnabled = true`):** Đã kết nối luồng Camera thời gian thực (`camera` package, YUV420), tiền xử lý song song trong Isolate (YUV420 → RGB 300×300 cho SSD MobileNet và → Luma 160×120 cho phân tích bậc thềm), điều tiết khung hình bằng `BatteryThermalOptimizer`, tự động bỏ khung hình trễ (Frame-dropping, không xếp hàng).
> - **Mô hình On-device & Tăng tốc phần cứng:** Nạp mô hình SSD MobileNet với 91 nhãn COCO chuẩn, tự động chọn Hardware Delegate (`GPU Delegate` → `NNAPI` → `CPU đa luồng`). Báo lỗi to bằng giọng nói và khóa dẫn đường nếu không nạp được mô hình.
> - **Giữ màn hình sáng (`wakelock_plus`) & Giới hạn nền:** Ứng dụng tự động giữ màn hình luôn sáng khi đang dẫn đường để duy trì luồng camera liên tục. Do chính sách bảo mật của Android 9+ hạn chế nghiêm ngặt việc truy cập camera khi màn hình tắt/ứng dụng chạy ngầm, điện thoại được thiết kế để đeo trước ngực với màn hình sáng ở giao diện đen thuần OLED (`#000000`) nhằm tối thiểu hóa tiêu hao pin.
> - **Công cụ đo đạc thực địa (CSV Logger):** HUD kỹ thuật cung cấp công cụ ghi log FPS, độ trễ từng chặng (`t_preprocess`, `t_inference`, `t_analysis`, `t_total`), mối đe dọa chính và nút một chạm sao chép toàn bộ CSV vào Clipboard để người kiểm thử gửi lại số liệu thẩm định thực tế.
> - **Mục tiêu hiệu năng cần đo thực địa:** Đích nhắm $\ge 15$ FPS và độ trễ $< 300$ ms trên thiết bị tầm trung. Hiện tại các số liệu này **chưa có số đo thực tế từ thiết bị phần cứng**, cần chạy APK trên máy thật và xuất CSV để kiểm chứng.

---

## 1. CẤU TRÚC DỰ ÁN FLUTTER

```
flutter_app/
├── pubspec.yaml                        # Danh sách dependencies (camera, tflite_flutter, wakelock_plus,...)
├── android/app/src/main/AndroidManifest.xml # Quyền Camera, GPS, Rung, WakeLock
├── ios/Runner/Info.plist              # Quyền Camera, Location cho iOS
└── lib/
    ├── main.dart                      # Điểm khởi chạy & Theme đen OLED
    ├── config/
    │   └── thresholds.dart            # Toàn bộ ngưỡng cấu hình thuật toán, âm thanh & cờ kPipelineEnabled
    ├── models/
    │   ├── detection_result.dart      # Model Bounding Box, 3 hành lang & cự ly
    │   ├── ground_hazard.dart         # Model Bậc tam cấp & Bậc bước xuống (vật cản âm)
    │   └── waypoint.dart              # Model điểm mốc dẫn đường GPS
    ├── services/
    │   ├── detector_service.dart      # TFLite Interpreter (MobileNet SSD 91 nhãn, GPU/NNAPI/CPU Fallback)
    │   ├── camera_pipeline_service.dart # Điều phối luồng camera, Isolate và chuỗi xử lý
    │   ├── image_preprocessor.dart    # Biến đổi YUV420 sang RGB 300x300 & Luma 160x120 trong Isolate
    │   ├── csv_logger.dart            # Ghi nhận log CSV đo đạc thực địa (FPS, Latency Breakdown)
    │   ├── spatial_analyzer.dart      # Phân tích 3 hành lang & tốc độ xe lao tới
    │   ├── ground_analyzer.dart       # Quét Sobel ngang & lọc 8 frames chống rung bước chân
    │   ├── alert_decision_engine.dart # Bộ não ưu tiên hiểm họa, Cooldown & Heartbeat
    │   ├── audio_haptics_service.dart # Bíp Stereo Pan, TTS tiếng Việt & Rung xúc giác
    │   ├── navigation_service.dart    # GPS làm mượt chống trôi + La bàn + Simulator
    │   └── battery_optimizer.dart     # Điều tiết FPS động theo chuyển động người dùng
    └── ui/
        ├── accessible_screen.dart     # Giao diện xúc giác 1 nút to cho người khiếm thị
        ├── developer_hud_screen.dart  # HUD kỹ thuật, CameraPreview, vẽ Bbox & Xuất CSV
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

### Bước 4: Chạy trên thiết bị thật & Lấy dữ liệu CSV
Cắm điện thoại vào máy tính qua cáp USB và chạy lệnh:
```bash
flutter run -d <device-id>
```
Khi đang chạy:
1. Bấm nút **"Màn hình Kỹ thuật & Đo đạc"**.
2. Xem camera trực tiếp, Bounding Box và bảng thông số độ trễ từng bước.
3. Bấm **"Sao chép CSV"** để dán toàn bộ dữ liệu đo (thời điểm, FPS, độ trễ tiền xử lý, suy luận, phân tích) gửi lại cho nhóm kỹ sư.

---

## 3. CÁC NGUYÊN TẮC AN TOÀN BẮT BUỘC
1. **Tuyệt đối không thay thế gậy trắng:** Ứng dụng chỉ là giác quan phụ trợ tầm xa và tầm cao. Người khiếm thị bắt buộc phải luôn sử dụng gậy trắng khi di chuyển.
2. **Không bao giờ khẳng định "đường an toàn":** Ứng dụng im lặng chỉ biểu thị hệ thống chưa nhận diện thấy vật thể trong tầm nhìn cảm biến, tuyệt đối không đảm bảo đường đi hoàn toàn không có chướng ngại.
3. **Cơ chế ngắt an toàn tuyệt đối (Safety Preemption):** Bất cứ khi nào camera phát hiện xe máy lao tới hoặc bậc bước xuống, câu chỉ dẫn GPS lập tức bị ngắt.
4. **Nhịp đập giữ liên lạc (Heartbeat Haptic Pulse):** Khẽ rung 35ms mỗi 12 giây im lặng để người dùng yên tâm ứng dụng vẫn đang hoạt động bình thường.
5. **Xử lý on-device 100%:** Toàn bộ dữ liệu camera và cảm biến được xử lý cục bộ trên điện thoại, không truyền hình ảnh lên máy chủ đám mây nhằm đảm bảo quyền riêng tư.

---

## 4. QUYỀN HẠN HỆ THỐNG & BẢO MẬT (NV10)

### 4.1 Danh sách quyền tối giản trong AndroidManifest.xml
Ứng dụng chỉ yêu cầu các quyền thực sự cần thiết cho tính năng hỗ trợ người khiếm thị:
- `android.permission.CAMERA`: Luồng khung hình thời gian thực phục vụ thị giác máy tính on-device.
- `android.permission.VIBRATE`: Phản hồi rung xúc giác khi phát hiện chướng ngại vật nguy cấp.
- `android.permission.ACCESS_FINE_LOCATION` & `ACCESS_COARSE_LOCATION`: Định vị GPS ngoài trời cho dẫn đường từng bước.
- `android.permission.INTERNET` & `ACCESS_NETWORK_STATE`: Truy vấn tuyến đường đi bộ OSRM (OpenStreetMap).
- `android.permission.WAKE_LOCK`: Giữ màn hình luôn sáng ở nền đen OLED khi điện thoại gắn ngực.
- `android.permission.FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CAMERA`, `FOREGROUND_SERVICE_LOCATION`: Đảm bảo dịch vụ thị giác và GPS hoạt động ổn định.

Ứng dụng **KHÔNG** yêu cầu quyền ghi âm microphone (`RECORD_AUDIO`), không đọc danh bạ, không truy cập thẻ nhớ ngoài hay bất kỳ quyền nhạy cảm không cần thiết nào.

### 4.2 Hướng dẫn Ký phát hành (Release Signing) an toàn
Tuyệt đối không commit tệp chứng chỉ (`.jks`, `.keystore`, `.pem`, `.key`) hoặc thông tin mật khẩu lên kho mã nguồn Git.
Để ký bản APK Release cục bộ:
1. Tạo tệp keystore cục bộ ngoài repo:
   ```bash
   keytool -genkey -v -keystore ~/bemyeye-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bemyeye
   ```
2. Tạo tệp `flutter_app/android/key.properties` (đã được cấu hình trong `.gitignore`):
   ```properties
   storePassword=<mật_khẩu_keystore>
   keyPassword=<mật_khẩu_key>
   keyAlias=bemyeye
   storeFile=<đường_dẫn_tuyệt_đối_đến_file_jks>
   ```
