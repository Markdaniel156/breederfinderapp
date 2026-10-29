import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/breeder_provider.dart';
import '../models/breeder.dart';
import 'profile_screen.dart';
import 'chat_screen.dart';
import '../providers/navigation_provider.dart';
import '../widgets/restricted_access_dialog.dart';
import '../providers/auth_provider.dart';
import '../utils/animal_breeds.dart';
import '../utils/system_ui_utils.dart';

class SmartMatchingScreen extends StatefulWidget {
  const SmartMatchingScreen({super.key});

  @override
  State<SmartMatchingScreen> createState() => _SmartMatchingScreenState();
}

class _SmartMatchingScreenState extends State<SmartMatchingScreen> {
  int _currentStep = 0;
  
  // Answers
  String _searchType = 'Breeder'; // Default to Breeder
  String? _selectedCategory;
  String _selectedBreed = 'Any';
  String _location = 'Any';
  
  final TextEditingController _budgetController = TextEditingController(text: '1000000');
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _sexController = TextEditingController();

  String? _budgetError;
  String? _sexError;
  String? _ageError;

  final List<String> _district5 = [
    'Any',
    'Binalbagan',
    'Himamaylan City',
    'Hinigaran',
    'Isabela',
    'La Castellana',
    'Moises Padilla',
  ];

  final Map<String, String> _categoryImages = {
    'Dog': 'https://images.unsplash.com/photo-1517849845537-4d257902454a?auto=format&fit=crop&q=80&w=300',
    'Cat': 'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?auto=format&fit=crop&q=80&w=300',
    'Pig': 'https://images.unsplash.com/photo-1544225071-886490fee298?auto=format&fit=crop&q=80&w=300',
    'Goat': 'https://images.unsplash.com/photo-1524024973431-2ad916746881?auto=format&fit=crop&q=80&w=300',
    'Cow': 'https://images.unsplash.com/photo-1546445317-29f4545e9d53?auto=format&fit=crop&q=80&w=300',
    'Carabao': 'https://images.unsplash.com/photo-1589923188900-85dae523342b?auto=format&fit=crop&q=80&w=300',
    'Horse': 'https://images.unsplash.com/photo-1553284965-83fd3e82fa5a?auto=format&fit=crop&q=80&w=300',
    'Sheep': 'https://images.unsplash.com/photo-1484557918186-7b4e571d4552?auto=format&fit=crop&q=80&w=300',
    'Rabbit': 'https://images.unsplash.com/photo-1585110396000-c9ffd4e4b308?auto=format&fit=crop&q=80&w=300',
    'Chicken': 'https://images.unsplash.com/photo-1548550023-2bdb3c5beed7?auto=format&fit=crop&q=80&w=300',
    'Betta Fish': 'https://images.unsplash.com/photo-1524704659690-3f7a3fe41bb7?auto=format&fit=crop&q=80&w=300',
    'Koi Fish': 'https://images.unsplash.com/photo-1522069169874-c58ec4b76be5?auto=format&fit=crop&q=80&w=300',
  };

  List<Breeder> _matches = [];
  bool _showingResults = false;
  bool _isSearching = false;

