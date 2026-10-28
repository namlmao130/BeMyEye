# Be My Eyes VN

Ứng dụng Flutter hỗ trợ người khiếm thị nhận biết vật cản theo thời gian thực.
Camera, mô hình TFLite, âm thanh định hướng và rung đều chạy trên thiết bị.

> Ứng dụng chỉ là công cụ hỗ trợ. Không thay thế gậy trắng, kỹ năng định hướng,
> người dẫn đường hoặc việc quan sát giao thông thực tế.

## Yêu cầu

- Flutter 3.47.8 / Dart 3.13.7
- Android 8.0 (API 26) trở lên
- Thiết bị thật có camera; nên dùng tai nghe truyền xương hoặc loa mở

## Chạy và kiểm tra

```bash
cd flutter_app
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter run
```

Mô hình và âm thanh phải nằm trong:

- `assets/models/mobilenet_ssd.tflite`
- `assets/models/labelmap.txt`
- `assets/sounds/beep.wav`

## Dẫn đường đi bộ

Không dùng máy chủ OSRM demo mặc định vì cấu hình profile trên máy chủ có thể
không phải dữ liệu đi bộ. Hãy cung cấp endpoint HTTPS đã dựng với profile đi bộ:

```bash
flutter run \
  --dart-define=OSRM_FOOT_API_BASE=https://routing.example.com/route/v1/foot
```

Nếu chưa cấu hình endpoint, nhận diện vật cản vẫn hoạt động nhưng dẫn đường trực
tuyến sẽ bị khóa và thông báo rõ bằng giọng nói.

## Script kiểm thử ảnh thật

Các gói Python ở thư mục gốc chỉ phục vụ `scripts/test_real_model_bus.py`:

```bash
python -m pip install -r requirements.txt
python scripts/test_real_model_bus.py
```

Nên dùng CPython 3.11-3.13 vì TensorFlow chưa có wheel Windows cho Python 3.15.

## CI

Workflow `.github/workflows/build_apk.yml` kiểm tra format, analyze, unit test và
build APK debug. Không tự sửa mã, không bỏ qua test và không ghi ngược log lỗi
vào repository.
