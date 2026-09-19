/**
 * PZ Skillbücher - Progress Sync Lambda
 * 
 * Handles GET (load progress) and POST (save progress) requests.
 * Authentication via Basic Auth with PBKDF2 password verification.
 * Progress stored in S3 as JSON.
 */

import { S3Client, GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { createHash, pbkdf2Sync, timingSafeEqual } from 'crypto';

// ============================================================
// Configuration
// ============================================================
const s3 = new S3Client({});
const BUCKET = process.env.BUCKET_NAME;
const AUTH_USERNAME = process.env.AUTH_USERNAME;
const AUTH_PASSWORD_HASH = process.env.AUTH_PASSWORD_HASH; // Format: iterations:salt:hash (all hex)

// ============================================================
// Logging
// ============================================================
const log = {
  info: (requestId, message, data = {}) => {
    console.log(JSON.stringify({ level: 'INFO', requestId, message, ...data }));
  },
  warn: (requestId, message, data = {}) => {
    console.warn(JSON.stringify({ level: 'WARN', requestId, message, ...data }));
  },
  error: (requestId, message, error = null, data = {}) => {
    console.error(JSON.stringify({ 
      level: 'ERROR', 
      requestId, 
      message, 
      error: error ? { name: error.name, message: error.message, stack: error.stack } : null,
      ...data 
    }));
  }
};

// ============================================================
// Password Verification
// ============================================================
function verifyPassword(password, storedHash) {
  try {
    const parts = storedHash.split(':');
    if (parts.length !== 3) {
      return false;
    }
    
    const [iterStr, salt, hash] = parts;
    const iterations = parseInt(iterStr, 10);
    
    if (isNaN(iterations) || iterations < 1) {
      return false;
    }
    
    const saltBuf = Buffer.from(salt, 'hex');
    const hashBuf = Buffer.from(hash, 'hex');
    
    if (saltBuf.length === 0 || hashBuf.length === 0) {
      return false;
    }
    
    const derivedKey = pbkdf2Sync(password, saltBuf, iterations, hashBuf.length, 'sha256');
    
    return timingSafeEqual(derivedKey, hashBuf);
  } catch (e) {
    // Don't log password verification errors in detail (security)
    return false;
  }
}

// ============================================================
// Basic Auth Parsing
// ============================================================
function parseBasicAuth(authHeader) {
  if (!authHeader || !authHeader.startsWith('Basic ')) {
    return null;
  }
  
  try {
    const base64 = authHeader.slice(6);
    const decoded = Buffer.from(base64, 'base64').toString('utf-8');
    const colonIndex = decoded.indexOf(':');
    
    if (colonIndex === -1) {
      return null;
    }
    
    const username = decoded.slice(0, colonIndex);
    const password = decoded.slice(colonIndex + 1);
    
    return { username, password };
  } catch {
    return null;
  }
}

// ============================================================
// Response Builder
// ============================================================
function response(statusCode, body, requestId = null) {
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Cache-Control': 'no-store',
  };
  
  if (requestId) {
    headers['X-Request-Id'] = requestId;
  }
  
  return {
    statusCode,
    headers,
    body: JSON.stringify(body),
  };
}

// ============================================================
// S3 Key Generation
// ============================================================
function progressKey(username) {
  // Hash username for privacy in S3 keys
  const hash = createHash('sha256').update(username).digest('hex').slice(0, 16);
  return `progress/${hash}.json`;
}

// ============================================================
// S3 Operations
// ============================================================
async function loadProgress(username, requestId) {
  const key = progressKey(username);
  
  try {
    const result = await s3.send(new GetObjectCommand({
      Bucket: BUCKET,
      Key: key,
    }));
    
    const body = await result.Body.transformToString();
    const progress = JSON.parse(body);
    
    log.info(requestId, 'Progress loaded from S3', { 
      key, 
      itemCount: Object.keys(progress).length 
    });
    
    return progress;
  } catch (e) {
    if (e.name === 'NoSuchKey') {
      log.info(requestId, 'No existing progress found', { key });
      return {};
    }
    throw e;
  }
}

async function saveProgress(username, progress, requestId) {
  const key = progressKey(username);
  const itemCount = Object.keys(progress).filter(k => progress[k]).length;
  
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: JSON.stringify(progress),
    ContentType: 'application/json',
  }));
  
  log.info(requestId, 'Progress saved to S3', { key, itemCount });
}

