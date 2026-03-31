#!/usr/bin/env python3
import logging
import threading
from concurrent import futures

import grpc
from flask import Flask
from flask_cors import CORS
from flask_socketio import SocketIO

import metrics_pb2
import metrics_pb2_grpc
from google.protobuf import empty_pb2

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")


class MonitorServiceServicer(metrics_pb2_grpc.MonitorServiceServicer):
    def SendMetric(self, request, context):
        logging.info(
            "[REMOTE AGENT] New Process: %s (PID: %d)",
            request.comm,
            request.pid,
        )
        socketio.emit(
            "new_process",
            {
                "pid": request.pid,
                "comm": request.comm,
                "timestamp": request.timestamp,
            },
        )
        return empty_pb2.Empty()


def run_grpc_server() -> None:
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    metrics_pb2_grpc.add_MonitorServiceServicer_to_server(
        MonitorServiceServicer(), server
    )
    server.add_insecure_port("0.0.0.0:50051")
    server.start()
    logging.info("Aggregator listening on 0.0.0.0:50051")
    server.wait_for_termination()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    grpc_thread = threading.Thread(target=run_grpc_server, daemon=True)
    grpc_thread.start()
    logging.info("WebSocket dashboard bridge listening on 0.0.0.0:5000")
    socketio.run(app, host="0.0.0.0", port=5000, allow_unsafe_werkzeug=True)

