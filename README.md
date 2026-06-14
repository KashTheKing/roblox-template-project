# Roblox Template Project
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
