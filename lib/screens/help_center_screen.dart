import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'privacy_policy_screen.dart';
import 'feedback_screen.dart';
import 'faq_detail_screen.dart';
import '../utils/system_ui_utils.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const themeGreen = Color(0xFF2D6A4F);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAF8),
      appBar: AppBar(
        systemOverlayStyle: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAF8),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: themeGreen, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help Center',
          style: TextStyle(
            color: themeGreen,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(isDark),
            const SizedBox(height: 30),
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildFAQList(isDark),
            const SizedBox(height: 30),
            const Text(
              'Still need help?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildContactSupport(context, isDark),
            const SizedBox(height: 30),
            const Text(
              'More Resources',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildResourceLinks(context, isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search for help...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          border: InputBorder.none,
          icon: const Icon(Icons.search_rounded, color: themeGreen),
        ),
      ),
    );
  }

  Widget _buildFAQList(bool isDark) {
    final faqs = [
      {
        'q': 'How do I register as a breeder?',
        'a': 'Go to your Profile, tap the menu icon (Settings and Privacy), and look for Registration options. Alternatively, tap the "+" button on the home screen to start a new listing.'
      },
      {
        'q': 'How does the map geofencing work?',
        'a': 'Our geofencing technology alerts you when you enter an area with registered breeders or traders nearby, helping you discover local listings instantly.'
      },
      {
        'q': 'How can I report a suspicious user?',
        'a': 'On any listing details page, you will find a "Report" button next to the breeder\'s name. Tap it to submit a report to our moderation team.'
      },
      {
        'q': 'Is my data secure?',
        'a': 'Yes, we use Supabase for secure authentication and data storage. Your personal information is encrypted and never shared without your consent.'
      },
      {
        'q': 'How do I update my profile?',
        'a': 'Go to the Profile screen and tap the camera icon on your avatar to change your photo, or tap the "Edit Profile" button to update your name and location details.'
      },
      {
        'q': 'How do I delete a listing?',
        'a': 'To delete a listing, open the listing details from your profile and tap the delete icon (trash can) at the bottom. You will be asked to confirm the deletion.'
      },
      {
        'q': 'What happens if I forget my password?',
        'a': 'On the Login screen, tap "Forgot Password". We will send a password reset link to your registered email address.'
      },
    ];

    return Column(
      children: faqs.map((faq) => _buildFAQItem(faq['q']!, faq['a']!, isDark)).toList(),
    );
  }

  Widget _buildFAQItem(String question, String answer, bool isDark) {
    return Builder(
      builder: (context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1)),
        ),
        child: ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FAQDetailScreen(
                  question: question,
                  answer: answer,
                ),
              ),
            );
          },
          title: Text(
            question,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildContactSupport(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [themeGreen, Color(0xFF40916C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: themeGreen.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text(
            'Contact Customer Support',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Available Mon-Fri, 9am - 6pm',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              // Action to send email or open chat
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: themeGreen,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Send Message', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceLinks(BuildContext context, bool isDark) {
    return Column(
      children: [
        _buildResourceItem(
          Icons.policy_outlined,
          'Privacy Policy',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          isDark,
        ),
        const SizedBox(height: 10),
        _buildResourceItem(
          Icons.rate_review_outlined,
          'Share Feedback',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackScreen())),
          isDark,
        ),
      ],
    );
  }

  Widget _buildResourceItem(IconData icon, String label, VoidCallback onTap, bool isDark) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: themeGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: themeGreen, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1)),
      ),
      tileColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    );
  }
}
