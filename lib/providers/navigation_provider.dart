import 'package:flutter/material.dart';
import '../models/breeder.dart';

class NavigationProvider with ChangeNotifier {
  int _selectedIndex = 0;
  Breeder? _selectedBreeder;

  int get selectedIndex => _selectedIndex;
  Breeder? get selectedBreeder => _selectedBreeder;

  void setIndex(int index, {Breeder? breeder}) {
    _selectedIndex = index;
    _selectedBreeder = breeder;
    notifyListeners();
  }

  void clearSelectedBreeder() {
    _selectedBreeder = null;
    notifyListeners();
  }
}
