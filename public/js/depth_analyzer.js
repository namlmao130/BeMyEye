/**
 * depth_analyzer.js
 * Module phát hiện vật cản bất định (Generic Obstacles) không có trong nhãn mô hình 2D
 * Đặc biệt tập trung vào:
 * - VẬT CẢN NGANG TẦM ĐẦU / NGỰC (Head & Chest Clearance Corridor):
 *   Bạt che hạ thấp, cành cây chìa ra, gương chiếu hậu xe tải, biển hiệu treo thấp, giàn giáo...
 *   (Đây là những hiểm họa số 1 mà gậy trắng hoàn toàn không chạm tới!)
 */

class GenericDepthAnalyzer {
  constructor() {
    this.PROC_WIDTH = 120;
    this.PROC_HEIGHT = 90;

    this.offscreenCanvas = document.createElement('canvas');
    this.offscreenCanvas.width = this.PROC_WIDTH;
    this.offscreenCanvas.height = this.PROC_HEIGHT;
    this.ctx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });

    // Khu vực tầm đầu / ngực (Head/Chest Frustum): từ 15% đến 55% chiều cao ảnh
    this.HEAD_CORRIDOR_TOP = 0.15;
    this.HEAD_CORRIDOR_BOTTOM = 0.55;

    // Lưới phân tích 3 ô: Trái, Giữa, Phải
    this.occupancyGrid = {
      left: { occupied: false, density: 0, distanceLevel: 'far' },
      center: { occupied: false, density: 0, distanceLevel: 'far' },
      right: { occupied: false, density: 0, distanceLevel: 'far' }
    };
  }

  /**
   * Phân tích không gian tầm cao tìm vật cản nhô ra
   * @param {HTMLVideoElement|HTMLCanvasElement} inputElement
   * @param {Array} known2DDetections - Danh sách các vật thể 2D đã biết (để không báo trùng với người/xe đã nhận diện)
   * @returns {Array} Danh sách chướng ngại vật bất định (Generic Obstacles)
   */
  detectGenericObstacles(inputElement, known2DDetections = []) {
    if (!inputElement) return [];

    this.ctx.drawImage(inputElement, 0, 0, this.PROC_WIDTH, this.PROC_HEIGHT);
    const imgData = this.ctx.getImageData(0, 0, this.PROC_WIDTH, this.PROC_HEIGHT);
    const data = imgData.data;

    // Chuyển xám và tính mật độ cạnh/gradient ở vùng ngang đầu
    const yStart = Math.floor(this.PROC_HEIGHT * this.HEAD_CORRIDOR_TOP);
    const yEnd = Math.floor(this.PROC_HEIGHT * this.HEAD_CORRIDOR_BOTTOM);

    const xThird = Math.floor(this.PROC_WIDTH / 3);
    const zoneScores = { left: 0, center: 0, right: 0 };
    const zonePixelCounts = { left: 0, center: 0, right: 0 };

    // Quét độ biến thiên và chi tiết cục bộ (Texture / Edge Disparity)
    for (let y = yStart + 1; y < yEnd - 1; y++) {
      for (let x = 1; x < this.PROC_WIDTH - 1; x++) {
        const idx = (y * this.PROC_WIDTH + x) * 4;
        
        // Gradient Laplace đơn giản để đo độ nổi hạt/vật cản cục bộ
        const grayCenter = (data[idx] + data[idx + 1] + data[idx + 2]) / 3;
        const grayTop = (data[idx - this.PROC_WIDTH * 4] + data[idx - this.PROC_WIDTH * 4 + 1] + data[idx - this.PROC_WIDTH * 4 + 2]) / 3;
        const grayBottom = (data[idx + this.PROC_WIDTH * 4] + data[idx + this.PROC_WIDTH * 4 + 1] + data[idx + this.PROC_WIDTH * 4 + 2]) / 3;
        const grayLeft = (data[idx - 4] + data[idx - 3] + data[idx - 2]) / 3;
        const grayRight = (data[idx + 4] + data[idx + 5] + data[idx + 6]) / 3;

        const diff = Math.abs(4 * grayCenter - grayTop - grayBottom - grayLeft - grayRight);

        let zone = 'center';
        if (x < xThird) zone = 'left';
        else if (x > xThird * 2) zone = 'right';

        if (diff > 35) { // Pixel có độ sắc nét/nổi khối cao
          zoneScores[zone] += diff;
        }
        zonePixelCounts[zone]++;
      }
    }

    const detectedGeneric = [];
    const zones = ['left', 'center', 'right'];

    for (const z of zones) {
      const avgScore = zoneScores[z] / (zonePixelCounts[z] || 1);
      
      // Ngưỡng phát hiện vật cản tầm đầu (Awning, tree branch, suspended hurdle)
      if (avgScore > 18.0) {
        // Kiểm tra xem vùng này đã có vật thể 2D (như người hoặc xe) bao phủ chưa
        const isCoveredBy2D = this.isZoneCoveredBy2D(z, known2DDetections);
        
        if (!isCoveredBy2D) {
          let distanceLevel = 'near';
          let distanceMeters = '1.5m - 2.5m';
          let panValue = 0.0;

          if (z === 'left') panValue = -0.7;
          else if (z === 'right') panValue = 0.7;

          if (avgScore > 32.0) {
            distanceLevel = 'critical'; // Rất sát mặt (< 1.5m)
            distanceMeters = '< 1.5m';
          }

          detectedGeneric.push({
            id: 'generic_head_' + z,
            type: 'generic_head_obstacle',
            vietnameseClass: 'Vật cản tầm đầu / bạt che',
            category: 'obstacle',
            direction: z,
            panValue: panValue,
            distanceLevel: distanceLevel,
            approximateDistanceMeters: distanceMeters,
            isHeadLevelHazard: true, // Cờ đặc biệt cho gậy trắng không với tới
            score: Math.min(0.92, avgScore / 40.0),
            bbox: this.getZoneBBox(z)
          });
        }
      }
    }

    return detectedGeneric;
  }

  /**
   * Kiểm tra xem vùng ngang đầu này có đang trùng với Bounding Box 2D đã biết không
   */
  isZoneCoveredBy2D(zone, known2DDetections) {
    if (!known2DDetections || known2DDetections.length === 0) return false;

    let targetCenterXMin = 0.33;
    let targetCenterXMax = 0.66;
    if (zone === 'left') {
      targetCenterXMin = 0.0;
      targetCenterXMax = 0.33;
    } else if (zone === 'right') {
      targetCenterXMin = 0.66;
      targetCenterXMax = 1.0;
    }

    for (const det of known2DDetections) {
      if (det.normalized && det.normalized.centerX >= targetCenterXMin && det.normalized.centerX <= targetCenterXMax) {
        // Nếu có người hoặc xe máy lớn ở vùng này thì bỏ qua generic để tránh báo trùng
        if (det.category === 'vehicle' || det.class === 'person') {
          return true;
        }
      }
    }
    return false;
  }

  getZoneBBox(zone) {
    // Trả về bbox tọa độ chuẩn hóa để vẽ debug
    const y = this.HEAD_CORRIDOR_TOP;
    const h = this.HEAD_CORRIDOR_BOTTOM - this.HEAD_CORRIDOR_TOP;
    let x = 0.33;
    let w = 0.34;
    if (zone === 'left') {
      x = 0.05;
      w = 0.28;
    } else if (zone === 'right') {
      x = 0.67;
      w = 0.28;
    }
    return [x, y, w, h];
  }
}

window.GenericDepthAnalyzer = GenericDepthAnalyzer;
