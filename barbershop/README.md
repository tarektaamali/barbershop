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

## Salon content management (Plan 3)

- The approved-salon dashboard is a tabbed view: **Profil** (the salon profile
  form), **Services**, and **Équipe** (staff).
- **Services** — add/edit (name, duration, price) and activate/deactivate.
- **Équipe** — add/edit staff (name, specialty) and activate/deactivate.
- Public can read the services and staff of approved salons. All writes go through
  owner-scoped `SECURITY DEFINER` RPCs (`add_service`/`update_service`/
  `set_service_active`, `add_staff`/`update_staff`/`set_staff_active`), guarded by
  `owns_salon()` — an owner can only mutate their own salon's content.

## Working hours & availability (Plan 4)

- The salon dashboard gains an **Horaires** tab: pick a coiffeur, then add/remove
  weekly time ranges per day (multiple ranges per day support breaks). Hours are
  stored as `working_hours` rows (`weekday` is Postgres `dow`: 0=Sunday..6=Saturday).
- `available_slots(salon, service, date, staff?, slot_minutes)` is a server-side
  SQL function that returns the bookable start times for a service on a date —
  generated from each staff member's working hours, minus confirmed/completed
  bookings and unexpired pending holds. With `staff` null it returns the union
  across all active staff ("sans préférence").
- The `bookings` table + a GiST **overlap exclusion constraint** (no two
  confirmed/completed bookings overlap for the same staff) ship here so the slot
  function is correct; booking *write RPCs and the booking UI* arrive in Plan 5.

## Booking engine — request → confirm (Plan 5)

- A customer browses approved salons from the home screen, opens a salon, and
  picks a **service**, optional **coiffeur** (default "Sans préférence"), a
  **date**, and an open **slot**, then taps **Demander ce créneau**.
- `request_booking` creates a `pending` booking and **soft-holds the slot for 15
  minutes** (`hold_expires_at`), auto-assigning the chosen staff or the first
  free one — so the slot disappears from `available_slots` for everyone else
  while the request is pending.
- The owner sees pending requests in the **Demandes** tab and **Confirme** or
  **Refuse** them; confirming is guarded by the overlap exclusion constraint
  (a conflicting confirmation fails with `23P01`).
- The customer sees their bookings in **Mes réservations** and can **Annuler** a
  pending/confirmed one.
- All transitions go through owner-only (`confirm`/`decline`) or customer-only
  (`request`/`cancel`) `SECURITY DEFINER` RPCs. (Notifications come in a later
  plan.)

## Discovery feed (Plan 6)

- The customer home is now a full-screen, vertically-swipeable **story-style
  feed** of approved salons (cover image or gradient, name/city/rating overlay,
  ♥ favorite, **Réserver**), with a search field filtering by name/city.
- Tapping a card opens the **salon profile** (cover header, services with prices
  if `show_prices`, staff, rating) with a **Réserver** button → the booking flow.
- Customers **favorite** salons (♥ on the feed/profile) and see them in
  **Favoris**; `toggle_favorite` is idempotent (toggles on/off).
- Owners set a **cover image URL** on their salon profile form (`set_salon_cover`);
  the feed and profile render it with a gradient fallback.
- Image uploads via Supabase Storage (and multi-photo galleries/stories) are a
  later refinement — this version uses a single owner-provided cover URL.
