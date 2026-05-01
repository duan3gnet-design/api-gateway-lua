local auth = require("middleware.auth")
local rate_limiter = require("middleware.rate_limiter")
local rbac = require("middleware.rbac")

auth.check()
rate_limiter.check()
rbac.check()