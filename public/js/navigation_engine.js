/**
 * navigation_engine.js
 * Bộ máy dẫn đường từng bước (Turn-by-Turn Navigation Engine)
 * 
 * TÍNH NĂNG CHÍNH:
 * 1. Định vị GPS độ chính xác cao (Geolocation API) kèm bộ lọc làm mượt chống trôi (GPS Drift Filter).
 * 2. Đọc La bàn số (Digital Compass / DeviceOrientation) để hướng dẫn chuẩn góc quay người dùng.
 * 3. Tính toán khoảng cách (Haversine) & góc phương vị (Bearing) tới các mốc rẽ.
 * 4. Lời chỉ dẫn tiếng Việt cực ngắn: "Đi thẳng 40 mét", "Chuẩn bị rẽ phải", "Rẽ trái".
 * 5. NGUYÊN TẮC AN TOÀN SỐ 1: Cảnh báo va chạm luôn lập tức NGẮT LỜI dẫn đường GPS.
 * 6. Hỗ trợ chế độ mô phỏng tuyến đường (Route Simulator) để kiểm thử tại chỗ.
 */

class NavigationEngine {
  constructor(audioHaptics, alertEngine) {
    this.audio = audioHaptics;
    this.alertEngine = alertEngine;

    // Trạng thái GPS
    this.currentPosition = null;      // { lat, lng, accuracy, heading }
    this.smoothedPosition = null;     // Vị trí đã làm mượt
    this.compassHeading = 0;          // Góc la bàn (0 - 360 độ)
    this.watchId = null;
    this.isNavigating = false;
    this.gpsAccuracy = 999;           // Sai số bán kính mét

    // Tuyến đường hiện tại (Danh sách Waypoints)
    this.activeRoute = [];
    this.currentWaypointIndex = 0;
    this.lastSpokenInstruction = '';
    this.lastInstructionTime = 0;
    this.INSTRUCTION_COOLDOWN_MS = 6000; // Tối đa 1 chỉ dẫn mỗi 6 giây để không gây rối

    // Trạng thái mô phỏng (Simulation)
    this.isSimulating = false;
    this.simInterval = null;

    this.initCompass();
  }

  /**
   * Khởi tạo lắng nghe La bàn số (DeviceOrientation)
   */
  initCompass() {
    const handleOrientation = (e) => {
      let heading = 0;
      if (e.webkitCompassHeading !== undefined) {
        // iOS Safari cung cấp trực tiếp góc Bắc thực
        heading = e.webkitCompassHeading;
      } else if (e.alpha !== null) {
        // Android Chrome
        heading = 360 - e.alpha;
      }
      this.compassHeading = Math.round(heading);
    };

    if (window.DeviceOrientationEvent) {
      window.addEventListener('deviceorientation', handleOrientation, true);
    }
  }

