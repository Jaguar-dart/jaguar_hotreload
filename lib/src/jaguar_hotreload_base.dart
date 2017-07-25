// Copyright (c) 2017, teja. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:glob/glob.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart' show vmServiceConnectUri;
import 'package:vm_service_lib/vm_service_lib.dart'
    show VM, VmService, IsolateRef, ReloadReport;
import 'package:watcher/watcher.dart';

const String _kVmServiceUrl = 'ws://localhost:8181/ws';

/// Encapsulates Hot reloader path
class HotReloaderPath {
  /// [HotReloader] the path belongs to
  final HotReloader reloader;

  /// [path] being watched
  String get path => watcher.path;

  /// The watcher
  final Watcher watcher;

  /// Subscription
  StreamSubscription<WatchEvent> _sub;

  HotReloaderPath._(this.reloader, String path) : watcher = new Watcher(path);

  /// Is this path being watched
  bool get isWatching => _sub != null;

  /// Stops watching
  Future _stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Hot reloader
///
///     final reloader = new HotReloader();
///     reloader.addPath('.');
///     await reloader.go();
///
/// ## VM services
/// Hot reloading requires that VM service is enabled! VM services can be started
/// by passing `--enable-vm-service` or `--observe` command line flags while
/// starting the application.
///
/// `--enable-vm-service=<port>/<IP address>` and `--enable-vm-service=<port>`
/// can be used to start VM services at desired address.
///
/// More information can be found at: https://www.dartlang.org/dart-vm/tools/dart-vm
class HotReloader {
  /// The URL of the Dart VM service.
  ///
  /// This is used to connect to Dart VM service to request hot reloading.
  ///
  /// Hot reloading requires that VM service is enabled! VM services can be started
  /// by passing `--enable-vm-service` or `--observe` command line flags while
  /// starting the application.
  ///
  /// `--enable-vm-service=<port>/<IP address>` and `--enable-vm-service=<port>`
  /// can be used to start VM services at desired address.
  ///
  /// More information can be found at: https://www.dartlang.org/dart-vm/tools/dart-vm
  final String vmServiceUrl;

  /// Debounce interval for [onChange] event
  final Duration debounceInterval;

  /// Stream controller to fire events when any of the file being listened to
  /// changes
  final StreamController<WatchEvent> _onChange =
      new StreamController<WatchEvent>.broadcast();

  /// Stream that is fired when any of the file being listened to changes
  Stream<WatchEvent> get onChange => _onChange.stream;

  /// Stream controller to fire events when the application is reloaded
  final StreamController<DateTime> _onReload =
      new StreamController<DateTime>.broadcast();

  /// Stream that is fired after the application is reloaded
  Stream<DateTime> get onReload => _onReload.stream;

  /// [VmService] client to request hot reloading
  VmService _client;

  /// Stream subscription for [_onChange]
  StreamSubscription _onChangeSub;

  /// Private variable to track if the hot reloader is running
  bool _isRunning = false;

  /// Is the hot reloader running?
  bool get isRunning => _isRunning;

  /// Store for registered paths
  final Set<String> _registeredPaths = new Set<String>();

  /// Store for built [HotReloaderPath]s
  final Map<String, HotReloaderPath> _builtPaths =
      new Map<String, HotReloaderPath>();

  /// Creates a [HotReloader] with given [vmServiceUrl]
  ///
  /// By default, [vmServiceUrl] uses `ws://localhost:8181/ws`
  HotReloader(
      {this.vmServiceUrl: _kVmServiceUrl,
      this.debounceInterval: const Duration(seconds: 5)}) {
    if (!isHotReloadable) throw notHotReloadable;

    _onChangeSub = onChange
        .transform(new _FoldedDebounce(debounceInterval))
        .listen((List<WatchEvent> events) async {
      final sb = new StringBuffer();
      sb.write('Paths ');
      sb.write(events.map((WatchEvent event) => event.path).join(', '));
      sb.write( ' changed!');
      print(sb.toString());
      await reload();
    });
  }

  /// Is the application hot reloadable?
  ///
  /// Hot reloading requires that VM service is enabled! VM services can be started
  /// by passing `--enable-vm-service` or `--observe` command line flags while
  /// starting the application.
  ///
  /// `--enable-vm-service=<port>/<IP address>` and `--enable-vm-service=<port>`
  /// can be used to start VM services at desired address.
  ///
  /// More information can be found at: https://www.dartlang.org/dart-vm/tools/dart-vm
  static bool get isHotReloadable =>
      Platform.executableArguments.contains('--observe') ||
      Platform.executableArguments.contains('--enable-vm-service');

  /// Go! Start listening for changes to files in registered paths
  ///
  /// If already running, restarts the hot reloader
  Future go() async {
    // If already killed, provide an explanation for failure
    if (_onChange.isClosed) throw alreadyKilled;

    // If currently running, restart
    if (_isRunning) {
      await stop();
    }

    final hps = <String, HotReloaderPath>{};

    for (String path in _registeredPaths) {
      final String resolvedPath = await _resolvePath(path);
      if (resolvedPath != null)
        hps[path] = new HotReloaderPath._(this, resolvedPath);
    }

    _builtPaths.clear();
    _builtPaths.addAll(hps);

    _builtPaths.values.forEach((HotReloaderPath hp) {
      hp._sub = hp.watcher.events.listen(_onChange.add, onError: (e) {
        stderr.writeln('Error listening to file changes at ${hp.path}: $e');
      });
      print('Listening for file changes at ${hp.path}...');
    });
  }

