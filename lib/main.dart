import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/import_queue_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Offline cache is on by default on Android, but make the intent explicit and
  // remove the cache size cap so a few hundred documents always stay local.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Only initialise here. The runtime permission prompt is deferred to the
  // first frame (HomeScreen.initState) so it does not appear over a blank
  // window before any UI has rendered.
  await NotificationService.instance.init();
  await ImportQueueService.instance.sweepInterrupted();
  await SettingsService.warmUp();
  runApp(const PhdTrackerApp());
}
