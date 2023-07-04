local M = {}

---@param config HurlConfig
function M.hurl(config)
  local gheight = vim.api.nvim_list_uis()[1].height
  local gwidth = vim.api.nvim_list_uis()[1].width
  local file = vim.fn.expand("%")
  local buf = vim.api.nvim_create_buf(false, true)
  local width = gwidth - 10
  local height = gheight - 4
  local win_id = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (gheight - height) * 0.5,
    col = (gwidth - width) * 0.5,
    style = "minimal",
    border = "rounded",
  })

  -- This ensures the window created is closed instead of covering the editor when a split is created
  vim.api.nvim_create_autocmd("WinLeave", {
    pattern = "*",
    desc = "Win Leave Autocmd to close Hurl Output window on leave",
    callback = function(args)
      if args.buf == buf then
        vim.api.nvim_win_close(win_id, true)
      end
      -- Clean this autocmd up
      vim.api.nvim_del_autocmd(args.id)
    end,
  })

  -- Build arguments list
  local hurl_args_t = { "hurl", file, "--include" }
  if config.color then
    table.insert(hurl_args_t, "--color")
  else
    table.insert(hurl_args_t, "--no-color")
  end

  vim.system(
    hurl_args_t,
    { text = true },
    ---@param cmd SystemCompleted
    function(cmd)
      vim.schedule(function()
        if cmd.code == 0 then
          -- Filetype detection
          local _, _, filetype = string.find(cmd.stdout, [[.*content%-type.*: .*/(.*);.*]])
          vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })

          -- We don't want to include the header information in the good output ideally with its terminal colors so we
          -- have to parse both the returned content and headers so they don't conflict.
          local stdout_unparsed_t = vim.split(cmd.stdout, "\n")
          local should_record = false
          local stdout_t = {}
          for _, line in ipairs(stdout_unparsed_t) do
            if should_record then
              table.insert(stdout_t, line)
            elseif line == "" then
              should_record = true
            end
            -- This cursed gsub removes all color codes from the header section of the return. If I actually understood
            -- treesitter injections I could then ideally reintroduce highlights for the headers; however, for this POC
            -- idaf.
            local removed_term_codes_line, _ = line:gsub([[%[%d*m]], ""):gsub([[%[%d*;%d*m]], "")
            table.insert(stdout_t, removed_term_codes_line)
          end
          vim.api.nvim_buf_set_lines(buf, 0, -1, true, stdout_t)
        else
          local term = vim.api.nvim_open_term(buf, {})
          vim.api.nvim_chan_send(term, table.concat(vim.split(cmd.stderr, "\n"), "\r\n"))
        end
      end)
    end
  )
end

return M
