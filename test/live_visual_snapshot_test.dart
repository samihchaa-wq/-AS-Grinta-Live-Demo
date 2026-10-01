import 'dart:io';
import 'dart:ui' as ui;

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_accessibility_scope.dart';
import 'package:as_grinta/demo/demo_backend.dart';
import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:as_grinta/demo/demo_match_page.dart';
import 'package:as_grinta/demo/demo_repositories.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pilot.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _boundaryKey = ValueKey('live-snapshot-boundary');
const _francois = 'a699d053-420f-4ab2-b15f-27048f68d565';
const _allan = 'abe33132-6417-43f9-a67f-3325bd542878';
const _amine = 'a4e345f9-bfd0-44ea-bae6-c2b7106a6aae';
const _lulu = 'e41da6cf-245c-4057-be2f-059de3330cba';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(430, 1600);
  });

  testWidgets('avant ouverture', (tester) async {
    await _capture(tester, '01_before_open', DemoBackend());
  });

  testWidgets('avant coup d’envoi', (tester) async {
    final backend = DemoBackend()..openWorkspace(90);
    await _capture(tester, '02_pre_kickoff', backend);
  });

  testWidgets('mi-temps avec but et remplacements', (tester) async {
    final backend = _halftimeScenario();
    await _capture(tester, '03_halftime_spectator', backend);
  });

  testWidgets('salves distinctes dans la même minute côté pilote',
      (tester) async {
    final backend = _halftimeScenario();
    await _capture(
      tester,
      '04_same_minute_salvos_pilot',
      backend,
      pilot: true,
    );
  });

  testWidgets('fin du match', (tester) async {
    final backend = _halftimeScenario()..endMatch();
    await _capture(tester, '05_finished', backend);
  });
}

DemoBackend _halftimeScenario() {
  final backend = DemoBackend()
    ..openWorkspace(90)
    ..confirmStart()
    ..setClockState('halftime')
    ..adjustScore(team: 'us', delta: 1, operationId: 'visual-goal');

  final events = backend.liveSnapshot()['events'] as List<dynamic>;
  final goal = Map<String, dynamic>.from(events.last as Map);
  backend.setEventScorer(
    eventId: goal['id'] as String,
    scorerParticipantId: _francois,
    assistParticipantId: _allan,
  );

  _substitute(backend, playerIn: _amine, playerOut: _francois);
  _substitute(backend, playerIn: _lulu, playerOut: _allan);
  return backend;
}

void _substitute(
  DemoBackend backend, {
  required String playerIn,
  required String playerOut,
}) {
  final snapshot = backend.compositionSnapshot();
  final entries = (snapshot['entries'] as List<dynamic>)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();
  final incoming = entries.firstWhere(
    (entry) => entry['participant_id'] == playerIn,
  );
  final outgoing = entries.firstWhere(
    (entry) => entry['participant_id'] == playerOut,
  );

  final incomingOrder = incoming['sort_order'];
  incoming
    ..['zone'] = 'field'
    ..['x'] = outgoing['x']
    ..['y'] = outgoing['y']
    ..['slot_label'] = outgoing['slot_label']
    ..['sort_order'] = outgoing['sort_order'];
  outgoing
    ..['zone'] = 'bench'
    ..['x'] = null
    ..['y'] = null
    ..['slot_label'] = null
    ..['sort_order'] = incomingOrder;

  backend.saveLiveLineup(
    entries: entries,
    expectedLineupRevision:
        backend.liveSnapshot()['lineup_revision'] as int,
    substitutions: [(playerIn: playerIn, playerOut: playerOut)],
  );
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  DemoBackend backend, {
  bool pilot = false,
}) async {
  await tester.pumpWidget(_SnapshotApp(backend: backend, pilot: pilot));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));

  expect(find.byKey(_boundaryKey), findsOneWidget);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );

  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Impossible de générer la capture Live.');
      }

      final output = Platform.environment['SNAPSHOT_DIR'] ??
          '${Directory.current.path}/build/live_snapshots';
      final directory = Directory(output)..createSync(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        data.buffer.asUint8List(),
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _SnapshotApp extends StatelessWidget {
  const _SnapshotApp({required this.backend, required this.pilot});

  final DemoBackend backend;
  final bool pilot;

  @override
  Widget build(BuildContext context) {
    final baseTheme = AppTheme.dark;
    return ProviderScope(
      overrides: [
        demoBackendProvider.overrideWithValue(backend),
        supabaseClientProvider.overrideWith(
          (ref) => throw UnsupportedError('Snapshot hors ligne.'),
        ),
        matchLiveRepositoryProvider.overrideWith(
          (ref) => DemoMatchLiveRepository(ref.watch(demoBackendProvider)),
        ),
        matchSportReportRepositoryProvider.overrideWith(
          (ref) =>
              DemoMatchSportReportRepository(ref.watch(demoBackendProvider)),
        ),
        isAdminViewProvider.overrideWith((ref) => false),
        isMatchCoachOrAdminProvider.overrideWith((ref, matchId) async => true),
        upcomingMatchFixtureProvider.overrideWith(
          (ref, matchId) async => UpcomingMatchFixtureData(
            status: 'a_venir',
            location: demoLocation,
            opponentName: demoOpponentName,
            kickoffAt: demoKickoffAt.toLocal(),
            address: demoAddress,
            matchType: demoMatchType,
          ),
        ),
        if (pilot) ...[
          livePilotProvider(demoMatchId).overrideWith((ref) => LivePilot.me),
          liveViewModeProvider(demoMatchId)
              .overrideWith((ref) => LiveViewMode.pilot),
        ],
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: baseTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(430, 1600),
            textScaler: TextScaler.linear(1.10),
          ),
          child: GrintaAccessibilityScope(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: const DemoMatchPage(),
            ),
          ),
        ),
      ),
    );
  }
}
