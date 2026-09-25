// Brainmerge: gentle reveals, and the memory timeline lighting up line by line.
// Everything is visible without this file. It only adds motion when motion is welcome.
(function () {
  var motionOK = window.matchMedia && window.matchMedia('(prefers-reduced-motion: no-preference)').matches;
  if (!motionOK || !('IntersectionObserver' in window)) return;

  var root = document.documentElement;
  root.classList.add('js');

  // Anything already on screen is shown at once; the rest rises in as it arrives.
  var viewport = window.innerHeight || root.clientHeight;
  var reveals = Array.prototype.slice.call(document.querySelectorAll('.reveal'));
  var seen = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-in');
      seen.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0 });
  reveals.forEach(function (el) {
    if (el.getBoundingClientRect().top < viewport * 0.92) el.classList.add('is-in');
    else seen.observe(el);
  });

  // Each remembered sentence lights up in its account's color as it reaches the lower third, and stays lit.
  var lines = Array.prototype.slice.call(document.querySelectorAll('.said li'));
  var lit = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('lit');
      lit.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -32% 0px', threshold: 0 });
  lines.forEach(function (el) { lit.observe(el); });
})();

// Page views for the owner's own counter: no cookie, no identifier, only the page and where the visit came from.
(function () {
  if (location.hostname !== 'brainmerge.vercel.app') return;
  var endpoint = 'https://ruben-analytics.vercel.app/api/hit';
  var body = JSON.stringify({ site: 'brainmerge', path: location.pathname, ref: document.referrer });
  try {
    if (!navigator.sendBeacon(endpoint, body)) throw new Error('beacon');
  } catch (e) {
    fetch(endpoint, { method: 'POST', body: body, keepalive: true }).catch(function () {});
  }
})();
