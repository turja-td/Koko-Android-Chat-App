String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool _isYesterday(DateTime t) => sameDay(t, DateTime.now().subtract(const Duration(days: 1)));

/// 5:32 PM
String time12(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// For the chat list: time today, "Yesterday", or a short date.
String shortTime(DateTime t) {
  if (sameDay(t, DateTime.now())) return time12(t);
  if (_isYesterday(t)) return 'Yesterday';
  return '${t.day}/${t.month}/${t.year % 100}';
}

/// Date separator label inside a chat.
String dayLabel(DateTime t) {
  if (sameDay(t, DateTime.now())) return 'Today';
  if (_isYesterday(t)) return 'Yesterday';
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// last seen today at 5:32 PM
String lastSeenText(DateTime t) {
  if (sameDay(t, DateTime.now())) return 'last seen today at ${time12(t)}';
  if (_isYesterday(t)) return 'last seen yesterday at ${time12(t)}';
  return 'last seen ${t.day} ${_months[t.month - 1]} at ${time12(t)}';
}

String formatDuration(int sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
