# Visual Discovery Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the plain salon list with a full-screen, swipeable **story-style discovery feed** (cover image + name/city/rating overlay, ♥ favorite, "Réserver"), a **salon profile** screen (cover, services, staff, rating, book), owner-editable **cover images**, a **favorites** list, and a simple **search filter**.

**Architecture:** Builds on Plans 1–5. Adds a `favorites` table + toggle RPC and a `set_salon_cover` owner RPC over the existing `salons.cover_url`. Flutter adds a vertical `PageView` feed, a salon profile screen, a favorites screen, and a cover-URL field on the salon profile form. Discovery reuses `approvedSalonsProvider`, `servicesProvider`, `staffProvider`; booking reuses Plan 5's `/book/:salonId`.

**Tech Stack:** Flutter 3.35, Dart 3.9, `supabase_flutter` v2, `flutter_riverpod` v3, `go_router` v17, `mocktail`, Supabase CLI + Docker (pgTAP).

## Global Constraints

Carried over from Plans 1–5 (verified against the codebase):

- **Riverpod 3.x:** `AsyncNotifier`/`AsyncNotifierProvider` (auto-dispose default). `AsyncValue.value` (no `valueOrNull`). The `Override` type is NOT importable by name — widget-test helpers take domain values and build `ProviderScope` overrides internally.
- **Localization:** strings in `lib/l10n/app_fr.arb`; run `flutter gen-l10n` **from `barbershop/`**; generated files committed; import `package:barbershop/l10n/app_localizations.dart`. No hardcoded UI text. French only.
- **RLS + RPC writes:** writes go through `SECURITY DEFINER` RPCs (`owns_salon()` / `auth.uid()` guards); tables enable RLS with `grant select` + a read policy. Stub `client.rpc(...)` in tests with `thenAnswer((_) => FakeFilterBuilder<dynamic>(value))` from `test/support/fake_postgrest.dart`. Query-chain fetch methods (`.from().select()...`) are not unit-tested (un-mockable builders); they are covered by the live e2e check.
- **Existing interfaces:** `Salon` (has `coverUrl`, `ratingAvg`), `salonRepositoryProvider`, `approvedSalonsProvider`, `updateMySalon(...)`, `SalonProfileForm` (Plan 2/3); `servicesProvider(salonId)`, `staffProvider(salonId)`; `/book/:salonId` route + `BookingScreen` (Plan 5); `currentProfileProvider`, `authRepositoryProvider`; customer home renders `BrowseSalonsScreen` (Plan 5) — this plan replaces that body with the feed.
- **TDD:** failing test first; commit after each green step.
- **Working dir:** Flutter from `barbershop/`; `supabase` from repo root.

---

## File Structure

```
barbershop/
├── lib/features/
│   ├── discovery/
│   │   ├── data/favorites_repository.dart        # toggle + my favorite ids
│   │   └── presentation/
│   │       ├── feed_screen.dart                    # vertical PageView story feed
│   │       ├── salon_profile_screen.dart           # cover + services + staff + book
│   │       └── favorites_screen.dart
│   ├── salon/
│   │   ├── data/salon_repository.dart              # MODIFY: setCover + fetchApprovedById
│   │   └── presentation/salon_profile_form.dart    # MODIFY: cover URL field
│   └── home/presentation/customer_home_screen.dart # MODIFY: body = FeedScreen + favorites action
├── lib/core/router/app_router.dart                 # MODIFY: /s/:salonId, /favorites
├── lib/l10n/app_fr.arb                              # MODIFY
└── supabase/
    ├── migrations/0006_favorites_cover.sql
    └── tests/favorites_test.sql
```

---

## Task 1: Favorites table + cover RPC (pgTAP)

**Files:**
- Create: `supabase/migrations/0006_favorites_cover.sql`, `supabase/tests/favorites_test.sql`

