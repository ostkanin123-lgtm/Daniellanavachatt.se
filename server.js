const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const querystring = require('querystring');
const { randomUUID, createHash } = require('crypto');

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const ROOT = __dirname;
const INDEX_PATH = path.join(ROOT, 'index.html');
const DATA_PATH = path.join(ROOT, 'social-data.json');
const STRIPE_SECRET_KEY = String(process.env.STRIPE_SECRET_KEY || '');
const PUBLIC_BASE_URL = String(process.env.PUBLIC_BASE_URL || '').trim();
const STRIPE_MONTHLY_PRICE_SEK = Number(process.env.STRIPE_MONTHLY_PRICE_SEK || process.env.STRIPE_SIGNUP_PRICE_SEK || 7900);
const ACCESS_PERIOD_MS = 1000 * 60 * 60 * 24 * 30;
const TRIAL_LIMIT_PER_IP = Number(process.env.TRIAL_LIMIT_PER_IP || 2);
const TRIAL_PERIOD_MS = Number(process.env.TRIAL_PERIOD_MS || 1000 * 60 * 60 * 24 * 5);

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
    blocks: {},
    verifications: {},
    ipTrialUsage: {},
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
  const now = Date.now();
  const trialEndsAt = Number(user.trialEndsAt || 0);
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    phone: user.phone || '',
    birthDate: user.birthDate || '',
    birthPlace: user.birthPlace || '',
    emailVerified: !!user.emailVerified,
    phoneVerified: !!user.phoneVerified,
    selfieVerified: !!user.selfieVerified,
    trialCount: Number(user.trialCount || 0),
    trialEndsAt,
    trialRemainingMs: trialEndsAt > now ? trialEndsAt - now : 0,
    trialLimit: TRIAL_LIMIT_PER_IP,
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
  const trialEndsAt = Number(user.trialEndsAt || 0);
  if (trialEndsAt > Date.now()) return true;
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

function ensureBlockList(userId) {
  const key = String(userId);
  if (!Array.isArray(data.blocks[key])) data.blocks[key] = [];
  return data.blocks[key];
}

function isBlocked(blockerUserId, targetUserId) {
  const list = ensureBlockList(blockerUserId);
  return list.includes(Number(targetUserId));
}

function isBlockedEither(a, b) {
  return isBlocked(a, b) || isBlocked(b, a);
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

function clientIpFromReq(req) {
  const xff = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  const xri = String(req.headers['x-real-ip'] || '').trim();
  const raw = xff || xri || String((req.socket && req.socket.remoteAddress) || '');
  const unwrapped = raw.replace(/^::ffff:/, '').trim();
  return unwrapped || '0.0.0.0';
}

function hashIp(ip) {
  return createHash('sha256').update(String(ip || '')).digest('hex');
}

function getIpTrialRecord(req) {
  const ipHash = hashIp(clientIpFromReq(req));
  if (!data.ipTrialUsage[ipHash]) {
    data.ipTrialUsage[ipHash] = { count: 0, updatedAt: nowIso() };
  }
  return { ipHash, rec: data.ipTrialUsage[ipHash] };
}

function canUseTrial(req, user) {
  const { rec } = getIpTrialRecord(req);
  const userTrials = Number((user && user.trialCount) || 0);
  const ipTrials = Number(rec.count || 0);
  const remainingByIp = Math.max(0, TRIAL_LIMIT_PER_IP - ipTrials);
  const remainingByUser = Math.max(0, TRIAL_LIMIT_PER_IP - userTrials);
  return {
    ok: remainingByIp > 0 && remainingByUser > 0,
    remainingByIp,
    remainingByUser
  };
}

function consumeTrial(req, user) {
  const trialCheck = canUseTrial(req, user);
  if (!trialCheck.ok) {
    return { ok: false, error: 'Gratis testperioder är slut för denna anslutning.' };
  }
  const { rec } = getIpTrialRecord(req);
  rec.count = Number(rec.count || 0) + 1;
  rec.updatedAt = nowIso();
  user.trialCount = Number(user.trialCount || 0) + 1;
  user.trialEndsAt = Date.now() + TRIAL_PERIOD_MS;
  scheduleSave();
  return { ok: true };
}

function ensureVerificationState(userId) {
  const key = String(userId);
  if (!data.verifications[key]) {
    data.verifications[key] = {
      email: { code: '', expiresAt: 0 },
      sms: { code: '', expiresAt: 0 }
    };
  }
  return data.verifications[key];
}

function parseBirthData(body) {
  const birthDate = String(body.birthDate || '').trim();
  const birthPlace = String(body.birthPlace || '').trim().slice(0, 80);
  if (!birthDate || !birthPlace) {
    return { ok: false, error: 'Fyll i födelsedatum och var du är född.' };
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) {
    return { ok: false, error: 'Födelsedatum måste vara i formatet YYYY-MM-DD.' };
  }
  const ts = Date.parse(`${birthDate}T00:00:00Z`);
  if (!Number.isFinite(ts) || ts > Date.now()) {
    return { ok: false, error: 'Ogiltigt födelsedatum.' };
  }
  return { ok: true, birthDate, birthPlace };
}

function ageFromBirthDate(birthDate) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(birthDate || ''))) return '';
  const [y, m, d] = String(birthDate).split('-').map((n) => Number(n));
  if (!y || !m || !d) return '';
  const now = new Date();
  let age = now.getUTCFullYear() - y;
  const monthDiff = (now.getUTCMonth() + 1) - m;
  const dayDiff = now.getUTCDate() - d;
  if (monthDiff < 0 || (monthDiff === 0 && dayDiff < 0)) age -= 1;
  if (!Number.isFinite(age) || age < 0 || age > 130) return '';
  return String(age);
}

