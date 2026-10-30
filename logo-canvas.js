/**
 * logo-canvas.js — Miniature mycelium growth inside the logo mark
 *
 * Normal state: gentle, sparse growth from center.
 * Hover state: explosive growth — branches multiply rapidly and
 * fill the entire circle. Growth stays as long as hovered.
 */

(function () {
  "use strict";

  var canvas = document.getElementById("logo-canvas");
  if (!canvas) return;

  var ctx = canvas.getContext("2d");
  // Steward pages reuse the website's mark without a continuous animation.
  var staticMark = canvas.hasAttribute("data-static");
  var S = 76;
  var CX = S / 2, CY = S / 2;
  var R = 34; // circle radius
  var branches = [];
  var MAX_BRANCHES_NORMAL = 8;
  var MAX_BRANCHES_HOVER = 60;
  var spawnTimer = 0;
  var SPAWN_NORMAL = 90;
  var SPAWN_HOVER = 6; // much faster on hover
  var isHovered = false;

  var PALETTES = {
    dark: {
      colors: [
        { r: 122, g: 170, b: 106 },
        { r: 142, g: 196, b: 114 },
        { r: 196, g: 120, b: 56 },
        { r: 72,  g: 184, b: 144 },
        { r: 212, g: 160, b: 48 },
      ],
      fade: "rgba(13,16,10,0.06)",
      fadeHover: "rgba(13,16,10,0.008)"
    },
    light: {
      colors: [
        { r: 30,  g: 58,  b: 16 },
        { r: 60,  g: 98,  b: 22 },
        { r: 148, g: 72,  b: 24 },
        { r: 26,  g: 120, b: 96 },
        { r: 168, g: 112, b: 16 },
      ],
      fade: "rgba(237,229,212,0.06)",
      fadeHover: "rgba(237,229,212,0.008)"
    }
  };

  var theme = document.documentElement.getAttribute("data-theme") || "dark";
  var pal = PALETTES[theme];

  window.addEventListener("theme-change", function (e) {
    theme = e.detail.theme;
    pal = PALETTES[theme];
    ctx.clearRect(0, 0, S, S);
    branches = [];
    if (staticMark) renderStatic();
  });

  // Hover detection on the logo-mark container
  var logoMark = canvas.closest(".logo-mark");
  if (logoMark && !staticMark) {
    logoMark.addEventListener("mouseenter", function () { isHovered = true; });
    logoMark.addEventListener("mouseleave", function () { isHovered = false; });
  }

  function rgba(c, a) {
    return "rgba(" + c.r + "," + c.g + "," + c.b + "," + Math.max(0, Math.min(1, a)) + ")";
  }

  function spawnBranch() {
    var max = isHovered ? MAX_BRANCHES_HOVER : MAX_BRANCHES_NORMAL;
    if (branches.length >= max) {
      if (!isHovered) branches.shift();
      else return; // don't evict on hover — let it fill
    }

    // On hover, spawn from random points across the circle, not just center
    var sx, sy;
    if (isHovered && Math.random() > 0.3) {
      var angle = Math.random() * Math.PI * 2;
      var dist = Math.random() * R * 0.7;
      sx = CX + Math.cos(angle) * dist;
      sy = CY + Math.sin(angle) * dist;
    } else {
      sx = CX + (Math.random() - 0.5) * 6;
      sy = CY + (Math.random() - 0.5) * 6;
    }

    var a = Math.random() * Math.PI * 2;
    var color = pal.colors[Math.floor(Math.random() * pal.colors.length)];
    var hoverBoost = isHovered ? 1.4 : 1;

    branches.push({
      segments: [{ x: sx, y: sy }],
      angle: a,
      speed: (0.3 + Math.random() * 0.5) * hoverBoost,
      thickness: (0.5 + Math.random() * 0.5) * hoverBoost,
      growing: true,
      maxLen: Math.floor((12 + Math.random() * 18) * hoverBoost),
      color: color,
      opacity: isHovered ? 0.65 : 0.45,
      children: []
    });
  }

  function growBranch(b) {
    if (!b.growing || b.segments.length >= b.maxLen) {
      b.growing = false;
      return;
    }

    var last = b.segments[b.segments.length - 1];
    b.angle += (Math.random() - 0.5) * 0.5;

    if (Math.random() < 0.03) {
      b.angle = Math.round(b.angle / (Math.PI / 2)) * (Math.PI / 2);
    }

    var nx = last.x + Math.cos(b.angle) * b.speed;
    var ny = last.y + Math.sin(b.angle) * b.speed;

    var dx = nx - CX, dy = ny - CY;
    if (dx * dx + dy * dy > R * R) {
      b.growing = false;
      return;
    }

    b.segments.push({ x: nx, y: ny });

    // Fork more aggressively on hover
    var forkChance = isHovered ? 0.09 : 0.04;
    var maxChildren = isHovered ? 3 : 2;
    if (b.segments.length > 4 && Math.random() < forkChance && b.children.length < maxChildren) {
      var forkAngle = b.angle + (Math.random() < 0.5 ? 1 : -1) * (0.4 + Math.random() * 0.8);
      b.children.push({
        segments: [{ x: nx, y: ny }],
        angle: forkAngle,
        speed: b.speed * 0.85,
        thickness: b.thickness * 0.7,
        growing: true,
        maxLen: Math.floor(b.maxLen * 0.65),
        color: b.color,
        opacity: b.opacity * 0.85,
        children: []
      });
    }
  }

  function drawBranch(b) {
    if (b.segments.length < 2) return;

    ctx.beginPath();
    ctx.moveTo(b.segments[0].x, b.segments[0].y);
    for (var i = 1; i < b.segments.length; i++) {
      ctx.lineTo(b.segments[i].x, b.segments[i].y);
    }
    ctx.strokeStyle = rgba(b.color, b.opacity);
    ctx.lineWidth = b.thickness;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.stroke();

    if (b.children.length > 0) {
      var forkPt = b.segments[b.segments.length - 1];
      ctx.beginPath();
      ctx.arc(forkPt.x, forkPt.y, 1.2 + (isHovered ? 0.5 : 0), 0, Math.PI * 2);
      ctx.fillStyle = rgba(b.color, b.opacity * 0.6);
      ctx.fill();
    }

    for (var c = 0; c < b.children.length; c++) {
      growBranch(b.children[c]);
      drawBranch(b.children[c]);
    }
  }

  function loop() {
    if (!staticMark) requestAnimationFrame(loop);

    // Fade slower on hover so the network fills and persists
    ctx.fillStyle = isHovered ? pal.fadeHover : pal.fade;
    ctx.fillRect(0, 0, S, S);

    // Spawn
    spawnTimer++;
    var interval = isHovered ? SPAWN_HOVER : SPAWN_NORMAL;
    if (spawnTimer >= interval) {
      spawnBranch();
      spawnTimer = 0;
    }

    // Grow and draw
    for (var i = 0; i < branches.length; i++) {
      growBranch(branches[i]);
      drawBranch(branches[i]);
      // Fade much slower on hover
      branches[i].opacity -= isHovered ? 0.0003 : 0.0015;
    }

    branches = branches.filter(function (b) { return b.opacity > 0.01; });
  }

  function renderStatic() {
    ctx.clearRect(0, 0, S, S);
    branches = [];
    spawnTimer = 0;
    spawnBranch();
    spawnBranch();
    for (var frame = 0; frame < 120; frame++) loop();
  }

  if (staticMark) renderStatic();
  else {
    spawnBranch();
    spawnBranch();
    loop();
  }
})();
