local function tablelength(T)
	local count = 0
	for value in pairs(T) do
		if value == "" then
			return count
		end
		count = count + 1
	end
	return count
end
local function _register_keylogger(M)
	vim.on_key(function(key, typed)
		M.safestate = false
		table.insert(M.typed_storage, typed)
		table.insert(M.keys_storage, key)
	end, M.ns_id, {})
end

local function _unregister_keylogger(M)
	vim.on_key(nil, M.ns_id, {})
end
local M = {
	safestate = false,
	augroup_name1 = "dejavu-auto-repeat",
	augroup_name2 = "dejavu-enable",
	augroup_name3 = "dejavu-disable",
	typed_storage = {},
	keys_storage = {},
	typed = nil,
	keys = nil,
	command = nil,
	ns_id = vim.api.nvim_create_namespace("dejavu-key-reader"),
	config = {
		which_key = false,
		enabled = false,
		macro_key = "x",
		callback = function(command)
			vim.fn.setreg("x", command)
		end,
		notify = vim.notify,
	},
}
function M.setup(opt)
	opt = opt or {}
	local ok, _ = pcall(require, "which-key")
	M.enabled = opt.enabled or false
	if M.enabled then
		M.on()
	end
	M.which_key = ok or M.config.which_key
	if opt.macro_key and opt.callback then
		vim.notify(
			"Setup received a macro_key and a callback function. The macro_key is ignored and the callback function is used",
			vim.log.levels.ERROR
		)
	end
	M.config = vim.tbl_deep_extend("force", M.config, opt)
	if opt.macro_key and not opt.callback then
		M.config.callback = function(command)
			vim.fn.setreg(opt.macro_key, command)
		end
	end
end

-- Function to check for single duplication, which happens due to which-key
local function is_once_duplicated_substring(s)
	local len = #s
	if len % 2 ~= 0 then
		return false -- odd length can't be a double repeat
	end
	local half = len / 2
	local left = s:sub(1, half)
	local right = s:sub(half + 1, len)
	return left == right, left
end

function M.on()
	vim.api.nvim_create_autocmd("SafeState", {
		group = vim.api.nvim_create_augroup(M.augroup_name1, { clear = true }),
		callback = M.storage_logic,
	})

	if vim.fn.mode("n") or vim.fn.mode("o") then
		_register_keylogger(M)
	end

	-- Autocommands to turn on keylogger depending on the mode
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = vim.api.nvim_create_augroup(M.augroup_name2, { clear = true }),
		pattern = { "*:n", "*:o" },
		callback = function()
			if M.enabled then
				_register_keylogger(M)
			end
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = vim.api.nvim_create_augroup(M.augroup_name3, { clear = true }),
		-- Turn off when entering insert, terminal, cmd or visual mode
		pattern = { "*:i", "*:c", "*:tl", "*:v" },
		callback = function()
			_unregister_keylogger(M)
		end,
	})
end

function M.storage_logic()
	if M.safestate then
		M.typed_storage = {}
		M.keys_storage = {}
		return
	end
	-- dejavu doesnt store 1 key commands. This has some false positives in
	-- case of bytestreams.
	M.typed = table.concat(M.typed_storage)
	M.keys = table.concat(M.keys_storage)
	local no_escaped_string = string.gsub(M.typed, "\\", "")
	if string.len(no_escaped_string) < 2 or string.find(M.typed, "^" .. "\r") then
		M.safestate = true
		return
	end
	-- dejavu doesnt store macros either
	-- this can easily crash vim when recursivly calling macros
	if string.find(M.keys, "@" .. M.config.macro_key) then
		M.config.notify("dejvu: recursive macro not allowed")
		M.safestate = true
		return
	end
	M.command = M.typed
	if M.which_key then
		duplicated, left = is_once_duplicated_substring(M.command)
		M.command = not duplicated and M.command or left
	end
	M.config.notify("dejavu: Command:" .. M.command)
	M.config.callback(M.command)
	M.safestate = true
end

function M.off()
	-- Remove the on key callback
	_unregister_keylogger(M)
	-- Remove the safestate callback
	vim.api.nvim_clear_autocmds({ group = M.augroup_name1 })
	vim.api.nvim_clear_autocmds({ group = M.augroup_name2 })
	vim.api.nvim_clear_autocmds({ group = M.augroup_name3 })
end

function M.toggle()
	if not M.enabled then
		M.config.notify("dejavu enabled")
		M.on()
	else
		M.config.notify("dejavu disabled")
		M.off()
	end
	M.enabled = not M.enabled
end
vim.api.nvim_create_user_command("DejavuToggle", M.toggle, {})
vim.api.nvim_create_user_command("DejavuOn", M.on, {})
vim.api.nvim_create_user_command("DejavuOff", M.off, {})
return M
