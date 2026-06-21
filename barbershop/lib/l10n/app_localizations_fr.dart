// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Barbershop';

  @override
  String get loginTitle => 'Connexion';

  @override
  String get signupTitle => 'Créer un compte';

  @override
  String get emailLabel => 'E-mail';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get fullNameLabel => 'Nom complet';

  @override
  String get signInButton => 'Se connecter';

  @override
  String get signUpButton => 'S\'inscrire';

  @override
  String get googleButton => 'Continuer avec Google';

  @override
  String get signOutButton => 'Se déconnecter';

  @override
  String get noAccountPrompt => 'Pas de compte ? Inscrivez-vous';

  @override
  String get haveAccountPrompt => 'Déjà un compte ? Connectez-vous';

  @override
  String get customerHomeTitle => 'Accueil';

  @override
  String get salonHomeTitle => 'Mon salon';

  @override
  String get adminHomeTitle => 'Administration';
}
