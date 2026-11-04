# NOT RUN YET. Written on Linux; check it on the Mac.
# V1, 0:47 to 0:55: hats ps with one row waiting. Needs running sessions, see the README.
Source tapes/settings.tape
Output out/v1-ps.mp4

Hide
Type `[ -n "$HATS_TEST_SANDBOX" ] || exit 1; export PS1='$ '; clear`
Enter
Show

Type "hats ps"
Sleep 400ms
Enter
Sleep 7s
