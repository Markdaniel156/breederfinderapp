import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/breeder.dart';
import '../utils/animal_breeds.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/limit_reached_card.dart';
import '../utils/location_utils.dart';
import '../utils/system_ui_utils.dart';
import 'subscription_screen.dart';

class TraderPostingsScreen extends StatefulWidget {
  final Breeder? initialData;
  const TraderPostingsScreen({super.key, this.initialData});

  @override
  State<TraderPostingsScreen> createState() => _TraderPostingsScreenState();
}

class _TraderPostingsScreenState extends State<TraderPostingsScreen> {
  static const Color forestGreen = Color(0xFF2D6A4F);
  static const Color darkGreen = Color(0xFF1B4332);
  final _scrollController = ScrollController();
  final ValueNotifier<double> _appBarOpacity = ValueNotifier<double>(0.0);
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  String? _avatarUrl;
  List<String> _existingAnimalImages = [];
  List<String> _existingCredentialImages = [];
  bool _isLimitReached = false;

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
        _addressController.text = data.address;
        _contactController.text = data.contactNumber;
        if (_animalTypes.contains(data.category)) {
          _selectedAnimalType = data.category;

          // Cascading breed prefill
          final breeds = animalBreeds[_selectedAnimalType] ?? [];
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
        if (_genders.contains(data.gender)) {
          _selectedGender = data.gender;
        }
        _avatarUrl = data.imageUrl;
        _existingAnimalImages = data.animals.map((a) => a.imageUrl).toList();
        _existingCredentialImages = data.credentialUrls;
      });
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final fullName = user.userMetadata?['full_name'] as String?;
      if (fullName != null) {
        _nameController.text = fullName;
      }

      try {
        final response = await Supabase.instance.client
            .from('create_account')
            .select('phone_number, full_name, city_municipality, barangay, avatar_url')
            .eq('id', user.id)
            .single();

        if (mounted) {
          setState(() {
            if (response['avatar_url'] != null) {
              _avatarUrl = response['avatar_url'];
            }
            if (response['full_name'] != null) {
              _nameController.text = response['full_name'];
            }
            if (response['phone_number'] != null) {
              _contactController.text = response['phone_number'];
            }
            if (response['city_municipality'] != null && response['barangay'] != null) {
              _addressController.text = LocationUtils.sanitizeAddress("${response['barangay']}, ${response['city_municipality']}");
            }
          });
        }
      } catch (e) {
        debugPrint('Error prefilling trader data: $e');
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
  final _addressController = TextEditingController();
  final _breedController = TextEditingController();
  final _contactController = TextEditingController();
  final _priceController = TextEditingController();
  
  String? _selectedAnimalType;
  String? _selectedBreed;
  String? _selectedGender;
  final List<File> _newCredentialImages = [];
  final List<File> _newAnimalImages = [];
  final ImagePicker _picker = ImagePicker();

  final List<String> _animalTypes = [
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
  final List<String> _genders = ['Male', 'Female'];

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _scrollController.dispose();
    _appBarOpacity.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _breedController.dispose();
    _contactController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickCredentials() async {
    final totalCredentials = _existingCredentialImages.length + _newCredentialImages.length;
    if (totalCredentials >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can upload up to 3 credential photos only'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final remainingSlots = 3 - totalCredentials;
      if (remainingSlots == 1) {
        final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (image != null) {
          setState(() {
            _newCredentialImages.add(File(image.path));
          });
        }
      } else {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (pickedFiles.isNotEmpty) {
          setState(() {
            _newCredentialImages.addAll(
              pickedFiles.take(remainingSlots).map((x) => File(x.path)),
            );
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking credential image: $e')),
      );
    }
  }

  void _removeExistingCredential(int index) {
    setState(() {
      _existingCredentialImages.removeAt(index);
    });
  }

  void _removeNewCredential(int index) {
    setState(() {
      _newCredentialImages.removeAt(index);
    });
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
        SnackBar(content: Text('Error picking animal images: $e')),
      );
    }
  }

  void _removeExistingAnimalImage(int index) {
    setState(() {
      _existingAnimalImages.removeAt(index);
    });
  }

  void _removeNewAnimalImage(int index) {
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
      if (_newCredentialImages.isEmpty && _existingCredentialImages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload at least 1 credential document photo'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (_newAnimalImages.isEmpty && _existingAnimalImages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload at least 1 photo of the animal'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final breederProvider = Provider.of<BreederProvider>(context, listen: false);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final bool isFirstPost = breederProvider.breeders.every((b) => b.userId != userId);

      final newTrader = Breeder(
        id: widget.initialData?.id ?? '', // Preserve ID if editing
        userId: '', // Set by provider
        name: _nameController.text,
        category: _selectedAnimalType ?? 'Others',
        type: 'Trader',
        location: const LatLng(0, 0), // Don't set location automatically
        address: _addressController.text,
        description: '', 
        imageUrl: _avatarUrl ?? widget.initialData?.imageUrl ?? '',
        contactNumber: _contactController.text,
        price: _priceController.text,
        breed: _selectedBreed == 'Other' ? _breedController.text : (_selectedBreed ?? ''),
        gender: _selectedGender ?? '',
        credentialsUrl: '', 
      );

      List<String> imagePaths = _newAnimalImages.map((f) => f.path).toList();
      List<String> credentialPaths = _newCredentialImages.map((f) => f.path).toList();

      try {
        await breederProvider.addBreeder(
          newTrader, 
          imagePaths,
          credentialImagePaths: credentialPaths,
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
                Icon(Icons.check_circle_rounded, color: Colors.orange, size: 32),
                SizedBox(width: 12),
                Text('Success', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(isFirstPost
                ? 'Your listing has been created! Since this is your first post, we will now take you to the map to pin your business location.'
                : 'Your animal listing has been successfully ${_existingAnimalImages.isNotEmpty ? 'updated' : 'listed in AniMarket'}.'),
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
                child: const Text('Great!', style: TextStyle(color: forestGreen, fontWeight: FontWeight.bold, fontSize: 16)),
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
      // We do NOT clear name, address, or contact as they are part of "Trader Details"
      _breedController.clear();
      _priceController.clear();
      _selectedAnimalType = null;
      _selectedBreed = null;
      _selectedGender = null;
      _newCredentialImages.clear();
      _existingCredentialImages.clear();
      _newAnimalImages.clear();
      _existingAnimalImages.clear();
      _formKey.currentState?.reset();
    });
    // This will ensure name/contact/address are refilled if they were empty
    _prefillUserData();
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
                  widget.initialData != null ? 'Edit Trader Listing' : 'Trader Registration',
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
                              color: Colors.orange.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.storefront_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'TRADER PROGRAM',
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
                            widget.initialData != null ? 'Update Listing Details' : 'Trader Marketplace',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Post your animals for sale and connect directly with buyers.',
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

                      // Card 1: Trader Details
                      _buildFormCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('Trader Details', Icons.person_outline_rounded, forestGreen),
                            const SizedBox(height: 18),
                            _buildTextField(
                              controller: _nameController,
                              label: "Trader/Business Name",
                              icon: Icons.person_outline,
                              validator: (value) => value!.isEmpty ? 'Name is required' : null,
                              themeColor: forestGreen,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _addressController,
                              label: "Address",
                              icon: Icons.location_on_outlined,
                              validator: (value) => value!.isEmpty ? 'Address is required' : null,
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

                      // Card 2: Animal Information
                      _buildFormCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('Animal Information', Icons.pets_outlined, forestGreen),
                            const SizedBox(height: 18),
                            _buildDropdown(forestGreen),
                            if (_selectedAnimalType != null) ...[
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
                            if (!['Chicken'].contains(_selectedAnimalType)) ...[
                              const SizedBox(height: 14),
                              _buildGenderDropdown(forestGreen),
                            ],
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _priceController,
                              label: 'Selling Price (₱)',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty ? 'Price is required' : null,
                              themeColor: forestGreen,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Card 3: Credentials (Max 3)
                      _buildFormCard(
                        isDark: isDark,
                        child: _buildCredentialsPicker(isDark),
                      ),
                      const SizedBox(height: 18),

                      // Card 4: Animal Photos
                      _buildFormCard(
                        isDark: isDark,
                        child: _buildAnimalPhotosPicker(isDark),
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
                                          : (_isLimitReached ? 'Limit Reached' : (widget.initialData != null ? 'Update Trader Listing' : 'Submit Trader Registration')),
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

  Widget _buildCredentialsPicker(bool isDark) {
    final totalCredentials = _existingCredentialImages.length + _newCredentialImages.length;
    final bool canAddMore = totalCredentials < 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Credentials', Icons.badge_outlined, forestGreen),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (totalCredentials >= 3 ? Colors.orange : forestGreen).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalCredentials / 3 Photos',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: totalCredentials >= 3 ? Colors.orange[800] : forestGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Upload Health Certificate, Vet Clearance, Farm Permit or Proof of Source (max 3).',
          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (canAddMore)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: _pickCredentials,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: forestGreen.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: forestGreen.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded, color: forestGreen, size: 28),
                          SizedBox(height: 6),
                          Text(
                            'Add Credential',
                            style: TextStyle(
                              color: forestGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Existing Network Credentials
              ..._existingCredentialImages.asMap().entries.map((entry) {
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
                          onTap: () => _removeExistingCredential(index),
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
              // New Local Credentials
              ..._newCredentialImages.asMap().entries.map((entry) {
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
                          onTap: () => _removeNewCredential(index),
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
    );
  }

  Widget _buildAnimalPhotosPicker(bool isDark) {
    final totalAnimalPhotos = _existingAnimalImages.length + _newAnimalImages.length;

    return Column(
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
                '$totalAnimalPhotos ${totalAnimalPhotos == 1 ? 'Photo' : 'Photos'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: forestGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Upload clear photos of the animal for buyers to see.',
          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: _pickAnimalImages,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 110,
                    height: 110,
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
                          style: TextStyle(
                            color: forestGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Existing Network Animal Photos
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
                          onTap: () => _removeExistingAnimalImage(index),
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
              // New Local Animal Photos
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
                          onTap: () => _removeNewAnimalImage(index),
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
          initialValue: _selectedAnimalType,
          hint: Text('Select Animals', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[700], fontSize: 13)),
          validator: (value) => value == null ? 'Please select an animal type' : null,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.category_outlined, color: themeColor, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          dropdownColor: isDark ? const Color(0xFF1B3326) : Colors.white,
          items: _animalTypes.map((String type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _selectedAnimalType = newValue;
              _selectedBreed = null;
              _breedController.clear();
            });
          },
        ),
      ),
    );
  }

  Widget _buildBreedDropdown(Color themeColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final breeds = animalBreeds[_selectedAnimalType] ?? [];
    
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
}
