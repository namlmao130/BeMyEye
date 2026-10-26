# HƯỚNG DẪN CÀI ĐẶT THÀNH APP TRÊN ĐIỆN THOẠI (ANDROID & IPHONE)
**Dự án:** Trợ lý dẫn đường thời gian thực cho người khiếm thị (Be My Eyes VN)  

---

## CÁCH 1: CÀI ĐẶT TRỰC TIẾP LÀM APP TRÊN ĐIỆN THOẠI (NHANH NHẤT - 10 GIÂY)
*(Công nghệ PWA - Progressive Web App: Không cần máy tính cấu hình phức tạp, cài xong có Icon App riêng ngoài màn hình, mở chạy toàn màn hình độc lập như mọi app App Store / CH Play).*

### 1. Trên iPhone (iOS Safari)
1. Kết nối iPhone cùng Wi-Fi với máy tính, mở trình duyệt **Safari**, truy cập:  
   `https://192.168.0.36:8443` *(hoặc địa chỉ IP hiển thị khi chạy `node server.js`)*.
2. Bỏ qua cảnh báo SSL (chọn *Nâng cao* $\to$ *Tiếp tục truy cập*).
3. Bấm vào nút **Chia sẻ (Share)** ở thanh công cụ dưới cùng (biểu tượng hình ô vuông có mũi tên chỉ lên $\uparrow$).
4. Cuộn xuống và chọn **"Thêm vào MH chính" (Add to Home Screen)**.
5. Bấm nút **"Thêm" (Add)** ở góc trên bên phải.
6. **Kết quả:** Icon ứng dụng màu vàng **BeMyEyes** sẽ xuất hiện ngay trên màn hình chính của iPhone. Bấm vào icon này, app sẽ mở toàn màn hình, không còn thanh địa chỉ của Safari, chạy mượt mà và lưu offline.

### 2. Trên Android (Google Chrome)
1. Mở trình duyệt **Chrome**, truy cập link: `https://192.168.0.36:8443`.
2. Bấm vào biểu tượng **3 dấu chấm** ở góc trên bên phải.
3. Chọn **"Cài đặt ứng dụng" (Install app)** hoặc **"Thêm vào Màn hình chính" (Add to Home Screen)**.
4. Bấm **Cài đặt**.
5. **Kết quả:** Ứng dụng được cài đặt thành một App độc lập trong danh sách ứng dụng của điện thoại, hỗ trợ đầy đủ Camera, Rung (Haptic), và Định vị GPS.

---

## CÁCH 2: XUẤT FILE CÀI ĐẶT `.APK` CHO ANDROID (TỪ MÃ NGUỒN FLUTTER)

### Cách A: Tự động Build APK trên đám mây (GitHub Actions - Miễn phí)
Tôi đã cấu hình sẵn tệp tự động build [`.github/workflows/build_apk.yml`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/.github/workflows/build_apk.yml).
1. Đẩy mã nguồn dự án lên tài khoản GitHub của bạn:
   ```bash
   git init
   git add .
   git commit -m "Be My Eyes VN Release"
   git remote add origin https://github.com/[ten-cua-ban]/be-my-eye.git
   git push -u origin main
   ```
2. Trên giao diện GitHub, vào tab **Actions**: Hệ thống máy chủ đám mây của GitHub sẽ tự động biên dịch dự án Flutter thành file **`app-release.apk`**.
3. Bạn chỉ cần bấm tải file `.apk` về điện thoại và cài đặt trực tiếp, hoặc gửi qua Zalo/Google Drive cho bạn bè.

### Cách B: Build APK trực tiếp trên máy tính cá nhân
Nếu máy tính của bạn đã cài đặt Flutter SDK và Android Studio:
```bash
cd flutter_app
flutter pub get
flutter build apk --release
```
File APK thành phẩm sẽ nằm tại đường dẫn:  
`flutter_app/build/app/outputs/flutter-apk/app-release.apk`.
