import 'package:equatable/equatable.dart';
import '../models/wallet.dart';

// welcome = brak nodów (portfel rozstrzygany przy dodawaniu noda)
enum AppPhase { loading, welcome, ready }

class CoreState extends Equatable {
  final AppPhase phase;
  final AppWallet? wallet;

  const CoreState({
    this.phase = AppPhase.loading,
    this.wallet,
  });

  CoreState copyWith({AppPhase? phase, AppWallet? wallet}) => CoreState(
        phase: phase ?? this.phase,
        wallet: wallet ?? this.wallet,
      );

  @override
  List<Object?> get props => [phase, wallet];
}
