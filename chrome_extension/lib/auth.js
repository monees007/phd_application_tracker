/**
 * Firebase Auth over REST.
 *
 * The Firebase JS SDK is deliberately not used: it is large, and in a
 * Manifest V3 service worker its auth persistence fights with the worker
 * being torn down between events. Two REST endpoints do everything needed
 * here, with no build step and no bundler.
 *
 * Only a refresh token is stored, never the password. Sign-in happens once on
 * the options page; after that an ID token is minted on demand and cached in
 * memory for the life of the worker.
 */

import { DEFAULTS } from '../config.js';

const SIGN_IN =
  'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const SIGN_UP =
  'https://identitytoolkit.googleapis.com/v1/accounts:signUp';
const REFRESH = 'https://securetoken.googleapis.com/v1/token';

let cachedToken = null;
let cachedExpiry = 0;

export async function getConfig() {
  const stored = await chrome.storage.local.get([
    'apiKey',
    'projectId',
    'refreshToken',
    'uid',
    'email',
    'geminiKey',
    'geminiModel',
  ]);

  // A stored value wins, but only when it is actually set — an empty string
  // in storage must not blank out a baked-in default.
  const pick = (key) =>
    stored[key] && String(stored[key]).length > 0 ? stored[key] : DEFAULTS[key];

  return {
    ...stored,
    projectId: pick('projectId'),
    apiKey: pick('apiKey'),
    geminiKey: pick('geminiKey'),
    geminiModel: pick('geminiModel'),
  };
}

export async function signIn(apiKey, email, password) {
  const res = await fetch(`${SIGN_IN}?key=${encodeURIComponent(apiKey)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });

  const body = await res.json();
  if (!res.ok) {
    throw new Error(describeAuthError(body?.error?.message));
  }

  await chrome.storage.local.set({
    refreshToken: body.refreshToken,
    uid: body.localId,
    email,
  });

  cachedToken = body.idToken;
  cachedExpiry = Date.now() + Number(body.expiresIn || 3600) * 1000;

  return { uid: body.localId };
}

/**
 * Creates an account on the configured project.
 *
 * Needed once the extension ships with a project baked in: a new user has
 * nowhere to sign in from otherwise. Existing app users should sign in
 * instead, so both clients land on the same uid.
 */
export async function register(apiKey, email, password) {
  const res = await fetch(`${SIGN_UP}?key=${encodeURIComponent(apiKey)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });

  const body = await res.json();
  if (!res.ok) throw new Error(describeAuthError(body?.error?.message));

  await chrome.storage.local.set({
    refreshToken: body.refreshToken,
    uid: body.localId,
    email,
  });

  cachedToken = body.idToken;
  cachedExpiry = Date.now() + Number(body.expiresIn || 3600) * 1000;
  return { uid: body.localId };
}

export async function signOut() {
  cachedToken = null;
  cachedExpiry = 0;
  await chrome.storage.local.remove(['refreshToken', 'uid', 'email']);
}

/** A valid ID token, refreshed if the cached one is close to expiring. */
export async function getIdToken() {
  // 60s of slack so a token cannot expire mid-request.
  if (cachedToken && Date.now() < cachedExpiry - 60_000) return cachedToken;

  const { apiKey, refreshToken } = await getConfig();
  if (!apiKey) throw new Error('No Firebase Web API key saved. Open settings.');
  if (!refreshToken) throw new Error('Not signed in. Open settings.');

  const res = await fetch(`${REFRESH}?key=${encodeURIComponent(apiKey)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    }),
  });

  const body = await res.json();
  if (!res.ok) {
    // A revoked or expired refresh token cannot be recovered from silently.
    await signOut();
    throw new Error('Sign-in expired. Open settings and sign in again.');
  }

  cachedToken = body.id_token;
  cachedExpiry = Date.now() + Number(body.expires_in || 3600) * 1000;
  return cachedToken;
}

function describeAuthError(code) {
  switch (code) {
    case 'EMAIL_NOT_FOUND':
    case 'INVALID_PASSWORD':
    case 'INVALID_LOGIN_CREDENTIALS':
      return 'Email or password is incorrect.';
    case 'USER_DISABLED':
      return 'That account is disabled.';
    case 'INVALID_EMAIL':
      return 'That email address is not valid.';
    case 'OPERATION_NOT_ALLOWED':
      return 'Email/password sign-in is not enabled on the Firebase project.';
    case 'EMAIL_EXISTS':
      return 'An account already exists for that email — sign in instead.';
    case 'WEAK_PASSWORD : Password should be at least 6 characters':
      return 'Password must be at least 6 characters.';
    default:
      return code || 'Sign-in failed.';
  }
}
