# jocalhost Vision

## Ausgangspunkt

jocalhost soll die lokale Entwicklungsumgebung sichtbar und steuerbar machen, ohne dass Entwickler und KI-Agenten direkt Dev-Server-Prozesse starten muessen. Die App ist der lokale Supervisor: Sie kennt Projekte, Ports, Prozesse, lokale URLs und Netzwerk-URLs.

Die groessere Vision ist, dass diese Sicht nicht an einen einzelnen Rechner gebunden ist. Ein Mac Mini kann die eigentlichen Dev-Server ausfuehren, waehrend ein MacBook, iPhone oder ein KI-Agent denselben Status sieht und die passenden Preview-URLs oeffnet.

## Zielbild

1. Lokales Netzwerk: jocalhost-Instanzen im selben LAN koennen sich gegenseitig finden. Ein Rechner kann als Host laufen, andere Rechner zeigen dessen Status in der eigenen Menueleisten-App an.
2. Remote Preview Links: Ein lokaler Run kann optional eine geschuetzte oeffentliche HTTPS-URL bekommen, die an andere Personen geteilt werden kann.
3. KI-Workflow Boundary: Codex und andere Agenten nutzen jocalhost als Kontrollschicht, statt selbst `npm run dev`, `pnpm dev`, `bun dev` oder Framework-Dev-Server direkt zu starten.

## Lokales Netzwerk

Der Mac, auf dem die Dev-Server laufen, ist der Host. Er startet Projekte lokal und stellt einen token-geschuetzten LAN-Status- und Control-Endpunkt bereit.

Der Client-Rechner liest diesen Status und nutzt `networkURL`, nicht `localhost`, weil `localhost` immer auf den Rechner zeigt, auf dem der Browser gerade laeuft.

Der erste MVP ist absichtlich klein:

- Host zeigt Status, Ports, Prozesszustand und Netzwerk-URLs.
- Client kann `ping`, `list`, `status`, `start`, `stop` und `restart` ausfuehren.
- `open` bleibt lokal auf dem Client, weil der Browser auf dem Client-Rechner oeffnen soll.
- Zugriff ist mit einem lokalen Bearer-Token geschuetzt.

Spaetere Ausbaustufen:

- Bonjour/mDNS Discovery fuer automatische Host-Erkennung.
- Pairing per Code oder expliziter Bestaetigung am Host.
- Rollen: read-only, control, admin.
- Remote-Menueleistenansicht mit Host-Auswahl.
- Bessere Rechtefuehrung fuer geschuetzte macOS-Ordner wie `~/Documents`.

## Oeffentliche Preview Links

Oeffentliche Links brauchen einen Reverse Tunnel. Der lokale Rechner baut ausgehend eine Verbindung zu einem Gateway auf. Das Gateway nimmt HTTPS-Traffic an und leitet ihn durch den Tunnel zum lokalen Port weiter.

Zielbild:

```txt
https://project-user.preview.jocalhost.dev
    -> jocalhost gateway
    -> tunnel to host Mac
    -> http://localhost:3000
```

Produktregeln:

- Preview Links sind standardmaessig geschuetzt.
- Links koennen zeitlich begrenzt werden.
- Optional: Team-Login, E-Mail-Allowlist, Basic Auth oder Einmal-Link.
- Ein Link endet automatisch, wenn der lokale Run stoppt.
- Jeder Run kann eine eigene, nachvollziehbare Preview-URL bekommen.

Technisch kann jocalhost zuerst Adapter fuer bestehende Tunnel-Anbieter unterstuetzen. Ein eigener Gateway-Dienst lohnt sich erst, wenn das Produktmodell klar ist.

## Sicherheitsprinzipien

- Keine Prozesssteuerung ohne Authentifizierung.
- Keine offenen Statusdaten im LAN ohne Token.
- Keine oeffentliche Preview ohne explizite Nutzeraktion.
- Tokens und spaeter Pairing-Schluessel gehoeren in lokale sichere Speicherung.
- Remote-URLs sollen immer sichtbar machen, welcher Host dahintersteht.

## Aktueller Schritt

Der erste gebaute Schritt ist der LAN-Control-MVP:

- jocalhost startet lokal einen token-geschuetzten HTTP-Status- und Control-Server.
- Der Statusserver liefert denselben Snapshot wie die lokale CLI und MCP-Schicht.
- `jocalhostctl lan-info` zeigt URL und Token fuer den lokalen Host.
- `jocalhostctl --remote <host[:port]> --token <token> status` liest den Status von einem anderen Rechner im lokalen Netzwerk.
- `start`, `stop` und `restart` koennen denselben Host im LAN steuern.
- Client-Macs koennen Remote-Hosts dauerhaft in `remote-hosts.plist` speichern.
- Die Menueleisten-App pollt gespeicherte Remote-Hosts und zeigt deren Projekte unter einer Remote-Sektion an.
- Remote-Projektlinks oeffnen nur `networkURL`, nicht die `localhost`-URL des Host-Macs.
