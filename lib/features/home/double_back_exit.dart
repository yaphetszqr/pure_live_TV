/// Decides whether a back press on the home page should leave the app: the
/// first press arms it, a second one inside [window] exits.
class DoubleBackExit {
  DoubleBackExit({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Matches ToastUtil's three second de-duplication, so a press that has to
  /// arm again can always show its hint.
  static const Duration window = Duration(seconds: 3);

  /// PopScope can call back more than once for one press (predictive back).
  /// Anything this close to the first call is that same press, otherwise a
  /// single press would exit.
  static const Duration samePressGap = Duration(milliseconds: 200);

  final DateTime Function() _clock;
  DateTime? _armedAt;

  /// True when this press should exit. False means the caller should tell the
  /// user to press again.
  bool onBackPressed() {
    final now = _clock();
    final armedAt = _armedAt;
    if (armedAt != null) {
      final elapsed = now.difference(armedAt);
      if (elapsed < samePressGap) return false;
      if (elapsed <= window) return true;
    }
    _armedAt = now;
    return false;
  }
}
