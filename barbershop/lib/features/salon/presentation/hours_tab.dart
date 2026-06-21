import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/staff_repository.dart';
import '../data/working_hours_repository.dart';
import '../domain/staff.dart';
import '../domain/working_hours.dart';

// Monday-first display order mapped to Postgres dow (0=Sun..6=Sat).
const _dayOrder = [1, 2, 3, 4, 5, 6, 0];

String _dayLabel(AppLocalizations l10n, int dow) {
  switch (dow) {
    case 1:
      return l10n.dayMon;
    case 2:
      return l10n.dayTue;
    case 3:
      return l10n.dayWed;
    case 4:
      return l10n.dayThu;
    case 5:
      return l10n.dayFri;
    case 6:
      return l10n.daySat;
    default:
      return l10n.daySun;
  }
}

class HoursTab extends ConsumerStatefulWidget {
  const HoursTab({required this.salonId, super.key});

  final String salonId;

  @override
  ConsumerState<HoursTab> createState() => _HoursTabState();
}

class _HoursTabState extends ConsumerState<HoursTab> {
  String? _staffId;

  Future<void> _addRange(int weekday) async {
    final staffId = _staffId;
    if (staffId == null) return;
    final range = await showDialog<_RangeResult>(
      context: context,
      builder: (_) => const _RangeDialog(),
    );
    if (range == null) return;
    await ref.read(workingHoursRepositoryProvider).addRange(
          staffId: staffId,
          weekday: weekday,
          start: range.start,
          end: range.end,
        );
    ref.invalidate(workingHoursProvider(staffId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final staffAsync = ref.watch(staffProvider(widget.salonId));

    return staffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (staff) {
        final active = staff.where((s) => s.active).toList();
        if (active.isEmpty) {
          return Center(child: Text(l10n.noStaffForHours));
        }
        final selected = _staffId ?? active.first.id;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                key: const Key('staffPicker'),
                initialValue: selected,
                decoration: InputDecoration(labelText: l10n.selectStaffLabel),
                items: [
                  for (final Staff s in active)
                    DropdownMenuItem(value: s.id, child: Text(s.displayName)),
                ],
                onChanged: (v) => setState(() => _staffId = v),
              ),
            ),
            Expanded(child: _HoursList(staffId: selected, onAdd: _addRange)),
          ],
        );
      },
    );
  }
}

class _HoursList extends ConsumerWidget {
  const _HoursList({required this.staffId, required this.onAdd});

  final String staffId;
  final void Function(int weekday) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hoursAsync = ref.watch(workingHoursProvider(staffId));

    return hoursAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (hours) {
        return ListView(
          children: [
            for (final dow in _dayOrder)
              _DaySection(
                label: _dayLabel(l10n, dow),
                ranges: hours.where((h) => h.weekday == dow).toList(),
                onAdd: () => onAdd(dow),
                onRemove: (id) async {
                  await ref
                      .read(workingHoursRepositoryProvider)
                      .deleteRange(id);
                  ref.invalidate(workingHoursProvider(staffId));
                },
              ),
          ],
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.label,
    required this.ranges,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final List<WorkingHours> ranges;
  final VoidCallback onAdd;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              IconButton(icon: const Icon(Icons.add), onPressed: onAdd),
            ],
          ),
          for (final r in ranges)
            ListTile(
              dense: true,
              title: Text('${r.startHm} – ${r.endHm}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onRemove(r.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeResult {
  _RangeResult(this.start, this.end);
  final String start;
  final String end;
}

class _RangeDialog extends StatefulWidget {
  const _RangeDialog();

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '17:00');

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.addRangeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('rangeStart'),
            controller: _start,
            decoration: InputDecoration(labelText: l10n.startTimeLabel),
          ),
          TextField(
            key: const Key('rangeEnd'),
            controller: _end,
            decoration: InputDecoration(labelText: l10n.endTimeLabel),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _RangeResult(_start.text.trim(), _end.text.trim()),
          ),
          child: Text(l10n.addButton),
        ),
      ],
    );
  }
}
