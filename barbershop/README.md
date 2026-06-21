# barbershop

Coiffeur/barbershop reservation platform for Tunisia. Flutter (web-first) +
Supabase. This is **Plan 1 — Foundation (Auth & Roles)**: sign up / log in
(email or Google) and land on a role-appropriate home screen, with `profiles`
secured by Row-Level Security.

See the spec and plans in `../docs/superpowers/`.

## Prerequisites

- Flutter 3.35+ (`flutter --version`)
- Docker (for the local Supabase stack)
- Supabase CLI (`supabase --version`)

## Running locally (against the local Supabase stack)

```bash
# From the repo root: start the local stack
supabase start
supabase status        # note the API URL and the publishable key

# Run the app on Chrome (substitute the publishable key from `supabase status`)
cd barbershop
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local publishable key>
```

Local Supabase auto-confirms emails, so email signup works immediately. A new
account defaults to the `customer` role and is routed to `/home`.

## Running against the hosted (cloud) project

```bash
# One-time: push the schema to your cloud project
supabase login
supabase link --project-ref <your-project-ref>
supabase db push

# Run the app pointed at the cloud project (keys from Dashboard -> Settings -> API)
cd barbershop
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<your-project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<cloud publishable key>
```

Note: the hosted project may require email confirmation depending on your Auth
settings (Dashboard -> Authentication -> Providers -> Email).

## Tests

```bash
cd barbershop && flutter analyze && flutter test   # Dart unit + widget tests
supabase test db                                   # pgTAP RLS tests (from repo root)
```

## Google sign-in (dev)

Google OAuth requires a Google Cloud OAuth client. For local testing, add the
client id/secret under `[auth.external.google]` in `supabase/config.toml` and set
`enabled = true`, then `supabase stop && supabase start`. For the cloud project,
configure Google under Dashboard -> Authentication -> Providers. The "Continuer
avec Google" button uses `signInWithOAuth(OAuthProvider.google)` and is fully
wired — it only needs these credentials to complete the redirect.

## Manual smoke check (in-browser)

1. Open `/signup`, enter name/email/password, tap **S'inscrire**.
2. You should be redirected to `/home` (customer). Verify the profile:
   `docker exec -i supabase_db_<project> psql -U postgres -d postgres -c "select role from public.profiles;"`
3. Tap logout -> back to `/login`. Sign back in -> `/home`.
4. To test role routing, set a profile's role to `admin` in the DB and reload;
   you should land on `/admin`.

## Salon onboarding & approval (Plan 2)

- A logged-in customer taps **Inscrire mon salon** (`/salon/register`), submits the
  form, and `register_salon` creates a `pending` salon and elevates them to
  `salon_owner` — the app then routes them to the salon dashboard.
- While `pending`/`rejected`/`suspended`, the dashboard shows a status banner.
  Once an admin approves it, the dashboard shows the editable salon profile
  (name, city, description, address, and the **Afficher les prix** toggle).
- An `admin` lands on the approvals screen, listing pending salons with
  **Valider** / **Refuser**.
- All salon writes go through `SECURITY DEFINER` RPCs (`register_salon`,
  `update_my_salon`, `set_salon_status`); the table has no write policy, so owners
  cannot self-approve. Reads are RLS-gated: approved salons are public; pending
  salons are visible only to their owner and admins.
