(function () {
  const STORAGE_KEY = 'stashDocsThemePreference';
  const VALID_THEMES = new Set(['light', 'dark']);
  const toggleButtons = new Set();
  const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
  let storageWarningShown = false;

  function showStorageWarning(error) {
    if (storageWarningShown) {
      return;
    }

    storageWarningShown = true;
    console.warn('Could not access theme preference storage. Falling back to system theme.', error);
  }

  function readStoredValue() {
    try {
      return window.localStorage.getItem(STORAGE_KEY);
    } catch (error) {
      showStorageWarning(error);
      return null;
    }
  }

  function writeStoredValue(value) {
    try {
      window.localStorage.setItem(STORAGE_KEY, value);
      return true;
    } catch (error) {
      showStorageWarning(error);
      return false;
    }
  }

  function clearStoredValue() {
    try {
      window.localStorage.removeItem(STORAGE_KEY);
    } catch (error) {
      showStorageWarning(error);
    }
  }

  function getStoredPreference() {
    const value = readStoredValue();
    return VALID_THEMES.has(value) ? value : null;
  }

  function getSystemTheme() {
    return mediaQuery.matches ? 'dark' : 'light';
  }

  function getResolvedTheme() {
    return getStoredPreference() || getSystemTheme();
  }

  function updateThemeColor(theme) {
    const metaThemeColor = document.querySelector('meta[name="theme-color"]');
    if (!metaThemeColor) {
      return;
    }

    const lightColor = metaThemeColor.dataset.themeColorLight;
    const darkColor = metaThemeColor.dataset.themeColorDark;
    const nextColor = theme === 'light' ? lightColor || metaThemeColor.content : darkColor || metaThemeColor.content;
    metaThemeColor.setAttribute('content', nextColor);
  }

  function syncToggleButton(button) {
    const activeTheme = document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
    const nextTheme = activeTheme === 'dark' ? 'light' : 'dark';
    const label = button.querySelector('.theme-toggle-label');

    if (label) {
      label.textContent = activeTheme === 'dark' ? 'Dark' : 'Light';
    }

    button.setAttribute('aria-pressed', activeTheme === 'dark' ? 'true' : 'false');
    button.setAttribute('aria-label', `Current theme: ${activeTheme}. Switch to ${nextTheme}.`);
    button.setAttribute('title', `Switch to ${nextTheme} theme`);
    button.dataset.theme = activeTheme;
  }

  function syncAllToggleButtons() {
    toggleButtons.forEach((button) => syncToggleButton(button));
  }

  function applyTheme(theme) {
    const nextTheme = VALID_THEMES.has(theme) ? theme : getSystemTheme();
    document.documentElement.dataset.theme = nextTheme;
    document.documentElement.style.colorScheme = nextTheme;
    updateThemeColor(nextTheme);
    syncAllToggleButtons();
    window.dispatchEvent(new CustomEvent('stashdocs:themechange', { detail: { theme: nextTheme } }));
    return nextTheme;
  }

  function setPreference(theme) {
    if (!VALID_THEMES.has(theme)) {
      clearStoredValue();
      return applyTheme(getSystemTheme());
    }

    if (!writeStoredValue(theme)) {
      return applyTheme(theme);
    }

    return applyTheme(theme);
  }

  function toggleTheme() {
    const currentTheme = document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
    return setPreference(currentTheme === 'dark' ? 'light' : 'dark');
  }

  function bindToggleButton(button) {
    if (!button || toggleButtons.has(button)) {
      return;
    }

    toggleButtons.add(button);
    button.addEventListener('click', toggleTheme);
    syncToggleButton(button);
  }

  function bindRegisteredToggleButtons() {
    document.querySelectorAll('[data-theme-toggle]').forEach((button) => bindToggleButton(button));
  }

  applyTheme(getResolvedTheme());

  if (typeof mediaQuery.addEventListener === 'function') {
    mediaQuery.addEventListener('change', () => {
      if (!getStoredPreference()) {
        applyTheme(getSystemTheme());
      }
    });
  } else if (typeof mediaQuery.addListener === 'function') {
    mediaQuery.addListener(() => {
      if (!getStoredPreference()) {
        applyTheme(getSystemTheme());
      }
    });
  }

  window.StashDocsTheme = {
    applyTheme,
    bindToggleButton,
    getResolvedTheme,
    getStoredPreference,
    getSystemTheme,
    setPreference,
    toggleTheme
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bindRegisteredToggleButtons, { once: true });
  } else {
    bindRegisteredToggleButtons();
  }
})();
