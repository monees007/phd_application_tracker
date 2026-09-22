/**
 * Writes positions through the Firestore REST API.
 *
 * The document shape must match `Position.toMap()` in the Flutter app field
 * for field, and must satisfy `firestore.rules` — which caps several string
 * lengths and validates the status enum. A mismatch here surfaces as a 403
 * that looks like an auth problem, so the caps are enforced before sending.
 */

import { getIdToken, getConfig } from './auth.js';

const BASE = 'https://firestore.googleapis.com/v1';

/** Limits copied from firestore.rules. Exceeding one means a rejected write. */
const LIMITS = {
  university: 200,
  programme: 500,
  notes: 40000,
  link: 2000,
  tags: 20,
};

const STATUSES = [
  'notApplied',
  'applied',
  'interview',
  'accepted',
  'rejected',
  'withdrawn',
];

function clip(value, max) {
  const s = (value ?? '').toString();
  return s.length > max ? `${s.slice(0, max - 1)}\u2026` : s;
}

// ---- typed-value helpers -------------------------------------------------

const str = (v) => ({ stringValue: v ?? '' });
const bool = (v) => ({ booleanValue: !!v });
const nul = () => ({ nullValue: null });
const num = (v) => ({ doubleValue: v });
const ts = (d) => ({ timestampValue: new Date(d).toISOString() });
const arr = (values) => ({ arrayValue: { values } });
const map = (fields) => ({ mapValue: { fields } });

const strOrNull = (v) =>
  v === null || v === undefined || v === '' ? nul() : str(v);
const numOrNull = (v) =>
  v === null || v === undefined || Number.isNaN(v) ? nul() : num(v);
const boolOrNull = (v) => (v === null || v === undefined ? nul() : bool(v));

/**
 * Builds the Firestore document for a position.
 *
 * @param {object} p plain fields, already extracted and cleaned
 */
export function buildDocument(p) {
  const now = new Date();
  const status = STATUSES.includes(p.status) ? p.status : 'notApplied';

  const university = clip(p.university || 'Shared advert', LIMITS.university);
  const programme = clip(p.programme, LIMITS.programme);
  const notes = clip(p.notes, LIMITS.notes);
  const tags = (p.tags || []).slice(0, LIMITS.tags).map((t) => str(t));

  return {
    fields: {
      university: str(university),
      programme: str(programme),
      deadline: p.deadline ? ts(p.deadline) : nul(),
      deadlineYearAssumed: bool(p.deadlineYearAssumed),
      funded: boolOrNull(p.funded),
      applicationFee: numOrNull(p.applicationFee),
      feeCurrency: strOrNull(p.feeCurrency),
      link: str(clip(p.link, LIMITS.link)),
      status: str(status),
      notes: str(notes),
      tags: arr(tags),
      country: strOrNull(p.country),
      appliedAt: nul(),
      resultAt: nul(),
      createdAt: ts(now),
      updatedAt: ts(now),
      archived: bool(false),
      reminderEnabled: bool(true),
      history: arr([
        map({ status: str(status), at: ts(now) }),
      ]),
      // Notes are deliberately excluded: they archive the full advert, and
      // including them here would roughly double every document for a field
      // the app does not read back.
      searchIndex: str(
        `${university} ${programme} ${(p.tags || []).join(' ')}`.toLowerCase()
      ),
    },
  };
}

/** Creates a position and returns its document id. */
export async function createPosition(position) {
  const { projectId, uid } = await getConfig();
  if (!projectId) throw new Error('No Firebase project ID saved.');
  if (!uid) throw new Error('Not signed in.');

  const token = await getIdToken();
  const url =
    `${BASE}/projects/${encodeURIComponent(projectId)}` +
    `/databases/(default)/documents/users/${encodeURIComponent(uid)}/positions`;

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(buildDocument(position)),
  });

  const body = await res.json();
  if (!res.ok) {
    const message = body?.error?.message || `HTTP ${res.status}`;
    if (res.status === 403) {
      throw new Error(
        `Firestore refused the write. Usually the security rules, or the ` +
          `project ID not matching the signed-in account. (${message})`
      );
    }
    throw new Error(`Firestore error: ${message}`);
  }

  // name is .../documents/users/{uid}/positions/{docId}
  return (body.name || '').split('/').pop();
}