function parsePhone(phone) {
  const raw = String(phone || '').trim();
  const normalized = raw.replace(/[^\d+]/g, '');
  if (!normalized || normalized.length < 7) return { ok: false, error: 'Fyll i ett giltigt telefonnummer.' };
  return { ok: true, phone: normalized.slice(0, 20) };
}

function createUser({ name, email, password, phone, birthDate, birthPlace, paidMember, paidUntilTs }) {
  const initialAge = ageFromBirthDate(birthDate);
  const user = {
    id: data.nextIds.user++,
    name,
    email,
    password,
    phone: String(phone || ''),
    birthDate: String(birthDate || ''),
    birthPlace: String(birthPlace || ''),
    emailVerified: false,
    phoneVerified: false,
    selfieVerified: false,
    trialCount: 0,
    trialEndsAt: 0,
    paidMember: !!paidMember,
    paidUntilTs: Number(paidUntilTs || 0),
    createdAt: nowIso()
  };
  data.users.push(user);
  data.profiles[user.id] = { age: initialAge, bio: '', imageData: '', updatedAt: nowIso() };
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
  const trialRequested = !!body.startTrial;

  const name = String(body.name || '').trim();
  const email = normalizeEmail(body.email);
  const password = String(body.password || '');
  const phoneInfo = parsePhone(body.phone);
  const birthInfo = parseBirthData(body);

  if (!name || !email || password.length < 6 || !birthInfo.ok || !phoneInfo.ok) {
    return json(res, 400, { error: birthInfo.error || phoneInfo.error || 'Ogiltiga uppgifter.' });
  }

  if (findUserByEmail(email)) {
    return json(res, 409, { error: 'E-post används redan.' });
  }

  const user = createUser({
    name,
    email,
    password,
    phone: phoneInfo.phone,
    birthDate: birthInfo.birthDate,
    birthPlace: birthInfo.birthPlace,
    paidMember: false
  });
  if (paymentEnabled() && trialRequested) {
    const trial = consumeTrial(req, user);
    if (!trial.ok) {
      data.users = data.users.filter((u) => Number(u.id) !== Number(user.id));
      delete data.profiles[user.id];
      return json(res, 403, { error: trial.error });
    }
  }
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
  const phoneInfo = parsePhone(body.phone);
  const birthInfo = parseBirthData(body);

  if (!name || !email || password.length < 6 || !birthInfo.ok || !phoneInfo.ok) {
    return json(res, 400, { error: birthInfo.error || phoneInfo.error || 'Ogiltiga uppgifter.' });
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
    phone: phoneInfo.phone,
    birthDate: birthInfo.birthDate,
    birthPlace: birthInfo.birthPlace,
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
    phone: pending.phone,
    birthDate: pending.birthDate,
    birthPlace: pending.birthPlace,
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

function verificationComplete(user) {
  return !!user.emailVerified && !!user.phoneVerified && !!user.selfieVerified;
}

function randomCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function handleVerifyStatus(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  json(res, 200, {
    emailVerified: !!auth.user.emailVerified,
    phoneVerified: !!auth.user.phoneVerified,
    selfieVerified: !!auth.user.selfieVerified,
    complete: verificationComplete(auth.user)
  });
}

function handleVerifyEmailSend(req, res, body) {
  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const state = ensureVerificationState(auth.user.id);
  const code = randomCode();
  state.email = { code, expiresAt: Date.now() + 1000 * 60 * 10 };
  addInboxMessage(auth.user.id, 'Nara Verify', 'E-postkod', `Din kod är: ${code}`);
  scheduleSave();
  json(res, 200, { ok: true, message: 'Kod skickad till din verifieringsbrevlåda.' });
}

function handleVerifyEmailConfirm(req, res, body) {
  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const code = String(body.code || '').trim();
  const state = ensureVerificationState(auth.user.id);
  if (!code || Date.now() > Number(state.email.expiresAt || 0) || code !== String(state.email.code || '')) {
    return json(res, 400, { error: 'Fel eller utgången e-postkod.' });
  }
  auth.user.emailVerified = true;
  state.email = { code: '', expiresAt: 0 };
  scheduleSave();
  json(res, 200, { ok: true, user: userPublic(auth.user) });
}

function handleVerifySmsSend(req, res, body) {
  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const state = ensureVerificationState(auth.user.id);
  const code = randomCode();
  state.sms = { code, expiresAt: Date.now() + 1000 * 60 * 10 };
  addInboxMessage(auth.user.id, 'Nara Verify', 'SMS-kod', `Din SMS-kod är: ${code}`);
  scheduleSave();
  json(res, 200, { ok: true, message: 'SMS-kod skickad (demo i brevlådan).' });
}

function handleVerifySmsConfirm(req, res, body) {
  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const code = String(body.code || '').trim();
  const state = ensureVerificationState(auth.user.id);
  if (!code || Date.now() > Number(state.sms.expiresAt || 0) || code !== String(state.sms.code || '')) {
    return json(res, 400, { error: 'Fel eller utgången SMS-kod.' });
  }
  auth.user.phoneVerified = true;
  state.sms = { code: '', expiresAt: 0 };
  scheduleSave();
  json(res, 200, { ok: true, user: userPublic(auth.user) });
}

function handleVerifySelfie(req, res, body) {
  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const imageData = String(body.imageData || '').slice(0, 500_000);
  if (!imageData.startsWith('data:image/')) {
    return json(res, 400, { error: 'Ogiltig selfie-bild.' });
  }
  const profile = data.profiles[auth.user.id] || { age: '', bio: '', imageData: '' };
  profile.selfieData = imageData;
  profile.updatedAt = nowIso();
  data.profiles[auth.user.id] = profile;
  auth.user.selfieVerified = true;
  scheduleSave();
  json(res, 200, { ok: true, user: userPublic(auth.user) });
}

function handleTrialStart(req, res, body) {
  const auth = authFrom(req, body, null, { allowExpiredMembership: true });
  if (!auth.ok) return json(res, 401, { error: auth.error });
  if (membershipActive(auth.user)) {
    return json(res, 400, { error: 'Du har redan aktiv tillgång.' });
  }
  const trial = consumeTrial(req, auth.user);
  if (!trial.ok) return json(res, 403, { error: trial.error });
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
  if (!profile.age && auth.user.birthDate) {
    profile.age = ageFromBirthDate(auth.user.birthDate);
    data.profiles[auth.user.id] = profile;
    scheduleSave();
  }
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
    if (u.id !== auth.user.id && !isBlockedEither(auth.user.id, u.id)) {
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
  const messages = data.chat
    .filter((m) => m.id > sinceId && !isBlockedEither(auth.user.id, m.fromUserId))
    .slice(-120);
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
    if (isBlockedEither(auth.user.id, user.id)) return;
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
      if (Number(u.id) === Number(auth.user.id)) return false;
      if (isBlockedEither(auth.user.id, u.id)) return false;
      if (!q) return true;
      return u.name.toLowerCase().includes(q) || String(u.bio).toLowerCase().includes(q);
    })
    .slice(0, 30);

  json(res, 200, { users });
}

function handleBlockedGet(req, res, body, urlObj) {
  const auth = authFrom(req, body, urlObj);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const blockedIds = ensureBlockList(auth.user.id);
  const users = blockedIds
    .map((id) => data.users.find((u) => Number(u.id) === Number(id)))
    .filter(Boolean)
    .map((u) => ({ id: u.id, name: u.name, email: u.email }));
  json(res, 200, { users });
}

function handleBlockUser(req, res, body) {
  const auth = authFrom(req, body, null);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const targetUserId = Number(body.targetUserId || 0);
  if (!targetUserId || targetUserId === auth.user.id) {
    return json(res, 400, { error: 'Ogiltig användare.' });
  }
  const target = data.users.find((u) => Number(u.id) === targetUserId);
  if (!target) return json(res, 404, { error: 'Användaren hittades inte.' });
  const list = ensureBlockList(auth.user.id);
  if (!list.includes(targetUserId)) list.push(targetUserId);

  data.dms = data.dms.filter((m) => {
    const a = Number(m.fromUserId);
    const b = Number(m.toUserId);
    return !((a === Number(auth.user.id) && b === targetUserId) || (a === targetUserId && b === Number(auth.user.id)));
  });
  scheduleSave();
  json(res, 200, { ok: true });
}

function handleUnblockUser(req, res, body) {
  const auth = authFrom(req, body, null);
  if (!auth.ok) return json(res, 401, { error: auth.error });
  const targetUserId = Number(body.targetUserId || 0);
  const list = ensureBlockList(auth.user.id);
  data.blocks[String(auth.user.id)] = list.filter((id) => Number(id) !== targetUserId);
  scheduleSave();
  json(res, 200, { ok: true });
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
  if (isBlockedEither(auth.user.id, withUserId)) {
    return json(res, 403, { error: 'Du kan inte chatta med denna användare.' });
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
  if (isBlockedEither(auth.user.id, toUserId)) {
    return json(res, 403, { error: 'Meddelande blockerat.' });
  }

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
    if (req.method === 'POST' && pathname === '/api/auth/trial/start') return handleTrialStart(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/verify/status') return handleVerifyStatus(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/verify/email/send') return handleVerifyEmailSend(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/verify/email/confirm') return handleVerifyEmailConfirm(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/verify/sms/send') return handleVerifySmsSend(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/verify/sms/confirm') return handleVerifySmsConfirm(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/verify/selfie') return handleVerifySelfie(req, res, await parseBody(req));

    if (req.method === 'GET' && pathname === '/api/profile') return handleProfileGet(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/profile/save') return handleProfileSave(req, res, await parseBody(req));

    if (req.method === 'GET' && pathname === '/api/inbox') return handleInboxGet(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/chat/send') return handleChatSend(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/chat') return handleChatGet(req, res, {}, urlObj);

    if (req.method === 'POST' && pathname === '/api/presence/ping') return handlePresencePing(req, res, await parseBody(req));
    if (req.method === 'GET' && pathname === '/api/online') return handleOnline(req, res, {}, urlObj);

    if (req.method === 'GET' && pathname === '/api/users/search') return handleUserSearch(req, res, {}, urlObj);
    if (req.method === 'GET' && pathname === '/api/users/blocked') return handleBlockedGet(req, res, {}, urlObj);
    if (req.method === 'POST' && pathname === '/api/users/block') return handleBlockUser(req, res, await parseBody(req));
    if (req.method === 'POST' && pathname === '/api/users/unblock') return handleUnblockUser(req, res, await parseBody(req));
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