**Interfaces:**
- Produces:
  - table `public.favorites` (`customer_id`, `salon_id`, unique).
  - `public.toggle_favorite(p_salon_id uuid) returns boolean` (true if now favorited).
  - `public.set_salon_cover(p_cover_url text) returns void` (owner sets their salon's cover).

- [ ] **Step 1: Write the migration.** Create `supabase/migrations/0006_favorites_cover.sql`:

```sql
create table public.favorites (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users (id) on delete cascade,
  salon_id    uuid not null references public.salons (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (customer_id, salon_id)
);
create index favorites_customer_idx on public.favorites (customer_id);

alter table public.favorites enable row level security;
grant select on public.favorites to authenticated;

-- A customer sees only their own favorites.
create policy "favorites_select_own"
  on public.favorites for select
  using (customer_id = auth.uid());

-- Toggle a favorite for the current user; returns true if now favorited.
create function public.toggle_favorite(p_salon_id uuid)
  returns boolean language plpgsql security definer set search_path = public
as $$
declare v_deleted int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from public.favorites
    where customer_id = auth.uid() and salon_id = p_salon_id;
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then
    return false;
  end if;
  insert into public.favorites (customer_id, salon_id)
    values (auth.uid(), p_salon_id);
  return true;
end;
$$;

-- Owner sets their salon's cover image URL.
create function public.set_salon_cover(p_cover_url text)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.salons set cover_url = p_cover_url where owner_id = auth.uid();
end;
$$;

grant execute on function public.toggle_favorite(uuid) to authenticated;
grant execute on function public.set_salon_cover(text) to authenticated;
```

- [ ] **Step 2: Apply.** Run (repo root): `supabase db reset`. Expected: applies `0001`–`0006` cleanly.

- [ ] **Step 3: Write the failing pgTAP test.** Create `supabase/tests/favorites_test.sql`:

```sql
begin;
select plan(4);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev'),
  ('dddddddd-0000-0000-0000-000000000004', 'customer@test.dev');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.register_salon('Barber House', 'Tunis');
set local role postgres;
update public.salons set status = 'approved'
  where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- Owner sets a cover.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.set_salon_cover('https://example.com/cover.jpg');
set local role postgres;
select is(
  (select cover_url from public.salons limit 1),
  'https://example.com/cover.jpg',
  'owner sets the salon cover');

-- Customer toggles a favorite on, then off.
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}';
select is(
  public.toggle_favorite((select id from public.salons limit 1)),
  true,
  'first toggle favorites the salon');
select is(
  (select count(*)::int from public.favorites), 1,
  'favorite row created');
select is(
  public.toggle_favorite((select id from public.salons limit 1)),
  false,
  'second toggle un-favorites the salon');

select * from finish();
rollback;
```

- [ ] **Step 4: Run.** Run (repo root): `supabase test db`. Expected: `favorites_test.sql` passes all 4; existing suites still pass.

- [ ] **Step 5: Commit.**

```bash
git add supabase/migrations/0006_favorites_cover.sql supabase/tests/favorites_test.sql
git commit -m "feat(db): favorites table with toggle RPC and owner set_salon_cover"
```

---

## Task 2: Localization strings

**Files:** Modify `barbershop/lib/l10n/app_fr.arb`.

**Interfaces:** Produces: `feedTitle`, `favoritesTitle`, `searchHint`, `bookButton`, `noFavorites`, `salonProfileServices`, `salonProfileStaff`, `coverUrlLabel`, `reviewsCountLabel`.

- [ ] **Step 1: Add the strings.** In `barbershop/lib/l10n/app_fr.arb`, add before the closing brace (preceding line gets a comma):

```json
  "feedTitle": "Découvrir",
  "favoritesTitle": "Favoris",
  "searchHint": "Rechercher un salon ou une ville",
  "bookButton": "Réserver",
  "noFavorites": "Aucun favori",
  "salonProfileServices": "Services",
  "salonProfileStaff": "Équipe",
  "coverUrlLabel": "Photo de couverture (URL)",
  "reviewsCountLabel": "{count} avis",
  "@reviewsCountLabel": {
    "placeholders": { "count": { "type": "int" } }
  }
```

- [ ] **Step 2: Regenerate.** Run: `cd barbershop && flutter gen-l10n`. Expected: regenerates; no errors.

- [ ] **Step 3: Verify.** Run: `flutter analyze lib/l10n`. Expected: No issues found.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/l10n/
git commit -m "feat(l10n): discovery feed, profile, and favorites strings"
```

---

## Task 3: Repositories — cover, single salon, favorites

**Files:**
- Modify: `barbershop/lib/features/salon/data/salon_repository.dart`, `barbershop/test/features/salon/salon_repository_test.dart`
- Create: `barbershop/lib/features/discovery/data/favorites_repository.dart`, `barbershop/test/features/discovery/favorites_repository_test.dart`

**Interfaces:**
- Produces:
  - On `SalonRepository`: `Future<void> setCover(String url)` → `rpc('set_salon_cover', {'p_cover_url': url})`; `Future<Salon?> fetchApprovedById(String id)` → `from('salons').select().eq('id',id).eq('status','approved').maybeSingle()`.
  - `final approvedSalonByIdProvider = FutureProvider.family<Salon?, String>(...)`.
  - `class FavoritesRepository` with `Future<bool> toggle(String salonId)` → `rpc('toggle_favorite', ...)`; `Future<Set<String>> fetchMyIds()` → `from('favorites').select('salon_id')`.
  - `final favoritesRepositoryProvider`, `final favoriteSalonIdsProvider = FutureProvider<Set<String>>(...)`.

- [ ] **Step 1: Add a failing test for `setCover`.** In `barbershop/test/features/salon/salon_repository_test.dart`, add inside `main()`:

```dart
  test('setCover calls set_salon_cover RPC', () async {
    when(() => client.rpc('set_salon_cover', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.setCover('https://example.com/c.jpg');

    verify(() => client.rpc('set_salon_cover', params: {
          'p_cover_url': 'https://example.com/c.jpg',
        })).called(1);
  });
```

- [ ] **Step 2: Run it (RED).** Run: `cd barbershop && flutter test test/features/salon/salon_repository_test.dart`. Expected: FAIL — `setCover` not defined.

- [ ] **Step 3: Implement on `SalonRepository`.** In `barbershop/lib/features/salon/data/salon_repository.dart`, add inside the class:

```dart
  Future<void> setCover(String url) async {
    await _client.rpc('set_salon_cover', params: {'p_cover_url': url});
  }

  Future<Salon?> fetchApprovedById(String id) async {
    final row = await _client
        .from('salons')
        .select()
        .eq('id', id)
        .eq('status', 'approved')
        .maybeSingle();
    if (row == null) return null;
    return Salon.fromMap(row);
  }
```

And add at the bottom of the file:

```dart
final approvedSalonByIdProvider =
    FutureProvider.family<Salon?, String>((ref, id) async {
  return ref.watch(salonRepositoryProvider).fetchApprovedById(id);
});
```

- [ ] **Step 4: Run it (GREEN).** Run: `flutter test test/features/salon/salon_repository_test.dart`. Expected: PASS.

- [ ] **Step 5: Create the favorites repository + test.** Create `barbershop/test/features/discovery/favorites_repository_test.dart`:

```dart
import 'package:barbershop/features/discovery/data/favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late FavoritesRepository repo;

  setUp(() {
    client = _MockClient();
    repo = FavoritesRepository(client);
  });

  test('toggle calls toggle_favorite RPC and returns the new state', () async {
    when(() => client.rpc('toggle_favorite', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(true));

    final favorited = await repo.toggle('s1');

    expect(favorited, true);
    verify(() => client.rpc('toggle_favorite', params: {
          'p_salon_id': 's1',
        })).called(1);
  });
}
```

Then create `barbershop/lib/features/discovery/data/favorites_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class FavoritesRepository {
  FavoritesRepository(this._client);

  final SupabaseClient _client;

  Future<bool> toggle(String salonId) async {
    final result = await _client.rpc('toggle_favorite', params: {
      'p_salon_id': salonId,
    });
    return result as bool;
  }

  Future<Set<String>> fetchMyIds() async {
    final rows = await _client.from('favorites').select('salon_id');
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['salon_id'] as String)
        .toSet();
  }
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository(ref.watch(supabaseClientProvider));
});

final favoriteSalonIdsProvider = FutureProvider<Set<String>>((ref) async {
  return ref.watch(favoritesRepositoryProvider).fetchMyIds();
});
```

- [ ] **Step 6: Run the favorites test.** Run: `flutter test test/features/discovery/favorites_repository_test.dart`. Expected: PASS.

- [ ] **Step 7: Analyze + commit.**

```bash
flutter analyze lib/features/salon/data lib/features/discovery/data
git add barbershop/lib/features/salon/data/salon_repository.dart \
        barbershop/test/features/salon/salon_repository_test.dart \
        barbershop/lib/features/discovery/data/favorites_repository.dart \
        barbershop/test/features/discovery/favorites_repository_test.dart
git commit -m "feat(discovery): cover RPC, single-salon fetch, and favorites repository"
```

---

## Task 4: Cover-URL field on the salon profile form

**Files:**
- Modify: `barbershop/lib/features/salon/presentation/salon_profile_form.dart`

**Interfaces:** the owner's profile form gains a "Photo de couverture (URL)" field; on save it calls `setCover` alongside the existing `updateMySalon`, then refreshes `mySalonProvider`.

- [ ] **Step 1: Add the field + save call.** In `barbershop/lib/features/salon/presentation/salon_profile_form.dart`:

Add a controller initializer alongside the others:
```dart
  late final TextEditingController _cover =
      TextEditingController(text: widget.salon.coverUrl ?? '');
```
Dispose it in `dispose()`:
```dart
    _cover.dispose();
```
In `_save()`, after the `updateMySalon(...)` call and before `ref.invalidate(mySalonProvider)`, add:
```dart
      await ref.read(salonRepositoryProvider).setCover(_cover.text.trim());
```
Add the field to the `ListView` (after the address field, before the `SwitchListTile`):
```dart
        const SizedBox(height: 12),
        TextField(
          key: const Key('coverUrl'),
          controller: _cover,
          decoration: InputDecoration(labelText: l10n.coverUrlLabel),
        ),
```

- [ ] **Step 2: Verify the existing dashboard test still passes + analyze.**

Run: `cd barbershop && flutter test test/features/salon/salon_dashboard_screen_test.dart && flutter analyze lib/features/salon/presentation/salon_profile_form.dart`
Expected: PASS; analyzer clean.

- [ ] **Step 3: Commit.**

```bash
git add barbershop/lib/features/salon/presentation/salon_profile_form.dart
git commit -m "feat(salon): cover image URL field on the profile form"
```

---

## Task 5: Salon profile screen

**Files:**
- Create: `barbershop/lib/features/discovery/presentation/salon_profile_screen.dart`
- Test: `barbershop/test/features/discovery/salon_profile_screen_test.dart`

**Interfaces:**
- Consumes: `approvedSalonByIdProvider(salonId)`, `servicesProvider`, `staffProvider`, `favoriteSalonIdsProvider`, `favoritesRepositoryProvider`; `Salon`, `Service`, `Staff`.
- Produces: `class SalonProfileScreen extends ConsumerWidget` taking `salonId` — a cover header (image or gradient) with the name/city/rating, a ♥ favorite toggle, the services and staff lists, and a **Réserver** button → `/book/:salonId`.

- [ ] **Step 1: Create the screen.** Create `barbershop/lib/features/discovery/presentation/salon_profile_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../salon/data/salon_repository.dart';
import '../../salon/data/service_repository.dart';
import '../../salon/data/staff_repository.dart';
import '../../salon/domain/salon.dart';
import '../data/favorites_repository.dart';

class SalonProfileScreen extends ConsumerWidget {
  const SalonProfileScreen({required this.salonId, super.key});

  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final salonAsync = ref.watch(approvedSalonByIdProvider(salonId));

    return Scaffold(
      body: salonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (salon) {
          if (salon == null) {
            return const Center(child: Text('404'));
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(salon.name),
                  background: _Cover(salon: salon),
                ),
                actions: [_FavoriteButton(salonId: salonId)],
              ),
              SliverToBoxAdapter(child: _Body(salon: salon, l10n: l10n)),
            ],
          );
        },
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.salon});
  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (salon.coverUrl != null && salon.coverUrl!.isNotEmpty) {
      return Image.network(salon.coverUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _gradient(scheme));
    }
    return _gradient(scheme);
  }

  Widget _gradient(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.salonId});
  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(favoriteSalonIdsProvider).value ?? const <String>{};
    final isFav = ids.contains(salonId);
    return IconButton(
      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
      onPressed: () async {
        await ref.read(favoritesRepositoryProvider).toggle(salonId);
        ref.invalidate(favoriteSalonIdsProvider);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.salon, required this.l10n});
  final Salon salon;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider(salon.id));
    final staff = ref.watch(staffProvider(salon.id));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${salon.city} · ★ ${salon.ratingAvg.toStringAsFixed(1)}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/book/${salon.id}'),
            child: Text(l10n.bookButton),
          ),
          const Divider(height: 32),
          Text(l10n.salonProfileServices,
              style: Theme.of(context).textTheme.titleMedium),
          services.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(e.toString()),
            data: (items) => Column(
              children: [
                for (final s in items.where((s) => s.active))
                  ListTile(
                    dense: true,
                    title: Text(s.name),
                    trailing: salon.showPrices
                        ? Text('${s.price.toStringAsFixed(0)} DT')
                        : null,
                    subtitle:
                        Text('${s.durationMin} ${l10n.minutesSuffix}'),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text(l10n.salonProfileStaff,
              style: Theme.of(context).textTheme.titleMedium),
          staff.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(e.toString()),
            data: (items) => Column(
              children: [
                for (final s in items.where((s) => s.active))
                  ListTile(
                    dense: true,
                    title: Text(s.displayName),
                    subtitle: s.specialty == null ? null : Text(s.specialty!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Write a widget test.** Create `barbershop/test/features/discovery/salon_profile_screen_test.dart`:

```dart
import 'package:barbershop/features/discovery/data/favorites_repository.dart';
import 'package:barbershop/features/discovery/presentation/salon_profile_screen.dart';
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _salon = Salon(
  id: 's1',
  ownerId: 'u1',
  name: 'Barber House',
  city: 'Tunis',
  status: SalonStatus.approved,
  showPrices: true,
  ratingAvg: 4.5,
  ratingCount: 3,
);

void main() {
  testWidgets('shows the salon name, services heading, and book button',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          approvedSalonByIdProvider('s1').overrideWith((ref) async => _salon),
          servicesProvider('s1').overrideWith((ref) async => []),
          staffProvider('s1').overrideWith((ref) async => []),
          favoriteSalonIdsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: SalonProfileScreen(salonId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barber House'), findsOneWidget);
    expect(find.text('Réserver'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test.** Run: `cd barbershop && flutter test test/features/discovery/salon_profile_screen_test.dart`. Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/features/discovery/presentation/salon_profile_screen.dart barbershop/test/features/discovery/salon_profile_screen_test.dart
git commit -m "feat(discovery): salon profile screen with cover, services, staff, favorite"
```

---

## Task 6: Visual feed screen (vertical story-style PageView)

**Files:**
- Create: `barbershop/lib/features/discovery/presentation/feed_screen.dart`
- Test: `barbershop/test/features/discovery/feed_screen_test.dart`

**Interfaces:**
- Consumes: `approvedSalonsProvider`, `favoriteSalonIdsProvider`, `favoritesRepositoryProvider`; `Salon`.
- Produces: `class FeedScreen extends ConsumerStatefulWidget` — a search field that filters approved salons by name/city; below it a vertical `PageView` of full-bleed salon cards (cover or gradient, name/city/rating overlay, ♥ favorite, "Réserver" → `/s/:salonId`). Empty state shows `noSalons`.

- [ ] **Step 1: Create the feed.** Create `barbershop/lib/features/discovery/presentation/feed_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../salon/data/salon_repository.dart';
import '../../salon/domain/salon.dart';
import '../data/favorites_repository.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final salonsAsync = ref.watch(approvedSalonsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const Key('feedSearch'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: salonsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (all) {
              final salons = _query.isEmpty
                  ? all
                  : all
                      .where((s) =>
                          s.name.toLowerCase().contains(_query) ||
                          s.city.toLowerCase().contains(_query))
                      .toList();
              if (salons.isEmpty) return Center(child: Text(l10n.noSalons));
              return PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: salons.length,
                itemBuilder: (context, i) => _SalonCard(salon: salons[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SalonCard extends ConsumerWidget {
  const _SalonCard({required this.salon});
  final Salon salon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ids = ref.watch(favoriteSalonIdsProvider).value ?? const <String>{};
    final isFav = ids.contains(salon.id);

    final cover = (salon.coverUrl != null && salon.coverUrl!.isNotEmpty)
        ? Image.network(salon.coverUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradient(scheme))
        : _gradient(scheme);

    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: IconButton(
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                color: Colors.white),
            onPressed: () async {
              await ref.read(favoritesRepositoryProvider).toggle(salon.id);
              ref.invalidate(favoriteSalonIdsProvider);
            },
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(salon.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text('${salon.city} · ★ ${salon.ratingAvg.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/s/${salon.id}'),
                child: Text(l10n.bookButton),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gradient(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.tertiary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}
```

- [ ] **Step 2: Write a widget test.** Create `barbershop/test/features/discovery/feed_screen_test.dart`:

```dart
import 'package:barbershop/features/discovery/data/favorites_repository.dart';
import 'package:barbershop/features/discovery/presentation/feed_screen.dart';
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _salon = Salon(
  id: 's1',
  ownerId: 'u1',
  name: 'Barber House',
  city: 'Tunis',
  status: SalonStatus.approved,
  showPrices: true,
  ratingAvg: 4.5,
  ratingCount: 3,
);

void main() {
  testWidgets('shows a salon card with name and book button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          approvedSalonsProvider.overrideWith((ref) async => const [_salon]),
          favoriteSalonIdsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: Scaffold(body: FeedScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barber House'), findsOneWidget);
    expect(find.text('Réserver'), findsOneWidget);
    expect(find.byKey(const Key('feedSearch')), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test.** Run: `cd barbershop && flutter test test/features/discovery/feed_screen_test.dart`. Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/features/discovery/presentation/feed_screen.dart barbershop/test/features/discovery/feed_screen_test.dart
git commit -m "feat(discovery): vertical story-style salon feed with search and favorite"
```

---

## Task 7: Favorites screen, routing, and home wiring

**Files:**
- Create: `barbershop/lib/features/discovery/presentation/favorites_screen.dart`
- Modify: `barbershop/lib/core/router/app_router.dart`, `barbershop/lib/features/home/presentation/customer_home_screen.dart`
- Test: `barbershop/test/features/discovery/favorites_screen_test.dart`

**Interfaces:**
- Produces: `class FavoritesScreen extends ConsumerWidget` — the customer's favorite salons (filter `approvedSalonsProvider` by `favoriteSalonIdsProvider`), each tappable → `/s/:salonId`; routes `/s/:salonId` → `SalonProfileScreen`, `/favorites` → `FavoritesScreen`; the customer home body becomes `FeedScreen` with a favorites app-bar action.

- [ ] **Step 1: Create the favorites screen.** Create `barbershop/lib/features/discovery/presentation/favorites_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../salon/data/salon_repository.dart';
import '../data/favorites_repository.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final salonsAsync = ref.watch(approvedSalonsProvider);
    final ids = ref.watch(favoriteSalonIdsProvider).value ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesTitle)),
      body: salonsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (all) {
          final favs = all.where((s) => ids.contains(s.id)).toList();
          if (favs.isEmpty) return Center(child: Text(l10n.noFavorites));
          return ListView.separated(
            itemCount: favs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = favs[i];
              return ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: Text(s.name),
                subtitle: Text(s.city),
                onTap: () => context.go('/s/${s.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Add routes.** In `barbershop/lib/core/router/app_router.dart`, add imports:

```dart
import '../../features/discovery/presentation/favorites_screen.dart';
import '../../features/discovery/presentation/salon_profile_screen.dart';
```

Add routes after the `/book/:salonId` route:

```dart
      GoRoute(
        path: '/s/:salonId',
        builder: (_, state) =>
            SalonProfileScreen(salonId: state.pathParameters['salonId']!),
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, __) => const FavoritesScreen(),
      ),
```

- [ ] **Step 3: Make the home body the feed + add a favorites action.** In `barbershop/lib/features/home/presentation/customer_home_screen.dart`, replace the `import '../../salon/presentation/browse_salons_screen.dart';` with `import '../../discovery/presentation/feed_screen.dart';`, change the title to `l10n.feedTitle`, change `body: const BrowseSalonsScreen()` to `body: const FeedScreen()`, and add a favorites `IconButton` as the first app-bar action:

```dart
          IconButton(
            tooltip: l10n.favoritesTitle,
            icon: const Icon(Icons.favorite_border),
            onPressed: () => context.go('/favorites'),
          ),
```

(`BrowseSalonsScreen` is now unused; delete `lib/features/salon/presentation/browse_salons_screen.dart`.)

- [ ] **Step 4: Write a favorites widget test.** Create `barbershop/test/features/discovery/favorites_screen_test.dart`:

```dart
import 'package:barbershop/features/discovery/data/favorites_repository.dart';
import 'package:barbershop/features/discovery/presentation/favorites_screen.dart';
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _salon = Salon(
  id: 's1',
  ownerId: 'u1',
  name: 'Barber House',
  city: 'Tunis',
  status: SalonStatus.approved,
  showPrices: true,
  ratingAvg: 4.5,
  ratingCount: 3,
);

void main() {
  testWidgets('lists only favorited salons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          approvedSalonsProvider.overrideWith((ref) async => const [_salon]),
          favoriteSalonIdsProvider.overrideWith((ref) async => {'s1'}),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: FavoritesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barber House'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Full analyze + suite.**

Run: `cd barbershop && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass (Plans 1–6).

- [ ] **Step 6: Commit.**

```bash
git add barbershop/lib/features/discovery/presentation/favorites_screen.dart \
        barbershop/lib/core/router/app_router.dart \
        barbershop/lib/features/home/presentation/customer_home_screen.dart \
        barbershop/test/features/discovery/favorites_screen_test.dart
git rm barbershop/lib/features/salon/presentation/browse_salons_screen.dart
git commit -m "feat(discovery): favorites screen, profile/favorites routes, feed home"
```

---

## Task 8: End-to-end verification

**Files:** none (verification + README).

- [ ] **Step 1: Full analyzer + suite.** Run: `cd barbershop && flutter analyze && flutter test`. Expected: clean; all pass. Note totals.

- [ ] **Step 2: pgTAP.** Run (repo root): `supabase test db`. Expected: all six suites pass.

- [ ] **Step 3: Web build.**

Run:
```bash
cd barbershop && flutter build web \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local publishable key>
```
Expected: `✓ Built build/web`.

- [ ] **Step 4: Live check.** As an owner set a cover; as a customer toggle a favorite and read it back.

```bash
KEY="<local publishable key>"
OEMAIL="owner_$(date +%s)@test.dev"
OTOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" -H "apikey: $KEY" -H "Content-Type: application/json" -d "{\"email\":\"$OEMAIL\",\"password\":\"secret123\"}" | jq -r '.access_token')
SALON=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/register_salon" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d '{"p_name":"E2E Salon","p_city":"Tunis"}' | tr -d '"')
CID=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -1)
docker exec -i "$CID" psql -U postgres -d postgres -c "update public.salons set status='approved' where id='$SALON';" >/dev/null
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/set_salon_cover" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d '{"p_cover_url":"https://example.com/c.jpg"}' >/dev/null
CEMAIL="cust_$(date +%s)@test.dev"
CTOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" -H "apikey: $KEY" -H "Content-Type: application/json" -d "{\"email\":\"$CEMAIL\",\"password\":\"secret123\"}" | jq -r '.access_token')
echo "toggle favorite (expect true):"
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/toggle_favorite" -H "apikey: $KEY" -H "Authorization: Bearer $CTOKEN" -H "Content-Type: application/json" -d "{\"p_salon_id\":\"$SALON\"}"; echo
docker exec -i "$CID" psql -U postgres -d postgres -c "select cover_url from public.salons where id='$SALON'; select count(*) from public.favorites;"
```
Expected: toggle returns `true`; the salon shows the cover URL; one favorite row.

- [ ] **Step 5: README + commit.** Append a "Discovery feed (Plan 6)" section to `barbershop/README.md` (feed, profile, favorites, cover images, search), then:

```bash
git add barbershop/README.md
git commit -m "docs: visual discovery feed"
```

---

## Self-Review

**Spec coverage (design §6 customer discovery):**
- Visual story-style feed (full-bleed cards, swipe) replacing the plain list → Task 6. ✓
- Search/filter affordance (by name/city) → Task 6. ✓
- Salon profile (cover, services, staff, rating, Réserver) → Task 5. ✓
- ♥ favorites (toggle on feed/profile, favorites list) → Tasks 1, 3, 5, 6, 7. ✓
- Owner-set cover image → Tasks 1, 3, 4. ✓
- Prices shown only when `show_prices` → Task 5 (`salon.showPrices`). ✓
- Localization-ready, French, no hardcoded text → Task 2. ✓
- *Deferred (correct):* push/in-app notifications (Plan 7); real image upload via Supabase Storage + multi-photo `salon_media` galleries/stories (this plan uses a single owner-provided `cover_url` with a gradient fallback); reviews shown on the profile (reviews plan).

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands show expected output. The one file removal (`browse_salons_screen.dart`, now replaced by the feed) is explicit in Task 7. ✓

**Type consistency:** RPC names/params match between Dart and SQL: `toggle_favorite(p_salon_id)`, `set_salon_cover(p_cover_url)`. `favoriteSalonIdsProvider` (Set<String>) consumed by feed/profile/favorites. `approvedSalonByIdProvider(id)` defined in Task 3, consumed in Task 5. Feed → `/s/:salonId` (profile) → `/book/:salonId` (Plan 5 booking). `Salon.coverUrl`/`showPrices`/`ratingAvg` reused. `FakeFilterBuilder` reused for RPC stubs. ✓
