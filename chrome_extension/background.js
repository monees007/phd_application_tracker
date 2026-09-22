/**
 * Right-click → extract → save. No review step, matching the phone app.
 *
 * The important difference from the app: this reads the *rendered* DOM
 * through a content script, so adverts built by JavaScript after page load —
 * most applicant tracking systems — are fully visible. The phone's plain HTTP
 * fetch cannot see those at all.
 */

import { getConfig } from './lib/auth.js';
import { extract } from './lib/gemini.js';
import { createPosition } from './lib/firestore.js';

const MENU_PAGE = 'phdtracker_save_page';
const MENU_SELECTION = 'phdtracker_save_selection';

const NEEDS_DETAILS_TAG = 'needs-details';

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_PAGE,
      title: 'Save this advert to PhD Tracker',
      contexts: ['page', 'link'],
    });
    chrome.contextMenus.create({
      id: MENU_SELECTION,
      title: 'Save selected text to PhD Tracker',
      contexts: ['selection'],
    });
  });
});

chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());

chrome.contextMenus.onClicked.addListener((info, tab) => {
  // Not awaited: the menu handler should return immediately so Chrome does
  // not hold the gesture open while a network call runs.
  void handleClick(info, tab);
});

async function handleClick(info, tab) {
  const url = info.linkUrl || info.pageUrl || tab?.url || '';
  const id = `${Date.now()}`;

  notify(id, 'Reading the advert\u2026', new URL(url).hostname, true);

  try {
    const config = await getConfig();

    let pageText = (info.selectionText || '').trim();
    if (pageText.length < 80) {
      pageText = await readPageText(tab.id);
    }

    if (!pageText || pageText.trim().length < 80) {
      throw new Error('Could not read any text from that page.');
    }

    let extracted = null;
    let failure = null;
    try {
      extracted = await extract({
        pageText,
        url,
        apiKey: config.geminiKey,
        model: config.geminiModel,
      });
    } catch (e) {
      failure = e.message;
    }

    const confident =
      extracted &&
      extracted.confidence !== 'low' &&
      (extracted.university || '').trim().length > 0;

    // Same contract as the app: something is always saved. A share lost to a
    // transient API error is worse than an untidy row.
    const position = confident
      ? fullPosition(extracted, url, pageText)
      : notePosition(extracted, url, pageText, failure);

    const docId = await createPosition(position);

    notify(
      id,
      confident
        ? `Added: ${position.university}`
        : 'Saved as a note',
      confident
        ? [position.programme, extracted.deadline
            ? `Deadline ${extracted.deadline}`
            : 'No deadline found']
            .filter(Boolean)
            .join(' \u00b7 ')
        : `${failure || 'The model was unsure.'} Open the app to fill it in.`,
      false
    );

    console.debug('PhD Tracker: saved', docId);
  } catch (e) {
    notify(id, 'Could not save', e.message, false);
  }
}

/**
 * Pulls readable text out of the live page.
 *
 * Runs in the page via activeTab, which the context-menu click grants for
 * this tab only — the extension has no standing access to your browsing.
 */
async function readPageText(tabId) {
  const [result] = await chrome.scripting.executeScript({
    target: { tabId },
    func: () => {
      // Prefer the semantic content container when the page has one; fall
      // back to body. Either way strip chrome that is never part of an advert.
      const root =
        document.querySelector('main, article, [role="main"]') || document.body;
      const clone = root.cloneNode(true);
      clone
        .querySelectorAll(
          'script, style, noscript, svg, nav, header, footer, iframe, ' +
            '[aria-hidden="true"]'
        )
        .forEach((el) => el.remove());

      const text = (clone.innerText || '')
        .replace(/[ \t\u00A0]+/g, ' ')
        .replace(/\n{3,}/g, '\n\n')
        .trim();

      // Same cap as the app, to keep token cost bounded.
      return text.slice(0, 24000);
    },
  });
  return result?.result || '';
}

function fullPosition(e, url, pageText) {
  const today = new Date().toISOString().slice(0, 10);
  return {
    university: e.university.trim(),
    programme: (e.programme || '').trim(),
    deadline: e.deadline || null,
    // An inferred year stays flagged, so the date shows the same "verify me"
    // marker as rows imported from the spreadsheet.
    deadlineYearAssumed: !!e.deadline && !e.deadlineYearExplicit,
    funded: e.funded,
    applicationFee: e.applicationFee,
    feeCurrency: e.feeCurrency,
    link: url,
    country: e.country,
    tags: e.tags,
    status: 'notApplied',
    notes: [
      e.summary,
      `Saved from Chrome on ${today}.`,
      e.notFound.length
        ? `Not stated in the source: ${e.notFound.join(', ')}.`
        : null,
      // The whole advert, archived with the entry so it survives the page
      // being taken down and a later re-extract needs no refetch. The app
      // shows this collapsed behind a "Full advert" tile.
      advertBlock(pageText),
    ]
      .filter(Boolean)
      .join('\n\n'),
  };
}

function notePosition(e, url, pageText, failure) {
  const today = new Date().toISOString().slice(0, 10);
  let host = 'Shared advert';
  try {
    host = new URL(url).hostname.replace(/^www\./, '');
  } catch {
    /* keep the fallback */
  }

  return {
    university: (e?.university || '').trim() || host,
    programme: (e?.programme || '').trim(),
    deadline: e?.deadline || null,
    deadlineYearAssumed: !!e?.deadline && !e?.deadlineYearExplicit,
    funded: e?.funded ?? null,
    applicationFee: e?.applicationFee ?? null,
    feeCurrency: e?.feeCurrency ?? null,
    link: url,
    country: e?.country ?? null,
    tags: [...(e?.tags || []), NEEDS_DETAILS_TAG],
    status: 'notApplied',
    notes: [
      e?.summary,
      failure ? `Extraction failed: ${failure}` : 'The model was not confident.',
      `Saved from Chrome on ${today}.`,
      'Open this entry in the app, tap "Extract from text" and retry, or ' +
        'fill the fields in by hand.',
      // Kept verbatim so a later retry has something to work from. Trimmed
      // well inside the 5000-character notes cap in firestore.rules.
      advertBlock(pageText),
    ]
      .filter(Boolean)
      .join('\n\n'),
  };
}

/** Matches ADVERT_LIMIT in the app; see firestore.rules for the 40k cap. */
const ADVERT_LIMIT = 20000;

function advertBlock(pageText) {
  const text = (pageText || '').trim();
  if (!text) return null;
  const clipped =
    text.length > ADVERT_LIMIT
      ? `${text.slice(0, ADVERT_LIMIT)}\u2026`
      : text;
  return `--- shared text ---\n${clipped}`;
}

function notify(id, title, message, silent) {
  chrome.notifications.create(id, {
    type: 'basic',
    iconUrl: 'icon128.png',
    title,
    message: message || '',
    silent: !!silent,
  });
}
