import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/breeder_provider.dart';
import '../providers/navigation_provider.dart';
import '../utils/system_ui_utils.dart';

class SettingsPrivacyScreen extends StatefulWidget {
  final String initialPrivacyMode;

  const SettingsPrivacyScreen({
    super.key,
    required this.initialPrivacyMode,
  });

  @override
  State<SettingsPrivacyScreen> createState() => _SettingsPrivacyScreenState();
}

class _SettingsPrivacyScreenState extends State<SettingsPrivacyScreen> {
  late String _mapPrivacy;
  bool _isLoading = false;
  bool _isSaved = false;
  final supabase = Supabase.instance.client;

  static const themeGreen = Color(0xFF2D6A4F);

  @override
  void initState() {
    super.initState();
    _mapPrivacy = widget.initialPrivacyMode;
  }

  Future<void> _savePrivacySettings() async {
    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User not logged in';

      // Update create_account privacy mode
      await supabase.from('create_account').update({
        'privacy_mode': _mapPrivacy,
      }).eq('id', user.id);

      // Also update breeder_postings and trader_postings if they exist for this user
      try {
        await supabase.from('breeder_postings').update({
          'privacy_mode': _mapPrivacy,
        }).eq('user_id', user.id);
      } catch (_) {}

      try {
        await supabase.from('trader_postings').update({
          'privacy_mode': _mapPrivacy,
        }).eq('user_id', user.id);
      } catch (_) {}

      if (mounted) {
        // Refresh breeder provider so map updates instantly in real-time
        try {
          final breederProvider = Provider.of<BreederProvider>(context, listen: false);
          await breederProvider.fetchBreeders();
        } catch (_) {}

        setState(() {
          _isSaved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating privacy: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        systemOverlayStyle: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : Colors.white,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: themeGreen, size: 20),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: const Text(
          'MAP PRIVACY',
          style: TextStyle(
            color: themeGreen,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _isSaved ? _buildConfirmationCard(isDark) : _buildOptionsList(isDark),
      ),
    );
  }

  Widget _buildOptionsList(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MAP PRIVACY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: themeGreen,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Control how your location appears to other users on the map.',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 24),
        _buildPrivacyOption(
          'Exact Location',
          'Show your precise location on the map with a custom pin.',
          'Exact',
          Icons.my_location_rounded,
          isDark,
        ),
        _buildPrivacyOption(
          'Approximate Area',
          'Hide your house. Show a circular area where you are located.',
          'Approximate',
          Icons.blur_circular_rounded,
          isDark,
        ),
        _buildPrivacyOption(
          'Hidden',
          'Hide your pin entirely. Users only see your distance in kilometers.',
          'Hidden',
          Icons.visibility_off_rounded,
          isDark,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _savePrivacySettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(
                    'Save Privacy Settings',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: themeGreen.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: themeGreen,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Privacy Updated Successfully!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: themeGreen,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your map privacy mode is now saved as "$_mapPrivacy". Your preferences have been successfully applied to the map.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                final navProvider = Provider.of<NavigationProvider>(context, listen: false);
                navProvider.setIndex(1); // Switch to Map tab
                Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
              },
              icon: const Icon(Icons.map_rounded, color: Colors.white),
              label: const Text(
                'Check the map',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyOption(String title, String subtitle, String value, IconData icon, bool isDark) {
    final isSelected = _mapPrivacy == value;
    return GestureDetector(
      onTap: () => setState(() => _mapPrivacy = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? themeGreen.withValues(alpha: 0.1) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? themeGreen : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200]!),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? themeGreen : Colors.grey, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected ? themeGreen : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle_rounded, color: themeGreen, size: 20),
          ],
        ),
      ),
    );
  }
}
