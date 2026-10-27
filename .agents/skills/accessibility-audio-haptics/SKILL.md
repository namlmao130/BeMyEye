---
name: accessibility-audio-haptics
description: >-
  Sử dụng skill này khi thiết kế, triển khai hoặc kiểm thử các thành phần trợ năng (Accessibility)
  cho người khiếm thị: âm thanh không gian Stereo Panning, haptics xúc giác, phân biệt âm thanh bậc bước xuống,
  cơ chế chống lặp giọng nói TTS tiếng Việt, nhịp tim giữ liên lạc (heartbeat) và tuân thủ TalkBack/VoiceOver.
---

# Accessibility, Audio Panning & Haptic Feedback Skill

Skill này hướng dẫn xây dựng trải nghiệm giao diện người dùng và hệ thống phản hồi đa giác quan (Âm thanh 3D, Rung xúc giác, Giọng nói đọc màn hình) dành riêng cho người khiếm thị.

---

## 1. Nguyên tắc Trợ năng Cốt lõi (Accessibility First)

Tệp nguồn: [`flutter_app/lib/ui/accessible_screen.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/ui/accessible_screen.dart)

1. **Giao diện OLED Pure Black (`#000000`):**
   - Tiết kiệm tối đa điện năng cho màn hình AMOLED/OLED khi người dùng đeo máy trước ngực đi bộ nhiều giờ ngoài trời.
2. **Nút bấm khổng lồ (Giant Tactile Buttons):**
   - Chiếm trọn trung tâm màn hình (chiều cao $\ge 220\text{px}$), viền dày $4\text{px}$, tương phản cực mạnh (Vàng `#FACC15` trên Nền Đen).
   - Dễ dàng định vị bằng một ngón tay mà không cần nhìn vào màn hình.
3. **Hỗ trợ tuyệt đối Trình đọc màn hình (TalkBack & VoiceOver):**
   - Bọc toàn bộ widget quan trọng bằng `Semantics(liveRegion: true, button: true, label: '...')`.
   - Khi có lỗi mô hình hoặc lỗi camera: nút bấm chuyển sang trạng thái bị vô hiệu hóa (`enabled: false`) với nhãn thông báo lỗi rõ ràng.
4. **Hộp thoại Điều khoản An toàn Bắt buộc:**
   - [`SafetyDisclaimerDialog`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/ui/widgets/safety_disclaimer_dialog.dart) tự động hiển thị lúc mở app và đọc to bằng TTS: *"Ứng dụng chỉ có tính năng hỗ trợ, không thể thay thế gậy dò đường hay chó dẫn đường..."*.
   - Tuyệt đối không bao giờ cho phép bỏ qua điều khoản này.

---

## 2. Hệ thống Âm thanh Định hướng Stereo Panning & Phân biệt Vật cản

Tệp nguồn: [`flutter_app/lib/services/audio_haptics_service.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/audio_haptics_service.dart)

### 2.1. Phân bố không gian Stereo Panning
- Tọa độ ngang của vật cản $x_{center} \in [0.0, 1.0]$ được ánh xạ sang giá trị Stereo Pan:
  $$Pan = (x_{center} - 0.5) \times 2.0 \in [-1.0, 1.0]$$
  - $Pan < -0.25$: Lệch hẳn tai trái.
  - $-0.25 \le Pan \le 0.25$: Chính giữa trán.
  - $Pan > 0.25$: Lệch hẳn tai phải.

### 2.2. Ngân hàng âm thanh chuyên biệt & Tôn trọng Pitch / Duration
- **Bậc bước xuống / Hố sâu (`step_down.wav`):**
  - Âm lượn trượt tần số giảm dần (Frequency glide từ $420\text{Hz} \to 220\text{Hz}$) trong $280\text{ms}$.
  - Giúp não bộ người khiếm thị nhận diện ngay lập tức cảm giác "hụt chân / đi xuống" mà không bị nhầm với vật cản va chạm phía trước.
- **Vật cản thường (`beep_low.wav`, `beep_high.wav`):**
  - Cao độ (pitch) và thời lượng (durationMs) được điều chỉnh linh hoạt qua `AudioPlayer.setPlaybackRate()` và `setBalance()`.

---

## 3. Khắc phục Lỗi Lặp Giọng nói TTS Tiếng Việt

Tệp nguồn: [`flutter_app/lib/services/alert_decision_engine.dart`](file:///c:/Users/DELL/Downloads/Be%20my%20eye/flutter_app/lib/services/alert_decision_engine.dart)

### 3.1. Nguyên nhân lỗi gốc
Trước đây, luồng cảnh báo nguy cấp gọi âm thanh mỗi $240\text{ms}$. Nếu gọi `speakVietnamese(force: true)` liên tục, lệnh `_tts.stop()` sẽ bị kích hoạt mỗi 240ms, làm câu nói tiếng Việt bị ngắt cụt chữ liên tục (ví dụ: *"Xe m... Xe m... Xe..."*).

### 3.2. Thuật toán phân cấp phản hồi
1. **Âm bíp và Rung xúc giác:** Tiếp tục phát lặp theo chu kỳ ($240\text{ms}$ khi nguy cấp) để giữ cảnh giác cao độ.
2. **Giọng nói đọc tên vật cản (TTS):**
   - Áp dụng thời gian chờ (cooldown) **tối thiểu 3.0 giây** (`kSpeechCooldownSec`) cho cùng một loại mối đe dọa (theo ID hoặc Category).
   - **Quy tắc ngắt lời (Preemption):** Chỉ ngắt câu đang nói khi xuất hiện một mối đe dọa MỚI có điểm ưu tiên vượt trội hơn hẳn:
     $$Priority_{new} - Priority_{current} \ge 40$$
     *(Ví dụ: Đang nói "Người đi bộ phía trước" mà đột ngột có "Xe máy đang lao tới" thì ngắt lời ngay lập tức).*

---

## 4. Nhịp đập giữ liên lạc (Heartbeat Haptic Pulse)

- Khi đường đi hoàn toàn trống và ứng dụng im lặng liên tục trong **12.0 giây** (`kHeartbeatIntervalSec`):
  - Thiết bị tự động phát một xung rung siêu nhẹ **35ms** (`kHeartbeatDurationMs`).
  - Ý nghĩa nhân văn: Báo hiệu cho người dùng biết điện thoại vẫn đang hoạt động tốt, camera vẫn đang canh chừng phía trước, tránh cảm giác bất an "liệu app có bị treo không".

---

## 5. Các bước kiểm tra & Xác thực
1. Kiểm tra thuật toán chống lặp giọng nói:
   ```bash
   flutter test test/nv4_test.dart
   ```
2. Kiểm tra phân biệt âm thanh bậc bước xuống và stereo panning:
   ```bash
   flutter test test/nv12_item6_audio_test.dart
   ```
