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
_M.lastClientOrder = {}             -- Cache for client order to detect changes
_M.switcherNotification = nil       -- Notification for visual feedback
_M.customClientOrder = {}           -- Custom client order for tasklist
_M.originalTasklistSource = nil     -- Store original tasklist source function

-- simple function for counting the size of a table
function _M.tableLength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

-- Initialize the custom client order
function _M.initializeCustomOrder()
	local clients = _M.getTasklistClients()
	_M.customClientOrder = {}
	for i, c in ipairs(clients) do
		table.insert(_M.customClientOrder, c)
	end
end

-- Move a client to the front of the custom order
function _M.moveClientToFront(client)
	if not client or not client.valid then
		return
	end

	-- Remove client from current position
	for i = 1, #_M.customClientOrder do
		if _M.customClientOrder[i] == client then
			table.remove(_M.customClientOrder, i)
			break
		end
	end

	-- Insert at the front
	table.insert(_M.customClientOrder, 1, client)
end

-- Custom source function for tasklist that returns clients in our custom order
function _M.customTasklistSource(screen)
	-- Debug: Write to file when source function is called
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") .. " - customTasklistSource called for screen: " .. tostring(screen) .. "\n")
		debugFile:close()
	end

	if not _M.customClientOrder or #_M.customClientOrder == 0 then
		local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
		if debugFile then
			debugFile:write(os.date("%H:%M:%S") .. " - Initializing custom order...\n")
			debugFile:close()
		end
		_M.initializeCustomOrder()
	end

	-- Use the provided screen or fallback to mouse.screen
	local s = screen or mouse.screen

	-- Filter the custom order to only include valid clients that match the screen and tags
	local filtered = {}
	local function filter(c, scr)
		return awful.widget.tasklist.filter.currenttags(c, scr)
	end

	for _, c in ipairs(_M.customClientOrder) do
		if c.valid and (filter(c, s) or (_M.settings.cycle_all_clients and c.screen == s)) then
			table.insert(filtered, c)
		end
	end

	-- Add any new clients that might not be in our custom order yet
	-- Get clients for the specific screen
	local allClients = {}
	for _, c in ipairs(client.get()) do
		if filter(c, s) or (_M.settings.cycle_all_clients and c.screen == s) then
			table.insert(allClients, c)
		end
	end

	for _, c in ipairs(allClients) do
		local found = false
		for _, existing in ipairs(filtered) do
			if existing == c then
				found = true
				break
			end
		end
		if not found then
			table.insert(filtered, c)
			table.insert(_M.customClientOrder, c)
		end
	end

	-- Debug: Write the order being returned to file
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") .. " - Returning client order:\n")
		for i, c in ipairs(filtered) do
			debugFile:write("  " .. i .. ": " .. (c.name or c.class or "Unknown") .. "\n")
		end
		debugFile:close()
	end

	return filtered
end

-- Apply custom source to tasklist
function _M.applyCustomSource()
	-- Debug: Log that we're applying custom source
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") .. " - applyCustomSource called\n")
		debugFile:close()
	end

	-- Simpler approach: force update by emitting client property changes
	-- This should trigger the tasklist to refresh and call our source function
	local selectedClient = nil
	if _M.altTabTable and _M.altTabIndex and _M.altTabTable[_M.altTabIndex] then
		selectedClient = _M.altTabTable[_M.altTabIndex].client
	end

	-- Emit signals that force tasklist refresh
	client.emit_signal("list")
	awesome.emit_signal("tasklist::update")

	-- If we have a selected client, emit property change to force refresh
	if selectedClient and selectedClient.valid then
		selectedClient:emit_signal("property::urgent")
		selectedClient:emit_signal("property::urgent") -- Emit twice to toggle
	end

	-- Use timer for additional refresh attempts
	gears.timer.start_new(0.05, function()
		awesome.emit_signal("tasklist::update")
		client.emit_signal("list")
		return false -- Don't repeat
	end)

	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") .. " - Finished applyCustomSource\n")
		debugFile:close()
	end
end

-- Restore original tasklist source (simplified since source is set at creation)
function _M.restoreOriginalSource()
	-- Since the source is set during tasklist creation, just trigger refresh
	_M.applyCustomSource()
end

-- Get clients using the same filter and sort as the default tasklist
function _M.getTasklistClients()
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

-- this function returns the list of clients in the same order as wibar
function _M.getClients()
	-- Reset tasklist widget cache to get fresh order
	_M.tasklistWidget = nil

	-- Use our custom client order if available
	if _M.customClientOrder and #_M.customClientOrder > 0 then
		return _M.customTasklistSource(mouse.screen)
	end

	-- Fallback to default tasklist ordering
	local clients = _M.getTasklistClients()
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
	-- Move the selected client to the front of our custom order
	local selectedClient = _M.altTabTable[_M.altTabIndex].client

	-- Debug: Write what we're doing to file
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") ..
			" - Reordering: Moving '" .. (selectedClient.name or selectedClient.class or "Unknown") .. "' to front\n")
		debugFile:close()
	end

	_M.moveClientToFront(selectedClient)

	-- Focus the selected client first
	selectedClient:jump_to()
	client.focus = selectedClient

	-- Update the tasklist to reflect the new order
	_M.applyCustomSource()

	-- Debug: Write the new order to file
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") .. " - New order after reordering:\n")
		for i, c in ipairs(_M.customClientOrder or {}) do
			if c.valid then
				local focused = (c == client.focus) and " [FOCUSED]" or ""
				debugFile:write("  " .. i .. ": " .. (c.name or c.class or "Unknown") .. focused .. "\n")
			end
		end
		debugFile:close()
	end
