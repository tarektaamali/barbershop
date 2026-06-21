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
