import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lekka lokalizacja: klucz = polski tekst źródłowy, mapy nadpisań per język.
/// Domyślnie język z systemu (pl → polski, de → niemiecki, inne → angielski);
/// użytkownik może wymusić w ustawieniach ('pl'/'en'/'de'/'system').
/// Fallback brakującego wpisu: język → EN → klucz (PL).
/// Interpolacja: w kluczu `%s`, podmieniane kolejno z [args].
///
/// Użycie:
///   tr('Portfel')                       → "Wallet" (EN) / "Portfel" (PL)
///   tr('Saldo: %s GALU', [balance])     → "Balance: 12 GALU"
///
/// NOWY JĘZYK = mapa `_xxMap` + wpis w `_langMaps` + case w `_apply()`
/// + opcja w ustawieniach + Locale w main.dart.
class L10n {
  static String _lang = 'pl';                           // rozwiązany: 'pl' | 'en' | 'de'
  static String _mode = 'system';                       // 'system' | 'pl' | 'en' | 'de'
  static final ValueNotifier<int> notifier = ValueNotifier(0);  // wymusza rebuild UI

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _mode = p.getString('lang') ?? 'system';
    } catch (_) { _mode = 'system'; }
    _apply();
  }

  static void _apply() {
    _lang = switch (_mode) {
      'pl' || 'en' || 'de' => _mode,
      _ => switch (PlatformDispatcher.instance.locale.languageCode) {
             'pl' => 'pl',
             'de' => 'de',
             _    => 'en',
           },
    };
  }

  static String get mode => _mode;
  static String get lang => _lang;
  static bool   get isEn => _lang != 'pl';   // legacy (stare użycia binarne)

  static Future<void> setMode(String mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _apply();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('lang', mode);
    } catch (_) {}
    notifier.value++;   // przebuduj całą apkę
  }
}

const Map<String, Map<String, String>> _langMaps = {'en': _enMap, 'de': _deMap};

String tr(String pl, [List<Object?> args = const []]) {
  var s = L10n.lang == 'pl' ? pl : (_langMaps[L10n.lang]?[pl] ?? _enMap[pl] ?? pl);
  for (final a in args) {
    s = s.replaceFirst('%s', '$a');
  }
  return s;
}

