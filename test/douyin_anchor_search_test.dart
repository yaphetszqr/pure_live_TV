import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/index.dart';
import 'package:pure_live/platforms/douyin/douyin_search.dart';

void main() {
  LiveRoom room(String id, String nick, {LiveStatus status = LiveStatus.live}) =>
      LiveRoom(roomId: id, nick: nick, avatar: 'a$id', liveStatus: status);

  test('maps a room onto its streamer', () {
    final anchors = DouyinSearch.anchorsFromRooms([room('1', 'alice')]);
    expect(anchors.single.roomId, '1');
    expect(anchors.single.userName, 'alice');
    expect(anchors.single.avatar, 'a1');
    expect(anchors.single.liveStatus, isTrue);
  });

  test('keeps one entry per room', () {
    expect(DouyinSearch.anchorsFromRooms([room('1', 'alice'), room('1', 'alice'), room('2', 'bob')]).length, 2);
  });

  test('drops rooms without a streamer name', () {
    expect(DouyinSearch.anchorsFromRooms([room('1', '')]), isEmpty);
  });

  test('reports a room that is not live', () {
    expect(DouyinSearch.anchorsFromRooms([room('1', 'alice', status: LiveStatus.offline)]).single.liveStatus, isFalse);
  });
}
