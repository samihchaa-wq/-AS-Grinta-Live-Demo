import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_accessibility_scope.dart';
import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:as_grinta/demo/demo_match_page.dart';
import 'package:as_grinta/demo/demo_repositories.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Démo d'entraînement du Live.
///
/// Les écrans du Live sont copiés tels quels depuis l'application. Seules les
/// sources de données sont remplacées : les deux dépôts qui parlaient à
/// Supabase sont substitués par un faux serveur local, et le client Supabase
/// lui-même est rendu inutilisable. Supabase n'est jamais initialisé.
void main() {
  runApp(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWith(
          (ref) => throw UnsupportedError('Démo hors ligne : pas de Supabase.'),
        ),
        matchLiveRepositoryProvider.overrideWith(
          (ref) => DemoMatchLiveRepository(ref.watch(demoBackendProvider)),
        ),
        matchSportReportRepositoryProvider.overrideWith(
          (ref) =>
              DemoMatchSportReportRepository(ref.watch(demoBackendProvider)),
        ),
        // Le coach de la saison pilote le Live sans être administrateur.
        isAdminViewProvider.overrideWith((ref) => false),
        // Coach par défaut ; le menu de simulation de la démo permet de voir
        // l'écran comme un joueur.
        isMatchCoachOrAdminProvider.overrideWith(
          (ref, matchId) async => ref.watch(demoViewAsCoachProvider),
        ),
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
      ],
      child: const LiveDemoApp(),
    ),
  );
}

final _router = GoRouter(
  initialLocation: '/matches/$demoMatchId/lineup?section=live',
  routes: [
    GoRoute(
      path: '/matches/$demoMatchId/lineup',
      builder: (context, state) => const DemoMatchPage(),
    ),
    // Le logo de l'en-tête renvoie au calendrier : dans la démo, il ramène
    // simplement sur la fiche du match.
    GoRoute(
      path: '/:rest(.*)',
      redirect: (_, __) => '/matches/$demoMatchId/lineup?section=live',
    ),
  ],
);

class LiveDemoApp extends StatelessWidget {
  const LiveDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Thème, langue et échelle de texte repris de lib/app/app.dart.
    final baseTheme = AppTheme.dark;

    return MaterialApp.router(
      title: 'ASG',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: AppTheme.background,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: baseTheme.segmentedButtonTheme.style?.copyWith(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.accent;
              }
              return baseTheme.segmentedButtonTheme.style?.foregroundColor
                      ?.resolve(states) ??
                  AppTheme.textSecondary;
            }),
          ),
        ),
        navigationBarTheme: baseTheme.navigationBarTheme.copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            final inherited =
                baseTheme.navigationBarTheme.labelTextStyle?.resolve(states);
            return inherited?.copyWith(
                  color: selected ? AppTheme.accent : AppTheme.textFaint,
                ) ??
                TextStyle(
                  color: selected ? AppTheme.accent : AppTheme.textFaint,
                );
          }),
        ),
      ),
      routerConfig: _router,
      builder: (context, child) {
        final systemScale = MediaQuery.textScalerOf(context).scale(1);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              (systemScale * 1.10).clamp(1.10, 1.60),
            ),
          ),
          child: GrintaAccessibilityScope(
            child: ColoredBox(
              color: AppTheme.background,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
