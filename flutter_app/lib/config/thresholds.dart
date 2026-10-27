/// thresholds.dart
/// TẬP HỢP TOÀN BỘ NGƯỠNG CẤU HÌNH CỦA HỆ THỐNG DẪN ĐƯỜNG BE MY EYES VN
/// Tất cả các hằng số thuật toán, âm thanh, phân tích không gian và thị giác
/// đều phải được định nghĩa tại đây với đơn vị và lý do rõ ràng.

// ============================================================================
// 1. CỜ TRẠNG THÁI HỆ THỐNG
// ============================================================================

/// Cờ kích hoạt luồng camera thực tế.
/// Đặt [false] khi đang ở bản Demo / Mockup (chưa có luồng Camera thật).
/// Sẽ được chuyển sang [true] khi hoàn thành Nhiệm vụ 3 (nối Camera Stream).
bool kPipelineEnabled = false;

// ============================================================================
// 2. NGƯỠNG PHÂN TÍCH KHÔNG GIAN (SPATIAL ANALYZER)
// ============================================================================

/// Ranh giới hành lang Trái (tỷ lệ 0.0 -> 1.0 theo chiều rộng ảnh)
/// Vật thể có tâm X < 0.35 được xếp vào hành lang bên Trái.
double kLeftBoundary = 0.35;

/// Ranh giới hành lang Phải (tỷ lệ 0.0 -> 1.0 theo chiều rộng ảnh)
/// Vật thể có tâm X > 0.65 được xếp vào hành lang bên Phải.
double kRightBoundary = 0.65;

/// Ngưỡng chân vật thể (bottom Y) để xếp vào cự ly Gần (1.5m - 3.0m).
/// Đơn vị: Tỷ lệ vị trí trục Y từ trên xuống (0.0 -> 1.0).
double kNearBottomY = 0.65;

/// Ngưỡng chân vật thể (bottom Y) để xếp vào cự ly Nguy cấp (< 1.5m).
/// Đơn vị: Tỷ lệ vị trí trục Y từ trên xuống (0.0 -> 1.0).
double kCriticalBottomY = 0.82;

/// Ngưỡng tỷ lệ diện tích khung bao (Bounding Box / Khung hình) cho cự ly Gần.
/// Đơn vị: Tỷ lệ diện tích (0.0 -> 1.0).
double kNearAreaRatio = 0.08;

/// Ngưỡng tỷ lệ diện tích khung bao cho cự ly Nguy cấp.
/// Đơn vị: Tỷ lệ diện tích (0.0 -> 1.0).
double kCriticalAreaRatio = 0.22;

/// Ngưỡng tốc độ tăng diện tích tương đối (dArea / area mỗi giây) để coi là đang lao tới (Approaching).
/// Đơn vị: Tỷ lệ / giây (1/s).
double kApproachThreshold = 0.15;

/// Thời gian tối đa giữ lại track vật thể nếu không phát hiện lại trong các frame tiếp theo.
/// Đơn vị: Mili-giây (ms).
int kTrackExpirationMs = 600;

// ============================================================================
// 3. NGƯỠNG PHÂN TÍCH MẶT ĐẤT (GROUND PLANE ANALYZER)
// ============================================================================

/// Độ phân giải ảnh xám dùng để phân tích bậc thềm / lề đường
int kGroundProcWidth = 160;
int kGroundProcHeight = 120;

/// Đường chân trời giả định (bỏ qua 40% phần trên khung hình vì là bầu trời/thân người)
double kGroundHorizonY = 0.40;

/// Chiều rộng liên tục tối thiểu của một mép bậc so với chiều rộng khung hình
double kMinStepWidthRatio = 0.35;

/// Ngưỡng đạo hàm Sobel Gy để xác định cạnh ngang
int kEdgeThreshold = 38;

/// Số khung hình trong cửa sổ trượt lọc nhiễu thời gian (chống rung bước chân)
int kGroundHistorySize = 8;

// ============================================================================
// 4. NGƯỠNG ÂM THANH & CẢNH BÁO (AUDIO & ALERT ENGINE)
// ============================================================================

/// Chu kỳ bíp cảnh báo cự ly Nguy cấp (< 1.5m hoặc xe lao tới)
/// Đơn vị: Mili-giây (ms). ~4 lần/giây để phản xạ kịp thời.
int kBeepIntervalCriticalMs = 240;

/// Chu kỳ bíp cảnh báo cự ly Gần (1.5m - 3.0m)
/// Đơn vị: Mili-giây (ms). ~1.4 lần/giây.
int kBeepIntervalNearMs = 700;

/// Chu kỳ bíp cảnh báo cự ly Xa (> 3.0m)
/// Đơn vị: Mili-giây (ms). 2.2 giây/lần để chống mỏi thính giác trên phố đông.
int kBeepIntervalFarMs = 2200;

/// Thời gian giãn cách tối thiểu giữa 2 lần phát giọng nói TTS cùng loại
/// Đơn vị: Mili-giây (ms).
int kSpeechCooldownMs = 3000;

/// Thời gian im lặng tối đa trước khi phát nhịp đập xúc giác (Heartbeat) trấn an người dùng
/// Đơn vị: Mili-giây (ms). 12 giây im lặng sẽ khẽ rung 35ms.
int kHeartbeatIntervalMs = 12000;

/// Thời lượng rung nhịp đập xúc giác (Heartbeat)
/// Đơn vị: Mili-giây (ms). Rung siêu nhẹ để không gây giật mình.
int kHeartbeatDurationMs = 35;

// ============================================================================
// 5. NGƯỠNG MÔ HÌNH NHẬN DIỆN (DETECTOR)
// ============================================================================

/// Ngưỡng độ tin cậy tối thiểu để giữ lại dự đoán từ mô hình MobileNet SSD
/// Đơn vị: Xác suất (0.0 -> 1.0).
double kDefaultConfidenceThreshold = 0.45;

// ============================================================================
// 6. ĐIỀU TIẾT NĂNG LƯỢNG & NHIỆT ĐỘ (BATTERY / THERMAL)
// ============================================================================

/// Ngưỡng tốc độ đi bộ để phân biệt đứng yên vs đang bước đi
/// Đơn vị: Mét/giây (m/s). Dưới 0.25 m/s (~0.9 km/h) coi là đứng yên.
double kStaticSpeedThreshold = 0.25;

/// Số khung hình đứng yên liên tiếp trước khi chuyển sang trạng thái 'standing'
int kStaticFramesThreshold = 6;

/// Tốc độ khung hình mục tiêu khi bước đi
int kFpsWalking = 22;

/// Tốc độ khung hình mục tiêu khi đứng yên (hạ FPS để hạ nhiệt và tiết kiệm pin)
int kFpsStanding = 10;