  void _findMatches() async {
    setState(() {
      _isSearching = true;
    });

    // Simulate searching delay for aesthetics
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    final allBreeders = Provider.of<BreederProvider>(context, listen: false).breeders;
    final budgetText = _budgetController.text.replaceAll(',', '');
    final budget = double.tryParse(budgetText) ?? 1000000;
    final ageSearch = _ageController.text.trim().toLowerCase();
    final sexSearch = _sexController.text.trim().toLowerCase();
    
    String normalizeBreed(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedSelectedBreed = normalizeBreed(_selectedBreed);
    
    // Strict matching respecting user preferences (category, breed, location, budget, etc.)
    List<Breeder> results = allBreeders.where((breeder) {
      // 0. Search Type match
      if (_searchType != 'Any') {
        if (breeder.type.toLowerCase() != _searchType.toLowerCase()) return false;
      }

      // 1. Category match (flexible: handles plural/singular and case variations)
      if (_selectedCategory != null && _selectedCategory != 'Other' && _selectedCategory != 'Select Animals') {
        final selectedCatLower = _selectedCategory!.toLowerCase();
        final breederCatLower = breeder.category.toLowerCase();
        bool catMatch = breederCatLower == selectedCatLower ||
            breederCatLower.contains(selectedCatLower) ||
            selectedCatLower.contains(breederCatLower);
        if (!catMatch) {
          if ((selectedCatLower == 'poultry' || selectedCatLower == 'chicken') &&
              (breederCatLower == 'chicken' || breederCatLower == 'poultry')) {
            catMatch = true;
          }
        }
        if (!catMatch) return false;
      }

      // 2. Breed match (flexible with normalization for variants like "Shihtzu" vs "Shih Tzu")
      if (_selectedBreed != 'Any') {
        bool breedMatch = normalizeBreed(breeder.breed).contains(normalizedSelectedBreed) ||
            normalizedSelectedBreed.contains(normalizeBreed(breeder.breed));
        if (!breedMatch && breeder.animals.isNotEmpty) {
          breedMatch = breeder.animals.any((a) =>
              normalizeBreed(a.breed).contains(normalizedSelectedBreed) ||
              normalizedSelectedBreed.contains(normalizeBreed(a.breed)));
        }
        if (!breedMatch) return false;
      }

      // 3. Budget / Price match
      double listingPrice = double.tryParse(breeder.price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      if (listingPrice == 0 && breeder.animals.isNotEmpty) {
        final animalPrices = breeder.animals.map((a) => a.price).toList();
        if (animalPrices.isNotEmpty) {
          listingPrice = animalPrices.reduce((a, b) => a < b ? a : b);
        }
      }
      if (listingPrice > budget && listingPrice != 0) {
        return false;
      }

      // 4. Location match (flexible: handles "Himamaylan City" vs "Himamaylan", "Hinigaran", etc.)
      if (_location != 'Any') {
        final locQuery = _location.toLowerCase().replaceAll('city', '').trim();
        final addressLower = breeder.address.toLowerCase();
        if (!addressLower.contains(locQuery) && !addressLower.contains(_location.toLowerCase())) {
          return false;
        }
      }

      // 5. Sex / Gender match
      if (sexSearch.isNotEmpty && sexSearch != 'any') {
        bool sexMatch = breeder.gender.toLowerCase().contains(sexSearch);
        if (!sexMatch && breeder.gender.isNotEmpty) {
          return false;
        }
      }

      // 6. Age match
      if (ageSearch.isNotEmpty && ageSearch != 'any') {
        bool ageMatch = breeder.age.toLowerCase().contains(ageSearch);
        if (!ageMatch && breeder.age.isNotEmpty) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort by rating or freshness
    results.sort((a, b) => b.averageRating.compareTo(a.averageRating));
    
    setState(() {
      _matches = results;
      _showingResults = true;
      _isSearching = false;
    });
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _ageController.dispose();
    _sexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const themeGreen = Color(0xFF2D6A4F);
    const darkGreen = Color(0xFF1B4332);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('Find My Match', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7F5),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _isSearching 
              ? _buildSearchingView(themeGreen) 
              : (_showingResults ? _buildResultsView() : _buildQuestionnaireView(themeGreen, darkGreen)),
        ),
      ),
    );
  }

  Widget _buildSearchingView(Color themeGreen) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  strokeWidth: 6,
                  color: Color(0xFF2D6A4F),
                  backgroundColor: Color(0xFFE9F5F2),
                ),
              ),
              _PulseIcon(),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'Finding Your Perfect Match...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B4332),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scanning breeders and traders near you',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionnaireView(Color themeGreen, Color darkGreen) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 6,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(themeGreen),
            borderRadius: BorderRadius.circular(10),
            minHeight: 8,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentStep == 0) _buildTypeStep(themeGreen),
                if (_currentStep == 1) _buildCategoryStep(themeGreen),
                if (_currentStep == 2) _buildBreedStep(themeGreen),
                if (_currentStep == 3) _buildBudgetStep(themeGreen),
                if (_currentStep == 4) _buildLocationStep(themeGreen),
                if (_currentStep == 5) _buildFinalStep(themeGreen),
              ],
            ),
          ),
        ),
        _buildNavigationButtons(themeGreen),
      ],
    );
  }

  Widget _buildTypeStep(Color themeGreen) {
    final types = [
      {'name': 'Breeder', 'desc': 'Find verified professional breeders', 'icon': Icons.pets_rounded},
      {'name': 'Trader', 'desc': 'Find the best deals in AniMarket', 'icon': Icons.storefront_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What are you looking for?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose if you want professional breeding or trading animals.',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
        const SizedBox(height: 32),
        ...types.map((type) {
          final isSelected = _searchType == type['name'];
          return GestureDetector(
            onTap: () => setState(() => _searchType = type['name'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isSelected ? themeGreen : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: isSelected ? themeGreen : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    type['icon'] as IconData,
                    size: 32,
                    color: isSelected ? Colors.white : themeGreen,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type['name'] as String,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          type['desc'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected ? Colors.white.withValues(alpha: 0.8) : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Colors.white)
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCategoryStep(Color themeGreen) {
    final breederProvider = Provider.of<BreederProvider>(context, listen: false);
    
    // Dynamically get categories that actually have listings for the selected type
    final availableCategories = breederProvider.breeders
        .where((b) => b.type.toLowerCase() == _searchType.toLowerCase() && b.animals.isNotEmpty)
        .map((b) => b.category)
        .toSet()
        .toList();

    // Fallback to all standard categories if no data yet (for UI display)
    final displayCategories = availableCategories.isEmpty 
        ? _categoryImages.keys.toList() 
        : availableCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What are you looking for?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Select from available $_searchType animal types.',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
        const SizedBox(height: 32),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: displayCategories.length,
          itemBuilder: (context, index) {
            final catName = displayCategories[index];
            final imageUrl = _categoryImages[catName] ?? _categoryImages['Dog']!;
            final isSelected = _selectedCategory == catName;
            
            return GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = catName;
                _selectedBreed = 'Any'; // Reset breed when category changes
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected ? themeGreen.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: isSelected ? themeGreen : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          image: DecorationImage(
                            image: NetworkImage(imageUrl),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Text(
                        catName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? themeGreen : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBreedStep(Color themeGreen) {
    final List<String> breeds = ['Any', ...(animalBreeds[_selectedCategory] ?? [])];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preferred Breed?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a breed for your $_selectedCategory.',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
        const SizedBox(height: 32),
        DropdownButtonFormField<String>(
          initialValue: breeds.contains(_selectedBreed) ? _selectedBreed : breeds[0],
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            prefixIcon: Icon(Icons.pets, color: themeGreen),
          ),
          items: breeds.map<DropdownMenuItem<String>>((String breed) {
            return DropdownMenuItem<String>(
              value: breed,
              child: Text(breed),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedBreed = newValue;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildBudgetStep(Color themeGreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What is your budget?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Input the maximum price you are willing to pay.',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _budgetController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          onChanged: (val) {
            if (_budgetError != null) {
              setState(() => _budgetError = null);
            }
          },
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: themeGreen),
          decoration: InputDecoration(
            hintText: 'e.g. 50000',
            errorText: _budgetError,
            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
            prefixText: '₱ ',
            prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: themeGreen),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _budgetError != null ? Colors.redAccent : Colors.transparent,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _budgetError != null ? Colors.redAccent : themeGreen,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationStep(Color themeGreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preferred Location?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Select a place in the 5th District or choose Any.',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _district5.map((city) {
            final isSelected = _location == city;
            return GestureDetector(
              onTap: () => setState(() => _location = city),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? themeGreen : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)
                  ],
                  border: Border.all(color: isSelected ? themeGreen : Colors.transparent),
                ),
                child: Text(
                  city,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFinalStep(Color themeGreen) {
    final sexOptions = ['Male', 'Female', 'Any'];
    final ageOptions = ['Young', 'Adult', 'Any'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Almost there!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Input or select your preferences for sex and age.',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
        const SizedBox(height: 32),
        const Text('Preferred Sex *', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _sexController,
          onChanged: (_) {
            if (_sexError != null) {
              setState(() => _sexError = null);
            } else {
              setState(() {});
            }
          },
          decoration: InputDecoration(
            hintText: 'e.g. Male, Female, or Any',
            errorText: _sexError,
            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _sexError != null ? Colors.redAccent : Colors.transparent,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _sexError != null ? Colors.redAccent : themeGreen,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            prefixIcon: Icon(
              Icons.transgender,
              color: _sexError != null ? Colors.redAccent : themeGreen,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: sexOptions.map((option) {
            final isSelected = _sexController.text.trim().toLowerCase() == option.toLowerCase();
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              selectedColor: themeGreen,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _sexController.text = option;
                    _sexError = null;
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        const Text('Preferred Age *', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _ageController,
          onChanged: (_) {
            if (_ageError != null) {
              setState(() => _ageError = null);
            } else {
              setState(() {});
            }
          },
          decoration: InputDecoration(
            hintText: 'e.g. 2 months, Adult, or Any',
            errorText: _ageError,
            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _ageError != null ? Colors.redAccent : Colors.transparent,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _ageError != null ? Colors.redAccent : themeGreen,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            prefixIcon: Icon(
              Icons.cake_outlined,
              color: _ageError != null ? Colors.redAccent : themeGreen,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ageOptions.map((option) {
            final isSelected = _ageController.text.trim().toLowerCase() == option.toLowerCase();
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              selectedColor: themeGreen,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _ageController.text = option;
                    _ageError = null;
                  });
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons(Color themeGreen) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5)),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {
                if (_currentStep == 1 && _selectedCategory == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a category'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                if (_currentStep == 3 && _budgetController.text.trim().isEmpty) {
                  setState(() {
                    _budgetError = 'Please enter your budget';
                  });
                  return;
                }

                if (_currentStep == 5) {
                  final sex = _sexController.text.trim();
                  final age = _ageController.text.trim();

                  bool hasError = false;
                  if (sex.isEmpty) {
                    _sexError = 'Please enter or select preferred sex';
                    hasError = true;
                  } else {
                    _sexError = null;
                  }

                  if (age.isEmpty) {
                    _ageError = 'Please enter or select preferred age';
                    hasError = true;
                  } else {
                    _ageError = null;
                  }

                  if (hasError) {
                    setState(() {});
                    return;
                  }
                }

                if (_currentStep < 5) {
                  setState(() => _currentStep++);
                } else {
                  _findMatches();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: Text(_currentStep < 5 ? 'Next' : 'Find My Matches'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    const themeGreen = Color(0xFF2D6A4F);
    const darkGreen = Color(0xFF1B4332);

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [darkGreen, themeGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: themeGreen.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Matches Found!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'We found ${_matches.length} matches for you.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _showingResults = false;
                  _currentStep = 0;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Reset',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Row(
            children: [
              const Text(
                'Top Picks',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.5),
              ),
              const Spacer(),
              Text(
                '${_matches.length} items found',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: _matches.isEmpty 
            ? _buildNoMatchesState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _matches.length,
                itemBuilder: (context, index) {
                  final breeder = _matches[index];
                  return _buildMatchCard(breeder, themeGreen);
                },
              ),
        ),
      ],
    );
  }

  Widget _buildNoMatchesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No matches found',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try widening your budget or search area.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(Breeder breeder, Color themeGreen) {
    String displayPrice = '';
    if (breeder.animals.isNotEmpty) {
      final prices = breeder.animals.map((a) => a.price).toList();
      final minPrice = prices.reduce((a, b) => a < b ? a : b);
      final maxPrice = prices.reduce((a, b) => a > b ? a : b);
      if (minPrice == maxPrice || minPrice == 0) {
        displayPrice = minPrice > 0 ? '₱${minPrice.toStringAsFixed(0)}' : '₱${breeder.price}';
      } else {
        displayPrice = '₱${minPrice.toStringAsFixed(0)} - ₱${maxPrice.toStringAsFixed(0)}';
      }
    } else {
      displayPrice = '₱${breeder.price}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileScreen(userId: breeder.userId)),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: breeder.animals.isNotEmpty
                    ? Image.network(
                        breeder.animals.first.imageUrl,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(height: 180, color: Colors.grey[200], child: const Icon(Icons.pets, size: 50, color: Colors.grey)),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      breeder.role,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (breeder.averageRating > 0)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            breeder.averageRating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          breeder.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        displayPrice,
                        style: TextStyle(color: themeGreen, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.pets_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        breeder.breed +
                            (breeder.gender.isNotEmpty ? ' • ${breeder.gender}' : '') +
                            (breeder.age.isNotEmpty ? ' • ${breeder.age}' : ''),
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          breeder.address,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                             Provider.of<NavigationProvider>(context, listen: false)
                                .setIndex(1, breeder: breeder);
                             Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: themeGreen),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('View on Map'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                              RestrictedAccessDialog.show(context, 'chat with breeders and traders');
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  breederId: breeder.userId,
                                  breederName: breeder.name,
                                  breederAvatarUrl: breeder.imageUrl,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Contact'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  const _PulseIcon();

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: const Icon(
        Icons.auto_awesome_rounded,
        size: 50,
        color: Color(0xFF2D6A4F),
      ),
    );
  }
}
