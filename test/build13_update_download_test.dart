/// Build 13 (point #18) — the update-download permanent fix,
/// proven against a mocked `tj_pro/updater` channel:
///
/// - a RUNNING record re-attaches: ZERO new enqueues;
/// - a FAILED record is removed, then EXACTLY ONE fresh enqueue;
/// - a double-tap during a live flow enqueues nothing more;
/// - a PAUSED record surfaces its reason in the state note.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tj_pro/updater');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const update = UpdateInfo(
    versionCode: 2028,
    versionName: '1.10.0',
    url: 'https://example.com/app.apk',
    notes: '',
  );

  late Map<int, Map<String, Object>> statuses;
  late List<String> calls;
  late int nextId;

  setUp(() {
    statuses = {};
    calls = [];
    nextId = 900;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'canInstallPackages':
          return true;
        case 'openInstallSettings':
          return null;
        case 'downloadApk':
          final id = nextId++;
          statuses[id] = {
            'status': 'running',
            'bytesDownloaded': 10,
            'bytesTotal': 100,
            'reason': -1,
          };
          return id;
        case 'downloadStatus':
          final id = (call.arguments as Map)['downloadId'] as int;
          return statuses[id] ??
              {'status': 'not_found', 'reason': -1};
        case 'removeDownload':
          return true;
        case 'installApk':
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  int countCalls(String method) => calls.where((c) => c == method).length;

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    return ctx;
  }

  void seedPending({required int id, required int code}) {
    SharedPreferences.setMockInitialValues({
      'tjpro_pending_dl_id': id,
      'tjpro_pending_dl_code': code,
      'tjpro_pending_dl_name': '1.10.0',
      'tjpro_pending_dl_url': update.url,
      'tjpro_pending_dl_notes': '',
    });
  }

  testWidgets('running record: re-attaches, zero enqueues', (tester) async {
    seedPending(id: 42, code: 2028);
    statuses[42] = {
      'status': 'running',
      'bytesDownloaded': 50,
      'bytesTotal': 100,
      'reason': -1,
    };
    final ctx = await pumpHost(tester);
    await tester.runAsync(() async {
      final done = UpdateService.downloadAndInstall(ctx, update);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(UpdateService.updateState.value.phase,
          UpdatePhase.downloading);
      // The system finishes the SAME download.
      statuses[42] = {
        'status': 'success',
        'bytesDownloaded': 100,
        'bytesTotal': 100,
        'reason': -1,
        'localUri': 'file:///tmp/tj-pro-update.apk',
      };
      await done;
    });
    expect(countCalls('downloadApk'), 0);
    expect(countCalls('removeDownload'), 0);
    expect(countCalls('installApk'), 1);
    expect(UpdateService.updateState.value.phase, UpdatePhase.downloaded);
  });

  testWidgets('failed record: removed, exactly one fresh enqueue',
      (tester) async {
    seedPending(id: 42, code: 2028);
    statuses[42] = {'status': 'failed', 'reason': 1006};
    final ctx = await pumpHost(tester);
    await tester.runAsync(() async {
      final done = UpdateService.downloadAndInstall(ctx, update);
      // Let the fresh download (id 900) be enqueued + first poll.
      await Future<void>.delayed(const Duration(seconds: 3));
      statuses[900] = {
        'status': 'success',
        'bytesDownloaded': 100,
        'bytesTotal': 100,
        'reason': -1,
        'localUri': 'file:///tmp/tj-pro-update.apk',
      };
      await done;
    });
    expect(countCalls('removeDownload'), 1);
    expect(countCalls('downloadApk'), 1);
    expect(UpdateService.updateState.value.phase, UpdatePhase.downloaded);
  });

  testWidgets('double-tap: still exactly one enqueue', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctx = await pumpHost(tester);
    await tester.runAsync(() async {
      final first = UpdateService.downloadAndInstall(ctx, update);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // Second tap while the first flow is live: the guard turns
      // it away — no second enqueue, no second poll.
      await UpdateService.downloadAndInstall(ctx, update);
      expect(countCalls('downloadApk'), 1);
      statuses[900] = {
        'status': 'success',
        'bytesDownloaded': 100,
        'bytesTotal': 100,
        'reason': -1,
        'localUri': 'file:///tmp/tj-pro-update.apk',
      };
      await first;
    });
    expect(countCalls('downloadApk'), 1);
  });

  testWidgets('paused record: the reason shows in the state note',
      (tester) async {
    seedPending(id: 42, code: 2028);
    statuses[42] = {
      'status': 'paused',
      'bytesDownloaded': 40,
      'bytesTotal': 100,
      'reason': 2, // PAUSED_WAITING_FOR_NETWORK
    };
    final ctx = await pumpHost(tester);
    await tester.runAsync(() async {
      final done = UpdateService.downloadAndInstall(ctx, update);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final note = UpdateService.updateState.value.statusNote ?? '';
      expect(note, contains('paused'));
      expect(note, contains('network'));
      statuses[42] = {
        'status': 'success',
        'bytesDownloaded': 100,
        'bytesTotal': 100,
        'reason': -1,
        'localUri': 'file:///tmp/tj-pro-update.apk',
      };
      await done;
    });
    expect(countCalls('downloadApk'), 0);
  });
}
