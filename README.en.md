# DisplayToggle

[日本語](README.md)

A menu bar app that disconnects an external display from macOS, and connects it again, without unplugging the cable.
A command-line tool, `displayctl`, is included.

When you just turn off a display, macOS keeps it for a few minutes, and your cursor or windows can move to the dark screen.
DisplayToggle removes it from macOS right away.

- Requires macOS 13 or later (Apple silicon or Intel). Disconnecting has not been tested on Intel Macs yet.
- English and Japanese. The app and the command follow your Mac's language.

## Download and install

Download the zip from [Releases](https://github.com/guribow/display-toggle/releases/latest).
`DisplayToggle-<version>-en.zip` has an English guide, `-ja.zip` has a Japanese guide. The app is the same.

1. Open the zip and move DisplayToggle.app to the Applications folder.
2. Double-click it. If macOS says it can't open the app, click "Done".
   (This happens only the first time, because the app is not from the App Store.)
3. Open System Settings > Privacy & Security, scroll down, click "Open Anyway" and enter your password.
4. Double-click the app again and click "Open".

A display icon appears in the menu bar. After you install a new version, repeat steps 2-4.

## How to use

- Click the menu bar icon to see your external displays.
- Click a display to disconnect or reconnect it. A check mark means it is on.
- You can't disconnect the main display, or the only display.
- Two displays with the same name are shown as "(1)" and "(2)".
- If you unplug a disconnected display, it is shown as "(unplugged)".
  Plug it in again to get it back, or click it to remove it from the list.
- Disconnected displays come back when you log out, restart, or quit the app.

## Command line (optional)

`displayctl` in the zip does the same from Terminal. To install it:

```bash
xattr -d com.apple.quarantine displayctl
sudo mkdir -p /usr/local/bin && sudo cp displayctl /usr/local/bin/
```

```bash
displayctl list            # list displays
displayctl off <name>      # disconnect (part of the name, "(2)", or the number)
displayctl on [name]       # reconnect (all if no name)
displayctl toggle <name>   # disconnect or reconnect
displayctl forget <name>   # remove an unplugged display from the list
```

## Troubleshooting

- **A display does not come back:** Run `displayctl on`. If that does not work, quit the app or log out.
- **"Open at Login" shows an error:** Add DisplayToggle in System Settings > General > Login Items.

## Notes

- The app uses a private macOS feature (`CGSConfigureDisplayEnabled`). A macOS update may break it.
- Privacy: the app sends no data anywhere.

## Uninstall

1. Menu bar icon > Quit (disconnected displays come back)
2. Move DisplayToggle.app to the Trash.
3. To delete the saved state too, move `~/Library/Application Support/displayctl` to the Trash.
4. If you installed displayctl: `sudo rm /usr/local/bin/displayctl`

## Build from source

Requires Xcode (swiftc).

```bash
./build.sh   # builds and installs the app and displayctl
./dist.sh    # makes the zips in dist/
```

## License

MIT ([LICENSE](LICENSE)). No warranty.
