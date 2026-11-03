# NOT RUN YET. Written on Linux; check it on the Mac.
# V4h: "Removing it takes three lines." Caption the Keychain items. The stock folders stay untouched.
Source tapes/settings.tape
Output out/v4h-uninstall.mp4

Hide
Type `[ -n "$HATS_TEST_SANDBOX" ] || exit 1; export PS1='$ '; clear`
Enter
Show

Hide
Type "hats add work >/dev/null; hats add personal >/dev/null; clear"
Enter
Show
Type `hats dock unpin && hats rm --all --purge --yes && rm -rf "$HATS_LAUNCHER_DIR" "$HATS_HOME"`
Sleep 500ms
Enter
Sleep 5s
Type "ls -A ~/.claude ~/.claude.json"
Sleep 400ms
Enter
Sleep 5s
