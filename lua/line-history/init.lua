-- Public module facade; delegates lifecycle work to the application object.
local App = require("line-history.app")

local M = {}
local app = nil

function M.setup(opts)
  if app then
    app:close_session()
  end

  app = App.new(opts)
  app:setup()
end

function M.show(opts)
  if not app then
    app = App.new({})
    app:setup()
  end

  app:show(opts)
end

return M
