---
name: ci-release-workflow
description: >-
  Sử dụng skill này khi thực hiện quy trình kiểm tra chất lượng mã nguồn (lint/analyze),
  chạy test tự động, cấu hình GitHub Actions CI/CD và đóng gói phát hành APK Android cho ứng dụng Be My Eyes VN.
---

# CI/CD, Automated Testing & APK Release Workflow Skill

Skill này hướng dẫn quy trình kiểm thử tự động, chuẩn hóa commit Git và tự động hóa phát hành bản dựng APK cho dự án.

---

## 1. Quy trình Kiểm thử Bắt buộc Trước Commit

Trước khi tạo bất kỳ commit nào hoặc mở Pull Request, bắt buộc phải vượt qua 2 bước kiểm tra sau:

```bash
cd flutter_app
flutter analyze
flutter test
```

- **`flutter analyze`:** Phải đạt kết quả `No issues found!` (0 error, 0 warning).
- **`flutter test`:** Phải vượt qua 100% các bộ unit test và integration test. Nếu có test thất bại, bắt buộc phải điều tra sửa lỗi tận gốc thay vì sửa điều kiện test giả tạo.

---

## 2. Tiêu chuẩn Commit Message (Conventional Commits Tiếng Việt)

Mỗi commit đại diện cho một bước thay đổi độc lập, rõ ràng:
- `feat: ...` - Tính năng mới (ví dụ: `feat: tich hop ban do OSRM foot profile`).
- `fix: ...` - Sửa lỗi an toàn hoặc logic (ví dụ: `fix: lech nhan COCO kLabelOffset va chong lap giong noi`).
- `perf: ...` - Tối ưu hóa hiệu năng, FPS, bộ nhớ (ví dụ: `perf: tien xu ly LUT, Android NNAPI va tat CSV log che do thuong`).
- `refactor: ...` - Tái cấu trúc mã nguồn mà không đổi hành vi (ví dụ: `refactor: loai bo thanh cong cu Nguoi bao ho di kem`).
- `docs: ...` - Cập nhật tài liệu, README, thêm banner số liệu.

---

## 3. Quy trình Tự động hóa CI/CD với GitHub Actions

Tệp cấu hình: [`.github/workflows/build_apk.yml`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/.github/workflows/build_apk.yml)

### 3.1. Kích hoạt (Triggers)
Pipeline tự động kích hoạt khi:
1. Push commit lên nhánh `main`.
2. Tạo và push tag phiên bản mới (`v*.*.*`).
3. Kích hoạt thủ công từ giao diện (`workflow_dispatch`).

### 3.2. Các bước thực thi tự động của Workflow
1. **Set up Java JDK 17 & Flutter SDK:** Tự động cài đặt môi trường ổn định.
2. **Flutter Analyze (Code Quality Check):** Kiểm tra chuẩn mã nguồn nghiêm ngặt.
3. **Run Flutter Unit Tests:** Chạy toàn bộ test suites trong thư mục `flutter_app/test/`.
4. **Build Android APK Release:**
   ```bash
   flutter build apk --release --no-tree-shake-icons
   ```
5. **Đóng gói & Phát hành GitHub Release:**
   - Đổi tên tệp thành `BeMyEyes-VN-latest.apk`.
   - Nếu là tag phiên bản (ví dụ `v1.2.1`), tự động tạo bản phát hành GitHub Release kèm link tải trực tiếp cho người dùng.

---

## 4. Cách thức Kiểm tra Trạng thái Build từ Dòng lệnh
Nếu máy phát triển không có sẵn môi trường Android SDK đầy đủ, có thể theo dõi tiến trình build trực tiếp qua GitHub REST API:

```python
import urllib.request, json
runs = json.loads(urllib.request.urlopen('https://api.github.com/repos/namlmao130/BeMyEye/actions/runs?per_page=1').read())['workflow_runs']
print(runs[0]['name'], runs[0]['status'], runs[0]['conclusion'])
```
