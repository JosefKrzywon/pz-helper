/**
 * PZ Skill Books - API Lambda
 * 
 * Endpoints:
 *   POST /api/login     - Login, returns session cookie
 *   GET  /api/logout    - Clear session cookie
 *   GET  /api/sync      - Get progress
 *   POST /api/sync      - Save progress
 *   GET  /api/admin/users       - List users (admin only)
 *   POST /api/admin/users       - Create user (admin only)
 *   DELETE /api/admin/users/:id - Delete user (admin only)
 */

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { createHash, createHmac } from 'crypto';

const client = new DynamoDBClient({});
const db = DynamoDBDocumentClient.from(client);

const USERS_TABLE = process.env.USERS_TABLE;
const PROGRESS_TABLE = process.env.PROGRESS_TABLE;
const SESSION_SECRET = process.env.SESSION_SECRET;
const ADMIN_USERNAME = process.env.ADMIN_USERNAME;

// ============================================================
// HELPERS
// ============================================================

function response(statusCode, body, cookies = []) {
  const headers = {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
  };
  
  if (cookies.length > 0) {
    headers['Set-Cookie'] = cookies.join(', ');
  }
  
  return {
    statusCode,
    headers,
    body: JSON.stringify(body),
  };
}

function parseCookies(cookieHeader) {
  const cookies = {};
  if (!cookieHeader) return cookies;
  
  cookieHeader.split(';').forEach(cookie => {
    const [name, ...rest] = cookie.trim().split('=');
    cookies[name] = rest.join('=');
  });
  
  return cookies;
}

function createSessionToken(username) {
  const payload = {
    username,
    exp: Date.now() + (365 * 24 * 60 * 60 * 1000), // 1 year
  };
  const data = Buffer.from(JSON.stringify(payload)).toString('base64');
  const signature = createHmac('sha256', SESSION_SECRET).update(data).digest('base64url');
  return `${data}.${signature}`;
}

function verifySessionToken(token) {
  if (!token) return null;
  
  const [data, signature] = token.split('.');
  if (!data || !signature) return null;
  
  const expectedSig = createHmac('sha256', SESSION_SECRET).update(data).digest('base64url');
  if (signature !== expectedSig) return null;
  
  try {
    const payload = JSON.parse(Buffer.from(data, 'base64').toString());
    if (payload.exp && payload.exp < Date.now()) return null;
    return payload;
  } catch {
    return null;
  }
}

function verifyPassword(password, storedHash) {
  const parts = storedHash.split(':');
  if (parts.length !== 3) return false;
  
  const [format, salt, hash] = parts;
  
  if (format === 'sha256') {
    const computed = createHash('sha256').update(salt + password).digest('hex');
    return computed === hash;
  }
  
  return false;
}

function hashPassword(password) {
  const salt = createHash('sha256').update(Math.random().toString()).digest('hex').slice(0, 32);
  const hash = createHash('sha256').update(salt + password).digest('hex');
  return `sha256:${salt}:${hash}`;
}

function getUserIdHash(username) {
  return createHash('sha256').update(username).digest('hex').slice(0, 16);
}

// ============================================================
// HANDLERS
// ============================================================

async function handleLogin(body) {
  const { username, password } = JSON.parse(body || '{}');
  
  if (!username || !password) {
    return response(400, { error: 'Username and password required' });
  }
  
  // Get user from DB
  const result = await db.send(new GetCommand({
    TableName: USERS_TABLE,
    Key: { username },
  }));
  
  if (!result.Item) {
    return response(401, { error: 'Invalid credentials' });
  }
  
  if (!verifyPassword(password, result.Item.passwordHash)) {
    return response(401, { error: 'Invalid credentials' });
  }
  
  // Create session
  const token = createSessionToken(username);
  const cookie = `pz_session=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000`;
  
  return response(200, { 
    ok: true, 
    username,
    isAdmin: result.Item.isAdmin || false,
  }, [cookie]);
}

async function handleLogout() {
  const cookie = 'pz_session=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0';
  return response(200, { ok: true }, [cookie]);
}

async function handleGetProgress(username) {
  const visibleId = getUserIdHash(username);
  
  const result = await db.send(new GetCommand({
    TableName: PROGRESS_TABLE,
    Key: { visibleId },
  }));
  
  return response(200, { 
    progress: result.Item?.progress || {} 
  });
}

