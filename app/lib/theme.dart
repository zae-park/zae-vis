import 'package:flutter/material.dart';

/// zaevis look: a quiet notebook rather than a stock Material demo. Warm off-white paper, one ink
/// accent, Pretendard for every weight, flat surfaces with hairline borders, and no tinted app bars.
class ZaevisTheme {
  static const seed = Color(0xFF2F5D7C); // ink blue
  static const _paperLight = Color(0xFFF7F6F2);
  static const _paperDark = Color(0xFF131415);
  static const _cardLight = Color(0xFFFFFFFF);
  static const _cardDark = Color(0xFF1C1D1F);

  /// Code: a real monospace on each platform ('monospace' alone is not a font on macOS), Korean
  /// inside code falls back to Pretendard so it does not switch to a random system face.
  static const mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['SF Mono', 'Consolas', 'DejaVu Sans Mono', 'monospace', 'Pretendard'], fontSize: 13, height: 1.45);

  /// Formulas (`$…$`): serif italic, the conventional look for math without a LaTeX engine.
  static const math = TextStyle(fontFamily: 'Times New Roman', fontFamilyFallback: ['Georgia', 'serif', 'Pretendard'], fontStyle: FontStyle.italic, fontSize: 15, height: 1.4);

  static ThemeData of(Brightness b) {
    final dark = b == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final scheme = base.copyWith(
      surface: dark ? _paperDark : _paperLight,
      surfaceContainerLowest: dark ? _cardDark : _cardLight,
      surfaceContainerLow: dark ? const Color(0xFF191A1C) : const Color(0xFFFBFAF7),
      surfaceContainer: dark ? _cardDark : _cardLight,
      surfaceContainerHigh: dark ? const Color(0xFF232527) : const Color(0xFFF0EEE8),
      surfaceContainerHighest: dark ? const Color(0xFF2A2C2F) : const Color(0xFFE9E6DF),
      outlineVariant: dark ? const Color(0xFF2E3033) : const Color(0xFFE4E1D9),
    );
    final text = Typography.material2021(platform: TargetPlatform.macOS).black.apply(fontFamily: 'Pretendard');
    final textDark = Typography.material2021(platform: TargetPlatform.macOS).white.apply(fontFamily: 'Pretendard');
    final tt = (dark ? textDark : text).copyWith(
      headlineMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: scheme.onSurface),
      headlineSmall: TextStyle(fontFamily: 'Pretendard', fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: scheme.onSurface),
      titleLarge: TextStyle(fontFamily: 'Pretendard', fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: scheme.onSurface),
      titleMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
      titleSmall: TextStyle(fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
      bodyLarge: TextStyle(fontFamily: 'Pretendard', fontSize: 15, height: 1.5, color: scheme.onSurface),
      bodyMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 14, height: 1.5, color: scheme.onSurface),
      bodySmall: TextStyle(fontFamily: 'Pretendard', fontSize: 12.5, height: 1.45, color: scheme.onSurfaceVariant),
      labelLarge: TextStyle(fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
      labelMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 12.5, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
      labelSmall: TextStyle(fontFamily: 'Pretendard', fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: scheme.onSurfaceVariant),
    );
    final hairline = BorderSide(color: scheme.outlineVariant);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Pretendard',
      textTheme: tt,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: tt.titleLarge,
        toolbarHeight: 56,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
        selectedLabelTextStyle: tt.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: tt.labelMedium,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -1,
        minWidth: 76,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(tt.labelMedium),
        height: 64,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: hairline),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide.none,
        labelStyle: tt.labelMedium?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: hairline),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: hairline),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        labelStyle: tt.labelMedium,
        helperStyle: tt.bodySmall,
        hintStyle: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: hairline)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
        textStyle: WidgetStatePropertyAll(tt.bodyLarge),
        hintStyle: WidgetStatePropertyAll(tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
        constraints: const BoxConstraints(minHeight: 50),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: tt.labelLarge, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)), textStyle: tt.labelLarge),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: tt.labelLarge)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant)),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: tt.bodySmall,
        minVerticalPadding: 10,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: hairline),
        titleTextStyle: tt.titleLarge,
        contentTextStyle: tt.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surfaceContainerLowest, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: scheme.surfaceContainerHighest),
      tooltipTheme: TooltipThemeData(textStyle: tt.labelMedium?.copyWith(color: scheme.onInverseSurface)),
    );
  }
}
