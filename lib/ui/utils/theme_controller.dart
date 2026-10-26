import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import '/utils/helper.dart';

class ThemeController extends GetxController {
  final primaryColor = Colors.deepPurple[400].obs;
  final textColor = Colors.white24.obs;
  final themedata = Rxn<ThemeData>();

  /// The method channel for setting the title bar color on Windows.
  final platform = const MethodChannel('win_titlebar_color');
  String? currentSongId;

  ThemeController() {
    // Default to Velqi violet (#7C3AED = 4290363117) if no saved preference
    primaryColor.value =
        Color(Hive.box('AppPrefs').get("themePrimaryColor") ?? 0xFF7C3AED);

    // Load saved theme preference. Velqi is dark-only: a saved light/system
    // preference from older builds resolves to dark below.
    final savedIndex = Hive.box('AppPrefs').get('themeModeType') ?? 2;
    final themeType = ThemeType.values[savedIndex.clamp(0, ThemeType.values.length - 1)];
    changeThemeModeType(themeType);

    super.onInit();
  }

  void changeThemeModeType(dynamic value, {bool sysCall = false}) {
    // Velqi is DARK-ONLY: light and system modes no longer exist. Every
    // selection resolves to the dark theme — "dynamic" additionally tints
    // it with the current album's palette.
    if (value == ThemeType.light || value == ThemeType.system) {
      value = ThemeType.dark;
    }
    themedata.value = _createThemeData(
        value == ThemeType.dynamic
            ? _createMaterialColor(primaryColor.value!)
            : null,
        value);
    setWindowsTitleBarColor(themedata.value!.scaffoldBackgroundColor);
  }

