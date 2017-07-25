# jaguar_hotreload

Hot reloader for Dart

# Docs

## Reloading application on file modification

[HotReloader] lets the application hot reload itself on modifications to desired files.

```dart
main() async {
  final reloader = new HotReloader();
  reloader.addPath('.');
  await reloader.go();

  // TODO your code here!
}
```

## VM service

[HotReloader] requires that VM service is enabled during program run for reloading to work. To enable VM services supply
either `--enable-vm-service` or `--observe` command line flag when the application is run.

Failing to do so will result in `notHotReloadable` exception.

More information can be found at [Dart VM](https://www.dartlang.org/dart-vm/tools/dart-vm)

## Debouncing

When there are too many changes, it is not efficient to reload the application for every change. Debouncing allows
[HotReloader] to reload only once every specified interval. `debounceInterval` defaults to once every second.

```dart
main() async {
  final reloader = new HotReloader(debounceInterval: const Duration(seconds: 10));
  reloader.addPath('.');
  await reloader.go();

  // TODO your code here!
}
```

## Adding paths to listen

### Using String path

`addPath` method shall be used to register file/directory path as [String].

```dart
main() async {
    final reloader = new HotReloader();
    reloader.addPath('lib/');
    await reloader.go();
    
    // Your code goes here
}
```

### Using Glob

`addGlob` shall be used to register multiple files/directories using a [Glob].

```dart
main() async {
    final reloader = new HotReloader();
    reloader.addGlob(new Glob('jaguar_*/lib'));
    await reloader.go();
    
    // Your code goes here
}
```

### Using FileSystemEntity

`addFile` shall be used to register a `FileSystemEntity`.


```dart
main() async {
    final reloader = new HotReloader();
    reloader.addFile(new File('pubspec.yaml'));
    await reloader.go();
    
    // Your code goes here
}
```

### Using Uri

`addUri` shall be used to register a path using an instance of [Uri].


```dart
main() async {
    final reloader = new HotReloader();
    reloader.addUri(new Uri(scheme: 'file', path: '/usr/lib/dart'));
    await reloader.go();
    
    // Your code goes here
}
```

### Using package Uri

`addPackagePath` shall be used to register a path using package uri.

```dart
main() async {
    final reloader = new HotReloader();
    await reloader.addPackagePath(new Uri(scheme: 'package', path: 'jaguar/'));
    await reloader.go();
    
    // Your code goes here
}
```

### Using package dependencies

`addPackageDependencies` shall be used to register all packages the current package depends on.

```dart
main() async {
    final reloader = new HotReloader();
    await reloader.addPackageDependencies();
    await reloader.go();
    
    // Your code goes here
}
```

## Manually reloading the application

`reload` method is publicly available to request for application reload when desired.

## Event

### File modification event

`onChange` stream is fired every time there is a change in the registered file paths.

### Reload event

`onReload` stream is fired after the application is reloaded irrespective of whether the file change or the user triggered
 the reload.
