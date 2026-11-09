local RUNTIME_URL = "https://raw.githubusercontent.com/Daewid1/DaewidHUB/d30bc26c947614d1fe0d06af89d163e70308b064/DaewidHUB.lua"
local requestFunction = request or http_request or (type(syn) == "table" and syn.request)
assert(type(requestFunction) == "function", "DaewidHUB requires the executor request function")
assert(type(loadstring) == "function", "DaewidHUB requires loadstring")

local failure
for attempt = 1, 3 do
	local ok, response = pcall(requestFunction, { Url = RUNTIME_URL, Method = "GET" })
	if ok and type(response) == "table" and tonumber(response.StatusCode) == 200 and response.Success ~= false
		and type(response.Body) == "string" and #response.Body > 0 then
		local chunk, reason = loadstring(response.Body, "@DaewidHUB.lua")
		assert(chunk, "DaewidHUB could not compile: " .. tostring(reason))
		return chunk()
	end
	failure = ok and ("HTTP " .. tostring(type(response) == "table" and response.StatusCode or "invalid response")) or tostring(response)
	if attempt < 3 then task.wait(.5 * attempt) end
end
error("DaewidHUB could not download its runtime: " .. tostring(failure), 0)
