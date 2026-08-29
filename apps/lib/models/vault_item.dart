class VaultItem {
  final String id;
  final String title;
  final String username;
  final String password;
  final String? url;
  final String? notes;
  final String category;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const VaultItem({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    this.url,
    this.notes,
    this.category = 'logins',
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  /// Serializes the decrypted fields to JSON before AES-256-GCM encryption.
  Map<String, dynamic> toDecryptedJson() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'category': category,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toDecryptedJson();

  /// Deserializes plaintext JSON decrypted from the AES-256-GCM ciphertext payload.
  factory VaultItem.fromDecryptedJson(Map<String, dynamic> json, {String? entryId}) {
    return VaultItem(
      id: entryId ?? (json['id'] as String? ?? ''),
      title: (json['title'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      password: (json['password'] as String?) ?? '',
      url: json['url'] as String?,
      notes: json['notes'] as String?,
      category: (json['category'] as String?) ?? 'logins',
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now().toUtc(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  factory VaultItem.fromJson(Map<String, dynamic> json) =>
      VaultItem.fromDecryptedJson(json);

  VaultItem copyWith({
    String? id,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? category,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return VaultItem(
      id: id ?? this.id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
