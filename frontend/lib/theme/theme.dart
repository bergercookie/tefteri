/// The one place that styles the app. Screens read from the theme and the
/// tokens; they do not hard-code colors, font sizes or radii.
library;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';
import 'transitions.dart';
import 'typography.dart';

export 'empty_state.dart';
export 'logo.dart';
export 'palette.dart';
export 'tokens.dart';

/// Builds the light or the dark theme.
ThemeData buildTefteriTheme(Brightness brightness) {
  final scheme = tefteriScheme(brightness);
  final colors =
      brightness == Brightness.dark ? TefteriColors.dark : TefteriColors.light;
  final text = tefteriTextTheme(scheme);
  final hairline = BorderSide(color: colors.rule);
  RoundedRectangleBorder shape(double r, {BorderSide? side}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: side ?? BorderSide.none,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.paper,
    canvasColor: colors.paper,
    fontFamily: Fonts.ui,
    textTheme: text,
    primaryTextTheme: text,
    extensions: [colors],
    dividerColor: colors.rule,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SoftPageTransitionsBuilder(),
      TargetPlatform.iOS: SoftPageTransitionsBuilder(),
      TargetPlatform.linux: SoftPageTransitionsBuilder(),
      TargetPlatform.macOS: SoftPageTransitionsBuilder(),
      TargetPlatform.windows: SoftPageTransitionsBuilder(),
      TargetPlatform.fuchsia: SoftPageTransitionsBuilder(),
    }),
    dividerTheme: DividerThemeData(color: colors.rule, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.paper,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.headlineSmall,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: Space.xs),
      surfaceTintColor: Colors.transparent,
      shape: shape(Corner.lg, side: hairline),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape(Corner.lg, side: hairline),
      titleTextStyle: text.headlineSmall,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(right: hairline),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle:
          text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: shape(Corner.md),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape(Corner.md, side: hairline),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(Corner.sm),
      ),
      textStyle: text.labelSmall?.copyWith(color: scheme.onInverseSurface),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: shape(Corner.md),
      titleTextStyle: text.bodyMedium,
      subtitleTextStyle: text.bodySmall,
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.md),
        borderSide: hairline,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.md),
        borderSide: hairline,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.md),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.md),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape(Corner.md),
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape(Corner.md),
        textStyle: text.labelLarge,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        foregroundColor: scheme.onSurface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape(Corner.md),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        shape: shape(Corner.md),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.primaryContainer,
      side: hairline,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: text.labelMedium,
      secondaryLabelStyle:
          text.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurfaceVariant,
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: scheme.onPrimary,
        side: hairline,
        shape: const StadiumBorder(),
        textStyle: text.labelMedium,
        visualDensity: VisualDensity.compact,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
      circularTrackColor: Colors.transparent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(scheme.outline.withValues(alpha: 0.5)),
      radius: const Radius.circular(Corner.pill),
    ),
  );
}

/// The light theme.
final ThemeData tefteriLight = buildTefteriTheme(Brightness.light);

/// The dark theme.
final ThemeData tefteriDark = buildTefteriTheme(Brightness.dark);
