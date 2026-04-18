import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AnalyticsService {
  bool analyticsEnabled = true;
  bool analyticsDone = false;
  List<Map> logs = [];
  final VoidCallback notifyEngine;

  AnalyticsService({required this.notifyEngine});

  Future<void> startAnalytics() async {
    final box = Hive.box('paios_storage');
    await box.put("analytics", true);
    analyticsEnabled = true;
    
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    await FirebaseAnalytics.instance.setConsent();
    await Firebase.app().setAutomaticDataCollectionEnabled(true);
    await Firebase.app().setAutomaticResourceManagementEnabled(true);
    analyticsDone = true;
    
    await log("application", "info", "Enabling analytics");
  }

  Future<void> stopAnalytics() async {
    final box = Hive.box('paios_storage');
    await box.put("analytics", false);
    analyticsEnabled = false;
    
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
    await Firebase.app().setAutomaticDataCollectionEnabled(false);
    await Firebase.app().setAutomaticResourceManagementEnabled(false);
    
    await log("application", "info", "Disabling analytics");
  }

  Future<void> log(String name, String type, String message) async {
    if (logs.isEmpty) {
      logs.add({
        "thread": name,
        "time": DateTime.now().millisecondsSinceEpoch,
        "type": type,
        "message": message,
      });
    } else {
      if (logs.last["thread"] == name &&
          logs.last["type"] == type &&
          logs.last["message"] == message) {
        logs.last["time"] = DateTime.now().millisecondsSinceEpoch;
        if (kDebugMode) {
          print("Still alive, did the last thing said above");
        }
      } else {
        logs.add({
          "thread": name,
          "time": DateTime.now().millisecondsSinceEpoch,
          "type": type,
          "message": message,
        });
        if (kDebugMode) {
          print("${type}_$name: $message");
        }
      }
    }
    
    // Bubble up to engine so UI can see the new logs
    notifyEngine();

    if (analyticsEnabled && analyticsDone) {
      try {
        await FirebaseAnalytics.instance.logEvent(
          name: name,
          parameters: <String, Object>{'type': type, 'message': message},
        );
      } catch (e) {
        if (kDebugMode) {
          print("Analytics failed. Not waiting anymore. Error: $e");
        }
      }
    }
  }

  Future<void> initFromHive() async {
    final box = Hive.box('paios_storage');
    if (box.containsKey("analytics")) {
      analyticsEnabled = box.get("analytics", defaultValue: true);
      if (analyticsEnabled) {
        await startAnalytics();
      }
    } else {
      await startAnalytics();
    }
  }
}
