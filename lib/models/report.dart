class Report {
  final String? id;
  final String reporterId;
  final String reportedUserId;
  final String? listingId;
  final String reason;
  final String description;
  final List<String> evidenceUrls;
  final DateTime createdAt;

  Report({
    this.id,
    required this.reporterId,
    required this.reportedUserId,
    this.listingId,
    required this.reason,
    required this.description,
    required this.evidenceUrls,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'reporter_id': reporterId,
      'reported_user_id': reportedUserId,
      'listing_id': (listingId != null && listingId!.trim().isNotEmpty) ? listingId : null,
      'reason': reason,
      'description': description,
      'evidence_urls': evidenceUrls,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Report.fromMap(Map<String, dynamic> map) {
    return Report(
      id: map['id']?.toString(),
      reporterId: map['reporter_id'] ?? '',
      reportedUserId: map['reported_user_id'] ?? '',
      listingId: map['listing_id']?.toString(),
      reason: map['reason'] ?? '',
      description: map['description'] ?? '',
      evidenceUrls: List<String>.from(map['evidence_urls'] ?? []),
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}
