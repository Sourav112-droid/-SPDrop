import 'platform_service.dart';

class StubPlatform implements PlatformService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async {
    return true;
  }

  @override
  Future<void> setupBackgroundTasks() async {}

  @override
  Future<void> handlePlatformArgs(List<String> args, {required void Function(List<String>) onArgsReceived}) async {}
}

PlatformService getPlatformService() => StubPlatform();
