"""Forward a local harness ticket and permit a receiver restart."""
import socket

server = socket.create_server(('127.0.0.1', 47993), reuse_port=False)
peers = {}
ticket = None
while True:
    peer, _ = server.accept()
    stream = peer.makefile('rb')
    role = stream.readline().strip()
    print('connected', role.decode(), flush=True)
    if role == b'mac':
        peers['mac'] = peer
        ticket = stream.readline()
        if not ticket:
            raise RuntimeError('sender closed before ticket')
        if ticket.startswith(b'error '):
            raise RuntimeError(ticket.decode().strip())
        print('ticket ready', flush=True)
    elif role == b'android':
        if ticket is None:
            raise RuntimeError('receiver arrived before sender')
        peer.sendall(ticket)
        response = stream.readline()
        if response.startswith(b'received '):
            peers['mac'].sendall(b'received\n')
            print(response.decode().strip(), flush=True)
            break
        if response.startswith(b'error '):
            peers['mac'].sendall(b'error\n')
            raise RuntimeError(response.decode().strip())
        print('receiver disconnected; awaiting resume', flush=True)
    else:
        raise RuntimeError('unknown peer')
