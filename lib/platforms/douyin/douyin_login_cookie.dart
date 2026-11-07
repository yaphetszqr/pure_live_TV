/// Builds the cookie header to store after a web login, or null while the
/// browser session has not signed in yet.
///
/// Visiting Douyin anonymously already sets plenty of cookies (`ttwid`,
/// `msToken`, ...), so only a session cookie proves the scan went through.
String? douyinLoginCookie(Map<String, String> cookies) {
  const List<String> sessionNames = <String>['sessionid', 'sessionid_ss'];
  if (!sessionNames.any((name) => (cookies[name] ?? '').isNotEmpty)) return null;

  return [
    for (final MapEntry<String, String> cookie in cookies.entries)
      if (cookie.key.isNotEmpty && cookie.value.isNotEmpty) '${cookie.key}=${cookie.value}',
  ].join('; ');
}
