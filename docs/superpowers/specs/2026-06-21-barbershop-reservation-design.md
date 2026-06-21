# Barbershop — Coiffeur Reservation Platform (Tunisia)

**Design spec** · 2026-06-21 · Repo: `github.com/tarektaamali/barbershop`

## 1. Summary

A mobile-first platform for discovering hair salons / barbershops in Tunisia and
booking appointments online. Customers discover salons through a visual,
Snapchat-style story feed and request appointments; salons confirm or decline.
The salon side doubles as a lightweight daily-operations / point-of-sale (caisse)
tool: staff log walk-ins, declare who is working each day, and the owner sees
daily takings with a per-staff breakdown. An admin approves salons and moderates
reviews.

The platform launches **free**. Monetization (subscription plans, online payment)
is anticipated in the architecture but **out of scope** for this version.

## 2. Goals & Non-Goals

### Goals (this version)
- Visual, story-feed discovery of salons (with search/filter fallback).
- Online booking via a **request → salon confirms** model.
- Multi-staff salons: each coiffeur has their own schedule; choosing a coiffeur
  is **optional** ("Sans préférence" → salon assigns).
- Availability auto-generated from working hours + service duration + daily roster.
- Salon operations: requests inbox, calendar, walk-ins, daily staff roster.
- Caisse: daily total + **per-staff** revenue and cut counts.
- Reviews with **admin moderation** and reporting ("signaler").
- Admin: approve salon accounts, moderate/delete reviews, suspend salons.
- Auth: email/password + Google.
- French-only UI, built localization-ready for later languages.

### Non-Goals (deliberately deferred — YAGNI)
- Online payment / deposits (this version: **pay at the salon**; gateways like
  Konnect / Flouci / Clictopay later).
- SMS / phone-OTP notifications and login.
- Arabic / multi-language UI and RTL (architecture is localization-ready).
- Map-based discovery.
- Per-staff service lists, commission auto-calculation.
- Subscription / paid plans and platform analytics.

All deferred items are anticipated in the data model and architecture so they can
be added without a rewrite.

## 3. Roles

| Role | Summary |
|------|---------|
| **Customer** | Discovers salons, books appointments, leaves reviews. |
| **Salon owner** | Full control of one salon: team, services, hours, requests, caisse. Account requires **admin approval**. |
| **Staff (coiffeur)** | Optional login scoped to their salon: own schedule, log own walk-ins, see own daily numbers. |
| **Admin** | Approves salons, moderates reviews, manages/suspends accounts. |

## 4. Tech Stack & Architecture

- **Frontend:** Flutter, single codebase. Web-first during development
  (`flutter run -d chrome`); ships to Android/iOS for customers. Web used for
  salon ops and admin.
- **Backend:** Supabase — Postgres, Auth (email + Google), Storage (salon/staff
  photos), Row-Level Security, Edge Functions (trusted server-side logic),
  scheduled functions (cron) for soft-hold expiry.
- **Push notifications:** Firebase Cloud Messaging, mirrored by an in-app
  notification center.
- **Localization:** Flutter `intl` / ARB files from day one; all UI strings
  externalized (French now, additional languages later).

### App shape (Approach A — one codebase, role-based)

```
Flutter app (routes by role after login)
 ├─ Customer   → feed, salon profile, booking, my reservations, reviews
 ├─ Salon      → requests inbox, calendar, walk-ins, roster, caisse, manage
 └─ Admin      → salon approvals, review moderation, users
            │
            ▼
Supabase ── Postgres (+ RLS) · Auth · Storage · Edge Functions · Cron
            │
            ▼
        FCM push notifications
```

### Code organization (feature-first)
Feature modules: `auth`, `feed`, `booking`, `salon_ops`, `caisse`, `reviews`,
`admin`, plus shared `core` (models, Supabase client, theme, routing). Each
feature owns its UI + logic and reaches Supabase only through a thin repository
layer — screens never call the database directly. Keeps files small and each unit
independently understandable and testable.

## 5. Data Model (Postgres / Supabase)

### Identity & roles
- **`profiles`** (1:1 with `auth.users`): `id`, `role`
  (`customer` | `salon_owner` | `staff` | `admin`), `full_name`, `phone`,
  `avatar_url`, `language`, `fcm_token`, `created_at`.

### Salon & team
- **`salons`**: `id`, `owner_id`→profiles, `name`, `description`, `city`,
  `address`, `cover_url`, `status` (`pending` | `approved` | `rejected` |
  `suspended`), **`show_prices`** (bool), `rating_avg`, `rating_count`,
  `created_at`. New salons start `pending` until admin approves.
