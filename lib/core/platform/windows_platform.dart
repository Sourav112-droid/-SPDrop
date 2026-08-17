import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'platform_service.dart';

class WindowsPlatform implements PlatformService {
  @override
  Future<void> initialize() async {
    // Windows auto-start registry
    _setupWindowsAutoStart();
    
    // Create SendTo shortcut
    _createWindowsSendToShortcut();
    
    // Fix firewall rules
    fixFirewall();
  }

  @override
  Future<bool> requestPermissions() async {
    // Windows doesn't require explicit permission requests for standard operation
    return true;
  }

  @override
  Future<void> setupBackgroundTasks() async {
    // Managed via initialize and handlePlatformArgs on Windows
  }

  @override
  Future<void> handlePlatformArgs(List<String> args, {required void Function(List<String>) onArgsReceived}) async {
    final bool startInTray = args.contains('--tray');

    await WindowsSingleInstance.ensureSingleInstance(args, "SpDrop_Instance", onSecondWindow: (newArgs) {
      onArgsReceived(newArgs);
    });

    await windowManager.ensureInitialized();
    // ALWAYS prevent close on Windows, not just --tray mode.
    // This ensures the close event is intercepted even if SystemTrayService
    // hasn't finished initializing when the user clicks X.
    await windowManager.setPreventClose(true);
    // If starting in tray mode, hide window immediately
    if (startInTray) {
      await windowManager.hide();
    }
  }

  // Windows auto-start via registry
  void _setupWindowsAutoStart() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final psCommand =
          'if (-not (Get-ItemProperty -Path \'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\' -Name \'SpDrop\' -ErrorAction SilentlyContinue)) { New-ItemProperty -Path \'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\' -Name \'SpDrop\' -Value \'"$exePath" --tray\' -PropertyType String -Force }';
      await Process.run('powershell', ['-Command', psCommand]);
    } catch (_) {
      // Silent fail – auto-start is optional
    }
  }

  Future<void> _createWindowsSendToShortcut() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final exePath = Platform.resolvedExecutable;
      final script = '''
\$targetPath = "$exePath"
\$shortcutPath = "\$env:APPDATA\\Microsoft\\Windows\\SendTo\\SpDrop.lnk"
\$WshShell = New-Object -comObject WScript.Shell
\$Shortcut = \$WshShell.CreateShortcut(\$shortcutPath)
\$Shortcut.TargetPath = \$targetPath
\$Shortcut.Save()
''';
      await Process.run('powershell', ['-Command', script]);
    } catch (e) {
      debugPrint('Error creating SendTo shortcut: $e');
    }
  }

  /// Checks whether Windows firewall rule already exists before requesting elevation.
  void fixFirewall() async {
    try {
      // Check if rule already exists – no UAC needed for this check
      final check = await Process.run('netsh', [
        'advfirewall', 'firewall', 'show', 'rule', 'name=SpDrop',
      ]);
      if (check.stdout.toString().contains('SpDrop')) return; // Rule exists

      // Only prompt UAC if rule is missing
      final exePath = Platform.resolvedExecutable;
      final psCommand =
          'Start-Process netsh -ArgumentList "advfirewall firewall add rule name=\\"SpDrop\\" dir=in action=allow program=\\"$exePath\\" enable=yes" -Verb RunAs -WindowStyle Hidden';
      await Process.run('powershell', ['-Command', psCommand]);
    } catch (_) {}
  }
}
