class Review {
  final String id;
  final String listingId;
  final String userId;
  final String userName;
  final String userAvatarUrl;
  final double rating;
  final String comment;
  final DateTime createdAt;
  final List<String> reviewPhotos;
  final String? replyComment;
  final DateTime? replyCreatedAt;

  Review({
    required this.id,
    required this.listingId,
    required this.userId,
    required this.userName,
    required this.userAvatarUrl,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.reviewPhotos = const [],
    this.replyComment,
    this.replyCreatedAt,
  });

  factory Review.fromMap(Map<String, dynamic> map) {
    return Review(
      id: map['id']?.toString() ?? '',
      listingId: map['listing_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      userName: map['user_name']?.toString() ?? 'User',
      userAvatarUrl: map['user_avatar_url']?.toString() ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      comment: map['comment']?.toString() ?? '',
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at'].toString()) 
          : DateTime.now(),
      reviewPhotos: (map['review_photos'] as List?)?.map((e) => e.toString()).toList() ?? [],
      replyComment: map['reply_comment']?.toString(),
      replyCreatedAt: map['reply_created_at'] != null 
          ? DateTime.parse(map['reply_created_at'].toString()) 
          : null,
    );
  }

  static String maskName(String fullName) {
    if (fullName.isEmpty) return 'Anonymous';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.map((part) {
      if (part.isEmpty) return '';
      if (part.length <= 1) return '${part[0]}*';
      final firstChar = part[0];
      int starCount = part.length > 4 ? 3 : 2;
      return '$firstChar${'*' * starCount}';
    }).join(' ');
  }

  String get maskedUserName => maskName(userName);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listing_id': listingId,
      'user_id': userId,
      'user_name': userName,
      'user_avatar_url': userAvatarUrl,
      'rating': rating,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
      'review_photos': reviewPhotos,
      'reply_comment': replyComment,
      'reply_created_at': replyCreatedAt?.toIso8601String(),
    };
  }
}
