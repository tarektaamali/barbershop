import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../booking/data/booking_repository.dart';

class RequestsTab extends ConsumerWidget {
  const RequestsTab({required this.salonId, super.key});

  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pending = ref.watch(pendingBookingsProvider(salonId));

    return pending.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (items) {
        if (items.isEmpty) return Center(child: Text(l10n.noRequests));
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final b = items[i];
            return ListTile(
              title: Text(b.serviceName),
              subtitle: Text('${b.date} · ${b.startHm} – ${b.endHm}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      await ref.read(bookingRepositoryProvider).confirm(b.id);
                      ref.invalidate(pendingBookingsProvider(salonId));
                    },
                    child: Text(l10n.confirmButton),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref.read(bookingRepositoryProvider).decline(b.id);
                      ref.invalidate(pendingBookingsProvider(salonId));
                    },
                    child: Text(l10n.declineButton),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
