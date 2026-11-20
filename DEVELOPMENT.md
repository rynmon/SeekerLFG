# Developing Seeker LFG

The player-facing description is in [README.md](README.md).

## Files

| File | What it holds |
|---|---|
| `Core.lua` | Search, results, the XP rule, filters, sorting, continents, member locations and lookups, alerts, messages, actions |
| `UI.lua` | The window: Browse page, filters, cards, tooltips, side tabs, eye portrait, the game-window replacement hook, events and slash commands |
| `Listing.lua` | The List yourself page (mirrors the game's `Blizzard_LFGVanilla_Listing`) |
| `Who.lua` | The Who page (mirrors the game's `WhoList.lua`) |
| `Messages.lua` | The Messages window (Request to join and invite templates) |
| `Settings.lua` | The page in Options > AddOns |
| `Diagnostics.lua` | `/seeker selftest` |
| `Minimap.lua` | The minimap eye and the addon compartment |
| `Bindings.xml` | Keybindings: open or close, and Search again |
| `Changelog.lua` | Release notes (not shipped; the workflow reads it) |

Forever's own UI code, which Seeker mirrors, is on the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever) (`Interface/AddOns/Blizzard_GroupFinder_VanillaStyle`).

## Testing

Copy the addon files into `World of Warcraft\_forever_\Interface\AddOns\SeekerLFG`. New files or a changed TOC need a full game restart; other changes need only `/reload`. [TESTING.md](TESTING.md) has the checklist, starting with `/seeker selftest`.

## Releasing

`.github/workflows/release.yml` checks every push: it syntax-checks the Lua, checks every file the TOC loads exists, and makes sure `Changelog.lua` has notes for the version in `SeekerLFG.toc`.

1. Add the new version's notes at the top of `Changelog.lua`, and bump `## Version:` in `SeekerLFG.toc` to match.
2. Commit, then tag and push: `git tag v0.9.3` and `git push origin main v0.9.3`.
3. The workflow builds `SeekerLFG-0.9.3.zip` (one `SeekerLFG/` folder, made with `git archive`, leaving out what `.gitattributes` marks `export-ignore`) and publishes a GitHub release with the notes from `Changelog.lua`. A version containing `alpha` or `beta` is marked as a pre-release.

If the tag doesn't match the TOC version, the release fails, so the two can't drift apart. CurseForge uploads aren't set up yet.
