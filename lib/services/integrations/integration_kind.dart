import 'package:flutter/material.dart';

/// Typy pluginów które można PODPIĄĆ do noda (opt-in, per node). Nie każdy ma HA/terminal,
/// więc user dodaje tylko to, czego potrzebuje. Rozszerzalne — nowy plugin = nowy wariant.
/// linkReport (2026-08-25) = pierwszy plugin BEZ tunelu: dane z BE (wd_outages), nie z LAN.
enum IntegrationKind { terminal, homeAssistant, linkReport, lanPanel }

extension IntegrationKindX on IntegrationKind {
  String get id => switch (this) {
        IntegrationKind.terminal => 'terminal',
        IntegrationKind.homeAssistant => 'ha',
        IntegrationKind.linkReport => 'link',
        IntegrationKind.lanPanel => 'lan',
      };

  IconData get icon => switch (this) {
        IntegrationKind.terminal => Icons.terminal,
        IntegrationKind.homeAssistant => Icons.home_outlined,
        IntegrationKind.linkReport => Icons.network_check,
        IntegrationKind.lanPanel => Icons.lan,
      };

  // Klucz PL do tr() (etykieta) — tłumaczenia w l10n.
  String get labelKey => switch (this) {
        IntegrationKind.terminal => 'Zdalny terminal',
        IntegrationKind.homeAssistant => 'Panel HA',
        IntegrationKind.linkReport => 'Raport łącza',
        IntegrationKind.lanPanel => 'Panel LAN',
      };

  // Tunel na nodzie (FW > 0.70 + parowanie) potrzebują tylko pluginy sięgające do LAN.
  // Raport łącza czyta wyłącznie BE — działa też dla noda, który właśnie leży.
  bool get needsTunnel => switch (this) {
        IntegrationKind.terminal => true,
        IntegrationKind.homeAssistant => true,
        IntegrationKind.linkReport => false,
        IntegrationKind.lanPanel => true,
      };

  // Wymaga konfiguracji przed użyciem (HA: host+token; Panel LAN: adresy paneli).
  bool get needsConfig =>
      this == IntegrationKind.homeAssistant || this == IntegrationKind.lanPanel;

  static IntegrationKind? fromId(String id) => switch (id) {
        'terminal' => IntegrationKind.terminal,
        'ha' => IntegrationKind.homeAssistant,
        'link' => IntegrationKind.linkReport,
        'lan' => IntegrationKind.lanPanel,
        _ => null,
      };
}
