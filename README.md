# DATAHIVE App (Flutter)

Szkielet aplikacji mobilnej DATAHIVE.

## Architektura

```
CoreBloc (globalny stan: wallet + connected node)
   │
   ├─ AppRouter — wybiera ekran wg fazy:
   │    loading → needWallet → needNode → ready
   │
   ├─ Onboarding (tworzy wallet automatycznie)
   ├─ Setup (parowanie noda — IP+PIN teraz, BLE później)
   └─ AppShell (bottom nav)
        ├─ Dashboard   (DashboardBloc — TODO)
        ├─ Map         (flutter_map — TODO)
        ├─ Wallet      (claim, saldo — TODO)
        ├─ Ranking     (działa — leaderboard API)
        └─ NodeConfig  (lokalizacja, webhooki — TODO)
```

## Serwisy (wstrzykiwane do BLoCów)

- `WalletService` — generowanie/podpis, secure storage (opcja C)
- `NodeService`   — proxy do noda (PIN), operacje wrażliwe
- `ApiService`    — BE publiczne (mapa, ranking) — działa
- `BleService`    — skan BLE + mDNS (TODO: firmware BLE chars)

## Uruchomienie

```bash
cd datahive_app
flutter pub get
flutter run
```

Zmień `lib/config.dart` → `beUrl` na adres backendu.

## Model bezpieczeństwa

```
Wrażliwe (portfel, config) → NodeService → ESP32 (PIN) → BE (session token)
Publiczne (mapa, ranking)  → ApiService → BE bezpośrednio
Wallet → secure storage telefonu + backup do ESP NVS (opcja C)
```

## Do zrobienia (priorytety)

1. Mapa — przenieść z map.html (flutter_map + heatmapy)
2. Dashboard — wykres nagród (fl_chart) + saldo z noda
3. Wallet — claim on-chain (web3dart)
4. BLE setup — pełny flow (skan → WiFi → challenge)
5. Node config — picker lokalizacji, webhooki, skrypty
6. bip39 mnemonic w WalletService (backup frazy)