  void setTheme(ImageProvider imageProvider, String songId) async {
    if (songId == currentSongId) return;
    PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, height: 200, width: 200));
    //final colorList = generator.colors;
    final paletteColor = generator.dominantColor ??
        generator.darkMutedColor ??
        generator.darkVibrantColor ??
        generator.lightMutedColor ??
        generator.lightVibrantColor;
    primaryColor.value = paletteColor!.color;
    textColor.value = paletteColor.bodyTextColor;
    // printINFO(paletteColor.color.computeLuminance().toString());0.11 ref
    if (paletteColor.color.computeLuminance() > 0.10) {
      primaryColor.value = paletteColor.color.withLightness(0.10);
      textColor.value = Colors.white54;
    }
    final primarySwatch = _createMaterialColor(primaryColor.value!);
    themedata.value = _createThemeData(primarySwatch, ThemeType.dynamic,
        textColor: textColor.value,
        titleColorSwatch: _createMaterialColor(textColor.value));
    currentSongId = songId;
    Hive.box('AppPrefs').put("themePrimaryColor", (primaryColor.value!).value);
    setWindowsTitleBarColor(themedata.value!.scaffoldBackgroundColor);
  }

  ThemeData _createThemeData(MaterialColor? primarySwatch, ThemeType themeType,
      {MaterialColor? titleColorSwatch, Color? textColor}) {
    if (themeType == ThemeType.dynamic) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: true),
      );

      final baseTheme = ThemeData(
          useMaterial3: false,
          primaryColor: primarySwatch![500],
          colorScheme: ColorScheme.fromSwatch(
              accentColor: primarySwatch[200],
              brightness: Brightness.dark,
              backgroundColor: primarySwatch[700],
              primarySwatch: primarySwatch),
          //accentColor: primarySwatch[200],
          dialogBackgroundColor: primarySwatch[700],
          cardColor: primarySwatch[600],
          primaryColorLight: primarySwatch[400],
          primaryColorDark: primarySwatch[700],
          //secondaryHeaderColor: primarySwatch[50],
          canvasColor: primarySwatch[700],
          //scaffoldBackgroundColor: primarySwatch[700],
          bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: primarySwatch[600],
              modalBarrierColor: primarySwatch[400]),
          textTheme: TextTheme(
            titleLarge: const TextStyle(
                fontSize: 23, fontWeight: FontWeight.bold, color: Colors.white),
            titleMedium: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
            titleSmall: TextStyle(color: primarySwatch[100]),
            bodyMedium: TextStyle(color: primarySwatch[100]),
            labelMedium: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 23,
                color: textColor ?? primarySwatch[50]),
            labelSmall: TextStyle(
                fontSize: 15,
                color: titleColorSwatch != null
                    ? titleColorSwatch[900]
                    : primarySwatch[100],
                letterSpacing: 0,
                fontWeight: FontWeight.bold),
          ),
          indicatorColor: Colors.white,
          progressIndicatorTheme: ProgressIndicatorThemeData(
              linearTrackColor: (primarySwatch[300])!.computeLuminance() > 0.3
                  ? Colors.black54
                  : Colors.white70,
              color: textColor),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: primarySwatch[700],
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedIconTheme: IconThemeData(color: primarySwatch[100]),
              selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              unselectedLabelTextStyle: TextStyle(
                  color: primarySwatch[100], fontWeight: FontWeight.bold)),
          sliderTheme: SliderThemeData(
            inactiveTrackColor: primarySwatch[300],
            activeTrackColor: textColor,
            valueIndicatorColor: primarySwatch[400],
            thumbColor: Colors.white,
          ),
          textSelectionTheme: TextSelectionThemeData(
              cursorColor: primarySwatch[200],
              selectionColor: primarySwatch[200],
              selectionHandleColor: primarySwatch[200])
          //scaffoldBackgroundColor: primarySwatch[700]
          );
      return baseTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme));
    } else if (themeType == ThemeType.dark) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.black,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false),
      );
      // ── Velqi AMOLED theme (Material 3, total black + white) ──────────
      const velqiBg     = Color(0xFF000000); // pure black scaffold
      const velqiCard   = Color(0xFF0A0A0A); // near-black cards
      const velqiElev   = Color(0xFF141414); // elevated surfaces / sheets
      const velqiBtn    = Color(0xFF1E1E1E); // filled button surface (not white!)
      const velqiAccent = Color(0xFFBDBDBD);  // muted accent (sliders/active) — softer than white
      const velqiText   = Color(0xFFE6E6E6);  // high-emphasis body text (soft white)
      const velqiMuted  = Color(0xFF9A9A9A);  // muted grey text
      const velqiTrack  = Color(0xFF2A2A2A);  // inactive slider / divider
      final baseTheme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          canvasColor: velqiBg,
          primaryColor: velqiBg,
          primaryColorDark: velqiBg,
          primaryColorLight: velqiCard,
          scaffoldBackgroundColor: velqiBg,
          dialogBackgroundColor: velqiElev,
          cardColor: velqiCard,
          dividerColor: velqiTrack,
          splashColor: Colors.white10,
          highlightColor: Colors.white10,
          colorScheme: const ColorScheme.dark(
            primary: velqiAccent,
            onPrimary: Colors.black,
            secondary: velqiAccent,
            onSecondary: Colors.black,
            surface: velqiCard,
            onSurface: velqiText,
            surfaceContainerHighest: velqiElev,
            background: velqiBg,
            onBackground: velqiText,
            outline: velqiTrack,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: velqiBtn,
              foregroundColor: velqiText,
              elevation: 0,
              side: const BorderSide(color: velqiTrack, width: 1),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: velqiBtn,
              foregroundColor: velqiText,
            ),
          ),
          appBarTheme: const AppBarTheme(
              backgroundColor: velqiBg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: velqiText)),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: velqiElev,
              foregroundColor: velqiText,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              splashColor: Colors.white10),
          iconTheme: const IconThemeData(color: velqiText),
          progressIndicatorTheme: ProgressIndicatorThemeData(
              color: velqiAccent, linearTrackColor: velqiTrack),
          textTheme: const TextTheme(
              titleLarge: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: velqiText,
              ),
              titleMedium: TextStyle(
                fontWeight: FontWeight.w600,
                color: velqiText,
              ),
              titleSmall: TextStyle(color: velqiMuted),
              labelMedium: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 23,
                color: velqiText,
              ),
              labelSmall: TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: velqiText),
              bodyLarge: TextStyle(color: velqiText),
              bodyMedium: TextStyle(color: velqiMuted),
              bodySmall: TextStyle(color: velqiMuted)),
          navigationBarTheme: NavigationBarThemeData(
              backgroundColor: velqiBg,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.white12,
              elevation: 0,
              labelTextStyle: WidgetStateProperty.resolveWith((states) =>
                  TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: states.contains(WidgetState.selected)
                          ? velqiText
                          : velqiMuted)),
              iconTheme: WidgetStateProperty.resolveWith((states) =>
                  IconThemeData(
                      color: states.contains(WidgetState.selected)
                          ? velqiText
                          : velqiMuted))),
          navigationRailTheme: const NavigationRailThemeData(
              backgroundColor: velqiBg,
              selectedIconTheme: IconThemeData(color: velqiText),
              unselectedIconTheme: IconThemeData(color: velqiMuted),
              selectedLabelTextStyle: TextStyle(
                  color: velqiText,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              unselectedLabelTextStyle: TextStyle(
                  color: velqiMuted, fontWeight: FontWeight.bold)),
          bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: velqiElev,
              surfaceTintColor: Colors.transparent,
              modalBarrierColor: Colors.black87),
          sliderTheme: SliderThemeData(
            inactiveTrackColor: velqiTrack,
            activeTrackColor: velqiAccent,
            valueIndicatorColor: velqiElev,
            thumbColor: velqiAccent,
          ),
          textSelectionTheme: const TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: Colors.white24,
              selectionHandleColor: Colors.white),
          inputDecorationTheme: const InputDecorationTheme(
              focusColor: Colors.white,
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white))));
      return baseTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme));
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.dark,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: const Color(0xFFF5F5F5),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false),
      );
      // Velqi Light theme — soft white/grey, not harsh
      const velqiLightBg     = Color(0xFFF7F7F8); // soft off-white scaffold
      const velqiLightCard   = Color(0xFFFFFFFF); // white cards
      const velqiLightSurface= Color(0xFFF1F1F3); // elevated surfaces
      const velqiLightBorder = Color(0xFFECECEC); // very subtle borders (was E0E0E0 — too strong)
      const velqiLightDivider= Color(0xFFEFEFF1); // even softer for inner dividers
      const velqiLightText   = Color(0xFF1A1A1A); // high-emphasis text
      const velqiLightMuted  = Color(0xFF7A7A7A); // muted grey text
      const velqiLightAccent = Color(0xFF5C5C5C); // accent for sliders/buttons
      const velqiLightNavBg  = Color(0xFFF2F2F4); // bottom nav bar surface (slightly cooler than scaffold)
      final baseTheme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          canvasColor: velqiLightBg,
          primaryColor: velqiLightBg,
          primaryColorDark: velqiLightCard,
          primaryColorLight: velqiLightSurface,
          scaffoldBackgroundColor: velqiLightBg,
          dialogBackgroundColor: velqiLightCard,
          cardColor: velqiLightCard,
          dividerColor: velqiLightDivider,
          splashColor: Colors.black12,
          highlightColor: Colors.black12,
          colorScheme: const ColorScheme.light(
            primary: velqiLightAccent,
            onPrimary: Colors.white,
            secondary: velqiLightAccent,
            onSecondary: Colors.white,
            surface: velqiLightCard,
            onSurface: velqiLightText,
            surfaceContainerHighest: velqiLightSurface,
            background: velqiLightBg,
            onBackground: velqiLightText,
            outline: velqiLightBorder,
          ),
          appBarTheme: const AppBarTheme(
              backgroundColor: velqiLightBg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: velqiLightText)),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: velqiLightCard,
              foregroundColor: velqiLightText,
              elevation: 1,
              focusElevation: 1,
              hoverElevation: 1,
              splashColor: Colors.black12),
          iconTheme: const IconThemeData(color: velqiLightText),
          progressIndicatorTheme: ProgressIndicatorThemeData(
              color: velqiLightAccent, linearTrackColor: velqiLightBorder),
          textTheme: const TextTheme(
              titleLarge: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: velqiLightText,
              ),
              titleMedium: TextStyle(
                fontWeight: FontWeight.w600,
                color: velqiLightText,
              ),
              titleSmall: TextStyle(color: velqiLightMuted),
              labelMedium: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 23,
                color: velqiLightText,
              ),
              labelSmall: TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: velqiLightText),
              bodyLarge: TextStyle(color: velqiLightText),
              bodyMedium: TextStyle(color: velqiLightMuted),
              bodySmall: TextStyle(color: velqiLightMuted)),
          navigationBarTheme: NavigationBarThemeData(
              backgroundColor: velqiLightNavBg,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.black.withAlpha(10),
              elevation: 0,
              labelTextStyle: WidgetStateProperty.resolveWith((states) =>
                  TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: states.contains(WidgetState.selected)
                          ? velqiLightText
                          : velqiLightMuted)),
              iconTheme: WidgetStateProperty.resolveWith((states) =>
                  IconThemeData(
                      color: states.contains(WidgetState.selected)
                          ? velqiLightText
                          : velqiLightMuted))),
          navigationRailTheme: const NavigationRailThemeData(
              backgroundColor: velqiLightBg,
              selectedIconTheme: IconThemeData(color: velqiLightText),
              unselectedIconTheme: IconThemeData(color: velqiLightMuted),
              selectedLabelTextStyle: TextStyle(
                  color: velqiLightText,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              unselectedLabelTextStyle: TextStyle(
                  color: velqiLightMuted, fontWeight: FontWeight.bold)),
          bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: velqiLightCard,
              surfaceTintColor: Colors.transparent,
              modalBarrierColor: Colors.black26),
          sliderTheme: SliderThemeData(
            inactiveTrackColor: velqiLightBorder,
            activeTrackColor: velqiLightAccent,
            valueIndicatorColor: velqiLightSurface,
            thumbColor: velqiLightAccent,
          ),
          textSelectionTheme: const TextSelectionThemeData(
              cursorColor: velqiLightAccent,
              selectionColor: Colors.black26,
              selectionHandleColor: velqiLightAccent),
          inputDecorationTheme: const InputDecorationTheme(
              focusColor: velqiLightAccent,
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: velqiLightAccent))));
      return baseTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme));
    }
  }

  MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }

  Future<void> setWindowsTitleBarColor(Color color) async {
    if (!GetPlatform.isWindows) return;
    try {
      Future.delayed(
          const Duration(milliseconds: 350),
          () async {
        try {
          await platform.invokeMethod('setTitleBarColor', {
            'r': color.red,
            'g': color.green,
            'b': color.blue,
          });
        } catch (_) {}
      });
    } on PlatformException catch (e) {
      printERROR("Failed to set title bar color: ${e.message}");
    }
  }
}

