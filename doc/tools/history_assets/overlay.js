/*
 * VCS history overlay -- the navigation bar injected into every /v/<rev>/
 * page of the history browser (tools/build_history.py injects
 * <link /v/overlay.css> + <script /v/overlay.js> before </body>).
 *
 * Data source: /v/manifest.json (written by tools/build_history.py). Pure
 * URL/date logic lives in history-urls.js (window.HistoryUrls); this script
 * loads it dynamically from /v/history-urls.js when the global is missing,
 * so the injected tags stay exactly one <link> + one <script>.
 *
 * UI (one fixed bar, bottom of the viewport -- see overlay.css):
 *   <  [rev select]  >     revision dropdown + prev/next neighbours
 *   Zustand am [date] [vorgestern] [go]
 *                          "state of the docs at <date>": navigates to the
 *                          last BUILDABLE revision with date <= <date>;
 *                          "vorgestern" presets today-2. Failed builds
 *                          show as disabled options and are skipped by
 *                          every navigation path (their /v/<rev>/
 *                          directory was never placed -- navigating there
 *                          would 404).
 */
(function (window, document) {
  "use strict";

  function currentRev(pathname) {
    var match = /^\/v\/([^/]+)/.exec(pathname);
    return match ? match[1] : null;
  }

  function todayISO() {
    return new Date().toISOString().slice(0, 10);
  }

  function truncate(text, max) {
    return text.length > max ? text.slice(0, max - 1) + "…" : text;
  }

  function init(urls, manifest) {
    var revisions = urls.sortedRevisions((manifest && manifest.revisions) || []);
    var buildable = revisions.filter(function (e) {
      return e.status === "ok";
    });
    var here = currentRev(window.location.pathname);
    var at = buildable.findIndex(function (e) {
      return e.rev === here;
    });

    var bar = document.createElement("div");
    bar.className = "history-overlay";

    var label = document.createElement("span");
    label.className = "history-overlay__label";
    label.textContent = "History";
    bar.appendChild(label);

    function navigate(href) {
      window.location.href = href;
    }

    function step(delta) {
      if (at === -1) return;
      var target = buildable[at + delta];
      if (!target) return;
      navigate(urls.targetHref(window.location.pathname, target.rev));
    }

    var prev = document.createElement("button");
    prev.type = "button";
    prev.className = "history-overlay__btn";
    prev.textContent = "←";
    prev.title = "previous revision";
    prev.disabled = at <= 0;
    prev.addEventListener("click", function () {
      step(-1);
    });
    bar.appendChild(prev);

    var select = document.createElement("select");
    select.className = "history-overlay__select";
    revisions.forEach(function (entry) {
      var option = document.createElement("option");
      option.value = entry.rev;
      option.textContent =
        entry.rev +
        " · " +
        entry.date +
        " · " +
        truncate(entry.subject || "", 40);
      if (entry.status !== "ok") {
        option.disabled = true;
        option.textContent += " (build failed)";
      }
      if (entry.rev === here) {
        option.selected = true;
      }
      select.appendChild(option);
    });
    select.addEventListener("change", function () {
      navigate(urls.targetHref(window.location.pathname, select.value));
    });
    bar.appendChild(select);

    var next = document.createElement("button");
    next.type = "button";
    next.className = "history-overlay__btn";
    next.textContent = "→";
    next.title = "next revision";
    next.disabled = at === -1 || at >= buildable.length - 1;
    next.addEventListener("click", function () {
      step(1);
    });
    bar.appendChild(next);

    var notice = document.createElement("span");
    notice.className = "history-overlay__notice";
    bar.appendChild(notice);

    var dateLabel = document.createElement("label");
    dateLabel.className = "history-overlay__date-label";
    dateLabel.textContent = "Zustand am";
    bar.appendChild(dateLabel);

    var dateInput = document.createElement("input");
    dateInput.type = "date";
    dateInput.className = "history-overlay__date";
    bar.appendChild(dateInput);

    function applyDate() {
      notice.textContent = "";
      if (!dateInput.value) return;
      var rev = urls.revForDate(dateInput.value, revisions);
      if (rev === null) {
        notice.textContent =
          "nothing existed on or before " + dateInput.value;
        return;
      }
      navigate(urls.targetHref(window.location.pathname, rev));
    }

    var vorgestern = document.createElement("button");
    vorgestern.type = "button";
    vorgestern.className = "history-overlay__btn";
    vorgestern.textContent = "vorgestern";
    vorgestern.title = "state of the docs two days ago";
    vorgestern.addEventListener("click", function () {
      dateInput.value = urls.vorgestern(todayISO());
      applyDate();
    });
    bar.appendChild(vorgestern);

    var go = document.createElement("button");
    go.type = "button";
    go.className = "history-overlay__btn";
    go.textContent = "go";
    go.addEventListener("click", applyDate);
    bar.appendChild(go);

    document.body.appendChild(bar);
  }

  function boot() {
    window
      .fetch("/v/manifest.json")
      .then(function (response) {
        return response.json();
      })
      .then(function (manifest) {
        init(window.HistoryUrls, manifest);
      })
      .catch(function (err) {
        // Degraded, not broken: a missing manifest only costs the overlay.
        (window.console && window.console.warn || function () {})(
          "history-overlay: /v/manifest.json unavailable",
          err
        );
      });
  }

  if (window.HistoryUrls) {
    boot();
  } else {
    var loader = document.createElement("script");
    loader.src = "/v/history-urls.js";
    loader.addEventListener("load", boot);
    document.head.appendChild(loader);
  }
})(typeof window !== "undefined" ? window : globalThis,
   typeof document !== "undefined" ? document : undefined);
