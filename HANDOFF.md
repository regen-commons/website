# Handoff Checklist — going live

The code in this repo is complete and ready to deploy. Everything below is account / infrastructure work that requires *your* logins. Work through it top to bottom; each step gives you a value that the next step needs.

Estimated time end-to-end: **2–3 hours**, mostly waiting on DNS propagation.

---

## 1 · GitHub (15 min)

**Goal:** Code lives in a new GitHub org you control, with shared maintainer access.

- [ ] Create a new GitHub account (or use an existing one) for Regen Commons.
- [ ] Create a new org: `regen-commons` (or your preferred name). GitHub → top-right → **Your organizations** → **New organization** → Free plan is fine.
- [ ] Create a new empty repo inside the org: `site` (or `regen-commons-site`). Don't initialize with README — we have one.
- [ ] In this prototype directory locally:
  ```bash
  cd prototype
  git remote remove origin       # remove old kosmicgardener remote
  git remote add origin git@github.com:YOUR-ORG/YOUR-REPO.git
  git add .
  git commit -m "Initial Notion + Resend wiring"
  git push -u origin main
  ```
- [ ] **Branch protection:** Repo → Settings → Branches → Add rule for `main`:
  - ✅ Require pull request before merging (1 approval)
  - ✅ Require status checks (Vercel will appear here after step 4)
- [ ] **Add steward collaborators:** Org → People → Invite member. Each gets the `Member` role; for repo write access, repo → Settings → Collaborators → Add with `Maintain` role.

---

## 2 · Notion (45 min)

**Goal:** Three databases, one integration token, three database IDs.

### 2a · Create the integration

- [ ] Go to https://www.notion.so/profile/integrations → **New internal integration**.
- [ ] Name: `Regen Commons Site`. Workspace: pick the workspace where the DBs will live. Capabilities: Read content + Update content + Insert content.
- [ ] Copy the **Internal Integration Secret** (starts `secret_…` or `ntn_…`). Save somewhere safe; you'll paste it into Vercel later.

### 2b · Create the three databases

In whichever Notion page you want them under:

**Members** — full-page database. Properties (exact names):
- `Name` (Title)
- `Type` (Select: Individual, Organization)
- `Status` (Select: Pending, Active, Steward, Archived; default Pending)
- `Location` (Text)
- `Focus areas` (Multi-select — pre-create options: Ecological restoration, Regenerative agriculture, Governance & coordination, Regenerative finance, Community building, Education & knowledge, Technology & infrastructure, Indigenous & traditional knowledge, Health & wellbeing, Arts & culture, Policy & advocacy, Other)
- `Contribution areas` (Multi-select — pre-create options: Governance design, Community facilitation, Knowledge sharing, Project development, Cultural stewardship, Communications, Other)
- `Vision` (Text)
- `Website` (URL)
- `Avatar` (Files & media)
- `Affiliation` (Relation → this same Members DB)
- `Date joined` (Date)
- `Email` (Email)
- `Telegram` (Text)
- `Org rep` (Text)
- `Org description` (Text)
- `Nominator` (Text)
- `Regen relationship` (Text)
- `Values resonance` (Text)
- `Meaningful participation` (Text)
- `Capital contribution` (Text)
- `Contribution other` (Text)
- `Commitment` (Select: Yes, Yes with constraints, Unsure)
- `Constraints` (Text)
- `Authorized` (Select: Yes, Yes with limits)
- `Other colleagues` (Text)
- `Agreement reviewed` (Select: Yes, Has questions)
- `Governance consent` (Select: Yes, Has questions)
- `Closing notes` (Text)

**Contributions** — full-page database. Properties:
- `Title` (Title)
- `Type` (Select: Knowledge, Infrastructure, Brand & IP, Governance & Legal, Coordination)
- `Stage` (Select: Seed, Sprout, Flowering, Tree)
- `Status` (Select: Indexed, In progress, Curated, Archived)
- `Description` (Text)
- `Capital form` (Text)
- `Tier` (Text)
- `Contributor` (Relation → Members)
- `License` (Select: CopyFair, Open source, Custom)
- `Tags` (Multi-select)
- `Date contributed` (Date)

**Seeds** — full-page database. Properties:
- `Text` (Title — the vision quote itself)
- `Author` (Text — optional attribution)
- `Status` (Select: Active, Archived)
- `Tags` (Multi-select)

### 2c · Connect each DB to the integration

- [ ] On each of the three databases: top-right **⋯** → **Connections** → search for `Regen Commons Site` → Confirm.

### 2d · Copy database IDs

For each database, the URL looks like:
`https://www.notion.so/your-workspace/abc123def456…?v=…`

Copy the 32-character hex chunk *before* `?v=`. That's the database ID. You'll need three: members, contributions, seeds.

### 2e · Seed the databases (recommended)

- [ ] Add 2–3 test members with `Status = Active` so the map page has data on first load.
- [ ] Add 1–2 contributions linked to those members.
- [ ] Copy 10–20 quotes from the existing fallback `SEEDED` array (in `script.js` near the top) into the Seeds DB so the seeds page works.