/// Nadpisania angielskie. Brak wpisu → pokazujemy klucz (PL).
const Map<String, String> _enMap = {
  // ── Self-update ──────────────────────────────────────────────
  "Sprawdź aktualizację": "Check for updates",
  "nowa wersja i lista zmian": "new version and changelog",
  "Masz najnowszą wersję (%s)": "You're on the latest version (%s)",
  "Dostępna aktualizacja %s": "Update %s available",
  "Później": "Later",
  "Pobierz": "Download",
  "Nie udało się sprawdzić aktualizacji": "Couldn't check for updates",
  // ── Wspólne ──────────────────────────────────────────────────
  "Anuluj": "Cancel",
  "Zapisz": "Save",
  "Usuń": "Delete",
  "Zamknij": "Close",
  "Kopiuj": "Copy",
  "Edytuj": "Edit",
  "Dalej": "Next",
  "Błąd": "Error",
  "błąd": "error",
  "Błąd: %s": "Error: %s",
  "Błąd %s": "Error %s",
  "Błąd ładowania: %s": "Loading error: %s",
  "Błędny PIN": "Wrong PIN",
  "PIN noda": "Node PIN",
  "Skanowanie...": "Scanning...",
  "Łączę...": "Connecting...",
  "JAK TO DZIAŁA": "HOW IT WORKS",
  "Ustawienia": "Settings",
  "Język": "Language",
  "wymuś język aplikacji": "force app language",
  "Systemowy": "System",
  "Logi": "Logs",
  "błędy i zdarzenia aplikacji": "app errors and events",
  "Skopiowano logi": "Logs copied",
  "Brak logów": "No logs",
  "Nie odpowiada (offline?)": "Not responding (offline?)",
  "Poza siecią": "Off network",
  "Błędna odpowiedź noda": "Bad node response",
  "Niedostępny": "Unavailable",
  "Nody": "Nodes",
  "Encje": "Entities",
  "Skrypty": "Scripts",
  "Akcje": "Actions",
  "Odebrane": "Inbox",
  "Wymagane": "Required",
  "Wyczyść": "Clear",

  // ── Portfel ──────────────────────────────────────────────────
  "Portfel": "Wallet",
  "Wpłać GALU na nody": "Deposit GALU to nodes",
  "Za mało GALU w portfelu": "Not enough GALU in wallet",
  "Zatwierdzanie GALU (approve)…": "Approving GALU…",
  "Approve nie powiodło się": "Approve failed",
  "Wpłacanie…": "Depositing…",
  "Wpłacono %s GALU": "Deposited %s GALU",
  "Deposit zrewertowany": "Deposit reverted",
  "Brak nagród": "No rewards",
  "Nagrody z epoki %s już odebrane": "Rewards for epoch %s already claimed",
  "Odbieranie nagród…": "Claiming rewards…",
  "Odebrano nagrody (epoka %s)": "Rewards claimed (epoch %s)",
  "Claim zrewertowany": "Claim reverted",
  "Brak nodów — eksport wymaga PIN-u noda": "No nodes — export requires a node PIN",
  "Brak połączenia z żadnym nodem": "No connection to any node",
  "ADRES PORTFELA": "WALLET ADDRESS",
  "Adres skopiowany": "Address copied",
  "SALDO W SIECI (GALU)": "NETWORK BALANCE (GALU)",
  "Do wydania na nody": "Available for nodes",
  "Do odebrania (claim)": "Claimable",
  "Wypłata w toku": "Claim in progress",
  "Wpłata w toku": "Deposit in progress",
  "Zarobione (nagrody)": "Earned (rewards)",
  "Wpłacone (Twój kapitał)": "Deposited (your funds)",
  "Zdeponowane": "Deposited",
  "Odebrano": "Claimed",
  "Odbierz (Claim)": "Claim",
  "Wpłać (Deposit)": "Deposit",
  "SALDO ON-CHAIN (Polygon)": "ON-CHAIN BALANCE (Polygon)",
  "GALU w portfelu": "GALU in wallet",
  "MATIC (gas)": "MATIC (gas)",
  "Brak MATIC — transakcje (claim/deposit) wymagają gazu. Wpłać MATIC na adres portfela (QR powyżej).":
      "No MATIC — transactions (claim/deposit) require gas. Send MATIC to your wallet address (QR above).",
  "Eksportuj klucz (MetaMask)": "Export key (MetaMask)",
  "wymaga PIN-u dowolnego Twojego noda": "requires the PIN of any of your nodes",
  "Dostępne: %s (MAX)": "Available: %s (MAX)",
  "Odblokuj": "Unlock",
  "Klucz prywatny": "Private key",
  "⚠️ Nigdy nikomu nie pokazuj tego klucza. Kto go ma, kontroluje portfel i wszystkie GALU.":
      "⚠️ Never show this key to anyone. Whoever has it controls the wallet and all GALU.",
  "MetaMask → Importuj konto → Private Key → wklej.": "MetaMask → Import account → Private Key → paste.",
  "Klucz skopiowany": "Key copied",
  "Odbiór MATIC / GALU": "Receive MATIC / GALU",
  "Wyślij MATIC na ten adres (gas na transakcje)": "Send MATIC to this address (gas for transactions)",
  "Kopiuj adres": "Copy address",

  // ── Skrypty ──────────────────────────────────────────────────
  "Usuń skrypt": "Delete script",
  "Skrypty wykonywane lokalnie na nodzie — uruchamiane przez akcje wiadomości.":
      "Scripts run locally on the node — triggered by message actions.",
  "Brak skryptów. Dodaj przyciskiem +": "No scripts. Add one with +",
  "Kroki: %s": "Steps: %s",
  "Edytuj skrypt": "Edit script",
  "Nowy skrypt": "New script",
  "Dodaj krok (%s/%s)": "Add step (%s/%s)",
  "KROK %s": "STEP %s",
  "WARUNEK (opcjonalnie)": "CONDITION (optional)",
  "BODY TEMPLATE (opcjonalnie)": "BODY TEMPLATE (optional)",
  "TYTUŁ": "TITLE",
  "TREŚĆ": "BODY",
  "Wartość: {{pub.grid_v}}": "Value: {{pub.grid_v}}",
  "DEVICE ID ODBIORCY": "RECIPIENT DEVICE ID",
  "PAYLOAD (opc.)": "PAYLOAD (opt.)",
  "WYRAŻENIE": "EXPRESSION",
  "ZAPISZ DO": "STORE TO",
  "ZAPISZ DO (opc.)": "STORE TO (opt.)",
  "JSON PATH (opc.)": "JSON PATH (opt.)",
  "ENCJA": "ENTITY",
  "FUNKCJA": "FUNCTION",
  "PRÓBKI": "SAMPLES",

  // ── Akcje wiadomości / wiadomości ────────────────────────────
  "Usuń akcję": "Delete action",
  "Brak akcji. Dodaj przyciskiem +": "No actions. Add one with +",
  "Automatyczne akcje wykonywane gdy node odbierze wiadomość o podanym ID (lub \"*\" dla wszystkich).":
      "Automatic actions run when the node receives a message with the given ID (or \"*\" for all).",
  "ID wiadomości triggera — \"alarm\", \"update\", \"*\" = wszystkie":
      "Trigger message ID — \"alarm\", \"update\", \"*\" = all",
  "powiadomienie na telefon (tytuł/treść; {{from}}, {{payload}})":
      "phone notification (title/body; {{from}}, {{payload}})",
  "URL do wywołania HTTP POST z payloadem wiadomości": "URL to call via HTTP POST with the message payload",
  "Zapisz encje z payloadu jako {prefix}.entity_id na nodzie":
      "Store payload entities as {prefix}.entity_id on the node",
  "ID skryptu do uruchomienia przy odebraniu wiadomości": "Script ID to run when the message is received",
  "Edytuj akcję": "Edit action",
  "Nowa akcja": "New action",
  "alarm, update, * (wszystkie)": "alarm, update, * (all)",
  "POWIADOMIENIE": "NOTIFICATION",
  "Tytuł — np. Od {from}": "Title — e.g. From {from}",
  "Treść — np. {message}": "Body — e.g. {message}",
  "msg  →  zapisze jako msg.*": "msg  →  stored as msg.*",
  "ID skryptu do uruchomienia": "Script ID to run",
  "Brak wiadomości w skrzynce.": "No messages in the inbox.",
  "· %s nieprzeczytanych": "· %s unread",
  "od: %s": "from: %s",
  "(brak payloadu)": "(no payload)",

  // ── Setup / Onboarding ───────────────────────────────────────
  "Włącz Bluetooth": "Turn on Bluetooth",
  "Wpisz nazwę sieci WiFi": "Enter WiFi network name",
  "Łączenie przez BLE...": "Connecting via BLE...",
  "Łączenie z nodem...": "Connecting to node...",
  "Autoryzacja BLE...": "BLE authorization...",
  "Brak nonce — aktualizuj firmware": "No nonce — update firmware",
  "Zły PIN — sprawdź kod ustawiony na urządzeniu": "Wrong PIN — check the code set on the device",
  "Nie udało się połączyć z nodem przez Bluetooth. Upewnij się, że node jest w trybie konfiguracji (przytrzymaj przycisk ~3 s), podejdź bliżej i przełącz Bluetooth. Jeśli resetowałeś node — wróć do skanowania, bo ma teraz nową nazwę.": "Couldn't connect to the node over Bluetooth. Make sure the node is in setup mode (hold the button ~3 s), move closer and toggle Bluetooth. If you reset the node, go back to scanning — it now has a new name.",
  "Wpisz PIN urządzenia": "Enter the device PIN",
  "Autoryzacja nieudana": "Authorization failed",
  "Sprawdzam portfel...": "Checking wallet...",
  "Odzyskiwanie portfela z noda...": "Restoring wallet from node...",
  "Brak kopii na nodzie": "No backup on node",
  "Tworzę nowy portfel...": "Creating new wallet...",
  "Podpisywanie challenge...": "Signing challenge...",
  "Łączę z WiFi przez node...": "Connecting to WiFi via node...",
  "Łączę z nodem przez sieć...": "Connecting to node over network...",
  "Podłącz urządzenie": "Connect device",
  "Szukam...": "Searching...",
  "Znalezione urządzenia": "Found devices",
  "Brak urządzeń.\nUpewnij się że node jest w trybie konfiguracji.":
      "No devices.\nMake sure the node is in setup mode.",
  "Podaj dane WiFi": "Enter WiFi credentials",
  "Nazwa sieci WiFi (SSID)": "WiFi network name (SSID)",
  "Hasło WiFi": "WiFi password",
  "PIN noda (zapisany w urządzeniu)": "Node PIN (set on the device)",
  "Konfiguruj": "Configure",
  "← Wróć do skanowania": "← Back to scanning",
  // ── Odtwarzanie ID noda (po reflashu) ──
  "Odtwórz ID noda": "Restore node ID",
  "Ta płytka przejmie ID i historię wybranego noda offline (np. po reflashu).":
      "This board takes over the ID and history of the selected offline node (e.g. after a reflash).",
  "Odtwarzam poprzednie ID noda...": "Restoring the node's previous ID...",
  "Ta płytka ma za stary firmware, żeby odtworzyć ID. Zaflashuj najnowszy firmware na sensmos.com/flash i spróbuj ponownie.":
      "This board's firmware is too old to restore an ID. Flash the latest firmware at sensmos.com/flash and try again.",
  "Ta płytka nie umie odtworzyć ID (firmware: %s). Zaflashuj najnowszy firmware na sensmos.com/flash i spróbuj ponownie.":
      "This board can't restore an ID (firmware: %s). Flash the latest firmware at sensmos.com/flash and try again.",
  "Usunięto nieaktywny wpis %s (node po reflashu)": "Removed stale entry %s (reflashed node)",
  "Nie udało się zarejestrować noda": "Failed to register node",
  "Urządzenie się resetuje — zaczekaj i spróbuj ponownie.": "The device is resetting — wait and try again.",
  "Może potrwać do 30 sekund": "May take up to 30 seconds",
  "Gotowe!": "Done!",
  "Przejdź do panelu (%s)": "Go to dashboard (%s)",
  "Przejdź do panelu": "Go to dashboard",
  "Twoje urządzenia. Twoje dane. Twoja sieć.": "Your devices. Your data. Your network.",
  "Podłącz czujnik i monitoruj okolicę": "Connect a sensor and monitor your area",
  "Wymieniaj dane z sąsiadami": "Exchange data with neighbors",
  "Alerty na telefon": "Alerts on your phone",
  "Połącz node": "Connect node",
  "Portfel powstaje przy pierwszym nodzie albo jest odzyskiwany z noda przez Bluetooth.":
      "The wallet is created with your first node or restored from a node via Bluetooth.",

  // ── Ustawienia noda ──────────────────────────────────────────
  "Ustawienia noda": "Node settings",
  "odebrane wiadomości na nodzie": "messages received on the node",
  "akcje na odebrane wiadomości (webhook, encje)": "actions on received messages (webhook, entities)",
  "automatyzacje noda": "node automations",
  "Lokalizacja": "Location",
  "współrzędne noda": "node coordinates",
  "Lokalizacja noda": "Node location",
  "Integracja (webhook)": "Integration (webhook)",
  "URL wywoływany przy zdarzeniach noda": "URL called on node events",
  "Zaufanie (trust)": "Trust",
  "ceremonia potwierdzająca fizyczne urządzenie": "ceremony confirming the physical device",
  "Zmień PIN": "Change PIN",
  "PIN dostępu do noda": "node access PIN",
  "Tryb serwisowy (Bluetooth)": "Service mode (Bluetooth)",
  "zmiana WiFi / odzyskiwanie portfela": "change WiFi / recover wallet",
  "Usuń node z listy": "Remove node from list",
  "Usuwa node tylko z tej apki": "Removes the node only from this app",
  "Usuń node z sieci (permanentnie)": "Delete node from network (permanent)",
  "Kasuje node i wszystkie jego dane z SENSMOS. Możesz go później dodać ponownie (onboarding przez Bluetooth). Zarobione GALU zostają na Twoim wallecie.":
      "Removes the node and all its data from SENSMOS. You can add it back later (Bluetooth onboarding). Earned GALU stays in your wallet.",
  "Usunąć node z sieci?": "Delete node from network?",
  "Node %s i WSZYSTKIE jego dane zostaną trwale usunięte z SENSMOS. Możesz go później dodać ponownie (onboarding przez Bluetooth). Zarobione GALU pozostają na Twoim wallecie.":
      "Node %s and ALL its data will be permanently removed from SENSMOS. You can add it back later (Bluetooth onboarding). Earned GALU stays in your wallet.",
  "Usuń permanentnie": "Delete permanently",
  "Node usunięty z sieci": "Node deleted from network",
  "Błąd usuwania: %s": "Delete error: %s",
  "Brak walleta": "No wallet",
  "Importujesz INNY portfel (%s) niż obecny (%s).\n\nTwoje nody pozostaną przypisane do obecnego portfela, dopóki nie dodasz ich ponownie przez Bluetooth (to zmieni właściciela i wymaga ponownej weryfikacji — bez resetu urządzenia). Zarobione GALU zostają przy portfelu, który je zarobił.": "You are importing a DIFFERENT wallet (%s) than the current one (%s).\n\nYour nodes stay assigned to the current wallet until you re-add them over Bluetooth (that changes the owner and requires re-verification — no device reset). Earned GALU stays with the wallet that earned it.",

  "Moje nody w sieci": "My nodes in the network",
  "Wszystkie nody zarejestrowane na Twój wallet (wg SENSMOS)": "All nodes registered to your wallet (per SENSMOS)",
  "brak w tej apce": "not in this app",
  "nieaktywny": "inactive",
  "ID skopiowane: %s": "ID copied: %s",
  "Kopiuj ID noda": "Copy node ID",
  "Kopiuj ID": "Copy ID",
  "Importuj klucz prywatny": "Import private key",
  "Importuj portfel": "Import wallet",
  "Monitoruj sieć i internet": "Monitor your network and internet",
  "Korzystałeś już z SENSMOS?": "Already using SENSMOS?",
  "Wyszukaj moje nody w sieci WiFi": "Find my nodes on WiFi",
  "Wyszukaj moje nody": "Find my nodes",
  "Node dodany": "Node added",
  "Zły PIN": "Wrong PIN",
  "Szukam noda...": "Searching for node...",
  "Sprawdzam PIN...": "Checking PIN...",
  "Wpisz IP noda — PIN podasz, gdy urządzenie się odnajdzie.": "Enter the node IP — you'll enter the PIN once the device is found.",
  "brak portfela": "no wallet",
  "Aplikacja nie ma przypisanego portfela": "The app has no wallet assigned",
  "Zaimportuj go z klucza (zakladka Portfel) lub z noda (rozwin swoj node ponizej -> Importuj portfel z noda).": "Import it from a key (Wallet tab) or from a node (expand your node below -> Import wallet from node).",
  "import z klucza": "import from key",
  "Klucz portfela (zaawansowane)": "Wallet key (advanced)",
  "Usunąć z tej apki?": "Remove from this app?",
  "Node zniknie tylko z tego telefonu - pozostaje w sieci i nalicza nagrody. Aby usunac go z sieci, uzyj Usun z sieci.": "The node disappears only from this phone - it stays in the network and keeps earning. To remove it from the network, use Delete from network.",
  "Usuń z apki": "Remove from app",
  "import / eksport klucza prywatnego": "import / export private key",
  "Brak portfela w apce. Odzyskaj kopię zapisaną na tym nodzie.": "No wallet in the app. Recover the copy saved on this node.",
  "Importuj portfel z noda": "Import wallet from node",
  "Dodaj node": "Add node",
  "tworzy nowy portfel": "creates a new wallet",
  "masz już portfel (np. w MetaMask)? odzyskaj dostęp do swoich nodów": "already have a wallet (e.g. in MetaMask)? restore access to your nodes",
  "wklej klucz z MetaMask (0x… lub 64 hex)": "paste a key from MetaMask (0x… or 64 hex)",
  "Wklej klucz prywatny (np. z MetaMask). Rób to tylko na swoim telefonie.": "Paste a private key (e.g. from MetaMask). Only do this on your own phone.",
  "Importuj": "Import",
  "Nieprawidłowy klucz prywatny": "Invalid private key",
  "Inny portfel": "Different wallet",
  "Zaimportuj mimo to": "Import anyway",
  "Portfel zaimportowany — Twoje nody działają dalej": "Wallet imported — your nodes keep working",
  "Portfel zaimportowany: %s": "Wallet imported: %s",
  "Błąd importu: %s": "Import error: %s",
  "Odebrano nagrody": "Rewards claimed",
  "Wszystko już odebrane": "Everything already claimed",
  "Usunąć \"%s\"?": "Delete \"%s\"?",
  "Usunąć akcję dla \"%s\"?": "Delete action for \"%s\"?",
  "Usuń z sieci": "Delete from network",
  "Trwale usuwa node z Twoich urządzeń": "Permanently removes the node from your devices",
  "Node POST-uje tu zdarzenia (message_received, batch_sent, sub_received, ws_connected). Puste = wyłączone.":
      "The node POSTs events here (message_received, batch_sent, sub_received, ws_connected). Empty = disabled.",
  "Integracja wyłączona": "Integration disabled",
  "Webhook zapisany": "Webhook saved",
  "Nowy PIN (min. 4 cyfry)": "New PIN (min. 4 digits)",
  "PIN zmieniony": "PIN changed",

  // ── Lokalizacja noda (GPS) ───────────────────────────────────
  "Włącz lokalizację (GPS) w telefonie": "Enable location (GPS) on your phone",
  "Brak zgody na lokalizację": "Location permission denied",
  "Pozycja GPS pobrana ✓": "GPS position acquired ✓",
  "Błąd GPS: %s": "GPS error: %s",
  "Najpierw pobierz pozycję GPS": "Get the GPS position first",
  "Lokalizacja potwierdzona i zapisana": "Location confirmed and saved",
  "Stań przy nodzie i pobierz pozycję GPS — to potwierdza, że node jest naprawdę tutaj. Miasto uzupełni się samo.":
      "Stand next to the node and grab the GPS position — this confirms the node is really here. The city fills in automatically.",
  "Pobierz GPS ponownie": "Get GPS again",
  "Pobierz moją pozycję (GPS)": "Get my position (GPS)",
  "POZYCJA GPS": "GPS POSITION",
  "dokładność ±%s m": "accuracy ±%s m",
  "Brak pozycji — naciśnij przycisk powyżej.": "No position — tap the button above.",
  "Rozmycie prywatności": "Privacy blur",
  "Na mapie ~200–800 m od prawdziwej pozycji (losowo)": "On the map ~200–800 m from the real position (random)",
  "Na mapie dokładny adres noda": "Exact node address on the map",
  "Zapisz lokalizację": "Save location",

  // ── Node manager / lista nodów ───────────────────────────────
  "Dodaj": "Add",
  "Szukaj": "Search",
  "Ręcznie": "Manual",
  "Jak dodać node?": "How to add a node?",
  "ESP32 musi być włączony i w trybie konfiguracji (świeci LED)":
      "ESP32 must be on and in configuration mode (LED lit)",
  "Bluetooth musi być włączony na telefonie": "Bluetooth must be enabled on your phone",
  "Telefon musi być połączony z siecią WiFi z dostępem do internetu":
      "Phone must be connected to WiFi with internet access",
  "WiFi do której podłączysz node musi być w zasięgu": "The WiFi you connect the node to must be in range",
  "Przygotuj nazwę sieci (SSID) i hasło WiFi": "Have your network name (SSID) and WiFi password ready",
  "Dodaj nowy node przez BLE": "Add new node via BLE",
  "Szuka nodów SENSMOS w sieci WiFi.": "Searches for SENSMOS nodes on the WiFi network.",
  "Szukaj w sieci": "Search network",
  "Nie znaleziono nodów w sieci.": "No nodes found on the network.",
  "Dodany": "Added",
  "Wpisz IP i PIN gdy znasz adres noda.": "Enter IP and PIN if you know the node's address.",
  "Adres IP noda": "Node IP address",
  "Połącz i dodaj": "Connect and add",
  "Wpisz adres IP": "Enter IP address",
  "Brak odpowiedzi z %s.": "No response from %s.",
  "Dodaję...": "Adding...",
  "Panel": "Dashboard",
  "Odśwież": "Refresh",
  "GALU saldo": "GALU balance",
  "Sąsiedzi": "Neighbors",
  "Promień": "Radius",
  "Node niedostępny": "Node unavailable",
  "Brak nodów": "No nodes",
  "Dodaj node przez BLE": "Add node via BLE",

  // ── Zaufanie (trust) / tryb serwisowy ────────────────────────
  "Zaufanie noda": "Node trust",
  "Brak portfela": "No wallet",
  "Przełączam node w tryb Bluetooth…": "Switching node to Bluetooth mode…",
  "Node nie odpowiada: %s": "Node not responding: %s",
  "Node restartuje się — szukam przez Bluetooth…": "Node is restarting — searching over Bluetooth…",
  "Nie znalazłem noda przez Bluetooth.\nNode wróci sam do WiFi w ciągu 5 minut.":
      "Couldn't find the node over Bluetooth.\nThe node will return to WiFi on its own within 5 minutes.",
  "Połączono — przeprowadzam ceremonię…": "Connected — running the ceremony…",
  "Autoryzacja BLE nieudana (PIN?)": "BLE authorization failed (PIN?)",
  "Backend niedostępny — brak seedu ceremonii": "Backend unavailable — no ceremony seed",
  "Rundy challenge (%s)…": "Challenge rounds (%s)…",
  "Weryfikacja w sieci…": "Verifying on the network…",
  "Weryfikacja odrzucona: %s": "Verification rejected: %s",
  "Node zaufany — wraca do WiFi.": "Node trusted — returning to WiFi.",
  "Powtórz ceremonię": "Repeat ceremony",
  "Przeprowadź ceremonię": "Run ceremony",
  "Ceremonia zakończona — node zaufany.": "Ceremony complete — node trusted.",
  "Node zaufany": "Node trusted",
  "Node niezweryfikowany": "Node not verified",
  "Ceremonia: %s": "Ceremony: %s",
  "Przeprowadź ceremonię, aby potwierdzić,\nże to fizyczne urządzenie.":
      "Run the ceremony to confirm\nthis is a physical device.",
  "Node restartuje się w tryb Bluetooth (zostaw go włączonego).":
      "The node restarts into Bluetooth mode (leave it powered on).",
  "Telefon łączy się i wykonuje szybkie rundy challenge — dowód, że urządzenie jest fizycznie obok.":
      "The phone connects and runs quick challenge rounds — proof the device is physically nearby.",
  "Node podpisuje atest swoim kluczem, Ty podpisujesz portfelem.":
      "The node signs the attestation with its key, you sign with your wallet.",
  "Sieć weryfikuje oba podpisy i oznacza node jako zaufany. Node sam wraca do WiFi.":
      "The network verifies both signatures and marks the node as trusted. The node returns to WiFi on its own.",
  "Tryb serwisowy": "Service mode",
  "Node nieosiągalny po sieci — przytrzymaj przycisk na nodzie 3 s, aż wejdzie w tryb Bluetooth…":
      "Node unreachable over the network — hold the button on the node for 3 s until it enters Bluetooth mode…",
  "Nie znalazłem noda przez Bluetooth.\nUpewnij się, że jest w trybie serwisowym (przycisk 3 s).":
      "Couldn't find the node over Bluetooth.\nMake sure it's in service mode (button, 3 s).",
  "Zapisuję WiFi…": "Saving WiFi…",
  "WiFi zapisane — node restartuje się i łączy z siecią.": "WiFi saved — the node restarts and connects to the network.",
  "Pobieram kopię z noda…": "Fetching backup from the node…",
  "Ten node nie ma kopii portfela": "This node has no wallet backup",
  "Brak kopii": "No backup",
  "Portfel odzyskany: %s": "Wallet recovered: %s",
  "Wejdź w tryb serwisowy": "Enter service mode",
  "Zmień sieć WiFi": "Change WiFi network",
  "wpisz nowe SSID i hasło — node przełączy się": "enter a new SSID and password — the node will switch",
  "Odzyskaj portfel z noda": "Recover wallet from node",
  "pobierz kopię portfela na ten telefon": "download the wallet backup to this phone",
  "Po co tryb serwisowy?": "Why service mode?",
  "Zmiana WiFi i odzyskiwanie portfela działają tylko przez Bluetooth (bliskość fizyczna). Node przejdzie w tryb BLE — jeśli jest nieosiągalny po sieci, przytrzymaj przycisk na nodzie ok. 3 s.":
      "Changing WiFi and recovering the wallet work only over Bluetooth (physical proximity). The node enters BLE mode — if it's unreachable over the network, hold the button on the node for about 3 s.",
  "Nowa sieć WiFi": "New WiFi network",
  "Nazwa sieci (SSID)": "Network name (SSID)",
  "Hasło": "Password",

  // ── Powiadomienia / Ustawienia / Encje / Lokalizacje / Ranking ─
  "Zapisano na %s/%s nodach": "Saved on %s/%s nodes",
  "Powiadomienia": "Notifications",
  "TOKEN PUSH (FCM)": "PUSH TOKEN (FCM)",
  "wklej token FCM…": "paste FCM token…",
  "Włącz na nodach": "Enable on nodes",
  "Wyłącz": "Disable",
  "STAN NA NODACH": "STATUS ON NODES",
  "włączone · %s…": "enabled · %s…",
  "wyłączone": "disabled",
  "Token FCM jest pobierany automatycznie i rozsyłany na nody przy starcie aplikacji. To pole pokazuje aktualny token — możesz go też ręcznie wymusić na nodach. Node przekazuje go do backendu, który wysyła powiadomienia.":
      "The FCM token is fetched automatically and pushed to nodes at app startup. This field shows the current token — you can also force it onto nodes manually. The node forwards it to the backend, which sends notifications.",
  "Lokalizacja nodów": "Node locations",
  "współrzędne wszystkich urządzeń": "coordinates of all devices",
  "token push, włącz/wyłącz na nodach": "push token, enable/disable on nodes",
  "Aplikacja": "App",
  "Wersja": "Version",
  "Brak encji": "No entities",
  "Publiczne": "Public",
  "Własne": "Own",
  "Zewnętrzne": "External",
  "Wiek: %s": "Age: %s",
  "lokalna": "local",
  "Brak zapisanych nodów": "No saved nodes",
  "Ustaw współrzędne każdego noda osobno — pozycja na mapie sieci i regiony scoringu.":
      "Set coordinates for each node separately — position on the network map and scoring regions.",
  "Ranking miast": "City ranking",
  "%s nodów · %s online": "%s nodes · %s online",

  // ── Pasek nawigacji / powiadomienia ──────────────────────────
  "Nowe powiadomienie\nsprawdź skrzynkę noda": "New notification\ncheck the node inbox",

  // ── Komunikaty z serwisów (wyjątki → snackbar) ───────────────
  "Brak usługi SENSMOS": "SENSMOS service not found",
  "Nie połączono": "Not connected",
  "Node nie pojawił się w sieci.\nSprawdź SSID i hasło WiFi.":
      "Node didn't appear on the network.\nCheck the SSID and WiFi password.",
  "Błędny PIN lub uszkodzona kopia": "Wrong PIN or corrupted backup",

  // ── Lokalizacja / weryfikacja / prywatność ───────────────────
  "Lokalizacja i weryfikacja": "Location & verification",
  "ceremonia BLE + GPS — ustawia pozycję i potwierdza urządzenie":
      "BLE + GPS ceremony — sets position and verifies the device",
  "PRYWATNOŚĆ": "PRIVACY",
  "Na mapie ~200–800 m od prawdziwej pozycji (losowo).":
      "On the map ~200–800 m from the real position (random).",
  "Na mapie dokładny adres noda.": "Exact node address on the map.",
  "Rozmycie włączone — na mapie ~200–800 m od pozycji":
      "Blur on — shown ~200–800 m from position on the map",
  "Rozmycie wyłączone — na mapie dokładny adres":
      "Blur off — exact address shown on the map",
  "Najpierw ustaw lokalizację (ceremonia powyżej).":
      "Set the location first (ceremony above).",
  "Wymaga firmware 0.27+ — zaktualizuj node.":
      "Requires firmware 0.27+ — update the node.",
  "Wymaga firmware 0.25+ — zaktualizuj node.":
      "Requires firmware 0.25+ — update the node.",
  "Tryb prywatny (ghost)": "Private mode (ghost)",
  "Ukryty z mapy, 0 nagród. Dane działają lokalnie; za subskrypcje płacisz.":
      "Hidden from map, 0 rewards. Data works locally; you still pay for subscriptions.",
  "Tryb prywatny włączony — node ukryty z mapy i nagród":
      "Private mode on — node hidden from the map and rewards",
  "Tryb prywatny wyłączony": "Private mode off",
  "Pobieram pozycję GPS...": "Getting GPS position...",
  "Zaraz poprosimy o lokalizację (GPS) — potwierdza, że node jest fizycznie tutaj. Bez niej node działa, ale zarabia znacznie mniej.":
      "We'll ask for location (GPS) — it confirms the node is physically here. Without it the node works but earns much less.",
  "Brak lokalizacji — node niewidoczny na mapie i nie nalicza nagród.":
      "No location — node not shown on the map and earns no rewards.",
  "Ustaw lokalizację": "Set location",
  "Połącz się z siecią noda, aby ustawić lokalizację.":
      "Connect to the node's network to set the location.",
  "Połącz się z siecią WiFi noda, aby zobaczyć encje i zmienić ustawienia.":
      "Connect to the node's WiFi to view entities and change settings.",

  // ── Widok noda: chmura vs sieć lokalna ───────────────────────
  "raportuje": "reporting",
  "Raportują": "Reporting",
  "cisza": "silent",
  "brak danych z chmury": "no cloud data",
  "W sieci": "On network",
  "Zdalnie": "Remote",
  "przed chwilą": "just now",
};

