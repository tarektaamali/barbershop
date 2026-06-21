import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';

String bookingStatusLabel(AppLocalizations l10n, BookingStatus s) {
  switch (s) {
    case BookingStatus.pending:
      return l10n.statusPending;
    case BookingStatus.confirmed:
      return l10n.statusConfirmed;
    case BookingStatus.declined:
      return l10n.statusDeclined;
    case BookingStatus.cancelled:
      return l10n.statusCancelled;
    case BookingStatus.completed:
      return l10n.statusCompleted;
    case BookingStatus.noShow:
      return l10n.statusNoShow;
  }
}

class MyReservationsScreen extends ConsumerWidget {
  const MyReservationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bookings = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myReservationsTitle)),
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) return Center(child: Text(l10n.noReservations));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = items[i];
              final cancellable = b.status == BookingStatus.pending ||
                  b.status == BookingStatus.confirmed;
              return ListTile(
                title: Text(b.serviceName),
                subtitle: Text('${b.date} · ${b.startHm} – ${b.endHm}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bookingStatusLabel(l10n, b.status)),
                    if (cancellable)
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(bookingRepositoryProvider)
                              .cancel(b.id);
                          ref.invalidate(myBookingsProvider);
                        },
                        child: Text(l10n.cancelButton),
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
