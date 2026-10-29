import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApplySellerScreen extends StatefulWidget {
  const ApplySellerScreen({super.key});

  @override
  State<ApplySellerScreen> createState() => _ApplySellerScreenState();
}

class _ApplySellerScreenState extends State<ApplySellerScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedRole;
  bool _isLoading = false;
  int _currentStep = 0;

  String? _selectedIdType;
  File? _idFrontImage;
  File? _idBackImage;
  final List<File> _proofImages = [];
  final _experienceController = TextEditingController();
  final _sourceInfoController = TextEditingController();
  final _picker = ImagePicker();

  final List<String> _roles = ['BREEDER', 'TRADER', 'BREEDER AND TRADER'];
  final List<String> _idTypes = [
    'National ID', 'Drivers License', 'UMID (SSS/GSIS)', 'Voters ID', 'Postal ID'
  ];
  final Map<String, String> _roleDescriptions = {
    'BREEDER': 'Focuses on breeding animals and finding them new homes. Requires proof of ownership and breeding experience.',
    'TRADER': 'Involved in the buying and selling of animals. Requires proof of animal source/handling and trading experience.',
    'BREEDER AND TRADER': 'Combines both breeding and trading activities. Requires comprehensive documentation for both.',
  };

  static const _themeGreen = Color(0xFF2D6A4F);
  static const _darkGreen = Color(0xFF1B4332);
  static const _bgColor = Color(0xFFF5F7F5);

  bool _isCheckingPending = true;
  bool _isPendingReview = false;
  String? _pendingRole;

  @override
  void initState() {
    super.initState();
    _checkPendingApplication();
  }

  Future<void> _checkPendingApplication() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final pendingApp = await Supabase.instance.client
            .from('seller_applications')
            .select('role_applied, status')
            .eq('user_id', user.id)
            .eq('status', 'PENDING')
            .maybeSingle();

        if (pendingApp != null && mounted) {
          setState(() {
            _isPendingReview = true;
            _pendingRole = pendingApp['role_applied']?.toString();
          });
        }
      } catch (e) {
        debugPrint('Error checking pending application in ApplySellerScreen: $e');
      }
    }
    if (mounted) {
      setState(() => _isCheckingPending = false);
    }
  }

  @override
  void dispose() {
    _experienceController.dispose();
    _sourceInfoController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    if (type == 'proof') {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        setState(() {
          _proofImages.addAll(pickedFiles.map((xFile) => File(xFile.path)));
        });
      }
    } else {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          if (type == 'id_front') _idFrontImage = File(pickedFile.path);
          if (type == 'id_back') _idBackImage = File(pickedFile.path);
        });
      }
    }
  }

  void _removeProofImage(int index) {
    setState(() {
      _proofImages.removeAt(index);
    });
  }

  Future<void> _submitApplication() async {
    if (_selectedRole == null || _selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your role and ID type')),
      );
      return;
    }

    if (_idFrontImage == null || _idBackImage == null || _proofImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload all required photos')),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      String? idFrontUrl;
      String? idBackUrl;
      final List<String> proofUrls = [];

      // Upload ID Front
      final idFrontPath = '${user.id}/applications/id_front_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('verifications').upload(idFrontPath, _idFrontImage!, fileOptions: const FileOptions(upsert: true));
      idFrontUrl = supabase.storage.from('verifications').getPublicUrl(idFrontPath);

      // Upload ID Back
      final idBackPath = '${user.id}/applications/id_back_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('verifications').upload(idBackPath, _idBackImage!, fileOptions: const FileOptions(upsert: true));
      idBackUrl = supabase.storage.from('verifications').getPublicUrl(idBackPath);

      // Upload Proof Images
      for (int i = 0; i < _proofImages.length; i++) {
        final proofPath = '${user.id}/applications/proof_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('verifications').upload(
          proofPath, 
          _proofImages[i], 
          fileOptions: const FileOptions(upsert: true)
        );
        final url = supabase.storage.from('verifications').getPublicUrl(proofPath);
        proofUrls.add(url);
      }

      // Insert into seller_applications table
      await supabase.from('seller_applications').insert({
        'user_id': user.id,
        'role_applied': _selectedRole,
        'id_type': _selectedIdType,
        'id_front_url': idFrontUrl,
        'id_back_url': idBackUrl,
        'proof_url': proofUrls.join(','),
        'experience': _experienceController.text.trim(),
        'source_info': _sourceInfoController.text.trim(),
        'status': 'PENDING',
      });

      // Update role to pending or just keep as customer until admin approves?
      // For now, let's keep role as CUSTOMER until admin review.

      if (mounted) {
        final success = await _showSuccessDialog();
        if (success == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting application: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool?> _showSuccessDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _themeGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.access_time_rounded, color: _themeGreen, size: 52),
            ),
            const SizedBox(height: 22),
            const Text(
              'Submitted!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _darkGreen),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your application has been submitted for admin review. You will be notified once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _themeGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('OKAY', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPending || _isLoading) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: const Center(child: CircularProgressIndicator(color: _themeGreen)),
      );
    }

    if (_isPendingReview) {
      return Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Application Status',
            style: TextStyle(color: _darkGreen, fontWeight: FontWeight.bold, fontSize: 17),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _darkGreen),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildPendingReviewView(),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _currentStep == 0 ? 'Apply for Breeder or Seller' : 'Requirements',
          style: const TextStyle(
            color: _darkGreen, 
            fontWeight: FontWeight.bold, 
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _darkGreen),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep = 0);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _currentStep == 0 ? _buildRoleSelection() : _buildRequirementsForm(),
        ),
      ),
      bottomNavigationBar: _currentStep == 0 ? null : _buildSubmitButton(),
    );
  }

  Widget _buildPendingReviewView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 70),
            ),
            const SizedBox(height: 28),
            const Text(
              'Application Under Review',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _darkGreen),
            ),
            const SizedBox(height: 14),
            Text(
              'Your application to become a ${_pendingRole ?? 'Breeder or Trader'} has been submitted and is currently being reviewed by the admin. You will be notified once approved.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _themeGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('BACK TO HOME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Your Role',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _darkGreen),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the role you want to apply for.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 32),
        ..._roles.map((role) => _roleOption(role)),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _selectedRole == null ? null : () => setState(() => _currentStep = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementsForm() {
    final isTrader = _selectedRole == 'TRADER' || _selectedRole == 'BREEDER AND TRADER';
    final isBreeder = _selectedRole == 'BREEDER' || _selectedRole == 'BREEDER AND TRADER';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('1. ID Type'),
        _sectionSubtitle('Select the type of government ID you will upload.'),
        const SizedBox(height: 12),
        _dropdown(
          hint: 'Select ID Type',
          icon: Icons.assignment_ind_outlined,
          value: _selectedIdType,
          items: _idTypes,
          onChanged: (val) => setState(() => _selectedIdType = val),
        ),

        const SizedBox(height: 32),
        _sectionTitle('2. Valid Government ID'),
        _sectionSubtitle('Upload a clear photo of the front and back of your ID.'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _uploadTile(
                label: 'Front of ID',
                file: _idFrontImage,
                onTap: () => _pickImage('id_front'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _uploadTile(
                label: 'Back of ID',
                file: _idBackImage,
                onTap: () => _pickImage('id_back'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),
        _sectionTitle(_selectedRole == 'BREEDER AND TRADER' ? '3. Proof of Ownership & Source' : (isTrader ? '3. Proof of Animal Source' : '3. Proof of Animal Ownership')),
        _sectionSubtitle(_selectedRole == 'BREEDER AND TRADER' 
          ? 'Upload photos of animals you own and those you handle for trading.'
          : (isTrader ? 'Upload photos of animals you are currently selling or handling.' : 'Upload clear photos of the animals you currently own.')),
        const SizedBox(height: 12),
        _buildMultiImageUpload(
          label: _selectedRole == 'BREEDER AND TRADER' ? 'Upload Proof Photos' : (isTrader ? 'Upload Source Photos' : 'Upload Ownership Photos'),
          files: _proofImages,
          onTap: () => _pickImage('proof'),
          onRemove: _removeProofImage,
        ),

        if (isTrader) ...[
          const SizedBox(height: 24),
          _sectionTitle('Source Information'),
          _sectionSubtitle('Describe your animal source or supplier (required for traders).'),
          const SizedBox(height: 12),
          _textField(
            controller: _sourceInfoController,
            hint: 'e.g. Local farm supplier in Binalbagan...',
            maxLines: 2,
            validator: (value) => (value == null || value.isEmpty) ? 'Source information is required' : null,
          ),
        ],

        const SizedBox(height: 32),
        _sectionTitle(_selectedRole == 'BREEDER AND TRADER' ? '4. Experience' : (isBreeder ? '4. Breeding Experience' : '4. Trading Experience')),
        _sectionSubtitle('Describe your background in these activities.'),
        const SizedBox(height: 12),
        _textField(
          controller: _experienceController,
          hint: _selectedRole == 'BREEDER AND TRADER'
            ? 'Example: 3 years breeding German Shepherds and 2 years trading livestock.'
            : (isBreeder 
                ? 'Example: I have been breeding German Shepherds for 3 years.'
                : 'Example: I have been selling livestock for 2 years.'),
          maxLines: 3,
          validator: (value) => (value == null || value.isEmpty) ? 'Experience is required' : null,
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkGreen));
  Widget _sectionSubtitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black54)),
  );

  Widget _uploadTile({required String label, required File? file, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: file != null ? _themeGreen : Colors.grey.shade300, width: file != null ? 2 : 1),
        ),
        child: file != null 
          ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(file, fit: BoxFit.cover))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_a_photo_rounded, color: _themeGreen, size: 32),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(color: _themeGreen, fontWeight: FontWeight.w600)),
              ],
            ),
      ),
    );
  }

  Widget _buildMultiImageUpload({
    required String label,
    required List<File> files,
    required VoidCallback onTap,
    required Function(int) onRemove,
  }) {
    return Column(
      children: [
        if (files.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _themeGreen, width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(files[index], fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (files.isNotEmpty) const SizedBox(height: 12),
        _uploadTile(label: label, file: null, onTap: onTap),
      ],
    );
  }

  Widget _textField({required TextEditingController controller, required String hint, int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        errorStyle: const TextStyle(color: Colors.redAccent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _themeGreen, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
      ),
    );
  }

  Widget _dropdown({
    required String hint,
    required IconData icon,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      validator: (val) => val == null ? 'Selection required' : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        prefixIcon: Icon(icon, color: _themeGreen, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _themeGreen, width: 1.5)),
      ),
      onChanged: onChanged,
      items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))]),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitApplication,
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text('SUBMIT APPLICATION', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  Widget _roleOption(String role) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? _themeGreen.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _themeGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected ? _themeGreen : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? _themeGreen : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? _darkGreen : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _roleDescriptions[role]!,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.black87 : Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
