/*
 * Client-side platform version switcher (Read-the-Docs-style flyout).
 *
 * Loaded GLOBALLY via zensical.toml extra_javascript after the generated
 * data file _static/platform-versions.js and the pure-URL module
 * _static/version-switcher-urls.js:
 *
 *   window.PLATFORM_VERSIONS = {
 *     current: "<stable ver>",
 *     versions: [{ver, status, label, index, pages: {<page-id>: <prefix>}}]
 *   };
 *   window.VersionSwitcherUrls = {locate, targetHref, ...};
 *
 * The flyout is a native <details>/<summary> mounted as the FIRST element
 * of the secondary (right TOC) sidebar, selector
 * ".md-sidebar--secondary .md-sidebar__inner", falling back to the top of
 * the primary sidebar, selector ".md-sidebar--primary .md-sidebar__inner",
 * on pages without a secondary sidebar -- the selectors come from the URL
 * module's mount constants so they cannot drift.
 *
 * It is shown ONLY on versioned pages (user decision 2026-08-18): locate()
 * returning null means "nothing to switch here" and no flyout mounts --
 * the navigation tree stays undisplaced everywhere else.
 *
 * Switching versions follows the mapping rules the data file makes
 * computable (URL logic in version-switcher-urls.js; zensical serves
 * directory URLs):
 *
 *   - the same page in the target version, when <page-id> exists in that
 *     version's inventory (<prefix><page-id>/, one step, no version-index
 *     detour);
 *   - otherwise the target version's index with ?missing=<page-id>, where
 *     version-switcher-fallback.js (loaded globally, acting only when the
 *     parameter is present) explains what happened.
 *
 * It marks the currently viewed version selected (aria-current) and
 * suffixes the browser tab title with " — Platform <ver>" (guarded against
 * double-append across instant navigations).
 *
 * With navigation.instant enabled the theme swaps page content without a
 * full reload; the document$ observable exposed by the theme bundle fires
 * for every navigation, so init() re-runs and the flyout follows the
 * reader -- unmount() drops the previous page's instance first, including
 * when navigation lands on an unversioned page.
 *
 * The OPEN version list overlays the TOC below it
 * (version-switcher.css), so an open flyout would block the links
 * beneath it: document-level listeners (bound ONCE per page load, they
 * survive instant navigations) close every open flyout on clicks
 * outside it and on Escape. Summary clicks are left to the native
 * <details> toggle; version links navigate anyway.
 */
(function () {
  "use strict";

  function readData() {
    var data = window.PLATFORM_VERSIONS;
    if (
      !data ||
      !Array.isArray(data.versions) ||
      data.versions.length === 0
    ) {
      console.warn(
        "version-switcher: window.PLATFORM_VERSIONS is missing or empty -- " +
          "run `make fetch` to regenerate _static/platform-versions.js"
      );
      return null;
    }
    return data;
  }

  function readUrls() {
    var urls = window.VersionSwitcherUrls;
    if (!urls || typeof urls.locate !== "function") {
      console.warn(
        "version-switcher: window.VersionSwitcherUrls is missing -- " +
          "_static/version-switcher-urls.js must load before version-switcher.js"
      );
      return null;
    }
    return urls;
  }

  function buildFlyout(data, here, urls) {
    var details = document.createElement("details");
    details.className = "version-switcher";

    var summary = document.createElement("summary");
    summary.appendChild(
      document.createTextNode("Platform " + here.entry.label)
    );

    var list = document.createElement("ul");
    for (var v = 0; v < data.versions.length; v += 1) {
      var entry = data.versions[v];
      var item = document.createElement("li");
      var link = document.createElement("a");
      link.href = urls.targetHref(entry, here);
      link.textContent = entry.label;
      if (entry === here.entry) {
        link.setAttribute("aria-current", "true");
      }
      item.appendChild(link);
      list.appendChild(item);
    }

    details.appendChild(summary);
    details.appendChild(list);
    return details;
  }

  // Drop every flyout instance of a previous page render -- instant
  // navigation re-runs init(), and navigating onto an unversioned page
  // must remove the versioned page's flyout instead of leaving it stale.
  function unmount() {
    var stale = document.querySelectorAll("details.version-switcher");
    for (var i = 0; i < stale.length; i += 1) stale[i].remove();
  }

  function mount(flyout, urls) {
    var sidebar =
      document.querySelector(urls.SECONDARY_MOUNT_SELECTOR) ||
      document.querySelector(urls.PRIMARY_MOUNT_SELECTOR);
    if (!sidebar) {
      console.warn(
        "version-switcher: no sidebar container found -- flyout not mounted"
      );
      return;
    }
    unmount();
    // Top of the sidebar: the flyout precedes the TOC (or brand and
    // navigation tree on primary-fallback pages).
    sidebar.insertBefore(flyout, sidebar.firstChild);
  }

  function init() {
    var urls = readUrls();
    var data = readData();
    if (!urls || !data) return;
    var here = urls.locate(decodeURI(window.location.pathname), data);
    unmount();
    // Versioned pages only: nothing to switch elsewhere.
    if (!here) return;
    mount(buildFlyout(data, here, urls), urls);
    var suffix = " — Platform " + here.entry.ver;
    if (!document.title.endsWith(suffix)) {
      document.title = document.title + suffix;
    }
  }

  // Close every open flyout -- the open list overlays the TOC below it.
  function closeOpenFlyouts() {
    var open = document.querySelectorAll("details.version-switcher[open]");
    for (var i = 0; i < open.length; i += 1) open[i].removeAttribute("open");
  }

  function onDismissClick(event) {
    var target = event.target;
    if (
      target &&
      target.closest &&
      target.closest("details.version-switcher")
    ) {
      return; // summary: native toggle; links: navigate anyway
    }
    closeOpenFlyouts();
  }

  function onDismissKey(event) {
    if (event.key === "Escape") closeOpenFlyouts();
  }

  // Bound once per page load: init() re-runs on every instant
  // navigation, but document-level listeners persist with the document.
  var dismissBound = false;

  function bindDismiss() {
    if (dismissBound) return;
    dismissBound = true;
    document.addEventListener("click", onDismissClick);
    document.addEventListener("keydown", onDismissKey);
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
  bindDismiss();
})();
