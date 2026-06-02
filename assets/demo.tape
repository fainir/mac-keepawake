Output assets/demo.gif
Set Shell bash
Set FontSize 17
Set Width 1000
Set Height 560
Set Padding 22
Set Theme "Catppuccin Mocha"
Set TypingSpeed 32ms
Set Framerate 24

Hide
Type "export PATH=/usr/local/bin:$PATH; clear"
Enter
Show

Sleep 700ms
Type "# mac-keepawake - awake with the lid closed, dims the backlight while shut"
Enter
Sleep 1000ms
Type "dsbright g                           # read backlight (works on Apple Silicon)"
Enter
Sleep 1400ms
Type "# lid closes -> dim to 0     lid opens -> restore your exact level"
Enter
Sleep 700ms
Type "dsbright s 0 && dsbright g"
Enter
Sleep 1300ms
Type "dsbright s 0.45 && dsbright g        # restored"
Enter
Sleep 1500ms
Type "# on AC it is automatic; on battery, stay awake on demand:"
Enter
Sleep 700ms
Type "keepawake"
Enter
Sleep 2800ms
Ctrl+C
Sleep 2200ms
