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
  });
  final String instanceId;
  final String name;
  final Uri endpoint;
  final String platform;
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

  Future<void> start({required String name, required int port}) async {
    final broadcast = BonsoirBroadcast(
      printLogs: false,
      service: BonsoirService(
        name: name,
        type: serviceType,
        port: port,
        attributes: {
          'v': '1',
          'id': instanceId,
          'os': Platform.operatingSystem,
        },
      ),
    );
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
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
  final ordinary = interfaces.where(
    (interface) => !RegExp(
      r'^(tun|tap|utun|rmnet|pdp|lo)',
      caseSensitive: false,
    ).hasMatch(interface.name),
  );
  return ordinary
      .expand((interface) => interface.addresses)
      .where((address) => !address.isLoopback && !address.isLinkLocal)
      .map((address) => address.address)
      .toSet()
      .toList();
}
