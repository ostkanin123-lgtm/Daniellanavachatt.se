const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const querystring = require('querystring');
const { randomUUID } = require('crypto');

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const ROOT = __dirname;
const INDEX_PATH = path.join(ROOT, 'index.html');
const DATA_PATH = path.join(ROOT, 'social-data.json');
const STRIPE_SECRET_KEY = String(process.env.STRIPE_SECRET_KEY || '');
const PUBLIC_BASE_URL = String(process.env.PUBLIC_BASE_URL || '').trim();
const STRIPE_MONTHLY_PRICE_SEK = Number(process.env.STRIPE_MONTHLY_PRICE_SEK || process.env.STRIPE_SIGNUP_PRICE_SEK || 7900);
const ACCESS_PERIOD_MS = 1000 * 60 * 60 * 24 * 30;

const rooms = new Map();
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400'
};

let data = loadData();
let saveTimer = null;

function defaultData() {
  return {
    users: [],
    profiles: {},
    inbox: {},
    sessions: {},
    pendingSignups: {},
    pendingRenewals: {},
    chat: [],
    dms: [],
    nextIds: {
      user: 1,
      inbox: 1,
      chat: 1,
      dm: 1
    }
  };
}

function loadData() {
  try {
    if (!fs.existsSync(DATA_PATH)) return defaultData();
    const raw = fs.readFileSync(DATA_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      ...defaultData(),
      ...parsed,
      nextIds: {
        ...defaultData().nextIds,
        ...(parsed.nextIds || {})
      }
    };
  } catch {
    return defaultData();
  }
}

function scheduleSave() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    fs.writeFile(DATA_PATH, JSON.stringify(data, null, 2), () => {});
  }, 120);
}

function nowIso() {
  return new Date().toISOString();
}

function safeCode(code) {
  return String(code || 'default').toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 40) || 'default';
}

