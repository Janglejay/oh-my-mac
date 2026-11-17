-- One selection controls the Java provider; each backend retains its own settings.
local backend = require("user.java_backend")
return require("user.plugins.java_" .. backend.server)
