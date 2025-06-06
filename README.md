# awesome-switcher

This plugin integrates the familiar application switcher functionality in the
[awesome window manager](https://github.com/awesomeWM/awesome).

Features:

- **Smart tasklist reordering**: Selected clients are moved to the front of the tasklist when switching
- **ESC cancellation**: Press ESC while Alt-Tab switching to cancel and restore the original state
- Visual highlighting of selected window in the tasklist with customizable colors
- Easily adjustable settings
- Backward cycle using second modifier (e.g.: Shift)
- Intuitive order, respecting your client history
- Includes minimized clients (in contrast to some of the default window-switching utilities)

## Installation

Clone the repo into your `$XDG_CONFIG_HOME/awesome` directory:

```Shell
cd "$XDG_CONFIG_HOME/awesome"
git clone https://github.com/iondodon/awesome-switcher.git awesome-switcher
```

Then add the dependency to your Awesome `rc.lua` config file:

```Lua
    local switcher = require("awesome-switcher")
```

### Enhanced Tasklist Integration

To enable the tasklist reordering feature, you need to configure your tasklist widget to use the switcher's custom source function and initialize the switcher:

```Lua
    -- In your tasklist widget configuration (usually in your screen setup)
    s.mytasklist = awful.widget.tasklist {
        screen  = s,
        filter  = awful.widget.tasklist.filter.currenttags,
        buttons = tasklist_buttons,
        source  = switcher.customTasklistSource  -- Add this line for tasklist reordering
    }

    -- Initialize the switcher after setting up screens (add this after your screen setup)
    switcher.init()
```

## Configuration

Optionally edit any subset of the following settings, the defaults are:

```Lua
    switcher.settings.cycle_raise_client = true,                          -- raise clients on cycle
    switcher.settings.cycle_all_clients = false,                          -- cycle through all clients

    -- Wibar highlighting settings (for tasklist integration)
    switcher.settings.wibar_highlight_bg = "#5294e2aa",                   -- background color for selected client in wibar
    switcher.settings.wibar_highlight_border = "#5294e2ff",               -- border color for selected client in wibar
    switcher.settings.wibar_normal_bg = nil,                              -- normal background (nil = default)
    switcher.settings.wibar_normal_border = nil,                          -- normal border (nil = default)
```

Then add key-bindings. On my particular system I switch to the next client by Alt-Tab and
back with Alt-Shift-Tab. Therefore, this is what my keybindings look like:

```Lua
    awful.key({ "Mod1",           }, "Tab",
      function ()
          switcher.switch( 1, "Mod1", "Alt_L", "Shift", "Tab")
      end),

    awful.key({ "Mod1", "Shift"   }, "Tab",
      function ()
          switcher.switch(-1, "Mod1", "Alt_L", "Shift", "Tab")
      end),
```

Please keep in mind that "Mod1" and "Shift" are actual modifiers and not real keys.
This is important for the keygrabber as the keygrabber uses "Shift_L" for a pressed (left) "Shift" key.

## Usage

The switcher provides enhanced Alt-Tab functionality with the following behaviors:

### Normal Switching

1. **Hold Alt + press Tab**: Start cycling through windows
2. **Continue pressing Tab**: Move to the next window in the cycle
3. **Add Shift**: Press Shift+Tab to cycle backwards
4. **Release Alt**: Confirm your selection and move the selected window to the front of the tasklist

### Cancellation

1. **Hold Alt + press Tab**: Start cycling through windows
2. **Press Tab multiple times**: Navigate to different windows
3. **Press ESC (while still holding Alt)**: Cancel the operation and return to the original window and tasklist order

### Tasklist Integration

When the enhanced tasklist integration is enabled:

- The currently focused window automatically moves to the front of the tasklist
- When you complete an Alt-Tab operation, the selected window moves to the front
- The tasklist visually reflects the most recently used order
- ESC cancellation restores both focus and tasklist order to the original state

### Customizing the Tasklist Highlighting

You can customize the appearance of the selected window in the tasklist by modifying these settings:

```Lua
    -- Change the background color of the selected window in the tasklist
    switcher.settings.wibar_highlight_bg = "#5294e2aa"

    -- Change the border color of the selected window in the tasklist
    switcher.settings.wibar_highlight_border = "#5294e2ff"

    -- Normal background and border (nil = use default theme colors)
    switcher.settings.wibar_normal_bg = nil
    switcher.settings.wibar_normal_border = nil
```

The colors use the format "#RRGGBBAA" where:

- RR, GG, BB are hexadecimal values for red, green, and blue (00-FF)
- AA is the alpha channel for transparency (00-FF)
  - "aa" means semi-transparent
  - "ff" means fully opaque

## Credits

This plugin was created by [Joren Heit](https://github.com/jorenheit)
and later improved upon by [Matthias Berla](https://github.com/berlam).

## License

See [LICENSE](LICENSE).
