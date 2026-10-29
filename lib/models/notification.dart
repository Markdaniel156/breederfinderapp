enum NotificationType { subscription, posting, arrival, onTheWay }

class NotificationItem {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  final String? status; // Arrival or request status

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.data,
    this.status,
  });
}
