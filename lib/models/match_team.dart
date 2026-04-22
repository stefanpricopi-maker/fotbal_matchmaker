/// Echipă în meci — mapare DB `A` / `B` (echipa roșie vs albastră în UI).
enum MatchTeam {
  a('A'),
  b('B');

  const MatchTeam(this.dbValue);
  final String dbValue;

  static MatchTeam fromDb(String value) {
    final v = value.toUpperCase();
    return MatchTeam.values.firstWhere(
      (e) => e.dbValue == v,
      orElse: () => MatchTeam.a,
    );
  }
}
