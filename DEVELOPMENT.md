# Developing Seeker LFG

The player-facing description is in [README.md](README.md).

## Files

| File | What it holds |
|---|---|
| `Locale.lua` | Translations: `ns.L`, which every other file reads as `L` (`T` in `Listing.lua`, whose `L` is the page's state) |
| `Core.lua` | Search, results, the XP rule, filters, sorting, continents, member locations and lookups, alerts, messages, actions |
| `Social.lua` | Requests and invites you've made (and their answers), notes on players, Fill my group, the first-run message |
| `Chat.lua` | Groups and players from chat channels: reading LFM/LFG messages into cards |
| `Setups.lua` | Saved filter setups |
| `UI.lua` | The window: Browse page, filters, cards, tooltips, side tabs, eye portrait, the game-window replacement hook, events and slash commands |
| `Listing.lua` | The List yourself page (mirrors the game's `Blizzard_LFGVanilla_Listing`) |
| `Who.lua` | The Who page (mirrors the game's `WhoList.lua`) |
| `Messages.lua` | The Messages window (Request to join and invite templates) |
| `Settings.lua` | The page in Options > AddOns |
| `Diagnostics.lua` | `/seeker selftest` |
| `Minimap.lua` | The broker launcher, the minimap eye (a LibDBIcon button) and the addon compartment |
| `Libs\` | Bundled libraries, loaded first: LibStub, CallbackHandler-1.0 (from [Ace3](https://github.com/WoWUIDev/Ace3)), [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) and LibDBIcon-1.0 (from its [WowAce repository](https://repos.curseforge.com/wow/libdbicon-1-0)). Unchanged copies; to update one, replace its file with the new release. |
| `Bindings.xml` | Keybindings: open or close, and Search again |
| `Changelog.lua` | Release notes (not shipped; the workflow reads it) |

Forever's own UI code, which Seeker mirrors, is on the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever) (`Interface/AddOns/Blizzard_GroupFinder_VanillaStyle`).

## Text and translations

Every piece of text Seeker shows is written in English as `L["..."]`, where `L` is the translation table from `Locale.lua`. It returns the translation for the client's language, or the English when there isn't one. Where the game has its own wording, use the game's global string first: `LFG_LIST_UNLIST or L["Delist"]`. Strings that code matches on (atlas names, enum keys, command words, the English dungeon names in `Core.lua`) stay plain literals. To translate, add an `ns.AddTranslations("deDE", { ... })` block at the bottom of `Locale.lua`.

## Testing

Copy the addon files into `World of Warcraft\_forever_\Interface\AddOns\SeekerLFG`. New files or a changed TOC need a full game restart; other changes need only `/reload`. [TESTING.md](TESTING.md) has the checklist, starting with `/seeker selftest`.

## Releasing

`.github/workflows/release.yml` checks every push: it syntax-checks the Lua, runs luacheck for undefined or stray globals (`.luacheckrc` lists the game globals Seeker uses; add new ones there), checks every file the TOC loads exists, and makes sure `Changelog.lua` has notes for the version in `SeekerLFG.toc`.

1. Add the new version's notes at the top of `Changelog.lua`, and bump `## Version:` in `SeekerLFG.toc` to match.
2. Commit, then tag and push: `git tag v1.0.1` and `git push origin main v1.0.1`.
3. The workflow builds `SeekerLFG-1.0.1.zip` (one `SeekerLFG/` folder, made with `git archive`, leaving out what `.gitattributes` marks `export-ignore`), publishes a GitHub release with the notes from `Changelog.lua`, and uploads the same zip and notes to CurseForge. A version containing `alpha` or `beta` is a pre-release on GitHub and an alpha or beta on CurseForge.

If the tag doesn't match the TOC version, the release fails, so the two can't drift apart.

### CurseForge

The upload needs, once:

- `## X-Curse-Project-ID: <id>` in `SeekerLFG.toc` (the number in the project's About box on CurseForge).
- A CurseForge API token (curseforge.com > your avatar > My API Tokens) saved as the `CF_API_TOKEN` secret in the GitHub repository (Settings > Secrets and variables > Actions).

It tags the file for CurseForge's newest WoW Forever game version. To choose another, set the `CF_GAME_VERSION_ID` repository variable to its ID; if the upload can't find a WoW Forever version, its log lists the game version types CurseForge has. Without the token or the project ID, the upload is skipped and the GitHub release still goes out.

The project page's icon is `assets/icon/curseforge-icon.png` (drawn by `assets/icon/make_icon.py`), and its screenshots are in `assets/screenshots/`.
