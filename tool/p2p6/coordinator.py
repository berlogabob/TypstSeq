"""Forward a local harness ticket and permit a receiver restart."""
import argparse
import socket


def coordinate(server, sender_role):
    receiver_role = 'mac' if sender_role == 'android' else 'android'
    ticket = None
    sender = None
    try:
        while True:
            peer, _ = server.accept()
            with peer.makefile('rb') as stream:
                role = stream.readline().strip().decode()
                print('connected', role, flush=True)
                if role == sender_role and sender is None:
                    sender = peer
                    ticket = stream.readline()
                    if not ticket or ticket.startswith(b'error '):
                        raise RuntimeError('sender failed before ticket')
                    print('ticket ready', flush=True)
                    continue
                try:
                    if role != receiver_role or ticket is None:
                        raise RuntimeError('unexpected peer or receiver arrived before sender')
                    peer.sendall(ticket)
                    response = stream.readline()
                    if response.startswith(b'received '):
                        sender.sendall(b'received\n')
                        print(response.decode().strip(), flush=True)
                        return
                    if response.startswith(b'error '):
                        sender.sendall(b'error\n')
                        raise RuntimeError(response.decode().strip())
                    print('receiver disconnected; awaiting resume', flush=True)
                finally:
                    peer.close()
    finally:
        if sender is not None:
            sender.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sender', choices=['mac', 'android'], default='mac')
    args = parser.parse_args()
    with socket.create_server(('127.0.0.1', 47993), reuse_port=False) as server:
        coordinate(server, args.sender)
