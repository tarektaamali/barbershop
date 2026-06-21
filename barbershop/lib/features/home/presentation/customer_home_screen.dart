import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../discovery/presentation/feed_screen.dart';

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedTitle),
        actions: [
          IconButton(
            tooltip: l10n.favoritesTitle,
            icon: const Icon(Icons.favorite_border),
            onPressed: () => context.go('/favorites'),
          ),
          IconButton(
            tooltip: l10n.myReservationsTitle,
            icon: const Icon(Icons.event_note),
            onPressed: () => context.go('/reservations'),
          ),
          IconButton(
            tooltip: l10n.registerSalonButton,
            icon: const Icon(Icons.add_business),
            onPressed: () => context.go('/salon/register'),
          ),
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: const FeedScreen(),
    );
  }
}
