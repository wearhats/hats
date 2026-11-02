# NOT RUN YET. Written on Linux; check it on the Mac.
# V4f: "Change folder. Change hat." Needs direnv in the shell.
Source tapes/settings.tape
Output out/v4f-folder-account.mp4

Hide
Type "[ -n \"$HATS_TEST_SANDBOX\" ] || exit 1; export PS1='$ '; clear"
Enter
Show

Hide
Type "hats add work >/dev/null; hats add personal >/dev/null; mkdir -p ~/oss ~/client; eval \"$(direnv hook zsh)\""
Enter
Type "echo 'eval \"$(hats env personal)\"' > ~/oss/.envrc; echo 'eval \"$(hats env work)\"' > ~/client/.envrc; direnv allow ~/oss; direnv allow ~/client; clear"
Enter
Show
Type "cd ~/oss && printenv CLAUDE_CONFIG_DIR"
Sleep 400ms
Enter
Sleep 4s
Type "cd ~/client && printenv CLAUDE_CONFIG_DIR"
Sleep 400ms
Enter
Sleep 5s
