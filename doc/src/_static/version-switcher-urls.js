/*
 * Pure URL logic for the platform version switcher -- no DOM, no
 * fetch, only functions over (path, data). Loaded globally BEFORE
 * version-switcher.js (see zensical.toml extra_javascript) which
 * consumes this contract:
 *
 *   locate(path, data) -> {entry, pageId} describing the page the
 *     reader is on, or null when fewer than TWO versions carry the
 *     page-id -- common pages get NO flyout (user decision
 *     2026-08-18), the navigation tree stays undisplaced.
 *
 *   targetHref(entry, here) -> the SAME page in the target version as
 *     a zensical directory URL (<prefix><page-id>/, one step, no
 *     version-index detour) when the version's inventory carries the
 *     page-id; otherwise the version index with ?missing=<page-id>,
 *     where version-switcher-fallback.js explains what happened.
 *
 * URL spaces: "/" is the current version's space (the local tree),
 * "/<ver>/" a checked-out snapshot's (make checkout-versioned-docs).
 * Page-ids are URL-shaped and match the generated inventories in
 * window.PLATFORM_VERSIONS (make gen-platform-versions): tree-relative
 * paths sans .md with a trailing "index" component folded away -- the
 * root page has page-id "" and every href is prefix or
 * prefix + pageId + "/".
 */
window.VersionSwitcherUrls = {
  PRIMARY_MOUNT_SELECTOR: ".md-sidebar--primary .md-sidebar__inner",
  SECONDARY_MOUNT_SELECTOR: ".md-sidebar--secondary .md-sidebar__inner",

  // The version entry whose URL space *path* lives in: the first path
  // segment matching a version's ver, else the entry serving "/" (the
  // current version).
  entryFor: function (path, data) {
    var seg = path.replace(/^\/+/, "").split("/")[0];
    var v;
    for (v = 0; v < data.versions.length; v += 1) {
      if (seg && data.versions[v].ver === seg) return data.versions[v];
    }
    for (v = 0; v < data.versions.length; v += 1) {
      if (data.versions[v].index === "/") return data.versions[v];
    }
    return null;
  },

  // path -> page-id relative to its version space ("" = manual root).
  pageIdFor: function (path, entry) {
    var rest = entry && entry.index !== "/" ? path.slice(entry.index.length) : path;
    return rest.replace(/^\/+|\/+$/g, "");
  },

  // How many versions' inventories carry *pageId*.
  carriersOf: function (pageId, data) {
    var carriers = 0;
    for (var v = 0; v < data.versions.length; v += 1) {
      var pages = data.versions[v].pages;
      if (pages && Object.prototype.hasOwnProperty.call(pages, pageId)) {
        carriers += 1;
      }
    }
    return carriers;
  },

  locate: function (path, data) {
    var entry = this.entryFor(path, data);
    if (!entry) return null;
    var pageId = this.pageIdFor(path, entry);
    // Versioned pages only: a page-id found in fewer than two trees is
    // a common page -- nothing to switch here.
    if (this.carriersOf(pageId, data) < 2) return null;
    return { entry: entry, pageId: pageId };
  },

  targetHref: function (entry, here) {
    var prefix = entry.pages ? entry.pages[here.pageId] : undefined;
    if (prefix !== undefined) {
      return here.pageId === "" ? entry.index : prefix + here.pageId + "/";
    }
    return entry.index + "?missing=" + here.pageId;
  },
};
