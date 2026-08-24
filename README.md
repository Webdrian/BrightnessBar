# BrightnessBar

Helligkeit externer Monitore aus der Menüleiste steuern — auch die Monitore, für die macOS
gar keinen Regler anbietet.

> *English: a macOS menu bar app to control external monitor brightness, contrast and speaker
> volume over DDC/CI on Apple Silicon, with a gamma-based dimming fallback for displays whose
> I²C channel is unreachable. UI is in German.*

<p align="center">
  <img src="docs/menu.png" width="320" alt="Menü mit Helligkeits-, Lautstärke- und Softwaredimmungs-Reglern">
</p>

## Worum es geht

macOS regelt die Helligkeit nur bei internen Panels und bei Apples eigenen
Thunderbolt-Displays. Bei einem gewöhnlichen externen Monitor sind die Schieber in den
Systemeinstellungen wirkungslos und die Helligkeitstasten tun nichts — man muss ans
OSD-Menü des Geräts.

BrightnessBar spricht den Monitor direkt über den I²C-Kanal seines Displayanschlusses an
(DDC/CI) und regelt dort dieselben Werte, die das OSD-Menü setzt: Helligkeit, Kontrast,
Lautstärke.

## Funktionen

* Helligkeit und Kontrast pro Monitor, direkt am Backlight
* Lautstärke und Stummschaltung bei Monitoren mit Lautsprechern
* Globale Tastenkürzel, die auf den Monitor unter dem Mauszeiger wirken
* Mehrere Monitore koppeln und gemeinsam regeln
* Softwaredimmung als Fallback, wenn der DDC-Kanal nicht erreichbar ist
* Anmeldestart, optionales Dock-Symbol, Info-Fenster
* Braucht **keine** Bedienungshilfen- oder Bildschirmaufnahme-Rechte

## Installation

### Fertige App

Die neueste Version liegt unter [Releases](../../releases). Nach dem Entpacken nach
`/Applications` ziehen.

Die App ist nur ad-hoc signiert, nicht notarisiert — ein Apple-Developer-Account kostet
99 €/Jahr, und das ist für ein kleines Werkzeug wie dieses schwer zu rechtfertigen.
Gatekeeper blockiert sie deshalb beim ersten Start. Einmalig:

**Rechtsklick auf die App → Öffnen → im Dialog „Öffnen" bestätigen.**

Alternativ auf der Kommandozeile:

```bash
xattr -dr com.apple.quarantine /Applications/BrightnessBar.app
```

### Selbst bauen

Braucht eine Xcode-Toolchain (getestet mit Xcode 26.6 / Swift 6.3), aber kein
Xcode-Projekt:

```bash
git clone https://github.com/Webdrian/BrightnessBar.git
cd BrightnessBar
./build.sh --install
```

`./build.sh` allein baut nur ins Projektverzeichnis, `--install` legt die App zusätzlich
nach `/Applications`. Selbst gebaut greift Gatekeeper gar nicht ein.

## Benutzung

Klick auf das Sonnensymbol in der Menüleiste öffnet die Regler.

| Kürzel | Wirkung |
|---|---|
| `⌥⌘↑` / `⌥⌘↓` | heller / dunkler, 10-%-Schritte |
| `⇧⌥⌘↑` / `⇧⌥⌘↓` | heller / dunkler, 2-%-Schritte |

Die Kürzel wirken auf den Monitor, auf dem der Mauszeiger gerade steht — bei mehreren
Bildschirmen also auf den, an dem man arbeitet. Ist *Alle Displays koppeln* aktiv, wirken
sie auf alle steuerbaren Monitore gleichzeitig.

*Beim Anmelden starten* legt einen LaunchAgent unter
`~/Library/LaunchAgents/de.webdrian.brightnessbar.agent.plist` an. Der speichert den
absoluten Pfad zur App: erst an den endgültigen Ort verschieben, dann aktivieren.

## Welche Monitore funktionieren

