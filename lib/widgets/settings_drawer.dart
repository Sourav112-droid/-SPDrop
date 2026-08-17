import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/theme_service.dart';
import '../shared/widgets/glass_card.dart';
import '../features/transfer/models/transfer_record.dart';
import '../services/clipboard_privacy_service.dart';
import '../features/pairing/models/trusted_device.dart';

class SettingsDrawer extends StatefulWidget {
  final String deviceName;
  final String? connectedDeviceName;
  final bool isConnected;
  final bool isOfflineMode;
  final bool isOfflineModeLoading;
  final bool notificationsEnabled;
  final bool clipboardSyncEnabled;
  final List<TrustedDevice> trustedDevices;

  final VoidCallback onToggleOfflineMode;
  final ValueChanged<bool> onNotificationsChanged;
  final VoidCallback onOpenNotificationSettings;
  final ValueChanged<bool> onClipboardSyncChanged;
  final void Function(TrustedDevice) onDisconnectDevice;
  final void Function(TrustedDevice) onConnectDevice;
  final Future<void> Function(String?) onSetDefaultDevice;
  final Future<void> Function(String) onRemoveTrustedDevice;
  final Future<void> Function(String, DateTime) onDeleteHistoryRecord;
  final Future<void> Function() onClearHistory;
  final Future<List<TransferRecord>> Function() getHistory;
  final ValueChanged<AppTheme> onThemeChanged;

