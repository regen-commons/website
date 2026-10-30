import { createClient } from "@supabase/supabase-js";
import { drainNotifications } from "./intake-notifications.js";

export class AdminError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}

const summaryColumns =
  "id,display_name,applicant_type,submitted_at,review_state,cohort,nominator,revision,member_id";
const memberColumns =
  "id,name,member_type,publication_state,location,summary,website,focus_areas,contribution_areas";

function result({ data, error, count, status }) {
  if (error) {
    if (/^PT(400|403|404|409|429)$/.test(error.code || ""))
      throw new AdminError(Number(error.code.slice(2)), error.message);
    const limited = (error.status ?? status) === 429;
    throw new AdminError(
      limited ? 429 : 503,
      limited ? "rate_limited" : "provider_unavailable",
    );
  }
  return { data, count };
}

function checkAuthService(error) {
  if (!error) return;
  if (error.status === 429) throw new AdminError(429, "rate_limited");
  if (
    !error.status ||
    error.status >= 500 ||
    error.name === "AuthRetryableFetchError"
  )
    throw new AdminError(503, "provider_unavailable");
}

// Every database call carries the user's token. No service-role key is used.
export function createSupabaseProvider({
  url,
  key,
  request = fetch,
  env = process.env,
}) {
  if (!url || !key) throw new AdminError(503, "admin_not_configured");
  const client = (token) =>
    createClient(url, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
      global: {
        ...(token ? { headers: { Authorization: `Bearer ${token}` } } : {}),
        fetch: (input, options) =>
          request(input, { ...options, signal: AbortSignal.timeout(10000) }),
      },
    });
  return {
    async requestCode(email) {
      const { error } = await client().auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false },
      });
      // Do not reveal whether an account exists. Delivery failures still surface.
      if (
        error &&
        !["otp_disabled", "user_not_found", "signup_disabled"].includes(
          error.code,
        )
      )
        result({ error });
    },
    async verifyCode(email, token) {
      const { data, error } = await client().auth.verifyOtp({
        email,
        token,
        type: "email",
      });
      checkAuthService(error);
      if (error || !data.session) throw new AdminError(401, "invalid_code");
      return {
        token: data.session.access_token,
        expiresIn: Math.min(data.session.expires_in, 3600),
      };
    },
    async authorize(token) {
      const db = client(token);
      const { data, error } = await db.auth.getUser(token);
      checkAuthService(error);
      if (error || !data.user) throw new AdminError(401, "sign_in_required");
      const access = result(await db.rpc("steward_access")).data;
      if (access !== true) throw new AdminError(403, "steward_required");
      return { id: data.user.id, email: data.user.email };
    },
    async signOut(token) {
      const response = await request(`${url}/auth/v1/logout?scope=local`, {
        method: "POST",
        headers: { apikey: key, Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(10000),
      });
      // Match Supabase Auth's sign-out semantics for expired/deleted sessions.
      if (!response.ok && ![401, 403, 404].includes(response.status))
        throw new AdminError(503, "sign_out_failed");
    },
    async applications(token, { search, state, type, offset }) {
      let query = client(token)
        .from("applications")
        .select(summaryColumns, { count: "exact" });
      if (search)
        query = query.ilike(
          "display_name",
          `%${search.replace(/[\\%_]/g, "\\$&")}%`,
        );
      if (state) query = query.eq("review_state", state);
      if (type) query = query.eq("applicant_type", type);
      const { data, count } = result(
        await query
          .order("submitted_at", { ascending: false, nullsFirst: false })
          .order("id")
          .range(offset, offset + 24),
      );
      return { applications: data, total: count, offset };
    },
    async application(token, id) {
      const db = client(token);
      const application = result(
        await db
          .from("applications")
          .select(
            `${summaryColumns},email,answers_schema_version,original_answers`,
          )
          .eq("id", id)
          .maybeSingle(),
      ).data;
      if (!application) throw new AdminError(404, "application_not_found");
      const [profile, history] = await Promise.all([
        application.member_id
          ? db
              .from("members")
              .select(memberColumns)
              .eq("id", application.member_id)
              .maybeSingle()
          : { data: null },
        db
          .from("review_events")
          .select("id,event_type,created_at,reviewed_revision,note")
          .eq("application_id", id)
          .order("created_at"),
      ]);
      return {
        application,
        profile: result(profile).data,
        history: result(history).data,
      };
    },
    async members(token) {
      const db = client(token);
      // Paginate explicitly: PostgREST's default cap must not silently lose relations.
      async function all(table, columns, order, tieBreaker) {
        const rows = [];
        for (let offset = 0; ; offset += 500) {
          let query = db.from(table).select(columns).order(order);
          if (tieBreaker) query = query.order(tieBreaker);
          const page = result(await query.range(offset, offset + 499)).data;
          rows.push(...page);
          if (page.length < 500) return rows;
        }
      }
      const [members, affiliations, contributions, contributionMembers] =
        await Promise.all([
          all("members", memberColumns, "id"),
          all(
            "affiliations",
            "member_id,organization_id",
            "member_id",
            "organization_id",
          ),
          all("contributions", "id,title,publication_state", "id"),
          all(
            "contribution_members",
            "contribution_id,member_id",
            "contribution_id",
            "member_id",
          ),
        ]);
      return { members, affiliations, contributions, contributionMembers };
    },
    async notifications(token, applicationId) {
      return {
        notifications: result(
          await client(token).rpc("application_notifications", {
            p_application_id: applicationId,
          }),
        ).data,
      };
    },
    async retryNotification(token, body) {
      const db = client(token);
      // The user's current session claims exactly one eligible email. It cannot
      // supply a recipient, reset attempts, change channels or create a new job.
      const job = result(
        await db.rpc("retry_notification", {
          p_application_id: body.application_id,
          p_job_id: body.job_id,
          p_attempts: body.attempts,
        }),
      ).data;
      await drainNotifications({
        request,
        env,
        claim: async () => [job],
        finish: (job, status, outcome) =>
          db
            .rpc("complete_notification_retry", {
              p_job_id: job.id,
              p_lease: job.lease_id,
              p_status: status,
              p_provider_message_id: outcome.provider_message_id,
              p_failure_code: outcome.failure_code,
            })
            .then(result),
      });
      return this.notifications(token, body.application_id);
    },
    async content(
      token,
      resource,
      { search = "", state = "", offset = 0 } = {},
    ) {
      let query = client(token).from(resource).select("*", { count: "exact" });
      if (search)
        query = query.ilike(
          resource === "seeds" ? "text" : "title",
          `%${search.replace(/[\\%_]/g, "\\$&")}%`,
        );
      if (state) query = query.eq("publication_state", state);
      const { data, count } = result(
        await query
          .order("created_at", { ascending: false })
          .order("id")
          .range(offset, offset + 24),
      );
      return { items: data, total: count, offset };
    },
    async contentDetail(token, resource, id) {
      const db = client(token);
      const item = result(
        await db.from(resource).select("*").eq("id", id).maybeSingle(),
      ).data;
      if (!item) throw new AdminError(404, "content_not_found");
      const history = [];
      for (let offset = 0; ; offset += 500) {
        const page = result(
          await db
            .from("content_events")
            .select("id,action,revision,reason,created_at,actor_id,actor_label")
            .eq(resource === "seeds" ? "seed_id" : "contribution_id", id)
            .order("created_at")
            .order("id")
            .range(offset, offset + 499),
        ).data;
        history.push(...page);
        if (page.length < 500) break;
      }
      const contributors =
        resource === "contributions"
          ? result(
              await db
                .from("contribution_members")
                .select("member_id")
                .eq("contribution_id", id),
            ).data.map((r) => r.member_id)
          : [];
      return { item, history, contributor_ids: contributors };
    },
    async moderate(token, body) {
      return result(
        await client(token).rpc("moderate_content", {
          p_resource: body.resource,
          p_id: body.id,
          p_revision: body.revision,
          p_state: body.state,
          p_reason: body.reason,
        }),
      ).data;
    },
    async saveContribution(token, body) {
      return result(
        await client(token).rpc("save_contribution", {
          p_id: body.id || null,
          p_revision: body.revision || null,
          p_payload: body.payload,
          p_request_id: body.request_id,
        }),
      ).data;
    },
  };
}
