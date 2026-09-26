DisplayToggle

A menu bar app that disconnects an external display from macOS, and connects it again,
without unplugging the cable.

Requires macOS 13 or later (Apple silicon or Intel).
  Note: Disconnecting has not been tested on Intel Macs yet.
The app shows English or Japanese, following your Mac's language.


== Install ==

1. Move DisplayToggle.app to the Applications folder.
2. Double-click DisplayToggle.app.
3. If macOS says it can't open the app, click "Done".
   (This happens only the first time, because the app is not from the App Store.)
4. Open System Settings > Privacy & Security.
   Scroll down and click "Open Anyway", then enter your password.
5. Double-click DisplayToggle.app again and click "Open".

A display icon appears in the menu bar. You're ready.
To start DisplayToggle when you log in, click the icon and choose "Open at Login".


== How to use ==

- Click the menu bar icon to see your external displays.
- Click a display to disconnect or reconnect it. A check mark means it is on.
- You can't disconnect the main display, or the only display.
- Two displays with the same name are shown as "(1)" and "(2)".
- If you unplug a disconnected display, it is shown as "(unplugged)".
  Plug it in again to get it back, or click it to remove it from the list.
- Disconnected displays come back when you log out, restart, or quit the app.
- To see the version, click the icon and choose "About DisplayToggle".


== Command line (optional) ==

displayctl in this folder does the same from Terminal.
In Terminal, go to this folder and run:

  xattr -d com.apple.quarantine displayctl
  sudo mkdir -p /usr/local/bin && sudo cp displayctl /usr/local/bin/

  displayctl list          List displays
  displayctl off <name>    Disconnect (part of the name is OK)
  displayctl on            Reconnect all
  displayctl toggle <name> Disconnect or reconnect


== Notes ==

- The app uses a private macOS feature. A macOS update may break it.
- After you install a new version, repeat steps 3-5 of "Install".
- The app sends no data anywhere.


== Uninstall ==

1. Menu bar icon > Quit (disconnected displays come back)
2. Move DisplayToggle.app from the Applications folder to the Trash.
3. To delete the saved state too: in Finder, choose Go > Go to Folder,
   enter ~/Library/Application Support/displayctl and move that folder to the Trash.
4. If you installed displayctl, run: sudo rm /usr/local/bin/displayctl


License: MIT (see LICENSE). No warranty.
Questions or problems: https://github.com/guribow/display-toggle/issues
