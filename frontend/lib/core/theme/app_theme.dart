/// Système de design de l'application SGSUS.
///
/// Ce fichier est la source unique des couleurs, rayons, ombres, points de
/// rupture et du thème Material 3. Les écrans et composants ne définissent
/// pas leurs propres couleurs : ils utilisent [AppColors] et [AppTheme], ce
/// qui garantit une interface cohérente et facile à faire évoluer.
///
/// Charte graphique : encre (bleu-noir profond), or et blanc, complétés par
/// une gamme de gris « ardoise » pour les textes secondaires et bordures.
library;

import 'package:material_ui/material_ui.dart';

/// Palette de couleurs de l'application.
abstract final class AppColors {
  // --- Couleurs de marque -------------------------------------------------

  /// Encre : texte principal, barre latérale, éléments sélectionnés.
  static const ink = Color(0xFF0F172A);

  /// Encre adoucie : surfaces sombres secondaires (survol, infobulles).
  static const inkSoft = Color(0xFF1E293B);

  /// Or : couleur d'accent (boutons principaux, éléments actifs).
  static const gold = Color(0xFFC9A227);

  /// Or très clair : fonds d'icônes et de badges d'accent.
  static const goldSoft = Color(0xFFFBF4DF);

  // --- Neutres ----------------------------------------------------------------

  /// Blanc pur : cartes, champs de saisie, barre supérieure.
  static const white = Colors.white;

  /// Fond général des pages (gris très clair légèrement bleuté).
  static const bg = Color(0xFFF4F6FA);

  /// Fond alternatif discret (en-têtes de tableau, cellules hors mois).
  static const surfaceAlt = Color(0xFFF8FAFC);

  /// Texte secondaire (sous-titres, libellés).
  static const grey = Color(0xFF64748B);

  /// Texte tertiaire (indications, icônes discrètes).
  static const greyLight = Color(0xFF94A3B8);

  /// Bordures et séparateurs.
  static const line = Color(0xFFE2E8F0);

  // --- Couleurs sémantiques (texte / fond associé) -------------------------

  /// Succès : validé, disponible, confirmé.
  static const success = Color(0xFF15803D);
  static const successBg = Color(0xFFEAF7EF);

  /// Avertissement : en attente, occupé.
  static const warning = Color(0xFFB45309);
  static const warningBg = Color(0xFFFFF4E0);

  /// Danger : erreur, conflit, refus.
  static const danger = Color(0xFFB91C1C);
  static const dangerBg = Color(0xFFFDECEC);

  /// Information : éléments neutres mis en valeur.
  static const info = Color(0xFF1D4ED8);
  static const infoBg = Color(0xFFEAF0FF);

  /// Fond neutre (badges gris, états vides).
  static const neutralBg = Color(0xFFF1F5F9);

  // --- Barre latérale sombre ---------------------------------------------------

  /// Fond d'un élément de navigation actif ou survolé.
  static const sidebarActive = Color(0xFF1E293B);

  /// Texte et icônes de navigation inactifs.
  static const sidebarText = Color(0xFFCBD5E1);

  /// Texte discret de la barre latérale (titres de section).
  static const sidebarMuted = Color(0xFF64748B);

  /// Séparateurs de la barre latérale.
  static const sidebarLine = Color(0xFF1E293B);
}

/// Seuils de largeur (en pixels logiques) pour la mise en page adaptative.
abstract final class AppBreakpoints {
  /// En dessous : téléphone (une colonne, menu en tiroir).
  static const double compact = 600;

  /// En dessous : tablette portrait (rail de navigation réduit au-delà).
  static const double medium = 840;

  /// Au-delà : grand écran (barre latérale complète).
  static const double expanded = 1100;
}

/// Constantes de forme et thème Material de l'application.
abstract final class AppTheme {
  /// Rayon des cartes et grands conteneurs.
  static const double radius = 16;

  /// Rayon des champs, boutons et petits éléments.
  static const double radiusSmall = 10;

  /// Dégradé doré utilisé pour le logo et les pastilles de marque.
  static const LinearGradient goldLine = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD9B44A), Color(0xFFB8901C)],
  );

  /// Dégradé sombre des bandeaux d'accueil et en-têtes de fiche.
  static const LinearGradient inkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
  );

  /// Ombre douce des cartes : diffuse et très légère (aspect « flottant »).
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  /// Thème clair Material 3 de l'application.
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.gold,
        primary: AppColors.ink,
        secondary: AppColors.gold,
        surface: AppColors.white,
        error: AppColors.danger,
      ),
    );

    // Hiérarchie typographique : titres serrés et contrastés, corps aéré.
    final textTheme = base.textTheme
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
        )
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      // Indicateurs de chargement aux couleurs de la marque.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
        linearTrackColor: AppColors.goldSoft,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      // Champs de saisie : fond blanc, bordure fine, focus doré.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        hintStyle: const TextStyle(color: AppColors.greyLight, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.grey, fontSize: 13.5),
        floatingLabelStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: AppColors.greyLight,
        border: _border(AppColors.line),
        enabledBorder: _border(AppColors.line),
        focusedBorder: _border(AppColors.gold, width: 1.6),
        errorBorder: _border(AppColors.danger),
        focusedErrorBorder: _border(AppColors.danger, width: 1.6),
      ),
      // Boutons Material standard alignés sur les composants maison.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFFCBD5E1)),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }

  /// Construit une bordure arrondie de champ de saisie.
  ///
  /// [c] est la couleur du trait et [width] son épaisseur.
  static OutlineInputBorder _border(Color c, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSmall),
      borderSide: BorderSide(color: c, width: width),
    );
  }
}
