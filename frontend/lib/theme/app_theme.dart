import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF171717);
  static const inkSoft = Color(0xFF232323);
  static const gold = Color(0xFFD4AF37);
  static const goldSoft = Color(0xFFF8F1DC);
  static const white = Colors.white;
  static const bg = Color(0xFFF8F8F8);
  static const grey = Color(0xFF747474);
  static const greyLight = Color(0xFF9C9C9C);
  static const line = Color(0xFFEAEAEA);

  static const success = Color(0xFF1E7A4B);
  static const successBg = Color(0xFFE9F5EE);
  static const warning = Color(0xFFB78119);
  static const warningBg = Color(0xFFFFF4DF);
  static const danger = Color(0xFFB3261E);
  static const dangerBg = Color(0xFFFDECEA);
  static const info = Color(0xFF315FC7);
  static const infoBg = Color(0xFFEAF0FF);
  static const neutralBg = Color(0xFFF2F2F2);
}

class AppTheme {
  static const double radius = 14;

  static const LinearGradient goldLine = LinearGradient(
    colors: [Color(0xFFD4AF37), Color(0xFFE8CE7A)],
  );

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.gold,
        primary: AppColors.ink,
        surface: AppColors.white,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: const TextStyle(color: AppColors.greyLight, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.grey, fontSize: 13.5),
        floatingLabelStyle:
            const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        border: _border(AppColors.line),
        enabledBorder: _border(AppColors.line),
        focusedBorder: _border(AppColors.gold, width: 1.4),
        errorBorder: _border(AppColors.danger),
        focusedErrorBorder: _border(AppColors.danger, width: 1.4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFFD9D9D9)),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }

  static OutlineInputBorder _border(Color c, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c, width: width),
    );
  }
}