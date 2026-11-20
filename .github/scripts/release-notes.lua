-- Print one release's notes from Changelog.lua as Markdown, for the GitHub release.
-- Usage (Lua 5.1, from the repository root): lua5.1 .github/scripts/release-notes.lua 0.9.0
-- Exits non-zero if Changelog.lua has no entry for that version.

local wanted = arg[1]
if not wanted then
	io.stderr:write("usage: release-notes.lua <version>\n")
	os.exit(2)
end

local ns = {}
local chunk = assert(loadfile("Changelog.lua"))
chunk("SeekerLFG", ns) -- the addon's own `local ADDON, ns = ...`

for _, release in ipairs(ns.CHANGELOG) do
	if release.version == wanted then
		print("Released " .. release.date .. ".")
		print()
		for _, section in ipairs(release.sections) do
			print("### " .. section[1])
			print()
			for _, bullet in ipairs(section[2]) do
				print("- **" .. bullet[1] .. "** " .. bullet[2])
			end
			print()
		end
		print("Install: unzip into `World of Warcraft\\_forever_\\Interface\\AddOns\\` so you have an `AddOns\\SeekerLFG` folder, then restart the game. Type `/seeker` to open it.")
		os.exit(0)
	end
end

io.stderr:write("Changelog.lua has no entry for version " .. wanted .. "\n")
os.exit(1)
