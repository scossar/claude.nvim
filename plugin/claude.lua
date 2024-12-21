if vim.g.loaded_claude then
	return
end
vim.g.loaded_claude = true

vim.api.nvim_create_user_command("ClaudeSendSelection", function()
	require("claude").send_visual_selection()
end, { range = true })

-- For visual mode only
vim.keymap.set("v", "<leader>cs", ":ClaudeSendSelection<CR>", { desc = "[A]sk Claude", noremap = true, silent = true })

vim.api.nvim_set_hl(0, "ClaudeSendSelection", { link = "IncSearch" })

vim.api.nvim_create_user_command("ClaudeReload", function()
	package.loaded["claude"] = nil
	vim.cmd("source " .. vim.fn.expand("%"))
	print("Claude plugin reloaded")
end, {})

-- Make sure to disconnect when plugin is unloaded
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		require("claude").disconnect()
	end,
})
