-- Seeker LFG's changelog, newest first. The release workflow turns the entry for the TOC's
-- version into the GitHub release notes (.github/scripts/release-notes.lua).
-- Each release: { version, date, sections = { { heading, { { lead, text }, ... } }, ... } }.
-- Add a new entry at the top for every release, with the same version as the TOC.

local _, ns = ...

ns.CHANGELOG = {
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
