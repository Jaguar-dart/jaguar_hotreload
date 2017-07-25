// Copyright (c) 2017, teja. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:jaguar_hotreload/jaguar_hotreload.dart';

int count = 0;

main() async {
  final reloader = new HotReloader();
  reloader.addPath('.');
  await reloader.addPackageDependencies();
  await reloader.go();

  new Timer.periodic(new Duration(seconds: 1), (_) {
    print(count++);
  });
}
