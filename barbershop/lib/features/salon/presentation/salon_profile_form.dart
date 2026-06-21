import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';

class SalonProfileForm extends ConsumerStatefulWidget {
  const SalonProfileForm({required this.salon, super.key});

  final Salon salon;

  @override
  ConsumerState<SalonProfileForm> createState() => _SalonProfileFormState();
}

class _SalonProfileFormState extends ConsumerState<SalonProfileForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.salon.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.salon.description ?? '');
  late final TextEditingController _city =
      TextEditingController(text: widget.salon.city);
  late final TextEditingController _address =
      TextEditingController(text: widget.salon.address ?? '');
  late final TextEditingController _cover =
      TextEditingController(text: widget.salon.coverUrl ?? '');
  late bool _showPrices = widget.salon.showPrices;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _address.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(salonRepositoryProvider).updateMySalon(
            name: _name.text.trim(),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            city: _city.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            showPrices: _showPrices,
          );
      await ref.read(salonRepositoryProvider).setCover(_cover.text.trim());
      ref.invalidate(mySalonProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          key: const Key('profileName'),
          controller: _name,
          decoration: InputDecoration(labelText: l10n.salonNameLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          decoration: InputDecoration(labelText: l10n.salonCityLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          decoration: InputDecoration(labelText: l10n.salonDescriptionLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('coverUrl'),
          controller: _cover,
          decoration: InputDecoration(labelText: l10n.coverUrlLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          decoration: InputDecoration(labelText: l10n.salonAddressLabel),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('showPricesSwitch'),
          title: Text(l10n.showPricesLabel),
          value: _showPrices,
          onChanged: (v) => setState(() => _showPrices = v),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
