"""Readiness only. No terminal, command execution, or directory serving endpoint."""
import http.server
import json
import os


class Readiness(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ('/', '/healthz'):
            self.send_error(404)
            return
        ready = os.path.ismount('/data') and os.path.isfile('/run/cmux-runtime-ready')
        try:
            with open('/opt/cmux/runtime.json') as image, open('/data/.cmux/runtime.json') as saved:
                ready = ready and json.load(image) == json.load(saved)
        except (OSError, ValueError):
            ready = False
        body = b'ready\n' if ready else b'not ready\n'
        self.send_response(200 if ready else 503)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    http.server.ThreadingHTTPServer(('0.0.0.0', 8080), Readiness).serve_forever()
