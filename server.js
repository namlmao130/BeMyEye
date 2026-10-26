/**
 * Server phục vụ Web App Be My Eyes (Giai đoạn 1)
 * Hỗ trợ HTTPS tự động để trình duyệt điện thoại cho phép truy cập Camera (getUserMedia)
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const PORT_HTTPS = 8443;
const PORT_HTTP = 8080;
const PUBLIC_DIR = path.join(__dirname, 'public');
const CERTS_DIR = path.join(__dirname, 'certs');
const CERT_FILE = path.join(CERTS_DIR, 'cert.pem');
const KEY_FILE = path.join(CERTS_DIR, 'key.pem');

// Tự sinh SSL cert nếu chưa có
function ensureSSLCertificates() {
  if (!fs.existsSync(CERTS_DIR)) {
    fs.mkdirSync(CERTS_DIR, { recursive: true });
  }
  if (!fs.existsSync(CERT_FILE) || !fs.existsSync(KEY_FILE)) {
    console.log('Generating self-signed SSL certificate...');
    try {
      execSync(`openssl req -x509 -newkey rsa:2048 -keyout "${KEY_FILE}" -out "${CERT_FILE}" -days 365 -nodes -subj "/CN=bemyeye.local"`);
      console.log('SSL certificate generated successfully.');
    } catch (err) {
      console.error('Cannot generate SSL cert via openssl:', err.message);
    }
  }
}

ensureSSLCertificates();

// MIME Types
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wav': 'audio/wav',
  '.mp4': 'video/mp4'
};

function handleRequest(req, res) {
  let reqPath = decodeURI(req.url.split('?')[0]);
  if (reqPath === '/' || reqPath === '') {
    reqPath = '/index.html';
  }

  const filePath = path.join(PUBLIC_DIR, reqPath);

  // Chống Directory Traversal
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Not Found: ' + reqPath);
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, {
      'Content-Type': contentType,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    });

    const stream = fs.createReadStream(filePath);
    stream.pipe(res);
  });
}

// Lấy danh sách IP nội mạng
function getLocalIPAddresses() {
  const interfaces = os.networkInterfaces();
  const ips = [];
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        ips.push(iface.address);
      }
    }
  }
  return ips;
}

// Khởi chạy HTTPS Server
if (fs.existsSync(CERT_FILE) && fs.existsSync(KEY_FILE)) {
  const sslOptions = {
    key: fs.readFileSync(KEY_FILE),
    cert: fs.readFileSync(CERT_FILE)
  };

  https.createServer(sslOptions, handleRequest).listen(PORT_HTTPS, '0.0.0.0', () => {
    console.log('====================================================');
    console.log('BE MY EYES VN - MÁY CHỦ KIỂM THỬ THỜI GIAN THỰC');
    console.log('====================================================');
    console.log(`HTTPS Server đang chạy tại:`);
    console.log(`  - Máy tính (Local):   https://localhost:${PORT_HTTPS}`);
    const ips = getLocalIPAddresses();
    ips.forEach(ip => {
      console.log(`  - Điện thoại (Wi-Fi): https://${ip}:${PORT_HTTPS}`);
    });
    console.log('----------------------------------------------------');
    console.log('LƯU Ý TRÊN ĐIỆN THOẠI:');
    console.log('1. Điện thoại và máy tính cần kết nối cùng mạng Wi-Fi.');
    console.log('2. Mở trình duyệt (Safari trên iOS hoặc Chrome trên Android).');
    console.log('3. Nhập link https://[IP-cua-may]:8443');
    console.log('4. Chọn "Nâng cao (Advanced)" -> "Tiếp tục truy cập (Proceed/Bỏ qua cảnh báo)"');
    console.log('   để chấp nhận chứng chỉ SSL tự ký và cho phép dùng Camera.');
    console.log('====================================================\n');
  });
} else {
  console.warn('Không tìm thấy chứng chỉ SSL. Khởi chạy HTTP (Camera có thể bị chặn trên điện thoại).');
}

// Khởi chạy HTTP Server phụ
http.createServer((req, res) => {
  // Gợi ý chuyển sang HTTPS
  const host = req.headers.host ? req.headers.host.split(':')[0] : 'localhost';
  res.writeHead(301, { Location: `https://${host}:${PORT_HTTPS}${req.url}` });
  res.end();
}).listen(PORT_HTTP, '0.0.0.0');
