# Be My Eyes VN — Workspace Guidelines & Rules

Dự án ứng dụng dẫn đường bằng camera & thị giác máy tính thời gian thực dành cho người khiếm thị trên đường phố Việt Nam.

---

## 1. NGUYÊN TẮC BẮT BUỘC (NON-NEGOTIABLE RULES)

1. **An toàn trên hết:** 
   - Ứng dụng **tuyệt đối không bao giờ** nói "đường an toàn", "đường trống" hay các câu tương tự.
   - Luôn giữ nguyên hộp thoại điều khoản an toàn bắt buộc [`SafetyDisclaimerDialog`](file:///flutter_app/lib/ui/widgets/safety_disclaimer_dialog.dart).
2. **Lỗi phải "kêu to":** 
   - Mọi thất bại (mất tín hiệu camera, từ chối quyền, lỗi tải mô hình TFLite) phải được cảnh báo to rõ bằng giọng nói tiếng Việt và lập tức chặn chế độ dẫn đường (`PipelineStatus.failed`), tuyệt đối không âm thầm nuốt lỗi (`catch (_) {}`).
3. **Mọi ngưỡng số phải gom về một nơi:** 
   - Tất cả hằng số cấu hình (khoảng cách, tỷ lệ diện tích, thời gian cooldown, ngưỡng nhiệt độ) bắt buộc phải nằm trong [`flutter_app/lib/config/thresholds.dart`](file:///flutter_app/lib/config/thresholds.dart), có chú thích đơn vị đo và lý do khoa học rõ ràng.
4. **Trung thực về số liệu hiệu năng:** 
   - Tuyệt đối không tự bịa số FPS hay độ trễ vào tài liệu / README. Với mọi số liệu chưa có log thực địa từ thiết bị thật, luôn gắn kèm banner: *"TRẠNG THÁI SỐ LIỆU: Cần chạy trên thiết bị thật để có số liệu kiểm chứng, không tự khẳng định kết quả"*.
5. **Xử lý hoàn toàn trên thiết bị (On-Device):** 
   - Xử lý cục bộ 100% bằng TFLite, không gửi luồng hình ảnh người dùng lên máy chủ đám mây.

---

## 2. BỘ SKILLS CHUYÊN BIỆT CỦA DỰ ÁN (.agents/skills/)

Các skills sau đây đã được chuẩn hóa và đóng gói trong thư mục `.agents/skills/`:

1. **[`realtime-vision-pipeline`](file:///.agents/skills/realtime-vision-pipeline/SKILL.md):**
   - Tiền xử lý ảnh LUT YUV420 sang RGB 300x300 & Grayscale 160x120 siêu tốc (2-4ms).
   - Tối ưu hóa suy luận TFLite SSD MobileNet, Tensor buffers tái sử dụng zero-allocation, bộ tăng tốc phần cứng Android NNAPI / GPU / CPU Delegate.
   - Cơ chế Watchdog giám sát mất khung hình và tự động khóa an toàn.

2. **[`spatial-threat-analysis`](file:///.agents/skills/spatial-threat-analysis/SKILL.md):**
   - Mô hình camera Pin-hole và quy ước dấu bù góc nghiêng điện thoại (tilt angle).
   - Hồi quy tuyến tính diện tích ($R^2 \ge 0.5$, $\ge 5$ mẫu trong $\ge 0.3$s) phát hiện xe đang lao tới gần (`isApproaching`), triệt tiêu nhiễu rung lắc hộp bao và bù tốc độ bước chân.
   - Phân tích gradient luma mặt đất phát hiện bậc bước xuống và hố sụt.
   - Cân bằng điểm nguy cơ (`ThreatScore`), ưu tiên xe/người gần trước vật cản mặt đất tin cậy trung bình.

3. **[`accessibility-audio-haptics`](file:///.agents/skills/accessibility-audio-haptics/SKILL.md):**
   - Thiết kế giao diện trợ năng cao độ: tương thích VoiceOver / TalkBack, nút bấm khổng lồ OLED Pure Black.
   - Âm thanh không gian Stereo Panning theo tọa độ vật cản.
   - Ngân hàng âm thanh chuyên biệt: phân biệt tiếng lượn giảm tần số (`step_down.wav`) cho bậc bước xuống so với tiếng bíp vật cản.
   - Cơ chế chống lặp câu nói TTS tiếng Việt (cooldown $\ge 3$s, ngắt lời có ưu tiên).
   - Nhịp tim giữ liên lạc (Heartbeat haptic pulse) mỗi 12 giây im lặng.

4. **[`field-testing-benchmarking`](file:///.agents/skills/field-testing-benchmarking/SKILL.md):**
   - Chế độ Benchmark 3 phút tự động xuất CSV kèm banner thống kê trung thực.
   - Hàng đợi log hiệu năng cao $O(1)$ (`ListQueue`), tắt hoàn toàn ở chế độ thường để triệt tiêu GC churn và tối đa hóa FPS.
   - Quản lý tập trung các ngưỡng cấu hình trong `thresholds.dart`.

5. **[`ci-release-workflow`](file:///.agents/skills/ci-release-workflow/SKILL.md):**
   - Quy trình kiểm tra bắt buộc: `flutter analyze` (0 issues) và `flutter test` (100% pass) trước mỗi commit.
   - Tự động hóa build APK Android Release qua GitHub Actions và phát hành trực tiếp lên GitHub Releases.
