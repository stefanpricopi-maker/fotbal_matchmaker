import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/debug_log.dart';
import 'app/simf_app.dart';
import 'providers/simf_controller.dart';
import 'services/local_store.dart';
import 'services/matchmaking_engine.dart';
import 'services/ranking_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // #region agent log
  await DebugLog.writeAsync(
    runId: 'pre-fix',
    hypothesisId: 'H0',
    location: 'main.dart:main',
    message: 'app start',
    data: const {},
  );
  // #endregion

  // Suport: --dart-define=... sau --dart-define-from-file=simf_defines.json
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  final localStore = await LocalStore.open();
  final supabaseService = SupabaseService();
  final rankingService = RankingService();
  final matchmakingEngine = MatchmakingEngine(
    rankingService: rankingService,
  );

  final controller = SimfController(
    localStore: localStore,
    supabaseService: supabaseService,
    rankingService: rankingService,
    matchmakingEngine: matchmakingEngine,
  );

  runApp(SimfApp(controller: controller));
}