- **`salon_media`**: `id`, `salon_id`, `url`, `position` — photos for the story feed.
- **`staff`**: `id`, `salon_id`, `profile_id` (nullable — staff may exist as a
  name only or have a login), `display_name`, `avatar_url`, `specialty`, `active`.
- **`services`**: `id`, `salon_id`, `name`, `duration_min`, **`price`** (default),
  `active`. Salon-level; any active staff can perform them.

### Availability
- **`working_hours`**: `id`, `staff_id`, `weekday` (0–6), `start_time`,
  `end_time`. Multiple rows per weekday express breaks (e.g. 09:00–12:00,
  14:00–18:00). Recurring weekly template.
- **`staff_shifts`** (daily roster): `id`, `staff_id`, `date`, `status`
  (`working` | `off`), optional `start`/`end` override. Owner declares who works
  each day; a staff member is bookable on a date only if rostered `working`.

### Bookings & caisse (one table for reservations and walk-ins)
- **`bookings`**: `id`, `salon_id`, `customer_id` (nullable for walk-ins),
  `staff_id` (nullable until assigned for "sans préférence"), `service_id`,
  **`service_name_snapshot`**, **`price_default_snapshot`**, `date`,
  `start_time`, `end_time`, `status` (`pending` | `confirmed` | `declined` |
  `cancelled` | `completed` | `no_show`), `source` (`online` | `walkin`),
  `hold_expires_at`, **`actual_price`** (editable at payment), `created_by`,
  `created_at`, `confirmed_at`, `completed_at`.
  - *Reservation:* created by customer as `pending`, source `online`.
  - *Walk-in:* created by staff as `completed`, source `walkin`, `actual_price`
    set on the spot.
  - *Caisse:* `bookings` where `status = completed`, grouped by `date` and
    `staff_id` → daily total + per-staff revenue and cut counts. No separate table.

### Reviews & trust
- **`reviews`**: `id`, `salon_id`, `customer_id`, `booking_id` (verified visit),
  `rating` (1–5), `comment`, `status` (`pending` | `approved` | `rejected`),
  `moderated_by`, `moderated_at`, `created_at`. Public only when admin-approved.
- **`review_reports`** (signaler): `id`, `review_id`, `reporter_id`, `reason`,
  `created_at`.

### Engagement
- **`favorites`**: `id`, `customer_id`, `salon_id`.
- **`notifications`**: `id`, `user_id`, `type`, `title`, `body`, `data` (jsonb),
  `read`, `created_at`.

### Deliberate modeling choices
1. **Snapshots** — bookings store the service *name* and *default price* at
   booking time, so later edits to services/prices don't rewrite historical
   bookings or caisse totals.
2. **`actual_price` vs `services.price`** — `services.price` is the menu default
   (optionally hidden from customers via `salons.show_prices`);
   `bookings.actual_price` is what was really charged. It defaults to the service
   price but is **editable at checkout** (e.g. a foreign client pays more), and it
   is the figure the caisse counts.

## 6. Role Experiences

### Customer (mobile-first)
- **Visual feed** — full-screen, swipe-up story discovery (Snapchat-style), with a
  small **search/filter** icon (city, service, name) and **♥ save** to favorites.
- **Salon profile** — photos/stories, services (prices shown only if
  `show_prices`), staff, rating + approved reviews.
- **Booking flow** — coiffeur (optional, "Sans préférence" default) → service →
  date → slot → **request** → pending → push when confirmed/declined.
- **My reservations** — upcoming & past with status; cancel a pending/confirmed one.
- **Reviews** — after a completed visit, star rating + comment (→ admin approval).
- **Account** — email/Google login, profile, notification center.

### Salon side (owner + staff)
Same role family scoped to one salon; owner has full control, staff see a focused
subset.
- **Requests inbox** — confirm (assign a coiffeur if "sans préférence") or decline.
- **Today / calendar** — confirmed bookings per staff; mark **completed**
  (set/adjust `actual_price`) or **no-show**.
- **Walk-in** — one-tap add: staff + service, adjust price, save → recorded as a
  completed visit in the caisse.
- **Daily roster** — declare who works today (working/off, optional custom hours).
- **Caisse** — daily register: total takings + per-staff revenue and cut counts,
  filterable by date; lists every completed booking & walk-in with actual price.
- **Manage (owner)** — salon profile & photos, services (name/duration/price),
  staff, weekly working hours, and the **"Afficher les prix"** toggle.