async function handleSaveProgress(username, body) {
  const { progress } = JSON.parse(body || '{}');
  
  if (!progress || typeof progress !== 'object') {
    return response(400, { error: 'Invalid progress data' });
  }
  
  const visibleId = getUserIdHash(username);
  
  await db.send(new PutCommand({
    TableName: PROGRESS_TABLE,
    Item: {
      visibleId,
      username, // Store for reference
      progress,
      updatedAt: new Date().toISOString(),
    },
  }));
  
  return response(200, { ok: true });
}

async function handleListUsers(isAdmin) {
  if (!isAdmin) {
    return response(403, { error: 'Admin access required' });
  }
  
  const result = await db.send(new ScanCommand({
    TableName: USERS_TABLE,
    ProjectionExpression: 'username, isAdmin, createdAt',
  }));
  
  return response(200, { users: result.Items || [] });
}

async function handleCreateUser(isAdmin, body) {
  if (!isAdmin) {
    return response(403, { error: 'Admin access required' });
  }
  
  const { username, password, makeAdmin } = JSON.parse(body || '{}');
  
  if (!username || !password) {
    return response(400, { error: 'Username and password required' });
  }
  
  // Check if user exists
  const existing = await db.send(new GetCommand({
    TableName: USERS_TABLE,
    Key: { username },
  }));
  
  if (existing.Item) {
    return response(409, { error: 'User already exists' });
  }
  
  await db.send(new PutCommand({
    TableName: USERS_TABLE,
    Item: {
      username,
      passwordHash: hashPassword(password),
      isAdmin: makeAdmin || false,
      createdAt: new Date().toISOString(),
    },
  }));
  
  return response(201, { ok: true, username });
}

async function handleDeleteUser(isAdmin, username, currentUser) {
  if (!isAdmin) {
    return response(403, { error: 'Admin access required' });
  }
  
  if (username === currentUser) {
    return response(400, { error: 'Cannot delete yourself' });
  }
  
  await db.send(new DeleteCommand({
    TableName: USERS_TABLE,
    Key: { username },
  }));
  
  // Also delete their progress
  const visibleId = getUserIdHash(username);
  await db.send(new DeleteCommand({
    TableName: PROGRESS_TABLE,
    Key: { visibleId },
  }));
  
  return response(200, { ok: true });
}

async function handleGetSession(session) {
  // Return current session info
  const result = await db.send(new GetCommand({
    TableName: USERS_TABLE,
    Key: { username: session.username },
  }));
  
  if (!result.Item) {
    return response(401, { error: 'Session invalid' });
  }
  
  return response(200, {
    username: session.username,
    isAdmin: result.Item.isAdmin || false,
  });
}

// ============================================================
// MAIN HANDLER
// ============================================================

export async function handler(event) {
  const method = event.requestContext?.http?.method || event.httpMethod;
  const path = event.requestContext?.http?.path || event.path || '/';
  const cookies = parseCookies(event.headers?.cookie || event.headers?.Cookie);
  const body = event.body;
  
  console.log(`${method} ${path}`);
  
  // Public endpoints
  if (path === '/api/login' && method === 'POST') {
    return handleLogin(body);
  }
  
  if (path === '/api/logout' && method === 'GET') {
    return handleLogout();
  }
  
  // All other endpoints require session
  const session = verifySessionToken(cookies.pz_session);
  
  if (!session) {
    return response(401, { error: 'Not authenticated' });
  }
  
  // Get user info for admin check
  const userResult = await db.send(new GetCommand({
    TableName: USERS_TABLE,
    Key: { username: session.username },
  }));
  
  if (!userResult.Item) {
    return response(401, { error: 'User not found' });
  }
  
  const isAdmin = userResult.Item.isAdmin || false;
  
  // Session info
  if (path === '/api/session' && method === 'GET') {
    return handleGetSession(session);
  }
  
  // Progress sync
  if (path === '/api/sync' && method === 'GET') {
    return handleGetProgress(session.username);
  }
  
  if (path === '/api/sync' && method === 'POST') {
    return handleSaveProgress(session.username, body);
  }
  
  // Admin endpoints
  if (path === '/api/admin/users' && method === 'GET') {
    return handleListUsers(isAdmin);
  }
  
  if (path === '/api/admin/users' && method === 'POST') {
    return handleCreateUser(isAdmin, body);
  }
  
  if (path.startsWith('/api/admin/users/') && method === 'DELETE') {
    const targetUser = decodeURIComponent(path.split('/').pop());
    return handleDeleteUser(isAdmin, targetUser, session.username);
  }
  
  return response(404, { error: 'Not found' });
}
