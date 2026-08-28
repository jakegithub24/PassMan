class EncryptedVaultEntry {
  final String id;
  final String userId;
  final String encryptedData;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const EncryptedVaultEntry({
    required this.id,
    required this.userId,
    required this.encryptedData,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  factory EncryptedVaultEntry.fromJson(Map<String, dynamic> json) {
    return EncryptedVaultEntry(
      id: json['id'] as String,
      userId: (json['user_id'] ?? json['userId']) as String,
      encryptedData: (json['encrypted_data'] ?? json['encryptedData']) as String,
      updatedAt: DateTime.parse((json['updated_at'] ?? json['updatedAt']) as String),
      deletedAt: json['deleted_at'] != null || json['deletedAt'] != null
          ? DateTime.parse((json['deleted_at'] ?? json['deletedAt']) as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'encrypted_data': encryptedData,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  factory EncryptedVaultEntry.fromSqlite(Map<String, dynamic> map) {
    return EncryptedVaultEntry(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      encryptedData: map['encrypted_data'] as String,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toSqlite() {
    return {
      'id': id,
      'user_id': userId,
      'encrypted_data': encryptedData,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  EncryptedVaultEntry copyWith({
    String? id,
    String? userId,
    String? encryptedData,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return EncryptedVaultEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      encryptedData: encryptedData ?? this.encryptedData,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
