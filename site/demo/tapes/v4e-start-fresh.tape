# NOT RUN YET. Written on Linux; check it on the Mac.
# V4e: "Wrong account? Start that profile fresh."
Source tapes/settings.tape
Output out/v4e-start-fresh.mp4

Hide
Type "export PS1='$ '; clear"
Enter
Show

Hide
Type "hats add personal >/dev/null; clear"
Enter
Show
Type "hats reset personal --open --dry-run"
Sleep 500ms
Enter
Sleep 5s
Type "hats reset personal --open --yes"
Sleep 500ms
Enter
Sleep 6s
