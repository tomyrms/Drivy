/* Runs before styles and React. This preference contains no account or school data. */
(function () {
  var preference = 'system';
  try {
    var stored = localStorage.getItem('drivy.web.theme');
    if (stored === 'light' || stored === 'dark' || stored === 'system') preference = stored;
  } catch (_) { /* Private/restricted storage: the system remains usable. */ }
  var dark = preference === 'dark' || (preference === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.documentElement.dataset.themePreference = preference;
  document.querySelectorAll('meta[name="theme-color"]').forEach(function (meta) {
    meta.removeAttribute('media');
    meta.content = dark ? '#191b1e' : '#f7f8fa';
  });
})();
