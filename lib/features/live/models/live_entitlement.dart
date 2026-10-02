class GoLivePlan {
  final String planId;
  final String name;
  final int durationDays;
  final int includedMinutes;
  final bool trial;
  final String description;
  final String googlePlayProductId;
  final int displayOrder;

  const GoLivePlan({
    required this.planId,
    required this.name,
    required this.durationDays,
    required this.includedMinutes,
    required this.trial,
    required this.description,
    required this.googlePlayProductId,
    required this.displayOrder,
  });

  factory GoLivePlan.fromJson(Map<String, dynamic> json) {
    return GoLivePlan(
      planId: json['planId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      durationDays: _asInt(json['durationDays']),
      includedMinutes: _asInt(json['includedMinutes']),
      trial: json['trial'] == true,
      description: json['description']?.toString() ?? '',
      googlePlayProductId: json['googlePlayProductId']?.toString() ?? '',
      displayOrder: _asInt(json['displayOrder']),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class GoLiveEntitlement {
  final String planId;
  final String provider;
  final String status;
  final bool trial;
  final bool autoRenewing;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int includedMinutes;
  final int usedMinutes;
  final int remainingMinutes;

  const GoLiveEntitlement({
    required this.planId,
    required this.provider,
    required this.status,
    required this.trial,
    required this.autoRenewing,
    required this.startedAt,
    required this.expiresAt,
    required this.includedMinutes,
    required this.usedMinutes,
    required this.remainingMinutes,
  });

  factory GoLiveEntitlement.fromJson(Map<String, dynamic> json) {
    return GoLiveEntitlement(
      planId: json['planId']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      trial: json['trial'] == true,
      autoRenewing: json['autoRenewing'] == true,
      startedAt: _parseDate(json['startedAt']),
      expiresAt: _parseDate(json['expiresAt']),
      includedMinutes: _asInt(json['includedMinutes']),
      usedMinutes: _asInt(json['usedMinutes']),
      remainingMinutes: _asInt(json['remainingMinutes']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
