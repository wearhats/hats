# NOT RUN YET. Written on Linux; check it on the Mac.
# V1, 1:02 to 1:09: which account is which, and a clean doctor.
Source tapes/settings.tape
Output out/v1-ls-doctor.mp4

Hide
Type "[ -n \"$HATS_TEST_SANDBOX\" ] || exit 1; export PS1='$ '; clear"
Enter
Show

Type "hats ls"
Sleep 300ms
Enter
Sleep 3s
Type "hats doctor"
Sleep 300ms
Enter
Sleep 3s