  const SettingsDrawer({
    super.key,
    required this.deviceName,
    required this.connectedDeviceName,
    required this.isConnected,
    required this.isOfflineMode,
    required this.isOfflineModeLoading,
    required this.notificationsEnabled,
    required this.clipboardSyncEnabled,
    required this.trustedDevices,
    required this.onToggleOfflineMode,
    required this.onNotificationsChanged,
    required this.onOpenNotificationSettings,
    required this.onClipboardSyncChanged,
    required this.onDisconnectDevice,
    required this.onConnectDevice,
    required this.onSetDefaultDevice,
    required this.onRemoveTrustedDevice,
    required this.onDeleteHistoryRecord,
    required this.onClearHistory,
    required this.getHistory,
    required this.onThemeChanged,
  });

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  @override
  Widget build(BuildContext context) {
    final td = SpDropThemeProvider.of(context);
    return Drawer(
      backgroundColor: td.scaffoldBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    td.primary.withValues(alpha: 0.08),
                    td.scaffoldBg,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [td.primary, td.primary.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(color: td.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text('Settings', style: TextStyle(
                        color: td.textPrimary.withValues(alpha: 0.9),
                        fontSize: 22, fontWeight: FontWeight.w800,
                      )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Device info subtitle
                  Row(
                    children: [
                      Icon(Icons.computer, size: 14, color: td.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(width: 6),
                      Text("Device: ${widget.deviceName}", style: TextStyle(
                        color: td.textSecondary.withValues(alpha: 0.7), fontSize: 12,
                      )),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 1),

            _buildSectionHeader('APPEARANCE', td),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: AppTheme.values.length,
                itemBuilder: (context, index) {
                  final theme = AppTheme.values[index];
                  final data = appThemes[theme]!;
                  final isSelected = td.name == data.name;
                  return GestureDetector(
                    onTap: () {
                      widget.onThemeChanged(theme);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 10),
                      width: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? data.primary : td.textPrimary.withValues(alpha: 0.08),
                          width: isSelected ? 2 : 1,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [data.scaffoldBg, data.surfaceBg],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle, color: data.primary,
                              boxShadow: isSelected ? [BoxShadow(color: data.primary.withValues(alpha: 0.4), blurRadius: 8)] : null,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(data.name.split(' ').first, style: TextStyle(
                            color: isSelected ? data.primary : td.textSecondary.withValues(alpha: 0.5),
                            fontSize: 8, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Offline Mode Toggle
            if (Platform.isAndroid) ...[
              Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 1),
              SwitchListTile(
                title: Text('Offline Mode', style: TextStyle(color: td.textPrimary, fontSize: 13)),
                subtitle: Text(
                  widget.isOfflineModeLoading ? 'Starting...'
                    : widget.isOfflineMode ? 'Wi-Fi Direct / Hotspot active' : 'Requires internet/LAN',
                  style: TextStyle(color: td.textSecondary.withValues(alpha: 0.5), fontSize: 11),
                ),
                value: widget.isOfflineMode,
                activeThumbColor: td.success,
                onChanged: widget.isOfflineModeLoading ? null : (val) => widget.onToggleOfflineMode(),
              ),
              Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 1),
            ],
            // Notification Sync
            if (Platform.isAndroid) ...[
              SwitchListTile(
                title: Text('Notification Sync', style: TextStyle(color: td.textPrimary, fontSize: 13)),
                subtitle: Text('Forward Android notifications to Windows',
                  style: TextStyle(color: td.textSecondary.withValues(alpha: 0.5), fontSize: 11)),
                secondary: Icon(Icons.notifications_active_outlined, color: td.warning, size: 20),
                value: widget.notificationsEnabled,
                activeThumbColor: td.warning,
                onChanged: (val) {
                  widget.onNotificationsChanged(val);
                  if (val) {
                    _showNotificationOnboardingDialog(td);
                  }
                },
              ),
              Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 1),
            ],

            // Clipboard Sync
            SwitchListTile(
              title: Text('Clipboard Sync', style: TextStyle(color: td.textPrimary, fontSize: 13)),
              subtitle: Text('Sync clipboard to explicitly allowed devices',
                style: TextStyle(color: td.textSecondary.withValues(alpha: 0.5), fontSize: 11)),
              secondary: IconButton(
                icon: Icon(Icons.devices, color: td.primary, size: 20),
                onPressed: () => _showClipboardDevicesDialog(td),
              ),
              value: widget.clipboardSyncEnabled,
              activeThumbColor: td.primary,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('clipboard_sync_enabled', val);
                widget.onClipboardSyncChanged(val);
              },
            ),
            Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 1),

            // Trusted Devices section
            _buildSectionHeader('TRUSTED DEVICES', td),
            if (widget.trustedDevices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('No paired devices yet',
                    style: TextStyle(color: td.textTertiary.withValues(alpha: 0.3), fontSize: 12)),
              )
            else
              ...widget.trustedDevices.where((d) => d.isTrusted).map((device) => ListTile(
                leading: Icon(
                  device.platform == 'android' ? Icons.phone_android
                    : device.platform == 'windows' ? Icons.laptop_windows
                    : Icons.devices,
                  color: td.success,
                  size: 20,
                ),
                title: Row(
                  children: [
                    Text(device.name, style: TextStyle(color: td.textPrimary, fontSize: 13)),
                    if (device.isDefault) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.star, color: td.warning, size: 14),
                    ],
                  ],
                ),
                subtitle: Text(
                  device.isTrusted ? 'Trusted' : 'Known',
                  style: TextStyle(color: td.success.withValues(alpha: 0.7), fontSize: 11),
                ),
                trailing: Icon(Icons.more_vert, color: td.textSecondary.withValues(alpha: 0.5), size: 18),
                onTap: () {
                  _showDeviceManagerSheet(device, td);
                },
              )),

            Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 24),

            // Transfer History with clear-all (Issues #9/#10)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TRANSFER HISTORY', style: TextStyle(
                    color: td.textTertiary.withValues(alpha: 0.35),
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                  )),
                  TextButton.icon(
                    icon: Icon(Icons.delete_sweep_outlined, size: 14, color: td.error.withValues(alpha: 0.6)),
                    label: Text('Clear All', style: TextStyle(color: td.error.withValues(alpha: 0.6), fontSize: 10)),
                    onPressed: () async {
                      // Confirmation dialog before clearing all history
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: td.cardBg,
                          title: Text('Clear All History?', style: TextStyle(color: td.textPrimary, fontSize: 16)),
                          content: Text(
                            'This will permanently delete all transfer history records. Individual items can be deleted by swiping them left.',
                            style: TextStyle(color: td.textSecondary, fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text('Cancel', style: TextStyle(color: td.textTertiary)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Clear All', style: TextStyle(color: td.error)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await widget.onClearHistory();
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<TransferRecord>>(
                future: widget.getHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: td.primary));
                  }
                  final records = snapshot.data ?? [];
                  if (records.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off, color: td.textTertiary.withValues(alpha: 0.15), size: 48),
                          const SizedBox(height: 8),
                          Text("No transfers yet",
                              style: TextStyle(color: td.textTertiary.withValues(alpha: 0.2), fontSize: 13)),
                        ],
                      ),
                    );
                  }
                  final sentRecords = records.where((r) => r.direction == 'Sent').toList();
                  final receivedRecords = records.where((r) => r.direction == 'Received').toList();