function json(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    ...CORS_HEADERS
  });
  res.end(JSON.stringify(body));
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 1_000_000) {
        reject(new Error('Payload too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch {
        reject(new Error('Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function findUserByEmail(email) {
  const target = normalizeEmail(email);
  return data.users.find((u) => normalizeEmail(u.email) === target) || null;
}

function userPublic(user) {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    createdAt: user.createdAt,
    paidMember: !!user.paidMember,
    paidUntilTs: Number(user.paidUntilTs || 0),
    hasAccess: membershipActive(user)
  };
}

function paymentEnabled() {
  return !!STRIPE_SECRET_KEY;
}

function membershipActive(user) {
  if (!paymentEnabled()) return true;
  if (!user) return false;
  const paidUntilTs = Number(user.paidUntilTs || 0);
  if (paidUntilTs > Date.now()) return true;
  return !!user.paidMember && !paidUntilTs;
}

function createSession(userId) {
  const token = randomUUID();
  data.sessions[token] = {
    userId,
    lastSeen: Date.now(),
    createdAt: nowIso()
  };
  scheduleSave();
  return token;
}

function authFrom(req, body, urlObj, options = {}) {
  const allowExpiredMembership = !!options.allowExpiredMembership;
  const fromBody = body && body.token ? String(body.token) : '';
  const fromQuery = urlObj ? String(urlObj.searchParams.get('token') || '') : '';
  const token = fromBody || fromQuery;
  const session = token ? data.sessions[token] : null;
  if (!session) return { ok: false, error: 'Ej inloggad.' };
  const user = data.users.find((u) => u.id === session.userId);
  if (!user) return { ok: false, error: 'Ogiltig session.' };
  if (!allowExpiredMembership && !membershipActive(user)) {
    return { ok: false, error: 'Ditt medlemskap har gått ut. Förnya för att få full tillgång.' };
  }
  session.lastSeen = Date.now();
  return { ok: true, token, session, user };
}

function cleanupSessions() {
  const now = Date.now();
  let changed = false;
  Object.keys(data.sessions).forEach((token) => {
    if (now - Number(data.sessions[token].lastSeen || 0) > 1000 * 60 * 60 * 24 * 7) {
      delete data.sessions[token];
      changed = true;
    }
  });
  if (changed) scheduleSave();
}

function cleanupPendingSignups() {
  const now = Date.now();
  let changed = false;
  Object.keys(data.pendingSignups || {}).forEach((id) => {
    const item = data.pendingSignups[id];
    if (!item || Number(item.expiresAt || 0) < now || item.status === 'completed') {
      delete data.pendingSignups[id];
      changed = true;
    }
  });
  if (changed) scheduleSave();
}

function cleanupPendingRenewals() {
  const now = Date.now();
  let changed = false;
  Object.keys(data.pendingRenewals || {}).forEach((id) => {
    const item = data.pendingRenewals[id];
    if (!item || Number(item.expiresAt || 0) < now || item.status === 'completed') {
      delete data.pendingRenewals[id];
      changed = true;
    }
  });
  if (changed) scheduleSave();
}

function ensureInbox(userId) {
  if (!data.inbox[userId]) data.inbox[userId] = [];
  return data.inbox[userId];
}

function addInboxMessage(userId, fromName, subject, message) {
  const inbox = ensureInbox(userId);
  inbox.unshift({
    id: data.nextIds.inbox++,
    from: fromName,
    subject,
    message,
    createdAt: nowIso()
  });
  if (inbox.length > 200) inbox.length = 200;
  scheduleSave();
}

function createUser({ name, email, password, paidMember, paidUntilTs }) {
  const user = {
    id: data.nextIds.user++,
    name,
    email,
    password,
    paidMember: !!paidMember,
    paidUntilTs: Number(paidUntilTs || 0),
    createdAt: nowIso()
  };
  data.users.push(user);
  data.profiles[user.id] = { age: '', bio: '', imageData: '', updatedAt: nowIso() };
  addInboxMessage(user.id, 'Nara Team', 'Välkommen till Nara', `Kul att du är här, ${name}!`);
  scheduleSave();
  return user;
}

function getBaseUrl(req) {
  if (PUBLIC_BASE_URL) return PUBLIC_BASE_URL.replace(/\/+$/, '');
  const host = String(req.headers.host || 'localhost:8080');
  const proto = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim() || 'http';
  return `${proto}://${host}`;
}

function stripeRequest(method, endpoint, formBody) {
  return new Promise((resolve, reject) => {
    const payload = formBody ? querystring.stringify(formBody) : '';
    const req = https.request(
      {
        hostname: 'api.stripe.com',
        path: endpoint,
        method,
        headers: {
          Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(payload)
        }
      },
      (res) => {
        let raw = '';
        res.on('data', (chunk) => { raw += chunk; });
        res.on('end', () => {
          let jsonBody = {};
          try { jsonBody = raw ? JSON.parse(raw) : {}; } catch {}
          if (res.statusCode >= 200 && res.statusCode < 300) return resolve(jsonBody);
          reject(new Error((jsonBody && jsonBody.error && jsonBody.error.message) || 'Stripe error'));
        });
      }
    );

    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function handleRegister(req, res, body) {
  if (paymentEnabled()) {
    return json(res, 403, { error: 'Registrering sker via betalningsflödet.' });
  }

  const name = String(body.name || '').trim();
  const email = normalizeEmail(body.email);
  const password = String(body.password || '');

  if (!name || !email || password.length < 6) {
    return json(res, 400, { error: 'Ogiltiga uppgifter.' });
  }

  if (findUserByEmail(email)) {
    return json(res, 409, { error: 'E-post används redan.' });
  }

  const user = createUser({ name, email, password, paidMember: false });
  const token = createSession(user.id);
  json(res, 200, { token, user: userPublic(user) });
}

function handlePaymentStatus(req, res) {
  json(res, 200, {
    enabled: paymentEnabled(),
    currency: 'sek',
    amountSek: Math.max(1, Math.floor(STRIPE_MONTHLY_PRICE_SEK / 100)),
    periodDays: 30
  });
}

async function handleCreateSignupCheckout(req, res, body) {
  if (!paymentEnabled()) {
    return json(res, 503, { error: 'Betalning är inte aktiverad på servern.' });
  }

  const name = String(body.name || '').trim();
  const email = normalizeEmail(body.email);
  const password = String(body.password || '');

  if (!name || !email || password.length < 6) {
    return json(res, 400, { error: 'Ogiltiga uppgifter.' });
  }
  if (findUserByEmail(email)) {
    return json(res, 409, { error: 'E-post används redan.' });
  }

  const pendingId = randomUUID();
  data.pendingSignups[pendingId] = {
    id: pendingId,
    name,
    email,
    password,
    createdAt: nowIso(),
    expiresAt: Date.now() + 1000 * 60 * 30,
    status: 'pending'
  };
  scheduleSave();

  const baseUrl = getBaseUrl(req);
  const session = await stripeRequest('POST', '/v1/checkout/sessions', {
    mode: 'payment',
    'line_items[0][price_data][currency]': 'sek',
    'line_items[0][price_data][unit_amount]': String(Math.max(100, STRIPE_MONTHLY_PRICE_SEK)),
    'line_items[0][price_data][product_data][name]': 'Nara full tillgång - 1 månad',
    'line_items[0][quantity]': '1',
    'metadata[pendingId]': pendingId,
    success_url: `${baseUrl}/signup.html?paid=1&pending=${encodeURIComponent(pendingId)}&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${baseUrl}/signup.html?cancel=1`
  });

  json(res, 200, { checkoutUrl: session.url });
}

async function handleCompleteSignup(req, res, body) {
  if (!paymentEnabled()) {
    return json(res, 503, { error: 'Betalning är inte aktiverad på servern.' });
  }

  const pendingId = String(body.pendingId || '').trim();
  const sessionId = String(body.sessionId || '').trim();
  if (!pendingId || !sessionId) {
    return json(res, 400, { error: 'Saknar betalningsdata.' });
  }

  const pending = data.pendingSignups[pendingId];
  if (!pending || pending.status === 'completed' || Number(pending.expiresAt || 0) < Date.now()) {
    return json(res, 410, { error: 'Registreringen har gått ut. Försök igen.' });
  }

  if (findUserByEmail(pending.email)) {
    pending.status = 'completed';
    scheduleSave();
    return json(res, 409, { error: 'E-post används redan.' });
  }

  const session = await stripeRequest('GET', `/v1/checkout/sessions/${encodeURIComponent(sessionId)}`);
  if (String(session.payment_status || '') !== 'paid') {
    return json(res, 402, { error: 'Betalningen är inte klar.' });
  }
  if (String((session.metadata && session.metadata.pendingId) || '') !== pendingId) {
    return json(res, 403, { error: 'Betalning matchar inte registreringen.' });
  }

  const user = createUser({
    name: pending.name,
    email: pending.email,
    password: pending.password,
    paidMember: true,
    paidUntilTs: Date.now() + ACCESS_PERIOD_MS
  });
  pending.status = 'completed';
  scheduleSave();
  const token = createSession(user.id);
  json(res, 200, { token, user: userPublic(user) });
}

async function handleCreateRenewCheckout(req, res, body) {
  if (!paymentEnabled()) {
    return json(res, 503, { error: 'Betalning är inte aktiverad på servern.' });
  }

  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });

  const pendingId = randomUUID();
  data.pendingRenewals[pendingId] = {
    id: pendingId,
    userId: auth.user.id,
    createdAt: nowIso(),
    expiresAt: Date.now() + 1000 * 60 * 30,
    status: 'pending'
  };
  scheduleSave();

  const baseUrl = getBaseUrl(req);
  const session = await stripeRequest('POST', '/v1/checkout/sessions', {
    mode: 'payment',
    'line_items[0][price_data][currency]': 'sek',
    'line_items[0][price_data][unit_amount]': String(Math.max(100, STRIPE_MONTHLY_PRICE_SEK)),
    'line_items[0][price_data][product_data][name]': 'Nara full tillgång - förnya 1 månad',
    'line_items[0][quantity]': '1',
    'metadata[pendingRenewalId]': pendingId,
    'metadata[userId]': String(auth.user.id),
    success_url: `${baseUrl}/pip.html?renew=1&renewal=${encodeURIComponent(pendingId)}&session_id={CHECKOUT_SESSION_ID}#memberArea`,
    cancel_url: `${baseUrl}/pip.html?renew_cancel=1#memberArea`
  });

  json(res, 200, { checkoutUrl: session.url });
}

async function handleCompleteRenew(req, res, body) {
  if (!paymentEnabled()) {
    return json(res, 503, { error: 'Betalning är inte aktiverad på servern.' });
  }

  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });

  const renewalId = String(body.renewalId || '').trim();
  const sessionId = String(body.sessionId || '').trim();
  if (!renewalId || !sessionId) return json(res, 400, { error: 'Saknar förnyelsedata.' });

  const pending = data.pendingRenewals[renewalId];
  if (!pending || pending.status === 'completed' || Number(pending.expiresAt || 0) < Date.now()) {
    return json(res, 410, { error: 'Förnyelsen har gått ut. Försök igen.' });
  }
  if (Number(pending.userId) !== Number(auth.user.id)) {
    return json(res, 403, { error: 'Förnyelsen tillhör inte detta konto.' });
  }

  const session = await stripeRequest('GET', `/v1/checkout/sessions/${encodeURIComponent(sessionId)}`);
  if (String(session.payment_status || '') !== 'paid') {
    return json(res, 402, { error: 'Betalningen är inte klar.' });
  }
  if (String((session.metadata && session.metadata.pendingRenewalId) || '') !== renewalId) {
    return json(res, 403, { error: 'Betalning matchar inte förnyelsen.' });
  }

  const now = Date.now();
  const currentPaidUntil = Number(auth.user.paidUntilTs || 0);
  auth.user.paidMember = true;
  auth.user.paidUntilTs = Math.max(now, currentPaidUntil) + ACCESS_PERIOD_MS;
  pending.status = 'completed';
  scheduleSave();
  json(res, 200, { ok: true, user: userPublic(auth.user) });
}

function handleLogin(req, res, body) {
  const email = normalizeEmail(body.email);
  const password = String(body.password || '');
  const user = findUserByEmail(email);

  if (!user || user.password !== password) {
    return json(res, 401, { error: 'Fel e-post eller lösenord.' });
  }
  const token = createSession(user.id);
  json(res, 200, { token, user: userPublic(user), membershipExpired: !membershipActive(user) });
}

function handleMe(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  json(res, 200, { user: userPublic(auth.user) });
}

function handleLogout(req, res, body) {
  const token = String(body.token || '');
  if (token && data.sessions[token]) {
    delete data.sessions[token];
    scheduleSave();
  }
  json(res, 200, { ok: true });
}

function handleProfileGet(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const profile = data.profiles[auth.user.id] || { age: '', bio: '', imageData: '' };
  json(res, 200, { profile });
}

function handleProfileSave(req, res, body) {
  const auth = authFrom(req, body, null);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const age = String(body.age || '').slice(0, 3);
  const bio = String(body.bio || '').slice(0, 600);
  const imageData = String(body.imageData || '').slice(0, 500_000);
  data.profiles[auth.user.id] = { age, bio, imageData, updatedAt: nowIso() };
  scheduleSave();
  json(res, 200, { ok: true });
}

function handleInboxGet(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  json(res, 200, { inbox: ensureInbox(auth.user.id) });
}

function handleChatSend(req, res, body) {
  const auth = authFrom(req, body, null);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const text = String(body.text || '').trim();
  if (!text) return json(res, 400, { error: 'Meddelande saknas.' });

  const item = {
    id: data.nextIds.chat++,
    fromUserId: auth.user.id,
    fromName: auth.user.name,
    text: text.slice(0, 500),
    createdAt: nowIso()
  };
  data.chat.push(item);
  if (data.chat.length > 500) data.chat = data.chat.slice(-500);

  data.users.forEach((u) => {
    if (u.id !== auth.user.id) {
      addInboxMessage(u.id, auth.user.name, 'Nytt chattmeddelande', text.slice(0, 140));
    }
  });
  scheduleSave();
  json(res, 200, { ok: true, message: item });
}

function handleChatGet(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const sinceId = Number(urlObj.searchParams.get('sinceId') || '0');
  const messages = data.chat.filter((m) => m.id > sinceId).slice(-120);
  const latestId = data.chat.length ? data.chat[data.chat.length - 1].id : sinceId;
  json(res, 200, { messages, latestId });
}

function handlePresencePing(req, res, body) {
  const auth = authFrom(req, body, null);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  auth.session.lastSeen = Date.now();
  scheduleSave();
  json(res, 200, { ok: true });
}

function handleOnline(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const now = Date.now();
  const activeUsers = new Map();

  Object.values(data.sessions).forEach((session) => {
    if (now - Number(session.lastSeen || 0) > 15000) return;
    const user = data.users.find((u) => u.id === session.userId);
    if (!user) return;
    const prev = activeUsers.get(user.id);
    if (!prev || Number(session.lastSeen) > Number(prev.lastSeen)) {
      activeUsers.set(user.id, { id: user.id, name: user.name, lastSeen: session.lastSeen });
    }
  });

  const users = Array.from(activeUsers.values()).sort((a, b) => Number(b.lastSeen) - Number(a.lastSeen));
  json(res, 200, { users });
}

function handleUserSearch(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const q = String(urlObj.searchParams.get('q') || '').trim().toLowerCase();
  const users = data.users
    .map((u) => {
      const p = data.profiles[u.id] || {};
      return {
        id: u.id,
        name: u.name,
        age: p.age || '',
        bio: p.bio || '',
        email: u.email
      };
    })
    .filter((u) => {
      if (!q) return true;
      return u.name.toLowerCase().includes(q) || String(u.bio).toLowerCase().includes(q);
    })
    .slice(0, 30);

  json(res, 200, { users });
}

function dmKey(a, b) {
  const x = Number(a);
  const y = Number(b);
  return x < y ? `${x}:${y}` : `${y}:${x}`;
}

function handleDmThread(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const withUserId = Number(urlObj.searchParams.get('withUserId') || '0');
  if (!withUserId || withUserId === auth.user.id) {
    return json(res, 400, { error: 'Ogiltig mottagare.' });
  }

  const key = dmKey(auth.user.id, withUserId);
  const sinceId = Number(urlObj.searchParams.get('sinceId') || '0');
  const thread = data.dms.filter((m) => m.key === key && Number(m.id) > sinceId).slice(-150);
  const latestId = data.dms.length ? Number(data.dms[data.dms.length - 1].id) : sinceId;
  json(res, 200, { messages: thread, latestId });
}

function handleDmSend(req, res, body) {
  const auth = authFrom(req, body, null);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const toUserId = Number(body.toUserId || 0);
  const text = String(body.text || '').trim();
  if (!toUserId || toUserId === auth.user.id || !text) {
    return json(res, 400, { error: 'Ogiltigt meddelande.' });
  }

  const recipient = data.users.find((u) => Number(u.id) === toUserId);
  if (!recipient) return json(res, 404, { error: 'Mottagare hittades inte.' });

  const item = {
    id: data.nextIds.dm++,
    key: dmKey(auth.user.id, toUserId),
    fromUserId: auth.user.id,
    fromName: auth.user.name,
    toUserId,
    text: text.slice(0, 1200),
    createdAt: nowIso()
  };
  data.dms.push(item);
  if (data.dms.length > 5000) data.dms = data.dms.slice(-5000);

  addInboxMessage(recipient.id, auth.user.name, 'Nytt privat meddelande', text.slice(0, 140));
  scheduleSave();
  json(res, 200, { ok: true, message: item });
}

function getOrCreateRoom(code) {
  if (!rooms.has(code)) {
    rooms.set(code, {
      clients: new Map(),
      events: [],
      nextSeq: 1,
      lastTouched: Date.now()
    });
  }
  const room = rooms.get(code);
  room.lastTouched = Date.now();
  return room;
}

function cleanupRooms() {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    if (now - room.lastTouched > 1000 * 60 * 60) {
      rooms.delete(code);
    }
  }
}
setInterval(cleanupRooms, 1000 * 60 * 5).unref();
setInterval(cleanupSessions, 1000 * 60 * 10).unref();
setInterval(cleanupPendingSignups, 1000 * 60 * 10).unref();
setInterval(cleanupPendingRenewals, 1000 * 60 * 10).unref();

function handleJoin(req, res, body) {
  const code = safeCode(body.roomCode);
  const room = getOrCreateRoom(code);

  const currentCount = room.clients.size;
  if (currentCount >= 2) {
    return json(res, 409, { error: 'Rummet ar fullt (max 2 spelare).' });
  }

  const clientId = randomUUID();
  const role = currentCount === 0 ? 'host' : 'guest';
  room.clients.set(clientId, { role, joinedAt: Date.now() });

  json(res, 200, { roomCode: code, clientId, role });
}

function handleLeave(req, res, body) {
  const code = safeCode(body.roomCode);
  const clientId = String(body.clientId || '');
  const room = rooms.get(code);
  if (!room) return json(res, 200, { ok: true });

  room.clients.delete(clientId);
  room.lastTouched = Date.now();

  room.events.push({
    seq: room.nextSeq++,
    from: 'server',
    to: 'all',
    type: 'peer-left',
    payload: { clientId }
  });

  if (room.clients.size === 0) {
    rooms.delete(code);
  }

  json(res, 200, { ok: true });
}

function handleSignal(req, res, body) {
  const code = safeCode(body.roomCode);
  const clientId = String(body.clientId || '');
  const to = String(body.to || 'peer');
  const type = String(body.type || '');
  const payload = body.payload || {};

  const room = rooms.get(code);
  if (!room || !room.clients.has(clientId)) {
    return json(res, 400, { error: 'Ogiltig room/client.' });
  }

  room.lastTouched = Date.now();
  room.events.push({
    seq: room.nextSeq++,
    from: clientId,
    to,
    type,
    payload
  });

  json(res, 200, { ok: true });
}

function handlePoll(req, res, urlObj) {
  const code = safeCode(urlObj.searchParams.get('roomCode'));
  const clientId = String(urlObj.searchParams.get('clientId') || '');
  const since = Number(urlObj.searchParams.get('since') || '0');
  const room = rooms.get(code);

  if (!room || !room.clients.has(clientId)) {
    return json(res, 200, { events: [], now: since });
  }

  room.lastTouched = Date.now();

  const events = room.events.filter((e) => {
    if (e.seq <= since) return false;
    if (e.from === clientId) return false;
    if (e.to === 'all') return true;
    if (e.to === 'peer') return true;
    return e.to === clientId;
  });

  json(res, 200, {
    events,
    now: room.nextSeq - 1,
    peers: Array.from(room.clients.entries()).map(([id, c]) => ({ id, role: c.role }))
  });
}

function serveStatic(req, res, pathname) {
  const target = pathname === '/' ? INDEX_PATH : path.join(ROOT, pathname.replace(/^\/+/, ''));
  const resolved = path.resolve(target);
  if (!resolved.startsWith(path.resolve(ROOT))) {
    res.writeHead(403, CORS_HEADERS);
    res.end('Forbidden');
    return;
  }

  fs.readFile(resolved, (err, fileData) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8', ...CORS_HEADERS });
      res.end('Not found');
      return;
    }

    const ext = path.extname(resolved).toLowerCase();
    const typeMap = {
      '.html': 'text/html; charset=utf-8',
      '.js': 'text/javascript; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.json': 'application/json; charset=utf-8',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml'
    };

    res.writeHead(200, {
      'Content-Type': typeMap[ext] || 'application/octet-stream',
      'Cache-Control': 'no-store',
      ...CORS_HEADERS
    });
    res.end(fileData);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const pathname = urlObj.pathname;
    if (req.method === 'OPTIONS') {
      res.writeHead(204, CORS_HEADERS);
      res.end();
      return;
    }

    // Social API
    if (req.method === 'GET' && pathname === '/api/payments/status') return handlePaymentStatus(req, res);
    if (req.method === 'POST' && pathname === '/api/payments/create-signup-checkout') return handleCreateSignupCheckout(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/payments/complete-signup') return handleCompleteSignup(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/payments/create-renew-checkout') return handleCreateRenewCheckout(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/payments/complete-renew') return handleCompleteRenew(req, res, await parseBody(req));

    if (req.method === 'POST' && pathname === '/api/auth/register') return handleRegister(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/auth/login') return handleLogin(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/auth/me') return handleMe(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/auth/logout') return handleLogout(req, res, await parseBody(req));

    if (req.method === 'GET' && pathname === '/api/profile') return handleProfileGet(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/profile/save') return handleProfileSave(req, res, await parseBody(req));

    if (req.method === 'GET' && pathname === '/api/inbox') return handleInboxGet(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/chat/send') return handleChatSend(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/chat') return handleChatGet(req, res, {}, urlObj);

    if (req.method === 'POST' && pathname === '/api/presence/ping') return handlePresencePing(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/online') return handleOnline(req, res, {}, urlObj);

    if (req.method === 'GET' && pathname === '/api/users/search') return handleUserSearch(req, res, {}, urlObj);
    if (req.method === 'GET' && pathname === '/api/dm/thread') return handleDmThread(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/dm/send') return handleDmSend(req, res, await parseBody(req));

    // Existing game signaling API
    if (req.method === 'POST' && pathname === '/api/join') return handleJoin(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/leave') return handleLeave(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/signal') return handleSignal(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/poll') return handlePoll(req, res, urlObj);

    if (req.method === 'GET') return serveStatic(req, res, pathname);

    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8', ...CORS_HEADERS });
    res.end('Method Not Allowed');
  } catch (err) {
    json(res, 500, { error: err.message || 'Internal error' });
  }
});

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
