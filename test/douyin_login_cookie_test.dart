import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platforms/douyin/douyin_login_cookie.dart';

void main() {
  test('anonymous cookies are not a login', () {
    expect(douyinLoginCookie({'ttwid': 'a', 'msToken': 'b'}), isNull);
  });

  test('an empty session cookie is not a login', () {
    expect(douyinLoginCookie({'sessionid': '', 'ttwid': 'a'}), isNull);
  });

  test('a session cookie yields the whole cookie header', () {
    expect(douyinLoginCookie({'ttwid': 'a', 'sessionid': 'b'}), 'ttwid=a; sessionid=b');
  });

  test('sessionid_ss alone counts as a login', () {
    expect(douyinLoginCookie({'sessionid_ss': 'b'}), 'sessionid_ss=b');
  });

  test('blank cookies are left out', () {
    expect(douyinLoginCookie({'sessionid': 'b', 'empty': ''}), 'sessionid=b');
  });
}
