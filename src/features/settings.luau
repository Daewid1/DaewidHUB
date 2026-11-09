-- Settings tab (see shared/settings): Ball VS Ball configs, and what each missing function changes.

use("core/ui")
local Settings = use("shared/settings")

return Settings.build({
    folder = "BallVsBall",
    effects = {
        queue_on_teleport = "the hub does not come back after a teleport: run the loader again",
        writefile = "configs, themes and the offline cache cannot be saved",
        readfile = "saved configs and cached downloads cannot be read",
        isfile = "saved configs and cached downloads cannot be located",
        isfolder = "config folders cannot be managed",
        makefolder = "config folders cannot be created",
        listfiles = "saved configs and themes cannot be listed",
        delfile = "saved configs cannot be deleted",
        setclipboard = "copy buttons display their text instead",
    },
})
