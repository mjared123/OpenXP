local root = ...
local messages = {}
function GetLocale() return "frFR" end
function LibStub(name)
    if name == "AceAddon-3.0" then
        return { NewAddon = function(_, addon) return addon end }
    end
    assert(name == "AceLocale-3.0")
    return { NewLocale = function() return messages end, GetLocale = function() return messages end }
end
format = string.format
ACCEPT = "Accepter"

local addon = {}
for _, file in ipairs({
    "locale/enUS.lua", "locale/frFR.lua", "locale/frFR_guide.lua", "locale/NPCnames.lua", "Locale.lua",
}) do
    assert(loadfile(root .. "/" .. file))("OpenXP", addon)
end

local locale = addon.locale
local rudra = "Rudra Amberstill"
assert(locale.Get("You get this quest at this step") == "Vous obtenez cette quête à cette étape.")
assert(locale.Get("EARLIER STEPS") == "Étapes précédentes")
assert(addon.GetCreatureName(rudra) == "Rudra Distillambre")

addon.game = "FOREVER"
assert(addon.GetCreatureName(rudra) == rudra)

local names = { [1265] = rudra, [1376] = "Beldin Steelgrill", [233] = "Saldean le fermier" }
LibQuestieDB = {
    Npc = { name = function(id) return names[id] end },
    Quest = { name = function(id) if id == 9 then return "Titre de QuestieDB" end end },
}
local function TalkTo(name)
    return "|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_" .. name .. "|r"
end
for _, name in ipairs({ rudra, "Beldin Steelgrill", "Saldean le fermier" }) do
    local original = name == "Saldean le fermier" and "Farmer Saldean" or name
    assert(addon.GetCreatureName(original) == name)
    assert(locale.GuideText(TalkTo(original)):find("Parlez à |cRXP_FRIENDLY_" .. name .. "|r", 1, true))
end
assert(addon.GetCreatureName("Farmer Saldean::233") == "Saldean le fermier::233")
assert(addon.GetCreatureName("Unknown NPC") == "Unknown NPC")
assert(locale.GuideQuestName(9) == "Titre de QuestieDB")
C_QuestLog = { GetTitleForQuestID = function(id) if id == 9 then return "Titre du journal" end end }
assert(locale.GuideQuestName(9) == "Titre du journal")
assert(locale.GuideQuestName(36) == "Le ragoût de la marche de l’Ouest")

local spyLoot = "Kill |cRXP_ENEMY_Dark Iron Spies|r. Loot them for the |T237385:0|t[|cRXP_LOOT_Dark Iron Map|r]"
local map = "|T237385:0|t[|cRXP_LOOT_Carte sombrefer|r]"
assert(locale.GuideText(spyLoot) == "Tuez les |cRXP_ENEMY_espions Sombrefer|r et récupérez " .. map .. " sur eux.")
local useMap = "|cRXP_WARN_Use the|r |T237385:0|t[|cRXP_LOOT_Dark Iron Map|r] |cRXP_WARN_to start the quest|r"
assert(locale.GuideText(useMap) == "|cRXP_WARN_Utilisez|r " .. map .. " |cRXP_WARN_pour lancer la quête.|r")
local ambusherLoot = "Kill |cRXP_ENEMY_Rockjaw Ambushers|r. Loot them for their |cRXP_LOOT_Stolen Blasting Powder|r"
assert(locale.GuideText(ambusherLoot) ==
    "Tuez les |cRXP_ENEMY_embusqués Mâcheroc|r et récupérez |cRXP_LOOT_Poudre explosive volée|r sur eux.")
assert(locale.GuideQuestName(96391) == "La carte souterraine")

LibQuestieDB.Item = { name = function(id) if id == 274268 then return "Nom dans QuestieDB" end end }
C_Item = { GetItemInfo = function() return "" end }
assert(locale.GuideTerm("Dark Iron Map") == "Nom dans QuestieDB")
C_Item.GetItemInfo = function(id) if id == 274268 then return "Nom dans le client" end end
assert(locale.GuideTerm("Dark Iron Map") == "Nom dans le client")

names[3077] = "Mahnott Roughwound"
names[1256] = "Responsable Thesten"
assert(locale.GuideText(TalkTo("Mahnott")):find("Mahnott Roughwound", 1, true))
assert(addon.GetCreatureName("Other display name::1256") == "Responsable Thesten::1256")
assert(locale.GuideText("|cRXP_ENEMY_Owls|r") == "|cRXP_ENEMY_hiboux|r")
assert(locale.GuideText("|cRXP_LOOT_Hides|r") == "|cRXP_LOOT_peaux|r")

LibQuestieDB.Item.name = function(id) if id == 280042 then return "Tattered Spellbook" end end
LibQuestieDB.Object = { name = function(id) if id == 671518 then return "Grimoire en lambeaux" end end }
assert(locale.GuideText("|cRXP_PICK_Tattered Spellbook|r") == "|cRXP_PICK_Grimoire en lambeaux|r")
assert(locale.GuideText("|cRXP_LOOT_Tattered Spellbook|r") == "|cRXP_LOOT_Tattered Spellbook|r")

local grind = "|cRXP_WARN_Grind |cRXP_ENEMY_Mottled Boars|r. Loot them until you have 5 silver worth of vendor items|r"
assert(locale.GuideText(grind):find("|cRXP_ENEMY_sangliers tachetés|r", 1, true))

names[38] = "Nervi défias"
names[9163] = "Dimeurtrodon"
assert(addon.GetCreatureName("Defias Thug") == "Nervi défias")
assert(locale.GuideText("|cRXP_ENEMY_Diemetradon|r") == "|cRXP_ENEMY_Dimeurtrodon|r")

LibQuestieDB.Object.name = function(id)
    return ({ [1763] = "ON RECHERCHE", [164867] = "RECHERCHE" })[id]
end
assert(locale.GuideText("Click the |cRXP_PICK_WANTED|r") == "Cliquez sur |cRXP_PICK_ON RECHERCHE|r")
assert(locale.GuideText("Click the |cRXP_PICK_Dark Iron Wanted Poster|r") == "Cliquez sur |cRXP_PICK_RECHERCHE|r")

print("French locale tests passed")