end

function _M.switch(dir, mod_key1, release_key, mod_key2, key_switch)
	-- Initialize custom client order if not already done
	if not _M.customClientOrder or #_M.customClientOrder == 0 then
		_M.initializeCustomOrder()
	end

	-- Move the currently focused client to the front of the list BEFORE populating altTabTable
	if client.focus and client.focus.valid then
		_M.moveClientToFront(client.focus)
		_M.applyCustomSource()
	end

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

	-- Start cycling from the second client (index 2)
	-- Now the first client in the list is guaranteed to be the currently focused one
	_M.altTabIndex = 2
	if _M.altTabIndex > #_M.altTabTable then
		_M.altTabIndex = 1
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
						-- Restore original state without moving clients
						_M.isActive = false
						for i = 1, #_M.altTabTable do
							_M.altTabTable[i].client.opacity = _M.altTabTable[i].opacity
							_M.altTabTable[i].client.minimized = _M.altTabTable[i].minimized
						end
					else
						-- Switch to selected client and reorder
						-- Keep _M.isActive = true while we reorder to prevent onClientFocus interference
						_M.reorderWibarClients()

						-- restore minimized clients and opacity
						for i = 1, #_M.altTabTable do
							if i ~= _M.altTabIndex then
								_M.altTabTable[i].client.minimized = _M.altTabTable[i].minimized
							end
							_M.altTabTable[i].client.opacity = _M.altTabTable[i].opacity
						end

						-- Set inactive after a small delay to ensure all focus changes are complete
						gears.timer.start_new(0.1, function()
							_M.isActive = false
							return false -- Don't repeat
						end)
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

	-- We've already set altTabIndex to 2, so we don't need to cycle initially
	-- The first tab press will be handled by the keygrabber
end -- function switch

-- Handle client focus changes to maintain proper order
function _M.onClientFocus(c)
	-- Debug: Log focus changes
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		local clientName = c and c.valid and (c.name or c.class or "Unknown") or "nil"
		debugFile:write(os.date("%H:%M:%S") ..
			" - onClientFocus called for: " .. clientName .. " (isActive: " .. tostring(_M.isActive) .. ")\n")
		debugFile:close()
	end

	-- Only update order if we're not in the middle of alt-tab switching
	-- and the focused client is not already at the front
	if not _M.isActive and c and c.valid then
		-- Check if client is already at the front to avoid unnecessary updates
		if not _M.customClientOrder or #_M.customClientOrder == 0 or _M.customClientOrder[1] ~= c then
			local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
			if debugFile then
				debugFile:write(os.date("%H:%M:%S") ..
					" - onClientFocus moving '" .. (c.name or c.class or "Unknown") .. "' to front\n")
				debugFile:close()
			end
			_M.moveClientToFront(c)
			_M.applyCustomSource()
		end
	end
end

-- Clear debug log
function _M.clearDebugLog()
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "w")
	if debugFile then
		debugFile:write("=== Awesome Switcher Debug Log Started ===\n")
		debugFile:close()
	end
end

-- Initialize the module when first loaded
function _M.init()
	-- Clear debug log on init
	_M.clearDebugLog()

	_M.initializeCustomOrder()

	-- Connect to client focus signal
	client.connect_signal("focus", _M.onClientFocus)
end

-- Debug function to write current client order to file
function _M.debugClientOrder()
	local debugFile = io.open("/tmp/awesome-switcher-debug.log", "a")
	if debugFile then
		debugFile:write(os.date("%H:%M:%S") .. " - === Custom Client Order ===\n")
		for i, c in ipairs(_M.customClientOrder or {}) do
			if c.valid then
				local focused = (c == client.focus) and " [FOCUSED]" or ""
				debugFile:write("  " .. i .. ": " .. (c.name or c.class or "Unknown") .. focused .. "\n")
			end
		end
		debugFile:write("  Alt-Tab Active: " .. tostring(_M.isActive) .. "\n")
		if _M.isActive then
			debugFile:write("  Current Alt-Tab Index: " .. (_M.altTabIndex or "nil") .. "\n")
		end
		debugFile:write("  ============================\n")
		debugFile:close()
	end
end

return {
	switch = _M.switch,
	settings = _M.settings,
	customTasklistSource = _M.customTasklistSource,
	init = _M.init,
	applyCustomSource = _M.applyCustomSource,
	moveClientToFront = _M.moveClientToFront,
	debugClientOrder = _M.debugClientOrder,
	clearDebugLog = _M.clearDebugLog
}
