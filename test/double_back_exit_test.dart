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
    expect(backExit.onBackPressed(), BackPressResult.armed);
  });

  test('a second press inside the window exits', () {
    backExit.onBackPressed();
    advance(const Duration(seconds: 1));
    expect(backExit.onBackPressed(), BackPressResult.exit);
  });

  test('a press right at the end of the window still exits', () {
    backExit.onBackPressed();
    advance(DoubleBackExit.window);
    expect(backExit.onBackPressed(), BackPressResult.exit);
  });

  test('a repeated callback for one press is ignored', () {
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 20));
    expect(backExit.onBackPressed(), BackPressResult.ignored);
  });

  test('the same-press callback keeps the window from the first call', () {
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 20));
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 300));
    expect(backExit.onBackPressed(), BackPressResult.exit);
  });

  test('a press after the window arms again instead of exiting', () {
    backExit.onBackPressed();
    advance(DoubleBackExit.window + const Duration(milliseconds: 1));
    expect(backExit.onBackPressed(), BackPressResult.armed);
    advance(const Duration(seconds: 1));
    expect(backExit.onBackPressed(), BackPressResult.exit);
  });

  test('a press used for going back to follows starts the count over', () {
    backExit.onBackPressed();
    advance(const Duration(milliseconds: 500));
    backExit.consumed();
    advance(const Duration(milliseconds: 500));
    expect(backExit.onBackPressed(), BackPressResult.armed);
  });

  test('repeat callbacks of the consumed press are ignored', () {
    backExit.consumed();
    advance(const Duration(milliseconds: 20));
    expect(backExit.onBackPressed(), BackPressResult.ignored);
  });
}
