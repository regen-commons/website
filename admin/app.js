(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const messages = {
    invalid_code:
      "That code is invalid or expired. Check the code, or request a new one.",
    invalid_email: "Enter a valid email address.",
    steward_required:
      "This account does not have active steward access. Ask a project administrator to check your access.",
    sign_in_required: "Your session has ended. Sign in again to continue.",
    rate_limited: "Too many attempts. Wait a minute before trying again.",
    admin_not_configured:
      "Steward sign-in is not configured yet. Contact the project administrator.",
    application_not_found: "This application could not be found.",
  };
  let signedIn = false,
    loginEmail = "",
    offset = 0,
    generation = 0;
  const filters = { search: "", state: "", type: "" };
  function node(tag, text, className) {
    const element = document.createElement(tag);
    if (text != null) element.textContent = text;
    if (className) element.className = className;
    return element;
  }
  function date(value) {
    return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
      new Date(value),
    );
  }
  function label(value) {
    return String(value || "Not recorded")
      .replaceAll("_", " ")
      .replace(/^./, (letter) => letter.toUpperCase());
  }
  function link(text, href) {
    const element = node("a", text);
    element.href = href;
    return element;
  }
  async function api(params, body) {
    const response = await fetch(
      `/api/admin${params ? `?${new URLSearchParams(params)}` : ""}`,
      {
        method: body ? "POST" : "GET",
        credentials: "same-origin",
        cache: "no-store",
        ...(body
          ? {
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(body),
            }
          : {}),
        signal: AbortSignal.timeout(15000),
      },
    );
    const data = await response.json();
    if (!response.ok)
      throw Object.assign(
        new Error(
          messages[data.error] ||
            "We couldn’t load this from the steward service. Please try again.",
        ),
        { code: data.error, status: response.status },
      );
    return data;
  }
  function clearPrivateData() {
    generation++;
    for (const id of [
      "application-list",
      "member-list",
      "detail",
      "queue-count",
      "load-message",
    ])
      $(id).replaceChildren();
    $("retry").hidden = true;
  }
  function showLogin(message = "") {
    signedIn = false;
    clearPrivateData();
    $("signed-in").textContent = "";
    $("view-title").textContent = "Applications";
    $("view-description").textContent = "";
    for (const key of Object.keys(filters)) {
      filters[key] = "";
      $(key).value = "";
    }
    offset = 0;
    $("workspace").hidden = true;
    $("login").hidden = false;
    $("email-form").hidden = false;
    $("code-form").hidden = true;
    $("code").value = "";
    $("login-message").textContent = message;
    $("retry-sign-out").hidden = true;
  }
  function showWorkspace(user) {
    signedIn = true;
    $("login").hidden = true;
    $("workspace").hidden = false;
    $("signed-in").textContent = user.email;
    $("code").value = "";
    $("login-message").textContent = "";
    loadView();
  }
  async function submit(action) {
    const current = ++generation;
    const buttons = [...$("login").querySelectorAll("button")];
    buttons.forEach((button) => {
      button.disabled = true;
    });
    $("login-message").textContent =
      action === "request-code"
        ? "Requesting a code…"
        : "Checking your code and steward access…";
    try {
      if (action === "request-code") loginEmail = $("email").value.trim();
      const data = await api(null, {
        action,
        email: loginEmail,
        ...(action === "verify-code" ? { code: $("code").value.trim() } : {}),
      });
      if (current !== generation) return;
      if (action === "request-code") {
        $("email-form").hidden = true;
        $("code-form").hidden = false;
        $("login-message").textContent = "";
        $("code").focus();
      } else showWorkspace(data.user);
    } catch (error) {
      if (current !== generation) return;
      $("login-message").textContent = error.status
        ? error.message
        : "The connection failed. Please try again.";
      if (error.status === 403) {
        showLogin(messages.steward_required);
        $("email").focus();
      }
    } finally {
      buttons.forEach((button) => {
        button.disabled = false;
      });
    }
  }
  $("email-form").addEventListener("submit", (event) => {
    event.preventDefault();
    submit("request-code");
  });
  $("code-form").addEventListener("submit", (event) => {
    event.preventDefault();
    submit("verify-code");
  });
  $("change-email").addEventListener("click", () => {
    showLogin();
    $("email").focus();
  });
  async function signOut() {
    showLogin("Signing out…");
    $("email-form").hidden = true;
    try {
      await api(null, { action: "sign-out" });
      $("login-message").textContent = "You’re signed out.";
    } catch {
      $("login-message").textContent =
        "Private data has been cleared from this page, but sign-out could not be confirmed. Retry when your connection returns.";
      $("retry-sign-out").hidden = false;
    }
    $("email-form").hidden = false;
    ($("retry-sign-out").hidden ? $("email") : $("retry-sign-out")).focus();
  }
  $("sign-out").addEventListener("click", signOut);
  $("retry-sign-out").addEventListener("click", signOut);
  function profileCard(profile) {
    const card = node("article", null, "profile-card");
    card.append(
      node("span", label(profile.publication_state), "badge"),
      node("h2", profile.name),
      node(
        "p",
        `${label(profile.member_type)} · ${profile.location || "Location not set"}`,
        "muted",
      ),
    );
    card.append(
      node(
        "p",
        profile.summary || "No public summary has been curated.",
        "profile-summary",
      ),
    );
    const tags = node("div");
    for (const tag of [...profile.focus_areas, ...profile.contribution_areas])
      tags.append(node("span", tag, "tag"));
    card.append(tags);
    if (profile.website) {
      try {
        const url = new URL(profile.website);
        if (["https:", "http:"].includes(url.protocol)) {
          const website = link("Visit website ↗", url.href);
          website.rel = "noreferrer noopener";
          const paragraph = node("p");
          paragraph.append(website);
          card.append(paragraph);
        }
      } catch {
        /* Invalid imported URLs are not made clickable. */
      }
    }
    return card;
  }
  function renderQueue(data) {
    $("queue-count").textContent =
      `${data.total} ${data.total === 1 ? "application" : "applications"}${data.total ? ` · ${offset + 1}–${offset + data.applications.length}` : ""}`;
    for (const application of data.applications) {
      if (
        ![...$("state").options].some(
          (option) => option.value === application.review_state,
        )
      ) {
        const option = node("option", label(application.review_state));
        option.value = application.review_state;
        $("state").append(option);
      }
      const row = node("article", null, "application-row"),
        identity = node("div"),
        meta = node("div", null, "meta");
      identity.append(
        link(application.display_name, `#applications/${application.id}`),
        node(
          "p",
          `${label(application.applicant_type)}${application.cohort ? ` · ${application.cohort}` : ""}`,
        ),
      );
      meta.append(
        node("span", date(application.submitted_at)),
        node(
          "p",
          application.nominator
            ? `Nominated by ${application.nominator}`
            : "No nominator recorded",
        ),
      );
      row.append(
        identity,
        node("span", label(application.review_state), "badge"),
        meta,
      );
      $("application-list").append(row);
    }
    if (!data.applications.length)
      $("application-list").append(
        node(
          "p",
          "No applications match these filters. Try a different name or select all types and states.",
          "empty",
        ),
      );
    $("pagination").hidden = data.total <= 25;
    $("previous").disabled = offset === 0;
    $("next").disabled = offset + data.applications.length >= data.total;
  }
  const answerLabels = {
    "regen-relationship": "Relationship to regenerative work",
    "values-resonance": "Alignment with core values",
    "meaningful-participation": "Meaningful participation",
    "capital-contribution": "Pathways to contribution",
    "org-rep": "Organization representative",
    "org-description": "Organization mission and activities",
    "governance-consent": "Governance consent",
    "closing-notes": "Closing notes",
    "other-colleagues": "Colleague contact details",
    "agreement-reviewed": "Membership agreement",
    "contribution-area": "Contribution areas",
  };
  function renderDetail({ application, profile, history }) {
    $("view-title").textContent = application.display_name;
    $("view-description").textContent =
      `${label(application.applicant_type)} · Submitted ${date(application.submitted_at)} · Revision ${application.revision}`;
    $("detail").append(link("← Back to applications", "#applications"));
    const grid = node("div", null, "detail-grid"),
      privateColumn = node("div"),
      publicColumn = node("div");
    const answers = node("section", null, "detail-card");
    answers.append(
      node("p", "Private · stewards only", "eyebrow"),
      node("h2", "Original application"),
    );
    const list = node("dl");
    for (const [key, value] of Object.entries({
      Email: application.email,
      "Review state": label(application.review_state),
      ...application.original_answers,
    })) {
      list.append(
        node("dt", answerLabels[key] || label(key.replaceAll("-", " "))),
        node(
          "dd",
          typeof value === "object"
            ? JSON.stringify(value, null, 2)
            : String(value ?? "Not provided"),
        ),
      );
    }
    answers.append(
      list,
      node(
        "p",
        `Original answers · schema version ${application.answers_schema_version}`,
        "help",
      ),
    );
    const events = node("section", null, "detail-card");
    events.append(node("h2", "Record history"));
    if (!history.length)
      events.append(node("p", "No review events have been recorded.", "muted"));
    for (const event of history)
      events.append(
        node("h3", label(event.event_type)),
        node(
          "p",
          `${date(event.created_at)} · Revision ${event.reviewed_revision}`,
          "help",
        ),
        node("p", event.note),
      );
    privateColumn.append(answers, events);
    publicColumn.append(
      node("p", "Public-profile preview", "eyebrow"),
      node(
        "p",
        "Only separately curated profile fields appear here. Previewing a profile does not publish it or accept the application.",
        "help",
      ),
    );
    if (profile) publicColumn.append(profileCard(profile));
    else
      publicColumn.append(
        node(
          "p",
          "No curated profile has been linked yet. Private answers are not copied into a public profile automatically.",
          "empty",
        ),
      );
    grid.append(privateColumn, publicColumn);
    $("detail").append(grid);
  }
  function renderMembers(data) {
    if (!data.members.length)
      $("member-list").append(node("p", "No curated members yet.", "empty"));
    for (const member of data.members) {
      const card = profileCard(member);
      const affiliations = data.affiliations
        .filter((item) => item.member_id === member.id)
        .map(
          (item) =>
            data.members.find((row) => row.id === item.organization_id)?.name,
        )
        .filter(Boolean);
      const contributions = data.contributionMembers
        .filter((item) => item.member_id === member.id)
        .map((item) =>
          data.contributions.find((row) => row.id === item.contribution_id),
        )
        .filter(Boolean);
      card.append(
        node("h3", "Affiliations"),
        node("p", affiliations.join(", ") || "None recorded", "muted"),
        node("h3", "Contributions"),
      );
      if (!contributions.length)
        card.append(node("p", "None recorded", "muted"));
      for (const contribution of contributions)
        card.append(
          node(
            "p",
            `${contribution.title} · ${label(contribution.publication_state)}`,
          ),
        );
      $("member-list").append(card);
    }
  }
  async function loadView() {
    if (!signedIn) return;
    clearPrivateData();
    const current = generation;
    const route = location.hash.slice(1),
      detailId = route.startsWith("applications/") ? route.split("/")[1] : null;
    const members = route === "members";
    $("queue").hidden = members || !!detailId;
    $("members").hidden = !members;
    $("detail").hidden = !detailId;
    $("pagination").hidden = true;
    $("view-title").textContent = members
      ? "Members"
      : detailId
        ? "Application"
        : "Applications";
    $("view-description").textContent = members
      ? "Curated profiles, affiliations, and contributions. Publication is tracked separately."
      : "Get to know the people and organizations joining the commons.";
    $("nav-applications").removeAttribute("aria-current");
    $("nav-members").removeAttribute("aria-current");
    (members ? $("nav-members") : $("nav-applications")).setAttribute(
      "aria-current",
      "page",
    );
    $("load-message").textContent = "Loading…";
    try {
      const params = members
        ? { resource: "members" }
        : detailId
          ? { resource: "application", id: detailId }
          : { resource: "applications", ...filters, offset };
      const data = await api(params);
      if (current !== generation || !signedIn) return;
      if (members) renderMembers(data);
      else if (detailId) renderDetail(data);
      else renderQueue(data);
      $("load-message").textContent = "";
      $("view-title").focus();
    } catch (error) {
      if (current !== generation) return;
      if ([401, 403].includes(error.status)) {
        showLogin(error.message);
        $("email").focus();
        return;
      }
      $("load-message").textContent = error.status
        ? error.message
        : "The connection failed. Your review data could not be loaded. Try again.";
      $("retry").hidden = false;
    }
  }
  $("filters").addEventListener("submit", (event) => {
    event.preventDefault();
    for (const key of Object.keys(filters)) filters[key] = $(key).value.trim();
    offset = 0;
    loadView();
  });
  $("previous").addEventListener("click", () => {
    offset = Math.max(0, offset - 25);
    loadView();
  });
  $("next").addEventListener("click", () => {
    offset += 25;
    loadView();
  });
  $("retry").addEventListener("click", loadView);
  window.addEventListener("hashchange", loadView);
  async function checkSession() {
    const current = ++generation;
    try {
      const data = await api({ resource: "session" });
      if (current === generation) showWorkspace(data.user);
    } catch (error) {
      if (current === generation)
        showLogin(error.status === 401 ? "" : error.message);
    }
  }
  // Clear sensitive DOM before a page can enter the back/forward cache.
  window.addEventListener("pagehide", () => {
    showLogin();
  });
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) checkSession();
  });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && signedIn) checkSession();
  });
  checkSession();
})();
