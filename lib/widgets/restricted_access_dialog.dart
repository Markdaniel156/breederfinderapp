import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class RestrictedAccessDialog extends StatelessWidget {
  final String featureName;

  const RestrictedAccessDialog({super.key, required this.featureName});

  static void show(BuildContext context, String featureName) {
    showDialog(
      context: context,
      builder: (context) => RestrictedAccessDialog(featureName: featureName),
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF2D6A4F);
    const darkGreen = Color(0xFF1B4332);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      backgroundColor: Colors.white,
      contentPadding: EdgeInsets.zero,
      content: Stack(
        children: [
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
              splashRadius: 20,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline_rounded, color: themeGreen, size: 60),
                ),
                const SizedBox(height: 25),
                const Text(
                  '🔒 Login Required',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: darkGreen,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  'You need to create an account or log in to $featureName.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () {
                            Provider.of<AuthProvider>(context, listen: false).setGuest(false);
                            Navigator.pop(context); // Close dialog
                            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: themeGreen),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text(
                            'Log In',
                            style: TextStyle(color: themeGreen, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Provider.of<AuthProvider>(context, listen: false).setGuest(false);
                            Navigator.pop(context); // Close dialog
                            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                            Navigator.pushNamed(context, '/create-account');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text(
                            'Create Account',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
