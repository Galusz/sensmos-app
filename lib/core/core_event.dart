import 'package:equatable/equatable.dart';

abstract class CoreEvent extends Equatable {
  const CoreEvent();
  @override
  List<Object?> get props => [];
}

/// Start aplikacji — sprawdź wallet i node
class AppStarted extends CoreEvent {}

/// Node sparowany (portfel utworzony/odzyskany w trakcie setupu)
class NodeConnected extends CoreEvent {}

/// Node rozłączony
class NodeDisconnected extends CoreEvent {}

class NodeRemoved   extends CoreEvent { final String deviceId; const NodeRemoved(this.deviceId); }
