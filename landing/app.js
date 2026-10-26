// Velqi landing — stars, landscape, bushes, particles, cursor glow, scroll reveal, counters & tilt.

(function () {
  "use strict";

  var reducedMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ── Twinkling CSS stars ─────────────────────────────────── */
  (function () {
    var layer = document.getElementById("stars-layer");
    if (!layer || reducedMotion) return;

    // Seeded PRNG (consistent star positions)
    var seed = 0x5eed1234;
    function rand() {
      seed |= 0;
      seed = (seed + 0x6d2b79f5) | 0;
      var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 0x100000000;
    }

    var count = window.innerWidth < 640 ? 25 : 45;
    for (var i = 0; i < count; i++) {
      var size = rand() > 0.6 ? 3 : 2;
      var glow = size === 3 ? 5 : 4;
      var star = document.createElement("span");
      star.className = "lp-star";
      star.style.cssText =
        "left:" + (rand() * 100).toFixed(2) + "%;" +
        "top:" + (rand() * 65).toFixed(2) + "%;" +
        "--size:" + size + "px;" +
        "--glow:" + glow + "px;" +
        "--min:0.4;--max:1;" +
        "--dur:" + (3 + rand() * 4).toFixed(2) + "s;" +
        "--delay:" + (rand() * 5).toFixed(2) + "s";
      layer.appendChild(star);
    }
  })();

  /* ── Space dust cursor trail (desktop only) ─────────────────── */
  var finePointer = window.matchMedia && window.matchMedia("(pointer: fine)").matches;
  var trail = [];
  if (finePointer && !reducedMotion) {
    document.addEventListener("mousemove", function (e) {
      var dot = document.createElement("span");
      dot.className = "space-trail";
      dot.style.left = e.clientX + "px";
      dot.style.top = e.clientY + "px";
      var size = (Math.random() * 3 + 1).toFixed(1);
      dot.style.width = size + "px";
      dot.style.height = size + "px";
      dot.style.opacity = (Math.random() * 0.6 + 0.3).toFixed(2);
      dot.style.setProperty("--hue", Math.floor(Math.random() * 80 + 220) + "deg");
      document.body.appendChild(dot);
      trail.push(dot);
      setTimeout(function () {
        dot.classList.add("fade-out");
        setTimeout(function () { if (dot.parentNode) dot.parentNode.removeChild(dot); }, 600);
      }, 80);
      if (trail.length > 30) { var old = trail.shift(); if (old && old.parentNode) old.parentNode.removeChild(old); }
    });
  }

  /* ── Device architecture detection & card highlighting ─────── */
  function detectArch() {
    var ua = (navigator.userAgent || "").toLowerCase();
    if (ua.indexOf("x86_64") !== -1 || ua.indexOf("x64") !== -1 || ua.indexOf("amd64") !== -1) return "x86_64";
    if (ua.indexOf("aarch64") !== -1 || ua.indexOf("arm64") !== -1) return "arm64";
    if (ua.indexOf("armv7") !== -1 || ua.indexOf("armv7l") !== -1) return "armeabi";
    if (ua.indexOf("arm") !== -1) return "arm64";
    return null;
  }
  var arch = detectArch();
  var note = document.getElementById("device-note");
  var cards = document.querySelectorAll(".card[data-arch]");
  function markRecommended(sel) {
    cards.forEach(function (c) { c.classList.remove("recommended"); var f = c.querySelector(".card-flag"); if (f) f.remove(); });
    var el = document.querySelector(sel);
    if (!el) return;
    el.classList.add("recommended");
    var f = document.createElement("div"); f.className = "card-flag"; f.textContent = "★ Recomendado para ti"; el.appendChild(f);
  }
  if (arch && note) {
    var labels = { arm64: "Tu dispositivo usa ARM64.", armeabi: "Tu dispositivo usa ARMv7 (32 bits).", x86_64: "Pareces estar en un emulador o PC (x86_64)." };
    note.textContent = labels[arch] || "";
    if (cards.length) {
      markRecommended(arch === "arm64" ? '.card[data-arch="arm64"]' : arch === "armeabi" ? '.card[data-arch="armeabi"]' : '.card[data-arch="x86_64"]');
    }
  }

  /* ── Falling particles + shooting stars ────────────────────── */
  var canvas = document.getElementById("particles");
  var ctx = canvas ? canvas.getContext("2d") : null;
  var particles = [];
  var meteors = [];
  var W = 0, H = 0, dpr = 1, lastTs = 0, nextMeteor = 2600;

  function resizeCanvas() {
    if (!canvas || !ctx) return;
    dpr = window.devicePixelRatio || 1;
    W = document.documentElement.clientWidth || window.innerWidth;
    H = window.innerHeight;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  function spawnParticles() {
    particles = [];
    if (!ctx || W === 0 || H === 0) return;
    var count = Math.min(70, Math.max(15, Math.floor((W * H) / 20000)));
    if (W < 640) count = Math.floor(count * 0.5);
    for (var i = 0; i < count; i++) {
      particles.push({
        x: Math.random() * W, y: Math.random() * H,
        r: Math.random() * 1.6 + 0.3,
        vy: Math.random() * 0.4 + 0.1,
        vx: (Math.random() - 0.5) * 0.2,
        a: Math.random() * 0.4 + 0.1,
        tw: Math.random() * Math.PI * 2,
      });
    }
  }
  function spawnMeteor() {
    meteors.push({
      x: W * (0.1 + Math.random() * 0.9),
      y: Math.random() * H * 0.4,
      vx: -(6 + Math.random() * 7),
      vy: 2.2 + Math.random() * 2.5,
      life: 0,
      max: 65 + Math.random() * 40,
    });
  }
  function tick(ts) {
    if (!ctx) return;
    var dt = lastTs ? ts - lastTs : 16.7;
    lastTs = ts;
    ctx.clearRect(0, 0, W, H);
    for (var i = 0; i < particles.length; i++) {
      var p = particles[i];
      p.y += p.vy;
      p.x += p.vx + Math.sin(p.tw) * 0.12;
      p.tw += 0.01;
      if (p.y > H + 8) { p.y = -8; p.x = Math.random() * W; }
      if (p.x < -8) p.x = W + 8;
      if (p.x > W + 8) p.x = -8;
      var twinkle = 0.7 + 0.3 * Math.sin(p.tw * 2);
      if (p.r > 1.5) {
        var g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 3);
        g.addColorStop(0, "rgba(255,255,255," + (p.a * twinkle).toFixed(3) + ")");
        g.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r * 3, 0, Math.PI * 2); ctx.fill();
      } else {
        ctx.globalAlpha = p.a * twinkle;
        ctx.fillStyle = "#ffffff";
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
    nextMeteor -= dt;
    if (nextMeteor <= 0 && meteors.length < 3) {
      spawnMeteor();
      nextMeteor = 1200 + Math.random() * 1800;
    }
    for (var m = meteors.length - 1; m >= 0; m--) {
      var st = meteors[m];
      st.x += st.vx; st.y += st.vy; st.life++;
      var fade = Math.max(0, 1 - st.life / st.max);
      var tailX = st.x - st.vx * 7;
      var tailY = st.y - st.vy * 7;
      var grad = ctx.createLinearGradient(st.x, st.y, tailX, tailY);
      grad.addColorStop(0, "rgba(255,255,255," + (0.7 * fade).toFixed(3) + ")");
      grad.addColorStop(1, "rgba(255,255,255,0)");
      ctx.strokeStyle = grad;
      ctx.lineWidth = 1.6;
      ctx.lineCap = "round";
      ctx.beginPath(); ctx.moveTo(st.x, st.y); ctx.lineTo(tailX, tailY); ctx.stroke();
      if (st.life >= st.max || st.x < -60 || st.y > H + 20) meteors.splice(m, 1);
    }
    requestAnimationFrame(tick);
  }
  if (canvas && ctx && !reducedMotion) {
    resizeCanvas(); spawnParticles(); requestAnimationFrame(tick);
    window.addEventListener("resize", function () { resizeCanvas(); spawnParticles(); });
  }

  /* ── Cursor glow (desktop only) ────────────────────────────── */
  var glow = document.querySelector(".cursor-glow");
  if (glow && finePointer && !reducedMotion) {
    var gx = window.innerWidth / 2, gy = window.innerHeight / 3;
    var cx = gx, cy = gy, shown = false;
    document.addEventListener("mousemove", function (e) {
      gx = e.clientX; gy = e.clientY;
      if (!shown) { shown = true; glow.style.opacity = "1"; }
    });
    function renderGlow() {
      cx += (gx - cx) * 0.12;
      cy += (gy - cy) * 0.12;
      glow.style.transform = "translate3d(" + (cx - 260) + "px," + (cy - 260) + "px,0)";
      requestAnimationFrame(renderGlow);
    }
    renderGlow();
  }

  /* ── Scroll reveal (staggered) ─────────────────────────────── */
  var revealEls = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          var el = entry.target;
          var parent = el.parentElement;
          if (parent) {
            var idx = Array.prototype.indexOf.call(parent.children, el);
            el.style.transitionDelay = (idx % 8) * 70 + "ms";
          }
          el.classList.add("in");
          io.unobserve(el);
          var cleaned = false;
          function cleanup() {
            if (cleaned) return; cleaned = true;
            el.classList.remove("reveal", "in");
            el.style.transitionDelay = "";
          }
          el.addEventListener("transitionend", function (ev) {
            if (ev.target === el && ev.propertyName === "opacity") cleanup();
          });
          setTimeout(cleanup, 1500);
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("in"); });
  }

  /* ── Stats count-up ────────────────────────────────────────── */
  var counters = document.querySelectorAll(".count");
  function runCount(el) {
    var target = parseFloat(el.getAttribute("data-target") || "0");
    var suffix = el.getAttribute("data-suffix") || "";
    if (reducedMotion) { el.textContent = target + suffix; return; }
    el.textContent = "0";
    var dur = 1500, t0 = null;
    function step(ts) {
      if (!t0) t0 = ts;
      var p = Math.min((ts - t0) / dur, 1);
      var eased = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.round(target * eased) + suffix;
      if (p < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }
  var statsEl = document.querySelector(".stats");
  if (counters.length && statsEl && "IntersectionObserver" in window) {
    var so = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { counters.forEach(runCount); so.disconnect(); }
      });
    }, { threshold: 0.4 });
    so.observe(statsEl);
  } else if (counters.length) { counters.forEach(runCount); }

  /* ── 3D tilt on cards & mascots (desktop only) ─────────────── */
  if (finePointer && !reducedMotion) {
    var tiltables = document.querySelectorAll(".card, .mascot-card");
    tiltables.forEach(function (el) {
      el.addEventListener("mousemove", function (e) {
        var r = el.getBoundingClientRect();
        var px = (e.clientX - r.left) / r.width - 0.5;
        var py = (e.clientY - r.top) / r.height - 0.5;
        el.style.transform = "perspective(760px) rotateX(" + (-py * 4) + "deg) rotateY(" + (px * 4) + "deg) translateY(-4px)";
      });
      el.addEventListener("mouseleave", function () { el.style.transform = ""; });
    });
  }

  /* ── Price comparison bar animation ─────────────────────────── */
  var compareCard = document.querySelector(".compare-card");
  if (compareCard && "IntersectionObserver" in window && !reducedMotion) {
    var bars = compareCard.querySelectorAll(".compare-bar");
    // Save target widths
    var targets = [];
    bars.forEach(function (b) { targets.push(b.style.getPropertyValue("--bar-w")); b.style.width = "0%"; });
    var cso = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          bars.forEach(function (b, i) {
            setTimeout(function () { b.style.width = targets[i]; }, 200 + i * 150);
          });
          cso.disconnect();
        }
      });
    }, { threshold: 0.3 });
    cso.observe(compareCard);
  }

  /* ── Mobile nav menu ────────────────────────────────────────── */
  var burger = document.querySelector(".nav-burger");
  var navMenu = document.getElementById("nav-menu");
  if (burger && navMenu) {
    function closeMenu() {
      navMenu.classList.remove("open");
      burger.classList.remove("active");
      burger.setAttribute("aria-expanded", "false");
      burger.setAttribute("aria-label", "Abrir menú");
    }
    burger.addEventListener("click", function () {
      var open = navMenu.classList.toggle("open");
      burger.classList.toggle("active", open);
      burger.setAttribute("aria-expanded", open ? "true" : "false");
      burger.setAttribute("aria-label", open ? "Cerrar menú" : "Abrir menú");
    });
    navMenu.addEventListener("click", function (e) {
      if (e.target && e.target.closest && e.target.closest("a")) closeMenu();
    });
    document.addEventListener("click", function (e) {
      if (!e.target.closest(".nav") && navMenu.classList.contains("open")) closeMenu();
    });
  }
})();
