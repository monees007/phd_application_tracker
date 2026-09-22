import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/csv_service.dart';
import '../services/notification_service.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../services/seed_service.dart';
import '../services/settings_service.dart';
import '../state/positions_controller.dart';
import 'ai_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _swipeActions = true;
  final _settings = SettingsService();
  int? _pendingCount;
  bool? _exactAllowed;

  @override
  void initState() {
    super.initState();
    _refreshNotificationInfo();
    _settings.swipeActionsEnabled().then((v) {
      if (mounted) setState(() => _swipeActions = v);
    });
  }

  Future<void> _refreshNotificationInfo() async {
    final pending = await NotificationService.instance.pending();
    final exact = await NotificationService.instance.exactAlarmsAllowed();
    if (!mounted) return;
    setState(() {
      _pendingCount = pending.length;
      _exactAllowed = exact;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PositionsController>();
    final r = c.reminders;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const _Header('Reminders'),
          SwitchListTile(
            value: r.enabled,
            onChanged: (v) async {
              await c.updateReminderSettings(r.copyWith(enabled: v));
              if (v) await NotificationService.instance.requestPermissions();
              await _refreshNotificationInfo();
            },
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Deadline reminders'),
            subtitle: const Text(
                'Only for positions still marked “Not applied”.'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Reminder time'),
            subtitle: Text(r.timeOfDay.format(context)),
            onTap: () async {
              final picked = await showTimePicker(
                  context: context, initialTime: r.timeOfDay);
              if (picked != null) {
                await c.updateReminderSettings(
                    r.copyWith(hour: picked.hour, minute: picked.minute));
                await _refreshNotificationInfo();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Remind me'),
            subtitle: Text(_describeLeads(r.leadDays)),
            onTap: () => _editLeadDays(context, c, r),
          ),
          ListTile(
            leading: const Icon(Icons.pending_actions),
            title: const Text('Scheduled reminders'),
            subtitle: Text(_pendingCount == null
                ? 'Checking…'
                : '$_pendingCount alarms queued on this device'),
            trailing: IconButton(
              tooltip: 'Rebuild schedule',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await c.forceRescheduleReminders();
                await _refreshNotificationInfo();
              },
            ),
          ),
          if (_exactAllowed == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Exact alarms are not permitted, so reminders may '
                        'arrive late. Grant “Alarms & reminders” in Android '
                        'app settings.',
                        style: TextStyle(fontSize: 12.5, height: 1.3),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await NotificationService.instance.requestPermissions();
                        await _refreshNotificationInfo();
                      },
                      child: const Text('Fix'),
                    ),
                  ],
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Send a test notification'),
            subtitle: const Text('Arrives in about five seconds'),
            onTap: () async {
              await NotificationService.instance.sendTestNotification();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Test notification queued')));
            },
          ),

          const Divider(height: 28),
          const _Header('Interaction'),
          SwitchListTile(
            value: _swipeActions,
            onChanged: (v) async {
              await _settings.setSwipeActionsEnabled(v);
              if (mounted) setState(() => _swipeActions = v);
            },
            secondary: const Icon(Icons.swipe_outlined),
            title: const Text('Swipe actions on the list'),
            subtitle: const Text(
                'Swipe right to mark applied, left to archive. Both are also '
                'on the card and the detail screen.'),
          ),

          const Divider(height: 28),
          const _Header('Data'),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI extraction'),
            subtitle: const Text(
                'Gemini API key and model for importing shared links'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Import positions from a CSV'),
            subtitle: const Text(
                'Pick any spreadsheet export. Columns are matched by name, '
                'and re-importing the same file updates rather than '
                'duplicates.'),
            onTap: _busy ? null : () => _importCsv(context, c),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Import the bundled sheet'),
            subtitle: const Text(
                'The 45 rows converted from PG_-_Sheet5.csv at build time.'),
            onTap: _busy ? null : () => _importSeed(context, c),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export everything as CSV'),
            onTap: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await CsvService().exportAndShare(c.all);
                    } catch (e) {
                      messenger.showSnackBar(
                          SnackBar(content: Text('Export failed: $e')));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),

          const Divider(height: 28),
          const _Header('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.email ?? 'Guest (anonymous)'),
            subtitle: Text(
              user?.isAnonymous ?? true
                  ? 'Your data lives only on this account. Add an email so '
                      'you can sign in from another device.'
                  : 'Signed in — your board syncs across devices.',
            ),
          ),
          if (user?.isAnonymous ?? false)
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Add email & password'),
              onTap: () => _linkAccount(context, auth),
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: user?.isAnonymous ?? true
                ? const Text(
                    'Warning: an anonymous account cannot be recovered once '
                    'you sign out.')
                : null,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: Text(user?.isAnonymous ?? true
                      ? 'This account is anonymous. Signing out will make its '
                          'data unreachable. Add an email first if you want to '
                          'keep it.'
                      : 'You can sign back in with your email.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign out')),
                  ],
                ),
              );
              if (ok == true) await auth.signOut();
            },
          ),
        ],
      ),
    );
  }

  String _describeLeads(List<int> leads) {
    final parts = leads.map((d) =>
        d == 0 ? 'on the day' : '$d day${d == 1 ? '' : 's'} before');
    return parts.join(', ');
  }

  Future<void> _editLeadDays(
      BuildContext context, PositionsController c, ReminderSettings r) async {
    final options = [14, 7, 5, 3, 2, 1, 0];
    final selected = {...r.leadDays};

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('When should I remind you?',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in options)
                      FilterChip(
                        label: Text(d == 0
                            ? 'On the day'
                            : '$d day${d == 1 ? '' : 's'} before'),
                        selected: selected.contains(d),
                        onSelected: (sel) => setSheetState(() {
                          if (sel) {
                            selected.add(d);
                          } else {
                            selected.remove(d);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                            final leads = selected.toList()
                              ..sort((a, b) => b - a);
                            await c.updateReminderSettings(
                                r.copyWith(leadDays: leads));
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _refreshNotificationInfo();
  }

  Future<void> _importCsv(
      BuildContext context, PositionsController c) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // Some file providers report CSV as text/comma-separated-values and
        // others as application/octet-stream, so match on extension.
        allowedExtensions: const ['csv', 'txt', 'tsv'],
        withData: false,
      );
      final path = picked?.files.single.path;
      if (path == null) return; // cancelled

      final bundle = await SeedService().loadCsv(File(path));
      if (!context.mounted) return;

      if (bundle.positions.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Nothing to import'),
            content: Text(bundle.skipped.isEmpty
                ? 'No rows were found in that file.'
                : bundle.skipped.join('\n\n')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          ),
        );
        return;
      }

      final undated =
          bundle.positions.where((p) => p.deadline == null).length;
      final assumed =
          bundle.positions.where((p) => p.deadlineYearAssumed).length;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import from CSV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${bundle.positions.length} rows from ${bundle.source} '
                  'will be added or updated.'),
              if (assumed > 0) ...[
                const SizedBox(height: 10),
                Text('$assumed of them gave a day and month but no year, so '
                    '${bundle.assumedYear} was used. Those dates are flagged '
                    'in the app for you to check.'),
              ],
              if (undated > 0) ...[
                const SizedBox(height: 10),
                Text('$undated have no readable deadline and will get no '
                    'reminders until you add one.'),
              ],
              if (bundle.skipped.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(bundle.skipped.join('\n')),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (confirmed != true) return;

      await c.service.bulkSet(bundle.positions);
      messenger.showSnackBar(SnackBar(
          content: Text('Imported ${bundle.positions.length} positions')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importSeed(
      BuildContext context, PositionsController c) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bundle = await SeedService().loadBundled();
      if (!context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import from sheet'),
          content: Text(
            '${bundle.positions.length} positions will be added or updated '
            'from ${bundle.source}.\n\n'
            'The sheet recorded deadlines as day + month only, so every date '
            'was imported as ${bundle.assumedYear}. Entries with an inferred '
            'year are flagged in the app so you can correct them.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (confirmed != true) return;

      await c.service.bulkSet(bundle.positions);
      await c.service.markSeedImported();
      messenger.showSnackBar(SnackBar(
          content: Text('Imported ${bundle.positions.length} positions')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkAccount(BuildContext context, AuthService auth) async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add email & password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password (min 6 characters)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Link')),
        ],
      ),
    );

    if (ok == true) {
      try {
        await auth.linkEmail(emailCtrl.text, passCtrl.text);
        messenger.showSnackBar(
            const SnackBar(content: Text('Account linked. Your data is safe.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text(AuthService.describeError(e))));
      }
    }
    emailCtrl.dispose();
    passCtrl.dispose();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
