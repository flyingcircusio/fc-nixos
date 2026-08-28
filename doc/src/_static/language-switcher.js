/*
 * Client-side wiring of the header language switcher dropdown.
 *
 * Loaded GLOBALLY via the zensical tomls' extra_javascript right after
 * the pure rule module _static/language-switcher-urls.js:
 *
 *   window.LanguageSwitcherUrls = {langOf, targetPath, ...};
 *
 * The dropdown markup (theme partial alternate.html) bakes each link as
 * language ROOT + the page's root-relative page.url -- correct for the
 * unversioned manual, WRONG wherever the deployment mounts the build
 * under a version alias: page.url is baked WITHOUT the version prefix,
 * so on a versioned page every baked href silently drops the reader out
 * of their version. This script corrects the hrefs AT RUNTIME from
 * window.location.pathname: the link whose hreflang matches the current
 * path's language keeps the pathname, every other link gets the swapped
 * pathname from the rule module (same page, other language -- version
 * prefix and page path preserved). The homepage and page-less contexts
 * need no special case: the rule maps "/" <-> "/de/" exactly like the
 * baked roots.
 *
 * Links without a hreflang attribute keep their baked href (nothing
 * declared, nothing to correct). Queries and fragments are NOT carried
 * over: the baked switch links are plain page URLs, and a query like the
 * version switcher's ?missing=<page-id> is a version-switch concern.
 *
 * With navigation.instant enabled the theme swaps page content without a
 * full reload; the document$ observable exposed by the theme bundle fires
 * for every navigation, so init() re-runs and the hrefs follow the reader
 * (same bootstrap pattern as version-switcher.js).
 *
 * Under CommonJS (the e2e logic tier require()s every tracked
 * language-switcher*.js module) there is no window: the DOM wiring is
 * inert by design, only the pure rule module exports an API.
 */
(function () {
  "use strict";

  if (typeof window === "undefined" || typeof document === "undefined") {
    return; // CommonJS logic tier: no DOM to wire
  }

  function readUrls() {
    var urls = window.LanguageSwitcherUrls;
    if (
      !urls ||
      typeof urls.targetPath !== "function" ||
      typeof urls.langOf !== "function"
    ) {
      console.warn(
        "language-switcher: window.LanguageSwitcherUrls is missing -- " +
          "_static/language-switcher-urls.js must load before " +
          "language-switcher.js"
      );
      return null;
    }
    return urls;
  }

  function init() {
    var urls = readUrls();
    if (!urls) return;
    var pathname = decodeURI(window.location.pathname);
    var here = urls.langOf(pathname);
    var links = document.querySelectorAll(urls.LINK_SELECTOR);
    for (var i = 0; i < links.length; i += 1) {
      var lang = links[i].getAttribute("hreflang");
      if (!lang) continue; // no language declared -- keep the baked href
      links[i].setAttribute(
        "href",
        lang === here ? pathname : urls.targetPath(pathname)
      );
    }
  }

  // document$ (exposed by the theme bundle) fires on initial load and on
  // every instant navigation; without it, plain DOMContentLoaded.
  if (window.document$) {
    window.document$.subscribe(init);
  } else if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
