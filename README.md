# jaguar_hotreload

Hot reloader for Dart

# Example

```dart
main() async {
  final reloader = new HotReloader();
  reloader.addPath('.');
  await reloader.go();

  // TODO your code here!
}
```
