# Seeker LFG

**Looking for Group for WoW Forever, with groups and players side by side and filters that keep your dungeon runs earning XP.**

Seeker LFG replaces Forever's Looking for Group window with one that looks and feels like the game's own, but shows far more. It also does everything the game's window does, so you never need to open that window again.

![Browsing groups and players side by side](assets/screenshots/browse.png)

## Why Seeker

- **Keep your XP.** Kill XP is lost when the highest-level party member is more than 12 levels above the mob. Every group and player is checked against that rule, and the level is coloured: green for full XP, yellow for partial XP, red for none. One click hides everything that would cost you XP.
- **See where people are.** Every player's zone is shown, in red when they're on the wrong continent for their dungeon (someone in Kalimdor queued for the Deadmines) and in green when they're already there. Group tooltips show where every member is, too.
- **Groups and players side by side,** in the game's own style, with each party's roles at a glance.
- **Everything the game's window does:** list yourself or your group, browse, invite, report, and search /who.

## Browse

- **Groups on the left, players on the right.** Each card shows the name and level, the dungeon and zone, the playstyle, the party's roles (or the player's), the group's size and how long ago it was listed.
- **Filters:** XP (full only, any, or all), level range, groups that need a tank / healer / DPS, players who can tank / heal / DPS, player class, hide full groups, and hide far-away players.
- **Activities by XP:** the activity menu sorts dungeons into Full XP for you, Above your level, Some XP and No XP for you. One click picks every dungeon with full XP for you.
- **Friends and guildmates:** listings with them in get a badge and sort near the top.
- **Sort:** best XP, newest, oldest, level either way, or biggest groups first.
- **Tooltips:** every member with level, role and location, the group's note, playstyle, voice chat and bosses already killed.
- **Request to join.** Forever has no "apply to group", so this opens a whisper to the leader with your request already written; press Enter to send it.
- **Alerts:** new groups and players that pass your filters are announced in chat with a sound. Bind **Search again** (Keybindings > Seeker LFG) to check without opening the window.

## List yourself

![Listing yourself](assets/screenshots/listing.png)

Pick a category, tick what you're listing for, and choose a playstyle, voice chat, a description, your roles and "new player friendly". A preview shows how other players will see your listing. When you're in a group, you get the role dropdown and a role check, and only the leader can change the listing.

![Choosing activities, sorted by XP](assets/screenshots/listing-activities.png)

Activities are grouped by what they'd give you in XP, so you can see straight away which dungeons are worth listing for. Dungeons you'd get no XP from, and instances you're saved to, are flagged before you post.

## Who

A /who search with class, race, zone and sort filters, and an invite button for each player.

## Your own messages

**Messages** in the cog menu, or `/seeker messages`, lets you write your own **Request to join** message, and an **Invite** message that's whispered to players when you invite them. These placeholders are filled in for each listing:

| Placeholder | Becomes |
|---|---|
| `[level]` | your level |
| `[class]` | your class |
| `[roles]` | the roles you've ticked, e.g. Tank/Healer |
| `[dungeon]` | the dungeon they're listed for |
| `[name]` | your name |
| `[target]` | their name |
| `[zone]` | the zone you're in |

`Hey [target], [level] [class] here, free for [dungeon]?` becomes "Hey Skeron, 21 Mage here, free for Deadmines?". The window shows a preview as you type.

## Install

1. Download `SeekerLFG-x.y.z.zip` from [Releases](../../releases).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\` so that you have an `AddOns\SeekerLFG` folder.
3. Restart the game, then type `/seeker`.

## Using it

- Open it with `/seeker` (or `/slfg`), the minimap eye, or the addon compartment. The minimap eye watches while you're listed, like the game's own.
- To use Seeker for good, open the cog menu and turn on **Replace the game's Looking for Group window**. The game's keybind and menu button then open Seeker, and holding Shift opens the game's window instead.
- Drag the corner grip, or use Ctrl + mouse wheel, to resize the window.
- Every setting is also in **Options > AddOns > Seeker LFG**.
- If you have **Whisper Messenger**, whispers open there.

| Command | What it does |
|---|---|
| `/seeker` | Open or close the window |
| `/seeker messages` | Your Request to join and invite messages |
| `/seeker settings` | The options page |
| `/seeker replace` | Switch replacing the game's window on or off |
| `/seeker minimap` | Show or hide the minimap button |
| `/seeker reset` | Reset the window's position and size |
| `/seeker selftest` | Check everything Seeker relies on in the game (for bug reports) |

## Good to know

- **Mob levels are estimates,** taken from each dungeon's suggested level range.
- **Member locations:** the game only shares where a group's lister is. Seeker finds the other members with quiet /who lookups as you use the window, one every few seconds, since the game only allows /who from a click or key press. It also remembers zones from your friends list, guild roster and any /who.
- **Descriptions** are typed into the game's own description box, shown inside Seeker's window. The game only accepts listing text typed there.

## Bugs and ideas

Open an [issue](../../issues). For bugs, include the output of `/seeker selftest`.
