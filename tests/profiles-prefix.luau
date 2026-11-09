local disk, buttons, entries, encoded = {}, {}, {}, {}
local function clone(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = clone(item) end
	return copy
end
local files = { isfolder = function() return true end, makefolder = function() end,
	isfile = function(path) return disk[path] ~= nil end,
	readfile = function(path) assert(disk[path], path); return disk[path] end,
	writefile = function(path, body) disk[path] = body end,
	delfile = function(path) disk[path] = nil end,
	listfiles = function(root)
		local paths = {}
		for path in pairs(disk) do if path:sub(1, #root) == root then paths[#paths + 1] = path end end
		return paths
	end }
local Env = { files = files, HttpService = {
	JSONEncode = function(_, data) local name = "json" .. (#encoded + 1); encoded[#encoded + 1] = name; encoded[name] = clone(data); return name end,
	JSONDecode = function(_, data) assert(encoded[data]); return clone(encoded[data]) end } }
local flags = {
	AutoDuel = { Type = "Toggle", Value = false },
	Think = { Type = "Slider", Value = .4 },
	NeverPick = { Type = "Dropdown", Value = { A = true } },
	AutoDuel_bind = { Type = "Bind", Value = "F4" },
	MenuKeybind = { Type = "Keybind", Value = "RightShift" } }
local applied = {}
for name, entry in pairs(flags) do entry.Set = function(value) entry.Value = value; applied[#applied + 1] = name end end
local group = {}
local function entry(name, info)
	local value = info.Default
	if value == nil and info.Values then value = info.Values[1] end
	local object = { Value = value }
	function object:SetValues(values) self.Value = values[1] end
	function object:SetValue(nextValue) self.Value = nextValue end
	entries[name] = object
	return object
end
group.AddInput = function(_, name, info) return entry(name, info) end
group.AddDropdown = group.AddInput
group.AddLabel = function() return { SetText = function() end } end
group.AddButton = function(_, name, callback) buttons[name] = callback end
local tab = { AddGroupbox = function() return group end }
local notices = {}
local Ui = { Library = { Flags = flags }, notify = function(title, body) notices[#notices + 1] = title .. body end }
local function use(name) if name == "shared/env" then return Env elseif name == "shared/ui" then return Ui end; error(name) end
local Profiles = (function()
