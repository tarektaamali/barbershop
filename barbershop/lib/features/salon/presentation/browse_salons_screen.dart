import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../data/salon_repository.dart';

class BrowseSalonsScreen extends ConsumerWidget {
  const BrowseSalonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final salons = ref.watch(approvedSalonsProvider);
    return salons.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (items) {
        if (items.isEmpty) return Center(child: Text(l10n.noSalons));
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = items[i];
            return ListTile(
              title: Text(s.name),
              subtitle: Text(s.city),
              trailing: Text('★ ${s.ratingAvg.toStringAsFixed(1)}'),
              onTap: () => context.go('/book/${s.id}'),
            );
          },
        );
      },
    );
  }
}