---

## 3 · Resend (20 min)

**Goal:** API key + verified sender domain.

- [ ] Sign up at https://resend.com (free tier: 3,000 emails/month).
- [ ] **Add domain:** Resend → Domains → Add Domain → enter your domain. Resend will give you 3–5 DNS records (SPF / DKIM / return-path).
- [ ] Add those DNS records at your registrar. Wait for verification (usually 5–30 min).
- [ ] **Create API key:** Resend → API Keys → Create. Scope: full access. Copy the key (starts `re_…`).
- [ ] **Decide your `from` email:** something like `hello@yourdomain.org` or `commons@yourdomain.org`. It must be on the verified domain.
- [ ] **Add stewards as team members** (Resend → Team) so anyone can rotate the key or check email logs.

---

## 4 · Vercel (20 min)

**Goal:** Site deployed and connected to GitHub for auto-deploy on push.

- [ ] Sign up at https://vercel.com using **Sign up with GitHub** (signs in via the org you created).
- [ ] **Create a Team** (Vercel calls personal accounts "Hobby"; a Team gives shared access). Settings → Teams → Create Team. Free.
- [ ] Invite stewards to the team.
- [ ] **Import the repo:** Add New → Project → Import the GitHub repo from your org.
  - **Framework Preset:** Other
  - **Root Directory:** `.` (the repo root — since the prototype IS the repo root)
  - **Build Command:** *leave empty*
  - **Output Directory:** *leave empty (defaults to `.`)*
  - **Install Command:** `npm install` (default)
- [ ] **Add environment variables** before deploying (Settings → Environment Variables). Apply each to all three environments (Production, Preview, Development):

| Variable | Value |
|---|---|
| `NOTION_TOKEN` | the integration secret from step 2a |
| `NOTION_MEMBERS_DB_ID` | from step 2d |
| `NOTION_CONTRIBUTIONS_DB_ID` | from step 2d |
| `NOTION_SEEDS_DB_ID` | from step 2d |
| `RESEND_API_KEY` | from step 3 |
| `RESEND_FROM_EMAIL` | e.g. `hello@yourdomain.org` |
| `STEWARD_NOTIFY_EMAILS` | comma-separated list, e.g. `patricia@…,monty@…` |
| `SITE_URL` | `https://yourdomain.org` (will work after step 5) |

- [ ] Click **Deploy**. First deploy lands at something like `your-project.vercel.app`. Verify:
  - `https://your-project.vercel.app/api/members` returns `{"members":[…]}`
  - `https://your-project.vercel.app/api/contributions` returns `{"contributions":[…]}`
  - `https://your-project.vercel.app/api/seeds` returns `{"seeds":[…]}`
  - `https://your-project.vercel.app/map.html` shows your test members + contributions

---

## 5 · Domain (15 min active, up to 24 h propagation)

**Goal:** Custom domain pointing at Vercel.

- [ ] In Vercel project → Settings → Domains → Add your domain (apex + `www`).
- [ ] At your registrar's DNS panel, add:
  - Apex (`yourdomain.org`): **A** record → `76.76.21.21`
  - `www.yourdomain.org`: **CNAME** → `cname.vercel-dns.com`
- [ ] Wait for Vercel to show "Valid Configuration" (usually <10 min, sometimes longer).
- [ ] Vercel issues SSL automatically once DNS resolves.
- [ ] Set the apex as Primary (Vercel will redirect `www` → apex, or vice versa per your preference).

---

## 6 · End-to-end smoke test (15 min)

On the live domain:

- [ ] **Map page** — your test members and contributions render. Toggle one member's `Status` to `Pending` in Notion, wait 5 min, refresh — they disappear.
- [ ] **Seeds page** — visit `/seeds.html`, type a vision, click "Plant this seed" — the seed field renders with the quotes from your Seeds DB.
- [ ] **Apply flow** — fill out and submit `/join.html` with a test email. Verify:
  - Confirmation page renders
  - Confirmation email arrives at the test address within ~30s
  - Steward notification email arrives in the inboxes listed in `STEWARD_NOTIFY_EMAILS`
  - A new row exists in Members DB with `Status = Pending`
  - The new row does **not** appear on the public map
- [ ] **Approval flow** — flip the new row to `Status = Active` in Notion, wait 5 min, refresh map — they appear.
- [ ] **Multi-maintainer flow** — have a second steward open a tiny PR (typo fix via GitHub web editor). Confirm Vercel posts a preview URL in the PR within ~30s. Merge. Confirm production redeploys.

---

## When something goes wrong

The README in this repo has a **Troubleshooting** section. Most issues fall into:
- Wrong/missing env var in Vercel
- Database not shared with the integration in Notion
- Resend domain not verified
- DNS hasn't propagated yet (give it up to 24 h)

Vercel function logs (Deployments → click a deployment → Functions → click a function) are the first place to look when an `/api/*` route is misbehaving.
