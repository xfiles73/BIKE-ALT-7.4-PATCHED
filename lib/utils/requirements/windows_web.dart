/// Stub per Web: le API di registro Windows non sono disponibili.
class WindowsProtocolHandler {
  bool get shouldRegisterForOutsideStoreBuild => false;

  List<String> getArguments(List<String>? arguments) => arguments ?? ['%s'];

  void register(String scheme, {String? executable, List<String>? arguments}) {}

  void registerForOutsideStoreBuild(String scheme,
      {String? executable, List<String>? arguments}) {}

  void unregister(String scheme) {}
}
