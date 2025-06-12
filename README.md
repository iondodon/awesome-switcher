# awesome-switcher

This plugin integrates the familiar application switcher functionality in the
[awesome window manager](https://github.com/awesomeWM/awesome).

**Compatible with AwesomeWM v4.3**

Features:

- **Smart Window Switching**: Cycles through windows in their natural order (sorted by class, then instance)
- **Visual Feedback**: Highlights the selected window in the wibar using the urgent flag
- **Minimized Windows**: Automatically unminimizes windows when cycling through them
- **Window Raising**: Optional automatic raising of windows during cycling (configurable)
- **Multi-Screen Support**: Works across all screens with proper window management
- **Backward Cycling**: Use Alt-Shift-Tab to cycle backwards
- **State Preservation**: Remembers window states (minimized, opacity) and restores them properly
- **Focus Memory**: Tracks previously focused client for better switching experience

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

The switcher provides two configurable settings:

```Lua
switcher.settings.cycle_raise_client = true    -- Automatically raise windows when cycling through them
switcher.settings.cycle_all_clients = false    -- If true, cycle through all clients on the screen, not just the ones in the current tag
```

## Usage

The switcher provides Alt-Tab functionality with the following behaviors:

### Normal Switching

1. **Hold Alt + press Tab**: Start cycling through windows
2. **Continue pressing Tab**: Move to the next window in the cycle
3. **Add Shift**: Press Alt-Shift-Tab to cycle backwards
4. **Release Alt**: Switch to and focus the selected window

The switcher will:

- Automatically unminimize windows when cycling to them
- Highlight the selected window in the wibar
- Preserve window states when cycling ends
- Remember the previously focused window for better context

## Credits

This plugin was created by [Joren Heit](https://github.com/jorenheit)
and later improved upon by [Matthias Berla](https://github.com/berlam)
and [Ion Dodon](https://github.com/iondodon).

## License

See [LICENSE](LICENSE).
