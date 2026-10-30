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
  // Visions are loaded from /api/seeds; this array is filled at runtime.
  var SEEDED = [];

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
        SEEDED.length = 0;
        items.forEach(function (t) { SEEDED.push(t); });
      })
      .catch(function (err) {
        console.warn("seeds: empty (API error)", err && err.message);
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

    function showPlanted(text) {
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        formUI.style.display = "none";
        createField(text);
        bubbleUI.classList.add("visible");
        enterBtn.focus();
        return;
      }
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
                enterBtn.focus();
              }, 1200);
            }, 1200);
          }, 3000);
        } else {
          // Fallback if threshold elements don't exist
          createField(text);
          fieldActive = true;
          bubbleUI.classList.add("visible");
          enterBtn.focus();
        }
      }, 1500);
    }

    if (enterBtn) {
      enterBtn.addEventListener("click", function () { navigateTo("map.html"); });
    }

    // Learn already saved the seed. Consume a one-use receipt, never POST again.
    var plantedText = null;
    if (window.location.hash === "#planted") {
      try {
        plantedText = sessionStorage.getItem("regen_seed_receipt");
        sessionStorage.removeItem("regen_seed_receipt");
      } catch (_) {}
      history.replaceState(null, "", window.location.pathname + window.location.search);
    }
    if (plantedText) {
      offerBtn.disabled = true;
      offerBtn.querySelector(".btn-label").textContent = "Saved";
      input.value = plantedText;
      input.readOnly = true;
      document.getElementById("seed-status").textContent = "Your seed has been saved to the commons.";
      showPlanted(plantedText);
    } else {
      RegenSeeds.bind(document.getElementById("seed-form"), showPlanted);
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

    if (!hasVisitedMap && savedVision && arrivalEcho && echoVision) {
      // First arrival after planting a vision — show user's vision plus a few
      // others fetched from the live Seeds DB (best-effort).
      echoVision.textContent = '"' + savedVision + '"';
      if (echoOthers) {
        fetch("/api/seeds")
          .then(function (r) { return r.ok ? r.json() : { seeds: [] }; })
          .then(function (data) {
            var pool = ((data && data.seeds) || [])
              .map(function (s) { return s.text; })
              .filter(function (t) { return t && t !== savedVision; });
            var shuffled = pool.sort(function () { return 0.5 - Math.random(); });
            for (var i = 0; i < Math.min(3, shuffled.length); i++) {
              var v = document.createElement("p");
              v.className = "arrival-echo-other";
              v.textContent = '"' + shuffled[i] + '"';
              echoOthers.appendChild(v);
            }
          })
          .catch(function () { /* leave echoOthers empty if offline */ });
      }
      arrivalEcho.style.display = "block";
      arrivalEcho.style.opacity = "0";
      arrivalEcho.style.transition = "opacity 1.5s ease";
      requestAnimationFrame(function () { arrivalEcho.style.opacity = "1"; });
    } else if (hasVisitedMap && welcomeBack) {
      // Returning visitor — pulse content not wired to a live data source yet.
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
      var cards = getCards();
      var visibleCount = 0;
      cards.forEach(function (c) {
        var match =
          activeType === "all" ||
          (isStageFilter ? c.dataset.stage === activeType : c.dataset.type === activeType);
        if (match) {
          visibleCount++;
          c.classList.remove("hidden");
        } else {
          c.classList.remove("open");
          c.classList.add("hidden");
        }
      });
      var noMatches = document.getElementById("commons-no-matches");
      if (noMatches) noMatches.hidden = !cards.length || visibleCount > 0;
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

      var heading = target && target.querySelector(".join-heading");
      if (heading) {
        heading.focus({ preventScroll: true });
        target.scrollIntoView({ block: "start", behavior: "instant" });
      }
    }

    function clearFieldError(field) {
      var wrapper = field.closest(".join-field");
      if (!wrapper) return;
      wrapper.classList.remove("has-error");
      var error = wrapper.querySelector(".join-field-error");
      if (error) {
        wrapper.querySelectorAll("input, textarea, select").forEach(function (control) {
          control.removeAttribute("aria-invalid");
          var ids = (control.getAttribute("aria-describedby") || "").split(/\s+/).filter(function (id) {
            return id && id !== error.id;
          });
          if (ids.length) control.setAttribute("aria-describedby", ids.join(" "));
          else control.removeAttribute("aria-describedby");
        });
        error.remove();
      }
    }

    function validateStep(n) {
      var step = form.querySelector('.join-step[data-step="' + n + '"]');
      if (!step) return true;
      var firstInvalid = null;
      var checkedGroups = new Set();
      step.querySelectorAll("input, textarea, select").forEach(function (field) {
        if (!field.willValidate) return;
        if (field.type === "radio") {
          if (checkedGroups.has(field.name)) return;
          checkedGroups.add(field.name);
        }
        clearFieldError(field);
        var blank = field.required && !field.value.trim();
        if (field.validity.valid && !blank) return;
        if (!firstInvalid) firstInvalid = field;
        var wrapper = field.closest(".join-field");
        if (!wrapper) return;
        wrapper.classList.add("has-error");
        var error = document.createElement("p");
        error.className = "join-field-error";
        error.id = "join-error-" + field.name;
        error.textContent = field.validity.typeMismatch && field.type === "email"
          ? "Enter a valid email address, such as name@example.com."
          : field.validity.typeMismatch && field.type === "url"
          ? "Enter a full web address, such as https://example.com, or leave this optional field blank."
          : field.type === "radio" ? "Choose an option to continue." : "Complete this field to continue.";
        wrapper.appendChild(error);
        var controls = field.type === "radio" ? wrapper.querySelectorAll('input[type="radio"]') : [field];
        controls.forEach(function (control) {
          control.setAttribute("aria-invalid", "true");
          control.setAttribute("aria-describedby", [control.getAttribute("aria-describedby"), error.id].filter(Boolean).join(" "));
        });
      });
      if (firstInvalid) firstInvalid.focus();
      return !firstInvalid;
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
        clearFieldError(e.target);
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
        if (currentStep < 6) {
          goToStep(currentStep + 1);
          return;
        }
        if (!validateStep(6)) return;
        clearSubmitError();

        var originalLabel = submitBtn ? submitBtn.querySelector(".btn-label").textContent : "";
        if (submitBtn) {
          submitBtn.disabled = true;
          submitBtn.querySelector(".btn-label").textContent = "Sending…";
        }

        var res;
        try {
          try {
            res = await fetch("/api/apply", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(serializeForm()),
            });
          } catch (networkErr) {
            // fetch() rejects only on network failure (offline, DNS, blocked,
            // connection reset) — distinct from a server-side error response.
            console.error("join: network error reaching /api/apply", networkErr);
            throw new Error("network_error");
          }
          if (!res.ok) {
            var data = await res.json().catch(function () { return {}; });
            console.error("join: /api/apply failed", res.status, data && data.error);
            throw new Error(data.error || "request_failed");
          }
          form.style.display = "none";
          document.querySelector(".join-progress").style.display = "none";
          confirm.classList.add("active");
          confirm.focus({ preventScroll: true });
          confirm.scrollIntoView({ block: "start", behavior: "instant" });
        } catch (err) {
          var code = err && err.message;
          showError(
            code === "rate_limited"
              ? "Too many submissions from this connection. Please try again later."
              : code === "network_error"
              ? "We couldn't reach the server — please check your connection and try again, or email a steward directly."
              : "Something went wrong sending your application. Please try again, or email a steward directly."
          );
          if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.querySelector(".btn-label").textContent = originalLabel || "Submit application";
            submitBtn.focus();
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
    btn.type = "button";
    nav.id = "site-navigation";
    btn.setAttribute("aria-controls", nav.id);
    btn.setAttribute("aria-expanded", "false");
    var mobile = window.matchMedia("(max-width: 640px)");
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

    function setOpen(open, restoreFocus) {
      document.body.classList.toggle("mobile-nav-open", open);
      btn.setAttribute("aria-label", open ? "Close navigation" : "Open navigation");
      btn.setAttribute("aria-expanded", String(open));
      nav.inert = mobile.matches && !open;
      if (open) nav.querySelector("a").focus();
      else if (restoreFocus) btn.focus();
    }
    mobile.addEventListener("change", function () { setOpen(false); });
    setOpen(false);
    document.addEventListener("focusin", function (event) {
      if (document.body.classList.contains("mobile-nav-open") && !nav.contains(event.target) && event.target !== btn) {
        setOpen(false);
      }
    });
    btn.addEventListener("click", function () {
      setOpen(!document.body.classList.contains("mobile-nav-open"), true);
    });
    backdrop.addEventListener("click", function () { setOpen(false, true); });
    nav.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () { setOpen(false); });
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && document.body.classList.contains("mobile-nav-open")) setOpen(false, true);
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
      try { localStorage.setItem("rc-theme", next); } catch (_) { /* Theme still works without storage. */ }
      // Notify canvas.js so it can update palette
      window.dispatchEvent(new CustomEvent("theme-change", { detail: { theme: next } }));
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  function rand(lo, hi) { return lo + Math.random() * (hi - lo); }

})();
