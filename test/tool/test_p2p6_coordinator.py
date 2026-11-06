import socket
import threading
import unittest

from tool.p2p6.coordinator import coordinate


class CoordinatorTest(unittest.TestCase):
    def test_android_can_send_and_receiver_can_reconnect(self):
        server = socket.create_server(('127.0.0.1', 0))
        worker = threading.Thread(target=coordinate, args=(server, 'android'))
        worker.start()
        address = server.getsockname()
        try:
            with socket.create_connection(address) as sender:
                sender.settimeout(5)
                sender.sendall(b'android\nticket\n')
                with socket.create_connection(address) as interrupted:
                    interrupted.sendall(b'mac\n')
                    self.assertEqual(interrupted.makefile('rb').readline(), b'ticket\n')
                with socket.create_connection(address) as receiver:
                    receiver.sendall(b'mac\n')
                    self.assertEqual(receiver.makefile('rb').readline(), b'ticket\n')
                    receiver.sendall(b'received 123 10\n')
                self.assertEqual(sender.makefile('rb').readline(), b'received\n')
        finally:
            worker.join(timeout=5)
            server.close()
        self.assertFalse(worker.is_alive())


if __name__ == '__main__':
    unittest.main()
