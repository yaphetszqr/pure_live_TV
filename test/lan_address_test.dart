import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/utils/lan_address.dart';

void main() {
  List<String> rank(Map<String, String> interfaces) =>
      LanAddress.rank([for (final entry in interfaces.entries) LanCandidate(entry.key, entry.value)]);

  group('LanAddress.rank', () {
    test('real 10.x LAN beats a virtual 192.168.x adapter', () {
      expect(rank({'virbr0': '192.168.122.1', 'eth0': '10.0.0.8'}).first, '10.0.0.8');
    });

    test('real Wi-Fi beats virtual adapters listed before it', () {
      expect(
        rank({'cvd-ebr': '192.168.98.1', 'cvd-wbr': '192.168.96.1', 'wlo1': '192.168.5.24'}).first,
        '192.168.5.24',
      );
    });

    test('Wi-Fi Direct and hotspot lose to the LAN on Android', () {
      expect(rank({'p2p0': '192.168.49.1', 'ap0': '192.168.43.1', 'wlan0': '172.20.1.9'}).first, '172.20.1.9');
    });

    test('VPN and TUN addresses lose to the LAN', () {
      expect(rank({'tun0': '10.8.0.2', 'Clash': '198.18.0.1', 'wlan0': '192.168.1.5'}).first, '192.168.1.5');
    });

    test('Windows virtual adapters lose to a localized real adapter', () {
      expect(
        rank({
          'vEthernet (WSL)': '172.22.0.1',
          'VMware Network Adapter VMnet8': '192.168.80.1',
          '以太网': '192.168.31.20',
        }).first,
        '192.168.31.20',
      );
    });

    test('"Local Area Connection" is not mistaken for loopback', () {
      expect(rank({'lo0': '192.168.9.9', 'Local Area Connection': '192.168.1.2'}).first, '192.168.1.2');
    });

    test('a virtual adapter is still offered as the last resort', () {
      expect(rank({'vEthernet (External)': '192.168.1.7'}), ['192.168.1.7']);
    });

    test('drops loopback, link-local, invalid and duplicate addresses', () {
      expect(
        LanAddress.rank(const [
          LanCandidate('eth0', '127.0.0.1'),
          LanCandidate('eth0', '169.254.1.1'),
          LanCandidate('eth0', 'not-an-ip'),
          LanCandidate('eth0', '192.168.1.5'),
          LanCandidate('wlan0', '192.168.1.5'),
        ]),
        ['192.168.1.5'],
      );
    });

    test('equal candidates keep their order across a long list', () {
      final addresses = [for (var i = 1; i <= 40; i++) '192.168.1.$i'];
      expect(LanAddress.rank([for (final ip in addresses) LanCandidate('wlan0', ip)]), addresses);
    });
  });

  group('LanAddress.pick', () {
    const ranked = ['192.168.1.5', '10.0.0.8'];

    test('prefers a manual pick that still exists', () {
      expect(LanAddress.pick(ranked, '10.0.0.8'), '10.0.0.8');
    });

    test('falls back to the best address for a stale or empty pick', () {
      expect(LanAddress.pick(ranked, '172.16.0.1'), '192.168.1.5');
      expect(LanAddress.pick(ranked, ''), '192.168.1.5');
      expect(LanAddress.pick(ranked, null), '192.168.1.5');
    });

    test('returns null without candidates', () {
      expect(LanAddress.pick(const [], '10.0.0.8'), isNull);
    });
  });
}
