# Corrispondenza SF Symbols ↔ SimpleUI Icon Pack

Questo documento tiene traccia di tutti gli **Apple SF Symbols** utilizzati e utilizzabili all'interno di **SimpleUI (KOReader)**, con il rispettivo nome slot atteso per gli **Icon Pack**, la funzione nella UI e lo stato di completamento nel pack `applesymbols`.

---

## 1. Quick Actions (Barra Inferiore / Bottombar)

| SF Symbol Apple | Nome File Slot SimpleUI | Descrizione / Funzione | Stato in `applesymbols` | Note |
| :--- | :--- | :--- | :---: | :--- |
| `house.fill` | `sui_action_homescreen.svg` | Home Screen | ✅ Presente | Già attivo |
| `books.vertical.fill` | `sui_action_library.svg` | Libreria / File Browser | ✅ Presente | Già attivo |
| `chart.bar.xaxis` | `sui_action_stats_calendar.svg` | Statistiche di lettura | ✅ Presente | Già attivo |
| `wifi` | `sui_action_wifi_toggle.svg` | Attiva/Disattiva Wi-Fi | ✅ Presente | Già attivo |
| `power` | `sui_action_power.svg` | Menu spegnimento / sospensione | ✅ Presente | Già attivo |
| `gearshape.fill` | `sui_action_settings.svg` | Impostazioni SimpleUI | ✅ Presente | Già attivo |
| `book.pages.fill` | `sui_action_continue.svg` | Continua lettura libro corrente | ✅ Presente | Perfetta per "Continua" (libro con pagine) |
| `clock.fill` | `sui_action_recent.svg` | Letture recenti (*Recent*) | ✅ Presente | Orologio |
| `clock.arrow.trianglehead.counterclockwise.rotate.90` | `sui_action_history.svg` | Cronologia di lettura (*History*) | ✅ Presente | Orologio con freccia |
| `shuffle` | `sui_action_random_document.svg` | Apri documento casuale | ✅ Presente | Frecce incrociate |
| `bookmark.fill` | `sui_action_bookmark_browser.svg` | Gestore segnalibri | ✅ Presente | Segnalibro pieno |
| `heart.fill` | `sui_action_favorites.svg` | Preferiti (*Favorites*) | ✅ Presente | Cuore pieno |
| `square.stack.3d.up.fill` | `sui_action_collections.svg` | Collezioni | ⏳ Da creare | Suggerito: `square.stack.3d.up.fill` o `folder.fill` |
| `magnifyingglass` | `sui_action_search_library.svg` | Cerca nella libreria | ⏳ Da creare | Suggerito: `magnifyingglass` |
| `sun.max.fill` | `sui_action_frontlight.svg` | Luminosità / Luce frontale | ⏳ Da creare | Suggerito: `sun.max.fill` |
| `moon.fill` | `sui_action_night_mode.svg` | Modalità notte (inversione) | ⏳ Da creare | Suggerito: `moon.fill` o `circle.righthalf.filled` |
| `person.2.fill` | `sui_action_browse_authors.svg` | Sfoglia per autore | ⏳ Da creare | Suggerito: `person.2.fill` |
| `books.vertical.circle` | `sui_action_browse_series.svg` | Sfoglia per serie | ⏳ Da creare | Suggerito: `books.vertical.circle` |
| `tag.fill` | `sui_action_browse_tags.svg` | Sfoglia per tag | ⏳ Da creare | Suggerito: `tag.fill` |

---

## 2. Barra del Titolo (Titlebar)

Tutte le icone della barra superiore sono attualmente complete nel tuo pack:

| SF Symbol Apple | Nome File Slot SimpleUI | Descrizione / Funzione | Stato in `applesymbols` |
| :--- | :--- | :--- | :---: |
| `line.3.horizontal` | `sui_menu.svg` | Menu principale (in alto a destra) | ✅ Presente |
| `magnifyingglass` | `sui_search.svg` | Pulsante ricerca | ✅ Presente |
| `chevron.left` | `sui_back.svg` | Pulsante indietro / ritorno | ✅ Presente |
| `folder.fill` | `sui_browse_normal.svg` | Sfoglia libreria (modalità standard/cartelle) | ✅ Presente |
| `person.fill` | `sui_browse_author.svg` | Sfoglia libreria (per autore) | ✅ Presente |
| `books.vertical.fill` | `sui_browse_series.svg` | Sfoglia libreria (per serie) | ✅ Presente |
| `tag.fill` | `sui_browse_tags.svg` | Sfoglia libreria (per tag) | ✅ Presente |

