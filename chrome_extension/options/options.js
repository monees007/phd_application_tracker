import { signIn, register, signOut, getConfig } from '../lib/auth.js';
import { HAS_BAKED_PROJECT } from '../config.js';

const $ = (id) => document.getElementById(id);
const status = $('status');

function say(message, ok = true) {
  status.textContent = message;
  status.className = ok ? 'ok' : 'err';
}

async function load() {
  const c = await getConfig();

  // A released build already knows its project, so the Firebase fields are
  // noise for almost everyone. They stay reachable behind the toggle for
  // anyone pointing this at their own project.
  if (HAS_BAKED_PROJECT) {
    document.getElementById('firebase-section').hidden = true;
    document.getElementById('advanced-toggle').hidden = false;
  }

  $('projectId').value = c.projectId || '';
  $('apiKey').value = c.apiKey || '';
  $('geminiKey').value = c.geminiKey || '';
  $('geminiModel').value = c.geminiModel || '';
  $('email').value = c.email || '';
  if (c.uid) say(`Signed in as ${c.email} (${c.uid.slice(0, 8)}\u2026)`);
}

$('save').addEventListener('click', async () => {
  await chrome.storage.local.set({
    projectId: $('projectId').value.trim(),
    apiKey: $('apiKey').value.trim(),
    geminiKey: $('geminiKey').value.trim(),
    geminiModel: $('geminiModel').value.trim(),
  });
  say('Settings saved.');
});

document.getElementById('advanced-toggle')?.addEventListener('click', () => {
  const box = document.getElementById('firebase-section');
  box.hidden = !box.hidden;
});

async function authenticate(fn) {
  const c = await getConfig();
  const apiKey = $('apiKey').value.trim() || c.apiKey;
  const projectId = $('projectId').value.trim() || c.projectId;
  if (!apiKey || !projectId) {
    return say('No Firebase project configured. Open Advanced.', false);
  }

  // Persist before authenticating, so a successful sign-in is never stranded
  // without the project it belongs to.
  await chrome.storage.local.set({ apiKey, projectId });

  try {
    const { uid } = await fn(apiKey, $('email').value.trim(), $('password').value);
    $('password').value = '';
    say(`Signed in. Entries save to user ${uid.slice(0, 8)}\u2026`);
  } catch (e) {
    say(e.message, false);
  }
}

$('signup').addEventListener('click', () => authenticate(register));

$('signin').addEventListener('click', () => authenticate(signIn));

$('signout').addEventListener('click', async () => {
  await signOut();
  say('Signed out.');
});

$('models').addEventListener('click', async () => {
  const key = $('geminiKey').value.trim();
  if (!key) return say('Enter a Gemini key first.', false);
  try {
    const res = await fetch('https://generativelanguage.googleapis.com/v1beta/models', {
      headers: { 'x-goog-api-key': key },
    });
    const body = await res.json();
    if (!res.ok) throw new Error(body?.error?.message || `HTTP ${res.status}`);
    const names = (body.models || [])
      .filter((m) => (m.supportedGenerationMethods || []).includes('generateContent'))
      .map((m) => m.name.replace('models/', ''))
      .sort();
    say(names.length ? `Available: ${names.join(', ')}` : 'The key works but returned no models.');
  } catch (e) {
    say(e.message, false);
  }
});

load();
