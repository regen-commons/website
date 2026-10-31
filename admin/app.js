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
    revision_conflict:
      "Someone changed this record. Reload to see the latest revision before trying again.",
    request_conflict:
      "This save was already attempted with different content. Check the Contributions list before creating another entry.",
    invalid_contribution: "Check the title and field lengths, then try again.",
    content_not_found: "This content could not be found.",
    application_not_found: "This application could not be found.",
    notification_not_found:
      "This email record could not be found. Refresh its status.",
    notification_changed:
      "Another attempt has already started. Refresh the status before retrying.",
    already_sent:
      "Resend has already accepted this email. It will not be sent again.",
    notification_busy:
      "An email attempt is already in progress. Refresh its status shortly.",
    retry_window_expired:
      "The safe retry window has ended. Check Resend before arranging another email.",
    retry_limit_reached:
      "This email has reached its three-attempt limit. Check the failure reason and Resend.",
    manual_review_required:
      "This email needs manual review in Resend before another send.",
    email_retry_not_configured:
      "Email retries are not configured. Ask an administrator to check the sending service.",
  };
  let signedIn = false,
    loginEmail = "",
    offset = 0,
    generation = 0;
  const filters = { search: "", state: "", type: "" };
  const menuButton = $("workspace-menu-toggle");
  const navigation = $("workspace-navigation");
  const mobileNavigation = window.matchMedia("(max-width: 850px)");
  const nativePopover = "popover" in HTMLElement.prototype;
  function menuIsOpen() {
    return nativePopover && navigation.hasAttribute("popover")
      ? navigation.matches(":popover-open")
      : navigation.hasAttribute("data-menu-open");
  }
  function focusCurrentDestination() {
    (
      navigation.querySelector('[aria-current="page"]') ||
      navigation.querySelector("nav a")
    ).focus();
  }
  function closeMenu() {
    if (!menuIsOpen()) return;
    if (nativePopover) navigation.hidePopover();
    else {
      const hadFocus = navigation.contains(document.activeElement);
      navigation.removeAttribute("data-menu-open");
      navigation.hidden = mobileNavigation.matches;
      if (hadFocus && signedIn) menuButton.focus();
    }
    menuButton.setAttribute("aria-expanded", "false");
  }
  function layoutNavigation() {
    const hadFocus = navigation.contains(document.activeElement);
    closeMenu();
    if (nativePopover) {
      if (mobileNavigation.matches) navigation.setAttribute("popover", "auto");
      else navigation.removeAttribute("popover");
    } else navigation.hidden = mobileNavigation.matches;
    if (hadFocus && signedIn) {
      if (mobileNavigation.matches) menuButton.focus();
      else focusCurrentDestination();
    }
  }
  menuButton.addEventListener("click", (event) => {
    if (!signedIn || !mobileNavigation.matches) {
      event.preventDefault();
      return;
    }
    if (!nativePopover) {
      if (menuIsOpen()) closeMenu();
      else {
        navigation.hidden = false;
        navigation.setAttribute("data-menu-open", "");
        menuButton.setAttribute("aria-expanded", "true");
        focusCurrentDestination();
      }
    }
  });
  navigation.addEventListener("toggle", () => {
    const open = menuIsOpen();
    menuButton.setAttribute("aria-expanded", String(open));
    if (open) focusCurrentDestination();
  });
  $("close-workspace-menu").addEventListener("click", closeMenu);
  navigation.addEventListener("click", (event) => {
    const destination = event.target.closest("nav a");
    if (!destination) return;
    closeMenu();
    if (destination.hash === location.hash) $("view-title").focus();
  });
  document.addEventListener("focusin", (event) => {
    if (
      menuIsOpen() &&
      !navigation.contains(event.target) &&
      event.target !== menuButton
    )
      closeMenu();
  });
  // The fallback retains the same disclosure behavior on browsers without Popover.
  if (!nativePopover) {
    document.addEventListener("pointerdown", (event) => {
      if (
        !navigation.contains(event.target) &&
        !menuButton.contains(event.target)
      )
        closeMenu();
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeMenu();
    });
  }
  mobileNavigation.addEventListener("change", layoutNavigation);
  layoutNavigation();
  function node(tag, text, className) {
    const element = document.createElement(tag);
    if (text != null) element.textContent = text;
    if (className) element.className = className;
    return element;
  }
  function date(value) {
    if (!value || Number.isNaN(Date.parse(value))) return "Date not recorded";
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
        signal: AbortSignal.timeout(
          body?.action === "retry-email" ? 45000 : 15000,
        ),
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
      "content-management",
    ])
      $(id).replaceChildren();
    $("retry").hidden = true;
  }
  function showLogin(message = "") {
    signedIn = false;
    closeMenu();
    menuButton.hidden = true;
    clearPrivateData();
    $("signed-in").textContent = "";
    $("view-title").textContent = "Membership requests";
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
    menuButton.hidden = false;
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
      `${data.total} ${data.total === 1 ? "membership request" : "membership requests"}${data.total ? ` · ${offset + 1}–${offset + data.applications.length}` : ""}`;
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
          "No membership requests match these filters. Try a different name or select all types and states.",
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
  function emailDeliveryCard(application) {
    const card = node("section", null, "detail-card email-delivery"),
      heading = node("h2", "Email delivery"),
      content = node("div"),
      status = node("p", "", "help"),
      refresh = node("button", "Refresh email status", "text-button");
    heading.tabIndex = -1;
    status.setAttribute("role", "status");
    refresh.type = "button";
    card.append(
      heading,
      node(
        "p",
        "Accepted by Resend confirms the send request. Inbox delivery and bounces are not tracked here.",
        "help",
      ),
      content,
      status,
      refresh,
    );
    const states = {
      pending: "Pending",
      sending: "Sending",
      sent: "Accepted by Resend",
      failed: "Failed",
      skipped: "Not sent",
      needs_review: "Needs review",
    };
    const reasons = {
      resend_not_configured: "Email sending is not configured.",
      recipients_not_configured:
        "No steward notification recipients are configured.",
      resend_authentication_failed:
        "Resend denied this send. Ask an administrator to check the sending key and sender domain.",
      resend_rate_limited:
        "Resend temporarily limited sending. Wait before retrying.",
      resend_idempotency_conflict:
        "Resend found different email content for this send identity. Check Resend before sending again.",
      resend_invalid_request:
        "Resend rejected the email details. Check the sender and recipient configuration.",
      resend_unavailable: "Resend was temporarily unavailable.",
      resend_rejected: "Resend rejected the send request.",
      resend_invalid_response:
        "Resend did not return a usable message ID. The outcome is uncertain; check Resend.",
      notification_timeout:
        "The send timed out before its outcome was confirmed.",
      notification_connection_failed:
        "The connection failed before the send outcome was confirmed.",
    };
    const blocks = {
      already_sent: "Accepted emails cannot be retried here.",
      retry_window_expired:
        "Retry closed: the safe sending window has ended. Check Resend manually.",
      retry_limit_reached:
        "Retry closed: three attempts have been made. Check Resend manually.",
      notification_busy:
        "An attempt is in progress. Refresh the status shortly.",
      manual_review_required:
        "Check Resend manually before arranging another email.",
    };
    let busy = false;
    async function update(body) {
      if (busy) return;
      busy = true;
      const current = generation;
      card.setAttribute("aria-busy", "true");
      const buttons = [...card.querySelectorAll("button")];
      buttons.forEach((button) => (button.disabled = true));
      status.textContent = body ? "Retrying email…" : "Checking email status…";
      try {
        const data = await api(
          body ? null : { resource: "email-deliveries", id: application.id },
          body,
        );
        if (current !== generation || !signedIn) return;
        content.replaceChildren();
        if (!data.notifications.length)
          content.append(
            node(
              "p",
              "No email delivery recorded. Imported requests are not emailed automatically.",
              "muted",
            ),
          );
        for (const job of data.notifications) {
          const entry = node("article", null, "email-job"),
            title =
              job.channel === "receipt"
                ? "Membership receipt"
                : "Steward notification",
            list = node("dl");
          entry.append(
            node("h3", title),
            node("span", states[job.status] || "Unknown", "badge"),
          );
          if (job.channel === "receipt")
            entry.append(node("p", application.email, "help email-recipient"));
          list.append(
            node("dt", "Attempts"),
            node("dd", `${job.attempts} of 3`),
          );
          if (job.attempts)
            list.append(
              node("dt", "Last attempt"),
              node(
                "dd",
                job.last_attempt_at
                  ? new Intl.DateTimeFormat(undefined, {
                      dateStyle: "medium",
                      timeStyle: "short",
                    }).format(new Date(job.last_attempt_at))
                  : "Not recorded",
              ),
            );
          const messageId = node("dd");
          if (job.provider_message_id) {
            messageId.append(node("code", job.provider_message_id));
            const open = link(
              "View in Resend ↗",
              `https://resend.com/emails/${encodeURIComponent(job.provider_message_id)}`,
            );
            open.target = "_blank";
            open.rel = "noreferrer noopener";
            messageId.append(node("br"), open);
          } else messageId.textContent = "Not recorded";
          list.append(node("dt", "Resend message ID"), messageId);
          if (
            job.failure_code ||
            ["failed", "needs_review"].includes(job.status)
          )
            list.append(
              node("dt", "Last failure reason"),
              node(
                "dd",
                reasons[job.failure_code] ||
                  "No failure reason was recorded for this earlier attempt.",
              ),
            );
          entry.append(list);
          if (job.retry_block == null) {
            const retry = node(
              "button",
              job.channel === "receipt"
                ? "Retry receipt email"
                : "Retry steward email",
              "secondary",
            );
            retry.type = "button";
            retry.addEventListener("click", () =>
              update({
                action: "retry-email",
                application_id: application.id,
                job_id: job.id,
                attempts: job.attempts,
              }),
            );
            entry.append(retry);
          } else
            entry.append(
              node(
                "p",
                blocks[job.retry_block] || "Retry is unavailable.",
                "help",
              ),
            );
          content.append(entry);
        }
        status.textContent = body
          ? "Email attempt recorded. Check the updated status above."
          : "Email status is up to date.";
        if (body) heading.focus();
      } catch (error) {
        if (current !== generation || !signedIn) return;
        if ([401, 403].includes(error.status)) {
          showLogin(error.message);
          $("email").focus();
          return;
        }
        status.textContent =
          body && (!error.status || error.status >= 500)
            ? "We couldn’t confirm this email attempt. Refresh email status before retrying."
            : error.status
              ? error.message
              : "The connection failed. Refresh email status to check the outcome before retrying.";
      } finally {
        busy = false;
        card.removeAttribute("aria-busy");
        buttons.forEach((button) => (button.disabled = false));
      }
    }
    refresh.addEventListener("click", () => update());
    update();
    return card;
  }
  function renderDetail({ application, profile, history }) {
    $("view-title").textContent = application.display_name;
    $("view-description").textContent =
      `${label(application.applicant_type)} · Submitted ${date(application.submitted_at)} · Revision ${application.revision}`;
    $("detail").append(link("← Back to membership requests", "#applications"));
    const grid = node("div", null, "detail-grid application-grid"),
      privateColumn = node("div", null, "application-answers"),
      publicColumn = node("div", null, "application-profile");
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
    grid.append(emailDeliveryCard(application), privateColumn, publicColumn);
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
  const contentFilters = {
    seeds: { search: "", state: "", offset: 0 },
    contributions: { search: "", state: "", offset: 0 },
  };
  function control(form, key, title, value, options = {}) {
    const wrap = node("div", null, "editor-field"),
      id = "edit-" + key;
    const labelElement = node("label", title);
    labelElement.htmlFor = id;
    const input = document.createElement(
      options.multiline ? "textarea" : "input",
    );
    input.id = id;
    input.name = key;
    input.value = value || "";
    if (options.max) input.maxLength = options.max;
    if (options.required) input.required = true;
    if (options.multiline) input.rows = 4;
    wrap.append(labelElement, input);
    form.append(wrap);
    return input;
  }
  async function performWrite(form, body, done) {
    const current = generation,
      controls = [...form.querySelectorAll("button,input,textarea,select")].map(
        (element) => ({ element, disabled: element.disabled }),
      );
    const status = form.querySelector('[role="status"]');
    controls.forEach(({ element }) => (element.disabled = true));
    status.textContent = "Saving…";
    try {
      const result = await api(null, body);
      if (current !== generation || !signedIn) return;
      done(result);
    } catch (error) {
      if (current !== generation || !signedIn) return;
      if ([401, 403].includes(error.status)) {
        showLogin(error.message);
        $("email").focus();
        return;
      }
      status.textContent = error.status
        ? error.message
        : "We couldn’t confirm this save. Keep this form open and retry, or check the list before creating another entry.";
      if (error.code === "revision_conflict") {
        const reload = node("button", "Reload latest revision", "secondary");
        reload.type = "button";
        reload.addEventListener("click", loadView);
        status.append(document.createTextNode(" "), reload);
      }
    } finally {
      controls.forEach(
        ({ element, disabled }) => (element.disabled = disabled),
      );
    }
  }
  function renderContentList(resource, data) {
    const root = $("content-management"),
      filter = contentFilters[resource],
      form = node("form", null, "filters");
    form.setAttribute("role", "search");
    control(form, "content-search", "Search " + resource, filter.search, {
      max: 100,
    });
    const wrap = node("div"),
      caption = node("label", "Publication state"),
      select = node("select");
    caption.htmlFor = "content-state";
    select.id = "content-state";
    for (const [value, title] of [
      ["", "All states"],
      ["published", "Published"],
      ["hidden", "Hidden"],
      ...(resource === "contributions" ? [["draft", "Draft"]] : []),
    ]) {
      const option = node("option", title);
      option.value = value;
      select.append(option);
    }
    select.value = filter.state;
    wrap.append(caption, select);
    form.append(wrap, node("button", "Apply filters", "secondary"));
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      filter.search = form.elements["content-search"].value.trim();
      filter.state = select.value;
      filter.offset = 0;
      loadView();
    });
    root.append(form);
    if (resource === "contributions")
      root.append(link("Add contribution →", "#contributions/new"));
    root.append(
      node(
        "p",
        `${data.total} ${data.total === 1 ? resource.slice(0, -1) : resource} · newest first`,
        "help",
      ),
    );
    if (!data.items.length)
      root.append(node("p", "No content matches these filters.", "empty"));
    for (const item of data.items) {
      const row = node("article", null, "application-row"),
        identity = node("div");
      identity.append(
        link(item.text || item.title, `#${resource}/${item.id}`),
        node("p", (item.tags || []).join(" · "), "help"),
      );
      row.append(
        identity,
        node("span", label(item.publication_state), "badge"),
        node("span", date(item.created_at), "help"),
      );
      root.append(row);
    }
    if (data.total > 25) {
      const pager = node("div", null, "pagination");
      for (const [title, delta] of [
        ["Previous", -25],
        ["Next", 25],
      ]) {
        const button = node("button", title, "secondary");
        button.type = "button";
        button.disabled =
          delta < 0
            ? filter.offset === 0
            : filter.offset + data.items.length >= data.total;
        button.addEventListener("click", () => {
          filter.offset += delta;
          loadView();
        });
        pager.append(button);
      }
      root.append(pager);
    }
  }
  function contributionEditor(item, contributorIds, members) {
    const form = node("form", null, "detail-card contribution-editor");
    form.append(
      node("h2", item ? "Edit contribution" : "Add contribution"),
      node(
        "p",
        item
          ? "Editing keeps the current publication state."
          : "Saving publishes this contribution immediately.",
        "help",
      ),
    );
    for (const [key, title, max, multiline] of [
      ["title", "Title", 200, false],
      ["description", "Description", 10000, true],
      ["contribution_type", "Type", 100, false],
      ["stage", "Stage", 100, false],
      ["tier", "Tier", 100, false],
      ["terms", "Terms", 10000, true],
      ["license", "License", 200, false],
    ])
      control(form, key, title, item?.[key], {
        max,
        multiline,
        required: key === "title",
      });
    control(form, "tags", "Tags separated by commas", item?.tags?.join(", "), {
      max: 1600,
    });
    control(
      form,
      "capital_forms",
      "Capital forms separated by commas",
      item?.capital_forms?.join(", "),
      { max: 1600 },
    );
    const fieldset = node("fieldset");
    fieldset.append(node("legend", "Contributors"));
    fieldset.append(
      node(
        "p",
        "Only published members are attributed on the public library.",
        "help",
      ),
    );
    for (const member of members) {
      const labelElement = node("label", null, "contributor-option"),
        checkbox = node("input");
      checkbox.type = "checkbox";
      checkbox.name = "contributor_ids";
      checkbox.value = member.id;
      checkbox.checked = contributorIds.includes(member.id);
      labelElement.append(
        checkbox,
        document.createTextNode(
          `${member.name} · ${label(member.member_type)} · ${label(member.publication_state)}`,
        ),
      );
      fieldset.append(labelElement);
    }
    form.append(fieldset);
    const status = node("p");
    status.setAttribute("role", "status");
    const save = node("button", item ? "Save changes" : "Publish contribution");
    form.append(save, status);
    const requestId = crypto.randomUUID();
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const values = new FormData(form),
        payload = {};
      for (const key of [
        "title",
        "description",
        "contribution_type",
        "stage",
        "tier",
        "terms",
        "license",
      ])
        payload[key] = values.get(key);
      for (const key of ["tags", "capital_forms"])
        payload[key] = values
          .get(key)
          .split(",")
          .map((v) => v.trim())
          .filter(Boolean);
      payload.contributor_ids = values.getAll("contributor_ids");
      performWrite(
        form,
        {
          action: "save-contribution",
          request_id: requestId,
          ...(item ? { id: item.id, revision: item.revision } : {}),
          payload,
        },
        (result) => {
          if (location.hash === `#contributions/${result.id}`) loadView();
          else location.hash = `contributions/${result.id}`;
        },
      );
    });
    return form;
  }
  function renderContentDetail(resource, data, memberData) {
    const root = $("content-management"),
      item = data?.item;
    root.append(link(`← Back to ${resource}`, `#${resource}`));
    if (item) {
      $("view-title").textContent = resource === "seeds" ? "Seed" : item.title;
      const card = node("article", null, "detail-card");
      card.append(
        node("span", label(item.publication_state), "badge"),
        node("h2", item.text || item.title),
        node(
          "p",
          `Revision ${item.revision} · ${date(item.created_at)}`,
          "help",
        ),
      );
      if (resource === "seeds")
        card.append(
          node("p", item.author || "Anonymous", "muted"),
          node("p", (item.tags || []).join(" · "), "help"),
        );
      const form = node("form", null, "moderation-form");
      control(form, "reason", "Reason for this moderation action", "", {
        required: true,
        max: 1000,
        multiline: true,
      });
      const button = node(
        "button",
        item.publication_state === "hidden"
          ? "Restore publication"
          : "Hide from public site",
        "secondary",
      );
      const status = node("p");
      status.setAttribute("role", "status");
      form.append(button, status);
      form.addEventListener("submit", (e) => {
        e.preventDefault();
        performWrite(
          form,
          {
            action: "moderate",
            resource,
            id: item.id,
            revision: item.revision,
            state: item.publication_state === "hidden" ? "published" : "hidden",
            reason: form.elements.reason.value,
          },
          loadView,
        );
      });
      card.append(form);
      root.append(card);
    }
    if (resource === "contributions")
      root.append(
        contributionEditor(
          item,
          data?.contributor_ids || [],
          memberData.members,
        ),
      );
    if (item) {
      const history = node("section", null, "detail-card");
      history.append(node("h2", "Content history"));
      if (!data.history.length)
        history.append(
          node("p", "No steward actions have been recorded.", "muted"),
        );
      for (const event of data.history)
        history.append(
          node("h3", label(event.action)),
          node(
            "p",
            `${date(event.created_at)} · Revision ${event.revision} · ${event.actor_label || "Steward"}`,
            "help",
          ),
          node("p", event.reason || ""),
        );
      root.append(history);
    }
  }
  async function loadView() {
    if (!signedIn) return;
    closeMenu();
    clearPrivateData();
    const current = generation;
    const route = location.hash.slice(1),
      detailId = route.startsWith("applications/") ? route.split("/")[1] : null;
    const members = route === "members";
    const [resource, contentId] = route.split("/");
    const managing = ["seeds", "contributions"].includes(resource);
    $("content-management").hidden = !managing;
    $("queue").hidden = managing || members || !!detailId;
    $("members").hidden = !members;
    $("detail").hidden = !detailId;
    $("pagination").hidden = true;
    $("view-title").textContent = managing
      ? label(resource)
      : members
        ? "Members"
        : detailId
          ? "Membership request"
          : "Membership requests";
    $("view-description").textContent = managing
      ? "New items publish immediately. Hide or restore them as needed."
      : members
        ? "Individuals and organizations in the commons."
        : "Private membership requests from individuals and organizations.";
    for (const section of ["applications", "members", "seeds", "contributions"])
      $("nav-" + section).removeAttribute("aria-current");
    (managing
      ? $("nav-" + resource)
      : members
        ? $("nav-members")
        : $("nav-applications")
    ).setAttribute("aria-current", "page");
    $("load-message").textContent = "Loading…";
    try {
      if (managing) {
        if (contentId) {
          const [data, memberData] = await Promise.all([
            contentId === "new" && resource === "contributions"
              ? null
              : api({ resource: "content", kind: resource, id: contentId }),
            resource === "contributions" ? api({ resource: "members" }) : null,
          ]);
          if (current !== generation || !signedIn) return;
          renderContentDetail(resource, data, memberData);
        } else {
          const data = await api({ resource, ...contentFilters[resource] });
          if (current !== generation || !signedIn) return;
          renderContentList(resource, data);
        }
        $("load-message").textContent = "";
        if (!menuIsOpen()) $("view-title").focus();
        return;
      }
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
      if (!menuIsOpen()) $("view-title").focus();
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
    const current = generation;
    try {
      const data = await api({ resource: "session" });
      if (current === generation) {
        if (signedIn) $("signed-in").textContent = data.user.email;
        else showWorkspace(data.user);
      }
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
