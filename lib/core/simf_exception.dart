/// Eroare de domeniu / infrastructură SIMF (mesaj clar pentru UI sau log).
class SimfException implements Exception {
  SimfException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'SimfException: $message${cause != null ? ' ($cause)' : ''}';
}
