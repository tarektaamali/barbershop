import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../salon/data/availability_repository.dart';
import '../../salon/data/service_repository.dart';
import '../../salon/data/staff_repository.dart';
import 'booking_controller.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({required this.salonId, super.key});

  final String salonId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String? _serviceId;
  String? _staffId; // null => sans préférence
  DateTime _date = DateTime(2026, 6, 22);
  List<String> _slots = [];
  bool _loadingSlots = false;

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _loadSlots() async {
    final serviceId = _serviceId;
    if (serviceId == null) return;
    setState(() => _loadingSlots = true);
    final slots = await ref.read(availabilityRepositoryProvider).availableSlots(
          salonId: widget.salonId,
          serviceId: serviceId,
          date: _dateStr,
          staffId: _staffId,
        );
    if (mounted) {
      setState(() {
        _slots = slots;
        _loadingSlots = false;
      });
    }
  }

  Future<void> _request(String slot) async {
    final serviceId = _serviceId;
    if (serviceId == null) return;
    await ref.read(bookingControllerProvider.notifier).requestSlot(
          salonId: widget.salonId,
          serviceId: serviceId,
          date: _dateStr,
          startTime: slot,
          staffId: _staffId,
        );
    final state = ref.read(bookingControllerProvider);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (state.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error.toString())),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.requestSentTitle),
          content: Text(l10n.requestSentBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _loadSlots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final services = ref.watch(servicesProvider(widget.salonId));
    final staff = ref.watch(staffProvider(widget.salonId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.bookTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          services.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(e.toString()),
            data: (items) {
              final active = items.where((s) => s.active).toList();
              return DropdownButtonFormField<String>(
                key: const Key('servicePicker'),
                initialValue: _serviceId,
                decoration: InputDecoration(labelText: l10n.chooseServiceLabel),
                items: [
                  for (final s in active)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                          '${s.name} · ${s.durationMin} ${l10n.minutesSuffix}'),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _serviceId = v);
                  _loadSlots();
                },
              );
            },
          ),
          const SizedBox(height: 12),
          staff.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text(e.toString()),
            data: (items) {
              final active = items.where((s) => s.active).toList();
              return DropdownButtonFormField<String?>(
                key: const Key('staffPicker'),
                initialValue: _staffId,
                decoration: InputDecoration(labelText: l10n.chooseStaffLabel),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.noPreference)),
                  for (final s in active)
                    DropdownMenuItem(value: s.id, child: Text(s.displayName)),
                ],
                onChanged: (v) {
                  setState(() => _staffId = v);
                  _loadSlots();
                },
              );
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('datePicker'),
            title: Text(l10n.chooseDateLabel),
            subtitle: Text(_dateStr),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime(2027, 12, 31),
              );
              if (picked != null) {
                setState(() => _date = picked);
                _loadSlots();
              }
            },
          ),
          const Divider(),
          Text(l10n.chooseSlotLabel,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_loadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (_serviceId == null)
            const SizedBox.shrink()
          else if (_slots.isEmpty)
            Text(l10n.noSlots)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots)
                  OutlinedButton(
                    onPressed: () => _request(slot),
                    child: Text(slot),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
