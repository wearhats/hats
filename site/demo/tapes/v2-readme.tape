# NOT RUN YET. Written on Linux; check it on the Mac.
# V2, README GIF: add a profile, then ls, then ps. 25s, 800px wide, 3 MB at most.
Source tapes/settings.tape
Output out/v2-readme.gif
Set Width 800

Hide
Type "[ -n \"$HATS_TEST_SANDBOX\" ] || exit 1; export PS1='$ '; clear"
Enter
Show


Type "hats add personal"
Sleep 400ms
Enter
Sleep 3s
Type "hats ls"
Sleep 400ms
Enter
Sleep 6s
Type "hats ps"
Sleep 400ms
Enter
Sleep 8s
