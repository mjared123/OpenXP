"""Class quest chains added on top of the 21-60 route (tools/class_steps.py).

Matt (2026-11-11): every chain a class needs (pets, mounts, totems, forms)
and every chain that pays off while levelling (lots of XP, or gear or a
weapon that makes levelling easier). The shared route never moves: these
only add steps tagged for the class.

Each chain: cls, name, why ("need" or what it gives), quests in the order
you do them. A quest that a race can't take is skipped for that race by its
own race mask (the step is tagged "<< Race Class"). A tuple is one
quest from different givers: whichever the route reaches first. `group` = quests with an
elite or dungeon part: added, but marked so solo players can skip them.
`race` = only these races ("Dwarf/Gnome"). `after` = starts where that
chain ends. `from_start` = begin at the chain's first part even if the 1-20
guide does it (parts you've done skip themselves).
"""

ALLIANCE = [
    # Warlock: demons and the mount are trained by quest
    dict(cls="Warlock", name="Succubus", why="need",
         quests=[1717, 1738, 1739]),
    dict(cls="Warlock", name="Orb of Soran'ruk", why="off-hand for levelling",
         quests=[1740]),
    dict(cls="Warlock", name="Felhunter", why="need",
         quests=[1798, 1758, 1802, 1804, 1795]),
    dict(cls="Warlock", name="Enchanted Gold Bloodrobe", why="chest for levelling",
         quests=[(4736, 4738), 1796, 4781, 4782, 4783, 4785, 4784, 4786]),
    dict(cls="Warlock", name="Orb of Orahil", why="off-hand for levelling",
         quests=[(4965, 4968), 1799, 4962, 4961, 4976, 4964]),
    dict(cls="Warlock", name="Felsteed", why="need (mount)",
         quests=[(4487, 4488), 4490]),

    # Paladin
    dict(cls="Paladin", name="Tome of Valor and Verigan's Fist", why="two-hander for levelling",
         quests=[1650, 1651, 1652, 1653, 1655, 1442, 1654, 1806]),
    dict(cls="Paladin", name="Warhorse", why="need (mount)",
         quests=[(4485, 4486, 1661)]),

    # Warrior
    dict(cls="Warrior", name="Fire Hardened Mail", why="chest for levelling",
         quests=[1698, 1699, 1702, 1701, 1782]),
    # then the armorsmith of your race
    dict(cls="Warrior", race="Human", name="Fire Hardened Mail: Grimand Elmore", after="Fire Hardened Mail", why="chest for levelling",
         quests=[1700, 1705, 1706]),
    dict(cls="Warrior", race="NightElf", name="Fire Hardened Mail: Mathiel", after="Fire Hardened Mail", why="chest for levelling",
         quests=[1703, 1710, 1711]),
    dict(cls="Warrior", race="Dwarf/Gnome", name="Fire Hardened Mail: Klockmort", after="Fire Hardened Mail", why="chest for levelling",
         quests=[1704, 1708, 1709]),
    dict(cls="Warrior", name="Whirlwind Weapon", why="weapon for levelling",
         quests=[1718, 1719, 1791, 1712, 1713, 1792], group={1712}),

    # Shaman (Forever's Alliance shamans): Earth and Fire are done by 14 in
    # the 1-20 guide, so Water and Air here make all four totems
    dict(cls="Shaman", name="Call of Water", why="need (water totems)",
         quests=[94494, 94616, 94495, 94497, 94499, 94500, 94501, 94502, 94503, 94505]),
    dict(cls="Shaman", name="Call of Air", why="need (air totems)",
         quests=[94789, 96264, 96135, 96016]),

    # Rogue
    dict(cls="Rogue", name="Poisons", why="need",
         quests=[2360, 2359, 2607, 2608, 2609]),
    dict(cls="Rogue", name="Ravenholdt", why="XP and the Syndicate chain",
         quests=[6681, 96779, 96783, 96786, 96781]),

    # Priest: each race's spell
    dict(cls="Priest", race="Dwarf", name="Fear Ward", why="need", quests=[(5641, 5645, 5647)]),
    dict(cls="Priest", race="NightElf", name="Elune's Grace", why="need", quests=[(5672, 5673, 5674, 5675)]),
    dict(cls="Priest", race="Human", name="Arcane Feedback", why="need", quests=[(5676, 5677, 5678)]),
    dict(cls="Priest", race="Gnome", name="Contingency Plan", why="need", quests=[(94819, 94820)]),

    # Druid
    # Druid: every form (Bear is done by 10 in the 1-20 guide; Aquatic Form
    # and Cure Poison are left open there)
    dict(cls="Druid", name="Aquatic Form", why="need",
         quests=[272, 5061]),
    dict(cls="Druid", name="Cure Poison", why="need",
         quests=[6125]),
    dict(cls="Druid", name="The Great Cat Spirit", why="need",
         quests=[98731]),

    # Mage
    dict(cls="Mage", name="Astral Knot Robe", why="robe for levelling",
         quests=[1939, 1938, 1940, 1942]),
    dict(cls="Mage", name="Mage's Wand", why="wand for levelling",
         quests=[1947, 1949, 1950, 1951, 1948, 1952]),

    # Hunter: the 1-20 guide's Prospector chain, finished
    dict(cls="Hunter", name="The Absent Minded Prospector", why="XP (the 1-20 Hunter guide starts it)",
         quests=[729, 731, 741, 942, 943], from_start=True),
]

