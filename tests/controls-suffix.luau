local calls = 0
local dropdown = L.C.dropdown(node(), { text = "Multiple", items = { "A", "B", "C" },
	default = {}, multi = true, persist = false,
	callback = function() calls += 1 end })
assert(next(dropdown:get()) == nil)
dropdown:set({ A = true, B = true, Unknown = true })
assert(dropdown:get().A and dropdown:get().B and not dropdown:get().Unknown)
assert(calls == 1)
dropdown:set({ "C" })
assert(dropdown:get().C and not dropdown:get().A)
dropdown:setItems({ "A", "B" })
assert(next(dropdown:get()) == nil)
dropdown:set("not a table")
assert(next(dropdown:get()) == nil)
local rejected = L.C.dropdown(node(), { text = "Refusal", items = { "A", "B" },
	default = "A", persist = false, callback = function() return false, "No" end })
rejected:set("B")
assert(rejected:get() == "A")
rejected:set("missing")
assert(rejected:get() == "A")
local single = L.C.dropdown(node(), { text = "Single", items = { "A", "B" }, default = "B", persist = false })
single:setItems({ "C" })
assert(single:get() == "C")
print("PASS: native multi-select, dynamic options, invalid values and refusal rollback")
