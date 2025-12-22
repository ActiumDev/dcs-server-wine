#!/usr/bin/python3

import socket
import time

hostname = socket.gethostname()

now = time.time()
while True:
    # print timestamp
    now = time.time()
    print(hostname, time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(now)), flush=True)

    # wait until next minute, allowing sleep to wakeup early
    next = now // 60 * 60 + 60
    try:
        time.sleep(next - now)
    except ValueError:
        pass
