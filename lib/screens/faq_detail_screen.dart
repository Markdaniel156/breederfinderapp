import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/system_ui_utils.dart';

class FAQDetailScreen extends StatelessWidget {
  final String question;
  final String answer;

  const FAQDetailScreen({
    super.key,
    required this.question,
    required this.answer,
  });

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
          'FAQ Details',
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: themeGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.help_outline_rounded, color: themeGreen, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      question,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Answer',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: themeGreen,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              answer,
              style: TextStyle(
                fontSize: 16,
                height: 1.8,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 40),
            Divider(color: isDark ? Colors.white10 : Colors.black12),
            const SizedBox(height: 20),
            Text(
              'Was this helpful?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildFeedbackButton(Icons.thumb_up_alt_rounded, 'Yes', isDark),
                const SizedBox(width: 12),
                _buildFeedbackButton(Icons.thumb_down_alt_rounded, 'No', isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackButton(IconData icon, String label, bool isDark) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white70 : Colors.black87,
          side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
