--!strict
-- Animations players can pick in the Play Animation block.
--
-- WHY THIS EXISTS: Roblox only lets a game play animations owned by the game's
-- creator (you, or your group). Players can't use animations they uploaded
-- themselves in your game. So you upload a set of animations (punches, kicks,
-- casting poses, domain hand signs...) and list them here. Players then pick
-- them by name, and their share codes stay portable because they store the key,
-- not the asset id.
--
-- How to add one:
--   1. Animate in Studio (Animation Editor / Moon Animator), publish it to the
--      same user/group that owns the experience.
--   2. Add an entry below:  { key = "punch_r", name = "Right Punch", id = "1234567890" }
--      `key` must never change once players use it (codes reference it).

export type Entry = { key: string, name: string, id: string }

local entries: { Entry } = {
	-- { key = "punch_r", name = "Right Punch", id = "0000000000" },
	-- { key = "punch_l", name = "Left Punch", id = "0000000000" },
	-- { key = "kick_spin", name = "Spin Kick", id = "0000000000" },
	-- { key = "cast_point", name = "Cast (Point)", id = "0000000000" },
	-- { key = "cast_charge", name = "Charge Up", id = "0000000000" },
	-- { key = "domain_sign", name = "Domain Hand Sign", id = "0000000000" },
}

local AnimationLibrary = { List = entries, ByKey = {} :: { [string]: Entry } }
for _, e in entries do
	AnimationLibrary.ByKey[e.key] = e
end

return AnimationLibrary
