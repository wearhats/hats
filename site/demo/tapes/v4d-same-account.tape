# NOT RUN YET. Written on Linux; check it on the Mac.
# V4d: "Two profiles. One account. Doctor noticed." Plants the same account in both profiles first.
Source tapes/settings.tape
Output out/v4d-same-account.mp4

Hide
Type "[ -n \"$HATS_TEST_SANDBOX\" ] || exit 1; export PS1='$ '; clear"
Enter
Show

Hide
Type "hats add work >/dev/null; hats add personal >/dev/null"
Enter
Type "printf '{\"lastKnownAccountUuid\":\"00000000-0000-4000-8000-000000000003\"}' | tee \"$HATS_HOME/profiles/work/desktop/config.json\" > \"$HATS_HOME/profiles/personal/desktop/config.json\"; clear"
Enter
Show
Type "hats doctor"
Sleep 400ms
Enter
Sleep 9s
