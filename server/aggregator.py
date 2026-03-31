#!/usr/bin/env python3
import logging
from concurrent import futures

import grpc

import metrics_pb2
import metrics_pb2_grpc
from google.protobuf import empty_pb2


class MonitorServiceServicer(metrics_pb2_grpc.MonitorServiceServicer):
    def SendMetric(self, request, context):
        logging.info(
            "[REMOTE AGENT] New Process: %s (PID: %d)",
            request.comm,
            request.pid,
        )
        return empty_pb2.Empty()


def serve() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    metrics_pb2_grpc.add_MonitorServiceServicer_to_server(
        MonitorServiceServicer(), server
    )
    server.add_insecure_port("0.0.0.0:50051")
    server.start()
    logging.info("Aggregator listening on 0.0.0.0:50051")
    server.wait_for_termination()


if __name__ == "__main__":
    serve()

