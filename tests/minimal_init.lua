vim.opt.runtimepath:append(vim.fn.getcwd())

vim.notify = function(message, level, opts)
  vim.g.line_history_last_notify = {
    message = message,
    level = level,
    opts = opts,
  }
end
