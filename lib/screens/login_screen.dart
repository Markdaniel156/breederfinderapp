import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../providers/auth_provider.dart';
import '../utils/system_ui_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;
  String? _passwordError;
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  final ConnectivityService _connectivityService = ConnectivityService();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const themeGreen = Color(0xFF2D6A4F);
  static const darkGreen = Color(0xFF1B4332);

  @override
  void initState() {
    super.initState();
    _connectivityService.initialize(context);
    _loadSavedCredentials();

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    Future.delayed(const Duration(milliseconds: 100), () {
      _fadeController.forward();
      _slideController.forward();
    });
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('remembered_email');
    final savedPassword = prefs.getString('remembered_password');
    if (savedEmail != null && savedPassword != null) {
      setState(() {
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  // ── FIXED: Returns remaining lockout seconds (not minutes) for precision ──
  Future<int> _getRemainingLockoutSeconds() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return 0;

    try {
      final supabase = Supabase.instance.client;
      final userData = await supabase
          .from('create_account')
          .select('login_attempts, last_failed_login')
          .eq('email', email)
          .maybeSingle();

      if (userData == null) return 0;

      final attempts = userData['login_attempts'] ?? 0;
      if (attempts < 5) return 0;

      final lastFailedStr = userData['last_failed_login'];
      if (lastFailedStr == null) return 0;

      final lastFailed = DateTime.parse(lastFailedStr).toUtc();
      final now = DateTime.now().toUtc();
      final expiryTime = lastFailed.add(const Duration(minutes: 10));

      if (now.isAfter(expiryTime)) {
        // Lockout expired — reset attempts so user can try again
        await supabase
            .from('create_account')
            .update({'login_attempts': 0, 'last_failed_login': null})
            .eq('email', email);
        return 0;
      }

      // ✅ Return remaining seconds for precise ceiling-minute display
      return expiryTime.difference(now).inSeconds;
    } catch (e) {
      debugPrint('Error checking lockout in DB: $e');
      return 0;
    }
  }

  // ── Helper: convert remaining seconds to display string e.g. "9 min 30 sec" ──
  String _formatLockoutTime(int remainingSeconds) {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    if (minutes > 0 && seconds > 0) {
      return '$minutes min $seconds sec';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '$seconds sec';
    }
  }

  Future<void> _handleFailedAttempt() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      final userData = await supabase
          .from('create_account')
          .select('login_attempts')
          .eq('email', email)
          .maybeSingle();

      if (userData != null) {
        int currentAttempts = (userData['login_attempts'] ?? 0) + 1;
        await supabase
            .from('create_account')
            .update({
          'login_attempts': currentAttempts,
          // ✅ Always update last_failed_login to NOW so the 10-min window
          //    is anchored to the most recent failed attempt
          'last_failed_login': DateTime.now().toUtc().toIso8601String(),
        })
            .eq('email', email);
      }
    } catch (e) {
      debugPrint('Error updating failed attempts in DB: $e');
    }
  }

  Future<void> _resetAttempts() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('create_account')
            .update({
          'login_attempts': 0,
          'last_failed_login': null,
        })
            .eq('id', user.id);
      } catch (e) {
        debugPrint('Error resetting attempts in DB: $e');
      }
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _setFieldError('email', 'Email is required');
    }
    if (password.isEmpty) {
      _setFieldError('password', 'Password is required');
    }

    if (_emailError != null || _passwordError != null) return;

    // Email format validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _setFieldError('email', 'Please enter a valid email address');
      return;
    }

    // ✅ Use seconds-based lockout check for accuracy
    final remainingSeconds = await _getRemainingLockoutSeconds();
    if (remainingSeconds > 0) {
      _showError('Too many failed attempts. Try again in ${_formatLockoutTime(remainingSeconds)}.');
      return;
    }

    final hasConnection = await _connectivityService.checkConnection();
    if (!hasConnection) {
      if (mounted) _connectivityService.showNoInternetSnackBar(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user != null) {
        if (mounted) {
          Provider.of<AuthProvider>(context, listen: false).setGuest(false);
        }
        await _resetAttempts();
        await _updateFCMToken();

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        
        // Sync role if an application was recently approved
        final newRole = await authProvider.syncUserRoleAfterApproval(response.user!.id);

        final userData = await supabase
            .from('create_account')
            .select('verification_status, role')
            .eq('id', response.user!.id)
            .single();

        final status = userData['verification_status'];
        final role = userData['role']?.toString();

        if (mounted) {
          authProvider.setRole(role);
        }

        if (status == 'BLOCKED') {
          await supabase.auth.signOut();
          if (mounted) _showBlockedDialog();
          return;
        } else if (status == 'APPROVED') {
          final prefs = await SharedPreferences.getInstance();
          final hasBeenNotified = prefs.getBool('notified_approved_${response.user!.id}') ?? false;

          if (!hasBeenNotified && mounted) {
            String message = 'Congrats! You can now login and explore.';
            if (newRole != null) {
              final roleText = newRole.toLowerCase().contains('breeder') && newRole.toLowerCase().contains('trader')
                  ? 'Breeder and Trader'
                  : (newRole.toLowerCase().contains('trader') ? 'Trader' : 'Breeder');
              message = 'Congrats! Your requirements were approved to be a $roleText.';
            }

            _showNotificationOverlay(
              title: 'Account Approved',
              message: message,
              icon: Icons.verified_user_rounded,
              iconColor: themeGreen,
            );
            await prefs.setBool('notified_approved_${response.user!.id}', true);
          }
        }
        // PENDING status is now allowed to enter the app directly
      }

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailController.text.trim());
        await prefs.setString('remembered_password', _passwordController.text);
      } else {
        await prefs.remove('remembered_email');
        await prefs.remove('remembered_password');
      }

      if (mounted) {
        // Directed directly to home, subscription is no longer mandatory
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (error) {
      await _handleFailedAttempt();
      if (mounted) {
        _applyFieldErrors(error.message);
      }
    } catch (error) {
      if (mounted) {
        if (error.toString().contains('SocketException') || error.toString().contains('Failed host lookup')) {
          _connectivityService.showNoInternetSnackBar(context);
        } else {
          _applyFieldErrors('An unexpected error occurred. Please try again.');
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _continueAsGuest() {
    Provider.of<AuthProvider>(context, listen: false).setGuest(true);
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _setFieldError(String field, String? errorMessage) {
    setState(() {
      if (field == 'email') {
        _emailError = errorMessage;
      } else if (field == 'password') {
        _passwordError = errorMessage;
      }
    });
  }

  void _applyFieldErrors(String errorMessage) {
    final msg = errorMessage.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      _setFieldError('email', ' '); // Highlight red border
      _setFieldError('password', 'Invalid email or password');
    } else if (msg.contains('gateway timeout') ||
               msg.contains('bad gateway') ||
               msg.contains('504') ||
               msg.contains('502') ||
               msg.contains('503') ||
               msg.contains('timeout') ||
               msg.contains('timed out') ||
               msg.contains('connection') ||
               msg.contains('network') ||
               msg.contains('server error') ||
               msg.contains('service unavailable')) {
      _setFieldError('email', null);
      _setFieldError('password', null);
      _showError(errorMessage);
    } else if (msg.contains('password') && (msg.contains('length') || msg.contains('characters') || msg.contains('weak') || msg.contains('match'))) {
      _setFieldError('email', null);
      _setFieldError('password', errorMessage);
    } else if (msg.contains('email') || msg.contains('user not found')) {
      _setFieldError('email', errorMessage);
      _setFieldError('password', null);
    } else {
      _setFieldError('email', null);
      _setFieldError('password', null);
      _showError(errorMessage);
    }
  }

  void _showError(String message) {
    _showNotificationOverlay(
      title: 'Login Error',
      message: message,
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFC72C41),
    );
  }

  void _showNotificationOverlay({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _TopNotification(
        title: title,
        message: message,
        icon: icon,
        iconColor: iconColor,
        onDismiss: () {
          try {
            entry.remove();
          } catch (e) {
            debugPrint('Overlay already removed: $e');
          }
        },
      ),
    );

    overlay.insert(entry);
  }

  void _showBlockedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC72C41).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.block_flipped, color: Color(0xFFC72C41), size: 60),
            ),
            const SizedBox(height: 25),
            const Text(
              'Account Blocked',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC72C41)),
            ),
            const SizedBox(height: 15),
            const Text(
              'Your account has been blocked by the administrator.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC72C41),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('Understood', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }


  Future<void> _updateFCMToken() async {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    final user = Supabase.instance.client.auth.currentUser;

    if (fcmToken != null && user != null) {
      await Supabase.instance.client
          .from('create_account')
          .update({'fcm_token': fcmToken})
          .eq('id', user.id);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _connectivityService.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7F5),
      resizeToAvoidBottomInset: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7F5),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 3),
                    _buildBrandRow(),
                    const Spacer(flex: 3),
                    _buildWelcomeText(),
                    const Spacer(flex: 4),
                    _buildFormCard(),
                    const Spacer(flex: 3),
                    _buildLoginButton(),
                    const Spacer(flex: 3),
                    _buildDivider(),
                    const Spacer(flex: 2),
                    _buildSignUpRow(),
                    const Spacer(flex: 2),
                    _buildGuestButton(),
                    const Spacer(flex: 3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestButton() {
    return Center(
      child: TextButton(
        onPressed: _continueAsGuest,
        style: TextButton.styleFrom(
          foregroundColor: themeGreen,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
        child: const Text(
          'Continue as Guest',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _buildBrandRow() {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: themeGreen,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: themeGreen.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.pets, color: Colors.white, size: 30),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.location_on, color: themeGreen, size: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Breeder Finder',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: darkGreen,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              'Trusted Breeders. Happy Pets.',
              style: TextStyle(
                fontSize: 12,
                color: themeGreen.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome!\nPlease Login.',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: darkGreen,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Connect with verified breeders near you',
          style: TextStyle(
            fontSize: 14,
            color: Colors.black.withValues(alpha: 0.45),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel(label: 'Email address'),
          const SizedBox(height: 8),
          _StyledField(
            controller: _emailController,
            hint: 'you@example.com',
            icon: Icons.alternate_email_rounded,
            errorText: _emailError,
            onChanged: (val) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          const SizedBox(height: 18),
          const _FieldLabel(label: 'Password'),
          const SizedBox(height: 8),
          _StyledField(
            controller: _passwordController,
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscureText: !_isPasswordVisible,
            errorText: _passwordError,
            onChanged: (val) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
            suffixIcon: GestureDetector(
              onTap: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  _isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _rememberMe ? themeGreen : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _rememberMe ? themeGreen : Colors.grey.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: _rememberMe
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remember me',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: themeGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: themeGreen,
          foregroundColor: Colors.white,
          elevation: 10,
          shadowColor: themeGreen.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: _isLoading
            ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Sign In',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.3),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.black.withValues(alpha: 0.1), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'New here?',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.35),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.black.withValues(alpha: 0.1), thickness: 1)),
      ],
    );
  }

  Widget _buildSignUpRow() {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/create-account'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: themeGreen.withValues(alpha: 0.3), width: 1.5),
            borderRadius: BorderRadius.circular(16),
            color: themeGreen.withValues(alpha: 0.04),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Create an account',
                style: TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios_rounded, size: 13, color: themeGreen),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable field label ──────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1B4332),
        letterSpacing: 0.2,
      ),
    );
  }
}

// ── Reusable styled text field ────────────────────────────────────────────────
class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _StyledField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
  });

  static const themeGreen = Color(0xFF2D6A4F);
  static const errorRed = Color(0xFFC72C41);

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: hasError ? errorRed.withValues(alpha: 0.02) : const Color(0xFFF5F7F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError ? errorRed.withValues(alpha: 0.5) : Colors.grey.shade200,
              width: hasError ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: 15,
              color: hasError ? errorRed : const Color(0xFF1B4332),
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(
                  icon,
                  color: hasError ? errorRed : themeGreen,
                  size: 20,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            ),
          ),
        ),
        if (hasError && errorText != ' ')
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: errorRed,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Top notification overlay ──────────────────────────────────────────────────
class _TopNotification extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;

  const _TopNotification({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
  });

  @override
  State<_TopNotification> createState() => _TopNotificationState();
}

class _TopNotificationState extends State<_TopNotification> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _offsetAnimation = Tween<double>(begin: -100, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _controller.reverse().then((_) => widget.onDismiss());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 15,
      right: 15,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _offsetAnimation.value),
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.iconColor, size: 28),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'now',
                            style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.3)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black.withValues(alpha: 0.7),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}