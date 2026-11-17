--!strict
-- Token bucket per (player, action). `rate` = allowed requests per second;
-- bursts of up to max(1, rate) are allowed.

local Players = game:GetService("Players")

local RateLimiter = {}

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

function RateLimiter.check(player: Player, action: string, rate: number): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local capacity = math.max(1, rate)
	local now = os.clock()
	local b = perPlayer[action]
	if not b then
		b = { tokens = capacity, last = now }
		perPlayer[action] = b
	end
	b.tokens = math.min(capacity, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimiter
