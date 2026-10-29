import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SystemUiUtils {
  static SystemUiOverlayStyle getOverlayStyle({
    required bool isDark,
    Color? navBarColor,
    Color? statusBarColor,
  }) {
    return SystemUiOverlayStyle(
      statusBarColor: statusBarColor ?? Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navBarColor ?? (isDark ? const Color(0xFF121212) : Colors.white),
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );
  }
}
