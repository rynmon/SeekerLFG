# Testing Seeker LFG

Run the self-test first, then check the flows that need real players.

## 1. Self-test (a minute, alone)

Type `/seeker selftest`. It checks the game functions, templates, art, fonts and game data that Seeker uses, and what it works with. Every line should pass. (Seeker loads the game's group finder itself; if you reloaded in combat, the description box check passes once combat ends.) `/seeker selftest all` lists every check.

## 2. Browsing (alone)

- [ ] The minimap button shows the eye (still, then watching while listed), opens Seeker on click and the options on right-click, keeps its old position, and `/seeker minimap` hides and shows it.
- [ ] With a minimap button collector (e.g. MinimapButtonButton, MBB) the eye is collected with the rest; with a broker bar (Titan Panel, ChocolateBar) Seeker LFG appears there, says Listed while you're listed, and clicks work.
- [ ] Drag the corner grip down: the window gets taller and both lists show more cards; the List yourself and Who pages fill the height too. `/reload` keeps the height; `/seeker reset` restores it.
- [ ] Drag the window to the screen's right edge: the side tabs stay on screen.
- [ ] Make the bottom line long (in a party, one dungeon picked, Search again bound): it drops the keybind, then the party, rather than cutting off; hovering it shows every part.
- [ ] Point at a group card: its buttons appear beside line 3, and line 2 (dungeon and zone) stays whole.
- [ ] Search a category with no solo players: the Groups list takes most of the width.
- [ ] Cog > Show XP as symbols too: each level gets a tick, question mark or cross, and so does the colour key.
- [ ] A delisted card reads as grey text and icons (not faded), with Delisted in red.
- [ ] Who: the sorted column shows a small arrow, up for ascending and down for descending.
- [ ] `/seeker` opens the window at the game's window height. The eye portrait is still, and the three side tabs fill their frames.
- [ ] Pick Dungeons and press Search. Groups appear on the left and players on the right.
- [ ] Rows show the name, then the dungeon with the zone, then the playstyle. Nothing is cut off with "…".
- [ ] Hover a group: every member with level, role and zone, and the note if the group wrote one.
- [ ] Point at a group card with unknown members: a map button shows beside the whisper button. Click it: a member says "looking up..." at once, and members standing with the leader all get their zone together. The rest follow about every five seconds as you press keys or click. Searching alone looks nobody up.
- [ ] A member who's offline ends up saying "not found (offline?)" instead of "looking up..." forever.
- [ ] Walking with the window open: movement keys still work normally (Seeker only listens to keys, it never takes them).
- [ ] Turn on Full XP / Any XP / Show all, and check the level colours change.
- [ ] Check Hide far away: anyone shown in red, on another continent, disappears.
- [ ] Cog > Sort: each order changes the lists.
- [ ] A listing with a friend or guildmate shows the badge and sorts near the top.
- [ ] Cog > Sort > Best fit for my roles: with Tank ticked on your List yourself page, groups with a free tank seat come first, then bigger groups.
- [ ] Cog > Group activities by > The game's own groups: the activity menu and the List yourself page show the game's groups, and ticking a group ticks all of it. Switch back to XP: the XP sections return.
- [ ] A listing that's taken down while you watch stays in the list, greyed out at the bottom, saying Delisted; hovering says so and right-click does nothing.
- [ ] Cog > Sort > Grey out listings outside the picked activities, then pick one activity: other listings stay, greyed out, at the bottom.
- [ ] A Questing or Custom listing (activities listed by description) shows its note on the card's third line instead of party seats.
- [ ] While listed: a listing sharing two of your activities says "2 matching activities" in blue, and its tooltip shows those activities in blue under the game's group names.
- [ ] While listed: the minimap tooltip groups your activities and shows your description.
- [ ] Right-click a listing > Hide: it disappears, and Cog > Hidden lists the player. Click their name there: they're back.
- [ ] `/seeker hidewords wts`: listings with "wts" in the title or note disappear; `/seeker hidewords` brings them back. Filters shows one more filter while words are set.
- [ ] Someone on your ignore list doesn't show (Cog > Hidden > Hide players on my ignore list).
- [ ] `/seeker help` lists every command; `/seeker nonsense` says it's unknown instead of opening the window.

## 3. Alerts (alone)

- [ ] Bind Options > Keybindings > Seeker LFG > Search again. Close the window and press the key a few times over several minutes: new matches are listed in chat with a sound.
- [ ] Cog > Alerts > Only ones with full XP: only full-XP listings are announced.
- [ ] Switch category (Dungeons to Raids) and search: nothing is announced for that first search, only listings that appear on later ones.
- [ ] Loosen a filter (Full XP to Show all) and search again: listings that were there all along aren't announced.

## 3b. New in 1.0 (alone, then in a party)

- [ ] `/seeker chattest LF2M SM arm need heal` reads it as lfm, Scarlet Armory, healer, need 2. Try a few real messages from your server's LookingForGroup channel.
- [ ] Browse Dungeons while people post LFM/LFG in chat: their cards appear marked chat, groups on the left and players on the right; the hover shows their message and channel; their card has a map button that finds their level and zone.
- [ ] Cog > Chat posts > Only the LookingForGroup channel: posts from General and world stop appearing. Switching chat posts off removes them.
- [ ] Request to join a group: its card says "Requested ...". When they whisper back it says "Replied". Invite a player who declines: "Declined".
- [ ] Right-click a card > Add a note: the note icon shows on their card and the note in the tooltip, also as a member of another group. `/seeker note <name>` removes it.
- [ ] Set some filters, Cog > Filter setups > Save current filters... "Test"; change the filters; pick "Test": they all come back, including the checkboxes and level boxes.
- [ ] In a party missing a healer, as leader: Cog > Fill my group (or right-click your party card): Player can > Heal is on, XP is Full XP, and the next click searches.
- [ ] With Keep results fresh on, wait 30s with the window open, then press a key: it searches again (the bottom line resets to "Searched 0s ago").
- [ ] Browse on one character, log onto an alt: the alt opens on its own category and activities; back on the first, its picks are still there.
- [ ] A fresh install (no saved settings) prints the two welcome lines once, a few seconds after login.

## 4. Listing yourself (alone)

- [ ] List yourself tab: pick Dungeons, tick a dungeon, pick a playstyle, and type a description.
- [ ] A dungeon you'd get no XP from shows "No XP" and a warning above the List button.
- [ ] List self: the eye starts watching, the browse tab shows "Your listing" at the top, and the game's own window shows the same listing and description.
- [ ] Update (change a dungeon), then Delist: both work, and the eye stops.
- [ ] Right after listing, Search Again is lit; the next click searches your listing's activities.
- [ ] While listed, the playstyle dropdown is greyed out and its tooltip says to delist to change it.
- [ ] While listed, tick another dungeon, switch to Browse and back: your unsaved change is still there.
- [ ] Straight after logging in (without opening the game's window), the description box is there.
- [ ] Messages: click a placeholder button, close the window and reopen it: the placeholder is still in the message.

## 5. With other players

- [ ] Request to join on a group: a whisper to the leader opens with your message filled in (or in Whisper Messenger, if it's installed).
- [ ] Invite on a solo player: they get the invite, and your invite message if you've set one in Messages.
- [ ] In a party, as leader: the List yourself tab shows the role dropdown and Role check, and listing works as "List group".
- [ ] In a party, not as leader: the List yourself tab shows the read-only view.
- [ ] In a party of five, as leader: Invite a solo player; the game offers to convert the party to a raid.
- [ ] In a party, not as leader or assistant: Invite is greyed out, and its tooltip says why.
- [ ] In a party with a higher-level member: the activity menu's sections, the status line and the List yourself warnings use their level.
- [ ] A group of more than five (a raid listing): the row shows counts per role, and the tooltip groups more than ten members by role.

## 6. Who

- [ ] Who tab: search a zone name. Results appear in Seeker, and the game's own window doesn't pop open.
- [ ] Filter > Class: untick one class and search again.
- [ ] Invite and right-click work on a result.
- [ ] Hover a row whose name, zone or guild is cut off: a tooltip shows it in full.
- [ ] Click each column heading: the list sorts by it, and a second click reverses it. Filter > Sort > Ascending / Descending do the same.
- [ ] `/reload`: the class, race and zone filters and the sort are as you left them.
- [ ] Search, switch to Browse and hover a few groups (member lookups run), then go back to Who: your results are still there.
- [ ] Type `/who` in chat while Browse is open: the answer shows in chat as usual.

## 7. Replace mode

- [ ] Cog > Replace the game's Looking for Group window: the game's keybind and menu button now open Seeker, and Shift opens the game's.

## 8. Other languages (if you can)

- [ ] On a character below the level the group finder needs: `/seeker` says why instead of opening (the Who tab still opens from a /who), and `/seeker selftest` reports it.
- [ ] On a non-English client, `/seeker selftest` shows every dungeon with a known continent, and far-away players turn red.
