/// thresholds.dart
/// TẬP HỢP TOÀN BỘ NGƯỠNG CẤU HÌNH CỦA HỆ THỐNG DẪN ĐƯỜNG BE MY EYES VN
/// Tất cả các hằng số thuật toán, âm thanh, phân tích không gian và thị giác
/// đều phải được định nghĩa tại đây với đơn vị và lý do rõ ràng.

// ============================================================================
// 1. CỜ TRẠNG THÁI HỆ THỐNG
// ============================================================================

/// Cờ kích hoạt luồng camera thực tế.
/// Đặt [true] khi hoàn thành Nhiệm vụ 3 (nối Camera Stream).
bool kPipelineEnabled = true;

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

/// Chiều cao đeo điện thoại mặc định ngang ngực (mét).
double kDefaultMountHeightMeters = 1.35;

/// Góc nghiêng ngực hiệu chuẩn ban đầu (radian).
double kCalibratedNeutralTiltRad = 0.0;

/// Hệ số bù trừ góc nghiêng điện thoại cho ngưỡng bottomY.
double kTiltCompensationFactor = 0.35;

/// Danh sách các lớp phương tiện/vật thể có kích thước lớn (chiếm diện tích lớn dù ở xa).
const Set<String> kLargeVehicleClasses = {'bus', 'truck', 'train'};

/// Ngưỡng chân vật thể lớn cho cự ly Gần (1.5m - 3.0m).
double kLargeVehicleNearBottomY = 0.68;

/// Ngưỡng chân vật thể lớn cho cự ly Nguy cấp (< 1.5m).
double kLargeVehicleCriticalBottomY = 0.84;

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

/// Số lượng chuyển đổi cạnh tối đa trong 1 hàng (quá số này coi là vạch qua đường / gạch lát)
int kMaxCrosswalkTransitions = 4;

/// Tỷ lệ tính nhất quán bước sáng/tối dọc theo mép bậc (0.0 -> 1.0)
double kStepConsistencyRatio = 0.70;

/// Số khung hình trùng khớp tối thiểu để xác nhận bậc mức tin cậy cao (High Confidence)
int kGroundHighConfidenceHits = 5;

/// Số khung hình trùng khớp tối thiểu để xác nhận bậc mức tin cậy trung bình (Medium Confidence)
int kGroundMediumConfidenceHits = 3;

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

/// Ngưỡng pin yếu cần kích hoạt chế độ tiết kiệm năng lượng
/// Đơn vị: Phần trăm (%) (pin < 20% thì kích hoạt).
int kLowBatteryPercent = 20;

/// Tốc độ khung hình mục tiêu khi pin yếu (< 20%)
int kFpsLowBattery = 10;

/// Chu kỳ tối thiểu giữa các lần phân tích mặt đất khi pin yếu hoặc quá nhiệt
/// Đơn vị: Mili-giây (ms). Giãn chu kỳ còn 1 lần/giây (1000ms) để giảm tải vi xử lý.
int kGroundIntervalLowBatteryMs = 1000;

/// Ngưỡng mã trạng thái nhiệt độ bắt đầu throttling nghiêm trọng của Android
/// Android PowerManager: THERMAL_STATUS_SEVERE = 3, CRITICAL = 4, EMERGENCY = 5, SHUTDOWN = 6
int kThermalStatusSevere = 3;

/// Tốc độ khung hình mục tiêu khi thiết bị bị quá nhiệt (Thermal Throttling)
int kFpsThermalThrottling = 8;

/// Thời gian giãn cách tối thiểu giữa 2 lần phát cảnh báo giọng nói về quá nhiệt
/// Đơn vị: Mili-giây (ms). 15 giây/lần để tránh nói liên tục.
int kThermalWarningCooldownMs = 15000;

// ============================================================================
// 7. NGƯỠNG DẪN ĐƯỜNG GPS & ĐI BỘ OSRM (NAVIGATION)
// ============================================================================

/// Bán kính đạt mốc dẫn đường (mét). Dưới 6 mét coi như đã chạm điểm mốc.
double kGpsArrivalThresholdMeters = 6.0;

/// Thời gian giãn cách giữa các lần nhắc nhở chỉ dẫn GPS nếu không chuyển mốc
/// Đơn vị: Mili-giây (ms).
int kGpsInstructionCooldownMs = 6000;

/// Mức độ ưu tiên giọng nói dẫn đường GPS (Thấp hơn nhiều so với camera threat: 200+)
int kGpsSpeechPriority = 50;

/// Địa chỉ API định tuyến đi bộ OpenStreetMap / OSRM Foot Profile
String kOsrmFootApiBase = 'https://router.project-osrm.org/route/v1/foot';

/// Thời gian chờ mạng tối đa khi truy vấn OSRM
/// Đơn vị: Mili-giây (ms). Quá 7 giây sẽ chuyển sang lộ trình dự phòng/ngoại tuyến.
int kOsrmNetworkTimeoutMs = 7000;
