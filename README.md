# awesome-switcher

This plugin integrates the familiar application switcher functionality in the
[awesome window manager](https://github.com/awesomeWM/awesome).

Features:

- **Simple Alt-Tab switching**: Cycle through windows in their natural order
- **ESC cancellation**: Press ESC while Alt-Tab switching to cancel and return to the original window
- Visual highlighting of selected window with urgent flag
- Easily adjustable settings
- Backward cycle using second modifier (e.g.: Shift)
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

### Initialization

Initialize the switcher after setting up your screens:

```Lua
    -- Initialize the switcher (add this after your screen setup)
    switcher.init()
```

## Configuration

Optionally edit any subset of the following settings, the defaults are:

```Lua
    switcher.settings.cycle_raise_client = true    -- raise clients on cycle
    switcher.settings.cycle_all_clients = false    -- cycle through all clients
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

The switcher provides Alt-Tab functionality with the following behaviors:

### Normal Switching

1. **Hold Alt + press Tab**: Start cycling through windows
2. **Continue pressing Tab**: Move to the next window in the cycle
3. **Add Shift**: Press Shift+Tab to cycle backwards
4. **Release Alt**: Confirm your selection and focus the selected window

### Cancellation

1. **Hold Alt + press Tab**: Start cycling through windows
2. **Press Tab multiple times**: Navigate to different windows
3. **Press ESC (while still holding Alt)**: Cancel the operation and return to the original window

## Credits

This plugin was created by [Joren Heit](https://github.com/jorenheit)
and later improved upon by [Matthias Berla](https://github.com/berlam).

## License

See [LICENSE](LICENSE).
