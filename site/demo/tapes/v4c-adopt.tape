# NOT RUN YET. Written on Linux; check it on the Mac.
# V4c: "Already have ~/.claude-work? Keep it."
Source tapes/settings.tape
Output out/v4c-adopt.mp4

Hide
Type "export PS1='$ '; clear"
Enter
Show

Type "hats add work --code-dir ~/.claude-work"
Sleep 500ms
Enter
Sleep 4s
Type "hats ls"
Sleep 400ms
Enter
Sleep 8s
