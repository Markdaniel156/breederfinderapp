import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  bool _isGuest = false;
  bool get isGuest => _isGuest;
  String? _role;
  String? get role => _role;

  void setGuest(bool value) {
    _isGuest = value;
    notifyListeners();
  }

  void setRole(String? value) {
    _role = value;
    notifyListeners();
  }

  /// Synchronizes the user's role from seller_applications to create_account
  /// if an application has been APPROVED but the role hasn't been updated yet.
  /// Returns the newly approved role if a synchronization occurred, null otherwise.
  Future<String?> syncUserRoleAfterApproval(String userId) async {
    try {
      // 1. Check if there's an APPROVED application
      final application = await _supabase
          .from('seller_applications')
          .select('role_applied')
          .eq('user_id', userId)
          .eq('status', 'APPROVED')
          .maybeSingle();

      if (application != null) {
        final appliedRole = application['role_applied']?.toString();
        
        // 2. Check current role in create_account
        final userData = await _supabase
            .from('create_account')
            .select('role, verification_status')
            .eq('id', userId)
            .single();

        final currentRole = userData['role']?.toString();
        final currentStatus = userData['verification_status']?.toString();

        // 3. Update if role or status is not yet sync'd
        if (currentRole != appliedRole || currentStatus != 'APPROVED') {
          await _supabase
              .from('create_account')
              .update({
                'role': appliedRole,
                'verification_status': 'APPROVED',
              })
              .eq('id', userId);
          
          setRole(appliedRole);
          debugPrint('Successfully synchronized role to $appliedRole for user $userId');
          return appliedRole;
        }
      }
    } catch (e) {
      debugPrint('Error synchronizing user role: $e');
    }
    return null;
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    _isGuest = false;
    _role = null;
    notifyListeners();
  }
}
