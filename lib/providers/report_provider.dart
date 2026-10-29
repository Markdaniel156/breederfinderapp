import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/report.dart';

class ReportProvider with ChangeNotifier {
  final _supabase = Supabase.instance.client;
  bool _isSubmitting = false;

  bool get isSubmitting => _isSubmitting;

  Future<void> submitReport({
    required String reportedUserId,
    String? listingId,
    required String reason,
    required String description,
    required List<File> evidenceFiles,
  }) async {
    _isSubmitting = true;
    notifyListeners();

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('You must be logged in to submit a report');

      List<String> evidenceUrls = [];
      if (evidenceFiles.isNotEmpty) {
        evidenceUrls = await Future.wait(
          evidenceFiles.map((file) async {
            final fileName = 'report_${user.id}_${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
            await _supabase.storage.from('report-evidence').upload(fileName, file);
            return _supabase.storage.from('report-evidence').getPublicUrl(fileName);
          }),
        );
      }

      final report = Report(
        reporterId: user.id,
        reportedUserId: reportedUserId,
        listingId: listingId,
        reason: reason,
        description: description,
        evidenceUrls: evidenceUrls,
        createdAt: DateTime.now(),
      );

      await _supabase.from('reports').insert(report.toMap());
    } catch (e) {
      debugPrint('Error submitting report: $e');
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