Staff with a login see their own schedule, log their own walk-ins, and see their
own day's numbers; the owner sees the whole salon.

### Admin (web)
- **Salon approvals** — approve / reject pending salon-owner accounts.
- **Review moderation** — approve / reject pending reviews; see reported reviews
  and delete them.
- **Users & salons** — browse accounts; suspend a salon.
- *(Later)* subscription plans & platform stats.

## 7. Booking & Availability Logic (correctness-critical)

All availability and state transitions are decided **server-side** (Edge
Functions + DB constraints), never trusted from the client.

### Slot generation (salon + service + date)
- Start from each **rostered** (`staff_shifts = working`) staff member's hours,
  intersected with `working_hours`, minus break gaps.
- Slice into start times at a fixed **granularity** (e.g. 15 min) where a block of
  `service.duration_min` fits before the staff's end time.
- Remove starts overlapping that staff's `confirmed`, `completed`, or active
  **soft-held** bookings.
- **Specific coiffeur** → only that staff's free starts.
- **"Sans préférence"** → union of all rostered staff's free starts; person
  assigned at confirmation.
- Computed by an Edge Function / SQL view so all clients see the same truth.

### Soft-hold (prevents duplicate pending requests for one slot)
- On request, booking is created `pending` with `hold_expires_at = now + 15 min`
  (configurable).
- An unexpired `pending` hold blocks its interval in availability.
- A scheduled (cron) Edge Function expires lapsed holds: slot frees, customer is
  notified it lapsed.
- For "sans préférence", a hold reserves one unit of capacity at that time (blocks
  a slot only when no other staff remains free), avoiding over-blocking
  multi-staff salons.

### Confirm / decline (server-enforced)
- **Confirm** → Edge Function re-checks for conflicts, sets `confirmed`, assigns
  `staff_id` if needed, clears the hold, notifies the customer.
- **Decline** → `declined`, hold cleared, slot frees, customer notified.
- **Race guard** — a Postgres exclusion/overlap constraint guarantees no two
  `confirmed`/`completed` bookings overlap for the same `staff_id`; the database
  is the final arbiter.

### Completion, no-show, walk-ins
- Staff mark a confirmed booking **completed** (set/adjust `actual_price` → caisse)
  or **no-show**.
- Walk-ins are created directly as `completed`, `source = walkin`, against a
  rostered staff member, and block overlapping online slots going forward.

## 8. Notifications

- Each notable event writes a `notifications` row (in-app center) and sends an FCM
  push.
- Customer: request submitted, confirmed (with assigned coiffeur), declined, hold
  expired, appointment reminder.
- Salon: new request, customer cancelled.
- Admin: new salon awaiting approval, review reported.
- Sent from Edge Functions at each state transition. FCM tokens stored on
  `profiles`.

## 9. Security (Supabase Row-Level Security)

- **Customers**: read approved salons/services/staff/approved reviews; read/write
  only their own bookings, favorites, reviews, notifications.
- **Salon owner**: read/write only rows belonging to their salon.
- **Staff**: read their salon's schedule; write their own walk-ins/completions;
  see their own caisse numbers.
- **Admin**: elevated access for approvals, moderation, suspension.
- **Trusted transitions** (confirm booking, expire hold, recompute `rating_avg`)
  run in Edge Functions with the service role — never from the client. RLS is the
  backstop even against a tampered client.
- Pending/unapproved salons and unapproved reviews are invisible to customers via
  RLS.

## 10. Testing Strategy

Following **TDD**, especially for booking/availability/caisse logic.
- **Unit (Dart):** slot generation and soft-hold/overlap logic — table-driven
  cases: breaks, "sans préférence" union, hold blocking, durations that don't fit.
- **Database/RLS (pgTAP / Supabase tests):** overlap exclusion constraint rejects
  double-booking; RLS prevents cross-salon and cross-user access.
- **Edge Functions:** confirm-with-conflict loses gracefully; hold expiry frees
  slots; review approval flips visibility.
- **Widget (Flutter):** booking flow renders correct slots; caisse totals match
  seeded data.
- **Build verification:** `flutter analyze` + `flutter test` green; builds for web
  and Android.

## 11. Future / Anticipated Extensions

Online payment & deposits (Konnect / Flouci / Clictopay); SMS & phone-OTP;
Arabic + RTL and multi-language; map discovery; per-staff service lists;
commission auto-calculation; subscription/paid plans and analytics. The data model
and architecture are structured so each can be added incrementally.
