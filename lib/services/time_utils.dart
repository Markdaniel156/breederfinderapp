class TimeUtils {
  static String getTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years}y ago';
    }
  }

  static String maskUserName(String fullName) {
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
}
