import 'dart:io';

/// One IPv4 address and the network interface carrying it.
class LanCandidate {
  const LanCandidate(this.interfaceName, this.address);

  final String interfaceName;
  final String address;
}

/// Picks the address a phone on the same LAN can reach. Every QR code and
/// device-sync advertisement goes through here, so they cannot disagree.
///
/// Ranking by address alone is not enough: virtual adapters often own
/// `192.168.*` too, and interfaces that are down are still listed. The
/// interface name is therefore weighed first, then the private range.
///
/// Interfaces are demoted, never dropped: a Hyper-V external switch puts the
/// real LAN on `vEthernet (...)`, and the manual selector has to offer it.
abstract final class LanAddress {
  /// Prefs key of the address picked by hand on the device sync page.
  static const String selectedIpKey = 'syncSelectedIp';

  static final RegExp _virtualPrefix = RegExp(
    r'^(lo\d*$|docker|br-|virbr|veth|vnet|vmnet|vboxnet|cvd-|tun|tap|utun|wg\d|ppp|ipsec|ip6tnl|sit\d|gre\d|gretap|'
    r'dummy|bridge\d|awdl|llw|anpi|p2p|rmnet|ccmni|clat|v4-|wwan|cni|flannel|cali|vxlan|kube|lxc|lxd|incus|podman|'
    r'tailscale|zt|nordlynx)',
    caseSensitive: false,
  );
  static final RegExp _virtualKeyword = RegExp(
    r'vmware|virtualbox|hyper-v|vethernet|wsl|vpn|zerotier|wireguard|clash|mihomo|sing-?tun|wintun|loopback|'
    r'bluetooth|蓝牙|npcap',
    caseSensitive: false,
  );

  /// Only useful to phones joined to this device's own hotspot.
  static final RegExp _hotspot = RegExp(
    r'^(ap\d|swlan|softap|wlan_ap|rndis|ncm|usb|local area connection\*|本地连接\*)',
    caseSensitive: false,
  );

  /// Linux/Android/macOS names plus the English Windows defaults. Localized
  /// Windows names land in the "unknown" tier, which still beats virtual ones.
  static final RegExp _physical = RegExp(r'^(wlan\d|wl[opx]|eth\d|en[opsx0-9]|wi-?fi|ethernet)', caseSensitive: false);

  static bool isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final value = int.tryParse(part);
      return value != null && value >= 0 && value <= 255;
    });
  }

  static bool isPrivateIpv4(String ip) => _rangePriority(ip) > 0;

  static int _rangePriority(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return 0;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == 192 && second == 168) return 3;
    if (first == 10) return 2;
    if (first == 172 && second != null && second >= 16 && second <= 31) return 1;
    return 0;
  }

  static int _interfaceTier(String name) {
    if (_virtualPrefix.hasMatch(name) || _virtualKeyword.hasMatch(name)) return 0;
    if (_hotspot.hasMatch(name)) return 1;
    if (_physical.hasMatch(name)) return 3;
    return 2;
  }

  /// Usable addresses, best first and without duplicates. Equal candidates
  /// keep their input order.
  static List<String> rank(Iterable<LanCandidate> candidates) {
    final usable = <LanCandidate>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final ip = candidate.address.trim();
      if (!isValidIpv4(ip) || ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
      if (seen.add(ip)) usable.add(LanCandidate(candidate.interfaceName, ip));
    }
    final order = {for (var i = 0; i < usable.length; i++) usable[i]: i};
    usable.sort((a, b) {
      final tier = _interfaceTier(b.interfaceName).compareTo(_interfaceTier(a.interfaceName));
      if (tier != 0) return tier;
      final range = _rangePriority(b.address).compareTo(_rangePriority(a.address));
      return range != 0 ? range : order[a]!.compareTo(order[b]!);
    });
    return [for (final candidate in usable) candidate.address];
  }

  /// A manual pick wins while its interface still exists; otherwise the best
  /// ranked address, or null when there is none.
  static String? pick(List<String> ranked, String? manual) {
    if (manual != null && manual.isNotEmpty && ranked.contains(manual)) return manual;
    return ranked.isEmpty ? null : ranked.first;
  }

  /// This device's addresses, best first.
  static Future<List<String>> candidates() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    return rank([
      for (final interface in interfaces)
        for (final address in interface.addresses) LanCandidate(interface.name, address.address),
    ]);
  }
}
