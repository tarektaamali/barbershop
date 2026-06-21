import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('fr')];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'Barbershop'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get loginTitle;

  /// No description provided for @signupTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get signupTitle;

  /// No description provided for @emailLabel.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get passwordLabel;

  /// No description provided for @fullNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom complet'**
  String get fullNameLabel;

  /// No description provided for @signInButton.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get signInButton;

  /// No description provided for @signUpButton.
  ///
  /// In fr, this message translates to:
  /// **'S\'inscrire'**
  String get signUpButton;

  /// No description provided for @googleButton.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec Google'**
  String get googleButton;

  /// No description provided for @signOutButton.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOutButton;

  /// No description provided for @noAccountPrompt.
  ///
  /// In fr, this message translates to:
  /// **'Pas de compte ? Inscrivez-vous'**
  String get noAccountPrompt;

  /// No description provided for @haveAccountPrompt.
  ///
  /// In fr, this message translates to:
  /// **'Déjà un compte ? Connectez-vous'**
  String get haveAccountPrompt;

  /// No description provided for @customerHomeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get customerHomeTitle;

  /// No description provided for @salonHomeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mon salon'**
  String get salonHomeTitle;

  /// No description provided for @adminHomeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Administration'**
  String get adminHomeTitle;

  /// No description provided for @registerSalonButton.
  ///
  /// In fr, this message translates to:
  /// **'Inscrire mon salon'**
  String get registerSalonButton;

  /// No description provided for @salonRegistrationTitle.
  ///
  /// In fr, this message translates to:
  /// **'Inscription du salon'**
  String get salonRegistrationTitle;

  /// No description provided for @salonNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du salon'**
  String get salonNameLabel;

  /// No description provided for @salonCityLabel.
  ///
  /// In fr, this message translates to:
  /// **'Ville'**
  String get salonCityLabel;

  /// No description provided for @salonDescriptionLabel.
  ///
  /// In fr, this message translates to:
  /// **'Description'**
  String get salonDescriptionLabel;

  /// No description provided for @salonAddressLabel.
  ///
  /// In fr, this message translates to:
  /// **'Adresse'**
  String get salonAddressLabel;

  /// No description provided for @submitButton.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get submitButton;

  /// No description provided for @saveButton.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get saveButton;

  /// No description provided for @showPricesLabel.
  ///
  /// In fr, this message translates to:
  /// **'Afficher les prix'**
  String get showPricesLabel;

  /// No description provided for @pendingApprovalTitle.
  ///
  /// In fr, this message translates to:
  /// **'En attente de validation'**
  String get pendingApprovalTitle;

  /// No description provided for @pendingApprovalBody.
  ///
  /// In fr, this message translates to:
  /// **'Votre salon est en cours de validation par l\'administrateur.'**
  String get pendingApprovalBody;

  /// No description provided for @rejectedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Inscription refusée'**
  String get rejectedTitle;

  /// No description provided for @suspendedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Salon suspendu'**
  String get suspendedTitle;

  /// No description provided for @salonProfileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Profil du salon'**
  String get salonProfileTitle;

  /// No description provided for @adminApprovalsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Salons à valider'**
  String get adminApprovalsTitle;

  /// No description provided for @noPendingSalons.
  ///
  /// In fr, this message translates to:
  /// **'Aucun salon en attente'**
  String get noPendingSalons;

  /// No description provided for @approveButton.
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get approveButton;

  /// No description provided for @rejectButton.
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get rejectButton;

  /// No description provided for @tabProfile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get tabProfile;

  /// No description provided for @tabServices.
  ///
  /// In fr, this message translates to:
  /// **'Services'**
  String get tabServices;

  /// No description provided for @tabStaff.
  ///
  /// In fr, this message translates to:
  /// **'Équipe'**
  String get tabStaff;

  /// No description provided for @addServiceTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un service'**
  String get addServiceTitle;

  /// No description provided for @editServiceTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le service'**
  String get editServiceTitle;

  /// No description provided for @serviceNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du service'**
  String get serviceNameLabel;

  /// No description provided for @serviceDurationLabel.
  ///
  /// In fr, this message translates to:
  /// **'Durée (min)'**
  String get serviceDurationLabel;

  /// No description provided for @servicePriceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Prix (DT)'**
  String get servicePriceLabel;

  /// No description provided for @addStaffTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un coiffeur'**
  String get addStaffTitle;

  /// No description provided for @editStaffTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le coiffeur'**
  String get editStaffTitle;

  /// No description provided for @staffNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get staffNameLabel;

  /// No description provided for @staffSpecialtyLabel.
  ///
  /// In fr, this message translates to:
  /// **'Spécialité'**
  String get staffSpecialtyLabel;

  /// No description provided for @noServices.
  ///
  /// In fr, this message translates to:
  /// **'Aucun service'**
  String get noServices;

  /// No description provided for @noStaff.
  ///
  /// In fr, this message translates to:
  /// **'Aucun coiffeur'**
  String get noStaff;

  /// No description provided for @addButton.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get addButton;

  /// No description provided for @deactivateButton.
  ///
  /// In fr, this message translates to:
  /// **'Désactiver'**
  String get deactivateButton;

  /// No description provided for @activateButton.
  ///
  /// In fr, this message translates to:
  /// **'Activer'**
  String get activateButton;

  /// No description provided for @minutesSuffix.
  ///
  /// In fr, this message translates to:
  /// **'min'**
  String get minutesSuffix;

  /// No description provided for @tabHours.
  ///
  /// In fr, this message translates to:
  /// **'Horaires'**
  String get tabHours;

  /// No description provided for @selectStaffLabel.
  ///
  /// In fr, this message translates to:
  /// **'Coiffeur'**
  String get selectStaffLabel;

  /// No description provided for @noStaffForHours.
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez d\'abord un coiffeur'**
  String get noStaffForHours;

  /// No description provided for @addRangeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une plage'**
  String get addRangeTitle;

  /// No description provided for @startTimeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Début'**
  String get startTimeLabel;

  /// No description provided for @endTimeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Fin'**
  String get endTimeLabel;

  /// No description provided for @noHours.
  ///
  /// In fr, this message translates to:
  /// **'Aucune plage horaire'**
  String get noHours;

  /// No description provided for @removeButton.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get removeButton;

  /// No description provided for @dayMon.
  ///
  /// In fr, this message translates to:
  /// **'Lundi'**
  String get dayMon;

  /// No description provided for @dayTue.
  ///
  /// In fr, this message translates to:
  /// **'Mardi'**
  String get dayTue;

  /// No description provided for @dayWed.
  ///
  /// In fr, this message translates to:
  /// **'Mercredi'**
  String get dayWed;

  /// No description provided for @dayThu.
  ///
  /// In fr, this message translates to:
  /// **'Jeudi'**
  String get dayThu;

  /// No description provided for @dayFri.
  ///
  /// In fr, this message translates to:
  /// **'Vendredi'**
  String get dayFri;

  /// No description provided for @daySat.
  ///
  /// In fr, this message translates to:
  /// **'Samedi'**
  String get daySat;

  /// No description provided for @daySun.
  ///
  /// In fr, this message translates to:
  /// **'Dimanche'**
  String get daySun;

  /// No description provided for @browseSalonsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Salons'**
  String get browseSalonsTitle;

  /// No description provided for @myReservationsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes réservations'**
  String get myReservationsTitle;

  /// No description provided for @noSalons.
  ///
  /// In fr, this message translates to:
  /// **'Aucun salon disponible'**
  String get noSalons;

  /// No description provided for @noReservations.
  ///
  /// In fr, this message translates to:
  /// **'Aucune réservation'**
  String get noReservations;

  /// No description provided for @bookTitle.
  ///
  /// In fr, this message translates to:
  /// **'Réserver'**
  String get bookTitle;

  /// No description provided for @chooseServiceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Service'**
  String get chooseServiceLabel;

  /// No description provided for @chooseStaffLabel.
  ///
  /// In fr, this message translates to:
  /// **'Coiffeur'**
  String get chooseStaffLabel;

  /// No description provided for @noPreference.
  ///
  /// In fr, this message translates to:
  /// **'Sans préférence'**
  String get noPreference;

  /// No description provided for @chooseDateLabel.
  ///
  /// In fr, this message translates to:
  /// **'Date'**
  String get chooseDateLabel;

  /// No description provided for @chooseSlotLabel.
  ///
  /// In fr, this message translates to:
  /// **'Créneau'**
  String get chooseSlotLabel;

  /// No description provided for @noSlots.
  ///
  /// In fr, this message translates to:
  /// **'Aucun créneau disponible'**
  String get noSlots;

  /// No description provided for @requestSlotButton.
  ///
  /// In fr, this message translates to:
  /// **'Demander ce créneau'**
  String get requestSlotButton;

  /// No description provided for @requestSentTitle.
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée'**
  String get requestSentTitle;

  /// No description provided for @requestSentBody.
  ///
  /// In fr, this message translates to:
  /// **'En attente de confirmation du salon.'**
  String get requestSentBody;

  /// No description provided for @cancelButton.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancelButton;

  /// No description provided for @tabRequests.
  ///
  /// In fr, this message translates to:
  /// **'Demandes'**
  String get tabRequests;

  /// No description provided for @noRequests.
  ///
  /// In fr, this message translates to:
  /// **'Aucune demande'**
  String get noRequests;

  /// No description provided for @confirmButton.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get confirmButton;

  /// No description provided for @declineButton.
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get declineButton;

  /// No description provided for @statusPending.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get statusPending;

  /// No description provided for @statusConfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Confirmée'**
  String get statusConfirmed;

  /// No description provided for @statusDeclined.
  ///
  /// In fr, this message translates to:
  /// **'Refusée'**
  String get statusDeclined;

  /// No description provided for @statusCancelled.
  ///
  /// In fr, this message translates to:
  /// **'Annulée'**
  String get statusCancelled;

  /// No description provided for @statusCompleted.
  ///
  /// In fr, this message translates to:
  /// **'Terminée'**
  String get statusCompleted;

  /// No description provided for @statusNoShow.
  ///
  /// In fr, this message translates to:
  /// **'Absence'**
  String get statusNoShow;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
