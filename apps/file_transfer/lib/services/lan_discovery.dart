import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:uuid/uuid.dart';

class DiscoveredEndpoint {
  const DiscoveredEndpoint({
    required this.instanceId,
    required this.name,
    required this.endpoint,
    required this.platform,
    this.pairable = false,
  });
  final String instanceId;
  final String name;
  final Uri endpoint;
  final String platform;

  /// The device advertises an open nearby pairing window (TXT `pair=1`).
  /// Only a hint: the invitation fetched from it must match the TLS key, and
  /// the host still approves after comparing six-digit codes.
  final bool pairable;
}

/// Bonjour/NSD is an untrusted address hint. Authentication is exclusively the
/// pinned TLS connection established later by CoreClient, never this record.
class LanDiscovery {
  static const serviceType = '_xferapp._tcp';
  final instanceId = const Uuid().v4();
  final _changes = StreamController<List<DiscoveredEndpoint>>.broadcast();
  final _found = <String, DiscoveredEndpoint>{};
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;

  Stream<List<DiscoveredEndpoint>> get changes => _changes.stream;
  List<DiscoveredEndpoint> get endpoints => List.unmodifiable(_found.values);

  String? _name;
  int? _port;
  bool _pairable = false;

  Future<void> _startBroadcast() async {
    final broadcast = BonsoirBroadcast(
      printLogs: false,
      service: BonsoirService(
        name: _name!,
        type: serviceType,
        port: _port!,
        attributes: {
          'v': '1',
          'id': instanceId,
          'os': Platform.operatingSystem,
          if (_pairable) 'pair': '1',
        },
      ),
    );
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
  }

  /// Re-announces this device with or without the nearby-pairing hint.
  /// Bonjour records cannot be edited in place: the broadcast restarts.
  Future<void> setPairable(bool pairable) async {
    if (_pairable == pairable) return;
    _pairable = pairable;
    if (_name == null) return;
    try {
      await _broadcast?.stop();
    } catch (_) {
      /* Already stopped. */
    }
    await _startBroadcast();
  }

  Future<void> start({required String name, required int port}) async {
    _name = name;
    _port = port;
    await _startBroadcast();
    final discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
    _discovery = discovery;
    await discovery.initialize();
    _subscription = discovery.eventStream?.listen(
      (event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          discovery.serviceResolver.resolveService(event.service);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
            event is BonsoirDiscoveryServiceUpdatedEvent) {
          final service = event.service;
          if (service == null ||
              service.attributes['v'] != '1' ||
              service.attributes['id'] == instanceId ||
              service.port < 1 ||
              service.port > 65535) {
            return;
          }
          final id = service.attributes['id'];
          if (id == null || id.length > 128 || service.name.length > 256) {
            return;
          }
          // Alpha listens on IPv4. Do not advertise an untested IPv6 fallback.
          final address = service.hostAddresses.where((address) {
            final ip = InternetAddress.tryParse(address);
            return ip != null &&
                ip.type == InternetAddressType.IPv4 &&
                !ip.isLoopback &&
                ip.address != '0.0.0.0';
          }).firstOrNull;
          if (address == null ||
              (_found.length >= 64 && !_found.containsKey(id))) {
            return;
          }
          _found[id] = DiscoveredEndpoint(
            instanceId: id,
            name: service.name,
            endpoint: Uri(scheme: 'https', host: address, port: service.port),
            platform: service.attributes['os'] ?? 'unknown',
            pairable: service.attributes['pair'] == '1',
          );
          _emit();
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          _found.remove(event.service.attributes['id']);
          _emit();
        }
      },
      onError: (Object _) {
        _found.clear();
        _emit();
      },
    );
    await discovery.start();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(endpoints);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    try {
      await _discovery?.stop();
    } catch (_) {
      /* Already stopped. */
    }
    try {
      await _broadcast?.stop();
    } catch (_) {
      /* Already stopped. */
    }
    _found.clear();
    await _changes.close();
  }
}

Future<List<String>> localIpv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return rankLanAddresses([
    for (final interface in interfaces)
      for (final address in interface.addresses)
        (interface.name, address.address),
  ]);
}

/// Orders candidate (interface, IPv4) pairs so that the address most likely
/// reachable by another device on the same Wi-Fi/Ethernet comes first.
/// Virtual adapters (VPN, Hyper-V/WSL, Docker, VM bridges) and link-local
/// addresses are excluded; private LAN ranges on Wi-Fi/Ethernet win.
List<String> rankLanAddresses(List<(String, String)> candidates) {
  final excluded = RegExp(
    r'^(tun|tap|utun|ipsec|ppp|rmnet|pdp|ccmni|lo|docker|br-|veth|virbr|vmnet|'
    r'vboxnet|zt|wg|tailscale|awdl|llw|bridge|anpi|gif|stf)|'
    r'(vethernet|hyper-v|wsl|virtualbox|vmware|loopback|bluetooth)',
    caseSensitive: false,
  );
  final preferred = RegExp(
    r'^(en0|en1|wlan|wlp|wl|eth|enp|eno|ens|ap|swlan|wi-?fi|ethernet|беспровод)',
    caseSensitive: false,
  );
  int score(String name, InternetAddress ip) {
    final bytes = ip.rawAddress;
    var value = 0;
    if (preferred.hasMatch(name)) value += 100;
    if (bytes[0] == 192 && bytes[1] == 168) value += 40;
    if (bytes[0] == 10) value += 30;
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) value += 20;
    // Carrier-grade NAT (cellular) is rarely reachable from the LAN.
    if (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) value -= 50;
    return value;
  }

  final scored = <String, int>{};
  for (final (name, text) in candidates) {
    final ip = InternetAddress.tryParse(text);
    if (ip == null ||
        ip.type != InternetAddressType.IPv4 ||
        ip.isLoopback ||
        ip.isLinkLocal ||
        ip.address == '0.0.0.0' ||
        excluded.hasMatch(name)) {
      continue;
    }
    final value = score(name, ip);
    if (!scored.containsKey(ip.address) || scored[ip.address]! < value) {
      scored[ip.address] = value;
    }
  }
  final ordered = scored.keys.toList()
    ..sort((a, b) => scored[b]!.compareTo(scored[a]!));
  return ordered;
}
