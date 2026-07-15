/// SENSMOS — konfiguracja globalna
class Config {
  // Wersja aplikacji — trzymać w zgodzie z pubspec.yaml (version:)
  static const String appVersion = '1.4.7';
  // Manifest aktualizacji (wersja + changelog + URL APK) — public/app/manifest.json na BE
  static const String updateManifestUrl = 'https://api.sensmos.com/app/manifest.json';

  // Backend (publiczne dane: mapa, ranking, statystyki)
  static const String beUrl  = 'https://api.sensmos.com';
  // URL przekazywany do noda (z /v1 — firmware dokleja /ws)
  static const String nodeBackendUrl = 'https://api.sensmos.com/v1';
  static const String wsUrl  = 'wss://api.sensmos.com/v1/map/live';

  // BLE — UUID usługi SENSMOS (zgodne z firmware ble_config.h)
  static const String bleServiceUuid = 'a7f3bc52-4e1d-4e7a-9c2f-8b5d6e3a1f0c';
  static const String bleCharWrite    = 'a7f3bc52-4e1d-4e7a-9c2f-8b5d6e3a1f0d'; // app → esp
  static const String bleCharRead     = 'a7f3bc52-4e1d-4e7a-9c2f-8b5d6e3a1f0e'; // esp → app
  static const String bleNamePrefix   = 'SENSMOS-';

  // mDNS — wykrywanie nodów w sieci lokalnej
  static const String mdnsService = '_sensmos._tcp';

  // Klucze secure storage
  static const String kWalletKey   = 'sensmos_wallet_privkey';
  static const String kWalletAddr  = 'sensmos_wallet_address';
  static const String kNodeId      = 'sensmos_node_id';
  static const String kNodeIp      = 'sensmos_node_ip';
  static const String kNodePin      = 'sensmos_node_pin';
  static const String kNodeHostname = 'sensmos_node_hostname';

  // Polygon mainnet — kontrakt GALU (SensmosRewardPool = token + pula nagród).
  static const String polygonRpc  = 'https://polygon-bor-rpc.publicnode.com';
  static const String rewardPool  = '0x9d797D0E642D9EADdbDbD34ACFCFd07bf0043c6C';
}
