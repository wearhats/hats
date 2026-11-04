# NOT RUN YET. Written on Linux; check it on the Mac.
# V1, 0:04 to 0:25: install line, then guided setup adopting ~/.claude-work.
Source tapes/settings.tape
Output out/v1-setup.mp4

Hide
Type `[ -n "$HATS_TEST_SANDBOX" ] || exit 1; export PS1='$ '; clear`
Enter
Show

# Show the install line typed but not run: hats is already installed for the recording.
Type "# brew install wearhats/tap/hats"
Sleep 300ms
Enter
Sleep 2s
Type "hats setup"
Sleep 400ms
Enter
Sleep 2s
# Turn it into a profile?
Type "y"
Enter
Sleep 1s
# Profile name
Type "work"
Enter
Sleep 2s
# Add a profile for another account?
Type "y"
Enter
Sleep 1s
Type "personal"
Enter
Sleep 2s
# Pin the new launchers to the Dock?
Type "y"
Enter
Sleep 1s
# Copy on the Desktop?
Type "n"
Enter
Sleep 1s
# Open now to sign in?
Type "n"
Enter
Sleep 5s
