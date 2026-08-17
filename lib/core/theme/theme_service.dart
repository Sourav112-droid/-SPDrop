import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppTheme {
  midnightGlass,
  oceanAbyss,
  neonPulse,
  arcticFrost,
  sunsetEmber,
  forestWhisper,
  crimsonVelvet,
  solarFlare,
  cyberPunk,
  lavenderDream,
  obsidianOnyx,
}

/// Design tokens and visual palette properties for an application theme.
class AppThemeData {
  final String name;
  final String description;
  final IconData icon;
  final Brightness brightness;

  // Core palette
  final Color primary;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;

  // Background surfaces
  final Color scaffoldBg;
  final Color surfaceBg;
  final Color cardBg;
  final List<Color> backgroundGradient;

  // Glassmorphism properties
  final double glassOpacity;
  final double glassBorderOpacity;
  final double glassBlur;
  final Color glassBorderColor;
  final Color glassGlow;

  // Typography colors
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  const AppThemeData({
    required this.name,
    required this.description,
    required this.icon,
    required this.brightness,
    required this.primary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.scaffoldBg,
    required this.surfaceBg,
    required this.cardBg,
    required this.backgroundGradient,
    required this.glassOpacity,
    required this.glassBorderOpacity,
    required this.glassBlur,
    required this.glassBorderColor,
    required this.glassGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: surfaceBg,
        primary: primary,
      ),
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}

const Map<AppTheme, AppThemeData> appThemes = {
  AppTheme.midnightGlass: AppThemeData(
    name: 'Midnight Glass',
    description: 'Dark glassmorphism with electric blue accents',
    icon: Icons.nightlight_round,
    brightness: Brightness.dark,
    primary: Color(0xFF4F8EF7),
    accent: Color(0xFF6C63FF),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFFFB347),
    error: Color(0xFFFF6B6B),
    scaffoldBg: Color(0xFF0A0E1A),
    surfaceBg: Color(0xFF141824),
    cardBg: Color(0xFF1A1E2E),
    backgroundGradient: [Color(0xFF0A0E1A), Color(0xFF141824), Color(0xFF1A1E2E)],
    glassOpacity: 0.06,
    glassBorderOpacity: 0.08,
    glassBlur: 40,
    glassBorderColor: Color(0xFF4F8EF7),
    glassGlow: Color(0xFF4F8EF7),
    textPrimary: Color(0xFFF0F0F5),
    textSecondary: Color(0xFFa0a0b0),
    textTertiary: Color(0xFF606070),
  ),

  // 2. Ocean Abyss — deep teal/cyan
  AppTheme.oceanAbyss: AppThemeData(
    name: 'Ocean Abyss',
    description: 'Deep sea teal with bioluminescent accents',
    icon: Icons.water,
    brightness: Brightness.dark,
    primary: Color(0xFF00BFA5),
    accent: Color(0xFF00E5FF),
    success: Color(0xFF69F0AE),
    warning: Color(0xFFFFD54F),
    error: Color(0xFFFF5252),
    scaffoldBg: Color(0xFF0A1A1F),
    surfaceBg: Color(0xFF0F2027),
    cardBg: Color(0xFF142830),
    backgroundGradient: [Color(0xFF0A1A1F), Color(0xFF0F2027), Color(0xFF162D38)],
    glassOpacity: 0.07,
    glassBorderOpacity: 0.1,
    glassBlur: 35,
    glassBorderColor: Color(0xFF00BFA5),
    glassGlow: Color(0xFF00E5FF),
    textPrimary: Color(0xFFE0F7FA),
    textSecondary: Color(0xFF80CBC4),
    textTertiary: Color(0xFF4DB6AC),
  ),

  // 3. Neon Pulse — cyberpunk purple/magenta
  AppTheme.neonPulse: AppThemeData(
    name: 'Neon Pulse',
    description: 'Cyberpunk vibes with neon purple and pink',
    icon: Icons.electric_bolt,
    brightness: Brightness.dark,
    primary: Color(0xFFBB86FC),
    accent: Color(0xFFFF6EC7),
    success: Color(0xFF76FF03),
    warning: Color(0xFFFFAB40),
    error: Color(0xFFFF1744),
    scaffoldBg: Color(0xFF0D0B1A),
    surfaceBg: Color(0xFF16132B),
    cardBg: Color(0xFF1E1A38),
    backgroundGradient: [Color(0xFF0D0B1A), Color(0xFF16132B), Color(0xFF1E1A38)],
    glassOpacity: 0.08,
    glassBorderOpacity: 0.12,
    glassBlur: 45,
    glassBorderColor: Color(0xFFBB86FC),
    glassGlow: Color(0xFFFF6EC7),
    textPrimary: Color(0xFFF3E5F5),
    textSecondary: Color(0xFFCE93D8),
    textTertiary: Color(0xFF9C27B0),
  ),

