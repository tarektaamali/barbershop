import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'salon_registration_controller.dart';

class SalonRegistrationScreen extends ConsumerStatefulWidget {
  const SalonRegistrationScreen({super.key});

  @override
  ConsumerState<SalonRegistrationScreen> createState() =>
      _SalonRegistrationScreenState();
}

class _SalonRegistrationScreenState
    extends ConsumerState<SalonRegistrationScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _description.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(salonRegistrationControllerProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.salonRegistrationTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const Key('salonName'),
                controller: _name,
                decoration: InputDecoration(labelText: l10n.salonNameLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('salonCity'),
                controller: _city,
                decoration: InputDecoration(labelText: l10n.salonCityLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('salonDescription'),
                controller: _description,
                decoration:
                    InputDecoration(labelText: l10n.salonDescriptionLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('salonAddress'),
                controller: _address,
                decoration: InputDecoration(labelText: l10n.salonAddressLabel),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => ref
                        .read(salonRegistrationControllerProvider.notifier)
                        .submit(
                          name: _name.text.trim(),
                          city: _city.text.trim(),
                          description: _description.text.trim().isEmpty
                              ? null
                              : _description.text.trim(),
                          address: _address.text.trim().isEmpty
                              ? null
                              : _address.text.trim(),
                        ),
                child: Text(l10n.submitButton),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.error.toString(),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
