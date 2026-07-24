import 'package:flutter/material.dart';

/// Typy integracji które można PODPIĄĆ do noda (opt-in, per node). Nie każdy ma HA/terminal,
/// więc user dodaje tylko to, czego potrzebuje. Rozszerzalne — nowa integracja = nowy wariant.
enum IntegrationKind { terminal, homeAssistant }

extension IntegrationKindX on IntegrationKind {
  String get id => switch (this) {
        IntegrationKind.terminal => 'terminal',
        IntegrationKind.homeAssistant => 'ha',
      };

  IconData get icon => switch (this) {
        IntegrationKind.terminal => Icons.terminal,
        IntegrationKind.homeAssistant => Icons.home_outlined,
      };

  // Klucz PL do tr() (etykieta) — tłumaczenia w l10n.
  String get labelKey => switch (this) {
        IntegrationKind.terminal => 'Zdalny terminal',
        IntegrationKind.homeAssistant => 'Panel HA',
      };

  // Wymaga tunelu na nodzie → tylko FW > 0.70.
  bool get needsTunnel => true;

  // Wymaga konfiguracji przed użyciem (HA: host + token).
  bool get needsConfig => this == IntegrationKind.homeAssistant;

  static IntegrationKind? fromId(String id) => switch (id) {
        'terminal' => IntegrationKind.terminal,
        'ha' => IntegrationKind.homeAssistant,
        _ => null,
      };
}
