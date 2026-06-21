import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';

class StaffTab extends ConsumerWidget {
  const StaffTab({required this.salonId, super.key});

  final String salonId;

  Future<void> _openDialog(BuildContext context, WidgetRef ref,
      {Staff? existing}) async {
    final result = await showDialog<_StaffFormResult>(
      context: context,
      builder: (_) => _StaffDialog(existing: existing),
    );
    if (result == null) return;
    final repo = ref.read(staffRepositoryProvider);
    if (existing == null) {
      await repo.addStaff(
        salonId: salonId,
        displayName: result.displayName,
        specialty: result.specialty,
      );
    } else {
      await repo.updateStaff(
        id: existing.id,
        displayName: result.displayName,
        specialty: result.specialty,
      );
    }
    ref.invalidate(staffProvider(salonId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final staff = ref.watch(staffProvider(salonId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.addButton),
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noStaff));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = items[i];
              return ListTile(
                title: Text(s.displayName),
                subtitle: s.specialty == null ? null : Text(s.specialty!),
                onTap: () => _openDialog(context, ref, existing: s),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(staffRepositoryProvider)
                        .setActive(s.id, !s.active);
                    ref.invalidate(staffProvider(salonId));
                  },
                  child: Text(
                    s.active ? l10n.deactivateButton : l10n.activateButton,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StaffFormResult {
  _StaffFormResult(this.displayName, this.specialty);
  final String displayName;
  final String? specialty;
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog({this.existing});
  final Staff? existing;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.displayName ?? '');
  late final TextEditingController _specialty =
      TextEditingController(text: widget.existing?.specialty ?? '');

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(
          widget.existing == null ? l10n.addStaffTitle : l10n.editStaffTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('staffName'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.staffNameLabel),
          ),
          TextField(
            key: const Key('staffSpecialty'),
            controller: _specialty,
            decoration: InputDecoration(labelText: l10n.staffSpecialtyLabel),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _StaffFormResult(
              _name.text.trim(),
              _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
            ),
          ),
          child: Text(l10n.addButton),
        ),
      ],
    );
  }
}
