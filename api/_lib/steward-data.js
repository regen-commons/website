import { createClient } from "@supabase/supabase-js";

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

function result({ data, error, count }) {
  if (error)
    throw new AdminError(
      error.status === 429 ? 429 : 503,
      error.status === 429 ? "rate_limited" : "provider_unavailable",
    );
  return { data, count };
}

// Every database call carries the user's token. No service-role key is used.
export function createSupabaseProvider({ url, key, request = fetch }) {
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
      if (error || !data.session)
        throw new AdminError(
          error?.status === 429 ? 429 : 401,
          error?.status === 429 ? "rate_limited" : "invalid_code",
        );
      return {
        token: data.session.access_token,
        expiresIn: Math.min(data.session.expires_in, 3600),
      };
    },
    async authorize(token) {
      const db = client(token);
      const { data, error } = await db.auth.getUser(token);
      if (
        error &&
        (!error.status ||
          error.status >= 500 ||
          error.name === "AuthRetryableFetchError")
      )
        throw new AdminError(503, "provider_unavailable");
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
      if (!response.ok && response.status !== 401)
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
          .order("submitted_at", { ascending: false })
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
  };
}
