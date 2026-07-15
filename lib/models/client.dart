/// A CRM contact from the `clients` table.
class Client {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? company;
  final String notes;
  final DateTime createdAt;

  const Client({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.company,
    required this.notes,
    required this.createdAt,
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? 'Unnamed',
      phone: _nullIfBlank(map['phone'] as String?),
      email: _nullIfBlank(map['email'] as String?),
      company: _nullIfBlank(map['company'] as String?),
      notes: (map['notes'] as String?) ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }

  /// One-line subtitle for list rows: company, else phone, else email.
  String get subtitle {
    if (company != null) return company!;
    if (phone != null) return phone!;
    if (email != null) return email!;
    return 'No contact details';
  }

  /// Uppercase initials for the avatar (max two letters).
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  static String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
