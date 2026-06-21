import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/salon.dart';
import 'hours_tab.dart';
import 'salon_profile_form.dart';
import 'services_tab.dart';
import 'staff_tab.dart';

class SalonManageTabs extends StatelessWidget {
  const SalonManageTabs({required this.salon, super.key});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.tabProfile),
              Tab(text: l10n.tabServices),
              Tab(text: l10n.tabStaff),
              Tab(text: l10n.tabHours),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SalonProfileForm(salon: salon),
                ServicesTab(salonId: salon.id),
                StaffTab(salonId: salon.id),
                HoursTab(salonId: salon.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
