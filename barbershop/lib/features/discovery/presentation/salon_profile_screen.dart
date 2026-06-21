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
                    subtitle: Text('${s.durationMin} ${l10n.minutesSuffix}'),
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
