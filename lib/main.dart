import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'theme.dart';
import 'l10n.dart';
import 'log.dart';
import 'core/core_bloc.dart';
import 'core/core_event.dart';
import 'core/core_state.dart';
import 'services/wallet_service.dart';
import 'services/node_service.dart';
import 'services/api_service.dart';
import 'services/ble_service.dart';
import 'services/eth_service.dart';
import 'services/attest_service.dart';
import 'services/push_service.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'app_shell.dart';

// Handler powiadomień w tle (musi być top-level)
@pragma('vm:entry-point')
Future<void> _fcmBackground(RemoteMessage message) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L10n.init();
  await Log.load();
  // Firebase opcjonalny — apka działa też bez google-services.json
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_fcmBackground);
  } catch (_) {}
  runApp(const SensmosApp());
}

class SensmosApp extends StatelessWidget {
  const SensmosApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Serwisy — singletony wstrzykiwane do BLoCów
    final walletService = WalletService();
    final nodeService   = NodeService();
    final apiService    = ApiService();
    final bleService    = BleService();
    final ethService    = EthService();
    final attestService = AttestService();
    final pushService   = PushService()..init();

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: walletService),
        RepositoryProvider.value(value: nodeService),
        RepositoryProvider.value(value: apiService),
        RepositoryProvider.value(value: bleService),
        RepositoryProvider.value(value: ethService),
        RepositoryProvider.value(value: attestService),
        RepositoryProvider.value(value: pushService),
      ],
      child: BlocProvider(
        create: (_) => CoreBloc(
          walletService: walletService,
          nodeService: nodeService,
          bleService: bleService,
        )..add(AppStarted()),
        child: ValueListenableBuilder<int>(
          valueListenable: L10n.notifier,
          builder: (context, _, __) => MaterialApp(
            // Klucz zależny od języka: zmiana wymusza pełną przebudowę drzewa,
            // inaczej const-owe ekrany (IndexedStack) zostają w starym języku.
            key: ValueKey('lang-${L10n.mode}'),
            title: 'SENSMOS',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            locale: L10n.isEn ? const Locale('en') : const Locale('pl'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('pl')],
            home: const AppRouter(),
          ),
        ),
      ),
    );
  }
}

/// Router — wybiera ekran na podstawie fazy aplikacji
class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CoreBloc, CoreState>(
      builder: (context, state) {
        return switch (state.phase) {
          AppPhase.loading => const _LoadingScreen(),
          AppPhase.welcome => const OnboardingScreen(),
          AppPhase.ready   => const AppShell(),
        };
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.teal),
        ),
      );
}
