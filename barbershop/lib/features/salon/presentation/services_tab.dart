import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/service_repository.dart';
import '../domain/service.dart';

class ServicesTab extends ConsumerWidget {
  const ServicesTab({required this.salonId, super.key});

  final String salonId;

  Future<void> _openDialog(BuildContext context, WidgetRef ref,
      {Service? existing}) async {
    final result = await showDialog<_ServiceFormResult>(
      context: context,
      builder: (_) => _ServiceDialog(existing: existing),
    );
    if (result == null) return;
    final repo = ref.read(serviceRepositoryProvider);
    if (existing == null) {
      await repo.addService(
        salonId: salonId,
        name: result.name,
        durationMin: result.durationMin,
        price: result.price,
      );
    } else {
      await repo.updateService(
        id: existing.id,
        name: result.name,
        durationMin: result.durationMin,
        price: result.price,
      );
    }
    ref.invalidate(servicesProvider(salonId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final services = ref.watch(servicesProvider(salonId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.addButton),
      ),
      body: services.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noServices));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = items[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Text(
                  '${s.durationMin} ${l10n.minutesSuffix} · ${s.price.toStringAsFixed(0)} DT',
                ),
                onTap: () => _openDialog(context, ref, existing: s),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(serviceRepositoryProvider)
                        .setActive(s.id, !s.active);
                    ref.invalidate(servicesProvider(salonId));
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

class _ServiceFormResult {
  _ServiceFormResult(this.name, this.durationMin, this.price);
  final String name;
  final int durationMin;
  final double price;
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({this.existing});
  final Service? existing;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _duration = TextEditingController(
      text: widget.existing?.durationMin.toString() ?? '');
  late final TextEditingController _price = TextEditingController(
      text: widget.existing?.price.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.existing == null
          ? l10n.addServiceTitle
          : l10n.editServiceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('serviceName'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.serviceNameLabel),
          ),
          TextField(
            key: const Key('serviceDuration'),
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.serviceDurationLabel),
          ),
          TextField(
            key: const Key('servicePrice'),
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.servicePriceLabel),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ServiceFormResult(
              _name.text.trim(),
              int.tryParse(_duration.text.trim()) ?? 0,
              double.tryParse(_price.text.trim()) ?? 0,
            ),
          ),
          child: Text(l10n.addButton),
        ),
      ],
    );
  }
}
