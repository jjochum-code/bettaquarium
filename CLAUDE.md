# Betta-Simulation (Godot 4)

Realistisch wirkender Siamesischer Kampffisch in Lebensgröße vor schwarzem Hintergrund. Ziel: möglichst realistisch und spektakulär. Godot 4.7 per Homebrew (`godot` im PATH), Mac mit Apple M3, Renderer Forward+/Metal.

Starten: `godot --path /Users/golo/Downloads/betta-sim`

Tasten: `F` Futter, `C` feste Paletten (setzt Halfmoon), `2` versteckt: Zufallslook (Farbe + Flossentyp), `Cmd+F`/`F11` Vollbild, `Esc` Ende.

## Aufbau

Alles wird in Code erzeugt, `main.tscn` enthält nur den Wurzelknoten.

- `main.gd`: Umgebung (Nebel, Glow, Tonemapping), Lichter, Lichtstrahlen-Flächen, Schwebeteilchen, Kamera. `_fit_view()` macht den Fisch lebensgroß (`FISH_LENGTH_CM`, Bildschirm-DPI): größeres Fenster = mehr Wasser, nicht größerer Fisch. Sand und Pflanzen sind abgeschaltet (`SHOW_FLOOR`).
- `betta.gd`: Verhalten (CRUISE/HOVER/DART/FEED; Fressen: APPROACH -> AIM -> STRIKE -> CHEW). `_process` ruft der Reihe nach `_update_target` (Zustandsmaschine), `_steer` mit den Werten aus `_steering()` (Klasse `Steering` je Zustand), `_animate_swimming` (Shader-Parameter, Federn `Spring` für Flossen-Nachschwingen), `_update_mouth`, `_update_eyes`.
- `betta_mesh.gd`: prozedurales Mesh. Fischraum: Nase z=-0.5, Schwanzwurzel z=+0.5. Flossentyp über Shape-Dictionary (`DEFAULT_SHAPE`). Körpermaße (`center_y`, `half_width`, ...) sind statisch.
- `betta_morphs.gd`: alle Farbdaten: feste Paletten (`PRESETS`), reale Farbmorphe und Flossentypen für den Zufallslook.
- `food.gd`: Pellet (fällt, treibt, sinkt; `engulf`, `nudge`). Fische finden Pellets über die Gruppe `Food.GROUP`.
- `shaders/betta.gdshader`: Körper und Flossen. Verformung komplett im Vertex-Shader (`deform()`), Maul-/Kiemenlinien in `mouth_gape()`/`gill_distance()` (von Vertex und Fragment gemeinsam genutzt), Normalen per finiter Differenz aus CUSTOM0/CUSTOM1-Tangenten. Vertexfarbe r=Flexibilität, g=Teil (0 Körper, 0.35 Brust-, 0.7 Bauch-, 1 Mittelflossen), b=Phase. Flossen-UV: x=Strahlkoordinate, y=Basis->Spitze.
- `shaders/eye.gdshader`: Auge mit eigener `light()`-Funktion.
- `shaders/caustics.gdshaderinc`, `shafts.gdshader`, `sand.gdshader`, `plant.gdshader`.

## Testen (ohne dass jemand zuschaut)

- Bildfolgen: `godot --path . --write-movie <dir>/f.png --fixed-fps 20 --quit-after N` (Movie-Modus ignoriert `--resolution`; andere Größe nur über eine temporäre `override.cfg`).
- Eigene Testszenen: `godot --path . -s <skript.gd> -- <args>` mit `extends SceneTree`. Vor Screenshots `await RenderingServer.frame_post_draw`, sonst kommen veraltete Bilder.
- `tools/feed_test.gd`: wirft Futter, protokolliert die Fressphasen (läuft auch `--headless`, aber dort ist die Ansicht winzig). Gut als Regressionstest nach Umbauten: alten und neuen Stand je mehrmals laufen lassen.
- `tools/eye_track.gd` + `tools/sparkles.py`: Augenpositionen pro Frame und Zählung reinweißer Pixel am Auge. Seed als erstes Argument; Experiment-Schalter als zweites (`noeyes`, `plaineyes`, `nofish`, `noglow`, `nodof`, `novolfog`, `nomsaa`, `nospec`, `noparticles`). Achtung: Läufe sind trotz Seed nicht deterministisch, für Aussagen mehrere Läufe vergleichen.
- Kontaktbögen mit Python/PIL (`python3 -I`).

## Code-Stil

Code und Kommentare auf Englisch, knapp. Kommentare erklären das Warum, nicht das Was, und keine Debug-Geschichten. Getypte GDScript-Variablen, Skripte per `preload` als Typ (`const Food := preload(...)`) statt `class_name`. Zeitabhängiges Glätten mit `_damp(rate, delta)`.

## Fallstricke, die schon Zeit gekostet haben

- Blitzende weiße Pixel/Scheiben kommen von NaN- oder Riesenwerten, die der Glow aufbläht. Gefundene Ursachen: `pow()` im Augen-Shader (Metal), Division durch fast null in den Caustics, `atan(0, 0)`, Normalen, die zu null interpolieren, und kantenparallele Normalen an der Silhouette. Neue Shader-Mathematik immer gegen diese Fälle absichern (`normalize` nur auf geprüfte Vektoren, keine Divisionen durch ungeschützte sin/cos, `pow` nur mit sicherer Basis oder durch Multiplikation ersetzen).
- Details, die kleiner als ein Pixel werden (Flossenstrahlen, Iris, Schuppen), flimmern: per `fwidth` ausblenden. Der Fisch ist bei Lebensgröße nur ein paar hundert Pixel lang, ein Auge etwa 15 Pixel.
- Überlappende Flossen müssen sich identisch bewegen (Flexibilität aus der Position), sonst schneiden sie sich.
- Fressen: Zielen vom Körpermittelpunkt, Fangen am Maul, Fang entlang der Bahn prüfen (schneller Zustoß überspringt sonst das Pellet).

## Ideen für später

Fischverhalten (an der Oberfläche Luft holen, Imponieren mit gespreizten Kiemen und Flossen, Schaumnest, Ausruhen), Wasseroberfläche von unten, dezenter Bodengrund.
