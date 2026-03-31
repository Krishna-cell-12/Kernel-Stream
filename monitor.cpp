// SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <bpf/libbpf.h>
#include <grpcpp/grpcpp.h>

#include "monitor.skel.h"
#include "monitor.h"

#include "proto/metrics.grpc.pb.h"
#include "proto/metrics.pb.h"

static volatile sig_atomic_t exiting = 0;
static std::unique_ptr<metrics::MonitorService::Stub> g_stub;

static void handle_sigint(int sig)
{
	(void)sig;
	exiting = 1;
}

static int send_metric_to_server(const struct process_event *e)
{
	if (!g_stub)
		return 0;

	metrics::ProcessMetric metric;
	metric.set_pid(e->pid);
	metric.set_comm(e->comm);

	struct timespec ts;
	if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
		long long ts_ms = (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
		metric.set_timestamp(ts_ms);
	}

	grpc::ClientContext ctx;
	google::protobuf::Empty resp;
	grpc::Status status = g_stub->SendMetric(&ctx, metric, &resp);
	if (!status.ok()) {
		fprintf(stderr, "gRPC SendMetric failed: %s\n", status.error_message().c_str());
	}
	return 0;
}

static int handle_event(void *ctx, void *data, size_t data_sz)
{
	const struct process_event *e = (const struct process_event *)data;

	(void)ctx;
	(void)data_sz;

	printf("Capture -> Process: %s | PID: %d\n", e->comm, e->pid);
	fflush(stdout);

	send_metric_to_server(e);

	return 0;
}

int main(int argc, char **argv)
{
	struct monitor_bpf *skel = NULL;
	struct ring_buffer *rb = NULL;
	int err;

	(void)argc;
	(void)argv;

	libbpf_set_strict_mode(LIBBPF_STRICT_ALL);

	signal(SIGINT, handle_sigint);
	signal(SIGTERM, handle_sigint);

	auto channel = grpc::CreateChannel("localhost:50051",
					   grpc::InsecureChannelCredentials());
	g_stub = metrics::MonitorService::NewStub(channel);

	skel = monitor_bpf__open_and_load();
	if (!skel) {
		fprintf(stderr, "Failed to open and load BPF skeleton\n");
		return 1;
	}

	err = monitor_bpf__attach(skel);
	if (err) {
		fprintf(stderr, "Failed to attach BPF programs: %d\n", err);
		goto cleanup;
	}

	rb = ring_buffer__new(bpf_map__fd(skel->maps.rb), handle_event, NULL, NULL);
	if (!rb) {
		fprintf(stderr, "Failed to create ring buffer: %d\n", -errno);
		err = 1;
		goto cleanup;
	}

	printf("Monitoring exec events and forwarding to gRPC at localhost:50051. Press Ctrl+C to exit.\n");

	while (!exiting) {
		err = ring_buffer__poll(rb, 100);
		if (err < 0 && errno != EINTR) {
			fprintf(stderr, "Error polling ring buffer: %d\n", err);
			break;
		}
	}

cleanup:
	ring_buffer__free(rb);
	monitor_bpf__destroy(skel);

	return err < 0 ? 1 : 0;
}

