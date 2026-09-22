
export const DEFAULTS = {
  projectId: 'apply-phd',
  apiKey: 'AIzaSyATJrIF9rro9DWMoZUb2FwGbsmj9EJdSJE',

  // Leave empty. See above.
  geminiKey: '',

  geminiModel: 'gemini-3.5-flash',
};

/** True when a release build ships with a project already configured. */
export const HAS_BAKED_PROJECT =
  DEFAULTS.projectId.length > 0 && DEFAULTS.apiKey.length > 0;
