#!/usr/bin/env python3
"""A stand-in for tor in the UI tests (OWELK_TOR points here).

Answers SOCKS5 on each --SocksPort and lets through only owelk.test, which it connects to this computer
(so a page at http://owelk.test:<port>/ loads only through the proxy). The control port takes the
cookie written to the DataDirectory, AUTHENTICATE and SIGNAL NEWNYM. Everything it sees goes to
OWELK_FAKE_TOR_LOG. It quits when the process named by __OwningControllerProcess ends, as tor does.
"""
import os
import socket
import sys
import threading
import time

args = sys.argv[1:]
options, socks_ports = {}, []
i = 0
while i < len(args):
    if args[i].startswith("-") and i + 1 < len(args):
        key, value = args[i].lstrip("-"), args[i + 1]
        if key == "SocksPort":
            socks_ports.append(int(value.rsplit(":", 1)[1]))
        else:
            options[key] = value
        i += 2
    else:
        i += 1

log_path = os.environ.get("OWELK_FAKE_TOR_LOG")
lock = threading.Lock()


def log(line):
    if log_path:
        with lock, open(log_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def say(line):
    print(time.strftime("%b %d %H:%M:%S.000") + " " + line, flush=True)


def exact(conn, size):
    data = b""
    while len(data) < size:
        part = conn.recv(size - len(data))
        if not part:
            raise ConnectionError("closed")
        data += part
    return data


def pipe(source, target):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            target.sendall(data)
    except OSError:
        pass
    finally:
        for s in (source, target):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def serve_socks(client, port):
    try:
        _, methods = exact(client, 2)
        exact(client, methods)
        client.sendall(b"\x05\x00")
        _, command, _, kind = exact(client, 4)
        if kind == 3:
            host = exact(client, exact(client, 1)[0]).decode()
        elif kind == 1:
            host = socket.inet_ntoa(exact(client, 4))
        else:
            host = socket.inet_ntop(socket.AF_INET6, exact(client, 16))
        target_port = int.from_bytes(exact(client, 2), "big")
        log("connect %s:%d via %d" % (host, target_port, port))
        if command != 1 or host != "owelk.test":
            client.sendall(b"\x05\x04\x00\x01" + bytes(6))
            client.close()
            return
        upstream = socket.create_connection(("127.0.0.1", target_port), timeout=5)
        upstream.settimeout(None)
        client.sendall(b"\x05\x00\x00\x01" + bytes(6))
        threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()
        pipe(client, upstream)
    except (OSError, ConnectionError):
        client.close()


def serve_control(conn, cookie):
    authenticated = False
    reader = conn.makefile("rb")
    try:
        for raw in reader:
            line = raw.decode().strip()
            if line.startswith("AUTHENTICATE"):
                parts = line.split()
                authenticated = len(parts) == 2 and parts[1].lower() == cookie.hex()
                conn.sendall(b"250 OK\r\n" if authenticated else b"515 Authentication failed\r\n")
            elif line == "SIGNAL NEWNYM":
                if authenticated:
                    log("newnym")
                    conn.sendall(b"250 OK\r\n")
                else:
                    conn.sendall(b"514 Authentication required.\r\n")
            elif line == "QUIT":
                conn.sendall(b"250 closing connection\r\n")
                break
    except OSError:
        pass
    conn.close()


def listen(port, handler, *extra):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(16)

    def loop():
        while True:
            conn, _ = server.accept()
            threading.Thread(target=handler, args=(conn, *extra), daemon=True).start()

    threading.Thread(target=loop, daemon=True).start()


def owner_alive(pid):
    if os.name == "nt":
        # os.kill would end the process on Windows; ask whether it is still running instead.
        import ctypes
        kernel = ctypes.windll.kernel32
        handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        code = ctypes.c_ulong()
        kernel.GetExitCodeProcess(handle, ctypes.byref(code))
        kernel.CloseHandle(handle)
        return code.value == 259  # STILL_ACTIVE
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


log("start " + " ".join(args))
say("[notice] Tor 0.4.8.0 (fake) opening log file.")
say("[notice] Bootstrapped 0% (starting): Starting")
data = options.get("DataDirectory", ".")
os.makedirs(data, exist_ok=True)
cookie = os.urandom(32)
with open(os.path.join(data, "control_auth_cookie"), "wb") as f:
    f.write(cookie)
for port in socks_ports:
    listen(port, serve_socks, port)
if "ControlPort" in options:
    listen(int(options["ControlPort"].rsplit(":", 1)[1]), serve_control, cookie)
time.sleep(0.3)
say("[notice] Bootstrapped 45% (requesting_descriptors): Asking for relay descriptors")
time.sleep(0.3)
say("[notice] Bootstrapped 100% (done): Done")
owner = int(options.get("__OwningControllerProcess", "0"))
while owner == 0 or owner_alive(owner):
    time.sleep(0.5)
