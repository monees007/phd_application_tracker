/**
 * Gemini extraction, deliberately mirroring `gemini_service.dart`.
 *
 * The prompt and schema are duplicated in two languages, which is a real
 * maintenance cost — change one and the app and the extension will disagree
 * about what a field means. Kept in sync by hand; the alternative is a server
 * in the middle, which is a lot of infrastructure for a personal tracker.
 */

const BASE = 'https://generativelanguage.googleapis.com/v1beta';

const SCHEMA = {
  type: 'OBJECT',
  properties: {
    university: { type: 'STRING', nullable: true },
    programme: { type: 'STRING', nullable: true },
    deadline: {
      type: 'STRING',
      nullable: true,
      description: 'Application deadline as yyyy-MM-dd.',
    },
    deadlineYearExplicit: { type: 'BOOLEAN' },
    funded: { type: 'BOOLEAN', nullable: true },
    applicationFee: { type: 'NUMBER', nullable: true },
    feeCurrency: { type: 'STRING', nullable: true },
    country: { type: 'STRING', nullable: true },
    tags: { type: 'ARRAY', items: { type: 'STRING' } },
    summary: { type: 'STRING', nullable: true },
    confidence: { type: 'STRING', enum: ['high', 'medium', 'low'] },
    notFound: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: ['deadlineYearExplicit', 'confidence', 'tags', 'notFound'],
};

function buildPrompt(pageText, url) {
  const today = new Date().toISOString().slice(0, 10);
  return `You are extracting structured data from the text of a PhD or research
position advert. Today's date is ${today}.

Rules, in order of importance:
1. Only report what the page states. If a field is not stated, return null for
   it and add its name to "notFound". Never guess, never infer from the
   university's reputation, and never fill a field from general knowledge.
2. "deadline" must be yyyy-MM-dd. If the page gives a day and month but no
   year, choose the next occurrence of that date after today, and set
   "deadlineYearExplicit" to false. Set it to true only when the page states
   the year outright.
3. "funded" is true only if the page says the position is funded, salaried, or
   comes with a stipend or employment contract. Most European PhD positions
   are employment; if the page says nothing about money, return null.
4. "applicationFee" is the fee to submit an application, not the salary and
   not the tuition. Null unless a fee is explicitly stated.
5. "programme" is the position or project title, not the page's marketing
   headline. "university" is the institution, without its department.
6. "tags" are at most four short research-area keywords taken from the text.
7. "summary" is at most two sentences on what the project involves, in your
   own words.
8. "confidence" is high only when university, programme and deadline were all
   clearly stated; low if the text looks like a navigation page, a cookie
   banner, or a listing index rather than one specific advert.

Source URL: ${url}

--- PAGE TEXT ---
${pageText}
--- END PAGE TEXT ---

Respond with a single JSON object and nothing else. No prose, no code fences.`;
}

export async function extract({ pageText, url, apiKey, model }) {
  if (!apiKey) throw new Error('No Gemini API key saved. Open settings.');
  if (!pageText || pageText.trim().length < 80) {
    throw new Error('There was almost no text on that page to work from.');
  }

  const modelId = (model || 'gemini-3.5-flash').trim();
  const prompt = buildPrompt(pageText, url);

  const body = (withSchema) => ({
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: 0,
      responseMimeType: 'application/json',
      ...(withSchema ? { responseSchema: SCHEMA } : {}),
    },
  });

  const post = (payload) =>
    fetch(`${BASE}/models/${encodeURIComponent(modelId)}:generateContent`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify(payload),
    });

  let res = await post(body(true));

  // Schema field names have shifted between API versions; if the schema is
  // rejected, the prompt alone still asks for bare JSON.
  if (res.status === 400) {
    const text = await res.clone().text();
    if (text.toLowerCase().includes('schema')) res = await post(body(false));
  }

  // 503 means the model is overloaded, not that the request was wrong. It
  // clears in seconds, and nobody is watching a spinner here.
  let attempt = 0;
  while ((res.status === 503 || res.status === 500) && attempt < 3) {
    attempt += 1;
    await new Promise((r) => setTimeout(r, 2000 * attempt * attempt));
    res = await post(body(true));
  }

  if (!res.ok) throw new Error(await describeError(res, modelId));

  const json = await res.json();
  const parts = json?.candidates?.[0]?.content?.parts;
  if (!parts?.length) {
    throw new Error('The model returned an empty response.');
  }

  const text = parts.map((p) => p.text || '').join('').trim();
  return normalise(parseLoose(text));
}

function parseLoose(text) {
  let s = text.replace(/^```(?:json)?/gm, '').replace(/```$/gm, '').trim();
  try {
    return JSON.parse(s);
  } catch {
    const start = s.indexOf('{');
    const end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return JSON.parse(s.slice(start, end + 1));
    }
    throw new Error('The model did not return usable JSON.');
  }
}

/** Models occasionally emit "null" or "N/A" as literal strings. */
function clean(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  if (!s || s.toLowerCase() === 'null' || s.toLowerCase() === 'n/a') return null;
  return s;
}

function normalise(j) {
  return {
    university: clean(j.university),
    programme: clean(j.programme),
    deadline: clean(j.deadline),
    deadlineYearExplicit: j.deadlineYearExplicit === true,
    funded: typeof j.funded === 'boolean' ? j.funded : null,
    applicationFee:
      typeof j.applicationFee === 'number' ? j.applicationFee : null,
    feeCurrency: clean(j.feeCurrency),
    country: clean(j.country),
    tags: Array.isArray(j.tags)
      ? j.tags.map((t) => String(t).trim()).filter(Boolean).slice(0, 4)
      : [],
    summary: clean(j.summary),
    confidence: (clean(j.confidence) || 'low').toLowerCase(),
    notFound: Array.isArray(j.notFound) ? j.notFound.map(String) : [],
  };
}

async function describeError(res, modelId) {
  let detail = `HTTP ${res.status}`;
  try {
    const body = await res.json();
    detail = body?.error?.message || detail;
  } catch {
    /* keep the status */
  }
  if (res.status === 404) {
    return `No such model "${modelId}". Pick one your key can reach in settings. (${detail})`;
  }
  if (res.status === 401 || res.status === 403) {
    return `Gemini refused the API key. (${detail})`;
  }
  if (res.status === 429) return 'Gemini rate limit or quota exceeded.';
  return `Gemini error: ${detail}`;
}
