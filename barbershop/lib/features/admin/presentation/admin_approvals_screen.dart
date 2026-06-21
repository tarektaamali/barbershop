import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../salon/domain/salon.dart';
import '../data/admin_repository.dart';

class AdminApprovalsScreen extends ConsumerWidget {
  const AdminApprovalsScreen({super.key});

  Future<void> _set(WidgetRef ref, String id, SalonStatus status) async {
    await ref.read(adminRepositoryProvider).setStatus(id, status);
    ref.invalidate(pendingSalonsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pending = ref.watch(pendingSalonsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminApprovalsTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (salons) {
          if (salons.isEmpty) {
            return Center(child: Text(l10n.noPendingSalons));
          }
          return ListView.separated(
            itemCount: salons.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = salons[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Text(s.city),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _set(ref, s.id, SalonStatus.approved),
                      child: Text(l10n.approveButton),
                    ),
                    TextButton(
                      onPressed: () => _set(ref, s.id, SalonStatus.rejected),
                      child: Text(l10n.rejectButton),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
