import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';
import 'salon_profile_form.dart';

class SalonDashboardScreen extends ConsumerWidget {
  const SalonDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final salonAsync = ref.watch(mySalonProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.salonHomeTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: salonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (salon) {
          if (salon == null) {
            return Center(child: Text(l10n.pendingApprovalBody));
          }
          switch (salon.status) {
            case SalonStatus.approved:
              return SalonProfileForm(salon: salon);
            case SalonStatus.pending:
              return _Banner(
                icon: Icons.hourglass_top,
                title: l10n.pendingApprovalTitle,
                body: l10n.pendingApprovalBody,
              );
            case SalonStatus.rejected:
              return _Banner(
                icon: Icons.cancel,
                title: l10n.rejectedTitle,
                body: l10n.pendingApprovalBody,
              );
            case SalonStatus.suspended:
              return _Banner(
                icon: Icons.pause_circle,
                title: l10n.suspendedTitle,
                body: l10n.pendingApprovalBody,
              );
          }
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
