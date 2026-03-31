CLANG       ?= clang
CXX         ?= g++
BPFTOOL     ?= bpftool
PKG_CONFIG  ?= pkg-config
PROTOC      ?= protoc

BPF_CFLAGS  := -O2 -g -Wall -Werror -target bpf -D__TARGET_ARCH_x86
USER_CFLAGS := -O2 -g -Wall -Werror -I.

LIBBPF_CFLAGS := $(shell $(PKG_CONFIG) --cflags libbpf 2>/dev/null)
LIBBPF_LDLIBS := $(shell $(PKG_CONFIG) --libs libbpf 2>/dev/null)

GRPC_CPP_CFLAGS := $(shell $(PKG_CONFIG) --cflags grpc++ 2>/dev/null)
GRPC_CPP_LIBS   := $(shell $(PKG_CONFIG) --libs grpc++ 2>/dev/null)
PROTOBUF_LIBS   := $(shell $(PKG_CONFIG) --libs protobuf 2>/dev/null)
GRPC_CPP_PLUGIN := $(shell command -v grpc_cpp_plugin 2>/dev/null)

OBJ_BPF      := monitor.bpf.o
VMLINUX_HDR  := vmlinux.h
SKEL_HDR     := monitor.skel.h
AGENT_BIN    := monitor

PROTO_DIR    := proto
PROTO_SRC    := $(PROTO_DIR)/metrics.proto
PROTO_CC     := $(PROTO_DIR)/metrics.pb.cc
PROTO_HDR    := $(PROTO_DIR)/metrics.pb.h
GRPC_CC      := $(PROTO_DIR)/metrics.grpc.pb.cc
GRPC_HDR     := $(PROTO_DIR)/metrics.grpc.pb.h

.PHONY: all clean

all: $(VMLINUX_HDR) $(AGENT_BIN)

$(VMLINUX_HDR):
	@if [ -s "$@" ]; then echo "Using existing $@"; exit 0; fi; \
	if [ ! -r /sys/kernel/btf/vmlinux ]; then \
		echo "Error: /sys/kernel/btf/vmlinux not readable; cannot generate $@"; \
		exit 1; \
	fi; \
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

$(OBJ_BPF): monitor.bpf.c monitor.h $(VMLINUX_HDR)
	$(CLANG) $(BPF_CFLAGS) -I. -c $< -o $@

$(SKEL_HDR): $(OBJ_BPF)
	$(BPFTOOL) gen skeleton $< > $@

$(PROTO_CC) $(GRPC_CC): $(PROTO_SRC)
	$(PROTOC) -I. \
		--cpp_out=. \
		--grpc_out=. \
		--plugin=protoc-gen-grpc=$(GRPC_CPP_PLUGIN) \
		$(PROTO_SRC)

$(AGENT_BIN): monitor.cpp $(SKEL_HDR) monitor.h $(PROTO_CC) $(GRPC_CC)
	$(CXX) $(USER_CFLAGS) $(LIBBPF_CFLAGS) $(GRPC_CPP_CFLAGS) \
		-o $@ monitor.cpp $(PROTO_CC) $(GRPC_CC) \
		$(GRPC_CPP_LIBS) $(PROTOBUF_LIBS) $(LIBBPF_LDLIBS)

clean:
	$(RM) $(OBJ_BPF) $(SKEL_HDR) $(AGENT_BIN) \
		$(PROTO_CC) $(PROTO_HDR) $(GRPC_CC) $(GRPC_HDR)