---

## 3. Paginazione e Navigazione (Chevrons & Navpager)

| SF Symbol Apple | Nome File Slot SimpleUI | Descrizione / Funzione | Stato in `applesymbols` |
| :--- | :--- | :--- | :---: |
| `chevron.left` | `sui_pager_prev.svg` | Pagina precedente (paginazione KOReader) | ✅ Presente |
| `chevron.right` | `sui_pager_next.svg` | Pagina successiva (paginazione KOReader) | ✅ Presente |
| `chevron.left.to.line` / `backward.end` | `sui_pager_first.svg` | Prima pagina | ✅ Presente |
| `chevron.right.to.line` / `forward.end` | `sui_pager_last.svg` | Ultima pagina | ✅ Presente |
| `chevron.left` | `sui_navpager_prev.svg` | Navpager precedente (barra inferiore) | ⏳ Da creare |
| `chevron.right` | `sui_navpager_next.svg` | Navpager successivo (barra inferiore) | ⏳ Da creare |

---

## 4. Schede del Touch Menu (Touch Menu Tab Bar)

Le schede superiori del menu nativo di KOReader (accessibili nel File Browser e durante la lettura):

| SF Symbol Consigliato | Nome File Slot SimpleUI | Scheda Menu KOReader | Stato |
| :--- | :--- | :--- | :---: |
| `line.3.horizontal` | `sui_tab_main.svg` | Scheda Menu principale | ⏳ Opzionale |
| `gearshape` | `sui_tab_setting.svg` | Scheda Impostazioni | ⏳ Opzionale |
| `wrench.and.screwdriver` | `sui_tab_tools.svg` | Scheda Strumenti | ⏳ Opzionale |
| `magnifyingglass` | `sui_tab_search.svg` | Scheda Ricerca | ⏳ Opzionale |
| `slider.horizontal.3` | `sui_tab_fm_settings.svg` | Impostazioni File Browser | ⏳ Opzionale |
| `list.bullet.indent` | `sui_tab_navigation.svg` | Navigazione Reader (Indice TOC) | ⏳ Opzionale |
| `textformat.size` | `sui_tab_typeset.svg` | Impostazioni carattere/impaginazione Reader | ⏳ Opzionale |
| `arrow.backward.to.line` | `sui_tab_filebrowser.svg` | Torna al File Browser dal Reader | ⏳ Opzionale |
| `slider.horizontal.2.square.on.square` | `sui_tab_qs_panel.svg` | Scheda Quick Settings iniettata da SimpleUI | ⏳ Opzionale |

---

## 5. Icone Interne Statistiche & Insights (Glifi Font di Sistema)

Queste icone sono renderizzate internamente tramite caratteri tipografici (`nerdfonts/symbols.ttf`) e non tramite SVG dell'Icon Pack. Vengono mostrate nelle card del modulo **Reading Stats** (Home) e nelle finestre **Reading Insights** e **Streak**:

| Icona UI | Nome Chiave SimpleUI | Codepoint Font KOReader | Dove Compare | SF Symbol Corrispondente |
| :--- | :--- | :---: | :--- | :--- |
| **Orologio** | `clock` | `\u{E385}` | Tempi di lettura (*Oggi, Settimana, Mese, Anno, Medie, Sessione più lunga*) | `clock` / `clock.fill` |
| **Documento** | `page` | `\u{F40E}` | Pagine lette (*Oggi, Settimana, Mese, Anno, Medie, Totale pagine*) | `doc.text` / `doc.plaintext` |
| **Coppa** | `trophy` | `\u{EC3B}` | Miglior serie di lettura consecutiva (*Best streak*) | `trophy` / `trophy.fill` |
| **Fiamma** | `streak` | `\u{F490}` | Serie di lettura attuale (*Current streak*) e titolo finestra Streak | `flame` / `flame.fill` |
| **Grafico / Plot** | `chart` | `\u{E829}` | Intestazione Reading Insights, grafici *Questa settimana* e *Mese per mese* | `chart.bar.xaxis` / `chart.xyaxis.line` |
| **Calendario** | `calendar_select` | `\u{ED77}` | Riquadri attività, giorni letti, mese per giorno | `calendar` |
| **Libro** | `book` | `\u{F401}` | Libri completati (*Books finished*) | `book.closed` |
| **Bandiera** | `goal` | `\u{E153}` | Obiettivi di lettura (*Reading Goals*) | `flag` / `target` |
| **Fiocco di neve** | `freeze` | `\u{F2DC}` | Serie congelata (*Freeze streak*) | `snowflake` |
