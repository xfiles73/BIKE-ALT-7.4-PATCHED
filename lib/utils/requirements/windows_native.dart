import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';
import 'package:bike_control/utils/windows_store_environment.dart';

const _hive = HKEY_CURRENT_USER;

class WindowsProtocolHandler {
  bool get shouldRegisterForOutsideStoreBuild => WindowsStoreEnvironment.isOutsideStoreCached;

  List<String> getArguments(List<String>? arguments) {
    if (arguments == null) return ['%s'];

    if (arguments.isEmpty && !arguments.any((e) => e.contains('%s'))) {
      throw ArgumentError('arguments must contain at least 1 instance of "%s"');
    }

    return arguments;
  }

  void register(String scheme, {String? executable, List<String>? arguments}) {
    if (defaultTargetPlatform != TargetPlatform.windows) return;

    final prefix = _regPrefix(scheme);
    final capitalized = scheme[0].toUpperCase() + scheme.substring(1);
    final args = getArguments(arguments).map((a) => _sanitize(a));
    final cmd = '${executable ?? Platform.resolvedExecutable} ${args.join(' ')}';

    _regCreateStringKey(_hive, prefix, '', 'URL:$capitalized');
    _regCreateStringKey(_hive,