  // 4. Arctic Frost — light glassmorphism
  AppTheme.arcticFrost: AppThemeData(
    name: 'Arctic Frost',
    description: 'Clean frosted glass with icy blue tones',
    icon: Icons.ac_unit,
    brightness: Brightness.light,
    primary: Color(0xFF2979FF),
    accent: Color(0xFF448AFF),
    success: Color(0xFF00C853),
    warning: Color(0xFFFF9100),
    error: Color(0xFFD50000),
    scaffoldBg: Color(0xFFF0F4F8),
    surfaceBg: Color(0xFFE8EEF4),
    cardBg: Color(0xFFFFFFFF),
    backgroundGradient: [Color(0xFFE8F0FE), Color(0xFFF0F4F8), Color(0xFFE3EBF6)],
    glassOpacity: 0.25,
    glassBorderOpacity: 0.2,
    glassBlur: 30,
    glassBorderColor: Color(0xFF2979FF),
    glassGlow: Color(0xFF448AFF),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF5A5A7A),
    textTertiary: Color(0xFF9A9AB0),
  ),

  // 5. Sunset Ember — warm orange/dark
  AppTheme.sunsetEmber: AppThemeData(
    name: 'Sunset Ember',
    description: 'Warm amber tones with fiery gradients',
    icon: Icons.wb_twilight,
    brightness: Brightness.dark,
    primary: Color(0xFFFF7043),
    accent: Color(0xFFFFAB40),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFF176),
    error: Color(0xFFEF5350),
    scaffoldBg: Color(0xFF1A0F0A),
    surfaceBg: Color(0xFF241810),
    cardBg: Color(0xFF2E1E14),
    backgroundGradient: [Color(0xFF1A0F0A), Color(0xFF241810), Color(0xFF2E1E14)],
    glassOpacity: 0.08,
    glassBorderOpacity: 0.1,
    glassBlur: 38,
    glassBorderColor: Color(0xFFFF7043),
    glassGlow: Color(0xFFFFAB40),
    textPrimary: Color(0xFFFFF3E0),
    textSecondary: Color(0xFFFFCC80),
    textTertiary: Color(0xFFBF8040),
  ),

  // 6. Forest Whisper — earthy green
  AppTheme.forestWhisper: AppThemeData(
    name: 'Forest Whisper',
    description: 'Earthy greens with a soothing nature vibe',
    icon: Icons.forest,
    brightness: Brightness.dark,
    primary: Color(0xFF2E7D32),
    accent: Color(0xFF81C784),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFC107),
    error: Color(0xFFE57373),
    scaffoldBg: Color(0xFF0A140A),
    surfaceBg: Color(0xFF102010),
    cardBg: Color(0xFF162B16),
    backgroundGradient: [Color(0xFF0A140A), Color(0xFF102010), Color(0xFF162B16)],
    glassOpacity: 0.08,
    glassBorderOpacity: 0.1,
    glassBlur: 40,
    glassBorderColor: Color(0xFF2E7D32),
    glassGlow: Color(0xFF81C784),
    textPrimary: Color(0xFFE8F5E9),
    textSecondary: Color(0xFFA5D6A7),
    textTertiary: Color(0xFF81C784),
  ),

  // 7. Crimson Velvet — deep red
  AppTheme.crimsonVelvet: AppThemeData(
    name: 'Crimson Velvet',
    description: 'Luxurious deep reds and rose gold',
    icon: Icons.diamond,
    brightness: Brightness.dark,
    primary: Color(0xFFB71C1C),
    accent: Color(0xFFF48FB1),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFB300),
    error: Color(0xFFFF5252),
    scaffoldBg: Color(0xFF170909),
    surfaceBg: Color(0xFF210D0D),
    cardBg: Color(0xFF2C1111),
    backgroundGradient: [Color(0xFF170909), Color(0xFF210D0D), Color(0xFF2C1111)],
    glassOpacity: 0.08,
    glassBorderOpacity: 0.12,
    glassBlur: 35,
    glassBorderColor: Color(0xFFB71C1C),
    glassGlow: Color(0xFFF48FB1),
    textPrimary: Color(0xFFFFEBEE),
    textSecondary: Color(0xFFFFCDD2),
    textTertiary: Color(0xFFEF9A9A),
  ),

  // 8. Solar Flare — vibrant orange/yellow
  AppTheme.solarFlare: AppThemeData(
    name: 'Solar Flare',
    description: 'Vibrant amber and orange energy',
    icon: Icons.local_fire_department,
    brightness: Brightness.dark,
    primary: Color(0xFFFFC107),
    accent: Color(0xFFFF9800),
    success: Color(0xFF8BC34A),
    warning: Color(0xFFFFEB3B),
    error: Color(0xFFF44336),
    scaffoldBg: Color(0xFF1A1605),
    surfaceBg: Color(0xFF262008),
    cardBg: Color(0xFF332B0B),
    backgroundGradient: [Color(0xFF1A1605), Color(0xFF262008), Color(0xFF332B0B)],
    glassOpacity: 0.07,
    glassBorderOpacity: 0.1,
    glassBlur: 30,
    glassBorderColor: Color(0xFFFFC107),
    glassGlow: Color(0xFFFF9800),
    textPrimary: Color(0xFFFFFDE7),
    textSecondary: Color(0xFFFFF59D),
    textTertiary: Color(0xFFFFE082),
  ),

  // 9. Cyber Punk — high contrast neon yellow/magenta
  AppTheme.cyberPunk: AppThemeData(
    name: 'Cyber Punk',
    description: 'High contrast black with striking neon accents',
    icon: Icons.memory,
    brightness: Brightness.dark,
    primary: Color(0xFFF0F000), // Neon Yellow
    accent: Color(0xFFFF007F), // Neon Magenta
    success: Color(0xFF39FF14), // Neon Green
    warning: Color(0xFFFF8C00),
    error: Color(0xFFFF003C),
    scaffoldBg: Color(0xFF050505),
    surfaceBg: Color(0xFF0F0F0F),
    cardBg: Color(0xFF141414),
    backgroundGradient: [Color(0xFF050505), Color(0xFF0A0A0A), Color(0xFF121212)],
    glassOpacity: 0.1,
    glassBorderOpacity: 0.15,
    glassBlur: 35,
    glassBorderColor: Color(0xFFF0F000),
    glassGlow: Color(0xFFFF007F),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFD0D0D0),
    textTertiary: Color(0xFFA0A0A0),
  ),

  // 10. Lavender Dream — soft and airy light theme
  AppTheme.lavenderDream: AppThemeData(
    name: 'Lavender Dream',
    description: 'Soft pastel purples with a light, airy feel',
    icon: Icons.spa,
    brightness: Brightness.light,
    primary: Color(0xFF9575CD),
    accent: Color(0xFFBA68C8),
    success: Color(0xFF81C784),
    warning: Color(0xFFFFB74D),
    error: Color(0xFFE57373),
    scaffoldBg: Color(0xFFF3E5F5), // Light purple tinted bg
    surfaceBg: Color(0x33F8BBD0), // 20% opacity pink
    cardBg: Color(0xFFFFFFFF),
    backgroundGradient: [Color(0xFFF3E5F5), Color(0xFFEDE7F6), Color(0xFFE8EAF6)],
    glassOpacity: 0.4,
    glassBorderOpacity: 0.25,
    glassBlur: 45,
    glassBorderColor: Color(0xFF9575CD),
    glassGlow: Color(0xFFBA68C8),
    textPrimary: Color(0xFF311B92),
    textSecondary: Color(0xFF512DA8),
    textTertiary: Color(0xFF7E57C2),
  ),

  // 11. Obsidian Onyx — amoled pure black
  AppTheme.obsidianOnyx: AppThemeData(
    name: 'Obsidian Onyx',
    description: 'Pure pitch black with subtle silver and cyan',
    icon: Icons.dark_mode,
    brightness: Brightness.dark,
    primary: Color(0xFF00E5FF),
    accent: Color(0xFFB0BEC5), // Silver
    success: Color(0xFF00C853),
    warning: Color(0xFFFFD600),
    error: Color(0xFFD50000),
    scaffoldBg: Color(0xFF000000), // Pitch black
    surfaceBg: Color(0xFF080808),
    cardBg: Color(0xFF0C0C0C),
    backgroundGradient: [Color(0xFF000000), Color(0xFF000000), Color(0xFF050505)],
    glassOpacity: 0.05,
    glassBorderOpacity: 0.08,
    glassBlur: 50,
    glassBorderColor: Color(0xFF00E5FF),
    glassGlow: Color(0xFF00E5FF),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFFB0BEC5),
    textTertiary: Color(0xFF78909C),
  ),
};

/// Manages application theme selection and persistence.
class ThemeService extends ChangeNotifier {
  static const String _key = 'selected_theme';
  AppTheme _currentTheme = AppTheme.midnightGlass;

  AppTheme get currentTheme => _currentTheme;
  AppThemeData get themeData => appThemes[_currentTheme]!;
  ThemeData get materialTheme => themeData.toThemeData();

  /// Loads persisted theme preference from storage.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_key);
    if (savedIndex != null && savedIndex < AppTheme.values.length) {
      _currentTheme = AppTheme.values[savedIndex];
      notifyListeners();
    }
  }

  /// Updates current theme and persists preference to storage.
  Future<void> setTheme(AppTheme theme) async {
    if (_currentTheme == theme) return;
    _currentTheme = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, theme.index);
  }

  /// Retrieves theme data definition for a specified theme.
  static AppThemeData getThemeData(AppTheme theme) => appThemes[theme]!;
}
