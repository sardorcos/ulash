import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// [SecureSocket] view of a [RawSecureSocket], for `HttpServer.listenOn`.
///
/// dart:io offers no public way to turn a raw secure socket into a
/// [SecureSocket], and `SecureSocket.secureServer` detaches the accepted
/// socket so it can no longer be destroyed while the TLS handshake runs. The
/// host therefore accepts [RawSocket]s (closable at any moment, which is what
/// enforces the handshake deadline and eviction) and runs the handshake with
/// [RawSecureSocket.secureServer], then adapts the result here.
///
/// Semantics follow the SDK socket: reads honour pause (backpressure through
/// `readEventsEnabled`), writes are queued and drained on write events,
/// [close] half-closes the send side after the queue drains, and [destroy]
/// closes immediately.
final class SecureSocketAdapter extends Stream<Uint8List>
    implements SecureSocket {
  SecureSocketAdapter(this._raw) {
    _controller = StreamController<Uint8List>(
      sync: true,
      onPause: () => _setReading(false),
      onResume: () => _setReading(true),
      onCancel: () {
        // Like the SDK socket: stop receiving, keep the send side usable.
        _controllerClosed = true;
        if (!_destroyed) {
          try {
            _raw.shutdown(SocketDirection.receive);
          } catch (_) {
            /* Already closed. */
          }
        }
      },
    );
    _subscription = _raw.listen(
      _onEvent,
      onError: _onError,
      onDone: _onRawDone,
      cancelOnError: true,
    );
  }

  final RawSecureSocket _raw;
  late final StreamController<Uint8List> _controller;
  late final StreamSubscription<RawSocketEvent> _subscription;
  final _queue = Queue<_Chunk>();
  var _queuedBytes = 0;
  final _flushWaiters = <Completer<void>>[];
  final _done = Completer<Socket>();
  StreamSubscription<List<int>>? _source;
  bool _sourcePaused = false;
  bool _controllerClosed = false;
  bool _closing = false;
  bool _destroyed = false;

  static const int _highWater = 256 * 1024;

  @override
  Encoding encoding = utf8;

  void _setReading(bool enabled) {
    if (_destroyed) return;
    try {
      _raw.readEventsEnabled = enabled;
    } catch (_) {
      /* Closed. */
    }
  }

  void _onEvent(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        if (_controllerClosed) return;
        final data = _raw.read();
        if (data != null && data.isNotEmpty) _controller.add(data);
      case RawSocketEvent.write:
        _drain();
      case RawSocketEvent.readClosed:
      case RawSocketEvent.closed:
        _closeController();
    }
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    if (!_controllerClosed) {
      _controllerClosed = true;
      _controller.addError(error, stackTrace);
      unawaited(_controller.close());
    }
    _fail(error, stackTrace);
    destroy();
  }

  void _onRawDone() {
    _closeController();
    _destroyed = true;
    _finish();
  }

  void _closeController() {
    if (_controllerClosed) return;
    _controllerClosed = true;
    unawaited(_controller.close());
  }

  void _drain() {
    if (_destroyed) return;
    try {
      while (_queue.isNotEmpty) {
        final chunk = _queue.first;
        final written = _raw.write(chunk.bytes, chunk.offset);
        chunk.offset += written;
        _queuedBytes -= written;
        if (chunk.offset < chunk.bytes.length) {
          _raw.writeEventsEnabled = true;
          return;
        }
        _queue.removeFirst();
      }
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
      return;
    }
    if (_sourcePaused && _queuedBytes < _highWater) {
      _sourcePaused = false;
      _source?.resume();
    }
    for (final waiter in _flushWaiters) {
      waiter.complete();
    }
    _flushWaiters.clear();
    if (_closing && _source == null) {
      try {
        _raw.shutdown(SocketDirection.send);
      } catch (_) {
        /* Already closed. */
      }
      _finish();
    }
  }

  void _finish() {
    for (final waiter in _flushWaiters) {
      waiter.complete();
    }
    _flushWaiters.clear();
    if (!_done.isCompleted) _done.complete(this);
  }

  void _fail(Object error, StackTrace? stackTrace) {
    for (final waiter in _flushWaiters) {
      waiter.completeError(error, stackTrace);
    }
    _flushWaiters.clear();
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(List<int> data) {
    if (_closing) throw StateError('StreamSink is closed');
    if (_source != null) throw StateError('StreamSink is bound to a stream');
    _enqueue(data);
  }

  void _enqueue(List<int> data) {
    if (_destroyed || data.isEmpty) return;
    _queue.add(_Chunk(data));
    _queuedBytes += data.length;
    _drain();
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (_closing) throw StateError('StreamSink is closed');
    if (_source != null) throw StateError('StreamSink is bound to a stream');
    final completer = Completer<void>();
    _source = stream.listen(
      (data) {
        _enqueue(data);
        if (_queuedBytes >= _highWater && !_sourcePaused) {
          _sourcePaused = true;
          _source?.pause();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _source = null;
        destroy();
        completer.completeError(error, stackTrace);
      },
      onDone: () {
        _source = null;
        _sourcePaused = false;
        completer.complete();
        if (_closing) _drain();
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _fail(error, stackTrace);
    destroy();
  }

  @override
  Future<void> flush() {
    if (_destroyed || _queue.isEmpty) return Future<void>.value();
    final waiter = Completer<void>();
    _flushWaiters.add(waiter);
    return waiter.future;
  }

  @override
  Future<void> close() {
    if (!_closing) {
      _closing = true;
      if (_source == null) _drain();
    }
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _queue.clear();
    _queuedBytes = 0;
    unawaited(_source?.cancel());
    _source = null;
    unawaited(_subscription.cancel());
    try {
      _raw.close();
    } catch (_) {
      /* Already closed. */
    }
    _closeController();
    _finish();
  }

  @override
  void write(Object? object) {
    final text = '$object';
    if (text.isEmpty) return;
    add(encoding.encode(text));
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeln([Object? object = '']) {
    write('$object\n');
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  InternetAddress get address => _raw.address;
  @override
  int get port => _raw.port;
  @override
  InternetAddress get remoteAddress => _raw.remoteAddress;
  @override
  int get remotePort => _raw.remotePort;
  @override
  X509Certificate? get peerCertificate => _raw.peerCertificate;
  @override
  String? get selectedProtocol => _raw.selectedProtocol;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _raw.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _raw.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _raw.setRawOption(option);

  @override
  // ignore: deprecated_member_use
  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
  }) => throw UnsupportedError('TLS renegotiation is not supported.');
}

final class _Chunk {
  _Chunk(this.bytes);
  final List<int> bytes;
  int offset = 0;
}
