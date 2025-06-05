local cairo = require("lgi").cairo
local mouse = mouse
local screen = screen
local wibox = require('wibox')
local table = table
local keygrabber = keygrabber
local math = require('math')
local awful = require('awful')
local gears = require("gears")
local timer = gears.timer
local client = client
awful.client = require('awful.client')

local naughty = require("naughty")
local string = string
local tostring = tostring
local tonumber = tonumber
local debug = debug
local pairs = pairs
local unpack = unpack or table.unpack

local _M = {}

-- settings
_M.settings = {
	cycle_raise_client = true,
	cycle_all_clients = false,

	-- Wibar highlighting settings
	wibar_highlight_bg = "#5294e2aa",  -- background color for selected client in wibar
	wibar_highlight_border = "#5294e2ff", -- border color for selected client in wibar
	wibar_normal_bg = nil,             -- normal background (nil = default)
	wibar_normal_border = nil,         -- normal border (nil = default)
}

_M.altTabTable = {}
_M.altTabIndex = 1
_M.originalTasklistOrder = {}
_M.isActive = false
_M.originalTasklistBackgrounds = {} -- Store original backgrounds
_M.tasklistWidget = nil             -- Cache for tasklist widget
_M.switcherNotification = nil       -- Notification for visual feedback

-- simple function for counting the size of a table
function _M.tableLength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

-- this function returns the list of clients to be shown.
function _M.getClients()
	local clients = {}

	-- Get focus history for current tag
	local s = mouse.screen;
	local idx = 0
	local c = awful.client.focus.history.get(s, idx)

	while c do
		table.insert(clients, c)

		idx = idx + 1
		c = awful.client.focus.history.get(s, idx)
	end

	-- Minimized clients will not appear in the focus history
	-- Find them by cycling through all clients, and adding them to the list
	-- if not already there.
	-- This will preserve the history AND enable you to focus on minimized clients

	local t = s.selected_tag
	local all = client.get(s)

	for i = 1, #all do
		local c = all[i]
		local ctags = c:tags();

		-- check if the client is on the current tag
		local isCurrentTag = false
		for j = 1, #ctags do
			if t == ctags[j] then
				isCurrentTag = true
				break
			end
		end

		if isCurrentTag or _M.settings.cycle_all_clients then
			-- check if client is already in the history
			-- if not, add it
			local addToTable = true
			for k = 1, #clients do
				if clients[k] == c then
					addToTable = false
					break
				end
			end

			if addToTable then
				table.insert(clients, c)
			end
		end
	end

	return clients
end

-- here we populate altTabTable using the list of clients taken from
-- _M.getClients(). In case we have altTabTable with some value, the list of the
-- old known clients is restored.
function _M.populateAltTabTable()
	local clients = _M.getClients()

	if _M.tableLength(_M.altTabTable) then
		for ci = 1, #clients do
			for ti = 1, #_M.altTabTable do
				if _M.altTabTable[ti].client == clients[ci] then
					_M.altTabTable[ti].client.opacity = _M.altTabTable[ti].opacity
					_M.altTabTable[ti].client.minimized = _M.altTabTable[ti].minimized
					break
				end
			end
		end
	end

	_M.altTabTable = {}

	for i = 1, #clients do
		table.insert(_M.altTabTable, {
			client = clients[i],
			minimized = clients[i].minimized,
			opacity = clients[i].opacity
		})
	end
end

-- If the length of list of clients is not equal to the length of altTabTable,
-- we need to repopulate the array and update the UI. This function does this
-- check.
function _M.clientsHaveChanged()
	local clients = _M.getClients()
	return _M.tableLength(clients) ~= _M.tableLength(_M.altTabTable)
end

-- Find tasklist widget for the current screen
function _M.findTasklistWidget()
	if _M.tasklistWidget then
		return _M.tasklistWidget
	end

	local s = mouse.screen
	if not s.mywibar or not s.mywibar.widget then
		return nil
	end

	-- Try to find the tasklist widget in the wibar
	local function findTasklist(widget)
		if widget.get_children then
			local children = widget:get_children()
			for _, child in ipairs(children) do
				if child.get_children then
					local result = findTasklist(child)
					if result then return result end
				end
				-- Check if this is a tasklist widget (awful.widget.tasklist)
				if child.update and child.buttons and child._private and child._private.data then
					return child
				end
			end
		end
		return nil
	end

	_M.tasklistWidget = findTasklist(s.mywibar.widget)
	return _M.tasklistWidget
end

-- Store original widget states when starting Alt-Tab
function _M.storeOriginalBackgrounds()
	_M.originalTasklistBackgrounds = {}
	local s = mouse.screen

	-- Find all tasklist buttons for our clients
	if s.mywibar and s.mywibar.widget then
		for i = 1, #_M.altTabTable do
			local c = _M.altTabTable[i].client
			_M.originalTasklistBackgrounds[c] = {
				urgent = c.urgent,
				focus = c == client.focus
			}
		end
	end
end

-- Restore original widget states when ending Alt-Tab
function _M.restoreOriginalBackgrounds()
	-- Reset all clients to their original state
	for c, state in pairs(_M.originalTasklistBackgrounds) do
		if c.valid then
			c.urgent = state.urgent
		end
	end
	_M.originalTasklistBackgrounds = {}

	-- Emit signal to update tasklist
	awesome.emit_signal("tasklist::update")

	-- Also try to update all screens
	for s in screen do
		if s.mywibar then
			s.mywibar:emit_signal("widget::updated")
		end
	end