  /// Stops listening for file system changes
  Future stop() async {
    for (HotReloaderPath hp in _builtPaths.values) {
      await hp._stop();
    }

    _builtPaths.clear();
  }

  /// Completely kills the hot reloader. Shall not be used, once it is killed!
  Future kill() async {
    if (_onChange.isClosed) return;

    await _onChange.close();
    await _onChangeSub?.cancel();
    _onChangeSub = null;

    await _onReload.close();

    stop();
  }

  /// Registers a [path] to watch
  void addPath(String path) => _registeredPaths.add(path);

  /// Registers [glob] to watch
  void addGlob(Glob glob) {
    final List<FileSystemEntity> entities = glob.listSync();
    entities.forEach(addFile);
  }

  /// Registers [FileSystemEntity] to watch
  void addFile(FileSystemEntity entity) => addPath(entity.path);

  /// Registers [Uri] to watch
  void addUri(Uri uri) => addPath(uri.path);

  /// Registers package [uri] to watch
  ///
  /// If schema of the [uri] is not `'package'`, throws [notPackageUri]
  /// If package uri cannot be resolved, throws [packageNotFound]
  Future addPackagePath(Uri uri) async {
    if (!uri.isScheme('package')) throw notPackageUri;
    final Uri packageUri = await Isolate.resolvePackageUri(uri);
    if (packageUri == null) throw packageNotFound;
    addPath(uri.toFilePath());
  }

  /// Exception thrown when supplied package uri is not a package uri
  static final notPackageUri = new Exception('Not a package Uri!');

  /// Exception thrown when package is not found
  static final packageNotFound = new Exception('Package not found!');

  /// Exception thrown when hot reloader is already killed
  static final alreadyKilled =
      new Exception('Hot reloader killed! Create new one!');

  static final notHotReloadable = new Exception(_msg);

  static String _msg = '''
Hot reloading requires `--enable-vm-service` or `--observe` command line flags to the Dart VM!
More information can be found at: https://www.dartlang.org/dart-vm/tools/dart-vm
  ''';

  /// Returns all the registered paths
  List<String> get registeredPaths => _registeredPaths.toList();

  /// Returns all the paths being listened to
  ///
  /// Returns empty list, when the hot reloader is not listening
  List<String> get listeningPaths => _builtPaths.keys.toList();

  /// Returns if [path] is being listened to
  bool isListeningTo(String path) => _builtPaths.containsKey(path);

  /// Resolves the given path
  ///
  /// If [path] is link, it resolves the link
  /// If the [path] is not found, `null` is returned
  Future<String> _resolvePath(String path) async {
    try {
      final FileStat stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.LINK) {
        final lnk = new Link(path);
        final String p = await lnk.resolveSymbolicLinks();
        return await _resolvePath(p);
      } else if (stat.type == FileSystemEntityType.FILE) {
        final file = new File(path);
        if (!await file.exists()) return null;
      } else if (stat.type == FileSystemEntityType.DIRECTORY) {
        final dir = new Directory(path);
        if (!await dir.exists()) return null;
      } else
        return null;
      return path;
    } catch (e) {
      if (e is! FileSystemException) rethrow;
    }

    return null;
  }

  /// Reloads the application
  Future<Null> reload() async {
    print('Reloading the application...');

    // Get vm service
    if (_client == null) _client = await vmServiceConnectUri(vmServiceUrl);

    // Find main isolate id to reload it
    final VM vm = await _client.getVM();
    final IsolateRef ref = vm.isolates.first;

    // Reload
    final ReloadReport rep = await _client.reloadSources(ref.id);

    if (!rep.success) throw new Exception('Reloading failed! Reason: $rep');

    _onReload.add(new DateTime.now());
  }
}

/// Debouncer to combine all [WatchEvent]s between [interval] into one event
class _FoldedDebounce implements StreamTransformer<WatchEvent, List<WatchEvent>> {
  final Duration interval;

  _FoldedDebounce(Duration duration) : interval = duration;

  Stream<List<WatchEvent>> bind(Stream<WatchEvent> stream) {
    // List to hold items between intervals
    List<WatchEvent> values = <WatchEvent>[];
    // Tracks when next interval ends
    DateTime next = new DateTime.now().subtract(this.interval);

    return stream.map((WatchEvent e) {
      values.add(e);
      return values;
    }).where((List<WatchEvent> value) {
      final now = new DateTime.now();
      if (now.isBefore(next)) {
        return false;
      }

      next = now.add(this.interval);
      values = <WatchEvent>[];
      return true;
    }).timeout(interval, onTimeout: (EventSink<List<WatchEvent>> sink) {
      if(values.length == 0) return;
      next = new DateTime.now().add(this.interval);
      final tempValues = values;
      values = <WatchEvent>[];
      sink.add(tempValues);
    });
  }
}
