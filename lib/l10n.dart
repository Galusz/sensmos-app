import 'dart:ui';

/// Lekka lokalizacja: klucz = polski tekst źródłowy, mapa nadpisań EN.
/// Język z systemu (pl → polski, inne → angielski), fallback na klucz (PL).
/// Interpolacja: w kluczu `%s`, podmieniane kolejno z [args].
///
/// Użycie:
///   tr('Portfel')                       → "Wallet" (EN) / "Portfel" (PL)
///   tr('Saldo: %s GALU', [balance])     → "Balance: 12 GALU"
class L10n {
  static bool _en = false;

  static void init() {
    _en = PlatformDispatcher.instance.locale.languageCode != 'pl';
  }

  static bool get isEn => _en;
}

String tr(String pl, [List<Object?> args = const []]) {
  var s = L10n.isEn ? (_enMap[pl] ?? pl) : pl;
  for (final a in args) {
    s = s.replaceFirst('%s', '$a');
  }
  return s;
}

/// Nadpisania angielskie. Brak wpisu → pokazujemy klucz (PL).
const Map<String, String> _enMap = {
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
