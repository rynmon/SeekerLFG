-- Seeker LFG: translations. Every piece of text Seeker shows is written in English in the code as
-- L["..."]; this table gives it in the client's language when there's a translation, else the
-- English itself. Where the game has its own wording (its global strings), Seeker uses that first.
--
-- To translate: add a block for your locale below, mapping each English string (exactly as it is
-- in the code, %s and %d included) to its translation. Leave out anything you haven't translated;
-- it stays in English. Keep [placeholders] such as [dungeon] in English in the default messages:
-- they're what Seeker looks for when filling a message in.
--
--     ns.AddTranslations("deDE", {
--         ["Request to join"] = "Beitrittsanfrage",
--     })
local _, ns = ...

local L = setmetatable({}, {
    __index = function(_, english) return english end, -- untranslated: the English
})
ns.L = L

function ns.AddTranslations(locale, strings)
    if GetLocale and GetLocale() ~= locale then return end
    for english, translated in pairs(strings) do
        if type(translated) == "string" and translated ~= "" then rawset(L, english, translated) end
    end
end

-- Translations go here, one ns.AddTranslations block per locale.
