import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/breeder.dart';
import '../utils/animal_breeds.dart';
import '../widgets/limit_reached_card.dart';
import '../utils/system_ui_utils.dart';
import 'subscription_screen.dart';

class BreederPostingsScreen extends StatefulWidget {
  final Breeder? initialData;
  const BreederPostingsScreen({super.key, this.initialData});

  @override
  State<BreederPostingsScreen> createState() => _BreederPostingsScreenState();
}

class _BreederPostingsScreenState extends State<BreederPostingsScreen> {
  static const Color forestGreen = Color(0xFF2D6A4F);
  static const Color darkGreen = Color(0xFF1B4332);
  final _scrollController = ScrollController();
  final ValueNotifier<double> _appBarOpacity = ValueNotifier<double>(0.0);
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  String _userRole = 'Breeder';
  String? _avatarUrl;
  List<String> _existingAnimalImages = [];
  final List<File> _newAnimalImages = [];
  bool _isLimitReached = false;
  String? _selectedGender;
  final List<String> _genders = ['Male', 'Female'];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _appBarOpacity.value = (_scrollController.offset / 100).clamp(0.0, 1.0);
    });
    _prefillUserData();
    _checkConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        });
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      });
    }
  }

  Future<void> _prefillUserData() async {
    // If we have initial data (Edit Mode), use it immediately
    if (widget.initialData != null) {
      final data = widget.initialData!;
      setState(() {
        _nameController.text = data.name;
        _contactController.text = data.contactNumber;
        _descriptionController.text = data.description;
        if (_categories.contains(data.category)) {
          _selectedCategory = data.category;
          
          // Cascading breed prefill
          final breeds = animalBreeds[_selectedCategory] ?? [];
          if (breeds.contains(data.breed)) {
            _selectedBreed = data.breed;
            _breedController.text = '';
          } else if (data.breed.isNotEmpty) {
            _selectedBreed = 'Other';
            _breedController.text = data.breed;
          } else {
            _selectedBreed = null;
          }
        }
        _priceController.text = data.price;
        _ageController.text = data.age;
        if (_genders.contains(data.gender)) {
          _selectedGender = data.gender;
        }
        _avatarUrl = data.imageUrl;
        _existingAnimalImages = data.animals.map((a) => a.imageUrl).toList();
      });
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Preference: try to get from user_metadata first if not in edit mode
      if (widget.initialData == null) {
        final fullName = user.userMetadata?['full_name'] as String?;
        if (fullName != null) {
          _nameController.text = fullName;
        }
      }

      // Fetch additional details from create_account table
      try {
        final response = await Supabase.instance.client
            .from('create_account')
            .select('phone_number, full_name, role, avatar_url')
            .eq('id', user.id)
            .maybeSingle();
        
        if (response != null) {
          if (mounted) {
            setState(() {
              if (response['avatar_url'] != null) {
                _avatarUrl = response['avatar_url'];
              }
              
              // Only overwrite if not in edit mode
              if (widget.initialData == null) {
                if (response['full_name'] != null) {
                  _nameController.text = response['full_name'];
                }
                if (response['phone_number'] != null) {
                  _contactController.text = response['phone_number'];
                }
                if (response['role'] != null) {
                  _userRole = 'Breeder';
                }
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error prefilling user data: $e');
      }

      // Check listing limit after prefilling (only for NEW listings)
      if (widget.initialData == null && mounted) {
        final breederProvider = Provider.of<BreederProvider>(context, listen: false);
        final hasReachedLimit = await breederProvider.hasReachedListingLimit(user.id);

        if (hasReachedLimit && mounted) {
          setState(() => _isLimitReached = true);
        }
      }
    }
  }

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _breedController = TextEditingController();
  final _priceController = TextEditingController();
  final _ageController = TextEditingController();
  String _selectedCategory = 'Select Animals';
  String? _selectedBreed;

  final ImagePicker _picker = ImagePicker();

  final List<String> _categories = [
    'Select Animals',
    'Dog',
    'Cat',
    'Pig',
    'Goat',
    'Cow',
    'Carabao',
    'Horse',
    'Sheep',
    'Rabbit',
    'Chicken',
    'Betta Fish',
    'Koi Fish',
  ];

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _scrollController.dispose();
    _appBarOpacity.dispose();
    _nameController.dispose();
    _contactController.dispose();
    _descriptionController.dispose();
    _breedController.dispose();
    _priceController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _pickAnimalImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFiles.isNotEmpty) {
        setState(() {
          _newAnimalImages.addAll(pickedFiles.map((xFile) => File(xFile.path)));
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking images: $e')),
      );
    }
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingAnimalImages.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newAnimalImages.removeAt(index);
    });
  }

  Future<void> resetPostLimit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && mounted) {
      final breederProvider = Provider.of<BreederProvider>(context, listen: false);
      await breederProvider.fetchBreeders(silent: true);
      final hasLimit = await breederProvider.hasReachedListingLimit(user.id);
      if (mounted) {
        setState(() {
          _isLimitReached = hasLimit;
        });
        if (!_isLimitReached) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subscription active! Post limit reset. You can now submit your post.'),
              backgroundColor: forestGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _submitForm() async {
    if (_isLimitReached) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
      );
      if (result == true) {
        await resetPostLimit();
      }
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (_newAnimalImages.isEmpty && _existingAnimalImages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please add at least one photo of the animal'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final breederProvider = Provider.of<BreederProvider>(context, listen: false);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final bool isFirstPost = breederProvider.breeders.every((b) => b.userId != userId);

      final newBreeder = Breeder(
        id: widget.initialData?.id ?? '', // Preserve ID if editing
        userId: '', // Set by provider
        name: _nameController.text,
        category: _selectedCategory,
        type: 'Breeder',
        location: const LatLng(0, 0), // Don't set location automatically
        address: '', 
        description: _descriptionController.text,
        imageUrl: _avatarUrl ?? widget.initialData?.imageUrl ?? '',
        contactNumber: _contactController.text,
        price: _priceController.text,
        breed: _selectedBreed == 'Other' ? _breedController.text : (_selectedBreed ?? ''),
        age: _ageController.text,
        gender: _selectedGender ?? '',
        credentialsUrl: '', 
      );

      List<String> imagePaths = _newAnimalImages.map((f) => f.path).toList();

      try {
        await breederProvider.addBreeder(
          newBreeder, 
          imagePaths,
          existingAnimalUrls: _existingAnimalImages,
        );
        
        if (!mounted) return;
        
        _resetForm();
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: forestGreen, size: 32),
                SizedBox(width: 12),
                Text('Success', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(isFirstPost
                ? 'Your listing has been created! Since this is your first post, we will now take you to the map to pin your breeding location.'
                : 'Your breeder listing has been successfully ${_existingAnimalImages.isNotEmpty ? 'updated' : 'created'}.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(); // Close screen if it was pushed
                  }
                  
                  if (isFirstPost) {
                    Provider.of<NavigationProvider>(context, listen: false).setIndex(1); // Go to Map
                  }
                },
                child: Text(isFirstPost ? 'Continue to Map' : 'Great!', style: const TextStyle(color: forestGreen, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;

        if (e.toString().contains('LIMIT_REACHED')) {
          setState(() {
            _isLimitReached = true;
          });
          _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registration failed: ${e.toString()}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _resetForm() {
    setState(() {
      final savedName = _nameController.text;
      final savedContact = _contactController.text;

      _formKey.currentState?.reset();

      // Clear animal-specific fields
      _descriptionController.clear();
      _breedController.clear();
      _priceController.clear();
      _ageController.clear();
      _selectedCategory = 'Select Animals';
      _selectedBreed = null;
      _selectedGender = null;
      _newAnimalImages.clear();
      _existingAnimalImages.clear();

      // Restore basic info
      _nameController.text = savedName;
      _contactController.text = savedContact;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiUtils.getOverlayStyle(
        isDark: isDark,
        navBarColor: isDark ? const Color(0xFF14241B) : const Color(0xFFF5F7F5),
      ),
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF14241B) : const Color(0xFFF5F7F5),
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: ValueListenableBuilder<double>(
            valueListenable: _appBarOpacity,
            builder: (context, opacity, child) {
              return AppBar(
                title: Text(
                  widget.initialData != null ? 'Edit Breeder Listing' : 'Breeder Registration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: opacity > 0.5 ? (isDark ? Colors.white : darkGreen) : darkGreen,
                  ),
                ),
                elevation: opacity > 0.5 ? 2 : 0,
                backgroundColor: opacity > 0.5
                    ? (isDark ? const Color(0xFF1B3326) : Colors.white)
                    : Colors.transparent,
                surfaceTintColor: Colors.transparent,
                centerTitle: true,
                iconTheme: IconThemeData(
                  color: opacity > 0.5 ? (isDark ? Colors.white : forestGreen) : darkGreen,
                ),
              );
            },
          ),
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            children: [
              if (_isOffline) _buildOfflineBanner(),
              // Header Banner
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 60, 24, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1B4332), const Color(0xFF2D6A4F)]
                        : [const Color(0xFF2D6A4F), const Color(0xFF40916C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: forestGreen.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.pets_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'BREEDER PROGRAM',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.initialData != null ? 'Update Listing Details' : 'Join Breeder Community',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Showcase your breeders to thousands of verified buyers.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isLimitReached)
                        LimitReachedCard(
                          margin: const EdgeInsets.only(bottom: 20),
                          onUpgrade: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
                            );
                            if (result == true) {
                              await resetPostLimit();
                            }
                          },
                        ),

                      // Card 1: Owner Information
                      _buildFormCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('Owner Information', Icons.person_outline_rounded, forestGreen),
                            const SizedBox(height: 18),
                            _buildTextField(
                              controller: _nameController,
                              label: "Owner's Name",
                              icon: Icons.person_outline,
                              validator: (value) => value!.isEmpty ? 'Name is required' : null,
                              themeColor: forestGreen,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _contactController,
                              label: "Contact Number",
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Contact number is required';
                                if (value.length != 11) return 'Phone number must be exactly 11 digits';
                                return null;
                              },
                              themeColor: forestGreen,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Card 2: Animal Details
                      _buildFormCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('Animal Details', Icons.pets_outlined, forestGreen),
                            const SizedBox(height: 18),
                            _buildDropdown(forestGreen),
                            if (_selectedCategory != 'Select Animals') ...[
                              const SizedBox(height: 14),
                              _buildBreedDropdown(forestGreen),
                            ],
                            if (_selectedBreed == 'Other') ...[
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _breedController,
                                label: 'Specify Breed',
                                icon: Icons.edit_note_outlined,
                                validator: (value) => value!.isEmpty ? 'Please specify the breed' : null,
                                themeColor: forestGreen,
                              ),
                            ],
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _priceController,
                              label: 'Price for Breeding (₱)',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty ? 'Price is required' : null,
                              themeColor: forestGreen,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _ageController,
                              label: 'Age (e.g., 3 months, 2 years)',
                              icon: Icons.cake_outlined,
                              validator: (value) => value!.isEmpty ? 'Age is required' : null,
                              themeColor: forestGreen,
                            ),
                            const SizedBox(height: 14),
                            _buildGenderDropdown(forestGreen),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Card 3: Description
                      _buildFormCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('Description', Icons.description_outlined, forestGreen),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 4,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                hintText: 'Tell us about your breeding practices, health guarantees, vaccinations...',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAF8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: forestGreen, width: 2),
                                ),
                              ),
                              validator: (value) => value!.isEmpty ? 'Description is required' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Card 4: Animal Photos
                      _buildFormCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSectionHeader('Animal Photos', Icons.photo_library_outlined, forestGreen),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: forestGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_existingAnimalImages.length + _newAnimalImages.length} Photos',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: forestGreen),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Upload clear photos of your animal to attract buyers.',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 110,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  // Add Photos Button Card
                                  InkWell(
                                    onTap: _pickAnimalImages,
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      width: 110,
                                      height: 110,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        color: forestGreen.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: forestGreen.withValues(alpha: 0.3), width: 1.5),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo_rounded, color: forestGreen, size: 28),
                                          SizedBox(height: 6),
                                          Text(
                                            'Add Photos',
                                            style: TextStyle(color: forestGreen, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Existing Images
                                  ..._existingAnimalImages.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final url = entry.value;
                                    return Container(
                                      width: 110,
                                      height: 110,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                              onTap: () => _removeExistingImage(index),
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  // New Picked Images
                                  ..._newAnimalImages.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final file = entry.value;
                                    return Container(
                                      width: 110,
                                      height: 110,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                              onTap: () => _removeNewImage(index),
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: Consumer<BreederProvider>(
                          builder: (context, provider, _) {
                            return ElevatedButton(
                              onPressed: (provider.isLoading || _isOffline) ? null : _submitForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: forestGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: provider.isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _isOffline 
                                          ? 'No Internet Connection' 
                                          : (_isLimitReached ? 'Limit Reached' : (widget.initialData != null ? 'Update Breeder Listing' : 'Submit Breeder Registration')),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                                    ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard({required Widget child, required bool isDark}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B3326) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFFFEF2F2),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 16),
          SizedBox(width: 8),
          Text(
            'No Internet Connection',
            style: TextStyle(color: Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color themeColor) {
    return Row(
      children: [
        Icon(icon, color: themeColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: themeColor,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    required Color themeColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: themeColor, size: 20),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: themeColor, width: 2),
        ),
        labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey[700], fontSize: 13),
      ),
    );
  }

  Widget _buildDropdown(Color themeColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.category_outlined, color: themeColor, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          dropdownColor: isDark ? const Color(0xFF1B3326) : Colors.white,
          items: _categories.map((String category) {
            return DropdownMenuItem(
              value: category,
              child: Text(category, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _selectedCategory = newValue!;
              _selectedBreed = null;
              _breedController.clear();
            });
          },
        ),
      ),
    );
  }

  Widget _buildGenderDropdown(Color themeColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: _selectedGender,
          hint: Text('Select Gender', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[700], fontSize: 13)),
          validator: (value) => value == null ? 'Please select a gender' : null,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.transgender_rounded, color: themeColor, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          dropdownColor: isDark ? const Color(0xFF1B3326) : Colors.white,
          items: _genders.map((String gender) {
            return DropdownMenuItem(
              value: gender,
              child: Text(gender, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            );
          }).toList(),
          onChanged: (newValue) => setState(() => _selectedGender = newValue),
        ),
      ),
    );
  }

  Widget _buildBreedDropdown(Color themeColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final breeds = animalBreeds[_selectedCategory] ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: _selectedBreed,
          hint: Text('Select Breed', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[700], fontSize: 13)),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.pets_outlined, color: themeColor, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          validator: (value) => value == null ? 'Breed is required' : null,
          dropdownColor: isDark ? const Color(0xFF1B3326) : Colors.white,
          items: breeds.map((String breed) {
            return DropdownMenuItem(
              value: breed,
              child: Text(breed, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _selectedBreed = newValue;
              if (_selectedBreed != 'Other') {
                _breedController.clear();
              }
            });
          },
        ),
      ),
    );
  }
}
