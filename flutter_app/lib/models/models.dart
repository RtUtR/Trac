// lib/models/models.dart
class GroupSummary {
  final String id;
  final int maxDevices;
  final DateTime expiresAt;
  final String myDisplayName;
  final String myColor;

  const GroupSummary({
    required this.id,
    required this.maxDevices,
    required this.expiresAt,
    required this.myDisplayName,
    required this.myColor,
  });

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}

class GroupInfoRow {
  final String id;
  final int maxDevices;
  final DateTime expiresAt;

  const GroupInfoRow({
    required this.id,
    required this.maxDevices,
    required this.expiresAt,
  });

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  factory GroupInfoRow.fromJson(Map<String, dynamic> json) {
    return GroupInfoRow(
      id: json['id'] as String,
      maxDevices: (json['max_devices'] as num).toInt(),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class GroupMember {
  final String userId;
  final String displayName;
  final String color;

  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.color,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      color: json['color'] as String,
    );
  }
}

class MemberLocation {
  final String userId;
  final String displayName;
  final String color;
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime updatedAt;

  const MemberLocation({
    required this.userId,
    required this.displayName,
    required this.color,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.updatedAt,
  });

  factory MemberLocation.fromJson(Map<String, dynamic> json) {
    return MemberLocation(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      color: json['color'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'color': color,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'updated_at': updatedAt.toIso8601String(),
      };
}

class JoinGroupResult {
  final bool ok;
  final GroupSummary? group;
  final String? errorCode;

  const JoinGroupResult._({
    required this.ok,
    this.group,
    this.errorCode,
  });

  factory JoinGroupResult.success(GroupSummary group) =>
      JoinGroupResult._(ok: true, group: group);

  factory JoinGroupResult.failure(String errorCode) =>
      JoinGroupResult._(ok: false, errorCode: errorCode);
}

class FetchLocationsResult {
  final bool ok;
  final int? cooldownSeconds;
  final List<MemberLocation> locations;
  final String? errorCode;
  final int? remainingSeconds;

  const FetchLocationsResult._({
    required this.ok,
    this.cooldownSeconds,
    this.locations = const [],
    this.errorCode,
    this.remainingSeconds,
  });

  factory FetchLocationsResult.success({
    required int cooldownSeconds,
    required List<MemberLocation> locations,
  }) =>
      FetchLocationsResult._(
        ok: true,
        cooldownSeconds: cooldownSeconds,
        locations: locations,
      );

  factory FetchLocationsResult.failure({
    required String errorCode,
    int? remainingSeconds,
  }) =>
      FetchLocationsResult._(
        ok: false,
        errorCode: errorCode,
        remainingSeconds: remainingSeconds,
      );
}

class QueuedLocationPayload {
  final double lat;
  final double lng;
  final double accuracy;

  const QueuedLocationPayload({
    required this.lat,
    required this.lng,
    required this.accuracy,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
      };

  factory QueuedLocationPayload.fromJson(Map<String, dynamic> json) {
    return QueuedLocationPayload(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
    );
  }
}
