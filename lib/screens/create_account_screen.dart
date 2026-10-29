import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/system_ui_utils.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen>
    with TickerProviderStateMixin {
  // ── Theme ──────────────────────────────────────────────────────────────────
  static const _themeGreen = Color(0xFF2D6A4F);
  static const _darkGreen = Color(0xFF1B4332);
  static const _bgColor = Color(0xFFF5F7F5);

  // ── Step management ────────────────────────────────────────────────────────
  int _currentStep = 0;
  static const int _totalSteps = 4;
  final _pageController = PageController();

  late AnimationController _stepAnimController;

  // ── Form keys per step ─────────────────────────────────────────────────────
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();

  // ── Scroll controllers ─────────────────────────────────────────────────────
  final _scroll1 = ScrollController();
  final _scroll2 = ScrollController();
  final _scroll3 = ScrollController();
  final _scroll4 = ScrollController();

  // ── Text controllers ───────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _termsAccepted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _selectedIdType;
  File? _image;
  File? _idFrontImage;
  File? _idBackImage;
  File? _selfieImage;
  bool _isLoading = false;
  bool _isScanningFace = false;
  bool _isFaceVerified = false;

  final _picker = ImagePicker();
  late AnimationController _scanController;

  // ── Data ───────────────────────────────────────────────────────────────────
  final List<String> _idTypes = [
    'National ID', 'Drivers License', 'UMID (SSS/GSIS)', 'Voters ID', 'Postal ID'
  ];

  String? _selectedCity;
  String? _selectedBarangay;

  final List<String> _quintoDistritoCities = [
    'Binalbagan', 'Himamaylan City', 'Hinigaran', 'Isabela', 'La Castellana', 'Moises Padilla',
  ];

  final Map<String, List<String>> _barangays = {
    'Himamaylan City': ['Aguisan','Buenavista','Cabadiangan','Cabanbanan','Carabalan','Caradio-an','Libacao','Mahalang','Mambagaton','Nabali-an','San Antonio','Sara-et','Su-ay','Talaban','To-oy','Barangay I','Barangay II','Barangay III','Barangay IV'],
    'Binalbagan': ['Amontay','Bagroy','Bi-ao','Canmoros','Enclaro','Marina','Paglaum','Payao','Progreso','San Jose','San Juan','San Pedro','San Teodoro','San Vicente','Santo Rosario','Santol'],
    'Hinigaran': ['Anahaw','Aranda','Baga-as','Barangay I','Barangay II','Barangay III','Barangay IV','Bato','Calapi','Camalobalo','Camba-og','Cambugsa','Candumarao','Gargato','Himaya','Miranda','Nanunga','Narauis','Palayog','Paticui','Pilar','Quiwi'],
    'Isabela': ['Amin','Banogbanog','Bulad','Bungahin','Cabcab','Camangcamang','Camp Clark','Cansalongon','Guintubhan','Libas','Limalima','Makilignit','Mansablay','Maytubig','Panaquiao','Barangay 1','Barangay 2','Barangay 3','Barangay 4','Barangay 5','Barangay 6','Barangay 7','Barangay 8','Barangay 9','Riverside','Rumirang','San Agustin','Sebucawan','Sikatuna','Tinongan'],
    'La Castellana': ['Biaknabato','Cabacungan','Cabagnaan','Camandag','Lalagsan','Manghanoy','Mansalanao','Masulog','Nato','Puso','Robles','Sag-ang','Talaptap'],
    'Moises Padilla': ['Barangay 1','Barangay 2','Barangay 3','Barangay 4','Barangay 5','Barangay 6','Barangay 7','Crossing Magallon','Guinpana-an','Inolingan','Macagahay','Magallon Cadre','Montilla','Odiong','Quintin Remo'],
  };

  static const _stepMeta = [
    {'label': 'Account\nDetails',  'short': 'Account Details'},
    {'label': 'Location',          'short': 'Location'},
    {'label': 'ID\nVerification',  'short': 'ID Verification'},
    {'label': 'Terms &\nSubmit',   'short': 'Terms & Submit'},
  ];

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _stepAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _stepAnimController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scroll1.dispose(); _scroll2.dispose(); _scroll3.dispose(); _scroll4.dispose();
    _nameController.dispose(); _phoneController.dispose(); _emailController.dispose();
    _passwordController.dispose(); _confirmPasswordController.dispose();
    _scanController.dispose(); _stepAnimController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _goToStep(int step) {
    _stepAnimController.forward(from: 0);
    setState(() => _currentStep = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_image == null) {
        _showError('Please upload a profile photo');
        return;
      }
      if (!(_step1Key.currentState?.validate() ?? false)) {
        _showError('Please fill in all required fields');
        return;
      }
    }
    if (_currentStep == 1) {
      if (_selectedCity == null || _selectedBarangay == null) {
        _showError('Please select your city and barangay');
        return;
      }
    }
    if (_currentStep == 2) {
      if (_idFrontImage == null || _idBackImage == null) {
        _showError('Please upload front and back of your ID');
        return;
      }
      if (_selfieImage == null || !_isFaceVerified) {
        _showError('Please complete face verification');
        return;
      }
      if (_selectedIdType == null) {
        _showError('Please select an ID type');
        return;
      }
    }
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  // ── Image picking ──────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source, {String type = 'profile'}) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    if (type == 'selfie') {
      setState(() { _selfieImage = File(pickedFile.path); _isScanningFace = true; _isFaceVerified = false; });
      HapticFeedback.mediumImpact();
      _scanController.repeat(reverse: true);

      bool faceDetected = false;
      String? detectionError;
      try {
        final inputImage = InputImage.fromFilePath(pickedFile.path);
        final faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.1));
        final List<Face> faces = await faceDetector.processImage(inputImage);
        faceDetected = faces.isNotEmpty;
        await faceDetector.close();
      } catch (e) { detectionError = e.toString(); }

      await Future.delayed(const Duration(milliseconds: 2500));

      if (mounted) {
        _scanController.stop();
        if (faceDetected) {
          HapticFeedback.lightImpact();
          setState(() { _isScanningFace = false; _isFaceVerified = true; });
        } else {
          setState(() { _isScanningFace = false; _isFaceVerified = false; _selfieImage = null; });
          _showError(detectionError != null ? 'Verification system initializing. Try again.' : 'No face detected. Ensure your face is visible and well-lit.');
        }
      }
    } else {
      setState(() {
        if (type == 'profile') _image = File(pickedFile.path);
        else if (type == 'id_front') _idFrontImage = File(pickedFile.path);
        else if (type == 'id_back') _idBackImage = File(pickedFile.path);
      });
    }
  }

  void _showImagePickerSheet(BuildContext context, {String type = 'profile'}) {
    if (type == 'selfie') { _showFaceVerificationInstructions(); return; }
    final title = type == 'id_front' ? 'Front of ID' : type == 'id_back' ? 'Back of ID' : 'Account Photo';
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (bc) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25))),
        child: SafeArea(child: Wrap(children: [
          Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 15), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
          ListTile(leading: const Icon(Icons.photo_library, color: _themeGreen), title: const Text('Photo Library'), onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery, type: type); }),
          ListTile(leading: const Icon(Icons.photo_camera, color: _themeGreen), title: const Text('Camera'), onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera, type: type); }),
          const SizedBox(height: 15),
        ])),
      ),
    );
  }

  void _showFaceVerificationInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Column(children: [
          Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: _themeGreen.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.face_unlock_rounded, color: _themeGreen, size: 40)),
          const SizedBox(height: 15),
          const Text('Face Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Let\'s verify your identity', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          _instructionTile(Icons.face_retouching_off_rounded, 'Remove face masks or face shields'),
          _instructionTile(Icons.monetization_on_outlined, 'Remove sunglasses or hats'),
          _instructionTile(Icons.light_mode_rounded, 'Ensure you are in a well-lit area'),
          _instructionTile(Icons.center_focus_strong_rounded, 'Position your face in the center'),
        ]),
        actions: [Row(children: [
          Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
          Expanded(child: ElevatedButton(
            onPressed: () { Navigator.pop(context); _pickImage(ImageSource.camera, type: 'selfie'); },
            style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('READY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )),
        ])],
      ),
    );
  }

  Widget _instructionTile(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _themeGreen.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: _themeGreen)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87))),
      ]),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      elevation: 0, behavior: SnackBarBehavior.floating, backgroundColor: Colors.transparent,
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFC72C41), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14))),
        ]),
      ),
    ));
  }

  Future<void> _signUp() async {
    if (!_termsAccepted) { _showError('Please accept the Terms and Conditions'); return; }
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      String? avatarUrl, idFrontUrl, idBackUrl, selfieImageUrl, fcmToken;
      try {
        await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) { debugPrint('FCM token failed: $e'); }

      final AuthResponse res = await supabase.auth.signUp(email: _emailController.text.trim(), password: _passwordController.text, data: {'full_name': _nameController.text.trim()});
      final userId = res.user?.id;
      if (userId == null) throw Exception('Signup failed: No user ID returned');

      if (_image != null) {
        final fn = '$userId/avatar.jpg';
        await supabase.storage.from('avatars').upload(fn, _image!, fileOptions: const FileOptions(upsert: true));
        avatarUrl = supabase.storage.from('avatars').getPublicUrl(fn);
      }
      for (final entry in [('id_front', _idFrontImage), ('id_back', _idBackImage), ('selfie', _selfieImage)]) {
        final file = entry.$2;
        if (file != null) {
          final fn = '$userId/${entry.$1}.jpg';
          await supabase.storage.from('verifications').upload(fn, file, fileOptions: const FileOptions(upsert: true));
          final url = supabase.storage.from('verifications').getPublicUrl(fn);
          if (entry.$1 == 'id_front') idFrontUrl = url;
          else if (entry.$1 == 'id_back') idBackUrl = url;
          else selfieImageUrl = url;
        }
      }

      await supabase.from('create_account').upsert({
        'id': userId, 'email': _emailController.text.trim(), 'full_name': _nameController.text.trim(),
        'phone_number': _phoneController.text.trim(), 'city_municipality': _selectedCity, 'barangay': _selectedBarangay,
        'role': 'CUSTOMER', 'id_type': _selectedIdType, 'avatar_url': avatarUrl, 'id_front_url': idFrontUrl,
        'id_back_url': idBackUrl, 'selfie_image_url': selfieImageUrl, 'verification_status': 'PENDING', 'fcm_token': fcmToken,
      });

      if (res.user != null && mounted) _showSuccessDialog();
    } on AuthException catch (e) { if (mounted) _showError(e.message); }
    on StorageException catch (e) { if (mounted) _showError('Storage error: ${e.message}'); }
    catch (e) { if (mounted) _showError('Error: ${e.toString()}'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: _themeGreen.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: _themeGreen, size: 52)),
          const SizedBox(height: 22),
          const Text('Account Created!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _darkGreen)),
          const SizedBox(height: 10),
          Text('Welcome to Breeder Finder! Your account has been created successfully. Please log in with your credentials.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.5), height: 1.5)),
          const SizedBox(height: 28),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                try {
                  await Supabase.instance.client.auth.signOut();
                } catch (e) {
                  debugPrint('Sign out error: $e');
                }
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: const Text('PROCEED TO LOGIN', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showTermsSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (context, sc) => Column(children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), children: [
            const Icon(Icons.shield_rounded, size: 60, color: Color(0xFF1976D2)),
            const SizedBox(height: 16),
            const Center(child: Text('Terms & Data Privacy Agreement', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1976D2)))),
            const SizedBox(height: 8),
            const Center(child: Text('In compliance with Republic Act No. 10173 (Data Privacy Act of 2012)', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey))),
            const SizedBox(height: 24),
            _privacyCard(icon: Icons.info_outline_rounded, title: '1. Information We Collect', content: 'We collect personal information including your full name, contact details, address, government/breeder credentials, and animal listings submitted during registration and platform usage. This data is collected to establish secure, verified connections within the Breeder Finder ecosystem.'),
            const SizedBox(height: 16),
            _privacyCard(icon: Icons.security_rounded, title: '2. Purpose & Data Processing', content: 'Your data is processed strictly for platform verification, matching breeders with responsible pet seekers, administrative communications, and ensuring compliance with local animal welfare and agricultural standards.'),
            const SizedBox(height: 16),
            _privacyCard(icon: Icons.verified_user_outlined, title: '3. Your Rights Under RA 10173', child: Column(children: [
              _rightItem('Right to be informed regarding data collection and processing activities.'),
              _rightItem('Right to access your personal data and transaction history.'),
              _rightItem('Right to correct or update inaccurate or outdated information.'),
              _rightItem('Right to suspend, withdraw, or request blocking/deletion of your personal data.'),
              _rightItem('Right to data portability and indemnification for damages due to inaccurate or unauthorized data use.'),
            ])),
            const SizedBox(height: 16),
            _privacyCard(icon: Icons.gavel_rounded, title: '4. Terms of Use & User Conduct', content: 'By using Breeder Finder, you agree to provide truthful credentials, adhere to ethical animal breeding guidelines, maintain respectful communications, and refrain from fraudulent or harmful activities. Violation may result in immediate account suspension or termination.'),
            const SizedBox(height: 16),
            _privacyCard(icon: Icons.help_outline_rounded, title: '5. Contact & Data Protection Officer', content: 'For privacy concerns, data requests, or inquiries regarding these Terms & Conditions, please contact our Data Protection Officer through the app support center or via our official support channels.'),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('I UNDERSTAND & AGREE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
            const SizedBox(height: 20),
          ])),
        ]),
      ),
    );
  }

  Widget _privacyCard({required IconData icon, required String title, String? content, Widget? child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade100), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF1976D2).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF1976D2), size: 24)),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
        const SizedBox(height: 10),
        if (content != null) Text(content, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5)),
        if (child != null) child,
      ]),
    );
  }

  Widget _rightItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87))),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : _bgColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : _bgColor,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildStepIndicator(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                    _buildStep4(),
                  ],
                ),
              ),
              _buildNavBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final stepShort = _stepMeta[_currentStep]['short'] as String;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 20, 10),
      child: Row(children: [
        IconButton(
          onPressed: _currentStep > 0 ? _prevStep : () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))]),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _darkGreen),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Step ${_currentStep + 1} of $_totalSteps', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _themeGreen.withValues(alpha: 0.7), letterSpacing: 0.5)),
          Text(stepShort, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _darkGreen, letterSpacing: -0.3)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: _themeGreen, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: _themeGreen.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pets, color: Colors.white, size: 13),
            SizedBox(width: 5),
            Text('Breeder Finder', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          ]),
        ),
      ]),
    );
  }

  // ── Step Indicator ─────────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.055), blurRadius: 16, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: List.generate(_totalSteps * 2 - 1, (i) {
          // Even indices = step circles, Odd indices = connectors
          if (i.isOdd) {
            final stepIndex = i ~/ 2;
            final isDone = stepIndex < _currentStep;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 2,
                  decoration: BoxDecoration(
                    color: isDone ? _themeGreen : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            );
          }

          final stepIndex = i ~/ 2;
          final isActive = stepIndex == _currentStep;
          final isDone = stepIndex < _currentStep;

          return GestureDetector(
            onTap: () { if (isDone) _goToStep(stepIndex); },
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isActive ? 38 : 32,
                height: isActive ? 38 : 32,
                decoration: BoxDecoration(
                  color: isDone ? _themeGreen : isActive ? _themeGreen : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone || isActive ? _themeGreen : Colors.grey.shade300,
                    width: isActive ? 2.5 : 1.5,
                  ),
                  boxShadow: isActive ? [BoxShadow(color: _themeGreen.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 1)] : [],
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                      : Text('${stepIndex + 1}', style: TextStyle(color: isActive ? Colors.white : Colors.grey.shade400, fontSize: isActive ? 14 : 12, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                width: 58,
                child: Text(
                  _stepMeta[stepIndex]['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                    color: isActive ? _themeGreen : isDone ? _themeGreen.withValues(alpha: 0.65) : Colors.grey.shade400,
                    height: 1.2,
                  ),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  // ── Bottom Nav Bar ─────────────────────────────────────────────────────────
  Widget _buildNavBar() {
    final isLast = _currentStep == _totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Row(children: [
        if (_currentStep > 0)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _prevStep,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _themeGreen.withValues(alpha: 0.4), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: const Row(children: [
                  Icon(Icons.arrow_back_rounded, size: 17, color: _themeGreen),
                  SizedBox(width: 6),
                  Text('Back', style: TextStyle(color: _themeGreen, fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
              ),
            ),
          ),
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : (isLast ? _signUp : _nextStep),
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeGreen, foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200, elevation: 8,
                shadowColor: _themeGreen.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isLoading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(isLast ? 'Create Account' : 'Continue', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                const SizedBox(width: 8),
                Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 18),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // STEP PAGES
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      controller: _scroll1,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Form(
        key: _step1Key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _stepSubtitle('Set up your profile photo and basic account information.'),
          const SizedBox(height: 18),

          _card(child: Row(children: [
            GestureDetector(
              onTap: () => _showImagePickerSheet(context),
              child: Stack(children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _image != null ? _themeGreen : Colors.grey.shade300, width: 2)),
                  child: CircleAvatar(
                    radius: 38, backgroundColor: _bgColor,
                    backgroundImage: _image != null ? FileImage(_image!) : null,
                    child: _image == null ? Icon(Icons.add_a_photo_outlined, size: 24, color: _themeGreen.withValues(alpha: 0.5)) : null,
                  ),
                ),
                Positioned(bottom: 2, right: 2, child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: _themeGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 11),
                )),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Profile Photo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _darkGreen)),
              const SizedBox(height: 4),
              Text('Tap to upload a clear photo of yourself', style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45), height: 1.4)),
              if (_image != null) ...[
                const SizedBox(height: 6),
                const Row(children: [
                  Icon(Icons.check_circle_rounded, color: _themeGreen, size: 13),
                  SizedBox(width: 4),
                  Text('Photo uploaded', style: TextStyle(fontSize: 11, color: _themeGreen, fontWeight: FontWeight.w600)),
                ]),
              ],
            ])),
          ])),

          const SizedBox(height: 12),
          _card(child: Column(children: [
            _field(hint: 'Full Name', icon: Icons.person_outline_rounded, controller: _nameController, validator: (v) => v!.isEmpty ? 'Name required' : null),
            const SizedBox(height: 12),
            _field(hint: 'Email Address', icon: Icons.alternate_email_rounded, controller: _emailController, keyboardType: TextInputType.emailAddress, validator: (v) => (v!.isEmpty || !v.contains('@')) ? 'Invalid email' : null),
            const SizedBox(height: 12),
            _field(hint: 'Phone Number', icon: Icons.phone_android_rounded, controller: _phoneController, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], validator: (v) => v!.length != 11 ? 'Enter 11 digits' : null),
            const SizedBox(height: 12),
            _field(hint: 'Password', icon: Icons.lock_outline_rounded, controller: _passwordController, isPassword: _obscurePassword, suffixIcon: _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, onSuffixPressed: () => setState(() => _obscurePassword = !_obscurePassword), validator: (v) => v!.length < 6 ? 'Min 6 characters' : null),
            const SizedBox(height: 12),
            _field(hint: 'Confirm Password', icon: Icons.lock_clock_outlined, controller: _confirmPasswordController, isPassword: _obscureConfirmPassword, suffixIcon: _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, onSuffixPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword), validator: (v) { if (v == null || v.isEmpty) return 'Confirm your password'; if (v != _passwordController.text) return 'Passwords do not match'; return null; }),
          ])),

          const SizedBox(height: 16),
          _loginLink(),
        ]),
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      controller: _scroll2,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepSubtitle('Select your municipality and barangay.'),
        const SizedBox(height: 18),

        _cardWithHeader(
          headerIcon: Icons.location_on_outlined,
          headerTitle: 'Your Location',
          child: Form(key: _step2Key, child: Column(children: [
            _dropdown(hint: 'City / Municipality', icon: Icons.location_city_rounded, value: _selectedCity, items: _quintoDistritoCities, onChanged: (val) => setState(() { _selectedCity = val; _selectedBarangay = null; })),
            const SizedBox(height: 12),
            _dropdown(hint: 'Barangay', icon: Icons.map_rounded, value: _selectedBarangay, items: _selectedCity != null ? _barangays[_selectedCity] ?? [] : [], onChanged: (val) => setState(() => _selectedBarangay = val)),
          ])),
        ),
      ]),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      controller: _scroll3,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Form(
        key: _step3Key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _stepSubtitle('Upload a valid government ID and complete face verification.'),
          const SizedBox(height: 18),

          _cardWithHeader(
            headerIcon: Icons.assignment_ind_outlined,
            headerTitle: 'ID Type',
            child: _dropdown(hint: 'Select ID Type', icon: Icons.assignment_ind_outlined, value: _selectedIdType, items: _idTypes, onChanged: (val) => setState(() => _selectedIdType = val)),
          ),

          const SizedBox(height: 12),

          _cardWithHeader(
            headerIcon: Icons.photo_library_outlined,
            headerTitle: 'ID Photos',
            child: Row(children: [
              Expanded(child: _idTile(label: 'Front of ID', image: _idFrontImage, onTap: () => _showImagePickerSheet(context, type: 'id_front'))),
              const SizedBox(width: 12),
              Expanded(child: _idTile(label: 'Back of ID', image: _idBackImage, onTap: () => _showImagePickerSheet(context, type: 'id_back'))),
            ]),
          ),

          const SizedBox(height: 12),

          _cardWithHeader(
            headerIcon: Icons.face_unlock_rounded,
            headerTitle: 'Face Verification',
            child: Row(children: [
              GestureDetector(
                onTap: _isScanningFace ? null : () => _showImagePickerSheet(context, type: 'selfie'),
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      color: _bgColor, shape: BoxShape.circle,
                      border: Border.all(color: _isFaceVerified ? _themeGreen : (_isScanningFace ? _themeGreen.withValues(alpha: 0.5) : Colors.grey.shade200), width: _isFaceVerified ? 2.5 : 1.5),
                      boxShadow: _isFaceVerified ? [BoxShadow(color: _themeGreen.withValues(alpha: 0.15), blurRadius: 10, spreadRadius: 1)] : [],
                    ),
                    child: ClipOval(child: Stack(children: [
                      if (_selfieImage != null)
                        Opacity(opacity: _isScanningFace ? 0.5 : 1.0, child: Image.file(_selfieImage!, fit: BoxFit.cover, width: 90, height: 90))
                      else
                        Center(child: Icon(Icons.face_unlock_rounded, size: 28, color: _themeGreen.withValues(alpha: 0.5))),
                      if (_isScanningFace)
                        AnimatedBuilder(
                          animation: _scanController,
                          builder: (_, __) => Align(
                            alignment: Alignment(0, -1.0 + (2.0 * _scanController.value)),
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: _themeGreen,
                                boxShadow: [
                                  BoxShadow(
                                    color: _themeGreen.withValues(alpha: 0.8),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                    ])),
                  ),
                  if (_isScanningFace) SizedBox(width: 90, height: 90, child: CircularProgressIndicator(valueColor: const AlwaysStoppedAnimation<Color>(_themeGreen), strokeWidth: 2.5)),
                  if (_isFaceVerified && !_isScanningFace)
                    Positioned(bottom: 2, right: 2, child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: _themeGreen, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                    )),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Selfie Scan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _darkGreen)),
                  if (_isFaceVerified) ...[
                    const SizedBox(width: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: _themeGreen, borderRadius: BorderRadius.circular(8)), child: const Text('VERIFIED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(
                  _isScanningFace ? 'Analyzing your face...' : _isFaceVerified ? 'Identity verified successfully' : 'Tap circle to take a selfie for verification',
                  style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.45), height: 1.4),
                ),
                if (!_isFaceVerified && !_isScanningFace) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showImagePickerSheet(context, type: 'selfie'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: _themeGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _themeGreen.withValues(alpha: 0.25))),
                      child: const Text('Scan My Face', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _themeGreen)),
                    ),
                  ),
                ],
              ])),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildStep4() {
    return SingleChildScrollView(
      controller: _scroll4,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepSubtitle('Review your information and accept the terms to finish.'),
        const SizedBox(height: 18),

        _cardWithHeader(
          headerIcon: Icons.summarize_outlined,
          headerTitle: 'Your Summary',
          child: Column(children: [
            _summaryRow(Icons.person_outline_rounded, 'Name', _nameController.text.isEmpty ? '—' : _nameController.text),
            _summaryRow(Icons.alternate_email_rounded, 'Email', _emailController.text.isEmpty ? '—' : _emailController.text),
            _summaryRow(Icons.phone_android_rounded, 'Phone', _phoneController.text.isEmpty ? '—' : _phoneController.text),
            _summaryRow(Icons.location_city_rounded, 'City', _selectedCity ?? '—'),
            _summaryRow(Icons.map_rounded, 'Barangay', _selectedBarangay ?? '—'),
            _summaryRow(Icons.assignment_ind_outlined, 'ID Type', _selectedIdType ?? '—'),
            _summaryRow(Icons.photo_camera_outlined, 'Profile Photo', _image != null ? 'Uploaded ✓' : 'Not uploaded'),
            _summaryRow(Icons.face_unlock_rounded, 'Face Verification', _isFaceVerified ? 'Verified ✓' : 'Not verified'),
          ]),
        ),

        const SizedBox(height: 12),

        GestureDetector(
          onTap: () => setState(() => _termsAccepted = !_termsAccepted),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _termsAccepted ? _themeGreen.withValues(alpha: 0.4) : Colors.grey.shade200, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: _termsAccepted ? _themeGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _termsAccepted ? _themeGreen : Colors.grey.shade300, width: 1.5),
                ),
                child: _termsAccepted ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null,
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Terms & Conditions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _darkGreen)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _showTermsSheet,
                  child: const Text('Read our Data Privacy Agreement →', style: TextStyle(fontSize: 11, color: _themeGreen, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                ),
              ])),
            ]),
          ),
        ),

        const SizedBox(height: 16),
        _loginLink(),
      ]),
    );
  }

  // ── Reusable widgets ───────────────────────────────────────────────────────
  Widget _stepSubtitle(String text) => Text(text, style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45), height: 1.4));

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6))]),
      child: child,
    );
  }

  Widget _cardWithHeader({required IconData headerIcon, required String headerTitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 11),
          decoration: BoxDecoration(
            color: _themeGreen.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Row(children: [
            Icon(headerIcon, color: _themeGreen, size: 16),
            const SizedBox(width: 8),
            Text(headerTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _darkGreen, letterSpacing: 0.1)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  Widget _idTile({required String label, required File? image, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: 0.5), letterSpacing: 0.3)),
        const SizedBox(height: 8),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _bgColor, 
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: image != null ? _themeGreen : Colors.grey.shade300, width: image != null ? 2 : 1),
            boxShadow: image != null ? [BoxShadow(color: _themeGreen.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: image != null
              ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(image, fit: BoxFit.cover, width: double.infinity))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _themeGreen.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.add_a_photo_rounded, size: 24, color: _themeGreen),
            ),
            const SizedBox(height: 8),
            Text('Tap to Upload', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _themeGreen.withValues(alpha: 0.7))),
          ]),
        ),
        if (image != null) ...[
          const SizedBox(height: 6),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_rounded, color: _themeGreen, size: 14),
            SizedBox(width: 4),
            Text('Photo Uploaded', style: TextStyle(fontSize: 11, color: _themeGreen, fontWeight: FontWeight.w700)),
          ]),
        ],
      ]),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    final isCheck = value.endsWith('✓');
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _themeGreen.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 13, color: _themeGreen)),
        const SizedBox(width: 10),
        Text('$label:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black.withValues(alpha: 0.4))),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isCheck ? _themeGreen : value == '—' ? Colors.grey.shade400 : _darkGreen), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _loginLink() {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: RichText(text: TextSpan(
          style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.4)),
          children: const [
            TextSpan(text: 'Already a member? '),
            TextSpan(text: 'Sign In', style: TextStyle(color: _themeGreen, fontWeight: FontWeight.w800)),
          ],
        )),
      ),
    );
  }

  Widget _field({
    required String hint, required IconData icon, bool isPassword = false,
    IconData? suffixIcon, VoidCallback? onSuffixPressed, TextEditingController? controller,
    String? Function(String?)? validator, TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller, obscureText: isPassword, validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: keyboardType, inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: _darkGreen, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 14),
        prefixIcon: Icon(icon, color: _themeGreen, size: 19),
        suffixIcon: suffixIcon != null ? IconButton(icon: Icon(suffixIcon, color: Colors.grey.shade400, size: 19), onPressed: onSuffixPressed) : null,
        filled: true, fillColor: _bgColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _themeGreen, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
    );
  }

  Widget _dropdown({
    required String hint, required IconData icon, required String? value,
    required List<String> items, required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value, isExpanded: true,
      style: const TextStyle(fontSize: 14, color: _darkGreen, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 14),
        prefixIcon: Icon(icon, color: _themeGreen, size: 19),
        filled: true, fillColor: _bgColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _themeGreen, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      ),
      validator: (val) => val == null ? 'Selection required' : null,
      onChanged: onChanged,
      items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
    );
  }
}