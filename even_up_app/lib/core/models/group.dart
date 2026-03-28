import 'package:even_up_app/core/models/group_member.dart';

class Group {
  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final List<GroupMember>? members;
  final String? icon;
  final Map<String, double>? memberBalances;

  Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    this.members,
    this.icon,
    this.memberBalances,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: _safeString(json['id']),
      name: _safeString(json['name'] ?? json['displayName'], defaultValue: 'Unnamed Group'),
      createdBy: _safeString(json['createdBy']),
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      members: json['members'] != null
          ? (json['members'] as List).map((m) => GroupMember.fromJson(m)).toList()
          : null,
      icon: _safeString(json['icon'], defaultValue: 'group'),
      memberBalances: json['memberBalances'] != null 
          ? Map<String, double>.from(
              (json['memberBalances'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
              ),
            )
          : null,
    );
  }

  static String _safeString(dynamic value, {String defaultValue = ''}) {
    if (value is String) return value;
    if (value == null) return defaultValue;
    try {
      // Use string interpolation as it's generally safer in DDC
      final String s = '$value';
      if (s == 'undefined' || s == 'null') return defaultValue;
      return s;
    } catch (_) {
      return defaultValue;
    }
  }
}
