import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/home/double_back_exit.dart';

void main() {
  late DateTime now;
  late DoubleBackExit backExit;

  setUp(() {
    now = DateTime(2026);
    backExit = DoubleBackExit(clock: () => now);
  });

  void advance(Duration by) => now = now.add(by);

  test('the first press only arms', () {
    expect(backExit.onBackPressed(), isFalse);
  });

  test('a second press inside the window exits', () {
    backExit.onBackPressed();
    advance(const Duration(seconds: 1));
    expect(backExit.onBackPressed(), isTrue);
  });

  test('a press right at the end of the window still exits', () {
    backExit.onBackPressed();
    advance(DoubleBackExit.window);
    expect(backExit.onBackPressed(), isTrue);
  });

  test('a repeated callback for one press does not exit', () {
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 20));
    expect(backExit.onBackPressed(), isFalse);
  });

  test('the same-press callback keeps the window from the first call', () {
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 20));
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 300));
    expect(backExit.onBackPressed(), isTrue);
  });

  test('a press after the window arms again instead of exiting', () {
    backExit.onBackPressed();
    advance(DoubleBackExit.window + const Duration(milliseconds: 1));
    expect(backExit.onBackPressed(), isFalse);
    advance(const Duration(seconds: 1));
    expect(backExit.onBackPressed(), isTrue);
  });
}
