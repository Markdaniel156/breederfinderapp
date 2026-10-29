import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/paymongo_service.dart';
import '../widgets/subscription_plans_view.dart';
import '../utils/system_ui_utils.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static const themeGreen = Color(0xFF2D6A4F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('Subscription', style: TextStyle(fontWeight: FontWeight.bold, color: themeGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: themeGreen, size: 20),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        systemOverlayStyle: SystemUiUtils.getOverlayStyle(
          isDark: Theme.of(context).brightness == Brightness.dark,
          navBarColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF121212) : Colors.white,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SubscriptionPlansView(
            onBack: () => Navigator.pop(context, true),
          ),
        ),
      ),
    );
  }
}

class PayMongoWebView extends StatefulWidget {
  final String checkoutUrl;
  final String sessionId;

  const PayMongoWebView({
    super.key,
    required this.checkoutUrl,
    required this.sessionId,
  });

  @override
  State<PayMongoWebView> createState() => _PayMongoWebViewState();
}

class _PayMongoWebViewState extends State<PayMongoWebView> {
  late final WebViewController _controller;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            debugPrint('DEBUG: WebView navigating to: ${request.url}');
            // 1. Handle GCash App Deep Link
            if (request.url.startsWith('gcash://')) {
              debugPrint('DEBUG: GCash deep link detected');
              launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }

            // 2. Handle Success Redirect
            if (request.url.contains('success.com')) {
              debugPrint('DEBUG: Success URL detected! Verifying payment...');
              _verifyPayment();
              return NavigationDecision.prevent;
            }

            // 3. Handle Cancel Redirect
            if (request.url.contains('cancel.com')) {
              Navigator.pop(context, 'cancel');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  Future<void> _verifyPayment() async {
    setState(() => _isVerifying = true);
    try {
      debugPrint('DEBUG: Calling PayMongo to verify session: ${widget.sessionId}');

      // Retry logic: PayMongo/GCash status sync can take a few seconds
      int attempts = 0;
      const maxAttempts = 5;
      String status = 'pending';

      while (attempts < maxAttempts && status != 'paid') {
        attempts++;
        debugPrint('DEBUG: Verification attempt $attempts/$maxAttempts...');
        status = await PayMongoService.getSessionStatus(widget.sessionId);
        debugPrint('DEBUG: Attempt $attempts status result: $status');

        if (status == 'paid') break;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 4));
        }
      }

      if (status == 'paid') {
        if (mounted) Navigator.pop(context, 'success');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment still processing or failed. Please wait a moment.')),
          );
          await Future.delayed(const Duration(seconds: 3));
          if (mounted) Navigator.pop(context, 'error');
        }
      }
    } catch (e) {
      debugPrint('DEBUG: Error verifying payment: $e');
      if (mounted) Navigator.pop(context, 'error');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with GCash'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, 'cancel'),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isVerifying)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Verifying Payment...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}