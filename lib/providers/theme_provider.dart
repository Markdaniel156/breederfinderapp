import 'package:flutter/material.dart';

import 'dart:ui' as ui;

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Offset? _togglePosition;
  ui.Image? _screenshot;

  ThemeMode get themeMode => _themeMode;
  Offset? get togglePosition => _togglePosition;
  ui.Image? get screenshot => _screenshot;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void setScreenshot(ui.Image? image) {
    _screenshot = image;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void toggleTheme(bool isOn, [Offset? position]) {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    _togglePosition = position;
    notifyListeners();
  }
}
