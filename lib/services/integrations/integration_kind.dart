import 'package:flutter/material.dart';

/// Typy pluginów które można PODPIĄĆ do noda (opt-in, per node). Nie każdy ma HA/terminal,
/// więc user dodaje tylko to, czego potrzebuje. Rozszerzalne — nowy plugin = nowy wariant.
/// linkReport (2026-08-25) = pierwszy plugin BEZ tunelu: dane z BE (wd_outages), nie z LAN.
/// store (2026-09-07) = drugi plugin bez tunelu: pakiet miejsca u innych właścicieli nodów,
/// pliki szyfrowane na telefonie kluczem z podpisu portfela; rozmowa tylko apka↔BE.
enum IntegrationKind { terminal, homeAssistant, linkReport, lanPanel, store }

extension IntegrationKindX on IntegrationKind {
  String get id => switch (this) {
        IntegrationKind.terminal => 'terminal',
        IntegrationKind.homeAssistant => 'ha',
        IntegrationKind.linkReport => 'link',
        IntegrationKind.lanPanel => 'lan',
        IntegrationKind.store => 'store',
      };

  IconData get icon => switch (this) {
        IntegrationKind.terminal => Icons.terminal,
        IntegrationKind.homeAssistant => Icons.home_outlined,
        IntegrationKind.linkReport => Icons.network_check,
        IntegrationKind.lanPanel => Icons.lan,
        IntegrationKind.store => Icons.sd_storage_outlined,
      };

  // Klucz PL do tr() (etykieta) — tłumaczenia w l10n.
  String get labelKey => switch (this) {
        IntegrationKind.terminal => 'Zdalny terminal',
        IntegrationKind.homeAssistant => 'Panel HA',
        IntegrationKind.linkReport => 'Łącze',
        IntegrationKind.lanPanel => 'HTTP w LAN',
        IntegrationKind.store => 'Dysk',
      };

  // Tunel na nodzie (FW > 0.70 + parowanie) potrzebują tylko pluginy sięgające do LAN.
  // Raport łącza czyta wyłącznie BE — działa też dla noda, który właśnie leży.
  bool get needsTunnel => switch (this) {
        IntegrationKind.terminal => true,
        IntegrationKind.homeAssistant => true,
        IntegrationKind.linkReport => false,
        IntegrationKind.lanPanel => true,
        IntegrationKind.store => false,
      };

  // Wymaga konfiguracji przed użyciem (HA: host+token; Panel LAN i Terminal: lista celów).
  bool get needsConfig => this != IntegrationKind.linkReport && this != IntegrationKind.store;

  static IntegrationKind? fromId(String id) => switch (id) {
        'terminal' => IntegrationKind.terminal,
        'ha' => IntegrationKind.homeAssistant,
        'link' => IntegrationKind.linkReport,
        'lan' => IntegrationKind.lanPanel,
        'store' => IntegrationKind.store,
        _ => null,
      };
}
