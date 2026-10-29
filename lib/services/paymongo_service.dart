import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PayMongoService {
  // ⚠️ SECURITY: This secret key is embedded in the compiled app and can be
  // extracted by anyone via decompilation (apktool/jadx). Before shipping
  // beyond local testing, move createCheckoutSession() and getSessionStatus()
  // to a backend (e.g. a Supabase Edge Function) and call that backend from
  // the app instead, so the secret key never ships in the client.
  static const String _secretKey = 'sk_test_HBt73nDbZABekEbu44BfUwEj';

  static String get _authHeader {
    const String credentials = '$_secretKey:';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  /// Creates a Checkout Session and returns the checkout URL and session ID.
  /// Uses the V2 endpoint, as documented.
  static Future<Map<String, dynamic>> createCheckoutSession({
    required String name,
    required int amountInCentavos,
    required String successUrl,
    required String cancelUrl,
  }) async {
    const String url = 'https://api.paymongo.com/v2/checkout_sessions';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _authHeader,
      },
      body: jsonEncode({
        'data': {
          'attributes': {
            'line_items': [
              {
                'name': name,
                'amount': amountInCentavos,
                'currency': 'PHP',
                'quantity': 1,
              }
            ],
            'payment_method_types': ['gcash'],
            'success_url': successUrl,
            'cancel_url': cancelUrl,
            'description': 'Breeder Finder Subscription',
          }
        }
      }),
    );

    debugPrint('DEBUG: createCheckoutSession HTTP ${response.statusCode}: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return {
        'id': data['data']['id'],
        'checkout_url': data['data']['attributes']['checkout_url'],
      };
    } else {
      throw Exception('Failed to create checkout session: ${response.body}');
    }
  }

  /// Retrieves the status of a Checkout Session.
  ///
  /// IMPORTANT: PayMongo's documented GET endpoint for checkout sessions is
  /// v1, even though creation happens via v2:
  ///   GET https://api.paymongo.com/v1/checkout_sessions/{id}
  /// There is no documented v2 GET endpoint. Hitting /v2/ here was the likely
  /// cause of verification always failing even after a successful payment.
  ///
  /// Also: the Checkout Session's own `status` field only ever takes the
  /// values 'active' or 'expired' — it never becomes 'paid'. The real signal
  /// that a payment succeeded is a 'paid' entry inside the `payments` array,
  /// which is what hasPaidPayment checks below.
  static Future<String> getSessionStatus(String sessionId) async {
    final String url = 'https://api.paymongo.com/v1/checkout_sessions/$sessionId';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': _authHeader,
      },
    );

    debugPrint('DEBUG: getSessionStatus HTTP ${response.statusCode}: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final attributes = data['data']['attributes'];

      final String sessionStatus = attributes['status'] ?? ''; // 'active' or 'expired' only
      final payments = attributes['payments'] as List? ?? [];

      final bool hasPaidPayment =
      payments.any((p) => p['attributes']['status'] == 'paid');

      debugPrint(
        'DEBUG: PayMongo session status="$sessionStatus", '
            'payments count=${payments.length}, hasPaidPayment=$hasPaidPayment',
      );

      return hasPaidPayment ? 'paid' : sessionStatus;
    } else {
      debugPrint('DEBUG: Error retrieving session: ${response.body}');
      throw Exception('Failed to retrieve session: ${response.body}');
    }
  }
}