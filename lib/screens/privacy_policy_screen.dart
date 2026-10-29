import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/system_ui_utils.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const themeGreen = Color(0xFF2D6A4F);

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
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: themeGreen, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            color: themeGreen,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Introduction'),
            _buildSectionText(
              'Welcome to BreederFinder. We are committed to protecting your personal information and your right to privacy. If you have any questions or concerns about our policy, or our practices with regards to your personal information, please contact us.',
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('1. Information We Collect'),
            _buildSectionText(
              'We collect personal information that you provide to us such as name, address, contact information, and account credentials. We also collect location data to provide geofencing services and help you find breeders nearby.',
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('2. How We Use Your Information'),
            _buildSectionText(
              'We use your information to facilitate account creation, provide our services (like animal listings and chat), send administrative information, and for other business purposes such as data analysis and improving our application.',
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('3. Data Sharing'),
            _buildSectionText(
              'We only share information with your consent, to comply with laws, to provide you with services, to protect your rights, or to fulfill business obligations.',
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('4. Data Security'),
            _buildSectionText(
              'We use appropriate technical and organizational security measures designed to protect the security of any personal information we process. However, please also remember that we cannot guarantee that the internet itself is 100% secure.',
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('5. Contact Us'),
            _buildSectionText(
              'If you have questions or comments about this policy, you may email us at support@breederfinder.com.',
            ),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Last updated: July 25, 2026',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: themeGreen,
        ),
      ),
    );
  }

  Widget _buildSectionText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Colors.grey,
      ),
    );
  }
}
