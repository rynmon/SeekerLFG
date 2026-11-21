-- Seeker LFG's changelog, newest first. The release workflow turns the entry for the TOC's
-- version into the GitHub release notes (.github/scripts/release-notes.lua).
-- Each release: { version, date, sections = { { heading, { { lead, text }, ... } }, ... } }.
-- Add a new entry at the top for every release, with the same version as the TOC.

local _, ns = ...

ns.CHANGELOG = {
	{
		version = "0.9.6",
		date = "21 November 2026",
		sections = {
			{ "Changed", {
				{ "Colour-coded locations.", "Every member's zone in a tooltip is now coloured for the group's dungeon: green with the dungeon's icon when they're inside it, white on the same continent, red on another continent." },
				{ "Your party's zones.", "Your party card reads each member's zone from the game's group roster, so it's known even when they're far away or in a dungeon." },
				{ "Lookups in progress.", "Members whose zone is being looked up say looking up... instead of ?, and the tooltip explains that lookups run as you click or scroll." },
			} },
			{ "Fixed", {
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