Die App unterscheidet drei Fälle, weil sie sehr unterschiedlich zu behandeln sind.

1. **Antwortet auf Lesen und Schreiben.** Normalbetrieb, das Backlight wird geregelt.
2. **Antwortet nicht auf Lesen, nimmt aber Befehle an.** Der Regler wird angezeigt und mit
   „?" markiert; viele Geräte verweigern nur *Get*, nicht *Set*.
3. **Der I²C-Kanal ist gar nicht erreichbar.** `IOAVServiceWriteI2C` scheitert schon beim
   Absenden. Ein Regler, der vorgibt das Backlight zu steuern, wäre hier eine Lüge, also
   schaltet die App auf Softwaredimmung um und schreibt das in die Zeile.

Fall 3 liegt fast immer an der Strecke zwischen Mac und Monitor, nicht am Monitor. Auf dem
Entwicklungsrechner trifft es zwei von drei Displays, und die IORegistry benennt die Ursache
eindeutig: beide hängen hinter einem DisplayPort-Branch-Device, das funktionierende nicht.

| Monitor | Branch-Device in der Strecke | DDC |
|---|---|---|
| LG HDR 4K, direkt an USB-C/DP | keins | funktioniert |
| DELL U2719D | `pHDMIg` — DP→HDMI-Wandler | abgelehnt |
| DELL U2719D | `Dp1.2` — DP-Branch | abgelehnt |

Gemessen mit 27 Parametervarianten pro Monitor (ein bis drei Sendevorgänge, 40/150/400 ms
Wartezeit, VCP `0x10`, `0xDF`, `0x60`): beim LG jedes Mal eine gültige Antwort, bei beiden
Dells jedes Mal Fehler `0xE0114000` bereits beim Schreiben und ein Antwortpuffer aus lauter
Nullen. Timing, Protokoll und Parameter sind als Ursache damit ausgeschlossen.

Was hilft:

* **Verbindung ohne Protokollwandler** — USB-C (DP Alt Mode) auf DisplayPort. Adapter mit
  Wandlerchip, DP-Hubs, MST-Splitter und KVM-Switches leiten den I²C-Kanal meist nicht
  durch.
* **DDC/CI im OSD-Menü aktivieren.** Beim U2719D unter *Menu → Others → DDC/CI*. Das allein
  reicht aber nicht, wenn schon die Strecke den Kanal nicht führt.

## Softwaredimmung

Für Monitore aus Fall 3 skaliert die App die Übertragungsfunktion des Displays
(`CGSetDisplayTransferByFormula`), statt das Backlight zu regeln. Das ist ausdrücklich nicht
dasselbe:

* Das Backlight leuchtet weiter mit voller Leistung — es wird kein Strom gespart.
* Sehr dunkle Einstellungen kosten Farbauflösung.
* 0 % entspricht Faktor 0,15, nicht Schwarz. Ein Display, das man nicht mehr sieht, kann man
  auch nicht mehr zurückstellen.

Der Schalter *Softwaredimmung, wo DDC fehlt* ist standardmäßig an, weil die betroffenen
Monitore sonst überhaupt nicht regelbar wären. Ausgeschaltet stellt die App alle
Gamma-Tabellen wieder her und listet die Displays als nicht steuerbar.

Eine Gamma-Tabelle überlebt den Prozess, der sie gesetzt hat. Beim Beenden räumt die App
deshalb auf. Nach Aufwachen oder einer Display-Umkonfiguration setzt sie den Wert neu, weil
macOS die Tabelle dabei verwirft.

## Aufbau

