/**
 * canvas.js — Cursor-reactive mycelial / circuit / neuron growth
 *
 * Patterns grow from where the cursor moves. Branches fork,
 * make occasional 90° circuit-board turns, and fade over time.
 * Small pad/synapse nodes appear at junctions.
 */

(function () {
  "use strict";

  // ─── Theme-aware palettes ────────────────────────────────────────────────
  var PALETTES = {
    dark: {
      colors: [
        { r: 122, g: 170, b: 106 },  // forest
        { r: 142, g: 196, b: 114 },  // moss
        { r: 196, g: 120, b: 56  },  // copper
        { r: 72,  g: 184, b: 144 },  // teal
        { r: 212, g: 160, b: 48  },  // gold
        { r: 90,  g: 172, b: 204 },  // signal
      ],
      fade: "rgba(13,16,10,0.035)"
    },
    light: {
      colors: [
        { r: 30,  g: 58,  b: 16  },  // forest
        { r: 60,  g: 98,  b: 22  },  // moss
        { r: 148, g: 72,  b: 24  },  // copper
        { r: 26,  g: 120, b: 96  },  // teal
        { r: 168, g: 112, b: 16  },  // gold
        { r: 42,  g: 104, b: 136 },  // signal
      ],
      fade: "rgba(237,229,212,0.035)"
    }
  };

  var currentTheme = (document.documentElement.getAttribute("data-theme") || "dark");
  var COLORS = PALETTES[currentTheme].colors;
  var fadeFill = PALETTES[currentTheme].fade;

  window.addEventListener("theme-change", function (e) {
    currentTheme = e.detail.theme;
    COLORS = PALETTES[currentTheme].colors;
    fadeFill = PALETTES[currentTheme].fade;
    // Clear canvas on theme switch to avoid ghosting
    if (ctx) { ctx.clearRect(0, 0, W, H); }
    nodes = [];
  });

  // ─── Config per depth — intentionally subtle ────────────────────────────
  var DEPTH_CONFIG = {
    1: { branchCount: 2, maxLen: 50,  forkRate: 0.012, opacity: 0.22, fadeRate: 0.0014 },
    2: { branchCount: 2, maxLen: 60,  forkRate: 0.015, opacity: 0.25, fadeRate: 0.0012 },
    3: { branchCount: 3, maxLen: 70,  forkRate: 0.018, opacity: 0.28, fadeRate: 0.0010 },
    4: { branchCount: 3, maxLen: 80,  forkRate: 0.022, opacity: 0.32, fadeRate: 0.0008 },
    5: { branchCount: 4, maxLen: 120, forkRate: 0.03,  opacity: 0.40, fadeRate: 0.0004 },
  };

  var canvas, ctx, cfg;
  var W, H;
  var mouseX = -999, mouseY = -999;
  var lastSpawnX = -999, lastSpawnY = -999;
  var nodes = [];        // active growth nodes
  var MAX_NODES = 30;    // cap lower — keep it sparse
  var SPAWN_DIST = 45;   // spawn less frequently
  var frameId;

  // ─── Public API ───────────────────────────────────────────────────────────
  window.initCanvas = function (depth) {
    depth = Math.max(1, Math.min(4, depth || 1));
    cfg = DEPTH_CONFIG[depth];

    canvas = document.getElementById("mycelium-canvas");
    if (!canvas) return;
    ctx = canvas.getContext("2d");

    resize();
    window.addEventListener("resize", resize);
    window.addEventListener("mousemove", onMouse);
    window.addEventListener("touchmove", onTouch, { passive: true });

    if (frameId) cancelAnimationFrame(frameId);
    loop();
  };

  function resize() {
    W = canvas.width  = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }

  function onMouse(e) {
    mouseX = e.clientX;
    mouseY = e.clientY;
    maybeSpawn();
  }

  function onTouch(e) {
    if (e.touches.length > 0) {
      mouseX = e.touches[0].clientX;
      mouseY = e.touches[0].clientY;
      maybeSpawn();
    }
  }

  // ─── Spawn new growth node at cursor ──────────────────────────────────────
  function maybeSpawn() {
    var dx = mouseX - lastSpawnX;
    var dy = mouseY - lastSpawnY;
    if (dx * dx + dy * dy < SPAWN_DIST * SPAWN_DIST) return;

    lastSpawnX = mouseX;
    lastSpawnY = mouseY;

    // Evict oldest if at cap
    if (nodes.length >= MAX_NODES) nodes.shift();

    var color = COLORS[Math.floor(Math.random() * COLORS.length)];
    var node = {
      branches: [],
      age: 0,
      opacity: cfg.opacity,
      color: color,
    };

    // Spawn branches in varied directions
    var numBranches = cfg.branchCount + (Math.random() < 0.3 ? 1 : 0);
    var baseAngle = Math.random() * Math.PI * 2;
    for (var i = 0; i < numBranches; i++) {
      var angle = baseAngle + (i / numBranches) * Math.PI * 2 + (Math.random() - 0.5) * 0.8;
      node.branches.push(createBranch(mouseX, mouseY, angle, color, 0));
    }

    nodes.push(node);
  }

  function createBranch(x, y, angle, color, generation) {
    return {
      segments: [{ x: x, y: y }],
      angle: angle,
      speed: 0.6 + Math.random() * 1.0,
      thickness: Math.max(0.3, 1.2 - generation * 0.25 + Math.random() * 0.4),
      growing: true,
      maxLength: cfg.maxLen * (0.5 + Math.random() * 0.7) / (1 + generation * 0.4),
      color: color,
      generation: generation,
      children: [],
    };
  }

  // ─── Animation loop ──────────────────────────────────────────────────────
  function loop() {
    frameId = requestAnimationFrame(loop);

    // Fade previous frame — slow dissolve back into background
    ctx.fillStyle = fadeFill;
    ctx.fillRect(0, 0, W, H);

    for (var n = nodes.length - 1; n >= 0; n--) {
      var node = nodes[n];
      node.age++;
      node.opacity -= cfg.fadeRate;

      if (node.opacity <= 0) {
        nodes.splice(n, 1);
        continue;
      }

      growAndDraw(node);
    }
  }

  function growAndDraw(node) {
    var allBranches = collectBranches(node.branches);

    for (var i = 0; i < allBranches.length; i++) {
      var b = allBranches[i];

      // Grow
      if (b.growing && b.segments.length < b.maxLength) {
        var last = b.segments[b.segments.length - 1];

        // Organic wobble
        b.angle += (Math.random() - 0.5) * 0.35;

        // Occasional circuit-board 90° snap
        if (Math.random() < 0.018) {
          b.angle = Math.round(b.angle / (Math.PI / 2)) * (Math.PI / 2);
          b.angle += (Math.random() - 0.5) * 0.15;
        }

        var nx = last.x + Math.cos(b.angle) * b.speed;
        var ny = last.y + Math.sin(b.angle) * b.speed;

        // Stop if out of bounds
        if (nx < -20 || nx > W + 20 || ny < -20 || ny > H + 20) {
          b.growing = false;
        } else {
          b.segments.push({ x: nx, y: ny });

          // Fork — spawn child branch
          if (b.generation < 3 && Math.random() < cfg.forkRate && b.segments.length > 8) {
            var forkAngle = b.angle + (Math.random() < 0.5 ? 1 : -1) * (0.4 + Math.random() * 0.8);
            b.children.push(createBranch(nx, ny, forkAngle, b.color, b.generation + 1));
          }
        }
      } else {
        b.growing = false;
      }

      // Draw
      if (b.segments.length < 2) continue;

      var alpha = Math.min(1, node.opacity) * (1 - b.generation * 0.2);
      if (alpha <= 0) continue;

      ctx.beginPath();
      ctx.moveTo(b.segments[0].x, b.segments[0].y);
      for (var s = 1; s < b.segments.length; s++) {
        ctx.lineTo(b.segments[s].x, b.segments[s].y);
      }
      ctx.strokeStyle = rgba(b.color, alpha);
      ctx.lineWidth = b.thickness;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke();

      // Junction pad at branch origin (circuit/synapse feel)
      if (b.generation > 0 && b.segments.length > 2) {
        var origin = b.segments[0];
        ctx.beginPath();
        ctx.arc(origin.x, origin.y, 2 + b.thickness, 0, Math.PI * 2);
        ctx.fillStyle = rgba(b.color, alpha * 0.5);
        ctx.fill();
        ctx.beginPath();
        ctx.arc(origin.x, origin.y, 1, 0, Math.PI * 2);
        ctx.fillStyle = rgba(b.color, alpha * 0.8);
        ctx.fill();
      }

      // Terminal bulb on finished branches (neuron synapse)
      if (!b.growing && b.segments.length > 4) {
        var tip = b.segments[b.segments.length - 1];
        ctx.beginPath();
        ctx.arc(tip.x, tip.y, 1.5 + b.thickness * 0.5, 0, Math.PI * 2);
        ctx.fillStyle = rgba(b.color, alpha * 0.6);
        ctx.fill();
      }
    }
  }

  // Collect all branches + children recursively into flat array
  function collectBranches(branches) {
    var result = [];
    for (var i = 0; i < branches.length; i++) {
      result.push(branches[i]);
      if (branches[i].children.length > 0) {
        var sub = collectBranches(branches[i].children);
        for (var j = 0; j < sub.length; j++) result.push(sub[j]);
      }
    }
    return result;
  }

  function rgba(c, a) {
    return "rgba(" + c.r + "," + c.g + "," + c.b + "," + Math.max(0, Math.min(1, a)) + ")";
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SEED FIELD — mycelial network of vision nodes
  //  Replaces bubble physics on the declaration page.
  //  Nodes are positioned via force-directed layout, connected by living
  //  mycelial branches that grow between them.
  // ══════════════════════════════════════════════════════════════════════════

  window.initSeedField = function (canvasEl, seeds, userText) {
    var sfCanvas = canvasEl;
    var sfCtx    = sfCanvas.getContext("2d");
    var sfW, sfH;
    var sfMouse  = { x: -9999, y: -9999 };
    var sfNodes  = [];
    var sfBranches = [];     // living branches between nodes
    var sfCfg    = DEPTH_CONFIG[5];
    var sfFrame  = 0;
    var sfAnimId;

    // ── Theme palette access (reuses the module-level PALETTES) ──
    function sfColor() { return PALETTES[currentTheme].colors; }
    function sfFade()  { return PALETTES[currentTheme].fade; }

    // ── Resize ──
    function sfResize() {
      sfW = sfCanvas.width  = window.innerWidth;
      sfH = sfCanvas.height = window.innerHeight;
    }
    sfResize();
    window.addEventListener("resize", sfResize, { passive: true });

    // ── Mouse tracking ──
    sfCanvas.addEventListener("mousemove", function (e) {
      sfMouse.x = e.clientX;
      sfMouse.y = e.clientY;
    });
    sfCanvas.addEventListener("mouseleave", function () {
      sfMouse.x = -9999;
      sfMouse.y = -9999;
    });
    sfCanvas.addEventListener("touchmove", function (e) {
      if (e.touches.length > 0) {
        sfMouse.x = e.touches[0].clientX;
        sfMouse.y = e.touches[0].clientY;
      }
    }, { passive: true });

    // ── Create SeedNode objects ──
    var palette = sfColor();

    // User node first
    sfNodes.push({
      x: sfW / 2,
      y: sfH / 2,
      text: userText,
      isUser: true,
      r: 8,
      glowAlpha: 0,
      targetAlpha: 1,
      color: palette[0],
      hovered: false,
      revealWords: 0,
      spawnTimer: Math.floor(Math.random() * 60),
      fadeInDelay: 0,    // user appears first
      born: false,
    });

    // Seeded visions
    for (var i = 0; i < seeds.length; i++) {
      var text = seeds[i];
      sfNodes.push({
        x: sfW / 2 + (Math.random() - 0.5) * 100,
        y: sfH / 2 + (Math.random() - 0.5) * 100,
        text: text,
        isUser: false,
        r: 3 + Math.min(text.length / 50, 3),
        glowAlpha: 0,
        targetAlpha: 1,
        color: palette[Math.floor(Math.random() * palette.length)],
        hovered: false,
        revealWords: 0,
        spawnTimer: Math.floor(Math.random() * 120),
        fadeInDelay: 30 + Math.floor(Math.random() * 150),  // staggered 0.5-3s
        born: false,
      });
    }

    // ── Force-directed layout — 80 iterations before display ──
    forceLayout(80);

    function forceLayout(iterations) {
      var cx = sfW / 2, cy = sfH / 2;
      var n = sfNodes.length;

      for (var iter = 0; iter < iterations; iter++) {
        for (var i = 0; i < n; i++) {
          var ni = sfNodes[i];
          var fx = 0, fy = 0;

          // Repulsion from all other nodes
          for (var j = 0; j < n; j++) {
            if (i === j) continue;
            var nj = sfNodes[j];
            var dx = ni.x - nj.x;
            var dy = ni.y - nj.y;
            var dist = Math.sqrt(dx * dx + dy * dy) || 1;
            var repulse = 4000 / (dist * dist);
            fx += (dx / dist) * repulse;
            fy += (dy / dist) * repulse;
          }

          // Attraction to center
          var toCenterX = cx - ni.x;
          var toCenterY = cy - ni.y;
          fx += toCenterX * 0.005;
          fy += toCenterY * 0.005;

          // User node has stronger center pull
          if (ni.isUser) {
            fx += toCenterX * 0.02;
            fy += toCenterY * 0.02;
          }

          // Apply with damping
          ni.x += fx * 0.4;
          ni.y += fy * 0.4;

          // Keep within bounds with padding
          var pad = 60;
          ni.x = Math.max(pad, Math.min(sfW - pad, ni.x));
          ni.y = Math.max(pad, Math.min(sfH - pad, ni.y));
        }
      }
    }

    // ── Branch creation (reuses module createBranch but with seed field config) ──
    function sfCreateBranch(x, y, angle, color, generation) {
      return {
        segments: [{ x: x, y: y }],
        angle: angle,
        speed: 0.6 + Math.random() * 1.0,
        thickness: Math.max(0.3, 1.2 - generation * 0.25 + Math.random() * 0.4),
        growing: true,
        maxLength: sfCfg.maxLen * (0.5 + Math.random() * 0.7) / (1 + generation * 0.4),
        color: color,
        generation: generation,
        children: [],
        opacity: sfCfg.opacity,
        age: 0,
      };
    }

    // Spawn a branch from one node toward a target point
    function spawnBranchToward(fromNode, tx, ty) {
      var angle = Math.atan2(ty - fromNode.y, tx - fromNode.x);
      angle += (Math.random() - 0.5) * 0.6; // slight variation
      var branch = sfCreateBranch(fromNode.x, fromNode.y, angle, fromNode.color, 0);
      sfBranches.push(branch);
    }

    // ── Grow and draw a single branch ──
    function sfGrowBranch(b) {
      if (b.growing && b.segments.length < b.maxLength) {
        var last = b.segments[b.segments.length - 1];

        // Organic wobble
        b.angle += (Math.random() - 0.5) * 0.35;

        // Occasional circuit-board 90° snap
        if (Math.random() < 0.018) {
          b.angle = Math.round(b.angle / (Math.PI / 2)) * (Math.PI / 2);
          b.angle += (Math.random() - 0.5) * 0.15;
        }

        var nx = last.x + Math.cos(b.angle) * b.speed;
        var ny = last.y + Math.sin(b.angle) * b.speed;

        if (nx < -20 || nx > sfW + 20 || ny < -20 || ny > sfH + 20) {
          b.growing = false;
        } else {
          b.segments.push({ x: nx, y: ny });

          // Fork
          if (b.generation < 3 && Math.random() < sfCfg.forkRate && b.segments.length > 8) {
            var forkAngle = b.angle + (Math.random() < 0.5 ? 1 : -1) * (0.4 + Math.random() * 0.8);
            b.children.push(sfCreateBranch(nx, ny, forkAngle, b.color, b.generation + 1));
          }
        }
      } else {
        b.growing = false;
      }
    }

    function sfDrawBranch(b, parentOpacity) {
      if (b.segments.length < 2) return;

      var alpha = Math.min(1, parentOpacity) * (1 - b.generation * 0.2);
      if (alpha <= 0) return;

      sfCtx.beginPath();
      sfCtx.moveTo(b.segments[0].x, b.segments[0].y);
      for (var s = 1; s < b.segments.length; s++) {
        sfCtx.lineTo(b.segments[s].x, b.segments[s].y);
      }
      sfCtx.strokeStyle = rgba(b.color, alpha);
      sfCtx.lineWidth = b.thickness;
      sfCtx.lineCap = "round";
      sfCtx.lineJoin = "round";
      sfCtx.stroke();

      // Junction pad at branch origin
      if (b.generation > 0 && b.segments.length > 2) {
        var origin = b.segments[0];
        sfCtx.beginPath();
        sfCtx.arc(origin.x, origin.y, 2 + b.thickness, 0, Math.PI * 2);
        sfCtx.fillStyle = rgba(b.color, alpha * 0.5);
        sfCtx.fill();
        sfCtx.beginPath();
        sfCtx.arc(origin.x, origin.y, 1, 0, Math.PI * 2);
        sfCtx.fillStyle = rgba(b.color, alpha * 0.8);
        sfCtx.fill();
      }

      // Terminal bulb
      if (!b.growing && b.segments.length > 4) {
        var tip = b.segments[b.segments.length - 1];
        sfCtx.beginPath();
        sfCtx.arc(tip.x, tip.y, 1.5 + b.thickness * 0.5, 0, Math.PI * 2);
        sfCtx.fillStyle = rgba(b.color, alpha * 0.6);
        sfCtx.fill();
      }

      // Recurse children
      for (var c = 0; c < b.children.length; c++) {
        sfGrowBranch(b.children[c]);
        sfDrawBranch(b.children[c], parentOpacity);
      }
    }

    // ── Draw a seed node as a glowing junction pad ──
    function drawSeedNode(node) {
      if (node.glowAlpha < 0.01) return;

      var pulse = node.isUser ? 1 + 0.32 * Math.sin(sfFrame * 0.05) : 1;
      var r = node.r * pulse;
      var col = node.color;

      sfCtx.save();

      // Outer glow halo
      var glowR = r * (node.hovered ? 5 : (node.isUser ? 5 : 3.5));
      var grd = sfCtx.createRadialGradient(node.x, node.y, 0, node.x, node.y, glowR);
      var glowStrength = node.hovered ? 0.30 : (node.isUser ? 0.28 : 0.15);
      grd.addColorStop(0,   rgba(col, node.glowAlpha * glowStrength));
      grd.addColorStop(0.5, rgba(col, node.glowAlpha * glowStrength * 0.35));
      grd.addColorStop(1,   rgba(col, 0));
      sfCtx.beginPath();
      sfCtx.arc(node.x, node.y, glowR, 0, Math.PI * 2);
      sfCtx.fillStyle = grd;
      sfCtx.fill();

      // Expanding ring — only on the user's seed, to draw the eye
      if (node.isUser) {
        var ringPhase = (sfFrame % 120) / 120;
        var ringR = r * (1.4 + ringPhase * 3.8);
        var ringAlpha = node.glowAlpha * (1 - ringPhase) * 0.55;
        sfCtx.beginPath();
        sfCtx.arc(node.x, node.y, ringR, 0, Math.PI * 2);
        sfCtx.strokeStyle = rgba(col, ringAlpha);
        sfCtx.lineWidth = 1.2;
        sfCtx.stroke();
      }

      // Core pad (larger than normal junctions)
      sfCtx.beginPath();
      sfCtx.arc(node.x, node.y, r, 0, Math.PI * 2);
      sfCtx.fillStyle = rgba(col, node.glowAlpha * (node.hovered ? 0.95 : 0.75));
      sfCtx.fill();

      // Inner bright center
      sfCtx.beginPath();
      sfCtx.arc(node.x, node.y, r * 0.45, 0, Math.PI * 2);
      sfCtx.fillStyle = rgba(col, node.glowAlpha * 0.95);
      sfCtx.fill();

      sfCtx.restore();
    }

    // ── Draw text box (word-by-word reveal, styled like bubble text boxes) ──
    function drawSeedText(node) {
      if (node.revealWords < 1) return;

      var allWords = node.text.split(" ");
      var revealed = allWords.slice(0, node.revealWords).join(" ");

      // Use bp palette from script.js context — but we're in canvas.js,
      // so replicate the styling with the node's own color
      var maxTextW = 220;
      var pad      = 14;
      var lh       = 19;

      sfCtx.font = "italic 13px 'Source Serif 4', Georgia, serif";
      var words = revealed.split(" ");
      var lines = [], line = "";
      for (var i = 0; i < words.length; i++) {
        var test = line ? line + " " + words[i] : words[i];
        if (sfCtx.measureText(test).width > maxTextW && line) {
          lines.push(line); line = words[i];
        } else { line = test; }
      }
      if (line) lines.push(line);

      var boxW = maxTextW + pad * 2;
      var boxH = lines.length * lh + pad * 1.8;

      // Position near node (keep in bounds)
      var bx = node.x + node.r * 2 + 12;
      var by = node.y - boxH / 2;
      if (bx + boxW > sfW - 8) bx = node.x - boxW - node.r * 2 - 12;
      by = Math.max(8, Math.min(sfH - boxH - 8, by));

      sfCtx.save();
      sfCtx.globalAlpha = Math.min(1, node.revealWords / 3);

      // Box background — themed
      var isDark = currentTheme === "dark";
      sfCtx.fillStyle = isDark ? "rgba(13,16,10,0.95)" : "rgba(237,229,212,0.97)";
      sfCtx.strokeStyle = rgba(node.color, node.isUser ? 0.45 : 0.28);
      sfCtx.lineWidth = 1.0;
      sfCtx.beginPath();
      sfCtx.rect(bx, by, boxW, boxH);
      sfCtx.fill();
      sfCtx.stroke();

      // Text
      sfCtx.fillStyle = node.isUser
        ? (isDark ? "rgba(122,170,106,0.95)" : "rgba(30,58,16,0.95)")
        : (isDark ? "rgba(226,218,200,0.88)" : "rgba(26,20,8,0.88)");
      sfCtx.font = "italic 13px 'Source Serif 4', Georgia, serif";
      sfCtx.textAlign = "left";
      for (var li = 0; li < lines.length; li++) {
        sfCtx.fillText(lines[li], bx + pad, by + pad + (li + 1) * lh - 3);
      }

      sfCtx.restore();
    }

    // ── Main animation loop ──
    function sfLoop() {
      sfAnimId = requestAnimationFrame(sfLoop);
      sfFrame++;

      // Fade previous frame
      sfCtx.fillStyle = sfFade();
      sfCtx.fillRect(0, 0, sfW, sfH);

      var n = sfNodes.length;

      // ── Update nodes ──
      for (var i = 0; i < n; i++) {
        var nd = sfNodes[i];

        // Sequential fade-in: don't activate until delay is met
        if (!nd.born) {
          if (sfFrame >= nd.fadeInDelay) {
            nd.born = true;
          } else {
            continue;
          }
        }

        // Fade in glow
        nd.glowAlpha = Math.min(nd.targetAlpha, nd.glowAlpha + 0.012);

        // Mouse distance
        var mdx = nd.x - sfMouse.x;
        var mdy = nd.y - sfMouse.y;
        var mDist = Math.sqrt(mdx * mdx + mdy * mdy) || 9999;

        // Hover detection (within r * 2)
        nd.hovered = (mDist < nd.r * 2 + 6);

        // Mouse proximity — within 80px: brighten and attract
        if (mDist < 80 && !nd.hovered) {
          nd.glowAlpha = Math.min(1, nd.glowAlpha + 0.02);
          // Send a branch toward cursor occasionally
          if (Math.random() < 0.008 && nd.born) {
            spawnBranchToward(nd, sfMouse.x, sfMouse.y);
          }
        }

        // Gentle attraction toward cursor when nearby (REVERSED from repulsion)
        if (mDist < 130 && mDist > 10) {
          var attractStrength = (1 - mDist / 130) * 0.15;
          nd.x -= (mdx / mDist) * attractStrength;
          nd.y -= (mdy / mDist) * attractStrength;
        }

        // When hovered: expand glow, reveal words
        if (nd.hovered) {
          nd.glowAlpha = Math.min(1, nd.glowAlpha + 0.04);
          var totalWords = nd.text.split(" ").length;
          nd.revealWords = Math.min(totalWords, nd.revealWords + 0.15);
        } else {
          // Slow fade-out of reveal
          if (nd.revealWords > 0) nd.revealWords = Math.max(0, nd.revealWords - 0.3);
        }

        // Periodic branch spawning toward a random nearby node
        nd.spawnTimer++;
        var spawnInterval = 60 + Math.floor(Math.random() * 60);
        if (nd.spawnTimer > spawnInterval && nd.born) {
          nd.spawnTimer = 0;
          // Find a random nearby node to branch toward
          var candidates = [];
          for (var j = 0; j < n; j++) {
            if (j === i || !sfNodes[j].born) continue;
            var cdx = sfNodes[j].x - nd.x;
            var cdy = sfNodes[j].y - nd.y;
            var cDist = Math.sqrt(cdx * cdx + cdy * cdy);
            if (cDist < 250) candidates.push(sfNodes[j]);
          }
          if (candidates.length > 0) {
            var target = candidates[Math.floor(Math.random() * candidates.length)];
            spawnBranchToward(nd, target.x, target.y);
          }
        }

        // Soft boundary repulsion (keep nodes from drifting off-screen)
        var m = 50;
        if (nd.x < m)      nd.x += 0.3;
        if (nd.x > sfW - m) nd.x -= 0.3;
        if (nd.y < m)      nd.y += 0.3;
        if (nd.y > sfH - m) nd.y -= 0.3;
      }

      // ── Grow and draw branches ──
      for (var bi = sfBranches.length - 1; bi >= 0; bi--) {
        var br = sfBranches[bi];
        br.age++;
        br.opacity -= sfCfg.fadeRate;

        if (br.opacity <= 0) {
          sfBranches.splice(bi, 1);
          continue;
        }

        sfGrowBranch(br);
        sfDrawBranch(br, br.opacity);
      }

      // Cap total branches to prevent performance degradation
      while (sfBranches.length > 120) {
        sfBranches.shift();
      }

      // ── Draw nodes (non-hovered first, hovered on top) ──
      var hoveredNode = null;
      for (var di = 0; di < n; di++) {
        var dNode = sfNodes[di];
        if (!dNode.born) continue;
        if (!dNode.hovered) {
          drawSeedNode(dNode);
        } else {
          hoveredNode = dNode;
        }
      }
      if (hoveredNode) {
        drawSeedNode(hoveredNode);
        drawSeedText(hoveredNode);
      }
    }

    // ── Expose update info for external counter ──
    window._seedFieldNodeCount = function () {
      var count = 0;
      for (var i = 0; i < sfNodes.length; i++) {
        if (sfNodes[i].born) count++;
      }
      return count;
    };

    // ── Start the loop ──
    sfLoop();

    // Return cleanup handle
    return {
      stop: function () {
        if (sfAnimId) cancelAnimationFrame(sfAnimId);
      }
    };
  };
})();
