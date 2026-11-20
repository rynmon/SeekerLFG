# Seeker LFG

Looking for Group for **WoW Forever**, with groups and players side by side and filters that keep your dungeon runs earning XP. It looks and works like the game's own group finder, and does everything that window does.

## Keep your XP

Kill XP is lost when the **highest-level party member is more than 12 levels above the enemy**. Seeker checks every listing against this rule and colours it:

| Colour | Meaning |
|---|---|
| Green: Full XP | Highest member ≤ the dungeon's lowest mobs + 12 |
| Yellow: Partial XP | Highest member ≤ the dungeon's highest mobs + 12, so only the tougher mobs give XP |
| Red: No XP | Above every mob + 12 |
| Grey: Unknown | The game didn't report a level |

The XP filter has three settings: **Full XP**, **Any XP** and **Show all**. With **Count my level** ticked, your own level is counted too, so the colours show what happens if you join. Mob levels are estimated from each dungeon's suggested level range.

## Where players are

Each player's zone is shown under their name. It's red when they're on a different continent from the dungeon they listed for, like someone in Kalimdor queued for the Deadmines, and green when they're already there. **Hide far away** removes those players from the list.

## Everything the game's own finder does

The window has the same three tabs as Forever's group finder:

- **List yourself:** pick a category and the activities you want. Then set the playstyle, voice chat, a description, your roles and "new player friendly", and press List. When you're in a group, you get the role dropdown and a role check, and only the leader can change the listing.
- **Browse:** groups and solo players side by side. Your listing appears at the top, and listings that match it show in blue. Right-click a listing to whisper, invite or report it.
- **Who:** a /who search with class, race, zone and sort filters, and an invite button for each player.

Forever has no "apply to group". **Request to join** opens a whisper to the leader with your request already written; press Enter to send it. If **Whisper Messenger** is installed, whispers open there instead.

Other filters: level range, group needs a tank / healer / DPS, player can tank / heal / DPS, player class, hide full groups.

## Your own messages

In the cog menu, **Messages** (or `/seeker messages`) lets you write your own **Request to join** message, and an **Invite** message that's whispered to players when you invite them. Leave the invite message empty for a plain invite.

You can use these placeholders, which are filled in for each listing:

| Placeholder | Becomes |
|---|---|
| `[level]` | your level |
| `[class]` | your class |
| `[roles]` | the roles you've ticked, e.g. Tank/Healer |
| `[dungeon]` | the dungeon they're listed for |
| `[name]` | your name |
| `[target]` | their name |
| `[zone]` | the zone you're in |

For example, `Hey [target], [level] [class] here, free for [dungeon]?` becomes "Hey Skeron, 21 Mage here, free for Deadmines?". The Messages window shows a preview as you type.

## Usage

- `/seeker` (or `/slfg`) opens and closes the window, as do the minimap button and the addon compartment.
- The cog menu has these options:
  - **Replace the game's Looking for Group window:** Seeker opens wherever the game would open its own window. Hold Shift for the game's window.
  - **Show all level ranges**, which is the game's own setting.
  - **Whisper with Whisper Messenger**.
  - **Show minimap button**.
- Drag the corner grip, or use Ctrl + mouse wheel, to resize the window.
- `/seeker reset` resets the window position and size, and `/seeker debug` prints what the game's LFG API reports, for bug reports.

## Install

Download `SeekerLFG-x.y.z.zip` from [Releases](../../releases). Unzip it into `World of Warcraft\_forever_\Interface\AddOns\` so that you have an `AddOns\SeekerLFG` folder, then restart the game.

## Releasing

`.github/workflows/release.yml` checks every push: it syntax-checks the Lua files and makes sure `Changelog.lua` has notes for the version in `SeekerLFG.toc`.

To release:

1. Add the new version's notes at the top of `Changelog.lua`, and bump `## Version:` in `SeekerLFG.toc` to match.
2. Commit, then tag and push: `git tag v0.9.1` and `git push origin main v0.9.1`.
3. The workflow builds `SeekerLFG-0.9.1.zip` (one `SeekerLFG/` folder, made with `git archive`) and publishes a GitHub release with that zip and the notes from `Changelog.lua`. A version containing `alpha` or `beta` is marked as a pre-release.

If the tag doesn't match the TOC version, the release fails, so the two can't drift apart.
