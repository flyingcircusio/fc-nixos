/*
 * Missing-page fallback notice for the platform version switcher.
 *
 * Loaded GLOBALLY via zensical.toml extra_javascript but acting ONLY when
 * the ?missing=<page-id> parameter is present -- i.e. when the switcher
 * (version-switcher.js) sent the reader to a version index because the
 * page they were on does not exist in the chosen version. The notice
 * names the missing page and the platform version the reader has landed
 * in (from window.PLATFORM_VERSIONS, see _static/platform-versions.js),
 * and links straight to the page in the first version that has it.
 *
 * Every link built here is a zensical DIRECTORY URL (<prefix><page-id>/),
 * like everywhere in the switcher asset family.
 *
 * Inserted at the top of the page content (.md-content__inner), right
 * AFTER any archived-version banner so the banner stays the first content
 * element above the page title (the banner is prepended by the fetch
 * tool's _adapt_archived_page).
 *
 * document$ (exposed by the theme bundle) re-runs init() on every instant
 * navigation; insertion is idempotent (an existing notice is left alone).
 */
(function () {
  "use strict";

  var MISSING_PARAM = "missing";

  // The version entry whose index page this is (its index URL ends the path).
  function locateVersion(path, data) {
    for (var v = 0; v < data.versions.length; v += 1) {
      var entry = data.versions[v];
      if (path.slice(-entry.index.length) === entry.index) return entry;
    }
    return null;
  }

  // "../"*depth: relative path from this index page to the manual root.
  function rootRel(indexUrl) {
    return "../".repeat(indexUrl.split("/").length - 1);
  }

  // The first version (stable first, per the data order) that has the page.
  function findElsewhere(pageId, data) {
    for (var v = 0; v < data.versions.length; v += 1) {
      var entry = data.versions[v];
      var prefix = entry.pages ? entry.pages[pageId] : undefined;
      if (prefix !== undefined) {
        return { entry: entry, url: prefix + pageId + "/" };
      }
    }
    return null;
  }

  function buildNotice(missing, here, elsewhere, prefix) {
    var notice = document.createElement("div");
    notice.className = "admonition note version-switcher-notice";

    var heading = document.createElement("p");
    heading.className = "admonition-title";
    heading.textContent = "Page not available in this platform version";

    var body = document.createElement("p");
    body.appendChild(document.createTextNode('The page "'));
    var code = document.createElement("code");
    code.textContent = missing;
    body.appendChild(code);
    body.appendChild(
      document.createTextNode(
        here
          ? '" is not part of the platform documentation version ' +
              here.label +
              "."
          : '" is not part of this platform documentation version.'
      )
    );

    var hint = document.createElement("p");
    if (elsewhere) {
      var link = document.createElement("a");
      link.href = prefix + elsewhere.url;
      link.textContent =
        "Open the corresponding page in the " +
        elsewhere.entry.label +
        " documentation";
      hint.appendChild(link);
      hint.appendChild(
        document.createTextNode(", or use the version switcher in the sidebar.")
      );
    } else {
      hint.appendChild(
        document.createTextNode(
          "Use the version switcher in the sidebar to browse this version " +
            "or pick another one."
        )
      );
    }

    notice.appendChild(heading);
    notice.appendChild(body);
    notice.appendChild(hint);
    return notice;
  }

  function insert(notice) {
    var article = document.querySelector(".md-content__inner");
    if (!article) {
      console.warn(
        "version-switcher-fallback: no content container found -- notice not shown"
      );
      return;
    }
    if (article.querySelector(":scope > .version-switcher-notice")) return;
    // Keep the archived-version banner the FIRST content element: insert
    // after it (or above the page title when there is no banner).
    var banner = article.querySelector(".admonition");
    var anchor = banner ? banner.nextSibling : article.querySelector("h1, h2, h3");
    if (anchor) {
      article.insertBefore(notice, anchor);
    } else {
      article.appendChild(notice);
    }
  }

  function init() {
    var params = new URLSearchParams(window.location.search);
    var missing = params.get(MISSING_PARAM);
    if (!missing) return;

    var data = window.PLATFORM_VERSIONS;
    if (!data || !Array.isArray(data.versions)) {
      console.warn(
        "version-switcher-fallback: window.PLATFORM_VERSIONS is missing -- " +
          "run `make fetch` to regenerate _static/platform-versions.js"
      );
      return;
    }

    var here = locateVersion(decodeURI(window.location.pathname), data);
    var prefix = here ? rootRel(here.index) : "";
    insert(buildNotice(missing, here, findElsewhere(missing, data), prefix));
  }

  // document$ (exposed by the theme bundle) fires on initial load and on
  // every instant navigation; without it, plain DOMContentLoaded.
  if (window.document$) {
    document$.subscribe(init);
  } else if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