// ============================================================
// Request Validation
// ============================================================
function validateProgressObject(progress) {
  if (!progress || typeof progress !== 'object' || Array.isArray(progress)) {
    return { valid: false, error: 'Progress must be an object' };
  }
  
  // Check that all values are booleans (or at least truthy/falsy is fine)
  // and keys look reasonable (skill|volume format)
  const keyPattern = /^[\w\s]+\|\d$/;
  
  for (const [key, value] of Object.entries(progress)) {
    if (!keyPattern.test(key)) {
      return { valid: false, error: `Invalid key format: ${key}` };
    }
    if (typeof value !== 'boolean') {
      return { valid: false, error: `Value for ${key} must be boolean` };
    }
  }
  
  // Sanity check: max 200 entries (24 skills × 5 volumes = 120, with buffer)
  if (Object.keys(progress).length > 200) {
    return { valid: false, error: 'Too many entries' };
  }
  
  return { valid: true };
}

// ============================================================
// Lambda Handler
// ============================================================
export async function handler(event) {
  const requestId = event.requestContext?.requestId || 
                    event.headers?.['x-amzn-requestid'] || 
                    `local-${Date.now()}`;
  
  const method = event.requestContext?.http?.method || event.httpMethod;
  const path = event.requestContext?.http?.path || event.path || '/';
  const userAgent = event.headers?.['user-agent'] || 'unknown';
  
  log.info(requestId, 'Request received', { method, path, userAgent });
  
  // Handle CORS preflight
  if (method === 'OPTIONS') {
    log.info(requestId, 'CORS preflight');
    return response(200, { ok: true }, requestId);
  }
  
  // Check configuration
  if (!BUCKET || !AUTH_USERNAME || !AUTH_PASSWORD_HASH) {
    log.error(requestId, 'Missing environment configuration', null, {
      hasBucket: !!BUCKET,
      hasUsername: !!AUTH_USERNAME,
      hasPasswordHash: !!AUTH_PASSWORD_HASH
    });
    return response(500, { error: 'Server configuration error' }, requestId);
  }
  
  // Parse and verify auth
  const authHeader = event.headers?.authorization || event.headers?.Authorization;
  const auth = parseBasicAuth(authHeader);
  
  if (!auth) {
    log.warn(requestId, 'Missing or invalid Authorization header');
    return response(401, { error: 'Authorization required' }, requestId);
  }
  
  if (auth.username !== AUTH_USERNAME) {
    log.warn(requestId, 'Invalid username', { provided: auth.username });
    return response(401, { error: 'Invalid credentials' }, requestId);
  }
  
  if (!verifyPassword(auth.password, AUTH_PASSWORD_HASH)) {
    log.warn(requestId, 'Invalid password');
    return response(401, { error: 'Invalid credentials' }, requestId);
  }
  
  log.info(requestId, 'Authentication successful', { username: auth.username });
  
  try {
    // GET - Load progress
    if (method === 'GET') {
      const progress = await loadProgress(auth.username, requestId);
      return response(200, { progress }, requestId);
    }
    
    // POST - Save progress
    if (method === 'POST') {
      let body;
      try {
        body = JSON.parse(event.body || '{}');
      } catch (e) {
        log.warn(requestId, 'Invalid JSON in request body');
        return response(400, { error: 'Invalid JSON body' }, requestId);
      }
      
      if (!body.progress) {
        log.warn(requestId, 'Missing progress in request body');
        return response(400, { error: 'Missing progress object' }, requestId);
      }
      
      const validation = validateProgressObject(body.progress);
      if (!validation.valid) {
        log.warn(requestId, 'Invalid progress object', { error: validation.error });
        return response(400, { error: validation.error }, requestId);
      }
      
      await saveProgress(auth.username, body.progress, requestId);
      return response(200, { ok: true }, requestId);
    }
    
    // Method not allowed
    log.warn(requestId, 'Method not allowed', { method });
    return response(405, { error: 'Method not allowed' }, requestId);
    
  } catch (e) {
    log.error(requestId, 'Handler error', e);
    return response(500, { error: 'Internal server error' }, requestId);
  }
}
