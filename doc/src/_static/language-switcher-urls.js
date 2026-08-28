/*
 * Pure URL logic of the header language switcher -- no DOM, no state.
 *
 * Consumed by language-switcher.js as window.LanguageSwitcherUrls (loaded
 * as a plain <script> after this module) and by the e2e logic tier via
 * CommonJS `require()` under node (tests/e2e/test_language_switcher.py)
 * -- hence the dual export.
 *
 * WHY A RUNTIME RULE: the dropdown markup (theme partial alternate.html)
 * bakes hrefs as language ROOT + page.url, and page.url is baked WITHOUT
 * any version prefix -- the versioned deployments serve the SAME builds
 * under deployment aliases the build never sees (the English tree under
 * /<ver>/, its German twin under /de/<ver>/). No bake-time formula can
 * reconstruct the served prefix; the switcher must read it off
 * window.location.pathname at runtime.
 *
 * THE RULE: swap ONLY the language prefix -- the German manual is a
 * deployment alias of the whole tree, so <path> and /de<path> address the
 * same page in the two languages. Whatever follows the language prefix
 * (a version segment /<ver>/, the page path, both, or neither) is
 * language-invariant and stays byte-identical. The version segment is
 * DERIVED from the pathname: the rule knows no version list, so versions
 * no tree pins today keep working the day they are served.
 */
(function (root, factory) {
  "use strict";
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.LanguageSwitcherUrls = factory();
  }
})(typeof window !== "undefined" ? window : this, function () {
  "use strict";

  // The German alias prefix: every English path <path> has its German
  // twin /de<path>. Also part of the exported contract so consumers and
  // tests cannot drift from the grammar.
  var DE_PREFIX = "/de/";

  // Dropdown links of the header language switcher (theme partial
  // alternate.html, class pinned by upstream). language-switcher.js
  // rewrites exactly these; the selector lives here so the rule and its
  // consumer cannot drift apart.
  var LINK_SELECTOR = "a.md-select__link";

  // Language of a served pathname: "de" under the /de/ alias, else "en"
  // (the unaliased "/" serves the English tree -- URL stability).
  function langOf(pathname) {
    if (pathname.indexOf(DE_PREFIX) === 0 || pathname === "/de") {
      return "de";
    }
    return "en";
  }

  // Same page in the OTHER language: swap the language prefix, keep the
  // rest byte-identical.
  //   "/" <-> "/de/", "/<page>/" <-> "/de/<page>/",
  //   "/<ver>/<page>/" <-> "/de/<ver>/<page>/"
  function targetPath(pathname) {
    if (langOf(pathname) === "de") {
      // "/de" itself maps to the English root; otherwise strip the "/de"
      // segment and keep the leading "/" of what follows.
      return pathname === "/de" ? "/" : pathname.slice(DE_PREFIX.length - 1);
    }
    // "/": the alias root; everything else: insert "/de" after the root.
    return pathname === "/" ? DE_PREFIX : DE_PREFIX + pathname.slice(1);
  }

  return {
    langOf: langOf,
    targetPath: targetPath,
    DE_PREFIX: DE_PREFIX,
    LINK_SELECTOR: LINK_SELECTOR,
  };
});
