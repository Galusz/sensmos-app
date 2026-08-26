import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n_pt.dart';

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
      'pl' || 'en' || 'de' || 'pt' => _mode,
      _ => switch (PlatformDispatcher.instance.locale.languageCode) {
             'pl' => 'pl',
             'de' => 'de',
             'pt' => 'pt',
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

const Map<String, Map<String, String>> _langMaps = {'en': _enMap, 'de': _deMap, 'pt': ptMap};

String tr(String pl, [List<Object?> args = const []]) {
  var s = L10n.lang == 'pl' ? pl : (_langMaps[L10n.lang]?[pl] ?? _enMap[pl] ?? pl);
  for (final a in args) {
    s = s.replaceFirst('%s', '$a');
  }
  return s;
}

/// Nadpisania angielskie. Brak wpisu → pokazujemy klucz (PL).
const Map<String, String> _enMap = {
  // ── RemoteTerminal / Panel (auto) ──
  "Łączę z relayem…": "Connecting to relay…",
  "Brak portfela w apce": "No wallet in the app",
  "Node jest offline — nie połączysz się z nim, dopóki nie wróci do sieci.": "Node is offline — you can't connect until it's back online.",
  "Remote access WŁĄCZONY — ten node będzie rzadziej wybierany do monitorów": "Remote access ON — this node will be chosen less often for monitors",
  "Otwieram tunel → %s:%s…": "Opening tunnel → %s:%s…",
  "Sesja zakończona": "Session ended",
  "Rozłączono": "Disconnected",
  "Terminal": "Terminal",
  "Rozłącz": "Disconnect",
  "Remote access na nodzie": "Remote access on the node",
  "Pozwala łączyć się z urządzeniami w sieci noda. Włączony node jest rzadziej wybierany do monitorów.": "Lets you connect to devices on the node's network. An enabled node is chosen less often for monitors.",
  "Host w sieci noda": "Host on the node's network",
  "Port": "Port",
  "Użytkownik SSH": "SSH user",
  "Hasło SSH": "SSH password",
  "SSH jest szyfrowany end-to-end — node i nasze serwery przekazują tylko zaszyfrowane bajty.": "SSH is end-to-end encrypted — the node and our servers only relay encrypted bytes.",
  "Połącz": "Connect",
  "Najpierw włącz remote access powyżej.": "Enable remote access above first.",
  "Podaj PIN noda": "Enter node PIN",
  "Integracje": "Integrations",
  "Dodaj integrację": "Add integration",
  "Odpiąć integrację?": "Remove integration?",
  "Odepnij": "Remove",
  "Wymaga FW > 0.70": "Requires FW > 0.70",
  "Wszystko już podpięte": "Everything already added",
  "Usuń node z sieci": "Remove node from network",
  "Integracje wymagają noda online (połączonego z chmurą).": "Integrations require the node online (connected to the cloud).",
  "Panel HA": "HA Panel",
  "Ustawienia HA": "HA settings",
  "Home Assistant": "Home Assistant",
  "Host HA (IP w sieci noda)": "HA host (IP on node's network)",
  "Long-lived token": "Long-lived token",
  "Podaj host i token": "Enter host and token",
  "Podłącz HA w sieci noda przez tunel. Użyj wewnętrznego adresu HTTP (np. 192.168.1.10:8123) — tunel i tak szyfruje.": "Connect to HA on the node's network via the tunnel. Use the internal HTTP address (e.g. 192.168.1.10:8123) — the tunnel encrypts anyway.",
  "Token wygenerujesz w HA: Profil → Long-Lived Access Tokens.": "Generate the token in HA: Profile → Long-Lived Access Tokens.",
  "Usuń integrację": "Remove integration",
  "Pokaż": "Show",
  "Ukryj": "Hide",
  "Łączę z HA…": "Connecting to HA…",
  "Node jest offline — wróci gdy odzyska sieć.": "Node is offline — it'll return once it regains network.",
  "HA nie odpowiada — sprawdź adres i token": "HA not responding — check address and token",
  "Pusty dashboard": "Empty dashboard",
  "Dodaj kafelek": "Add tile",
  "Nie udało się pobrać encji": "Couldn't fetch entities",
  "Szukaj encji…": "Search entities…",
  "Nazwa kafelka": "Tile name",
  "Odśwież encje z HA": "Refresh entities from HA",
  "Zły PIN — remote access nie włączony": "Wrong PIN — remote access not enabled",
  "Remote access wyłączony": "Remote access off",
  "Połączenie zerwane — dotknij „Spróbuj ponownie\".": "Connection lost — tap \"Try again\".",
  "Spróbuj ponownie": "Try again",
  "W tej sieci": "On this network",
  "Zdalny terminal": "Remote terminal",
  "Dostępne zawsze": "Always available",
  "Terminal wymaga noda online (połączonego z chmurą).": "Terminal requires the node to be online (connected to the cloud).",
  "Sieć lokalna (tylko w sieci noda)": "Local network (only on the node's network)",
  "Ustaw lokalizację (BLE + GPS)": "Set location (BLE + GPS)",
  "Połącz telefon z siecią WiFi noda, żeby zobaczyć encje i zmienić ustawienia.": "Connect your phone to the node's WiFi to see entities and change settings.",
  "Ten node nie jest dodany lokalnie — połącz się z jego siecią i dodaj go, by konfigurować.": "This node isn't added locally — connect to its network and add it to configure it.",
  "Online": "Online",
  "Z lokalizacją": "With location",
  "online": "online",
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
  "POL (gas)": "POL (gas)",
  "Za mało POL — transakcje (claim/deposit) wymagają gazu. Wpłać POL na adres portfela (QR powyżej).":
      "Not enough POL — transactions (claim/deposit) require gas. Send POL to your wallet address (QR above).",
  "Za mało POL — odbiór nagród (claim) wymaga gazu. Wpłać POL na adres portfela (QR powyżej).":
      "Not enough POL — claiming rewards requires gas. Send POL to your wallet address (QR above).",
  "Eksportuj klucz (MetaMask)": "Export key (MetaMask)",
  "wymaga PIN-u dowolnego Twojego noda": "requires the PIN of any of your nodes",
  "Dostępne: %s (MAX)": "Available: %s (MAX)",
  "Odblokuj": "Unlock",
  "Klucz prywatny": "Private key",
  "⚠️ Nigdy nikomu nie pokazuj tego klucza. Kto go ma, kontroluje portfel i wszystkie GALU.":
      "⚠️ Never show this key to anyone. Whoever has it controls the wallet and all GALU.",
  "MetaMask → Importuj konto → Private Key → wklej.": "MetaMask → Import account → Private Key → paste.",
  "Klucz skopiowany": "Key copied",
  "Odbiór POL / GALU": "Receive POL / GALU",
  "Wyślij POL na ten adres (gas na transakcje)": "Send POL to this address (gas for transactions)",
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
  "Lokalizacja (GPS) jest wyłączona — na Androidzie 11 i starszych jest wymagana do skanowania Bluetooth.":
      "Location (GPS) is off — on Android 11 and older it is required for Bluetooth scanning.",
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
  // „Pokrycie" = mnożnik geograficzny (dawniej „Scarcity"): im dalej najbliższy sąsiad,
  // tym wyżej. Trzymać przy „Sąsiedzi"/„Promień" — to jeden wiersz statystyk na karcie noda.
  "Pokrycie": "Coverage",
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
  "Telemetria": "Telemetry",
  "Radio LoRa": "LoRa radio",
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
  "Node jest skonfigurowany i zarejestrowany, ale apka nie widzi go w tej sieci WiFi.\nTelefon jest prawdopodobnie w innej sieci niż node. Połącz telefon z tą samą siecią WiFi i dodaj node ręcznie (Szukaj nodów w sieci).":
      "The node is set up and registered, but the app can't see it on this WiFi network.\nYour phone is probably on a different network than the node. Connect the phone to the same WiFi and add the node manually (Search for nodes).",
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
  "Tryb prywatny włączony — node ukryty z mapy":
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
  "Usuń z listy":
      "Remove from list",
  "Usunąć z aplikacji?":
      "Remove from the app?",
  "Node %s zniknie z tej listy. W sieci SENSMOS zostaje bez zmian — nie należy do Twojego portfela, więc nie możesz go stamtąd usunąć.":
      "Node %s will disappear from this list. It stays unchanged in the SENSMOS network — it does not belong to your wallet, so you cannot remove it from there.",
  "Usuń z aplikacji":
      "Remove from app",
  "Usunięto z aplikacji: %s":
      "Removed from the app: %s",
  "Zastąpić portfel w aplikacji?":
      "Replace the wallet in the app?",
  "W aplikacji jest już inny portfel. Odzysk go NADPISZE.":
      "The app already holds a different wallet. Restoring will OVERWRITE it.",
  "Obecny w aplikacji:":
      "Currently in the app:",
  "Kopia na nodzie:":
      "Backup on the node:",
  "Jeśli obecny portfel nie został nigdzie wyeksportowany, stracisz do niego dostęp razem ze środkami. Klucza nie da się odtworzyć.":
      "If the current wallet has not been exported anywhere, you will lose access to it and to its funds. The key cannot be recreated.",
  "Nadpisz":
      "Overwrite",
  "Sprawdzam kopię na nodzie…":
      "Checking the backup on the node…",
  "Na nodzie jest kopia TEGO SAMEGO portfela — nic nie zmieniam.":
      "The node holds a backup of THE SAME wallet — nothing changed.",
  "Pełne ID":
      "Full ID",
  "Adres IP":
      "IP address",
  "Skopiowano %s":
      "Copied %s",
  "Pod tym adresem jest inny node (%s) — ta płytka została przeflashowana i ma nową tożsamość.":
      "A different node is at this address (%s) — this board was reflashed and has a new identity.",
  "Ten node nie ma zapisanego adresu IP — apka zna go tylko z chmury. Połącz telefon z siecią noda i wyszukaj go lokalnie.":
      "This node has no saved IP address — the app only knows it from the cloud. Connect your phone to the node's network and search for it locally.",
  "Wyszukaj noda w tej sieci":
      "Search for the node on this network",
  "Szukam w sieci...":
      "Searching the network...",
  "Nie znaleziono noda w tej sieci. Upewnij się, że telefon jest w tej samej sieci WiFi co node.":
      "Node not found on this network. Make sure your phone is on the same WiFi network as the node.",
  "Node znaleziony: %s":
      "Node found: %s",
  "Rozmyj dokładną pozycję":
      "Blur the exact position",
  "Na mapie pokazujemy punkt przesunięty o 200-800 m. Wyłącz tylko, jeśli chcesz publikować dokładny adres.":
      "On the map we show a point shifted by 200-800 m. Turn this off only if you want to publish the exact address.",
  "Node w ogóle nie pojawi się na mapie. Zarabia mniej, bo nie współtworzy publicznego pokrycia sieci.":
      "The node will not appear on the map at all. It earns less because it does not contribute to the network's public coverage.",
  "Tryb prywatny — node nie jest pokazywany na mapie i zarabia w obniżonej stawce, bo nie współtworzy publicznego pokrycia sieci.":
      "Private mode — the node is not shown on the map and earns at a reduced rate, because it does not contribute to the network's public coverage.",
  "Brak potwierdzonej lokalizacji GPS — ten node prawie nie zarabia. Podejdź do niego z telefonem i ustaw lokalizację.":
      "No confirmed GPS location — this node earns almost nothing. Walk up to it with your phone and set the location.",
  "Sprawdzam połączenie...":
      "Checking connection...",
  "Nie można zarejestrować noda — aplikacja nie ma połączenia z internetem. Telefon musi być online przez cały czas rejestracji. Połącz się z siecią i spróbuj ponownie.":
      "Cannot register the node — the app has no internet connection. Your phone must stay online for the whole registration. Connect to a network and try again.",
  "Utracono połączenie z internetem — nie udało się zarejestrować noda. Telefon musi być online przez cały czas rejestracji.":
      "Internet connection lost — the node could not be registered. Your phone must stay online for the whole registration.",
  "Serwer odrzucił rejestrację noda.":
      "The server rejected the node registration.",
  "Node dodany, ale weryfikacja się nie powiodła — bez niej nie nalicza nagród. Powtórz ceremonię w ustawieniach noda (Zaufanie).":
      "Node added, but verification failed — without it the node earns nothing. Repeat the ceremony in the node settings (Trust).",
  // ── Panel HA: typy kafelków + akcje ──
  "Typ kafelka": "Tile type",
  "Wykres": "Chart",
  "Odczyt": "Reading",
  "Przełącznik": "Switch",
  "Światło": "Light",
  "Przycisk": "Button",
  "Uruchom": "Run",
  "uruchomiono": "started",
  "Nie udało się uruchomić": "Couldn't run it",
  "brak historii": "no history",
  "Gotowe": "Done",
  "OK": "OK",
  "Nagrody naliczają się po ok. 4 godzinach online w danej dobie — zero na starcie jest normalne.":
      "Rewards start after roughly 4 hours online within a day — zero at first is normal.",

  // ── Parowanie noda (klucz w telefonie, kanał wyłącznie po LAN) ──
  "Zdalny dostęp": "Remote access",
  "Zapamiętaj hasło na tym telefonie": "Remember the password on this phone",
  "sparowany — terminal i panel HA działają z dowolnego miejsca":
      "paired — terminal and HA panel work from anywhere",
  "NIESPAROWANY — sparuj teraz, będąc w sieci noda":
      "NOT PAIRED — pair now, while you're on the node's network",
  "Sparuj": "Pair",
  "Sparuj node": "Pair node",
  "Node sparowany.": "Node paired.",
  "Node sparowany — możesz się połączyć.": "Node paired — you can connect now.",
  "Node niesparowany": "Node not paired",
  "Najpierw sparuj node powyżej.": "Pair the node above first.",
  "Nie znam tego noda na tym telefonie.": "This phone doesn't know that node.",
  "Zdalny dostęp wymaga jednorazowego sparowania w tej samej sieci WiFi co node.":
      "Remote access needs a one-time pairing on the same Wi-Fi network as the node.",
  "Zdalny dostęp wymaga jednorazowego sparowania: telefon zapisze w nodzie tajny klucz, którego nasz serwer nigdy nie zobaczy. Bez niego nikt — łącznie z nami — nie otworzy tunelu do Twojej sieci.\n\nMusisz być teraz w tej samej sieci WiFi co node.":
      "Remote access needs a one-time pairing: your phone stores a secret key on the node that our server never sees. Without it nobody — us included — can open a tunnel into your network.\n\nYou need to be on the same Wi-Fi network as the node right now.",
  "Wyłączyć zdalny dostęp?": "Turn off remote access?",
  "Node skasuje wszystkie klucze — terminal i panel HA przestaną działać ze WSZYSTKICH telefonów, także innych domowników. Ponowne włączenie wymaga bycia w sieci noda.":
      "The node will erase every key — the terminal and the HA panel will stop working on ALL phones, including other people in your home. Turning it back on requires being on the node's network.",
  "Zdalny dostęp wyłączony.": "Remote access turned off.",
  "Zły PIN noda.": "Wrong node PIN.",
  "Nie widzę noda w tej sieci — połącz telefon z tym samym WiFi co node.":
      "Can't see the node on this network — connect your phone to the same Wi-Fi as the node.",
  "Node nie ma zapisanych kluczy (przeflashowany?) — sparuj go ponownie, będąc w jego sieci WiFi.":
      "The node has no saved keys (reflashed?) — pair it again while on its Wi-Fi network.",
  "Nowa płytka przejęła ID noda — zdalny dostęp wymaga ponownego sparowania: Ustawienia noda → Zdalny dostęp, będąc w jego sieci WiFi.":
      "A new board took over this node's ID — remote access requires pairing again: Node settings → Remote access, while on its Wi-Fi network.",
  "Odtwarzam parowanie...": "Restoring pairing...",
  "Uwaga: to lekka wersja proxy, nie pełny tunel — jedno połączenie naraz, bez WebSocketów i strumieni. Proste panele HTTP zadziałają, ciężkie aplikacje nie.":
      "Note: this is a lightweight proxy, not a full tunnel — one connection at a time, no WebSockets or streams. Simple HTTP panels will work, heavy apps won't.",
  "Zdalny dostęp sparowany ponownie.": "Remote access paired again.",
  "Node odrzucił parowanie (HTTP %s).": "The node refused pairing (HTTP %s).",
  "Node odrzucił żądanie (HTTP %s).": "The node refused the request (HTTP %s).",
  "Node nie jest sparowany z tym telefonem — sparuj go, będąc w tej samej sieci WiFi.":
      "This node isn't paired with this phone — pair it while on the same Wi-Fi network.",
  "Wymagane sparowanie": "Pairing required",
  "Rozumiem": "Got it",
  "Wymaga sparowania noda — tylko w jego sieci WiFi":
      "Needs node pairing — only on its Wi-Fi network",
  "Node niesparowany — tunel nie ruszy. Sparuj, będąc w jego sieci WiFi.":
      "Node not paired — the tunnel won't open. Pair it while on its Wi-Fi network.",
  "Ta integracja otwiera tunel do Twojej sieci, a zgodę na to daje sam node — nie nasz serwer. Trzeba zapisać w nim klucz, będąc w tej samej sieci WiFi: Ustawienia noda → Zdalny dostęp.\n\nIntegrację dodam już teraz, ale połączy się dopiero po sparowaniu.":
      "This integration opens a tunnel into your network, and only the node itself can allow that — not our server. You need to store a key on it while on the same Wi-Fi: Node settings → Remote access.\n\nI'll add the integration now, but it will only connect once the node is paired.",
  // ── 1.5.39/40: MQTT + LoRa awaryjne + push przez BE ──────────
  "MQTT (lokalny broker)": "MQTT (local broker)",
  "publikacja statusu i encji do Mosquitto / Home Assistant": "publish status and entities to Mosquitto / Home Assistant",
  "LoRa awaryjne": "LoRa emergency",
  "encje nadawane radiem przy padzie internetu": "entities broadcast over radio when internet is down",
  "Nie można połączyć z nodem: %s": "Cannot reach the node: %s",
  "Ten node nie obsługuje MQTT — zaktualizuj firmware do 0.90 lub nowszego.": "This node does not support MQTT — update the firmware to 0.90 or newer.",
  "Podaj adres brokera": "Enter the broker address",
  "Zapisano — node łączy się z brokerem": "Saved — the node is connecting to the broker",
  "Połączony z brokerem · wysłano %s wiadomości": "Connected to the broker · %s messages sent",
  "Łączenie... %s": "Connecting... %s",
  "Włączone": "Enabled",
  "Wyłączone": "Disabled",
  "Node publikuje do brokera w Twojej sieci: status (online/offline), diagnostykę, encje (z auto-wykryciem w Home Assistant) i wiadomości. Działa też bez internetu — temat net/wan mówi, czy internet w domu żyje.":
      "The node publishes to a broker on your network: status (online/offline), diagnostics, entities (auto-discovered by Home Assistant) and messages. Works without internet too — the net/wan topic tells you whether your home's internet is alive.",
  "Adres brokera (IP w LAN)": "Broker address (LAN IP)",
  "Użytkownik (opcjonalnie)": "Username (optional)",
  "Hasło (opcjonalnie)": "Password (optional)",
  "Zapisywanie...": "Saving...",
  "Ten node nie obsługuje trybu awaryjnego — wymaga firmware 0.91+ na płytce z radiem LoRa (SX1262, wariant -lora).":
      "This node does not support emergency mode — it needs firmware 0.91+ on a board with a LoRa radio (SX1262, -lora variant).",
  "Zapisano — node nada te encje przy awarii": "Saved — the node will broadcast these entities during an outage",
  "TRYB AWARYJNY AKTYWNY — node nadaje te encje przez LoRa": "EMERGENCY MODE ACTIVE — the node is broadcasting these entities over LoRa",
  "Gdy node straci internet, dołączy wybrane encje (max %s) do ramki radiowej LoRa. Jeśli usłyszy go sąsiedni node albo brama, dostaniesz powiadomienie z ostatnimi wartościami — mimo że Twój dom jest offline.":
      "When the node loses internet, it attaches the selected entities (max %s) to its LoRa radio frame. If a neighboring node or gateway hears it, you get a notification with the last values — even though your home is offline.",
  "Node nie ma jeszcze żadnych encji.": "The node has no entities yet.",
  "Maksymalnie %s encje": "At most %s entities",
  "Zapisz (%s/%s)": "Save (%s/%s)",
  "Zarejestrowane w SENSMOS": "Registered with SENSMOS",
  "Brak tokenu FCM (usługi Google niedostępne?)": "No FCM token (Google services unavailable?)",
  "Niezarejestrowane": "Not registered",
  "Zarejestruj ponownie": "Register again",
  "Rejestrowanie...": "Registering...",
  "Token zarejestrowany — powiadomienia aktywne na tym urządzeniu.": "Token registered — notifications are active on this device.",
  "Rejestracja nie powiodła się — sprawdź internet i spróbuj ponownie.": "Registration failed — check your internet and try again.",
  "Powiadomienia rejestrują się automatycznie przy starcie aplikacji — jedna rejestracja obejmuje wszystkie Twoje nody (akcje skryptów, wiadomości, alarm o utracie łączności przez LoRa). Wyłączysz je w systemowych ustawieniach powiadomień.":
      "Notifications register automatically when the app starts — one registration covers all your nodes (script actions, messages, the LoRa connectivity-loss alarm). You can turn them off in the system notification settings.",
  "Brak powiadomień": "No notifications",
  // ── 1.5.42: plugin Raport łącza ──────────────────────────────
  "Raport łącza": "Connection report",
  "Okres": "Period",
  "ostatnie %s dni": "last %s days",
  "Przerwy w dostępie do internetu": "Internet outages",
  "Łączny czas bez internetu": "Total time without internet",
  "Najdłuższa przerwa": "Longest outage",
  "Pomiar niezależny, 24/7, stempel czasu NTP": "Independent measurement, 24/7, NTP timestamps",
  "%s dni": "%s days",
  "Twój internet (wina dostawcy)": "Your internet (provider's fault)",
  "przerw": "outages",
  "bez internetu": "without internet",
  "najdłuższa": "longest",
  "Pozostałe %s przerw to chwilowe prace po stronie SENSMOS — nie liczą się do raportu.":
      "The remaining %s interruptions were brief SENSMOS maintenance — they don't count toward the report.",
  "Raport skopiowany — wklej go do reklamacji": "Report copied — paste it into your complaint",
  "Kopiuj raport": "Copy report",
  "Brak zaników w tym okresie — łącze działało bez przerw. 🎉":
      "No outages in this period — your connection ran uninterrupted. 🎉",
  "internet nie działał (wina dostawcy)": "internet was down (provider's fault)",
  "serwis SENSMOS — nie liczy się do raportu": "SENSMOS maintenance — not counted in the report",
  // ── 1.5.43: plugin Panel LAN ─────────────────────────────────
  "Panel LAN": "LAN panel",
  "Dodaj panel": "Add panel",
  "Edytuj panel": "Edit panel",
  "Nazwa": "Name",
  "Adres w LAN": "LAN address",
  "Tylko HTTP. Ciężkie panele (UniFi, HA) nie zadziałają — tunel jest wolny.":
      "HTTP only. Heavy panels (UniFi, HA) won't work — the tunnel is slow.",
  "Dodaj panele WWW z sieci noda (router, drukarka, Pi-hole…) — otworzysz je stąd z dowolnego miejsca, przez tunel.":
      "Add web panels from the node's network (router, printer, Pi-hole…) — you'll open them from anywhere, through the tunnel.",
  "Otwieram tunel do noda…": "Opening the tunnel to the node…",
  "Podaj adres w LAN": "Enter the LAN address",
  "LoRa awaryjne — słyszany radiem": "LoRa emergency — heard over radio",
  "LoRa awaryjne — bez internetu, słyszany %s temu przez %s": "LoRa emergency — no internet, heard %s ago by %s",
};

/// Nadpisania niemieckie. Brak wpisu → fallback EN → klucz (PL).
const Map<String, String> _deMap = {
  // ── Panel HA: typy kafelków + akcje ──
  "Typ kafelka": "Kacheltyp",
  "Wykres": "Diagramm",
  "Odczyt": "Messwert",
  "Przełącznik": "Schalter",
  "Światło": "Licht",
  "Przycisk": "Taste",
  "Uruchom": "Ausführen",
  "uruchomiono": "ausgeführt",
  "Nie udało się uruchomić": "Konnte nicht ausgeführt werden",
  "brak historii": "kein Verlauf",
  "Gotowe": "Fertig",
  "Usuń z listy":
      "Aus der Liste entfernen",
  "Usunąć z aplikacji?":
      "Aus der App entfernen?",
  "Node %s zniknie z tej listy. W sieci SENSMOS zostaje bez zmian — nie należy do Twojego portfela, więc nie możesz go stamtąd usunąć.":
      "Node %s verschwindet aus dieser Liste. Im SENSMOS-Netzwerk bleibt er unverändert — er gehört nicht zu deiner Wallet, du kannst ihn dort also nicht entfernen.",
  "Usuń z aplikacji":
      "Aus der App entfernen",
  "Usunięto z aplikacji: %s":
      "Aus der App entfernt: %s",
  "Zastąpić portfel w aplikacji?":
      "Wallet in der App ersetzen?",
  "W aplikacji jest już inny portfel. Odzysk go NADPISZE.":
      "Die App enthält bereits eine andere Wallet. Die Wiederherstellung ÜBERSCHREIBT sie.",
  "Obecny w aplikacji:":
      "Aktuell in der App:",
  "Kopia na nodzie:":
      "Kopie auf dem Node:",
  "Jeśli obecny portfel nie został nigdzie wyeksportowany, stracisz do niego dostęp razem ze środkami. Klucza nie da się odtworzyć.":
      "Wenn die aktuelle Wallet nirgends exportiert wurde, verlierst du den Zugang zu ihr und zu ihrem Guthaben. Der Schlüssel lässt sich nicht wiederherstellen.",
  "Nadpisz":
      "Überschreiben",
  "Sprawdzam kopię na nodzie…":
      "Prüfe die Kopie auf dem Node…",
  "Na nodzie jest kopia TEGO SAMEGO portfela — nic nie zmieniam.":
      "Auf dem Node liegt eine Kopie DERSELBEN Wallet — nichts geändert.",
  "Pełne ID":
      "Vollständige ID",
  "Adres IP":
      "IP-Adresse",
  "Skopiowano %s":
      "Kopiert %s",
  "Pod tym adresem jest inny node (%s) — ta płytka została przeflashowana i ma nową tożsamość.":
      "Unter dieser Adresse ist ein anderer Node (%s) — diese Platine wurde neu geflasht und hat eine neue Identität.",
  "Ten node nie ma zapisanego adresu IP — apka zna go tylko z chmury. Połącz telefon z siecią noda i wyszukaj go lokalnie.":
      "Dieser Node hat keine gespeicherte IP-Adresse — die App kennt ihn nur aus der Cloud. Verbinde das Telefon mit dem Netzwerk des Nodes und suche ihn lokal.",
  "Wyszukaj noda w tej sieci":
      "Node in diesem Netzwerk suchen",
  "Szukam w sieci...":
      "Suche im Netzwerk...",
  "Nie znaleziono noda w tej sieci. Upewnij się, że telefon jest w tej samej sieci WiFi co node.":
      "Node in diesem Netzwerk nicht gefunden. Stelle sicher, dass das Telefon im selben WLAN ist wie der Node.",
  "Node znaleziony: %s":
      "Node gefunden: %s",
  "Rozmyj dokładną pozycję":
      "Genaue Position unscharf machen",
  "Na mapie pokazujemy punkt przesunięty o 200-800 m. Wyłącz tylko, jeśli chcesz publikować dokładny adres.":
      "Auf der Karte zeigen wir einen um 200-800 m verschobenen Punkt. Schalte das nur aus, wenn du die genaue Adresse veröffentlichen willst.",
  "Node w ogóle nie pojawi się na mapie. Zarabia mniej, bo nie współtworzy publicznego pokrycia sieci.":
      "Der Node erscheint gar nicht auf der Karte. Er verdient weniger, weil er nicht zur öffentlichen Netzabdeckung beiträgt.",
  "Tryb prywatny — node nie jest pokazywany na mapie i zarabia w obniżonej stawce, bo nie współtworzy publicznego pokrycia sieci.":
      "Privater Modus — der Node wird nicht auf der Karte gezeigt und verdient zu einem reduzierten Satz, da er nicht zur öffentlichen Netzabdeckung beiträgt.",
  "Brak potwierdzonej lokalizacji GPS — ten node prawie nie zarabia. Podejdź do niego z telefonem i ustaw lokalizację.":
      "Kein bestätigter GPS-Standort — dieser Node verdient fast nichts. Geh mit dem Telefon zu ihm und setze den Standort.",
  "Sprawdzam połączenie...":
      "Verbindung wird geprüft...",
  "Nie można zarejestrować noda — aplikacja nie ma połączenia z internetem. Telefon musi być online przez cały czas rejestracji. Połącz się z siecią i spróbuj ponownie.":
      "Node kann nicht registriert werden — die App hat keine Internetverbindung. Das Telefon muss während der gesamten Registrierung online sein. Verbinde dich mit einem Netzwerk und versuche es erneut.",
  "Utracono połączenie z internetem — nie udało się zarejestrować noda. Telefon musi być online przez cały czas rejestracji.":
      "Internetverbindung verloren — der Node konnte nicht registriert werden. Das Telefon muss während der gesamten Registrierung online sein.",
  "Serwer odrzucił rejestrację noda.":
      "Der Server hat die Node-Registrierung abgelehnt.",
  "Node dodany, ale weryfikacja się nie powiodła — bez niej nie nalicza nagród. Powtórz ceremonię w ustawieniach noda (Zaufanie).":
      "Node hinzugefügt, aber die Verifizierung schlug fehl — ohne sie gibt es keine Belohnungen. Wiederhole die Zeremonie in den Node-Einstellungen (Vertrauen).",
  "Nagrody naliczają się po ok. 4 godzinach online w danej dobie — zero na starcie jest normalne.":
      "Belohnungen beginnen nach etwa 4 Stunden online pro Tag — null am Anfang ist normal.",
  // ── RemoteTerminal / Panel (auto) ──
  "Łączę z relayem…": "Verbinde mit Relay…",
  "Brak portfela w apce": "Keine Wallet in der App",
  "Node jest offline — nie połączysz się z nim, dopóki nie wróci do sieci.": "Node ist offline — keine Verbindung möglich, bis er wieder online ist.",
  "Remote access WŁĄCZONY — ten node będzie rzadziej wybierany do monitorów": "Fernzugriff AN — dieser Node wird seltener für Monitore ausgewählt",
  "Otwieram tunel → %s:%s…": "Öffne Tunnel → %s:%s…",
  "Sesja zakończona": "Sitzung beendet",
  "Rozłączono": "Getrennt",
  "Terminal": "Terminal",
  "Rozłącz": "Trennen",
  "Remote access na nodzie": "Fernzugriff auf dem Node",
  "Pozwala łączyć się z urządzeniami w sieci noda. Włączony node jest rzadziej wybierany do monitorów.": "Ermöglicht Verbindungen zu Geräten im Netzwerk des Nodes. Ein aktivierter Node wird seltener für Monitore ausgewählt.",
  "Host w sieci noda": "Host im Netzwerk des Nodes",
  "Port": "Port",
  "Użytkownik SSH": "SSH-Benutzer",
  "Hasło SSH": "SSH-Passwort",
  "SSH jest szyfrowany end-to-end — node i nasze serwery przekazują tylko zaszyfrowane bajty.": "SSH ist Ende-zu-Ende-verschlüsselt — der Node und unsere Server leiten nur verschlüsselte Bytes weiter.",
  "Połącz": "Verbinden",
  "Najpierw włącz remote access powyżej.": "Aktiviere zuerst oben den Fernzugriff.",
  "Podaj PIN noda": "Node-PIN eingeben",
  "Integracje": "Integrationen",
  "Dodaj integrację": "Integration hinzufügen",
  "Odpiąć integrację?": "Integration entfernen?",
  "Odepnij": "Entfernen",
  "Wymaga FW > 0.70": "Benötigt FW > 0.70",
  "Wszystko już podpięte": "Alles bereits hinzugefügt",
  "Usuń node z sieci": "Node aus Netzwerk entfernen",
  "Integracje wymagają noda online (połączonego z chmurą).": "Integrationen erfordern ein Online-Node (mit der Cloud verbunden).",
  "Panel HA": "HA-Panel",
  "Ustawienia HA": "HA-Einstellungen",
  "Home Assistant": "Home Assistant",
  "Host HA (IP w sieci noda)": "HA-Host (IP im Node-Netz)",
  "Long-lived token": "Long-Lived-Token",
  "Podaj host i token": "Host und Token angeben",
  "Podłącz HA w sieci noda przez tunel. Użyj wewnętrznego adresu HTTP (np. 192.168.1.10:8123) — tunel i tak szyfruje.": "Verbinde HA im Node-Netz über den Tunnel. Nutze die interne HTTP-Adresse (z. B. 192.168.1.10:8123) — der Tunnel verschlüsselt ohnehin.",
  "Token wygenerujesz w HA: Profil → Long-Lived Access Tokens.": "Token in HA erstellen: Profil → Long-Lived Access Tokens.",
  "Usuń integrację": "Integration entfernen",
  "Pokaż": "Anzeigen",
  "Ukryj": "Verbergen",
  "Łączę z HA…": "Verbinde mit HA…",
  "Node jest offline — wróci gdy odzyska sieć.": "Node ist offline — kommt zurück, sobald es wieder Netz hat.",
  "HA nie odpowiada — sprawdź adres i token": "HA antwortet nicht — Adresse und Token prüfen",
  "Pusty dashboard": "Leeres Dashboard",
  "Dodaj kafelek": "Kachel hinzufügen",
  "Nie udało się pobrać encji": "Entitäten konnten nicht geladen werden",
  "Szukaj encji…": "Entitäten suchen…",
  "Nazwa kafelka": "Kachelname",
  "Odśwież encje z HA": "Entitäten von HA aktualisieren",
  "Zły PIN — remote access nie włączony": "Falsche PIN — Fernzugriff nicht aktiviert",
  "Remote access wyłączony": "Fernzugriff aus",
  "Połączenie zerwane — dotknij „Spróbuj ponownie\".": "Verbindung getrennt — tippe auf „Erneut versuchen“.",
  "Spróbuj ponownie": "Erneut versuchen",
  "W tej sieci": "In diesem Netzwerk",
  "Zdalny terminal": "Fernterminal",
  "Dostępne zawsze": "Immer verfügbar",
  "Terminal wymaga noda online (połączonego z chmurą).": "Das Terminal erfordert einen Online-Node (mit der Cloud verbunden).",
  "Sieć lokalna (tylko w sieci noda)": "Lokales Netzwerk (nur im Netzwerk des Nodes)",
  "Ustaw lokalizację (BLE + GPS)": "Standort festlegen (BLE + GPS)",
  "Połącz telefon z siecią WiFi noda, żeby zobaczyć encje i zmienić ustawienia.": "Verbinde dein Telefon mit dem WLAN des Nodes, um Entitäten zu sehen und Einstellungen zu ändern.",
  "Ten node nie jest dodany lokalnie — połącz się z jego siecią i dodaj go, by konfigurować.": "Dieser Node ist nicht lokal hinzugefügt — verbinde dich mit seinem Netzwerk und füge ihn hinzu, um ihn zu konfigurieren.",
  "Online": "Online",
  "Z lokalizacją": "Mit Standort",
  "online": "online",
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
  "POL (gas)": "POL (Gas)",
  "Za mało POL — transakcje (claim/deposit) wymagają gazu. Wpłać POL na adres portfela (QR powyżej).":
      "Zu wenig POL — Transaktionen (Claim/Deposit) brauchen Gas. Sende POL an deine Wallet-Adresse (QR oben).",
  "Za mało POL — odbiór nagród (claim) wymaga gazu. Wpłać POL na adres portfela (QR powyżej).":
      "Zu wenig POL — das Abholen der Belohnungen braucht Gas. Sende POL an deine Wallet-Adresse (QR oben).",
  "Eksportuj klucz (MetaMask)": "Schlüssel exportieren (MetaMask)",
  "wymaga PIN-u dowolnego Twojego noda": "erfordert die PIN eines beliebigen deiner Nodes",
  "Dostępne: %s (MAX)": "Verfügbar: %s (MAX)",
  "Odblokuj": "Entsperren",
  "Klucz prywatny": "Privater Schlüssel",
  "⚠️ Nigdy nikomu nie pokazuj tego klucza. Kto go ma, kontroluje portfel i wszystkie GALU.":
      "⚠️ Zeige diesen Schlüssel niemandem. Wer ihn hat, kontrolliert das Wallet und alle GALU.",
  "MetaMask → Importuj konto → Private Key → wklej.": "MetaMask → Konto importieren → Private Key → einfügen.",
  "Klucz skopiowany": "Schlüssel kopiert",
  "Odbiór POL / GALU": "POL / GALU empfangen",
  "Wyślij POL na ten adres (gas na transakcje)": "Sende POL an diese Adresse (Gas für Transaktionen)",
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
  "Lokalizacja (GPS) jest wyłączona — na Androidzie 11 i starszych jest wymagana do skanowania Bluetooth.":
      "Standort (GPS) ist aus — auf Android 11 und älter ist er für das Bluetooth-Scannen erforderlich.",
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
  "Pokrycie": "Abdeckung",
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
  "Telemetria": "Telemetrie",
  "Radio LoRa": "LoRa-Funk",
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
  "Node jest skonfigurowany i zarejestrowany, ale apka nie widzi go w tej sieci WiFi.\nTelefon jest prawdopodobnie w innej sieci niż node. Połącz telefon z tą samą siecią WiFi i dodaj node ręcznie (Szukaj nodów w sieci).":
      "Der Node ist eingerichtet und registriert, aber die App sieht ihn in diesem WLAN nicht.\nDein Telefon ist vermutlich in einem anderen Netzwerk als der Node. Verbinde das Telefon mit demselben WLAN und füge den Node manuell hinzu (Nodes im Netzwerk suchen).",
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
  "Tryb prywatny włączony — node ukryty z mapy":
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

  // ── Node-Kopplung (Schlüssel im Telefon, Kanal ausschließlich über LAN) ──
  "Zdalny dostęp": "Fernzugriff",
  "Zapamiętaj hasło na tym telefonie": "Passwort auf diesem Telefon merken",
  "sparowany — terminal i panel HA działają z dowolnego miejsca":
      "gekoppelt — Terminal und HA-Panel funktionieren von überall",
  "NIESPAROWANY — sparuj teraz, będąc w sieci noda":
      "NICHT GEKOPPELT — jetzt koppeln, solange du im Netzwerk des Nodes bist",
  "Sparuj": "Koppeln",
  "Sparuj node": "Node koppeln",
  "Node sparowany.": "Node gekoppelt.",
  "Node sparowany — możesz się połączyć.": "Node gekoppelt — du kannst dich jetzt verbinden.",
  "Node niesparowany": "Node nicht gekoppelt",
  "Najpierw sparuj node powyżej.": "Kopple zuerst den Node oben.",
  "Nie znam tego noda na tym telefonie.": "Dieses Telefon kennt diesen Node nicht.",
  "Zdalny dostęp wymaga jednorazowego sparowania w tej samej sieci WiFi co node.":
      "Fernzugriff erfordert eine einmalige Kopplung im selben WLAN wie der Node.",
  "Zdalny dostęp wymaga jednorazowego sparowania: telefon zapisze w nodzie tajny klucz, którego nasz serwer nigdy nie zobaczy. Bez niego nikt — łącznie z nami — nie otworzy tunelu do Twojej sieci.\n\nMusisz być teraz w tej samej sieci WiFi co node.":
      "Fernzugriff erfordert eine einmalige Kopplung: Das Telefon speichert einen geheimen Schlüssel auf dem Node, den unser Server nie sieht. Ohne ihn kann niemand — auch wir nicht — einen Tunnel in dein Netzwerk öffnen.\n\nDu musst jetzt im selben WLAN wie der Node sein.",
  "Wyłączyć zdalny dostęp?": "Fernzugriff deaktivieren?",
  "Node skasuje wszystkie klucze — terminal i panel HA przestaną działać ze WSZYSTKICH telefonów, także innych domowników. Ponowne włączenie wymaga bycia w sieci noda.":
      "Der Node löscht alle Schlüssel — Terminal und HA-Panel funktionieren dann auf ALLEN Telefonen nicht mehr, auch bei anderen im Haushalt. Zum Wiedereinschalten musst du im Netzwerk des Nodes sein.",
  "Zdalny dostęp wyłączony.": "Fernzugriff deaktiviert.",
  "Zły PIN noda.": "Falsche Node-PIN.",
  "Nie widzę noda w tej sieci — połącz telefon z tym samym WiFi co node.":
      "Node in diesem Netzwerk nicht gefunden — verbinde das Telefon mit demselben WLAN wie den Node.",
  "Node nie ma zapisanych kluczy (przeflashowany?) — sparuj go ponownie, będąc w jego sieci WiFi.":
      "Der Node hat keine gespeicherten Schlüssel (neu geflasht?) — kopple ihn erneut in seinem WLAN.",
  "Nowa płytka przejęła ID noda — zdalny dostęp wymaga ponownego sparowania: Ustawienia noda → Zdalny dostęp, będąc w jego sieci WiFi.":
      "Eine neue Platine hat die ID dieses Nodes übernommen — Fernzugriff erfordert erneute Kopplung: Node-Einstellungen → Fernzugriff, im WLAN des Nodes.",
  "Odtwarzam parowanie...": "Kopplung wird wiederhergestellt...",
  "Uwaga: to lekka wersja proxy, nie pełny tunel — jedno połączenie naraz, bez WebSocketów i strumieni. Proste panele HTTP zadziałają, ciężkie aplikacje nie.":
      "Hinweis: das ist ein leichtes Proxy, kein voller Tunnel — eine Verbindung auf einmal, keine WebSockets oder Streams. Einfache HTTP-Panels funktionieren, schwere Apps nicht.",
  "Zdalny dostęp sparowany ponownie.": "Fernzugriff erneut gekoppelt.",
  "Node odrzucił parowanie (HTTP %s).": "Der Node hat die Kopplung abgelehnt (HTTP %s).",
  "Node odrzucił żądanie (HTTP %s).": "Der Node hat die Anfrage abgelehnt (HTTP %s).",
  "Node nie jest sparowany z tym telefonem — sparuj go, będąc w tej samej sieci WiFi.":
      "Dieser Node ist nicht mit diesem Telefon gekoppelt — kopple ihn im selben WLAN.",
  "Wymagane sparowanie": "Kopplung erforderlich",
  "Rozumiem": "Verstanden",
  "Wymaga sparowania noda — tylko w jego sieci WiFi":
      "Erfordert Node-Kopplung — nur in seinem WLAN",
  "Node niesparowany — tunel nie ruszy. Sparuj, będąc w jego sieci WiFi.":
      "Node nicht gekoppelt — der Tunnel startet nicht. Koppeln, solange du in seinem WLAN bist.",
  "Ta integracja otwiera tunel do Twojej sieci, a zgodę na to daje sam node — nie nasz serwer. Trzeba zapisać w nim klucz, będąc w tej samej sieci WiFi: Ustawienia noda → Zdalny dostęp.\n\nIntegrację dodam już teraz, ale połączy się dopiero po sparowaniu.":
      "Diese Integration öffnet einen Tunnel in dein Netzwerk, und das erlaubt nur der Node selbst — nicht unser Server. Dafür musst du einen Schlüssel auf ihm speichern, während du im selben WLAN bist: Node-Einstellungen → Fernzugriff.\n\nIch füge die Integration jetzt hinzu, aber sie verbindet sich erst nach der Kopplung.",
  // ── 1.5.39/40: MQTT + LoRa awaryjne + push przez BE ──────────
  "MQTT (lokalny broker)": "MQTT (lokaler Broker)",
  "publikacja statusu i encji do Mosquitto / Home Assistant": "Status und Entitäten an Mosquitto / Home Assistant veröffentlichen",
  "LoRa awaryjne": "LoRa-Notfall",
  "encje nadawane radiem przy padzie internetu": "Entitäten, die bei Internetausfall per Funk gesendet werden",
  "Nie można połączyć z nodem: %s": "Node nicht erreichbar: %s",
  "Ten node nie obsługuje MQTT — zaktualizuj firmware do 0.90 lub nowszego.": "Dieser Node unterstützt kein MQTT — aktualisiere die Firmware auf 0.90 oder neuer.",
  "Podaj adres brokera": "Broker-Adresse eingeben",
  "Zapisano — node łączy się z brokerem": "Gespeichert — der Node verbindet sich mit dem Broker",
  "Połączony z brokerem · wysłano %s wiadomości": "Mit dem Broker verbunden · %s Nachrichten gesendet",
  "Łączenie... %s": "Verbinde... %s",
  "Włączone": "Aktiviert",
  "Wyłączone": "Deaktiviert",
  "Node publikuje do brokera w Twojej sieci: status (online/offline), diagnostykę, encje (z auto-wykryciem w Home Assistant) i wiadomości. Działa też bez internetu — temat net/wan mówi, czy internet w domu żyje.":
      "Der Node veröffentlicht an einen Broker in deinem Netzwerk: Status (online/offline), Diagnose, Entitäten (automatisch von Home Assistant erkannt) und Nachrichten. Funktioniert auch ohne Internet — das Topic net/wan sagt dir, ob das Internet zu Hause lebt.",
  "Adres brokera (IP w LAN)": "Broker-Adresse (LAN-IP)",
  "Użytkownik (opcjonalnie)": "Benutzer (optional)",
  "Hasło (opcjonalnie)": "Passwort (optional)",
  "Zapisywanie...": "Speichern...",
  "Ten node nie obsługuje trybu awaryjnego — wymaga firmware 0.91+ na płytce z radiem LoRa (SX1262, wariant -lora).":
      "Dieser Node unterstützt den Notfallmodus nicht — er braucht Firmware 0.91+ auf einer Platine mit LoRa-Funk (SX1262, Variante -lora).",
  "Zapisano — node nada te encje przy awarii": "Gespeichert — der Node sendet diese Entitäten bei einem Ausfall",
  "TRYB AWARYJNY AKTYWNY — node nadaje te encje przez LoRa": "NOTFALLMODUS AKTIV — der Node sendet diese Entitäten über LoRa",
  "Gdy node straci internet, dołączy wybrane encje (max %s) do ramki radiowej LoRa. Jeśli usłyszy go sąsiedni node albo brama, dostaniesz powiadomienie z ostatnimi wartościami — mimo że Twój dom jest offline.":
      "Verliert der Node das Internet, hängt er die gewählten Entitäten (max. %s) an seinen LoRa-Funkrahmen. Hört ihn ein Nachbar-Node oder ein Gateway, bekommst du eine Benachrichtigung mit den letzten Werten — obwohl dein Zuhause offline ist.",
  "Node nie ma jeszcze żadnych encji.": "Der Node hat noch keine Entitäten.",
  "Maksymalnie %s encje": "Höchstens %s Entitäten",
  "Zapisz (%s/%s)": "Speichern (%s/%s)",
  "Zarejestrowane w SENSMOS": "Bei SENSMOS registriert",
  "Brak tokenu FCM (usługi Google niedostępne?)": "Kein FCM-Token (Google-Dienste nicht verfügbar?)",
  "Niezarejestrowane": "Nicht registriert",
  "Zarejestruj ponownie": "Erneut registrieren",
  "Rejestrowanie...": "Registriere...",
  "Token zarejestrowany — powiadomienia aktywne na tym urządzeniu.": "Token registriert — Benachrichtigungen sind auf diesem Gerät aktiv.",
  "Rejestracja nie powiodła się — sprawdź internet i spróbuj ponownie.": "Registrierung fehlgeschlagen — prüfe deine Internetverbindung und versuche es erneut.",
  "Powiadomienia rejestrują się automatycznie przy starcie aplikacji — jedna rejestracja obejmuje wszystkie Twoje nody (akcje skryptów, wiadomości, alarm o utracie łączności przez LoRa). Wyłączysz je w systemowych ustawieniach powiadomień.":
      "Benachrichtigungen registrieren sich automatisch beim App-Start — eine Registrierung deckt alle deine Nodes ab (Skript-Aktionen, Nachrichten, der LoRa-Verbindungsverlust-Alarm). Abschalten kannst du sie in den System-Benachrichtigungseinstellungen.",
  "Brak powiadomień": "Keine Benachrichtigungen",
  // ── 1.5.42: plugin Raport łącza ──────────────────────────────
  "Raport łącza": "Verbindungsbericht",
  "Okres": "Zeitraum",
  "ostatnie %s dni": "letzte %s Tage",
  "Przerwy w dostępie do internetu": "Internetausfälle",
  "Łączny czas bez internetu": "Gesamtzeit ohne Internet",
  "Najdłuższa przerwa": "Längster Ausfall",
  "Pomiar niezależny, 24/7, stempel czasu NTP": "Unabhängige Messung, 24/7, NTP-Zeitstempel",
  "%s dni": "%s Tage",
  "Twój internet (wina dostawcy)": "Dein Internet (Schuld des Anbieters)",
  "przerw": "Ausfälle",
  "bez internetu": "ohne Internet",
  "najdłuższa": "längster",
  "Pozostałe %s przerw to chwilowe prace po stronie SENSMOS — nie liczą się do raportu.":
      "Die übrigen %s Unterbrechungen waren kurze SENSMOS-Wartungen — sie zählen nicht zum Bericht.",
  "Raport skopiowany — wklej go do reklamacji": "Bericht kopiert — füge ihn in deine Beschwerde ein",
  "Kopiuj raport": "Bericht kopieren",
  "Brak zaników w tym okresie — łącze działało bez przerw. 🎉":
      "Keine Ausfälle in diesem Zeitraum — die Verbindung lief ohne Unterbrechung. 🎉",
  "internet nie działał (wina dostawcy)": "Internet war down (Schuld des Anbieters)",
  "serwis SENSMOS — nie liczy się do raportu": "SENSMOS-Wartung — zählt nicht zum Bericht",
  // ── 1.5.43: plugin Panel LAN ─────────────────────────────────
  "Panel LAN": "LAN-Panel",
  "Dodaj panel": "Panel hinzufügen",
  "Edytuj panel": "Panel bearbeiten",
  "Nazwa": "Name",
  "Adres w LAN": "LAN-Adresse",
  "Tylko HTTP. Ciężkie panele (UniFi, HA) nie zadziałają — tunel jest wolny.":
      "Nur HTTP. Schwere Panels (UniFi, HA) funktionieren nicht — der Tunnel ist langsam.",
  "Dodaj panele WWW z sieci noda (router, drukarka, Pi-hole…) — otworzysz je stąd z dowolnego miejsca, przez tunel.":
      "Füge Web-Panels aus dem Netzwerk des Nodes hinzu (Router, Drucker, Pi-hole…) — du öffnest sie von überall, durch den Tunnel.",
  "Otwieram tunel do noda…": "Öffne den Tunnel zum Node…",
  "Podaj adres w LAN": "Gib die LAN-Adresse ein",
  "LoRa awaryjne — słyszany radiem": "LoRa-Notfall — per Funk gehört",
  "LoRa awaryjne — bez internetu, słyszany %s temu przez %s": "LoRa-Notfall — kein Internet, vor %s gehört von %s",
};
