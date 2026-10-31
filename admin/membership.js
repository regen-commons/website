/* Private steward forms. Persistence and authority stay behind /api/admin. */
window.createMembershipSubmission = function () {
  let pending = null;
  return async (makeCommand, send) => {
    pending ||= structuredClone(makeCommand());
    const outcome = await send(pending);
    // A transport/server failure may follow a committed write. Recover that
    // exact command before allowing another payload with its request identity.
    if (
      outcome?.ok ||
      (outcome?.status >= 400 &&
        outcome.status < 500 &&
        outcome.code !== "request_conflict")
    )
      pending = null;
    return { uncertain: pending !== null };
  };
};
window.createMembershipUI = function ({
  node,
  link,
  label,
  date,
  control,
  performWrite,
  loadView,
}) {
  const reviewStates = {
    pending: ["approved", "declined", "changes_requested"],
    changes_requested: ["approved", "declined", "pending"],
    approved: ["pending"],
    declined: ["pending"],
    legacy_active: ["approved", "declined", "changes_requested", "pending"],
  };
  function select(form, key, title, options, value = "") {
    const wrap = node("div", null, "editor-field"),
      field = node("select");
    field.id = key;
    field.name = key;
    const caption = node("label", title);
    caption.htmlFor = key;
    for (const [id, text] of options) {
      const option = node("option", text);
      option.value = id;
      field.append(option);
    }
    field.value = value;
    wrap.append(caption, field);
    form.append(wrap);
    return field;
  }
  function form(title, help) {
    const el = node("form", null, "detail-card membership-form");
    el.method = "post";
    el.action = "/api/admin";
    el.append(node("h2", title), node("p", help, "help"));
    return el;
  }
  function finish(
    el,
    title,
    command,
    done = loadView,
    buttonLabel = () => title,
  ) {
    const reason = control(
      el,
      title.replaceAll(" ", "-").toLowerCase() + "-reason",
      "Reason (required, private)",
      "",
      { required: true, max: 1000, multiline: true },
    );
    reason.rows = 2;
    const button = node("button", buttonLabel()),
      status = node("p");
    button.type = "submit";
    status.setAttribute("role", "status");
    el.append(button, status);
    const requestId = crypto.randomUUID();
    const submit = window.createMembershipSubmission();
    const inputs = [...el.querySelectorAll("input,textarea,select")].map(
      (element) => ({ element, disabled: element.disabled }),
    );
    el.addEventListener("submit", async (event) => {
      event.preventDefault();
      const { uncertain } = await submit(
        () => ({
          ...command(new FormData(el)),
          request_id: requestId,
          reason: reason.value,
        }),
        (body) => performWrite(el, body, done),
      );
      if (!el.isConnected) return;
      inputs.forEach(({ element, disabled }) => {
        element.disabled = uncertain || disabled;
      });
      button.textContent = uncertain ? "Retry previous save" : buttonLabel();
      if (uncertain)
        status.append(
          document.createTextNode(
            " The last save is uncertain. Values are locked; retry the previous save before making another change.",
          ),
        );
    });
    return el;
  }
  function applicationControls({ application, profile }, memberData) {
    const root = node("section", null, "membership-controls");
    const review = form(
      "Application review",
      "Approve, decline, or request changes and email the applicant. Membership standing and profile visibility stay unchanged. Reopening sends no email.",
    );
    review.append(
      node(
        "p",
        "Review state: " + label(application.review_state),
        "state-summary",
      ),
    );
    const options = reviewStates[application.review_state] || [];
    const choice = select(review, "review-decision", "Decision", [
      ["", "Choose a decision"],
      ...options.map((state) => [
        state,
        state === "pending"
          ? "Reopen for review"
          : state === "changes_requested"
            ? "Request changes"
            : label(state),
      ]),
    ]);
    choice.required = true;
    const recipient = node(
      "p",
      "Choose a decision to see the email recipient.",
      "help",
    );
    recipient.setAttribute("aria-live", "polite");
    review.append(recipient);
    const applicantMessage = control(
      review,
      "applicant-message",
      "Message to applicant",
      "",
      { max: 4000, multiline: true },
    );
    applicantMessage.rows = 4;
    const messageField = applicantMessage.closest(".editor-field");
    const messageHelp = node(
      "p",
      "Required when requesting changes. This message is included in the email; the private reason below is never included.",
      "help",
    );
    messageHelp.id = "applicant-message-help";
    applicantMessage.setAttribute("aria-describedby", messageHelp.id);
    messageField.append(messageHelp);
    messageField.hidden = true;
    const buttonLabel = () =>
      choice.value === "pending"
        ? "Reopen for review"
        : "Record decision and email applicant";
    root.append(
      finish(
        review,
        "Record decision",
        (values) => ({
          action: "review-application",
          id: application.id,
          revision: application.revision,
          state: values.get("review-decision"),
          ...(values.get("review-decision") !== "pending"
            ? { applicant_message: applicantMessage.value }
            : {}),
        }),
        loadView,
        buttonLabel,
      ),
    );
    choice.addEventListener("change", () => {
      const sends = choice.value && choice.value !== "pending";
      messageField.hidden = !sends;
      applicantMessage.required = choice.value === "changes_requested";
      messageField.querySelector("label").textContent =
        applicantMessage.required
          ? "Message to applicant (required)"
          : "Message to applicant (optional)";
      recipient.textContent = sends
        ? `${label(choice.value)} email to ${application.email}. Review the message before recording the decision.`
        : choice.value === "pending"
          ? "Reopening records a private review change. No email is sent."
          : "Choose a decision to see the email recipient.";
      review.querySelector('button[type="submit"]').textContent = buttonLabel();
    });
    const section = node("details", null, "detail-card");
    section.append(
      node("summary", profile ? "Linked profile" : "Create or link a profile"),
    );
    section.append(
      node(
        "p",
        "A profile link does not approve an application, activate membership, or publish the profile.",
        "help",
      ),
    );
    if (profile)
      section.append(
        link("Manage " + profile.name + " →", "#members/" + profile.id),
      );
    else
      section.append(
        link("Create a draft profile →", "#members/new/" + application.id),
      );
    const linking = form(
      "Link an existing profile",
      "Choose an existing profile only when it represents this applicant. Original answers remain unchanged.",
    );
    const member = select(
      linking,
      "linked-profile",
      "Profile",
      [
        ["", "No linked profile"],
        ...memberData.members
          .filter((m) => m.member_type === application.applicant_type)
          .map((m) => [m.id, m.name]),
      ],
      application.member_id || "",
    );
    section.append(
      finish(linking, "Save profile link", () => ({
        action: "link-profile",
        id: application.id,
        revision: application.revision,
        member_id: member.value || null,
      })),
    );
    root.append(section);
    return root;
  }
  function history(events) {
    const root = node("section", null, "detail-card");
    root.append(node("h2", "Profile and membership history"));
    if (!events.length)
      root.append(
        node(
          "p",
          "No changes have been recorded. Existing profiles retain their source visibility; membership standing starts unconfirmed.",
          "help",
        ),
      );
    for (const event of events) {
      root.append(
        node("h3", label(event.event_type)),
        node(
          "p",
          date(event.created_at) +
            " · Revision " +
            event.revision +
            " · " +
            (event.actor_label || "Steward"),
          "help",
        ),
        node("p", event.reason),
      );
      const changes = event.changes;
      if (
        ["membership_changed", "visibility_changed"].includes(event.event_type)
      )
        root.append(
          node(
            "p",
            label(changes.before) + " → " + label(changes.after),
            "state-summary",
          ),
        );
      else if (changes?.after?.profile) {
        const before = changes.before?.profile || {},
          after = changes.after.profile;
        const list = node("ul");
        const value = (v) => (Array.isArray(v) ? v.join(", ") : v) || "Not set";
        for (const key of [
          "name",
          "location",
          "summary",
          "vision",
          "website",
          "avatar",
          "focus_areas",
          "contribution_areas",
        ])
          if (value(before[key]) !== value(after[key])) {
            list.append(
              node(
                "li",
                label(key) +
                  ": " +
                  value(before[key]) +
                  " → " +
                  value(after[key]),
              ),
            );
          }
        if (
          JSON.stringify(changes.before?.organization_ids || []) !==
          JSON.stringify(changes.after.organization_ids || [])
        )
          list.append(node("li", "Affiliation links changed."));
        root.append(list);
      }
    }
    return root;
  }
  function editor(member, data, application, currentOrganizations) {
    const el = form(
      member ? "Edit curated profile" : "Create a draft profile",
      member?.publication_state === "published"
        ? "This profile is public. Saving changes updates its public fields immediately. Membership standing stays unchanged."
        : "Curate only the information intended for the public profile. Saving keeps it unpublished; approval and membership standing are separate.",
    );
    const fields = {};
    fields.name = control(
      el,
      "profile-name",
      "Profile name (required)",
      member?.name || application?.display_name || "",
      { max: 200, required: true },
    );
    const type = select(
      el,
      "profile-type",
      "Member type",
      [
        ["individual", "Individual"],
        ["organization", "Organization"],
      ],
      member?.member_type || application?.applicant_type || "individual",
    );
    type.disabled = !!member || !!application;
    if (member)
      el.append(
        node(
          "p",
          "Member type is fixed to preserve identity and relationships.",
          "help",
        ),
      );
    for (const [key, title, max, multiline] of [
      ["location", "Location", 300],
      ["summary", "Curated summary", 2000, true],
      ["vision", "Public vision", 5000, true],
      ["website", "Website URL", 2048],
      ["avatar", "Avatar URL", 2048],
      ["focus_areas", "Focus areas, separated by commas", 1600],
      ["contribution_areas", "Contribution areas, separated by commas", 1600],
    ]) {
      fields[key] = control(
        el,
        "profile-" + key,
        title,
        Array.isArray(member?.[key]) ? member[key].join(", ") : member?.[key],
        { max, multiline },
      );
      if (["website", "avatar"].includes(key)) {
        fields[key].type = "url";
        fields[key].pattern = "https?://.+";
        fields[key].title = "Use a URL starting with http:// or https://";
        fields[key].autocomplete = "off";
        fields[key].spellcheck = false;
      }
    }
    const affiliations = node("fieldset");
    affiliations.append(
      node("legend", "Organization affiliations"),
      node(
        "p",
        "Only links between an individual and an organization are supported.",
        "help",
      ),
    );
    const organizations = new Map(
      data.members
        .filter((m) => m.member_type === "organization")
        .map((m) => [m.id, m]),
    );
    for (const org of currentOrganizations) organizations.set(org.id, org);
    for (const org of organizations.values()) {
      const caption = node("label", null, "contributor-option"),
        checkbox = node("input");
      checkbox.type = "checkbox";
      checkbox.name = "organization_ids";
      checkbox.value = org.id;
      checkbox.checked = currentOrganizations.some(
        (current) => current.id === org.id,
      );
      caption.append(checkbox, document.createTextNode(org.name));
      affiliations.append(caption);
    }
    const syncType = () => {
      affiliations.hidden = type.value !== "individual";
      affiliations.querySelectorAll("input").forEach((input) => {
        input.disabled = type.value !== "individual";
      });
    };
    type.addEventListener("change", syncType);
    syncType();
    el.append(affiliations);
    return finish(
      el,
      member ? "Save profile changes" : "Create draft profile",
      (values) => {
        const payload = { name: fields.name.value, member_type: type.value };
        for (const key of [
          "location",
          "summary",
          "vision",
          "website",
          "avatar",
        ])
          payload[key] = fields[key].value;
        for (const key of ["focus_areas", "contribution_areas"])
          payload[key] = fields[key].value
            .split(",")
            .map((v) => v.trim())
            .filter(Boolean);
        payload.organization_ids = values.getAll("organization_ids");
        return {
          action: "save-profile",
          payload,
          ...(member ? { id: member.id, revision: member.revision } : {}),
          ...(application
            ? {
                application_id: application.id,
                application_revision: application.revision,
              }
            : {}),
        };
      },
      (result) => {
        if (location.hash === "#members/" + result.id) loadView();
        else location.hash = "members/" + result.id;
      },
    );
  }
  function stateForm(member, kind) {
    const standing = kind === "membership";
    const key = standing ? "membership_status" : "publication_state";
    const choices = standing
      ? ["unconfirmed", "active", "paused", "ended"]
      : ["draft", "published", "hidden"];
    const el = form(
      standing ? "Membership standing" : "Profile visibility",
      standing
        ? "Record standing independently. This does not approve an application or hide a public profile."
        : "Published profiles appear on the website. Draft and hidden profiles stay private. Changing visibility does not change membership standing.",
    );
    el.append(node("p", "Current: " + label(member[key]), "state-summary"));
    const choice = select(
      el,
      kind + "-state",
      standing ? "New membership standing" : "New profile visibility",
      [
        ["", "Choose a new state"],
        ...choices.filter((s) => s !== member[key]).map((s) => [s, label(s)]),
      ],
    );
    choice.required = true;
    return finish(
      el,
      standing ? "Update membership standing" : "Update profile visibility",
      () => ({
        action: standing ? "set-membership-status" : "set-profile-visibility",
        id: member.id,
        revision: member.revision,
        state: choice.value,
      }),
    );
  }
  function renderMember(root, detail, data, application) {
    const member = detail?.member;
    root.append(link("← Back to members", "#members"));
    if (member) {
      const summary = node("dl", null, "member-facts detail-card");
      for (const [title, value] of [
        ["Member type", label(member.member_type)],
        ["Membership standing", label(member.membership_status)],
        ["Profile visibility", label(member.publication_state)],
        ["Revision", member.revision],
      ]) {
        const fact = node("div");
        fact.append(node("dt", title), node("dd", value));
        summary.append(fact);
      }
      root.append(summary);
      const controls = node("div", null, "membership-state-grid");
      controls.append(
        stateForm(member, "membership"),
        stateForm(member, "visibility"),
      );
      root.append(controls);
    } else if (application)
      root.append(
        node(
          "p",
          "Creating a profile for " +
            application.display_name +
            ". This will link the draft to that application.",
          "help",
        ),
      );
    root.append(editor(member, data, application, detail?.organizations || []));
    if (member) root.append(history(detail.history));
  }
  return { applicationControls, renderMember };
};
