/// Plain-language relative time ("20 min ago", "3 h ago") used on pins and
/// trust captions everywhere.
String relativeTime(DateTime? then) {
  if (then == null) return 'not yet verified';
  final diff = DateTime.now().toUtc().difference(then.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays} days ago';
}
