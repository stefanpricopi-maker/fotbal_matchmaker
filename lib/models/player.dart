import 'dart:convert';

/// Jucător SIMF — rating bayesian (μ, σ) conform specificației.
class Player {
  const Player({
    required this.id,
    required this.name,
    this.mu = Player.defaultMu,
    this.sigma = Player.defaultSigma,
    this.isPermanentGk = false,
    this.matchesPlayed = 0,
    this.updatedAt,
  });

  /// Valori implicite din specificație (secțiunea 2.1).
  static const double defaultMu = 25.0;
  static const double defaultSigma = 8.33;

  final String id;
  final String name;
  final double mu;
  final double sigma;
  final bool isPermanentGk;
  final int matchesPlayed;
  final DateTime? updatedAt;

  /// Estimare conservatoare uzuală în sisteme μ/σ (μ − 3σ).
  double get conservativeSkill => mu - 3 * sigma;

  Player copyWith({
    String? id,
    String? name,
    double? mu,
    double? sigma,
    bool? isPermanentGk,
    int? matchesPlayed,
    DateTime? updatedAt,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      mu: mu ?? this.mu,
      sigma: sigma ?? this.sigma,
      isPermanentGk: isPermanentGk ?? this.isPermanentGk,
      matchesPlayed: matchesPlayed ?? this.matchesPlayed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mu': mu,
        'sigma': sigma,
        'is_permanent_gk': isPermanentGk,
        'matches_played': matchesPlayed,
        'updated_at': updatedAt?.toUtc().toIso8601String(),
      };

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      mu: (json['mu'] as num?)?.toDouble() ?? defaultMu,
      sigma: (json['sigma'] as num?)?.toDouble() ?? defaultSigma,
      isPermanentGk: json['is_permanent_gk'] as bool? ??
          json['isPermanentGk'] as bool? ??
          false,
      matchesPlayed: (json['matches_played'] as num?)?.toInt() ??
          (json['matchesPlayed'] as num?)?.toInt() ??
          0,
      updatedAt: (json['updated_at'] as String?) != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : (json['updatedAt'] as String?) != null
              ? DateTime.tryParse(json['updatedAt'] as String)
              : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Player.fromJsonString(String source) =>
      Player.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
