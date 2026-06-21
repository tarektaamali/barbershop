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