end

-- Create a notification to show current selection (fallback visual feedback)
function _M.showSelectionNotification()
	if not _M.isActive or #_M.altTabTable == 0 then
		return
	end

	local selectedClient = _M.altTabTable[_M.altTabIndex].client
	local clientName = selectedClient.name or selectedClient.class or "Unknown"

	-- Cancel previous notification
	if _M.switcherNotification then
		naughty.destroy(_M.switcherNotification)
	end

	-- Show new notification
	_M.switcherNotification = naughty.notify({
		title = "Alt-Tab Switcher",
		text = string.format("(%d/%d) %s", _M.altTabIndex, #_M.altTabTable, clientName),
		timeout = 0.5,
		position = "top_middle",
		preset = naughty.config.presets.low
	})
end

-- Highlight the selected client in the wibar
function _M.highlightWibarClient()
	if not _M.isActive or #_M.altTabTable == 0 then
		return
	end

	-- Method 1: Try to modify client urgent state
	-- Reset all clients first
	for i = 1, #_M.altTabTable do
		local c = _M.altTabTable[i].client
		if c.valid then
			c.urgent = false
		end
	end

	-- Set the selected client as urgent to highlight it
	local selectedClient = _M.altTabTable[_M.altTabIndex].client
	if selectedClient.valid then
		selectedClient.urgent = true

		-- Method 2: Force focus temporarily for visual feedback (will be restored)
		client.focus = selectedClient
	end

	-- Method 3: Update all widgets
	awesome.emit_signal("tasklist::update")

	-- Method 4: Show notification as fallback visual feedback
	_M.showSelectionNotification()

	-- Ensure the client is raised if setting is enabled
	if _M.settings.cycle_raise_client then
		selectedClient:raise()
	end
end

function _M.cycle(dir)
	-- Switch to next client
	_M.altTabIndex = _M.altTabIndex + dir
	if _M.altTabIndex > #_M.altTabTable then
		_M.altTabIndex = 1         -- wrap around
	elseif _M.altTabIndex < 1 then
		_M.altTabIndex = #_M.altTabTable -- wrap around
	end

	-- Update wibar highlighting
	_M.highlightWibarClient()

	_M.altTabTable[_M.altTabIndex].client.minimized = false

	if _M.settings.cycle_raise_client == true then
		_M.altTabTable[_M.altTabIndex].client:raise()
	end
end

-- Reorder clients in the wibar based on the focus history
function _M.reorderWibarClients()
	-- This function would reorder the clients in the wibar/tasklist
	-- based on the new focus order after Alt-Tab switching
	-- Implementation depends on your specific wibar configuration

	-- For now, we'll just ensure the client gets proper focus
	local selectedClient = _M.altTabTable[_M.altTabIndex].client
	selectedClient:jump_to()
	client.focus = selectedClient
end

function _M.switch(dir, mod_key1, release_key, mod_key2, key_switch)
	_M.populateAltTabTable()

	if #_M.altTabTable == 0 then
		return
	elseif #_M.altTabTable == 1 then
		_M.altTabTable[1].client.minimized = false
		_M.altTabTable[1].client:raise()
		return
	end

	-- Mark as active
	_M.isActive = true

	-- reset index
	_M.altTabIndex = 1

	-- Store original backgrounds before highlighting
	_M.storeOriginalBackgrounds()

	-- Immediately highlight the first client
	_M.highlightWibarClient()

	-- Now that we have collected all windows, we should run a keygrabber
	-- as long as the user is alt-tabbing:
	keygrabber.run(
		function(mod, key, event)
			-- Stop alt-tabbing when the alt-key is released
			if gears.table.hasitem(mod, mod_key1) then
				if (key == release_key or key == "Escape") and event == "release" then
					_M.isActive = false

					if key == "Escape" then
						-- Restore original state
						for i = 1, #_M.altTabTable do
							_M.altTabTable[i].client.opacity = _M.altTabTable[i].opacity
							_M.altTabTable[i].client.minimized = _M.altTabTable[i].minimized
						end
					else
						-- Switch to selected client and reorder
						_M.reorderWibarClients()

						-- restore minimized clients and opacity
						for i = 1, #_M.altTabTable do
							if i ~= _M.altTabIndex then
								_M.altTabTable[i].client.minimized = _M.altTabTable[i].minimized
							end
							_M.altTabTable[i].client.opacity = _M.altTabTable[i].opacity
						end
					end

					-- Clear highlighting and restore original backgrounds
					_M.restoreOriginalBackgrounds()

					-- Clean up notification
					if _M.switcherNotification then
						naughty.destroy(_M.switcherNotification)
						_M.switcherNotification = nil
					end

					keygrabber.stop()
				elseif key == key_switch and event == "press" then
					if gears.table.hasitem(mod, mod_key2) then
						-- Move to previous client on Shift-Tab
						_M.cycle(-1)
					else
						-- Move to next client on each Tab-press
						_M.cycle(1)
					end
				end
			end
		end
	)

	-- switch to next client
	_M.cycle(dir)
end -- function switch

return { switch = _M.switch, settings = _M.settings }
