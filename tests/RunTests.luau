--!strict
-- Minimal test runner (no dependencies). In Studio, with the place synced via
-- Rojo, run this in the command bar (Edit mode or while playing):
--
--   require(game.ReplicatedStorage.Tests.RunTests)()
--
-- Each *.spec module returns { ["test name"] = function(t) ... end }.

local function makeAsserts(failures: { string }, name: string)
	local t = {}
	function t.ok(cond: any, msg: string?)
		if not cond then
			table.insert(failures, `{name}: {msg or "expected truthy"}`)
		end
	end
	function t.eq(a: any, b: any, msg: string?)
		if a ~= b then
			table.insert(failures, `{name}: {msg or "values differ"} (got {tostring(a)}, expected {tostring(b)})`)
		end
	end
	return t
end

return function(): boolean
	local passed, failed = 0, 0
	for _, module in script.Parent:GetChildren() do
		if module:IsA("ModuleScript") and string.match(module.Name, "%.spec$") then
			local tests = require(module) :: any
			for name, fn in tests do
				local failures = {}
				local ok, err = pcall(fn, makeAsserts(failures, `{module.Name} › {name}`))
				if not ok then
					table.insert(failures, `{module.Name} › {name}: error: {err}`)
				end
				if #failures == 0 then
					passed += 1
				else
					failed += 1
					for _, f in failures do
						warn("FAIL " .. f)
					end
				end
			end
		end
	end
	print(`[Tests] {passed} passed, {failed} failed`)
	return failed == 0
end
