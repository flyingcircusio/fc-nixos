/* Self-hosted GLightbox runtime shim for the Flying Circus manual.
 *
 * The zensical theme bundle lazy-loads the image-zoom runtime
 * (GLightbox 3) from unpkg.com at view time:
 *
 *   JS:  Hp() -- skipped when window.GLightbox is already defined, which
 *        the vendored _static/vendor/glightbox.min.js (extra_javascript)
 *        guarantees before the theme initializes on DOMContentLoaded.
 *   CSS: $p() -- ALWAYS appends
 *        <link href="https://unpkg.com/glightbox@3/dist/css/glightbox.min.css">.
 *        The vendored stylesheet is already wired via extra_css, so this
 *        shim rewrites that href to the local copy's URL: no request ever
 *        leaves flyingcircus.io (same self-hosting policy as the fonts).
 */
(function () {
  "use strict";

  var CDN = "https://unpkg.com/glightbox";
  var OWN = 'link[href$="vendor/glightbox.min.css"]';

  function localize(url) {
    if (typeof url !== "string" || url.indexOf(CDN) !== 0) {
      return url;
    }
    var own = document.querySelector(OWN);
    return own ? own.href : url;
  }

  var proto = HTMLLinkElement.prototype;
  var desc = Object.getOwnPropertyDescriptor(proto, "href");
  if (desc && desc.set) {
    Object.defineProperty(proto, "href", {
      get: desc.get,
      set: function (value) {
        desc.set.call(this, localize(value));
      },
      configurable: true,
    });
  }

  var setAttribute = proto.setAttribute;
  proto.setAttribute = function (name, value) {
    if (String(name).toLowerCase() === "href") {
      value = localize(value);
    }
    return setAttribute.call(this, name, value);
  };
})();
