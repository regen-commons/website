/**
 * script.js — Regen Commons
 *
 * Three systems:
 *  1. Learn page — 3-step navigation
 *  2. Declaration page — Mycelial seed field (network of vision nodes)
 *  3. Map page — localStorage echo, depth bar, filter/sort/view dashboard
 */

(function () {
  "use strict";

  // ─── Pre-seeded community visions ─────────────────────────────────────────
  // Authentic practitioner voices — drawn from real regenerative movement struggles.
  var SEEDED = [
    "Knowledge that outlasts the organizations that made it.",
    "Coordination without burning out the coordinator.",
    "A place to return to — not a platform that extracts and moves on.",
    "What we've been trying to build for fifteen years, finally held somewhere.",
    "Commons for my watershed. For the whole bioregion.",
    "Governance that doesn't require a lawyer to understand.",
    "A network where contributing makes you richer, not just busier.",
    "Experiments that can fail safely, with other people watching and learning.",
    "No more silos. No more re-inventing the same wheels.",
    "Connection that crosses sectors without needing a middleman.",
    "Infrastructure that belongs to everyone who maintains it.",
    "A record of what worked — and what didn't — that doesn't disappear.",
    "Tools that make the invisible visible: who's tending what.",
    "The kind of place I could actually send someone and trust they'd be held.",
    "Regenerative movement knowledge, finally findable.",
    "A home for things that don't fit inside one organization.",
    "Exit to commons — not exit to acquisition.",
    "Shared memory across the movement.",
    "What if good governance templates were public goods?",
    "The coordination layer we actually needed.",
    "Belonging without permission.",
    "A commons that's alive — not just archived.",
    "The ground beneath the work.",
    "Weaving without centralizing.",
    "Trust infrastructure at scale.",
    "Knowledge that breathes.",
    "A place where small orgs can stand on each other's shoulders.",
    "Not just another database. A living thing.",
    "Something that persists when the grant ends.",
    "Recognition for the invisible labor.",
    "Protocol that serves the practitioner, not the platform.",
    "Bioregional knowledge held in common.",
    "The connective tissue between experiments.",
    "Reciprocity made legible.",
    "An answer to the question: where does this work live?",
    "Commons for the commons-builders.",
    "Regenerative by structure, not just by intention.",
    "A field that gets richer with every person who tends it.",
    "Memory that survives organizational collapse.",
    "Governance as care, not as control.",
    // Second wave — field practitioners, direct voices
    "No more losing the thread when the project ends.",
    "What the regenerative movement needs most is to talk to itself.",
    "A library that knows it's alive.",
    "The wisdom is already here. Help it find itself.",
    "Coordination that scales without losing accountability.",
    "A commons that outlasts every org that builds it.",
    "Making the movement legible — to itself.",
    "Soil knowledge. Watershed knowledge. Commons knowledge.",
    "The right knowledge, at the right time, without the middleman.",
    "A place where 'who knows about this' is finally answered.",
    "Grant cycles end. The commons doesn't.",
    "What if the movement knew what it knew?",
    "A network that rewards contribution over extraction.",
    "Federated. Distributed. Alive.",
    "A place to bring the practices that still have no home.",
    "Governance that holds the tension between care and accountability.",
    "Not owned. Tended.",
    "The experiments worth naming, finally named.",
    "A commons where the cost of entry is an offering.",
    "Knowledge that flows without leaking.",
    "The long arc of regeneration, held somewhere.",
    "What happens after the workshop ends.",
    "The connective layer. The one we've always needed.",
    "A place where failure is held, not hidden.",
    "Interoperability without centralization.",
    "What would it look like if the movement trusted itself?",
    "Commons that make more commons.",
    "A field that remembers.",
    "What the seed holds before it opens.",
    "Roots before branches.",
    "Mutual aid with memory.",
    "The infrastructure of trust.",
    "A living archive of what actually worked.",
    "Something we can return to when everything else changes.",
    "Connection without permission. Depth without gatekeeping.",
    "A commons that breathes back.",
    "Not a monument. A metabolism.",
    "Letting the movement hold its own history.",
    "Knowledge as commons, not commodity.",
    "A place where showing up means something.",
  ];

  // ─── Organic blob SVG path (Symphony of Vines technique) ─────────────────
  // Irregular hand-drawn ellipse — used as button border
  var BLOB_PATH = "M15 10 C38 2 78 -1 122 3 C158 6 180 14 190 30 C196 42 186 56 160 62 C132 68 88 72 52 68 C22 64 6 52 3 38 C-1 22 5 14 15 10Z";

  // ─── Entry ────────────────────────────────────────────────────────────────
  document.addEventListener("DOMContentLoaded", function () {
    // ── Inject organic blob SVGs into all buttons ──
    injectBlobButtons();

    var page = document.body.dataset.page;
    if (page === "learn")       initLearnPage();
    if (page === "seeds")       { loadSeedsFromApi(); initDeclarationPage(); }
    if (page === "map")         initMapPage();
  });

  // ─── Seeds: replace inline SEEDED fallback with Notion-managed list ────────
  function loadSeedsFromApi() {
    fetch("/api/seeds")
      .then(function (r) { if (!r.ok) throw new Error("seeds_fetch_failed"); return r.json(); })
      .then(function (data) {
        var items = ((data && data.seeds) || []).map(function (s) { return s.text; }).filter(Boolean);
        if (!items.length) return;
        SEEDED.length = 0;
        items.forEach(function (t) { SEEDED.push(t); });
      })
      .catch(function (err) {
        console.warn("seeds using inline fallback:", err && err.message);
      });
  }

  // ─── Blob button injection ───────────────────────────────────────────────
  function injectBlobButtons() {
    document.querySelectorAll(".btn").forEach(function (btn) {
      // Don't double-inject
      if (btn.querySelector(".btn-blob")) return;
      // Skip blob on buttons inside declaration cards and map page
      if (btn.closest(".declaration-card")) return;
      if (document.body.dataset.page === "map") return;

      // Wrap existing content in a label span
      var label = document.createElement("span");
      label.className = "btn-label";
      while (btn.firstChild) label.appendChild(btn.firstChild);
      btn.appendChild(label);

      // Create organic blob SVG
      var ns = "http://www.w3.org/2000/svg";
      var svg = document.createElementNS(ns, "svg");
      svg.setAttribute("class", "btn-blob");
      svg.setAttribute("viewBox", "0 0 200 70");
      svg.setAttribute("preserveAspectRatio", "none");
      svg.setAttribute("aria-hidden", "true");

      var path = document.createElementNS(ns, "path");
      path.setAttribute("d", BLOB_PATH);
      path.setAttribute("stroke", "currentColor");
      path.setAttribute("stroke-width", "1.3");
      path.setAttribute("fill", "none");
      svg.appendChild(path);

      btn.appendChild(svg);
    });
  }

  // ─── Navigation ───────────────────────────────────────────────────────────
  function navigateTo(href) {
    // Create exit loader
    var loader = document.createElement("div");
    loader.className = "page-loader";
    loader.style.opacity = "0";
    loader.innerHTML = '<span class="loader-label" style="opacity:1">Regen Commons</span>';
    document.body.appendChild(loader);
    requestAnimationFrame(function () {
      loader.style.transition = "opacity 0.45s cubic-bezier(.25,1,.5,1)";
      loader.style.opacity = "1";
    });
    setTimeout(function () { window.location.href = href; }, 500);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LEARN PAGE
  // ══════════════════════════════════════════════════════════════════════════
  function initLearnPage() {
    var steps   = Array.from(document.querySelectorAll(".step"));
    var dots    = Array.from(document.querySelectorAll(".dot"));
    var current = 0;

    function showStep(i) {
      steps.forEach(function (s, idx) { s.classList.toggle("active", idx === i); });
      dots.forEach(function (d, idx)  { d.classList.toggle("active", idx === i); });
      current = i;
    }

    document.querySelectorAll(".btn-next").forEach(function (btn) {
      btn.addEventListener("click", function () {
        if (current + 1 < steps.length) showStep(current + 1);
      });
    });

    var btnReady = document.querySelector(".btn-ready");
    if (btnReady) btnReady.addEventListener("click", function () { navigateTo("seeds.html"); });

    showStep(0);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  DECLARATION PAGE — Mycelial seed field
  //  Visions become network nodes connected by living mycelial branches.
  //  Force-directed layout positions nodes; branches grow between them.
  //  On hover: word-by-word text reveal. Cursor attracts nearby nodes.
  //  3-phase threshold ceremony: form fade → vision moment → field appears.
  // ══════════════════════════════════════════════════════════════════════════
  function initDeclarationPage() {
    var formUI   = document.getElementById("declaration-form-ui");
    var input    = document.getElementById("vision-input");
    var offerBtn = document.getElementById("offer-btn");
    var bubbleUI = document.getElementById("bubble-ui");
    var counter  = document.getElementById("bubble-counter");
    var enterBtn = document.getElementById("enter-commons-btn");
    var canvas   = document.getElementById("bubble-canvas");
    if (!canvas) return;

    var W, H;
    var fieldActive = false;

    // ── Field setup — seed field (mycelial network) ─────────────────────
    var seedFieldHandle = null;
    var counterInterval = null;

    function createField(userText) {
      W = canvas.width  = window.innerWidth;
      H = canvas.height = window.innerHeight;

      // Initialize the seed field via the canvas.js public API
      seedFieldHandle = window.initSeedField(canvas, SEEDED, userText);

      // Counter disabled — removed per design feedback
      if (counterInterval) clearInterval(counterInterval);
    }

    window.addEventListener("resize", function () {
      W = canvas.width  = window.innerWidth;
      H = canvas.height = window.innerHeight;
    }, { passive: true });

    // ── Offer button — expanded threshold ceremony ──────────────────────
    var thresholdMoment = document.getElementById("threshold-moment");
    var thresholdText   = document.getElementById("threshold-vision-text");

    offerBtn.addEventListener("click", function () {
      var text = (input.value || "").trim();
      if (!text) {
        input.classList.add("shake");
        setTimeout(function () { input.classList.remove("shake"); }, 400);
        return;
      }
      if (text.length > 240) {
        input.classList.add("shake");
        setTimeout(function () { input.classList.remove("shake"); }, 400);
        return;
      }

      // Save for map page
      try {
        localStorage.setItem("regen_vision", text);
        localStorage.setItem("regen_vision_time", Date.now().toString());
      } catch (_) {}

      // Plant the seed in Notion (fire-and-forget; UX never blocks)
      var honeypot = document.getElementById("seed-website-confirm");
      fetch("/api/seeds", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text: text,
          website_confirm: honeypot ? honeypot.value : "",
        }),
      }).catch(function () { /* silent — local experience already works */ });

      // ── Phase 1: Form fades slowly (1.5s) ──
      formUI.style.transition = "opacity 1.5s ease";
      formUI.style.opacity = "0";

      setTimeout(function () {
        formUI.style.display = "none";

        // ── Phase 2: User's vision appears alone (threshold moment) ──
        if (thresholdMoment && thresholdText) {
          thresholdText.textContent = '"' + text + '"';
          thresholdMoment.style.display = "flex";
          thresholdMoment.style.opacity = "0";
          thresholdMoment.style.transition = "opacity 1.8s ease";
          requestAnimationFrame(function () {
            thresholdMoment.style.opacity = "1";
          });

          // ── Phase 3: After a pause, field materializes around them ──
          setTimeout(function () {
            thresholdMoment.style.transition = "opacity 1.2s ease";
            thresholdMoment.style.opacity = "0";
            setTimeout(function () {
              thresholdMoment.style.display = "none";
              createField(text);
              fieldActive = true;
              // Fade in the counter and CTA after the field has had time to populate
              setTimeout(function () {
                bubbleUI.classList.add("visible");
              }, 1200);
            }, 1200);
          }, 3000);
        } else {
          // Fallback if threshold elements don't exist
          createField(text);
          fieldActive = true;
          bubbleUI.classList.add("visible");
        }
      }, 1500);
    });

    if (enterBtn) {
      enterBtn.addEventListener("click", function () { navigateTo("map.html"); });
    }

    // ── Auto-proceed when arriving from learn page (#planted) ──────────────
    if (window.location.hash === "#planted") {
      var preVision = null;
      try { preVision = localStorage.getItem("regen_vision"); } catch (_) {}
      if (preVision && input && offerBtn) {
        input.value = preVision;
        setTimeout(function () { offerBtn.click(); }, 350);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MAP PAGE — directory + filter/view + card expand
  // ══════════════════════════════════════════════════════════════════════════
  function initMapPage() {
    // ── First-arrival echo & return visitor detection ──────────────────────
    var arrivalEcho   = document.getElementById("arrival-echo");
    var welcomeBack   = document.getElementById("welcome-back");
    var echoVision    = document.getElementById("arrival-echo-vision");
    var echoOthers    = document.getElementById("arrival-echo-others");
    var welcomePulse  = document.getElementById("welcome-back-pulse");

    var savedVision   = null;
    var lastVisit     = null;
    var hasVisitedMap = false;
    try {
      savedVision   = localStorage.getItem("regen_vision");
      lastVisit     = localStorage.getItem("regen_map_last_visit");
      hasVisitedMap = !!lastVisit;
      localStorage.setItem("regen_map_last_visit", Date.now().toString());
    } catch (_) {}

    // Sample visions for the echo (subset of SEEDED array)
    var echoSampleVisions = [
      "Knowledge that outlasts the organizations that made it.",
      "A commons that's alive — not just archived.",
      "The ground beneath the work.",
      "Belonging without permission.",
      "A field that gets richer with every person who tends it."
    ];

    if (!hasVisitedMap && savedVision && arrivalEcho && echoVision) {
      // First arrival after planting a vision
      echoVision.textContent = '"' + savedVision + '"';
      if (echoOthers) {
        // Show 3 random other visions
        var shuffled = echoSampleVisions.sort(function () { return 0.5 - Math.random(); });
        for (var i = 0; i < 3; i++) {
          var v = document.createElement("p");
          v.className = "arrival-echo-other";
          v.textContent = '"' + shuffled[i] + '"';
          echoOthers.appendChild(v);
        }
      }
      arrivalEcho.style.display = "block";
      arrivalEcho.style.opacity = "0";
      arrivalEcho.style.transition = "opacity 1.5s ease";
      requestAnimationFrame(function () { arrivalEcho.style.opacity = "1"; });
    } else if (hasVisitedMap && welcomeBack) {
      // Returning visitor
      if (welcomePulse) {
        var items = [
          "2 new resources added to the Knowledge Commons",
          "The Federated Knowledge experiment completed its first integration test",
          "Next commons gathering: April 8, 2026"
        ];
        items.forEach(function (item) {
          var p = document.createElement("p");
          p.className = "welcome-back-item";
          p.textContent = item;
          welcomePulse.appendChild(p);
        });
      }
      welcomeBack.style.display = "block";
      welcomeBack.style.opacity = "0";
      welcomeBack.style.transition = "opacity 1.2s ease";
      requestAnimationFrame(function () { welcomeBack.style.opacity = "1"; });
    }

    // ── Card click → open modal ────────────────────────────────────────────
    var grid = document.getElementById("commons-grid");
    if (grid) {
      grid.addEventListener("click", function (e) {
        // Contributor link gets its own profile-modal handler — let it bubble.
        if (e.target.closest(".contributor-link")) return;
        // External action links should still navigate normally.
        if (e.target.closest(".card-action-link")) return;

        var card = e.target.closest(".commons-card");
        if (!card) return;
        window.openCardModal(card);
      });
    }

    // ── Contributor name → profile modal ───────────────────────────────────
    document.addEventListener("click", function (e) {
      var link = e.target.closest(".contributor-link");
      if (!link) return;
      e.stopPropagation();
      window.openProfileModal(link.dataset.name || link.textContent.trim());
    });

    // ── Filter / view buttons ──────────────────────────────────────────────
    if (!grid) return;

    var activeType   = "all";
    var activeView   = "grid";
    function getCards() {
      return Array.from(grid.querySelectorAll(".commons-card"));
    }

    document.querySelectorAll(".filter-btn[data-filter]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        document.querySelectorAll(".filter-btn[data-filter]")
          .forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        activeType = btn.dataset.filter;
        applyFilter();
      });
    });

    document.querySelectorAll(".view-btn").forEach(function (btn) {
      btn.addEventListener("click", function () {
        document.querySelectorAll(".view-btn")
          .forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        activeView = btn.dataset.view;
        grid.classList.toggle("view-list", activeView === "list");
      });
    });

    var stageFilters = ["seed", "sprout", "flowering", "tree"];

    function applyFilter() {
      var isStageFilter = stageFilters.indexOf(activeType) !== -1;
      getCards().forEach(function (c) {
        var match =
          activeType === "all" ||
          (isStageFilter ? c.dataset.stage === activeType : c.dataset.type === activeType);
        if (match) {
          c.classList.remove("hidden");
        } else {
          c.classList.remove("open");
          c.classList.add("hidden");
        }
      });
    }
    window.applyCommonsFilter = applyFilter;

    // ── Directory toggle ──────────────────────────────────────────────────
    var dirToggle = document.getElementById("directory-toggle");
    var dirList   = dirToggle && dirToggle.previousElementSibling;
    if (dirToggle && dirList) {
      dirToggle.addEventListener("click", function () {
        var expanded = dirList.classList.toggle("expanded");
        dirToggle.textContent = expanded ? "Show fewer " : "Show all members ";
        var count = document.createElement("span");
        count.className = "directory-count";
        count.textContent = "11";
        dirToggle.appendChild(count);
      });
    }

    // ── Landscape tooltip ─────────────────────────────────────────────────
    var landscape = document.getElementById("directory-landscape");
    var tooltip   = document.getElementById("landscape-tooltip");
    if (landscape && tooltip) {
      landscape.addEventListener("mouseover", function (e) {
        var dot = e.target.closest(".member-dot");
        if (!dot) { tooltip.classList.remove("visible"); return; }
        var name = dot.getAttribute("data-name");
        var role = dot.getAttribute("data-role");
        tooltip.textContent = name + " — " + role;
        tooltip.classList.add("visible");
        var rect = landscape.getBoundingClientRect();
        var dr   = dot.getBoundingClientRect();
        tooltip.style.left = (dr.left - rect.left + dr.width / 2) + "px";
        tooltip.style.top  = (dr.top - rect.top - 28) + "px";
      });
      landscape.addEventListener("mouseout", function (e) {
        if (!e.target.closest(".member-dot")) tooltip.classList.remove("visible");
      });
    }

    // ── Modal helpers (library cards · profile) ────────────────────────────
    var modal       = document.getElementById("rc-modal");
    var modalContent = document.getElementById("rc-modal-content");

    function openModal(htmlContent) {
      if (!modal || !modalContent) return;
      modalContent.innerHTML = htmlContent;
      modal.classList.add("open");
      modal.setAttribute("aria-hidden", "false");
      document.body.classList.add("rc-modal-locked");
    }
    function closeModal() {
      if (!modal) return;
      modal.classList.remove("open");
      modal.setAttribute("aria-hidden", "true");
      document.body.classList.remove("rc-modal-locked");
      if (modalContent) modalContent.innerHTML = "";
    }
    if (modal) {
      modal.addEventListener("click", function (e) {
        if (e.target.closest("[data-modal-close]")) closeModal();
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && modal.classList.contains("open")) closeModal();
      });
    }

    // Build the card detail modal from a card element's existing markup.
    window.openCardModal = function (card) {
      if (!card) return;
      var nameEl     = card.querySelector(".card-name");
      var teaserEl   = card.querySelector(".card-teaser");
      var contribEl  = card.querySelector(".card-contributor");
      var tagsEl     = card.querySelector(".card-tags");
      var bodyEl     = card.querySelector(".card-body-inner");

      var html = '';
      html += '<span class="modal-eyebrow">Library entry</span>';
      if (nameEl)    html += '<h2 class="modal-name">' + nameEl.innerHTML + '</h2>';
      if (teaserEl)  html += '<p class="modal-meta">' + teaserEl.innerHTML + '</p>';
      if (tagsEl)    html += tagsEl.outerHTML;
      if (bodyEl)    html += '<div class="modal-body">' + bodyEl.innerHTML + '</div>';
      if (contribEl) {
        html += '<div class="modal-profile-section"><h4>Contributors</h4><p>' + contribEl.innerHTML.replace(/^Contributed by\s*/i, '') + '</p></div>';
      }
      openModal(html);
    };

    // Build a placeholder profile modal for a contributor / ecosystem node.
    window.openProfileModal = function (name, opts) {
      opts = opts || {};
      var role  = opts.role || "Member of the regenerative commons";
      var kind  = opts.kind === "person" ? "Individual" : (opts.kind === "org" ? "Organization" : "Profile");

      var html = '';
      html += '<span class="modal-eyebrow">' + kind + '</span>';
      html += '<h2 class="modal-name">' + name + '</h2>';
      html += '<p class="modal-meta">' + role + '</p>';
      html += '<div class="modal-profile-section"><h4>About</h4><p>Profile content for <strong>' + name + '</strong> will live here once contributors complete their member onboarding.</p></div>';
      html += '<div class="modal-profile-section"><h4>Contributions to the commons</h4><p>Library entries, governance work, and ongoing commitments authored or stewarded by ' + name + ' will be listed in this section.</p></div>';
      html += '<div class="modal-profile-section"><h4>Connections</h4><p>Other members and organizations this profile is in active relationship with.</p></div>';
      html += '<div class="modal-placeholder">Placeholder · profile schema TBD</div>';
      openModal(html);
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  JOIN PAGE — multi-step form
  // ══════════════════════════════════════════════════════════════════════════
  if (document.body.dataset.page === "join") {
    var form       = document.getElementById("join-form");
    var steps      = form ? Array.from(form.querySelectorAll(".join-step")) : [];
    var dots       = Array.from(document.querySelectorAll(".join-step-dot"));
    var confirm    = document.getElementById("join-confirmation");
    var currentStep = 1;

    // Individual / Organization radio — reveal org-only fields
    var applicantRadios = document.querySelectorAll('input[name="applicant-type"]');
    var orgFields       = document.querySelectorAll(".join-org-fields");
    function syncOrgFields() {
      var selected = document.querySelector('input[name="applicant-type"]:checked');
      var isOrg = selected && selected.value === "organization";
      orgFields.forEach(function (f) {
        f.style.display = isOrg ? "block" : "none";
      });
    }
    applicantRadios.forEach(function (r) { r.addEventListener("change", syncOrgFields); });
    syncOrgFields();

    // "Other" contribution-area checkbox reveals a free-text input
    var otherCheckbox = document.getElementById("contrib-other");
    var otherField    = document.querySelector(".join-other-field");
    if (otherCheckbox && otherField) {
      otherCheckbox.addEventListener("change", function () {
        otherField.style.display = otherCheckbox.checked ? "block" : "none";
      });
    }

    function goToStep(n) {
      // Validate current step before advancing
      if (n > currentStep && !validateStep(currentStep)) return;

      currentStep = n;
      steps.forEach(function (s) { s.classList.remove("active"); });
      var target = form.querySelector('.join-step[data-step="' + n + '"]');
      if (target) target.classList.add("active");

      // Update progress dots
      dots.forEach(function (d, i) {
        var stepNum = i + 1;
        d.classList.remove("active", "done");
        if (stepNum === n) d.classList.add("active");
        else if (stepNum < n) d.classList.add("done");
      });

      // Scroll to top of form
      window.scrollTo({ top: 0, behavior: "smooth" });
    }

    function validateStep(n) {
      var step = form.querySelector('.join-step[data-step="' + n + '"]');
      if (!step) return true;
      var valid = true;
      // Track required radio groups (one validation per name)
      var checkedGroups = {};
      step.querySelectorAll("[required]").forEach(function (f) {
        var wrapper = f.closest(".join-field");
        if (f.type === "radio") {
          if (checkedGroups[f.name]) return;
          checkedGroups[f.name] = true;
          var anyChecked = step.querySelector('input[name="' + f.name + '"]:checked');
          if (!anyChecked) {
            valid = false;
            if (wrapper) wrapper.classList.add("has-error");
          } else if (wrapper) {
            wrapper.classList.remove("has-error");
          }
        } else if (!f.value.trim()) {
          valid = false;
          if (wrapper) wrapper.classList.add("has-error");
        } else if (wrapper) {
          wrapper.classList.remove("has-error");
        }
      });
      return valid;
    }

    // Next / back buttons
    document.querySelectorAll(".join-next").forEach(function (btn) {
      btn.addEventListener("click", function () {
        goToStep(parseInt(btn.dataset.to, 10));
      });
    });
    document.querySelectorAll(".join-back").forEach(function (btn) {
      btn.addEventListener("click", function () {
        goToStep(parseInt(btn.dataset.to, 10));
      });
    });

    // Clear error on input or selection change
    if (form) {
      function clearError(e) {
        var wrapper = e.target.closest(".join-field");
        if (wrapper) wrapper.classList.remove("has-error");
      }
      form.addEventListener("input", clearError);
      form.addEventListener("change", clearError);
    }

    // Submit
    if (form) {
      var submitBtn = document.getElementById("join-submit");
      var errorEl = document.getElementById("join-error");

      function serializeForm() {
        var fd = new FormData(form);
        var payload = {};
        var multiKeys = new Set();
        fd.forEach(function (_, key) {
          var els = form.querySelectorAll('[name="' + key + '"]');
          var isMulti = els.length > 1 && els[0].type === "checkbox";
          if (isMulti) multiKeys.add(key);
        });
        multiKeys.forEach(function (key) {
          payload[key] = fd.getAll(key);
        });
        fd.forEach(function (value, key) {
          if (multiKeys.has(key)) return;
          payload[key] = value;
        });
        return payload;
      }

      function showError(msg) {
        if (!errorEl) return;
        errorEl.textContent = msg;
        errorEl.style.display = "block";
      }
      function clearSubmitError() {
        if (errorEl) errorEl.style.display = "none";
      }

      form.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateStep(6)) return;
        clearSubmitError();

        var originalLabel = submitBtn ? submitBtn.querySelector(".btn-label").textContent : "";
        if (submitBtn) {
          submitBtn.disabled = true;
          submitBtn.querySelector(".btn-label").textContent = "Sending…";
        }

        try {
          var res = await fetch("/api/apply", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(serializeForm()),
          });
          if (!res.ok) {
            var data = await res.json().catch(function () { return {}; });
            throw new Error(data.error || "request_failed");
          }
          form.style.display = "none";
          document.querySelector(".join-progress").style.display = "none";
          confirm.classList.add("active");
          window.scrollTo({ top: 0, behavior: "smooth" });
        } catch (err) {
          showError(
            err && err.message === "rate_limited"
              ? "Too many submissions from this connection. Please try again later."
              : "Something went wrong sending your application. Please try again, or email a steward directly."
          );
          if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.querySelector(".btn-label").textContent = originalLabel || "Submit application";
          }
        }
      });
    }
  }

  // ─── Mobile nav (hamburger drawer for the page-nav) ─────────────────────
  (function () {
    var nav = document.querySelector(".page-nav");
    if (!nav) return;

    var btn = document.createElement("button");
    btn.className = "mobile-nav-toggle";
    btn.setAttribute("aria-label", "Open navigation");
    btn.innerHTML =
      '<svg viewBox="0 0 24 24" fill="none" stroke-width="1.7" aria-hidden="true">' +
      '<line x1="4" y1="7"  x2="20" y2="7"/>' +
      '<line x1="4" y1="12" x2="20" y2="12"/>' +
      '<line x1="4" y1="17" x2="20" y2="17"/>' +
      '</svg>';

    var backdrop = document.createElement("div");
    backdrop.className = "mobile-nav-backdrop";

    document.body.appendChild(btn);
    document.body.appendChild(backdrop);

    function setOpen(open) {
      document.body.classList.toggle("mobile-nav-open", open);
      btn.setAttribute("aria-label", open ? "Close navigation" : "Open navigation");
    }
    btn.addEventListener("click", function () {
      setOpen(!document.body.classList.contains("mobile-nav-open"));
    });
    backdrop.addEventListener("click", function () { setOpen(false); });
    nav.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () { setOpen(false); });
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") setOpen(false);
    });
  })();

  // ─── Floating feedback indicator (every page) ────────────────────────────
  (function () {
    if (document.querySelector(".feedback-indicator")) return;
    var a = document.createElement("a");
    a.className = "feedback-indicator";
    a.href = "https://opencivics.notion.site/35206d2570f28065a7dcf559894ec554?pvs=105";
    a.target = "_blank";
    a.rel = "noopener";
    a.textContent = "Feedback";
    document.body.appendChild(a);
  })();

  // ─── Theme toggle ────────────────────────────────────────────────────────
  var toggleBtn = document.getElementById("theme-toggle");
  if (toggleBtn) {
    toggleBtn.addEventListener("click", function () {
      var current = document.documentElement.getAttribute("data-theme") || "dark";
      var next = current === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      localStorage.setItem("rc-theme", next);
      // Notify canvas.js so it can update palette
      window.dispatchEvent(new CustomEvent("theme-change", { detail: { theme: next } }));
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  function rand(lo, hi) { return lo + Math.random() * (hi - lo); }

})();
