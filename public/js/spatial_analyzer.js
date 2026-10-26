/**
 * spatial_analyzer.js
 * Phân tích không gian 2D từ Camera:
 * 1. Phân chia 3 hành lang di chuyển: Trái (Left), Giữa (Center), Phải (Right).
 * 2. Ước lượng độ gần/xa dựa trên vị trí chân vật thể (bottom-y) và diện tích bbox tương đối.
 * 3. Phát hiện vật thể đang lao tới (Approaching) thông qua tốc độ tăng kích thước khung hình theo thời gian.
 */

class SpatialAnalyzer {
  constructor() {
    // Ngưỡng phân chia 3 vùng ngang (tỷ lệ 0.0 - 1.0)
    this.LEFT_BOUNDARY = 0.35;
    this.RIGHT_BOUNDARY = 0.65;

    // Ngưỡng ước lượng khoảng cách
    this.NEAR_BOTTOM_Y = 0.65;      // Chân vật chạm 65% chiều cao ảnh
    this.CRITICAL_BOTTOM_Y = 0.82;  // Chân vật chạm 82% chiều cao ảnh (sát chân)
    this.NEAR_AREA_RATIO = 0.08;    // Diện tích bbox >= 8% khung hình
    this.CRITICAL_AREA_RATIO = 0.22;// Diện tích bbox >= 22% khung hình

    // Bộ nhớ theo dõi vật thể qua các khung hình (Simple Object Tracker)
    this.trackedObjects = [];
    this.TRACK_EXPIRATION_MS = 600; // Xóa track sau 600ms không thấy lại
    this.APPROACH_THRESHOLD = 0.15; // Tốc độ tăng diện tích / giây để coi là đang lao tới
  }

  /**
   * Phân tích một danh sách các phát hiện thô từ detector
   * @param {Array} rawDetections - Mảng các { class, score, bbox: [x, y, width, height] }
   * @param {number} frameWidth - Chiều rộng khung hình (px)
   * @param {number} frameHeight - Chiều cao khung hình (px)
   * @returns {Array} Danh sách vật thể đã được phân tích không gian
   */
  analyzeDetections(rawDetections, frameWidth, frameHeight) {
    const now = Date.now();
    const analyzed = [];

    for (const det of rawDetections) {
      const [x, y, w, h] = det.bbox;

      // 1. Tọa độ chuẩn hóa (0.0 - 1.0)
      const centerX = (x + w / 2) / frameWidth;
      const bottomY = (y + h) / frameHeight;
      const areaRatio = (w * h) / (frameWidth * frameHeight);

      // 2. Xác định hướng (Direction)
      let direction = 'center';
      let panValue = 0.0;
      if (centerX < this.LEFT_BOUNDARY) {
        direction = 'left';
        // Chuẩn hóa pan từ -1.0 đến -0.2
        panValue = -0.3 - (1 - (centerX / this.LEFT_BOUNDARY)) * 0.7;
      } else if (centerX > this.RIGHT_BOUNDARY) {
        direction = 'right';
        // Chuẩn hóa pan từ +0.2 đến +1.0
        panValue = 0.3 + ((centerX - this.RIGHT_BOUNDARY) / (1 - this.RIGHT_BOUNDARY)) * 0.7;
      } else {
        direction = 'center';
        // Nhẹ nhàng lệch nhẹ quanh tâm
        panValue = (centerX - 0.5) * 0.4;
      }

      // 3. Ước lượng khoảng cách tĩnh (Distance level)
      let distanceLevel = 'far';
      let approximateDistanceMeters = '> 3.5m';

      if (bottomY >= this.CRITICAL_BOTTOM_Y || areaRatio >= this.CRITICAL_AREA_RATIO) {
        distanceLevel = 'critical';
        approximateDistanceMeters = '< 1.5m';
      } else if (bottomY >= this.NEAR_BOTTOM_Y || areaRatio >= this.NEAR_AREA_RATIO) {
        distanceLevel = 'near';
        approximateDistanceMeters = '1.5m - 3.0m';
      } else {
        distanceLevel = 'far';
        approximateDistanceMeters = '> 3.0m';
      }

      // 4. Kiểm tra xem vật thể có đang lao tới nhanh không (Approaching speed)
      const approachingCheck = this.checkIfApproaching(det.class, centerX, bottomY, areaRatio, now);
      if (approachingCheck.isApproaching) {
        // Nâng cấp lên mức khẩn cấp nếu vật đang phóng nhanh về phía người dùng
        distanceLevel = 'critical';
      }

      analyzed.push({
        id: approachingCheck.trackId,
        class: det.class,
        vietnameseClass: det.vietnameseClass || det.class,
        category: det.category || 'obstacle',
        score: det.score,
        bbox: det.bbox,
        normalized: {
          centerX,
          bottomY,
          areaRatio
        },
        direction,
        panValue,
        distanceLevel,
        approximateDistanceMeters,
        isApproaching: approachingCheck.isApproaching,
        growthRate: approachingCheck.growthRate
      });
    }

    // Làm sạch bộ nhớ theo dõi các vật đã biến mất
    this.cleanupOldTracks(now);

    return analyzed;
  }

  /**
   * Theo dõi và tính toán độ dãn nở khung hình theo thời gian
   */
  checkIfApproaching(cls, cx, cy, area, timestamp) {
    // Tìm track gần nhất có cùng class và vị trí tâm gần nhau (Spatial distance < 0.25)
    let matchedTrack = null;
    let minDistance = 0.25;

    for (const track of this.trackedObjects) {
      if (track.class === cls) {
        const d = Math.hypot(track.lastCx - cx, track.lastCy - cy);
        if (d < minDistance) {
          minDistance = d;
          matchedTrack = track;
        }
      }
    }

    if (!matchedTrack) {
      // Tạo track mới
      const newTrack = {
        id: 'track_' + Math.random().toString(36).substr(2, 6),
        class: cls,
        firstTime: timestamp,
        lastTime: timestamp,
        firstArea: area,
        lastArea: area,
        lastCx: cx,
        lastCy: cy,
        history: [{ t: timestamp, area }]
      };
      this.trackedObjects.push(newTrack);
      return { isApproaching: false, growthRate: 0, trackId: newTrack.id };
    }

    // Cập nhật track hiện có
    const dt = (timestamp - matchedTrack.firstTime) / 1000; // Đổi ra giây
    matchedTrack.history.push({ t: timestamp, area });
    if (matchedTrack.history.length > 10) matchedTrack.history.shift();

    let growthRate = 0;
    if (dt > 0.15) {
      // Tính tốc độ tăng trưởng diện tích
      const areaDelta = area - matchedTrack.firstArea;
      growthRate = areaDelta / dt;
    }

    matchedTrack.lastTime = timestamp;
    matchedTrack.lastArea = area;
    matchedTrack.lastCx = cx;
    matchedTrack.lastCy = cy;

    // Chỉ coi là lao tới nếu diện tích tăng đáng kể và diện tích hiện tại không quá nhỏ
    const isApproaching = (growthRate > this.APPROACH_THRESHOLD && area > 0.05);

    return {
      isApproaching,
      growthRate,
      trackId: matchedTrack.id
    };
  }

  cleanupOldTracks(now) {
    this.trackedObjects = this.trackedObjects.filter(
      track => (now - track.lastTime) < this.TRACK_EXPIRATION_MS
    );
  }
}

window.SpatialAnalyzer = SpatialAnalyzer;
