import 'dart:async';

/// Abstract base class for platform-specific initialization and lifecycle logic.
abstract class PlatformService {
  /// General platform initialization to run during bootstrap.
  Future<void> initialize();

  /// Platform-specific permission requests.
  Future<bool> requestPermissions();

  /// Setup platform-specific background tasks.
  Future<void> setupBackgroundTasks();

  /// Handle any platform-specific command line arguments or application arguments.
  Future<void> handlePlatformArgs(List<String> args, {required void Function(List<String>) onArgsReceived});
}
