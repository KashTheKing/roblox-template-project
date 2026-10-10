# OSM World (Roblox)
Walk around anywhere on Earth as your Roblox character. Buildings, roads, paths, parks and water are generated
at runtime from [OpenStreetMap](https://www.openstreetmap.org) data, drawn with **EditableMesh** and textured with
procedurally generated **EditableImage**s (no uploaded assets), and streamed in tiles around you as you move.
Type a place name or `lat, lon` in the box at the top of the screen, or tap a preset.

Built on the Rojo/VSCode/GitHub template described further down.

## How it works
```
Overpass API --HTTP--> OsmService (server) --parsed tile--> RemoteFunction --> WorldController (client)
Photon/Nominatim ----> GeocodeService (server)                                     |
                                                                    TileRenderer -> geometry -> EditableMesh + EditableImage
```
- **Server** (`src/server/services`): `osm-service` fetches one lat/lon tile at a time from Overpass (queued, spaced out,
  retried across mirrors, cached, de-duplicated across players), `geocode-service` resolves place names, and
  `world-service` is the only entry point for clients (argument validation + per-player rate limits).
- **Shared, Roblox-free logic** (`src/shared`): projection, tile grid, OSM parsing, polygon triangulation/clipping and all
  mesh/texture generation are plain Luau, so they run in the offline tests.
- **Client** (`src/client`): `world-controller` decides which tiles to load/unload around the character, `tile-renderer`
  builds a tile, `mesh-writer` / `texture-library` turn plain mesh/pixel data into EditableMeshes/EditableImages.

Why the meshes are built on the **client**: EditableMeshes do not replicate from the server, so the server only fetches and
parses data. Each player also has their own local origin, so teleporting re-centres the world on `(0, 0, 0)` and
coordinates stay small anywhere on Earth. (Consequence: players are not shown each other across different origins. For
multiplayer, give each location its own reserved server.)

Collision comes from invisible wall parts along every building edge plus a ground slab per tile, not from the visual
meshes, which keeps physics cheap and independent of how the meshes render.

## Run it
1. Do the template setup below (`npm install`, `rokit install`, `npm run wally:install`).
2. `rojo serve` and connect from Studio (or `rojo build -o osm-world.rbxl`).
3. In Studio: **Game Settings > Security > Allow HTTP Requests** (needed to reach Overpass/Photon).
4. Press Play. You start in Times Square; use the box or presets to go elsewhere.

## Verify these in Studio first
This project was written and tested outside Studio (the pure logic has automated tests; the Roblox API calls
could not be run). A few engine behaviours are therefore worth a 2-minute check, and each has a switch in
`src/shared/configs/world-config.luau`:
- **Buildings look inside-out or invisible** -> flip `flipTriangleWinding`.
- **Facades look stretched or streaky** -> the texture sampler is not repeating UVs; set `facadeUvMode = "quads"`
  (exact but ~15x more triangles; also lower `viewRadiusTiles`).
- **No meshes at all** -> EditableMesh/EditableImage may be unavailable for your experience or account
  (they have creator requirements). The game then falls back to coloured parts for buildings and roads automatically;
  check the Output window for `[mesh]` warnings.
- **Memory warnings on the client** -> lower `viewRadiusTiles`, or set `keepEditableMeshes = false` once you have
  confirmed MeshParts keep rendering after their EditableMesh is destroyed.

## Tests
```bash
python3 tests/run.py            # needs python3 and the `luau` CLI on PATH (or --luau PATH)
```
The runner bundles the real files from `src/shared` and gives them a virtual `script`/`require`, so the same code that
ships to Roblox is what gets tested: projection, tile math, ear-clipping triangulation, polygon/line clipping, Overpass
parsing, building/road/area geometry (winding, normals, vertex caps), and procedural textures.

## Limits and ideas
- Flat world: no terrain elevation yet (a natural next step is an elevation source feeding a heightfield).
- Multipolygon relations (large buildings with courtyards, big lakes made of several ways) are skipped; only simple
  closed ways are drawn. Bridges are drawn at ground level, tunnels are skipped.
- Roads are flat colour (no lane markings), buildings use six facade styles picked per building id.
- The public Overpass servers are for light use. For a real game, host your own Overpass instance or a small caching
  proxy and point `overpassEndpoints` at it. Tiles are cached in server memory only.
- Data (c) OpenStreetMap contributors, available under the [ODbL](https://opendatacommons.org/licenses/odbl/). The HUD
  shows the required credit; keep it if you ship this.

## Folder layout
```
src/bootstrap/     entry scripts that load every service / controller
src/server/services/   osm-service, geocode-service, world-service
src/client/controllers/ world-controller, ui-controller
src/client/classes/     tile-renderer, mesh-writer, texture-library
src/shared/configs/     world-config  (all tuning knobs)
src/shared/geo/         geo-projection, tile-math
src/shared/osm/         osm-parser
src/shared/geometry/    polygon, clip, mesh-data, mesh-set, building/flat/tile geometry, texture-pixels
tests/                  offline specs + runner
```

---

# Template setup
This repository is a template project for coding with a Rojo/VSCode/GitHub workflow for Roblox luau!

## Setup Process
Alright, ready to get coding? First, there are a couple of things to get set up.

### Plugins
There are a few plugins you need installed in VSCode itself:

- [Luau Language Server](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp)
- [StyLua](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.stylua)
- [Rojo](https://marketplace.visualstudio.com/items?itemName=evaera.vscode-rojo)
- [Selene](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.stylua)

### VSCode Settings
Create a folder called `.vscode` on the root of the repository. Under this folder, make another folder called `settings.json`. Here are my settings, I suggest you use them:

```json
{
    "luau-lsp.completion.imports.requireStyle": "alwaysAbsolute",
    "luau-lsp.completion.imports.suggestRequires": false,
    "luau-lsp.completion.fillCallArguments": false,
    "luau-lsp.completion.imports.enabled": true,
    "luau-lsp.diagnostics.workspace": false,
    "luau-lsp.sourcemap.autogenerate": true,
    "luau-lsp.completion.enabled": true,
    "luau-lsp.fflags.enableNewSolver": true,
    
    "stylua.configPath": "stylua.toml",

    "editor.quickSuggestions": {
        "strings": "on"
    },

    "editor.suggestOnTriggerCharacters": true,
    "editor.quickSuggestionsDelay": 0,
    "editor.inlineSuggest.enabled": true,

    "[luau]": {
        "editor.defaultFormatter": "JohnnyMorganz.stylua",
        "editor.formatOnSave": true,
        "editor.acceptSuggestionOnEnter": "on",
        "editor.suggestSelection": "first",
        "editor.tabCompletion": "on",
    },

    "stylua.targetReleaseVersion": "latest",
}
```

Note: if you do not want to use the new Roblox type solver, set `luau-lsp.fflags.enableNewSolver` to false.

### Setup
Run the following commands:

```bash
npm install
```

```bash
rokit install
```

```bash
npm run wally:install
```

### Notes
- *Anytime your VSCode typechecking is geeking out, I would suggest running the `wally:install` command and then reloading VSCode. This does not happen often, but on occasion stuff can get weird.*

- *If something goes wrong with npm or Node.js, you can download it [here.](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)*

**Some niche VSCode niceties:**
- You don't have to create variables for services. Simply write `ServerScriptService` anywhere in a script and it'll auto create a variable at the top of the script for it.
- StyLua auto sorts all of your requires, it's great! Same with the services, they are also sorted by alphabetical order.
- You can Ctrl + Click on a require to bring you to the file
- You can add code snippets in a file under `.vscode` called `class.code-snippets`
- The luau typechecking is usually better than Roblox's. Sometimes it isn't, but for the most part I would say VSCode luau is better

I don't know if I forgot anything. Probably. Good luck! Everything is configurable and highly customizable (check the .tomls)
