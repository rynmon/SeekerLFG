# Testing Seeker LFG

Run the self-test first, then check the flows that need real players.

## 1. Self-test (a minute, alone)

Type `/seeker selftest`. It checks the game functions, templates, art, fonts and game data that Seeker uses, and what it works with. Every line should pass, except possibly the game's description box, which loads the first time the game's Looking for Group window opens. `/seeker selftest all` lists every check.

## 2. Browsing (alone)

- [ ] `/seeker` opens the window at the game's window height. The eye portrait is still, and the three side tabs fill their frames.
- [ ] Pick Dungeons and press Search. Groups appear on the left and players on the right.
- [ ] Rows show the name, then the dungeon with the zone, then the playstyle. Nothing is cut off with "…".
- [ ] Hover a group: every member with level, role and zone, and the note if the group wrote one.
- [ ] Turn on Full XP / Any XP / Show all, and check the level colours change.
- [ ] Check Hide far away: anyone shown in red, on another continent, disappears.
- [ ] Cog > Sort: each order changes the lists.
- [ ] A listing with a friend or guildmate shows the badge and sorts near the top.

## 3. Alerts (alone)

- [ ] Bind Options > Keybindings > Seeker LFG > Search again. Close the window and press the key a few times over several minutes: new matches are listed in chat with a sound.
- [ ] Cog > Alerts > Only ones with full XP: only full-XP listings are announced.

## 4. Listing yourself (alone)

- [ ] List yourself tab: pick Dungeons, tick a dungeon, pick a playstyle, and type a description.
- [ ] A dungeon you'd get no XP from shows "No XP" and a warning above the List button.
- [ ] List self: the eye starts watching, the browse tab shows "Your listing" at the top, and the game's own window shows the same listing and description.
- [ ] Update (change a dungeon), then Delist: both work, and the eye stops.

## 5. With other players

- [ ] Request to join on a group: a whisper to the leader opens with your message filled in (or in Whisper Messenger, if it's installed).
- [ ] Invite on a solo player: they get the invite, and your invite message if you've set one in Messages.
- [ ] In a party, as leader: the List yourself tab shows the role dropdown and Role check, and listing works as "List group".
- [ ] In a party, not as leader: the List yourself tab shows the read-only view.
- [ ] A group of more than five (a raid listing): the row shows counts per role, and the tooltip groups more than ten members by role.

## 6. Who

- [ ] Who tab: search a zone name. Results appear in Seeker, and the game's own window doesn't pop open.
- [ ] Filter > Class: untick one class and search again.
- [ ] Invite and right-click work on a result.

## 7. Replace mode

- [ ] Cog > Replace the game's Looking for Group window: the game's keybind and menu button now open Seeker, and Shift opens the game's.

## 8. Other languages (if you can)

- [ ] On a non-English client, `/seeker selftest` shows every dungeon with a known continent, and far-away players turn red.
