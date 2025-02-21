The SRS server (as of version 2.1.1.0) always writes its log to serverlog.txt in the same directory as the SR-Server.exe, regardless of the actual working directory.
Multiple SRS server instances with different configs but running off the same binary would log to the same file, clobbering the log.
As a workaround, all instances share C:\SRS_server\SR-Server.exe, but invoke it (via systemd units) through individual symlinks.
This results in separate log files next to each symlink.
