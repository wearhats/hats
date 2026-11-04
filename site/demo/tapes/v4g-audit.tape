# NOT RUN YET. Written on Linux; check it on the Mac.
# V4g: "Don't trust it. Check it." Real install script and gh, outside the sandbox. Run in a fresh shell.
Source tapes/settings.tape
Output out/v4g-audit.mp4

Hide
Type "export PS1='$ '; clear"
Enter
Show

Type "curl -fsSLO https://wearhats.dev/install.sh && less install.sh"
Sleep 500ms
Enter
Sleep 4s
Type "q"
Sleep 500ms
Type "gh release download --repo wearhats/hats --pattern hats-macos-universal.tar.gz"
Sleep 400ms
Enter
Sleep 4s
Type "gh attestation verify hats-macos-universal.tar.gz --repo wearhats/hats"
Sleep 400ms
Enter
Sleep 7s
