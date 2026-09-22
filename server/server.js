/**
 * Simple Node.js server for PZ Skill Books Checklist
 * Stores progress in a local JSON file with Basic Auth protection
 * 
 * Usage:
 *   node server.js
 * 
 * Environment variables:
 *   PORT          - Server port (default: 3000)
 *   USERNAME      - Basic auth username (default: admin)
 *   PASSWORD      - Basic auth password (required!)
 *   DATA_DIR      - Directory for progress files (default: ./data)
 */

import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Configuration
const PORT = process.env.PORT || 3000;
const USERNAME = process.env.USERNAME || 'admin';
const PASSWORD = process.env.PASSWORD;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');

if (!PASSWORD) {
  console.error('ERROR: PASSWORD environment variable is required');
  console.error('Usage: PASSWORD=yourpassword node server.js');
  process.exit(1);
}

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// MIME types
const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

// Basic auth check
function checkAuth(req) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Basic ')) return false;
  
  const credentials = Buffer.from(auth.slice(6), 'base64').toString();
  const [user, pass] = credentials.split(':');
  return user === USERNAME && pass === PASSWORD;
}

// Send auth required response
function sendAuthRequired(res) {
  res.writeHead(401, {
    'WWW-Authenticate': 'Basic realm="PZ Helper"',
    'Content-Type': 'text/plain'
  });
  res.end('Authentication required');
}

// Get progress file path for user
function getProgressPath(username) {
  // Sanitize username for filename
  const safe = username.replace(/[^a-zA-Z0-9_-]/g, '_');
  return path.join(DATA_DIR, `progress_${safe}.json`);
}

// Handle API requests
function handleAPI(req, res) {
  const progressPath = getProgressPath(USERNAME);
  
  if (req.method === 'GET') {
    // Load progress
    try {
      if (fs.existsSync(progressPath)) {
        const data = fs.readFileSync(progressPath, 'utf-8');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(data);
      } else {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ progress: {} }));
      }
    } catch (e) {
      console.error('Load error:', e);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Load failed' }));
    }
  } else if (req.method === 'POST') {
    // Save progress
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        fs.writeFileSync(progressPath, JSON.stringify(data, null, 2));
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
        console.log(`Progress saved for ${USERNAME}`);
      } catch (e) {
        console.error('Save error:', e);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Save failed' }));
      }
    });
  } else {
    res.writeHead(405);
    res.end('Method not allowed');
  }
}

// Serve static files
function serveStatic(req, res, filePath) {
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    
    const ext = path.extname(filePath);
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
}

// Main request handler
const server = http.createServer((req, res) => {
  // CORS headers for local development
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }
  
  // Check authentication
  if (!checkAuth(req)) {
    sendAuthRequired(res);
    return;
  }
  
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;
  
  // API endpoint
  if (pathname === '/api/progress') {
    handleAPI(req, res);
    return;
  }
  
  // Static files - serve from parent directory
  const WEBROOT = path.resolve(__dirname, '..');
  let filePath;
  if (pathname === '/' || pathname === '/index.html') {
    filePath = path.join(WEBROOT, 'index-server.html');
  } else {
    // Normalize and resolve the path, then verify it's within webroot
    const requestedPath = path.normalize(pathname).replace(/^(\.\.[\/\\])+/, '');
    filePath = path.resolve(WEBROOT, requestedPath.slice(1));
    
    // SECURITY: Prevent path traversal - must be within webroot
    if (!filePath.startsWith(WEBROOT + path.sep) && filePath !== WEBROOT) {
      console.warn(`Path traversal attempt blocked: ${pathname}`);
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }
  }
  
  serveStatic(req, res, filePath);
});

server.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════════════════════╗
║         PZ Skill Books - Self-Hosted Server            ║
╠════════════════════════════════════════════════════════╣
║  URL:      http://localhost:${PORT.toString().padEnd(28)}║
║  Username: ${USERNAME.padEnd(42)}║
║  Data:     ${DATA_DIR.slice(-40).padEnd(42)}║
╚════════════════════════════════════════════════════════╝
`);
});