| Datei | Inhalt |
|---|---|
| `Sources/DDC.swift` | DDC/CI über `IOAVService`: Paketformat, Prüfsummen, Timing, Coalescing |
| `Sources/DisplayRegistry.swift` | ordnet CoreGraphics-Displays über EDID und DCP-Instanz den I²C-Kanälen zu |
| `Sources/DisplayController.swift` | Display-Modell, Probing, Hotplug- und Aufwach-Behandlung |
| `Sources/SoftwareDimming.swift` | Gamma-Fallback für Displays ohne erreichbaren DDC-Kanal |
| `Sources/BuiltInBrightness.swift` | `DisplayServices`-Pfad für interne und Apple-Displays |
| `Sources/Hotkeys.swift` | globale Kurzbefehle (Carbon), LaunchAgent |
| `Sources/MenuUI.swift` | SwiftUI-Menü |
| `Sources/AboutWindow.swift` | Info-Fenster und App-Metadaten |
| `Sources/DockVisibility.swift` | Dock-Symbol ein- und ausschalten |
| `Sources/App.swift` | `MenuBarExtra`-Einstiegspunkt, Programmmenü |
| `Tools/make-icon.sh` | erzeugt `Resources/AppIcon.icns` aus Code |

## Technische Notizen

Auf Apple Silicon gibt es keine öffentliche I²C-Schnittstelle für externe Displays. Der Weg
führt über `IOAVServiceCreateWithService`, `IOAVServiceWriteI2C` und `IOAVServiceReadI2C` in
IOKit — undokumentiert und in keinem Header deklariert, deshalb werden die Symbole zur
Laufzeit über `dlsym` aufgelöst. Fehlen sie, meldet die App die Displays als nicht steuerbar
statt abzustürzen.

Die Zuordnung Monitor → I²C-Kanal läuft über die IORegistry: der Framebuffer-Knoten
(`disp0`, `dispext0`, …) trägt die EDID-Daten, über die er per Hersteller-, Produkt- und
Seriennummer eindeutig einer `CGDirectDisplayID` zugeordnet wird. Der zugehörige
`DCPAVServiceProxy` hängt unter der passenden DCP-Instanz (`dcp` → `disp0`,
`dcpext0` → `dispext0`).

Zwei Eigenheiten, die beim Messen auffielen und im Code berücksichtigt werden:

1. **Eine Leseanfrage muss zweimal gesendet werden.** Bei einmaligem Senden liefert der
   getestete Monitor jedes Mal einen unveränderten Altbestand seines Puffers zurück; bei
   zweimaligem Senden antwortet er zuverlässig — 4 von 4 gültigen Antworten statt 0 von 6.
2. **`IOAVServiceReadI2C` überschreibt Byte 1 der Antwort** — das Längenbyte `0x88` — mit dem
   gelesenen I²C-Offset. Vor der Prüfsummenkontrolle wird es wieder eingesetzt; die Prüfsumme
   entsteht mit Startwert `0x50` über die Antwort.

Schreibvorgänge werden zusammengefasst: beim Ziehen eines Reglers geht nur der jeweils
neueste Wert auf den Bus, damit der I²C-Kanal nicht überläuft. 31 Slider-Updates in 0,38 s
landeten im Test korrekt auf dem Endwert.

Beim Probing wird zwischen „Monitor schweigt" und „Kanal nicht verfügbar" unterschieden
(`DDCProbeResult`). Nur der zweite Fall führt zur Softwaredimmung, und er wird nicht
wiederholt — Retries können daran nichts ändern.

## Getestet auf

Mac Studio M4 Max, macOS 26.5, Xcode 26.6. LG HDR 4K über DisplayPort: Lesen und Schreiben
von Helligkeit, Kontrast, Lautstärke und Stummschaltung funktionieren, ein gesetzter Wert
bleibt stabil. Zwei DELL U2719D hinter Wandlern: über DDC nicht erreichbar, laufen über
Softwaredimmung.

Der `DisplayServices`-Pfad für interne Panels ist implementiert, aber **ungeprüft** — ein Mac
Studio hat kein internes Display. Ebenfalls ungeprüft ist die *Zustellung* der
Tastenkombinationen; ihre Registrierung beim System ist nachweislich erfolgreich.

## Autor

© 2026 Webdrian — [webdrian.de](https://webdrian.de)

## Lizenz

MIT — siehe [LICENSE](LICENSE).