HORDE = [
    # Warlock: the Succubus (Barrens, 20) is done in the 1-22 guide
    dict(cls="Warlock", name="Orb of Soran'ruk", why="off-hand for levelling",
         quests=[1740]),
    dict(cls="Warlock", name="Felhunter", why="need",
         quests=[(2996, 3001), 1801, 1803, 1805, 1795]),
    dict(cls="Warlock", name="Enchanted Gold Bloodrobe", why="chest for levelling",
         quests=[(4737, 4739), 1796, 4781, 4782, 4783, 4785, 4784, 4786]),
    dict(cls="Warlock", name="Orb of Orahil", why="off-hand for levelling",
         quests=[(4967, 4969), 1799, 4962, 4961, 4976, 4964]),
    dict(cls="Warlock", name="Felsteed", why="need (mount)",
         quests=[(3631, 4489), 4490]),

    # Warrior: Brutal Armor starts at the Field of Giants trial (the 1-22
    # guide takes "Speak with Ruga"), then two of the three pieces
    dict(cls="Warrior", name="Brutal Hauberk", why="chest for levelling",
         quests=[1823, 1824, 1825, 1838, 1848]),
    dict(cls="Warrior", name="Brutal Gauntlets", after="Brutal Hauberk", why="gloves for levelling",
         quests=[1839, 1842, 1843]),
    dict(cls="Warrior", name="Brutal Helm", after="Brutal Hauberk", why="helm for levelling",
         quests=[1840, 1844, 1845]),
    dict(cls="Warrior", name="Whirlwind Weapon", why="Berserker Stance and a weapon for levelling",
         quests=[1718, 1719, 1791, 1712, 1713, 1792], group={1712}),

    # Shaman: Earth and Fire are done in the starting zones, Water is
    # started in the Barrens; this finishes Water and adds Forever's Air
    dict(cls="Shaman", name="Call of Water", why="need (water totems)",
         quests=[1534, 220, 63, 100, 96]),
    dict(cls="Shaman", name="Call of Air", why="need (air totems)",
         quests=[(1531, 1532), 79360, 79366, 79442]),

    # Rogue
    dict(cls="Rogue", name="Poisons", why="need",
         quests=[2458, 2478, 2479, 2480]),
    dict(cls="Rogue", race="Undead", name="Tools of the Trade", why="gear for levelling",
         quests=[1998, 1999]),
    dict(cls="Rogue", name="Ravenholdt", why="XP and the Syndicate chain",
         quests=[6681, 96779, 96783, 96786, 96781]),

    # Druid (Tauren): Bear and Cat are done in the 1-22 guides; Aquatic Form
    # is started in the Barrens
    dict(cls="Druid", name="Aquatic Form", why="need",
         quests=[27, 28, 30, 31]),
    dict(cls="Druid", name="Cure Poison", why="need",
         quests=[6126, 6127, 6128, 6129, 6130]),

    # Mage
    dict(cls="Mage", race="Undead/Troll", name="Nether-lace Garment", why="robe for levelling",
         quests=[1943, 1944, 1945, 1946]),
    dict(cls="Mage", name="Mage's Wand", why="wand for levelling",
         quests=[1947, 1949, 1950, 1951, 1948, 1952]),
]
