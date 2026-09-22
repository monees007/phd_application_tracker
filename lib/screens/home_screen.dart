import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/position.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../state/positions_controller.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/position_card.dart';
import '../widgets/status_chip.dart';
import 'dashboard_screen.dart';
import 'position_detail_screen.dart';
import 'position_edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Ask once the first frame is on screen, so the system dialog appears over
    // the app rather than over a blank window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      _BoardPage(),
      DashboardScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PositionEditScreen(existing: null)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add position'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.view_list_outlined),
              selectedIcon: Icon(Icons.view_list),
              label: 'Positions'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Overview'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}

class _BoardPage extends StatefulWidget {
  const _BoardPage();

  @override
  State<_BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<_BoardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: Bucket.values.length, vsync: this);
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PositionsController>();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search university, programme, notes…',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: c.setQuery,
              )
            : const Text('Applications'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _searchCtrl.clear();
                c.setQuery('');
              }
            },
          ),
          IconButton(
            tooltip: 'Filter and sort',
            icon: Badge(
              isLabelVisible: c.hasActiveFilters,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => FilterSheet.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final b in Bucket.values)
              Tab(text: '${b.label} (${c.visible(b).length})'),
          ],
        ),
      ),
      body: c.loading
          ? const Center(child: CircularProgressIndicator())
          : c.error != null
              ? _ErrorView(message: c.error!)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    for (final b in Bucket.values) _PositionList(bucket: b),
                  ],
                ),
    );
  }
}

class _PositionList extends StatelessWidget {
  const _PositionList({required this.bucket});

  final Bucket bucket;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PositionsController>();
    final items = c.visible(bucket);

    if (items.isEmpty) {
      return _EmptyView(bucket: bucket, filtered: c.hasActiveFilters || c.query.isNotEmpty);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 96),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final p = items[i];

        final card = PositionCard(
          position: p,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PositionDetailScreen(positionId: p.id)),
          ),
          onStatusTap: () async {
            final next = await showStatusPicker(context, current: p.status);
            if (next != null) await c.changeStatus(p, next);
          },
          onOpenLink: () => _openLink(context, p.link),
        );

        // Swipe can be turned off in Settings: on a long board it is easy to
        // trigger by accident while scrolling, and every action it offers is
        // also reachable from the card and the detail screen.
        if (!SettingsService.swipeActionsEnabledSync()) return card;

        return Dismissible(
          key: ValueKey(p.id),
          direction: DismissDirection.horizontal,
          background: _SwipeBg(
            alignment: Alignment.centerLeft,
            icon: Icons.check_circle_outline,
            label: 'Mark applied',
            color: Theme.of(ctx).colorScheme.primaryContainer,
          ),
          secondaryBackground: _SwipeBg(
            alignment: Alignment.centerRight,
            icon: Icons.archive_outlined,
            label: 'Archive',
            color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
          ),
          confirmDismiss: (dir) async {
            final messenger = ScaffoldMessenger.of(ctx);
            if (dir == DismissDirection.startToEnd) {
              final next = p.status.needsAction
                  ? AppStatus.applied
                  : AppStatus.notApplied;
              await c.changeStatus(p, next);
              messenger.showSnackBar(SnackBar(
                content: Text('Marked as ${next.label.toLowerCase()}'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => c.changeStatus(p, p.status),
                ),
              ));
            } else {
              await c.setArchived(p.id, true);
              messenger.showSnackBar(SnackBar(
                content: const Text('Archived'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => c.setArchived(p.id, false),
                ),
              ));
            }
            // Never actually remove the tile: the Firestore stream drives the
            // list, so letting Dismissible remove it too would double-remove.
            return false;
          },
          child: card,
        );
      },
    );
  }
}

Future<void> _openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    messenger.showSnackBar(
        const SnackBar(content: Text('No valid link saved for this entry')));
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link')));
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.color,
  });

  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: alignment,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.bucket, required this.filtered});

  final Bucket bucket;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final msg = filtered
        ? 'Nothing matches the current search or filters.'
        : switch (bucket) {
            Bucket.toApply => 'No open positions left to apply to.',
            Bucket.pending => 'Nothing is waiting on a decision.',
            Bucket.decided => 'No results have come back yet.',
            Bucket.all => 'No positions yet. Add one, or import your sheet '
                'from Settings.',
          };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 44, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            const Text('Could not load your positions',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
