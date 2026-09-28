import os
import time
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

APP_VERSION = os.getenv("APP_VERSION", "v1")
READY_DELAY_SECONDS = int(os.getenv("READY_DELAY_SECONDS", "0"))
NEVER_READY = os.getenv("NEVER_READY", "false").lower() == "true"

START_TIME = time.monotonic()
INSTANCE_ID = os.getenv("HOSTNAME", socket.gethostname())


def is_ready():
    if NEVER_READY:
        return False

    elapsed = time.monotonic() - START_TIME
    return elapsed >= READY_DELAY_SECONDS


class Handler(BaseHTTPRequestHandler):

    def do_GET(self):

        if self.path == "/health":
            self.respond(200, "healthy")

        elif self.path == "/ready":
            if is_ready():
                self.respond(200, "ready")
            else:
                self.respond(503, "not ready")

        elif self.path == "/version":
            if is_ready():
                message = f"version={APP_VERSION} instance={INSTANCE_ID}"
                self.respond(200, message)
            else:
                self.respond(503, "not ready")

        else:
            self.respond(404, "not found")

    def respond(self, status, message):
        body = (message + "\n").encode()

        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

        self.wfile.write(body)

    def log_message(self, format, *args):
        print(
            f"{self.log_date_time_string()} "
            f"{self.client_address[0]} "
            f"{format % args}"
        )


server = HTTPServer(("0.0.0.0", 8080), Handler)

print(
    f"Starting service: version={APP_VERSION}, "
    f"ready_delay={READY_DELAY_SECONDS}s, "
    f"never_ready={NEVER_READY}, "
    f"instance={INSTANCE_ID}"
)

server.serve_forever()