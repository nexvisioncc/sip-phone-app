class Recording {
  final String id;
  final String filePath;
  final String number;
  final DateTime timestamp;
  final int durationSeconds;
  final bool isIncoming;

  Recording({
    required this.id,
    required this.filePath,
    required this.number,
    required this.timestamp,
    required this.durationSeconds,
    required this.isIncoming,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'number': number,
    'timestamp': timestamp.toIso8601String(),
    'durationSeconds': durationSeconds,
    'isIncoming': isIncoming,
  };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
    id: json['id'],
    filePath: json['filePath'],
    number: json['number'],
    timestamp: DateTime.parse(json['timestamp']),
    durationSeconds: json['durationSeconds'],
    isIncoming: json['isIncoming'],
  );

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