                  Widget buildRecordTile(TransferRecord record, AppThemeData td, bool isSent) {
                    return Dismissible(
                      key: Key('${record.filename}_${record.timestamp.millisecondsSinceEpoch}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: td.error.withValues(alpha: 0.2),
                        child: Icon(Icons.delete_rounded, color: td.error, size: 20),
                      ),
                      onDismissed: (direction) async {
                        await widget.onDeleteHistoryRecord(record.filename, record.timestamp);
                        setState(() {});
                      },
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isSent ? Colors.orangeAccent : td.success).withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            isSent ? Icons.upload_rounded : Icons.download_rounded,
                            color: isSent ? Colors.orangeAccent : td.success,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          record.filename,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: td.textPrimary, fontSize: 12),
                        ),
                        subtitle: Text(
                          '${record.timestamp.toLocal().toString().split('.')[0]}'
                          '${record.peerDevice != null ? ' • ${record.peerDevice}' : ''}'
                          '${record.fileSize != null ? ' • ${_formatFileSize(record.fileSize!)}' : ''}',
                          style: TextStyle(color: td.textTertiary.withValues(alpha: 0.35), fontSize: 10),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (record.filePath != null && !isSent)
                              IconButton(
                                icon: Icon(Icons.open_in_new_rounded, size: 14, color: td.primary),
                                onPressed: () => OpenFilex.open(record.filePath!),
                              ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 14, color: td.error.withValues(alpha: 0.7)),
                              onPressed: () async {
                                await widget.onDeleteHistoryRecord(record.filename, record.timestamp);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (receivedRecords.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text('RECEIVED FILES', style: TextStyle(color: td.success.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        ...receivedRecords.map((r) => buildRecordTile(r, td, false)),
                      ],
                      if (sentRecords.isNotEmpty) ...[
                        if (receivedRecords.isNotEmpty)
                          Divider(color: td.textPrimary.withValues(alpha: 0.06), height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text('SENT FILES', style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        ...sentRecords.map((r) => buildRecordTile(r, td, true)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Section header helper
  Widget _buildSectionHeader(String title, AppThemeData td) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(title, style: TextStyle(
        color: td.textTertiary.withValues(alpha: 0.35),
        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5,
      )),
    );
  }

  // File size formatter
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
  }

  // Notification onboarding dialog
  void _showNotificationOnboardingDialog(AppThemeData td) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_active, color: td.warning, size: 40),
              const SizedBox(height: 16),
              Text('Notification Sync', style: TextStyle(
                color: td.textPrimary.withValues(alpha: 0.95),
                fontSize: 20, fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 12),
              Text(
                'This feature forwards your Android notifications to your connected Windows PC.\n\n'
                '• Only works from Android → Windows\n'
                '• Requires Notification Listener permission\n'
                '• Sent over local network only (no internet)',
                style: TextStyle(color: td.textSecondary.withValues(alpha: 0.6), fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: td.warning),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenNotificationSettings();
                      },
                      child: const Text('Enable Access', style: TextStyle(color: Colors.black)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Later', style: TextStyle(color: td.textSecondary.withValues(alpha: 0.5))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClipboardDevicesDialog(AppThemeData td) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: GlassCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clipboard Sync Allowed Devices', style: TextStyle(
                      color: td.textPrimary.withValues(alpha: 0.95),
                      fontSize: 18, fontWeight: FontWeight.w700,
                    )),
                    const SizedBox(height: 8),
                    Text(
                      'Select which trusted devices can receive your clipboard updates. Syncing sensitive data (like passwords) over the network is risky.',
                      style: TextStyle(color: td.textSecondary.withValues(alpha: 0.6), fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: widget.trustedDevices.isEmpty
                          ? Text('No trusted devices found.', style: TextStyle(color: td.textTertiary.withValues(alpha: 0.5)))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: widget.trustedDevices.length,
                              itemBuilder: (context, index) {
                                final device = widget.trustedDevices[index];
                                if (!device.isTrusted) return const SizedBox.shrink();
                                final fingerprint = device.stableId ?? '';
                                if (fingerprint.isEmpty) return const SizedBox.shrink();
                                return FutureBuilder<bool>(
                                  future: ClipboardPrivacyService.isDeviceAllowedForClipboard(fingerprint),
                                  builder: (context, snapshot) {
                                    final isAllowed = snapshot.data ?? false;
                                    return SwitchListTile(
                                      title: Text(device.name, style: TextStyle(color: td.textPrimary, fontSize: 14)),
                                      subtitle: Text('${fingerprint.substring(0, 8)}...', style: TextStyle(color: td.textTertiary.withValues(alpha: 0.5), fontSize: 11)),
                                      value: isAllowed,
                                      activeThumbColor: td.primary,
                                      onChanged: (val) async {
                                        await ClipboardPrivacyService.setDeviceAllowedForClipboard(fingerprint, val);
                                        setDialogState(() {});
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Close', style: TextStyle(color: td.primary)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDeviceManagerSheet(TrustedDevice device, AppThemeData td) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassCard(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Manage ${device.name}",
                style: TextStyle(color: td.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              if (widget.isConnected && widget.connectedDeviceName == device.name) 
                ListTile(
                  leading: Icon(Icons.link_off, color: td.error),
                  title: Text('Disconnect', style: TextStyle(color: td.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDisconnectDevice(device);
                  },
                )
              else 
                ListTile(
                  leading: Icon(Icons.link, color: td.primary),
                  title: Text('Connect', style: TextStyle(color: td.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onConnectDevice(device);
                  },
                ),
              ListTile(
                leading: Icon(
                  device.isDefault ? Icons.star : Icons.star_border,
                  color: td.warning,
                ),
                title: Text(
                  device.isDefault ? 'Remove Default' : 'Set as Default',
                  style: TextStyle(color: td.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (device.isDefault) {
                    await widget.onSetDefaultDevice(null);
                  } else {
                    await widget.onSetDefaultDevice(device.name);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: td.error),
                title: Text('Remove Device', style: TextStyle(color: td.error)),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.onRemoveTrustedDevice(device.name);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
