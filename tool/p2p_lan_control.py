"""Forward scratch-only test tickets between two integration test instances.

Usage: python3 tool/p2p_lan_control.py <Mac LAN address>
"""
import selectors
import socket
import sys
server = socket.socket()
server.bind((sys.argv[1], 47993))
server.listen(2)
clients = {}
for _ in range(2):
    conn, addr = server.accept()
    role = b''
    while not role.endswith(b'\n'):
        role += conn.recv(1)
    clients[role.decode().strip()] = conn
    print('connected', role.decode().strip(), addr[0], flush=True)
sel = selectors.DefaultSelector()
for role, conn in clients.items(): sel.register(conn, selectors.EVENT_READ, role)
while clients:
    for key, _ in sel.select(timeout=600):
        data = key.fileobj.recv(65536)
        if not data: raise SystemExit('peer closed')
        other = 'android' if key.data == 'mac' else 'mac'
        clients[other].sendall(data)
