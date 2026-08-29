/* slideshow.js — the whole kiosk client.
 *
 * Photos are pre-rendered by sync.py to the screen's exact size, so the client
 * just cross-fades between two <img> layers and applies dimming + jitter.
 *
 * - polls /config.json every 30s  (live config changes)
 * - polls /manifest.json every 5m  (new photos from sync.py)
 * - dims + warms the picture around sunset using sun.js
 * - nudges the picture 1px periodically (anti burn-in)
 */
(function () {
  "use strict";

  var CONFIG_POLL_MS = 30 * 1000;
  var MANIFEST_POLL_MS = 5 * 60 * 1000;
  var DIM_TICK_MS = 60 * 1000;

  var cfg = {
    slideshow: { interval_seconds: 60, min_interval_seconds: 15, shuffle: true, transition_ms: 1200 },
    display: { anti_burnin_jitter_px: 1, anti_burnin_period_seconds: 90 },
    dimming: { enabled: true, latitude: 51.5074, longitude: -0.1278, day_brightness: 1, night_brightness: 0.75, night_warmth: 0.12, fade_minutes: 30 },
  };

  var stage = document.querySelector(".stage");
  var msg = document.getElementById("msg");
  var layers = [document.getElementById("layerA"), document.getElementById("layerB")];
  var front = 0;

  var srcs = [];
  var order = [];
  var cursor = 0;
  var slideTimer = null;
  var jitterTimer = null;
  var jitterStep = 0;

  function num(v, d) { return typeof v === "number" && isFinite(v) ? v : d; }

  /* ---------- config ---------- */

  function applyDisplayVars() {
    document.documentElement.style.setProperty("--fade", num(cfg.slideshow.transition_ms, 1200) + "ms");
  }

  function slideMs() {
    var s = cfg.slideshow || {};
    return Math.max(num(s.min_interval_seconds, 15), num(s.interval_seconds, 60)) * 1000;
  }

  function loadConfig() {
    return fetch("/config.json?t=" + Date.now())
      .then(function (r) { return r.json(); })
      .then(function (next) {
        if (next && !next.error) {
          cfg.slideshow = Object.assign(cfg.slideshow, next.slideshow || {});
          cfg.display = Object.assign(cfg.display, next.display || {});
          cfg.dimming = Object.assign(cfg.dimming, next.dimming || {});
          applyDisplayVars();
          armJitter();
        }
      })
      .catch(function () {});
  }

  /* ---------- manifest ---------- */

  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  function rebuildOrder() {
    order = srcs.map(function (_, i) { return i; });
    if (cfg.slideshow.shuffle !== false) shuffle(order);
    cursor = 0;
  }

  function loadManifest() {
    return fetch("/manifest.json?t=" + Date.now())
      .then(function (r) { return r.json(); })
      .then(function (m) {
        var next = (m && m.photos ? m.photos : []).map(function (p) { return p.src; });
        var changed = next.length !== srcs.length || next.some(function (s, i) { return s !== srcs[i]; });
        if (changed) { srcs = next; rebuildOrder(); }
        if (msg) {
          if (srcs.length) msg.classList.add("hidden");
          else { msg.textContent = "Waiting for photos…"; msg.classList.remove("hidden"); }
        }
      })
      .catch(function () {});
  }

  /* ---------- slideshow ---------- */

  function scheduleNext(ms) {
    clearTimeout(slideTimer);
    slideTimer = setTimeout(nextSlide, ms == null ? slideMs() : ms);
  }

  function nextSlide() {
    if (!srcs.length) { scheduleNext(2000); return; }
    if (cursor >= order.length) rebuildOrder();
    var url = srcs[order[cursor++]];

    var back = layers[front ^ 1];
    var pre = new Image();
    pre.onload = function () {
      back.src = url;
      back.classList.add("show");
      layers[front].classList.remove("show");
      front ^= 1;
      scheduleNext();
    };
    pre.onerror = function () { scheduleNext(200); };
    pre.src = url;
  }

  /* ---------- anti burn-in ---------- */

  function armJitter() {
    clearInterval(jitterTimer);
    var d = cfg.display || {};
    var px = num(d.anti_burnin_jitter_px, 1);
    var period = num(d.anti_burnin_period_seconds, 90) * 1000;
    if (px <= 0) { stage.style.transform = ""; return; }
    var offs = [[0, 0], [px, 0], [px, px], [0, px], [-px, 0], [-px, -px], [0, -px], [px, -px]];
    jitterTimer = setInterval(function () {
      jitterStep = (jitterStep + 1) % offs.length;
      stage.style.transform = "translate(" + offs[jitterStep][0] + "px," + offs[jitterStep][1] + "px)";
    }, period);
  }

  /* ---------- dimming ---------- */

  function applyDimming() {
    var dm = cfg.dimming || {};
    if (dm.enabled === false) { stage.style.filter = "none"; return; }
    var n = window.nightness(
      new Date(),
      num(dm.latitude, 51.5074),
      num(dm.longitude, -0.1278),
      num(dm.fade_minutes, 30)
    );
    var day = num(dm.day_brightness, 1.0);
    var night = num(dm.night_brightness, 0.75);
    var b = day + n * (night - day);
    var w = n * num(dm.night_warmth, 0.12);
    stage.style.filter =
      "brightness(" + b.toFixed(3) + ") sepia(" + w.toFixed(3) + ") saturate(" + (1 - w * 0.25).toFixed(3) + ")";
  }

  /* ---------- boot ---------- */

  loadConfig()
    .then(loadManifest)
    .then(function () {
      applyDisplayVars();
      armJitter();
      applyDimming();
      nextSlide();
    });

  setInterval(loadConfig, CONFIG_POLL_MS);
  setInterval(loadManifest, MANIFEST_POLL_MS);
  setInterval(applyDimming, DIM_TICK_MS);
})();
