import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/import_review_screen.dart';
import 'screens/position_detail_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/import_queue_service.dart';
import 'services/notification_service.dart';
import 'services/share_service.dart';
import 'state/positions_controller.dart';
import 'theme.dart';

/// Lets notification taps navigate from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

/// Lets the Undo handler show a snackbar without a BuildContext.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class PhdTrackerApp extends StatelessWidget {
  const PhdTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<AuthService>(
      create: (_) => AuthService(),
      child: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    return StreamBuilder<User?>(
      stream: auth.userChanges,
      builder: (context, snap) {
        final user = snap.data;
        final waiting = snap.connectionState == ConnectionState.waiting;

        debugPrint('AUTHGATE: state=${snap.connectionState} uid=${user?.uid}');

        // MaterialApp has to stay at a FIXED position in the tree. Wrapping it
        // conditionally changes its widget type when the user signs in, which
        // tears down the Navigator and leaves two MaterialApps fighting over
        // navigatorKey — the app then sits on the sign-in screen with no error.
        return MaterialApp(
          title: 'PhD Tracker',
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: ThemeMode.system,

          // `builder` wraps the Navigator, so whatever goes here is an ancestor
          // of every route including pushed ones. That is what lets the detail
          // and edit screens reach the controller.
          builder: (context, child) {
            if (user == null) return child!;
            return ChangeNotifierProvider<PositionsController>(
              key: ValueKey(user.uid),
              create: (_) => PositionsController(FirestoreService(user.uid)),
              child: child!,
            );
          },

          home: waiting
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : user == null
              ? const SignInScreen()
              : const _ShareWatcher(child: HomeScreen()),
        );
      },
    );
  }
}

/// Watches for text shared into the app and hands it to the background
/// importer, then gets out of the way.
class _ShareWatcher extends StatefulWidget {
  const _ShareWatcher({required this.child});

  final Widget child;

  @override
  State<_ShareWatcher> createState() => _ShareWatcherState();
}

class _ShareWatcherState extends State<_ShareWatcher>
    with WidgetsBindingObserver {
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.onNotificationPayload = _route;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _check();
      final payload = await NotificationService.instance.launchPayload();
      if (payload != null) _route(payload);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.onNotificationPayload = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _route(Map<String, dynamic> payload) {
    // Undo arrives as the same payload with the action id attached.
    if (payload['action'] == NotificationService.undoActionId) {
      final importId = payload['importId'] as String?;
      if (importId != null) _undo(importId);
      return;
    }

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (payload['type']) {
      case 'import':
        // Imports are saved on arrival now, so the tap opens the entry. Only
        // a share that could not be written at all goes to the importer.
        final positionId = payload['positionId'] as String?;
        if (positionId != null) {
          nav.push(MaterialPageRoute(
              builder: (_) => PositionDetailScreen(positionId: positionId)));
          return;
        }
        final importId = payload['importId'] as String?;
        if (importId != null) {
          nav.push(MaterialPageRoute(
              builder: (_) => ImportReviewScreen(importId: importId)));
        }
      case 'position':
        final id = payload['positionId'] as String?;
        if (id != null) {
          nav.push(MaterialPageRoute(
              builder: (_) => PositionDetailScreen(positionId: id)));
        }
    }
  }

  Future<void> _undo(String importId) async {
    await ImportQueueService.instance.undoAutoSave(importId);

    // Only the saved position goes; the extraction stays, so it can still be
    // reviewed and saved by hand.
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: const Text('Removed. The extraction is still saved.'),
      action: SnackBarAction(
        label: 'Review',
        onPressed: () => navigatorKey.currentState?.push(
          MaterialPageRoute(
              builder: (_) => ImportReviewScreen(importId: importId)),
        ),
      ),
    ));
  }


  Future<void> _check() async {
    if (_handling) return;
    _handling = true;
    try {
      final shared = await ShareService.instance.consumePendingShare();

      // Ordinary resume, nothing shared. Must return here — going further
      // would bounce the app to the background on every resume.
      if (shared == null || !mounted) return;

      final payload = ShareService.classify(shared);
      if (!payload.isUsable) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No link or text found in what you shared.')));
        return;
      }

      await ImportQueueService.instance.enqueue(payload);

      // Hand the phone straight back. The progress notification is the
      // feedback channel from here on, so a snackbar would go unseen.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await ShareService.instance.moveToBack();
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}