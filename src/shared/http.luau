-- Downloads the hub's own dependencies (the UI library and its addons), with a file cache.
--
-- Real's game:HttpGet does not throw when a request fails: it returns the status as the body
-- ("429: Too Many Requests", "404: Not Found"), loadstring of that is nil, and calling it killed
-- the whole hub with "attempt to call a nil value". GitHub answers like that now and then, most
-- often on the reload right after a teleport. So every download is checked and retried, the last
-- good copy is kept, and that copy is used when GitHub will not answer.

local Env = use("shared/env")

local Http = {}

local CACHE = "DaewidHUB/cache"
local TRIES = 3

local files = Env.files
local canWrite = files.writefile and files.isfolder and files.makefolder
local pending = {}
local memory = {}

-- The body at url, or nil and the reason. Tries the executor's request first (it reports the
-- status code); missing or failed requests report their actual failure.
local function download(url)
    if not Env.request then return nil, "request is unavailable" end
    local ok, response = Env.call(Env.request, { Url = url, Method = "GET" })
    if not ok then return nil, tostring(response) end
    if type(response) ~= "table" or response.Success == false or tonumber(response.StatusCode) ~= 200 then
        return nil, "HTTP " .. tostring(type(response) == "table" and response.StatusCode or "invalid response")
    end
    if type(response.Body) ~= "string" or response.Body == "" then return nil, "empty response" end
    return response.Body
end

local function get(url)
    local work = pending[url]
    if not work then
        work = {}
        pending[url] = work
        task.spawn(function()
            local ok, body, err = pcall(download, url)
            work.body, work.error = ok and body or nil, ok and err or tostring(body)
            work.done = true
        end)
    end
    local deadline = os.clock() + 15
    while not work.done and os.clock() < deadline do task.wait(0.05) end
    Env.elevate()
    if not work.done then
        -- Leave this one in flight. Reloading an addon must not spawn duplicate hung requests.
        return nil, "download timed out", true
    end
    pending[url] = nil
    return work.body, work.error
end

local function save(path, body)
    local dir = ""
    for part in CACHE:gmatch("[^/]+") do
        dir = dir == "" and part or dir .. "/" .. part
        if not files.isfolder(dir) then
            files.makefolder(dir)
        end
    end
    files.writefile(path, body)
end

local function compile(body, name)
    if not Env.loadstring then return nil, "loadstring is unavailable" end
    if type(body) ~= "string" or body == "" then return nil, "empty source" end
    local ok, chunk, reason = Env.call(Env.loadstring, body, "@" .. name)
    if not ok then return nil, tostring(chunk) end
    if type(chunk) ~= "function" then return nil, reason or "compilation failed" end
    return chunk
end

-- Downloads url and compiles it (chunk name `name`). Falls back to the cached copy saved under
-- `name` by an earlier load. Returns the compiled chunk; errors with the reason when neither works.
function Http.load(url, name)
    if not Env.loadstring then error("DaewidHUB: loadstring is unavailable; optional downloads cannot be loaded", 0) end
    local path = CACHE .. "/" .. name
    local reason
    if memory[url] then
        local chunk = compile(memory[url], name)
        if chunk then return chunk end
    end
    for attempt = 1, TRIES do
        local body, err, timedOut = get(url)
        Env.elevate()
        if body then
            local chunk, compileError = compile(body, name)
            if chunk then
                memory[url] = body
                if canWrite then
                    pcall(save, path, body)
                end
                return chunk
            end
            err = compileError -- a cut-off download
        end
        reason = err
        if timedOut then break end
        if attempt < TRIES then
            task.wait(attempt)
        end
    end
    local ok, cached = pcall(function()
        return Env.canCache and files.isfile(path) and files.readfile(path)
    end)
    local chunk = ok and compile(cached, name)
    if chunk then
        warn(string.format("[DaewidHUB] %s: %s, using the cached copy", name, tostring(reason)))
        return chunk
    end
    error(string.format("could not download %s (%s)", name, tostring(reason)), 0)
end

return Http
