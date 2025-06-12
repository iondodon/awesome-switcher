local mouse = mouse
local screen = screen
local keygrabber = keygrabber
local awful = require('awful')
local gears = require("gears")
local client = client
local naughty = require("naughty")
local string = string
local pairs = pairs

local _M = {}

-- settings
_M.settings = {
	cycle_raise_client = true,
	cycle_all_clients = false
}

_M.altTabTable = {}
_M.altTabIndex = 1
_M.isActive = false
_M.originalTasklistBackgrounds = {} -- Store original backgrounds
_M.switcherNotification = nil       -- Notification for visual feedback
_M.previouslyFocusedClient = nil    -- Track previously focused client

-- simple function for counting the size of a table
function _M.tableLength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

-- Get clients using the same filter and sort as the default tasklist
function _M.getClients()
	local s = mouse.screen
	local clients = {}

	-- Use awful.widget.tasklist's default filter function
	local function filter(c, screen)
		-- This mimics the default tasklist filter
		return awful.widget.tasklist.filter.currenttags(c, screen)
	end

	-- Get all clients and filter them the same way tasklist does
	for _, c in ipairs(client.get()) do
		if filter(c, s) or (_M.settings.cycle_all_clients and c.screen == s) then
			table.insert(clients, c)
		end
	end

	-- Sort clients the same way the default tasklist does (by class, then by instance)
	table.sort(clients, function(a, b)
		if a.class and b.class and a.class ~= b.class then
			return a.class < b.class
		elseif a.instance and b.instance then
			return a.instance < b.instance
		else
			return a.window < b.window
		end
	end)

	return clients
end

-- Find index of a client in altTabTable
function _M.findClientIndex(c)
	for i, entry in ipairs(_M.altTabTable) do
		if entry.client == c then
			return i
		end
	end
	return 1
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

	-- If we have a previously focused client, start from it
	if _M.previouslyFocusedClient and _M.previouslyFocusedClient.valid then
		_M.altTabIndex = _M.findClientIndex(_M.previouslyFocusedClient)
	else
		-- Initialize the index based on direction
		if dir == 1 then
			_M.altTabIndex = 1
		else
			_M.altTabIndex = #_M.altTabTable
		end
	end

	-- Store original backgrounds before highlighting
	_M.storeOriginalBackgrounds()

	-- Immediately highlight the current client
	_M.highlightWibarClient()

	-- Now that we have collected all windows, we should run a keygrabber
	-- as long as the user is alt-tabbing:
	keygrabber.run(
		function(mod, key, event)
			-- Stop alt-tabbing when the alt-key is released
			if gears.table.hasitem(mod, mod_key1) then
				if (key == release_key or key == "Escape") and event == "release" then
					if key == "Escape" then
						-- On Escape, restore original client states
						_M.isActive = false
						for i = 1, #_M.altTabTable do
							_M.altTabTable[i].client.opacity = _M.altTabTable[i].opacity
							_M.altTabTable[i].client.minimized = _M.altTabTable[i].minimized
						end
					else
						-- Switch to selected client
						local selectedClient = _M.altTabTable[_M.altTabIndex].client
						selectedClient:jump_to()
						client.focus = selectedClient

						-- Store the previously focused client
						_M.previouslyFocusedClient = client.focus

						-- restore minimized clients and opacity
						for i = 1, #_M.altTabTable do
							if i ~= _M.altTabIndex then
								_M.altTabTable[i].client.minimized = _M.altTabTable[i].minimized
							end
							_M.altTabTable[i].client.opacity = _M.altTabTable[i].opacity
						end

						_M.isActive = false
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

	-- Immediately cycle once to select the previous window
	_M.cycle(dir)
end

-- Initialize the module when first loaded
function _M.init()
	-- Connect to client focus signal to track previously focused client
	client.connect_signal("focus", function(c)
		if not _M.isActive and c and c.valid then
			_M.previouslyFocusedClient = client.focus
			client.focus = c
		end
	end)
end

return {
	switch = _M.switch,
	settings = _M.settings,
	init = _M.init
}