/// Nadpisania niemieckie. Brak wpisu → fallback EN → klucz (PL).
const Map<String, String> _deMap = {
  // ── Self-update ──────────────────────────────────────────────
  "Sprawdź aktualizację": "Nach Updates suchen",
  "nowa wersja i lista zmian": "neue Version und Änderungsliste",
  "Masz najnowszą wersję (%s)": "Du hast die neueste Version (%s)",
  "Dostępna aktualizacja %s": "Update %s verfügbar",
  "Później": "Später",
  "Pobierz": "Herunterladen",
  "Nie udało się sprawdzić aktualizacji": "Update-Prüfung fehlgeschlagen",
  // ── Wspólne ──────────────────────────────────────────────────
  "Anuluj": "Abbrechen",
  "Zapisz": "Speichern",
  "Usuń": "Löschen",
  "Zamknij": "Schließen",
  "Kopiuj": "Kopieren",
  "Edytuj": "Bearbeiten",
  "Dalej": "Weiter",
  "Błąd": "Fehler",
  "błąd": "Fehler",
  "Błąd: %s": "Fehler: %s",
  "Błąd %s": "Fehler %s",
  "Błąd ładowania: %s": "Ladefehler: %s",
  "Błędny PIN": "Falsche PIN",
  "PIN noda": "Node-PIN",
  "Skanowanie...": "Suche läuft...",
  "Łączę...": "Verbinde...",
  "JAK TO DZIAŁA": "SO FUNKTIONIERT ES",
  "Ustawienia": "Einstellungen",
  "Język": "Sprache",
  "wymuś język aplikacji": "App-Sprache erzwingen",
  "Systemowy": "System",
  "Logi": "Protokolle",
  "błędy i zdarzenia aplikacji": "App-Fehler und -Ereignisse",
  "Skopiowano logi": "Protokolle kopiert",
  "Brak logów": "Keine Protokolle",
  "Nie odpowiada (offline?)": "Antwortet nicht (offline?)",
  "Poza siecią": "Außerhalb des Netzwerks",
  "Błędna odpowiedź noda": "Ungültige Node-Antwort",
  "Niedostępny": "Nicht verfügbar",
  "Nody": "Nodes",
  "Encje": "Entitäten",
  "Skrypty": "Skripte",
  "Akcje": "Aktionen",
  "Odebrane": "Posteingang",
  "Wymagane": "Erforderlich",
  "Wyczyść": "Leeren",

  // ── Portfel ──────────────────────────────────────────────────
  "Portfel": "Wallet",
  "Wpłać GALU na nody": "GALU auf Nodes einzahlen",
  "Za mało GALU w portfelu": "Nicht genug GALU im Wallet",
  "Zatwierdzanie GALU (approve)…": "GALU wird freigegeben (approve)…",
  "Approve nie powiodło się": "Approve fehlgeschlagen",
  "Wpłacanie…": "Einzahlung läuft…",
  "Wpłacono %s GALU": "%s GALU eingezahlt",
  "Deposit zrewertowany": "Einzahlung zurückgesetzt (revert)",
  "Brak nagród": "Keine Belohnungen",
  "Nagrody z epoki %s już odebrane": "Belohnungen für Epoche %s bereits abgeholt",
  "Odbieranie nagród…": "Belohnungen werden abgeholt…",
  "Odebrano nagrody (epoka %s)": "Belohnungen abgeholt (Epoche %s)",
  "Claim zrewertowany": "Claim zurückgesetzt (revert)",
  "Brak nodów — eksport wymaga PIN-u noda": "Keine Nodes — Export erfordert eine Node-PIN",
  "Brak połączenia z żadnym nodem": "Keine Verbindung zu einem Node",
  "ADRES PORTFELA": "WALLET-ADRESSE",
  "Adres skopiowany": "Adresse kopiert",
  "SALDO W SIECI (GALU)": "NETZWERK-GUTHABEN (GALU)",
  "Do wydania na nody": "Verfügbar für Nodes",
  "Do odebrania (claim)": "Abholbar (Claim)",
  "Wypłata w toku": "Claim läuft",
  "Wpłata w toku": "Einzahlung läuft",
  "Zarobione (nagrody)": "Verdient (Belohnungen)",
  "Wpłacone (Twój kapitał)": "Eingezahlt (dein Kapital)",
  "Zdeponowane": "Eingezahlt",
  "Odebrano": "Abgeholt",
  "Odbierz (Claim)": "Abholen (Claim)",
  "Wpłać (Deposit)": "Einzahlen (Deposit)",
  "SALDO ON-CHAIN (Polygon)": "ON-CHAIN-GUTHABEN (Polygon)",
  "GALU w portfelu": "GALU im Wallet",
  "MATIC (gas)": "MATIC (Gas)",
  "Brak MATIC — transakcje (claim/deposit) wymagają gazu. Wpłać MATIC na adres portfela (QR powyżej).":
      "Kein MATIC — Transaktionen (Claim/Deposit) brauchen Gas. Sende MATIC an deine Wallet-Adresse (QR oben).",
  "Eksportuj klucz (MetaMask)": "Schlüssel exportieren (MetaMask)",
  "wymaga PIN-u dowolnego Twojego noda": "erfordert die PIN eines beliebigen deiner Nodes",
  "Dostępne: %s (MAX)": "Verfügbar: %s (MAX)",
  "Odblokuj": "Entsperren",
  "Klucz prywatny": "Privater Schlüssel",
  "⚠️ Nigdy nikomu nie pokazuj tego klucza. Kto go ma, kontroluje portfel i wszystkie GALU.":
      "⚠️ Zeige diesen Schlüssel niemandem. Wer ihn hat, kontrolliert das Wallet und alle GALU.",
  "MetaMask → Importuj konto → Private Key → wklej.": "MetaMask → Konto importieren → Private Key → einfügen.",
  "Klucz skopiowany": "Schlüssel kopiert",
  "Odbiór MATIC / GALU": "MATIC / GALU empfangen",
  "Wyślij MATIC na ten adres (gas na transakcje)": "Sende MATIC an diese Adresse (Gas für Transaktionen)",
  "Kopiuj adres": "Adresse kopieren",

  // ── Skrypty ──────────────────────────────────────────────────
  "Usuń skrypt": "Skript löschen",
  "Skrypty wykonywane lokalnie na nodzie — uruchamiane przez akcje wiadomości.":
      "Skripte laufen lokal auf dem Node — ausgelöst durch Nachrichten-Aktionen.",
  "Brak skryptów. Dodaj przyciskiem +": "Keine Skripte. Mit + hinzufügen",
  "Kroki: %s": "Schritte: %s",
  "Edytuj skrypt": "Skript bearbeiten",
  "Nowy skrypt": "Neues Skript",
  "Dodaj krok (%s/%s)": "Schritt hinzufügen (%s/%s)",
  "KROK %s": "SCHRITT %s",
  "WARUNEK (opcjonalnie)": "BEDINGUNG (optional)",
  "BODY TEMPLATE (opcjonalnie)": "BODY-TEMPLATE (optional)",
  "TYTUŁ": "TITEL",
  "TREŚĆ": "INHALT",
  "Wartość: {{pub.grid_v}}": "Wert: {{pub.grid_v}}",
  "DEVICE ID ODBIORCY": "EMPFÄNGER DEVICE-ID",
  "PAYLOAD (opc.)": "PAYLOAD (opt.)",
  "WYRAŻENIE": "AUSDRUCK",
  "ZAPISZ DO": "SPEICHERN NACH",
  "ZAPISZ DO (opc.)": "SPEICHERN NACH (opt.)",
  "JSON PATH (opc.)": "JSON-PFAD (opt.)",
  "ENCJA": "ENTITÄT",
  "FUNKCJA": "FUNKTION",
  "PRÓBKI": "PROBEN",

  // ── Akcje wiadomości / wiadomości ────────────────────────────
  "Usuń akcję": "Aktion löschen",
  "Brak akcji. Dodaj przyciskiem +": "Keine Aktionen. Mit + hinzufügen",
  "Automatyczne akcje wykonywane gdy node odbierze wiadomość o podanym ID (lub \"*\" dla wszystkich).":
      "Automatische Aktionen, wenn der Node eine Nachricht mit der angegebenen ID empfängt (oder \"*\" für alle).",
  "ID wiadomości triggera — \"alarm\", \"update\", \"*\" = wszystkie":
      "Trigger-Nachrichten-ID — \"alarm\", \"update\", \"*\" = alle",
  "powiadomienie na telefon (tytuł/treść; {{from}}, {{payload}})":
      "Benachrichtigung aufs Handy (Titel/Inhalt; {{from}}, {{payload}})",
  "URL do wywołania HTTP POST z payloadem wiadomości": "URL für HTTP POST mit dem Nachrichten-Payload",
  "Zapisz encje z payloadu jako {prefix}.entity_id na nodzie":
      "Payload-Entitäten als {prefix}.entity_id auf dem Node speichern",
  "ID skryptu do uruchomienia przy odebraniu wiadomości": "Skript-ID, die beim Empfang der Nachricht ausgeführt wird",
  "Edytuj akcję": "Aktion bearbeiten",
  "Nowa akcja": "Neue Aktion",
  "alarm, update, * (wszystkie)": "alarm, update, * (alle)",
  "POWIADOMIENIE": "BENACHRICHTIGUNG",
  "Tytuł — np. Od {from}": "Titel — z. B. Von {from}",
  "Treść — np. {message}": "Inhalt — z. B. {message}",
  "msg  →  zapisze jako msg.*": "msg  →  gespeichert als msg.*",
  "ID skryptu do uruchomienia": "Auszuführende Skript-ID",
  "Brak wiadomości w skrzynce.": "Keine Nachrichten im Posteingang.",
  "· %s nieprzeczytanych": "· %s ungelesen",
  "od: %s": "von: %s",
  "(brak payloadu)": "(kein Payload)",

  // ── Setup / Onboarding ───────────────────────────────────────
  "Włącz Bluetooth": "Bluetooth einschalten",
  "Wpisz nazwę sieci WiFi": "WLAN-Namen eingeben",
  "Łączenie przez BLE...": "Verbindung über BLE...",
  "Łączenie z nodem...": "Verbindung zum Node...",
  "Autoryzacja BLE...": "BLE-Autorisierung...",
  "Brak nonce — aktualizuj firmware": "Keine Nonce — Firmware aktualisieren",
  "Zły PIN — sprawdź kod ustawiony na urządzeniu": "Falsche PIN — prüfe den auf dem Gerät gesetzten Code",
  "Nie udało się połączyć z nodem przez Bluetooth. Upewnij się, że node jest w trybie konfiguracji (przytrzymaj przycisk ~3 s), podejdź bliżej i przełącz Bluetooth. Jeśli resetowałeś node — wróć do skanowania, bo ma teraz nową nazwę.": "Bluetooth-Verbindung zum Node fehlgeschlagen. Stelle sicher, dass der Node im Einrichtungsmodus ist (Taste ~3 s halten), geh näher heran und schalte Bluetooth aus/ein. Falls du den Node zurückgesetzt hast, geh zurück zum Scannen — er hat jetzt einen neuen Namen.",
  "Wpisz PIN urządzenia": "Geräte-PIN eingeben",
  "Autoryzacja nieudana": "Autorisierung fehlgeschlagen",
  "Sprawdzam portfel...": "Wallet wird geprüft...",
  "Odzyskiwanie portfela z noda...": "Wallet wird vom Node wiederhergestellt...",
  "Brak kopii na nodzie": "Keine Sicherung auf dem Node",
  "Tworzę nowy portfel...": "Neues Wallet wird erstellt...",
  "Podpisywanie challenge...": "Challenge wird signiert...",
  "Łączę z WiFi przez node...": "WLAN-Verbindung über den Node...",
  "Łączę z nodem przez sieć...": "Verbindung zum Node über das Netzwerk...",
  "Podłącz urządzenie": "Gerät verbinden",
  "Szukam...": "Suche...",
  "Znalezione urządzenia": "Gefundene Geräte",
  "Brak urządzeń.\nUpewnij się że node jest w trybie konfiguracji.":
      "Keine Geräte.\nStelle sicher, dass der Node im Konfigurationsmodus ist.",
  "Podaj dane WiFi": "WLAN-Zugangsdaten eingeben",
  "Nazwa sieci WiFi (SSID)": "WLAN-Name (SSID)",
  "Hasło WiFi": "WLAN-Passwort",
  "PIN noda (zapisany w urządzeniu)": "Node-PIN (im Gerät gespeichert)",
  "Konfiguruj": "Konfigurieren",
  "← Wróć do skanowania": "← Zurück zur Suche",
  // ── Odtwarzanie ID noda (po reflashu) ──
  "Odtwórz ID noda": "Node-ID wiederherstellen",
  "Ta płytka przejmie ID i historię wybranego noda offline (np. po reflashu).":
      "Dieses Board übernimmt ID und Verlauf des gewählten Offline-Nodes (z. B. nach einem Reflash).",
  "Odtwarzam poprzednie ID noda...": "Vorherige Node-ID wird wiederhergestellt...",
  "Ta płytka ma za stary firmware, żeby odtworzyć ID. Zaflashuj najnowszy firmware na sensmos.com/flash i spróbuj ponownie.":
      "Die Firmware dieses Boards ist zu alt, um eine ID wiederherzustellen. Flashe die neueste Firmware auf sensmos.com/flash und versuche es erneut.",
  "Ta płytka nie umie odtworzyć ID (firmware: %s). Zaflashuj najnowszy firmware na sensmos.com/flash i spróbuj ponownie.":
      "Dieses Board kann keine ID wiederherstellen (Firmware: %s). Flashe die neueste Firmware auf sensmos.com/flash und versuche es erneut.",
  "Usunięto nieaktywny wpis %s (node po reflashu)": "Inaktiven Eintrag %s entfernt (Node nach Reflash)",
  "Nie udało się zarejestrować noda": "Node-Registrierung fehlgeschlagen",
  "Urządzenie się resetuje — zaczekaj i spróbuj ponownie.": "Das Gerät startet neu — warte und versuche es erneut.",
  "Może potrwać do 30 sekund": "Kann bis zu 30 Sekunden dauern",
  "Gotowe!": "Fertig!",
  "Przejdź do panelu (%s)": "Zum Dashboard (%s)",
  "Przejdź do panelu": "Zum Dashboard",
  "Twoje urządzenia. Twoje dane. Twoja sieć.": "Deine Geräte. Deine Daten. Dein Netzwerk.",
  "Podłącz czujnik i monitoruj okolicę": "Sensor anschließen und die Umgebung überwachen",
  "Wymieniaj dane z sąsiadami": "Daten mit Nachbarn austauschen",
  "Alerty na telefon": "Alarme aufs Handy",
  "Połącz node": "Node verbinden",
  "Portfel powstaje przy pierwszym nodzie albo jest odzyskiwany z noda przez Bluetooth.":
      "Das Wallet wird mit dem ersten Node erstellt oder per Bluetooth vom Node wiederhergestellt.",

  // ── Ustawienia noda ──────────────────────────────────────────
  "Ustawienia noda": "Node-Einstellungen",
  "odebrane wiadomości na nodzie": "auf dem Node empfangene Nachrichten",
  "akcje na odebrane wiadomości (webhook, encje)": "Aktionen auf empfangene Nachrichten (Webhook, Entitäten)",
  "automatyzacje noda": "Node-Automatisierungen",
  "Lokalizacja": "Standort",
  "współrzędne noda": "Node-Koordinaten",
  "Lokalizacja noda": "Node-Standort",
  "Integracja (webhook)": "Integration (Webhook)",
  "URL wywoływany przy zdarzeniach noda": "URL, die bei Node-Ereignissen aufgerufen wird",
  "Zaufanie (trust)": "Vertrauen (Trust)",
  "ceremonia potwierdzająca fizyczne urządzenie": "Zeremonie zur Bestätigung des physischen Geräts",
  "Zmień PIN": "PIN ändern",
  "PIN dostępu do noda": "Zugriffs-PIN des Nodes",
  "Tryb serwisowy (Bluetooth)": "Servicemodus (Bluetooth)",
  "zmiana WiFi / odzyskiwanie portfela": "WLAN ändern / Wallet wiederherstellen",
  "Usuń node z listy": "Node von der Liste entfernen",
  "Usuwa node tylko z tej apki": "Entfernt den Node nur aus dieser App",
  "Usuń node z sieci (permanentnie)": "Node aus dem Netzwerk löschen (dauerhaft)",
  "Kasuje node i wszystkie jego dane z SENSMOS. Możesz go później dodać ponownie (onboarding przez Bluetooth). Zarobione GALU zostają na Twoim wallecie.":
      "Löscht den Node und alle seine Daten aus SENSMOS. Du kannst ihn später wieder hinzufügen (Bluetooth-Onboarding). Verdiente GALU bleiben in deinem Wallet.",
  "Usunąć node z sieci?": "Node aus dem Netzwerk löschen?",
  "Node %s i WSZYSTKIE jego dane zostaną trwale usunięte z SENSMOS. Możesz go później dodać ponownie (onboarding przez Bluetooth). Zarobione GALU pozostają na Twoim wallecie.":
      "Node %s und ALLE seine Daten werden dauerhaft aus SENSMOS gelöscht. Du kannst ihn später wieder hinzufügen (Bluetooth-Onboarding). Verdiente GALU bleiben in deinem Wallet.",
  "Usuń permanentnie": "Dauerhaft löschen",
  "Node usunięty z sieci": "Node aus dem Netzwerk gelöscht",
  "Błąd usuwania: %s": "Löschfehler: %s",
  "Brak walleta": "Kein Wallet",
  "Importujesz INNY portfel (%s) niż obecny (%s).\n\nTwoje nody pozostaną przypisane do obecnego portfela, dopóki nie dodasz ich ponownie przez Bluetooth (to zmieni właściciela i wymaga ponownej weryfikacji — bez resetu urządzenia). Zarobione GALU zostają przy portfelu, który je zarobił.":
      "Du importierst ein ANDERES Wallet (%s) als das aktuelle (%s).\n\nDeine Nodes bleiben dem aktuellen Wallet zugeordnet, bis du sie erneut über Bluetooth hinzufügst (das ändert den Besitzer und erfordert eine erneute Verifizierung — ohne Geräte-Reset). Verdiente GALU bleiben bei dem Wallet, das sie verdient hat.",

  "Moje nody w sieci": "Meine Nodes im Netzwerk",
  "Wszystkie nody zarejestrowane na Twój wallet (wg SENSMOS)": "Alle auf dein Wallet registrierten Nodes (laut SENSMOS)",
  "brak w tej apce": "nicht in dieser App",
  "nieaktywny": "inaktiv",
  "ID skopiowane: %s": "ID kopiert: %s",
  "Kopiuj ID noda": "Node-ID kopieren",
  "Kopiuj ID": "ID kopieren",
  "Importuj klucz prywatny": "Privaten Schlüssel importieren",
  "Importuj portfel": "Wallet importieren",
  "Monitoruj sieć i internet": "Netzwerk und Internet überwachen",
  "Korzystałeś już z SENSMOS?": "Hast du SENSMOS schon genutzt?",
  "Wyszukaj moje nody w sieci WiFi": "Meine Nodes im WLAN suchen",
  "Wyszukaj moje nody": "Meine Nodes suchen",
  "Node dodany": "Node hinzugefügt",
  "Zły PIN": "Falsche PIN",
  "Szukam noda...": "Node wird gesucht...",
  "Sprawdzam PIN...": "PIN wird geprüft...",
  "Wpisz IP noda — PIN podasz, gdy urządzenie się odnajdzie.": "Gib die Node-IP ein — die PIN folgt, sobald das Gerät gefunden ist.",
  "brak portfela": "kein Wallet",
  "Aplikacja nie ma przypisanego portfela": "Der App ist kein Wallet zugeordnet",
  "Zaimportuj go z klucza (zakladka Portfel) lub z noda (rozwin swoj node ponizej -> Importuj portfel z noda).":
      "Importiere es aus einem Schlüssel (Tab Wallet) oder von einem Node (Node unten aufklappen -> Wallet vom Node importieren).",
  "import z klucza": "Import aus Schlüssel",
  "Klucz portfela (zaawansowane)": "Wallet-Schlüssel (fortgeschritten)",
  "Usunąć z tej apki?": "Aus dieser App entfernen?",
  "Node zniknie tylko z tego telefonu - pozostaje w sieci i nalicza nagrody. Aby usunac go z sieci, uzyj Usun z sieci.":
      "Der Node verschwindet nur von diesem Handy — er bleibt im Netzwerk und sammelt Belohnungen. Zum Entfernen aus dem Netzwerk nutze Aus dem Netzwerk löschen.",
  "Usuń z apki": "Aus der App entfernen",
  "import / eksport klucza prywatnego": "Import / Export des privaten Schlüssels",
  "Brak portfela w apce. Odzyskaj kopię zapisaną na tym nodzie.": "Kein Wallet in der App. Stelle die auf diesem Node gespeicherte Kopie wieder her.",
  "Importuj portfel z noda": "Wallet vom Node importieren",
  "Dodaj node": "Node hinzufügen",
  "tworzy nowy portfel": "erstellt ein neues Wallet",
  "masz już portfel (np. w MetaMask)? odzyskaj dostęp do swoich nodów": "hast du schon ein Wallet (z. B. MetaMask)? Stelle den Zugriff auf deine Nodes wieder her",
  "wklej klucz z MetaMask (0x… lub 64 hex)": "Schlüssel aus MetaMask einfügen (0x… oder 64 Hex)",
  "Wklej klucz prywatny (np. z MetaMask). Rób to tylko na swoim telefonie.": "Füge einen privaten Schlüssel ein (z. B. aus MetaMask). Nur auf deinem eigenen Handy tun.",
  "Importuj": "Importieren",
  "Nieprawidłowy klucz prywatny": "Ungültiger privater Schlüssel",
  "Inny portfel": "Anderes Wallet",
  "Zaimportuj mimo to": "Trotzdem importieren",
  "Portfel zaimportowany — Twoje nody działają dalej": "Wallet importiert — deine Nodes laufen weiter",
  "Portfel zaimportowany: %s": "Wallet importiert: %s",
  "Błąd importu: %s": "Importfehler: %s",
  "Odebrano nagrody": "Belohnungen abgeholt",
  "Wszystko już odebrane": "Alles bereits abgeholt",
  "Usunąć \"%s\"?": "\"%s\" löschen?",
  "Usunąć akcję dla \"%s\"?": "Aktion für \"%s\" löschen?",
  "Usuń z sieci": "Aus dem Netzwerk löschen",
  "Trwale usuwa node z Twoich urządzeń": "Entfernt den Node dauerhaft aus deinen Geräten",
  "Node POST-uje tu zdarzenia (message_received, batch_sent, sub_received, ws_connected). Puste = wyłączone.":
      "Der Node POSTet hier Ereignisse (message_received, batch_sent, sub_received, ws_connected). Leer = deaktiviert.",
  "Integracja wyłączona": "Integration deaktiviert",
  "Webhook zapisany": "Webhook gespeichert",
  "Nowy PIN (min. 4 cyfry)": "Neue PIN (mind. 4 Ziffern)",
  "PIN zmieniony": "PIN geändert",

  // ── Lokalizacja noda (GPS) ───────────────────────────────────
  "Włącz lokalizację (GPS) w telefonie": "Standort (GPS) am Handy einschalten",
  "Brak zgody na lokalizację": "Standortberechtigung verweigert",
  "Pozycja GPS pobrana ✓": "GPS-Position erfasst ✓",
  "Błąd GPS: %s": "GPS-Fehler: %s",
  "Najpierw pobierz pozycję GPS": "Zuerst die GPS-Position abrufen",
  "Lokalizacja potwierdzona i zapisana": "Standort bestätigt und gespeichert",
  "Stań przy nodzie i pobierz pozycję GPS — to potwierdza, że node jest naprawdę tutaj. Miasto uzupełni się samo.":
      "Stell dich neben den Node und rufe die GPS-Position ab — das bestätigt, dass der Node wirklich hier ist. Die Stadt wird automatisch ergänzt.",
  "Pobierz GPS ponownie": "GPS erneut abrufen",
  "Pobierz moją pozycję (GPS)": "Meine Position abrufen (GPS)",
  "POZYCJA GPS": "GPS-POSITION",
  "dokładność ±%s m": "Genauigkeit ±%s m",
  "Brak pozycji — naciśnij przycisk powyżej.": "Keine Position — tippe auf den Button oben.",
  "Rozmycie prywatności": "Privatsphäre-Unschärfe",
  "Na mapie ~200–800 m od prawdziwej pozycji (losowo)": "Auf der Karte ~200–800 m von der echten Position (zufällig)",
  "Na mapie dokładny adres noda": "Exakte Node-Adresse auf der Karte",
  "Zapisz lokalizację": "Standort speichern",

  // ── Node manager / lista nodów ───────────────────────────────
  "Dodaj": "Hinzufügen",
  "Szukaj": "Suchen",
  "Ręcznie": "Manuell",
  "Jak dodać node?": "Wie füge ich einen Node hinzu?",
  "ESP32 musi być włączony i w trybie konfiguracji (świeci LED)":
      "Der ESP32 muss eingeschaltet und im Konfigurationsmodus sein (LED leuchtet)",
  "Bluetooth musi być włączony na telefonie": "Bluetooth muss am Handy aktiviert sein",
  "Telefon musi być połączony z siecią WiFi z dostępem do internetu":
      "Das Handy muss mit einem WLAN mit Internetzugang verbunden sein",
  "WiFi do której podłączysz node musi być w zasięgu": "Das WLAN für den Node muss in Reichweite sein",
  "Przygotuj nazwę sieci (SSID) i hasło WiFi": "Halte WLAN-Namen (SSID) und Passwort bereit",
  "Dodaj nowy node przez BLE": "Neuen Node über BLE hinzufügen",
  "Szuka nodów SENSMOS w sieci WiFi.": "Sucht SENSMOS-Nodes im WLAN.",
  "Szukaj w sieci": "Im Netzwerk suchen",
  "Nie znaleziono nodów w sieci.": "Keine Nodes im Netzwerk gefunden.",
  "Dodany": "Hinzugefügt",
  "Wpisz IP i PIN gdy znasz adres noda.": "Gib IP und PIN ein, wenn du die Node-Adresse kennst.",
  "Adres IP noda": "Node-IP-Adresse",
  "Połącz i dodaj": "Verbinden und hinzufügen",
  "Wpisz adres IP": "IP-Adresse eingeben",
  "Brak odpowiedzi z %s.": "Keine Antwort von %s.",
  "Dodaję...": "Wird hinzugefügt...",
  "Panel": "Dashboard",
  "Odśwież": "Aktualisieren",
  "GALU saldo": "GALU-Guthaben",
  "Sąsiedzi": "Nachbarn",
  "Promień": "Radius",
  "Node niedostępny": "Node nicht erreichbar",
  "Brak nodów": "Keine Nodes",
  "Dodaj node przez BLE": "Node über BLE hinzufügen",

  // ── Zaufanie (trust) / tryb serwisowy ────────────────────────
  "Zaufanie noda": "Node-Vertrauen",
  "Brak portfela": "Kein Wallet",
  "Przełączam node w tryb Bluetooth…": "Node wird in den Bluetooth-Modus geschaltet…",
  "Node nie odpowiada: %s": "Node antwortet nicht: %s",
  "Node restartuje się — szukam przez Bluetooth…": "Node startet neu — Suche über Bluetooth…",
  "Nie znalazłem noda przez Bluetooth.\nNode wróci sam do WiFi w ciągu 5 minut.":
      "Node über Bluetooth nicht gefunden.\nEr kehrt innerhalb von 5 Minuten selbst ins WLAN zurück.",
  "Połączono — przeprowadzam ceremonię…": "Verbunden — Zeremonie läuft…",
  "Autoryzacja BLE nieudana (PIN?)": "BLE-Autorisierung fehlgeschlagen (PIN?)",
  "Backend niedostępny — brak seedu ceremonii": "Backend nicht erreichbar — kein Zeremonie-Seed",
  "Rundy challenge (%s)…": "Challenge-Runden (%s)…",
  "Weryfikacja w sieci…": "Verifizierung im Netzwerk…",
  "Weryfikacja odrzucona: %s": "Verifizierung abgelehnt: %s",
  "Node zaufany — wraca do WiFi.": "Node vertrauenswürdig — kehrt ins WLAN zurück.",
  "Powtórz ceremonię": "Zeremonie wiederholen",
  "Przeprowadź ceremonię": "Zeremonie durchführen",
  "Ceremonia zakończona — node zaufany.": "Zeremonie abgeschlossen — Node vertrauenswürdig.",
  "Node zaufany": "Node vertrauenswürdig",
  "Node niezweryfikowany": "Node nicht verifiziert",
  "Ceremonia: %s": "Zeremonie: %s",
  "Przeprowadź ceremonię, aby potwierdzić,\nże to fizyczne urządzenie.":
      "Führe die Zeremonie durch, um zu bestätigen,\ndass dies ein physisches Gerät ist.",
  "Node restartuje się w tryb Bluetooth (zostaw go włączonego).":
      "Der Node startet in den Bluetooth-Modus neu (eingeschaltet lassen).",
  "Telefon łączy się i wykonuje szybkie rundy challenge — dowód, że urządzenie jest fizycznie obok.":
      "Das Handy verbindet sich und führt schnelle Challenge-Runden aus — Beweis, dass das Gerät physisch in der Nähe ist.",
  "Node podpisuje atest swoim kluczem, Ty podpisujesz portfelem.":
      "Der Node signiert die Attestierung mit seinem Schlüssel, du signierst mit dem Wallet.",
  "Sieć weryfikuje oba podpisy i oznacza node jako zaufany. Node sam wraca do WiFi.":
      "Das Netzwerk prüft beide Signaturen und markiert den Node als vertrauenswürdig. Der Node kehrt selbst ins WLAN zurück.",
  "Tryb serwisowy": "Servicemodus",
  "Node nieosiągalny po sieci — przytrzymaj przycisk na nodzie 3 s, aż wejdzie w tryb Bluetooth…":
      "Node über das Netzwerk nicht erreichbar — halte die Taste am Node 3 s, bis er in den Bluetooth-Modus wechselt…",
  "Nie znalazłem noda przez Bluetooth.\nUpewnij się, że jest w trybie serwisowym (przycisk 3 s).":
      "Node über Bluetooth nicht gefunden.\nStelle sicher, dass er im Servicemodus ist (Taste 3 s).",
  "Zapisuję WiFi…": "WLAN wird gespeichert…",
  "WiFi zapisane — node restartuje się i łączy z siecią.": "WLAN gespeichert — der Node startet neu und verbindet sich.",
  "Pobieram kopię z noda…": "Sicherung wird vom Node geladen…",
  "Ten node nie ma kopii portfela": "Dieser Node hat keine Wallet-Sicherung",
  "Brak kopii": "Keine Sicherung",
  "Portfel odzyskany: %s": "Wallet wiederhergestellt: %s",
  "Wejdź w tryb serwisowy": "In den Servicemodus wechseln",
  "Zmień sieć WiFi": "WLAN-Netzwerk ändern",
  "wpisz nowe SSID i hasło — node przełączy się": "neues SSID und Passwort eingeben — der Node wechselt",
  "Odzyskaj portfel z noda": "Wallet vom Node wiederherstellen",
  "pobierz kopię portfela na ten telefon": "Wallet-Sicherung auf dieses Handy laden",
  "Po co tryb serwisowy?": "Wozu der Servicemodus?",
  "Zmiana WiFi i odzyskiwanie portfela działają tylko przez Bluetooth (bliskość fizyczna). Node przejdzie w tryb BLE — jeśli jest nieosiągalny po sieci, przytrzymaj przycisk na nodzie ok. 3 s.":
      "WLAN-Wechsel und Wallet-Wiederherstellung funktionieren nur über Bluetooth (physische Nähe). Der Node wechselt in den BLE-Modus — ist er über das Netzwerk nicht erreichbar, halte die Taste am Node ca. 3 s.",
  "Nowa sieć WiFi": "Neues WLAN-Netzwerk",
  "Nazwa sieci (SSID)": "Netzwerkname (SSID)",
  "Hasło": "Passwort",

  // ── Powiadomienia / Ustawienia / Encje / Lokalizacje / Ranking ─
  "Zapisano na %s/%s nodach": "Auf %s/%s Nodes gespeichert",
  "Powiadomienia": "Benachrichtigungen",
  "TOKEN PUSH (FCM)": "PUSH-TOKEN (FCM)",
  "wklej token FCM…": "FCM-Token einfügen…",
  "Włącz na nodach": "Auf Nodes aktivieren",
  "Wyłącz": "Deaktivieren",
  "STAN NA NODACH": "STATUS AUF DEN NODES",
  "włączone · %s…": "aktiviert · %s…",
  "wyłączone": "deaktiviert",
  "Token FCM jest pobierany automatycznie i rozsyłany na nody przy starcie aplikacji. To pole pokazuje aktualny token — możesz go też ręcznie wymusić na nodach. Node przekazuje go do backendu, który wysyła powiadomienia.":
      "Der FCM-Token wird automatisch geholt und beim App-Start an die Nodes verteilt. Dieses Feld zeigt den aktuellen Token — du kannst ihn auch manuell auf die Nodes erzwingen. Der Node leitet ihn ans Backend weiter, das die Benachrichtigungen sendet.",
  "Lokalizacja nodów": "Node-Standorte",
  "współrzędne wszystkich urządzeń": "Koordinaten aller Geräte",
  "token push, włącz/wyłącz na nodach": "Push-Token, auf Nodes ein-/ausschalten",
  "Aplikacja": "App",
  "Wersja": "Version",
  "Brak encji": "Keine Entitäten",
  "Publiczne": "Öffentlich",
  "Własne": "Eigene",
  "Zewnętrzne": "Extern",
  "Wiek: %s": "Alter: %s",
  "lokalna": "lokal",
  "Brak zapisanych nodów": "Keine gespeicherten Nodes",
  "Ustaw współrzędne każdego noda osobno — pozycja na mapie sieci i regiony scoringu.":
      "Setze die Koordinaten jedes Nodes einzeln — Position auf der Netzwerkkarte und Scoring-Regionen.",
  "Ranking miast": "Städte-Ranking",
  "%s nodów · %s online": "%s Nodes · %s online",

  // ── Pasek nawigacji / powiadomienia ──────────────────────────
  "Nowe powiadomienie\nsprawdź skrzynkę noda": "Neue Benachrichtigung\nprüfe den Node-Posteingang",

  // ── Komunikaty z serwisów (wyjątki → snackbar) ───────────────
  "Brak usługi SENSMOS": "SENSMOS-Dienst nicht gefunden",
  "Nie połączono": "Nicht verbunden",
  "Node nie pojawił się w sieci.\nSprawdź SSID i hasło WiFi.":
      "Der Node ist nicht im Netzwerk erschienen.\nPrüfe SSID und WLAN-Passwort.",
  "Błędny PIN lub uszkodzona kopia": "Falsche PIN oder beschädigte Sicherung",

  // ── Lokalizacja / weryfikacja / prywatność ───────────────────
  "Lokalizacja i weryfikacja": "Standort & Verifizierung",
  "ceremonia BLE + GPS — ustawia pozycję i potwierdza urządzenie":
      "BLE-+-GPS-Zeremonie — setzt die Position und verifiziert das Gerät",
  "PRYWATNOŚĆ": "PRIVATSPHÄRE",
  "Na mapie ~200–800 m od prawdziwej pozycji (losowo).":
      "Auf der Karte ~200–800 m von der echten Position (zufällig).",
  "Na mapie dokładny adres noda.": "Exakte Node-Adresse auf der Karte.",
  "Rozmycie włączone — na mapie ~200–800 m od pozycji":
      "Unschärfe an — auf der Karte ~200–800 m von der Position",
  "Rozmycie wyłączone — na mapie dokładny adres":
      "Unschärfe aus — exakte Adresse auf der Karte",
  "Najpierw ustaw lokalizację (ceremonia powyżej).":
      "Setze zuerst den Standort (Zeremonie oben).",
  "Wymaga firmware 0.27+ — zaktualizuj node.":
      "Erfordert Firmware 0.27+ — aktualisiere den Node.",
  "Wymaga firmware 0.25+ — zaktualizuj node.":
      "Erfordert Firmware 0.25+ — aktualisiere den Node.",
  "Tryb prywatny (ghost)": "Privater Modus (Ghost)",
  "Ukryty z mapy, 0 nagród. Dane działają lokalnie; za subskrypcje płacisz.":
      "Von der Karte verborgen, 0 Belohnungen. Daten funktionieren lokal; Abos kosten weiterhin.",
  "Tryb prywatny włączony — node ukryty z mapy i nagród":
      "Privater Modus an — Node von Karte und Belohnungen ausgeblendet",
  "Tryb prywatny wyłączony": "Privater Modus aus",
  "Pobieram pozycję GPS...": "GPS-Position wird abgerufen...",
  "Zaraz poprosimy o lokalizację (GPS) — potwierdza, że node jest fizycznie tutaj. Bez niej node działa, ale zarabia znacznie mniej.":
      "Gleich fragen wir nach dem Standort (GPS) — er bestätigt, dass der Node physisch hier ist. Ohne ihn läuft der Node, verdient aber deutlich weniger.",
  "Brak lokalizacji — node niewidoczny na mapie i nie nalicza nagród.":
      "Kein Standort — Node nicht auf der Karte sichtbar und sammelt keine Belohnungen.",
  "Ustaw lokalizację": "Standort festlegen",
  "Połącz się z siecią noda, aby ustawić lokalizację.":
      "Verbinde dich mit dem Netzwerk des Nodes, um den Standort festzulegen.",
  "Połącz się z siecią WiFi noda, aby zobaczyć encje i zmienić ustawienia.":
      "Verbinde dich mit dem WLAN des Nodes, um Entitäten zu sehen und Einstellungen zu ändern.",

  // ── Widok noda: chmura vs sieć lokalna ───────────────────────
  "raportuje": "meldet",
  "Raportują": "Melden",
  "cisza": "still",
  "brak danych z chmury": "keine Cloud-Daten",
  "W sieci": "Im Netzwerk",
  "Zdalnie": "Remote",
  "przed chwilą": "gerade eben",
};
