# Tacview DCS Mod Directory

Upload the Tacview DCS mod into this directory, e.g., via a PowerShell terminal:
`scp -r "C:\Program Files (x86)\Tacview\DCS\*" user@server:.wine/drive_c/Tacview/`

Then, enable Tacview on the server via:
`systemctl --user enable --now tacview@server1`
