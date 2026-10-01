class LiveSession {
  final String sessionId;
  final String broadcasterXameId;
  final String? title;
  final String? category;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int viewerCount;
  final String? playbackUrl;
  final int allowedMinutes;
  final DateTime? usageCutoffAt;

  const LiveSession({
    required this.sessionId,
    required this.broadcasterXameId,
    this.title,
    this.category,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.viewerCount,
    this.playbackUrl,
    required this.allowedMinutes,
    this.usageCutoffAt,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    return LiveSession(
      sessionId: json['sessionId']?.toString() ?? '',
      broadcasterXameId:
          json['broadcasterXameId']?.toString() ?? '',
      title: json['title']?.toString(),
      category: json['category']?.toString(),
      status: json['status']?.toString() ?? 'STARTING',
      startedAt: _parseDate(json['startedAt']),
      endedAt: _parseDate(json['endedAt']),
      viewerCount: _parseInt(json['viewerCount']),
      playbackUrl: json['playbackUrl']?.toString(),
      allowedMinutes: _parseInt(json['allowedMinutes']),
      usageCutoffAt: _parseDate(json['usageCutoffAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'broadcasterXameId': broadcasterXameId,
      'title': title,
      'category': category,
      'status': status,
      'startedAt': startedAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'viewerCount': viewerCount,
      'playbackUrl': playbackUrl,
      'allowedMinutes': allowedMinutes,
      'usageCutoffAt': usageCutoffAt?.toIso8601String(),
    };
  }

  bool get isStarting => status == 'STARTING';
  bool get isLive => status == 'LIVE';
  bool get isEnded => status == 'ENDED';
}