extension ComplementaryColor on Color {
  Color get complementaryColor => getComplementaryColor(this);
  Color getComplementaryColor(Color color) {
    int r = 255 - color.red;
    int g = 255 - color.green;
    int b = 255 - color.blue;
    return Color.fromARGB(color.alpha, r, g, b);
  }
}

extension ColorWithHSL on Color {
  HSLColor get hsl => HSLColor.fromColor(this);

  Color withSaturation(double saturation) {
    return hsl.withSaturation(clampDouble(saturation, 0.0, 1.0)).toColor();
  }

  Color withLightness(double lightness) {
    return hsl.withLightness(clampDouble(lightness, 0.0, 1.0)).toColor();
  }

  Color withHue(double hue) {
    return hsl.withHue(clampDouble(hue, 0.0, 360.0)).toColor();
  }
}

extension HexColor on Color {
  /// String is in the format "aabbcc" or "ffaabbcc" with an optional leading "#".
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  /// Prefixes a hash sign if [leadingHashSign] is set to `true` (default is `true`).
  String toHex({bool leadingHashSign = true}) => '${leadingHashSign ? '#' : ''}'
      '${alpha.toRadixString(16).padLeft(2, '0')}'
      '${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

enum ThemeType {
  dynamic,
  system,
  dark,
  light,
}
