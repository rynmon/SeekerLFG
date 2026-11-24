-- Seeker LFG's changelog, newest first. The release workflow turns the entry for the TOC's
-- version into the GitHub release notes (.github/scripts/release-notes.lua).
-- Each release: { version, date, sections = { { heading, { { lead, text }, ... } }, ... } }.
-- Add a new entry at the top for every release, with the same version as the TOC.

local _, ns = ...

ns.CHANGELOG = {
	{
		version = "1.0.0",
		date = "24 November 2026",
		sections = {
			{ "New", {
				{ "Groups and players from chat.", "Groups (LFM) and players (LFG) posting in chat channels for a dungeon now appear beside the group finder's listings, marked chat, with the same filters: \"LF2M SM Arm need heal\" shows as a group for the Scarlet Armory needing a healer. Their level and zone are found with the map button on their card. Cog > Chat posts switches it off, keeps it to the LookingForGroup channel, or announces new ones. English messages only." },
				{ "See whom you've asked.", "Cards now say when you've asked a group to join or invited a player (\"Requested 2m ago\"), and what came of it: replied, declined, already in a group, or joined." },
				{ "Fill my group.", "For leaders: one click (cog menu, your party card, or /seeker fill) shows the players who play the roles your group is missing, with full XP for it." },
				{ "Keep results fresh.", "Once results are 30 seconds old, your next click or key press with the window open searches again, so the lists stay current while you play. Cog > Keep results fresh switches it off." },
				{ "Notes on players.", "Right-click a card > Add a note (\"great tank\"): it shows on their cards and tooltips, wherever they turn up. /seeker note works too." },
				{ "Filter setups.", "Save your filters as a setup (\"Tanking on my warrior\") and switch back to it in one click: cog menu > Filter setups, or /seeker setup." },
				{ "Each character its own.", "What you browse (category and activities) and the level and role filters are now kept per character, so an alt doesn't open on your main's dungeons." },
				{ "Hide players.", "Right-click a listing > Hide to stop seeing that player's listings. Cog > Hidden lists everyone you've hidden; click a name to show them again. Players on your ignore list are hidden too (switch it off in Cog > Hidden)." },
				{ "Hide by word.", "Hide listings whose title or note mentions words you pick, such as \"wts, boost\": Options > AddOns > Seeker LFG, or /seeker hidewords." },
				{ "Sort Who by any column.", "Click a column heading on the Who page to sort by it, and again to reverse. The Who page's filters and sort are now kept between sessions, and Filter > Clear all filters resets them." },
				{ "Minimap button collectors and broker bars.", "Seeker's minimap button is now a standard one (LibDBIcon), so addons that gather minimap buttons into one bar pick it up, and Seeker shows in broker bars such as Titan Panel, ChocolateBar and Bazooka (click to open, right-click for options, and it says when you're listed). It's still the game's LFG eye, and keeps its place on the minimap." },
				{ "/seeker help.", "Lists every command. A command Seeker doesn't know now says so instead of opening the window." },
				{ "Ready for translations.", "All of Seeker's own text can now be translated (Locale.lua). It uses the game's wording wherever the game has it." },
			} },
			{ "The window", {
				{ "Taller window, more cards.", "The corner grip now makes the window taller, so both lists show more cards; Ctrl + mouse wheel still scales everything. /seeker reset puts it back." },
				{ "No more cut-off bottom line.", "When it doesn't fit, the bottom line drops its least important parts first (your keybind, then your party) instead of cutting off the end, and hovering it shows all of it." },
				{ "More room on cards.", "A card's buttons are shorter and sit beside its third line, so the dungeon and where the leader is stay readable while you point at it, and long names no longer run into a raid's role counts." },
				{ "One empty list, one wide list.", "When there are no groups (or no players), the other list takes the room." },
				{ "Easier to read.", "Greyed-out cards are greyed text and icons rather than faded, so they're still readable, and an option shows XP as a tick, question mark or cross beside the colour (Cog menu or Options), for when green and red are hard to tell apart." },
				{ "Smaller fixes.", "The side tabs never go off the screen's edge, a long warning on the List yourself page stays on one line (hover it for the rest), card tooltips say what right-click does, and the Who page's sorted column shows the game's own sort arrow." },
			} },
			{ "Like the game's own window", {
				{ "Each activity's own display.", "Rows show a listing's party the way the game shows that activity: its note (for activities listed by description), a player count, class icons, role counts or role seats, or nothing." },
				{ "The game's order.", "A new sort, Best fit for my roles: groups with a seat for a role you play first, then bigger groups, then ones needing a tank or healer; and players who fill a role your party lacks. Best XP first now uses it to break ties." },
				{ "The game's activity groups.", "Cog > Group activities by: the game's own groups (with one box to tick a whole group) or, as before, what they'd give you in XP. It applies to the Browse activity menu and the List yourself page." },
				{ "Delisted listings.", "A listing taken down since your search stays in the list, greyed out at the bottom and marked Delisted, instead of vanishing. Cog > Sort > Grey out listings outside the picked activities keeps those too, as the game does." },
				{ "Your listing's activities.", "Listings that share activities with yours name only those, in blue, and tooltips group activities as the game does with yours in blue. The minimap tooltip groups them too and shows your description." },
				{ "When you can't use the group finder.", "When the game doesn't let you use the group finder yet (your level, for example), Seeker says why instead of opening, as the game's window does. The Who tab still opens." },
				{ "Who list details.", "Hover a Who row whose name, zone or guild is cut off to see it in full." },
			} },
			{ "Fixed", {
				{ "Member locations, when you ask.", "Where a group's members are is now looked up only for the groups you ask about: point at a card and click its map button. It checks the group's zone first (one /who that usually finds everyone gathered there), then each member by their first name (the name /who knows them by), trying again when the game drops a lookup; the rest run as you click or press keys with Seeker open. Searching no longer looks up every member of every group. Tooltips say whether a member is being looked up, queued, or wasn't found (offline, or hidden from /who)." },
				{ "Alerts after changing category.", "Switching category (or loosening a filter) announced every listing as new. Each search now has its own memory, so only listings that turn up later are announced." },
				{ "Who results replaced.", "Coming back to the Who tab could show a single player from a background member lookup instead of your search. The page now keeps your results." },
				{ "No more opening the game's window first.", "The description box, Open the game's Looking for Group window, and searching your new listing all needed the game's window opened once. Seeker now loads it itself." },
				{ "Placeholders from the buttons.", "Clicking a placeholder in Messages put it in the box but didn't save it unless you typed something too." },
				{ "Playstyle while listed.", "The game doesn't change a listing's playstyle, so the dropdown is now greyed out while you're listed instead of seeming to work." },
				{ "Your party's level everywhere.", "The activity menu, the status line and the List yourself warnings now judge XP by your party's highest level, as the lists already did." },
				{ "Unsaved listing changes.", "Switching tabs while listed no longer throws away changes you haven't posted." },
				{ "Your own /who.", "A /who you type while Seeker is looking someone up now answers in chat as usual." },
				{ "Invite.", "Invite is greyed out, saying why, when you can't invite (not the leader or an assistant) or your raid is full. Inviting a sixth player offers to turn your party into a raid, as the game does. The Who page invites the way the game's Who list does." },
				{ "Smaller fixes.", "[name] in messages is your full name; long messages are never cut mid-character; expired lockouts no longer count as saved; the Search again key picks Dungeons first, as the window does; the cog's tooltip lists what's in it." },
			} },
		},
	},
	{
		version = "0.9.6",
		date = "24 November 2026",
		sections = {
			{ "Changed", {
				{ "Colour-coded locations.", "Every member's zone in a tooltip is now coloured for the group's dungeon: green with the dungeon's icon when they're inside it, white on the same continent, red on another continent." },
				{ "Your party's zones.", "Your party card reads each member's zone from the game's group roster, so it's known even when they're far away or in a dungeon." },
				{ "Lookups in progress.", "Members whose zone is being looked up say looking up... instead of ?, and the tooltip explains that lookups run as you click or scroll." },
			} },
			{ "Fixed", {
				{ "Blocked searches.", "Picking a category could fail with an action blocked error: the game can block a search an addon makes from inside a menu. Picking now lights up Search Again, and your next click in the window searches. Member lookups also leave the search menus, Search Again and the List yourself page alone." },
				{ "Full names for your party.", "Your party card and the listing preview showed only first names (\"Platinum\" instead of \"Platinum Andy\"). They now use the game's own name formatting, with surnames, as its party frames do." },
			} },
		},
	},
	{
		version = "0.9.5",
		date = "20 November 2026",
		sections = {
			{ "Changed", {
				{ "Search Again.", "The Search button is now the game's own Search Again button: the square button with the blue refresh arrow, as in its Looking for Group window." },
				{ "Your party, always shown.", "When you're in a party (or listed), a card at the top shows your party: everyone's level, role and zone, and whether you're listed and for what, even when your search doesn't cover your listing. The leader can List group or Edit listing from it." },
				{ "XP counts your party.", "With Count my level on, the XP colours now use your party's highest level, not just yours, since that's what a new member would group with." },
				{ "Party on the bottom line.", "The status line says when you're in a party or raid, how big it is, and whether you lead it." },
			} },
		},
	},
	{
		version = "0.9.4",
		date = "20 November 2026",
		sections = {
			{ "Fixed", {
				{ "Cards past the window's edge.", "Opening the filters could leave the lists drawing cards below the bottom of the window. They now recount what fits every time they redraw, and never draw outside the window." },
				{ "Picking one dungeon.", "The bottom line no longer raises an error when a single dungeon is picked in the activity menu." },
			} },
		},
	},
	{
		version = "0.9.3",
		date = "20 November 2026",
		sections = {
			{ "New", {
				{ "Friends and guildmates.", "Listings with your friends or guildmates in them show a badge, sort near the top, and say who in the tooltip." },
				{ "Alerts.", "When a search turns up new groups or players that pass your filters, they're listed in chat with a sound, and the game's icon flashes if it's in the background. Bind Search again (Keybindings > Seeker LFG) to search with the window closed. Change it in Cog > Alerts." },
				{ "Sort.", "Cog > Sort: best XP, newest, oldest, level either way, or biggest groups first." },
				{ "A clearer activity list.", "The activity menu is now sorted into Full XP for you, Above your level, Some XP and No XP for you, lowest level first, with level ranges in their own column. One click picks every dungeon with full XP for you." },
				{ "Warnings when listing.", "Dungeons you'd get no XP from are marked, and before you post you're told about those and any instance you're saved to." },
				{ "A fuller List yourself page.", "The category buttons fill the column and say how many activities are at your level (and how many give you full XP), and a preview shows how your listing will look to other players as you fill it in." },
				{ "Where every member is.", "The game only shares where a group's lister is, so Seeker finds the rest by itself: members of the groups in your results are looked up quietly as you use the window (the game allows one /who every few seconds, from a click or key press), groups you hover first. Zones are also remembered from listings, your friends list, your guild roster and any /who, and tooltips show each member's zone with how old it is." },
				{ "A calmer Browse page.", "Shorter cards fit more on screen, Players gets a bit more of the width than Groups, each card's corner shows the group's size and how long ago it was listed, a card's buttons show when you point at it, the level's colour is the one XP signal (the stripe is gone), hovering a filter no longer looks like switching it on, the class filter is a compact dropdown, Filters is a toggle that shows how many are on, and the bottom line says when you last searched, what's shown and your Search again key." },
				{ "The game's minimap eye.", "The minimap button is now the game's own LFG eye: still, then watching while you're listed. Its tooltip says what you're listed for, and right-click offers Edit listing and Delist." },
				{ "Options page.", "Every setting is also in the game's Options > AddOns > Seeker LFG." },
				{ "Self-test.", "/seeker selftest checks everything Seeker relies on in the game, for bug reports." },
			} },
			{ "Fixed", {
				{ "Any language.", "Far-away players are now spotted on every client language: a dungeon's continent comes from the game's map data, not its English name." },
			} },
		},
	},
	{
		version = "0.9.2",
		date = "20 November 2026",
		sections = {
			{ "Your own messages", {
				{ "Request to join, your way.", "Write your own Request to join message in the cog menu > Messages (or /seeker messages). It still opens ready to send in a whisper, so you press Enter." },
				{ "A message with your invites.", "Set an invite message and it's whispered to players when you click Invite. Leave it empty for a plain invite." },
				{ "Placeholders.", "[level], [class], [roles], [dungeon], [name] (you), [target] (them) and [zone] are filled in for each listing. Click one in the Messages window to add it, and a preview shows exactly what will be sent." },
			} },
		},
	},
	{
		version = "0.9.1",
		date = "20 November 2026",
		sections = {
			{ "Better tooltips", {
				{ "Everyone in the group.", "A group's tooltip now lists every member (leader first, with the crown), each with their level, role and where they are, read fresh from the game as its own tooltip does." },
				{ "The group's note.", "The listing's note now shows in the tooltip. It was missing before." },
				{ "Where each player is.", "Every player's zone and continent are on their tooltip line, red when they're on the wrong continent for their dungeon and green when they're already there." },
				{ "Sturdier.", "If one part of a tooltip can't be read, the rest still shows." },
			} },
			{ "Big groups", {
				{ "Condensed by role.", "Groups of more than five now show a count per role in the list instead of five seats, and groups of more than ten list their members under Tanks, Healers and DPS in the tooltip." },
			} },
		},
	},
	{
		version = "0.9.0",
		date = "20 November 2026",
		sections = {
			{ "First release", {
				{ "Groups and players side by side.", "Seeker LFG replaces WoW Forever's Looking for Group window, at the game's own size, with groups on the left and solo players on the right." },
				{ "Keep your XP.", "Kill XP is lost when the highest-level party member is more than 12 levels above the mob. Every listing is coloured by what it means for you (full XP, partial XP, no XP), and the Full XP / Any XP filter hides the rest." },
				{ "See where players are.", "Each player's zone shows under their name, in red when they're on another continent from the dungeon they listed for, and Hide far away drops them from the list." },
				{ "Everything the game's window does.", "List yourself or your group (playstyle, voice chat, description, roles, new player friendly), browse with the game's own search rules, invite, report, and a Who tab, all in one window." },
				{ "Filters.", "Level range, group needs a tank / healer / DPS, player can tank / heal / DPS, player class, hide full groups." },
				{ "Request to join.", "Forever has no applications, so this opens a whisper to the leader with your level, class, roles and the dungeon ready to send." },
				{ "Whisper Messenger.", "When it's installed, whispers open there instead (switch it off in the options)." },
				{ "Replace the game's window.", "An option opens Seeker wherever the game would open its own Looking for Group window. Hold Shift for the game's." },
			} },
		},
	},
}