  /**
   * Yêu cầu quyền truy cập la bàn trên iOS 13+ nếu cần
   */
  async requestCompassPermission() {
    if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
      try {
        const response = await DeviceOrientationEvent.requestPermission();
        return response === 'granted';
      } catch (e) {
        console.warn('Lỗi xin quyền la bàn:', e);
        return false;
      }
    }
    return true;
  }

  /**
   * Bắt đầu theo dõi vị trí GPS thời gian thực
   */
  startNavigation(routeWaypoints = null) {
    if (routeWaypoints && routeWaypoints.length > 0) {
      this.activeRoute = routeWaypoints;
      this.currentWaypointIndex = 0;
    } else {
      // Tuyến đường mẫu mặc định (Tuyến thử nghiệm phố đi bộ / hẻm dài 150m)
      this.activeRoute = this.getDefaultSampleRoute();
      this.currentWaypointIndex = 0;
    }

    this.isNavigating = true;
    this.lastSpokenInstruction = '';

    if (!('geolocation' in navigator)) {
      this.audio.speakVietnamese('Thiết bị không hỗ trợ định vị GPS', true);
      return false;
    }

    const geoOptions = {
      enableHighAccuracy: true, // Bật GPS độ chính xác cao
      timeout: 10000,
      maximumAge: 1000
    };

    this.watchId = navigator.geolocation.watchPosition(
      (pos) => this.handleGPSUpdate(pos),
      (err) => this.handleGPSError(err),
      geoOptions
    );

    this.audio.speakVietnamese('Bắt đầu lộ trình dẫn đường', true);
    return true;
  }

  stopNavigation() {
    this.isNavigating = false;
    if (this.watchId !== null) {
      navigator.geolocation.clearWatch(this.watchId);
      this.watchId = null;
    }
    if (this.isSimulating) {
      this.stopSimulation();
    }
    this.audio.speakVietnamese('Đã kết thúc lộ trình', true);
  }

  /**
   * Xử lý tín hiệu GPS mới và lọc làm mượt (Smoothing Filter)
   */
  handleGPSUpdate(pos) {
    const rawLat = pos.coords.latitude;
    const rawLng = pos.coords.longitude;
    const accuracy = pos.coords.accuracy;
    this.gpsAccuracy = Math.round(accuracy);

    // Cảnh báo nếu tín hiệu GPS quá yếu (thường gặp trong hẻm sâu)
    if (accuracy > 25) {
      console.warn(`GPS yếu: sai số ±${this.gpsAccuracy}m`);
    }

    // Bộ lọc làm mượt vị trí (Exponential Moving Average)
    if (!this.smoothedPosition) {
      this.smoothedPosition = { lat: rawLat, lng: rawLng };
    } else {
      // Trọng số làm mượt alpha: tin tưởng vị trí mới hơn nếu accuracy nhỏ
      const alpha = accuracy < 10 ? 0.45 : 0.2;
      this.smoothedPosition.lat = this.smoothedPosition.lat * (1 - alpha) + rawLat * alpha;
      this.smoothedPosition.lng = this.smoothedPosition.lng * (1 - alpha) + rawLng * alpha;
    }

    this.currentPosition = {
      lat: this.smoothedPosition.lat,
      lng: this.smoothedPosition.lng,
      accuracy: this.gpsAccuracy,
      speed: pos.coords.speed || 0
    };

    // Tính toán dẫn đường tới mốc tiếp theo
    this.evaluateNavigationStep();
  }

  handleGPSError(err) {
    console.warn('Lỗi định vị GPS:', err.message);
    if (err.code === 1) {
      this.audio.speakVietnamese('Chưa cấp quyền truy cập vị trí GPS', true);
    }
  }

  /**
   * Đánh giá vị trí hiện tại so với Waypoint kế tiếp và phát câu chỉ dẫn
   */
  evaluateNavigationStep() {
    if (!this.isNavigating || !this.currentPosition || this.currentWaypointIndex >= this.activeRoute.length) {
      return;
    }

    // NGUYÊN TẮC AN TOÀN SỐ 1: NẾU ĐANG CÓ HIỂM HỌA KHẨN CẤP, TUYỆT ĐỐI KHÔNG NÓI GPS
    if (this.alertEngine && this.alertEngine.currentThreat) {
      const threat = this.alertEngine.currentThreat;
      if (threat.distanceLevel === 'critical' || threat.isApproaching || threat.isNegativeObstacle) {
        return; // Nhường hoàn toàn cho cảnh báo an toàn
      }
    }

    const targetWaypoint = this.activeRoute[this.currentWaypointIndex];
    const distToTarget = this.calculateHaversineDistance(
      this.currentPosition.lat,
      this.currentPosition.lng,
      targetWaypoint.lat,
      targetWaypoint.lng
    );

    const bearingToTarget = this.calculateBearing(
      this.currentPosition.lat,
      this.currentPosition.lng,
      targetWaypoint.lat,
      targetWaypoint.lng
    );

    // 1. Kiểm tra đã đến mốc chưa
    if (distToTarget <= 6) { // Bán kính tiếp cận 6 mét
      if (this.currentWaypointIndex === this.activeRoute.length - 1) {
        this.speakNavigation('Bạn đã đến điểm đích!', true);
        this.isNavigating = false;
        return;
      } else {
        // Đã tới ngã rẽ, chuyển sang mốc tiếp theo
        this.currentWaypointIndex++;
        const nextWp = this.activeRoute[this.currentWaypointIndex];
        this.speakNavigation(`${targetWaypoint.actionText || 'Rẽ vào'}. ${nextWp.instruction}`, true);
        return;
      }
    }

    // 2. Nhắc nhở cự ly và góc lệch
    const now = Date.now();
    if (now - this.lastInstructionTime >= this.INSTRUCTION_COOLDOWN_MS) {
      let instructionText = '';

      if (distToTarget > 20) {
        instructionText = `Đi thẳng ${Math.round(distToTarget)} mét`;
      } else if (distToTarget <= 20 && distToTarget > 6) {
        instructionText = `Chuẩn bị ${targetWaypoint.actionText || 'rẽ'} sau ${Math.round(distToTarget)} mét`;
      }

      // Kiểm tra góc lệch la bàn nếu người dùng đang đi ngược hướng
      const headingDiff = this.calculateAngleDifference(this.compassHeading, bearingToTarget);
      if (Math.abs(headingDiff) > 45 && distToTarget > 10) {
        if (headingDiff > 0) {
          instructionText = `Chếch sang phải. ` + instructionText;
        } else {
          instructionText = `Chếch sang trái. ` + instructionText;
        }
      }

      if (instructionText && instructionText !== this.lastSpokenInstruction) {
        this.speakNavigation(instructionText);
      }
    }
  }

  /**
   * Phát câu chỉ dẫn GPS (Có kiểm tra ưu tiên an toàn)
   */
  speakNavigation(text, force = false) {
    // Kiểm tra lại lần nữa: Nếu đang có vật cản trước mặt thì bỏ qua
    if (this.alertEngine && this.alertEngine.currentThreat) {
      const threat = this.alertEngine.currentThreat;
      if (threat.distanceLevel === 'critical' || threat.isApproaching) {
        return;
      }
    }

    this.lastSpokenInstruction = text;
    this.lastInstructionTime = Date.now();
    this.audio.speakVietnamese(text, force);
  }

  /**
   * Công thức Haversine tính khoảng cách giữa 2 tọa độ (mét)
   */
  calculateHaversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000; // Bán kính Trái Đất (mét)
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = 
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  /**
   * Tính góc phương vị Bearing (0 - 360 độ từ Bắc theo chiều kim đồng hồ)
   */
  calculateBearing(lat1, lon1, lat2, lon2) {
    const phi1 = lat1 * Math.PI / 180;
    const phi2 = lat2 * Math.PI / 180;
    const deltaLambda = (lon2 - lon1) * Math.PI / 180;

    const y = Math.sin(deltaLambda) * Math.cos(phi2);
    const x = Math.cos(phi1) * Math.sin(phi2) -
              Math.sin(phi1) * Math.cos(phi2) * Math.cos(deltaLambda);
    const theta = Math.atan2(y, x);
    return (theta * 180 / Math.PI + 360) % 360;
  }

  calculateAngleDifference(sourceAngle, targetAngle) {
    let diff = (targetAngle - sourceAngle + 180) % 360 - 180;
    return diff < -180 ? diff + 360 : diff;
  }

  /**
   * Chế độ Mô phỏng đi bộ (Simulation) để kiểm thử tại chỗ
   */
  startSimulation(customRoute = null) {
    this.stopNavigation();
    this.isSimulating = true;
    this.isNavigating = true;
    this.activeRoute = customRoute || this.getDefaultSampleRoute();
    this.currentWaypointIndex = 0;

    let progressIndex = 0;
    const simSpeedMps = 1.0; // Tốc độ đi bộ 1m/s
    let currentSimLat = this.activeRoute[0].lat;
    let currentSimLng = this.activeRoute[0].lng;

    this.audio.speakVietnamese('Bắt đầu mô phỏng đi bộ tuyến đường mẫu', true);

    this.simInterval = setInterval(() => {
      if (!this.isSimulating || this.currentWaypointIndex >= this.activeRoute.length) {
        this.stopSimulation();
        return;
      }

      const targetWp = this.activeRoute[this.currentWaypointIndex];
      const dist = this.calculateHaversineDistance(currentSimLat, currentSimLng, targetWp.lat, targetWp.lng);

      if (dist < 4) {
        if (this.currentWaypointIndex < this.activeRoute.length - 1) {
          this.currentWaypointIndex++;
        } else {
          this.speakNavigation('Bạn đã đến điểm đích mô phỏng!', true);
          this.stopSimulation();
          return;
        }
      } else {
        // Di chuyển dần về phía mốc
        const bearing = this.calculateBearing(currentSimLat, currentSimLng, targetWp.lat, targetWp.lng);
        const moveDist = 2.0; // Đi 2m mỗi chu kỳ
        const dLat = (moveDist * Math.cos(bearing * Math.PI / 180)) / 111111;
        const dLng = (moveDist * Math.sin(bearing * Math.PI / 180)) / (111111 * Math.cos(currentSimLat * Math.PI / 180));
        currentSimLat += dLat;
        currentSimLng += dLng;
        this.compassHeading = Math.round(bearing);
      }

      this.currentPosition = {
        lat: currentSimLat,
        lng: currentSimLng,
        accuracy: 4,
        speed: simSpeedMps
      };

      this.evaluateNavigationStep();
    }, 1500);
  }

  stopSimulation() {
    this.isSimulating = false;
    if (this.simInterval) {
      clearInterval(this.simInterval);
      this.simInterval = null;
    }
  }

  /**
   * Tuyến đường mẫu thực tế tại khu vực Hồ Gươm / Phố đi bộ Hà Nội
   */
  getDefaultSampleRoute() {
    return [
      { lat: 21.028511, lng: 105.854167, name: 'Điểm xuất phát: Vỉa hè Đinh Tiên Hoàng', instruction: 'Bắt đầu đi thẳng', actionText: 'Xuất phát' },
      { lat: 21.028850, lng: 105.854200, name: 'Ngã rẽ 1: Góc phố Lò Sũ', instruction: 'Đi thẳng 38 mét', actionText: 'Rẽ phải vào phố Lò Sũ' },
      { lat: 21.028880, lng: 105.854700, name: 'Ngã rẽ 2: Đầu hẻm 12', instruction: 'Đi tiếp 45 mét trong phố', actionText: 'Rẽ trái vào Hẻm 12' },
      { lat: 21.029300, lng: 105.854750, name: 'Điểm đích: Cổng trung tâm', instruction: 'Đi thẳng 42 mét nữa', actionText: 'Đích đến' }
    ];
  }

  getCurrentStatus() {
    if (!this.isNavigating) return { status: 'idle' };
    const target = this.activeRoute[this.currentWaypointIndex];
    let distance = 0;
    if (this.currentPosition && target) {
      distance = Math.round(this.calculateHaversineDistance(
        this.currentPosition.lat,
        this.currentPosition.lng,
        target.lat,
        target.lng
      ));
    }
    return {
      status: this.isSimulating ? 'simulating' : 'active',
      currentWaypointIndex: this.currentWaypointIndex,
      totalWaypoints: this.activeRoute.length,
      targetName: target ? target.name : '',
      distanceToTarget: distance,
      nextAction: target ? target.actionText : '',
      lastInstruction: this.lastSpokenInstruction,
      gpsAccuracy: this.gpsAccuracy,
      compassHeading: this.compassHeading
    };
  }
}

window.NavigationEngine = NavigationEngine;
