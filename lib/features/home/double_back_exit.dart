/// What a back press on the home page amounts to.
enum BackPressResult {
  /// A repeat callback of a press already handled: do nothing.
  ignored,

  /// The first press: tell the user to press again.
  armed,

  /// The second press inside the window: leave the app.
  exit,
}

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
  DateTime? _consumedAt;

  BackPressResult onBackPressed() {
    final now = _clock();
    final consumedAt = _consumedAt;
    if (consumedAt != null && now.difference(consumedAt) < samePressGap) return BackPressResult.ignored;
    final armedAt = _armedAt;
    if (armedAt != null) {
      final elapsed = now.difference(armedAt);
      if (elapsed < samePressGap) return BackPressResult.ignored;
      if (elapsed <= window) return BackPressResult.exit;
    }
    _armedAt = now;
    return BackPressResult.armed;
  }

  /// The press was used for something else (going back to follows). The
  /// count starts over, and repeat callbacks of that same press are ignored.
  void consumed() {
    _armedAt = null;
    _consumedAt = _clock();
  }
}
