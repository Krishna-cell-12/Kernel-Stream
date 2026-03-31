import { Activity, Cpu, Gauge } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import {
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { io } from "socket.io-client";

const socket = io("http://localhost:5000", {
  transports: ["websocket"],
});

function formatTime(ms) {
  const date = new Date(ms);
  return date.toLocaleTimeString();
}

function App() {
  const [processes, setProcesses] = useState([]);
  const [series, setSeries] = useState([]);
  const [connected, setConnected] = useState(socket.connected);

  useEffect(() => {
    function onConnect() {
      setConnected(true);
    }

    function onDisconnect() {
      setConnected(false);
    }

    function onNewProcess(metric) {
      const ts = metric.timestamp || Date.now();
      const timeKey = Math.floor(ts / 1000);

      setProcesses((prev) => [
        { ...metric, timestamp: ts },
        ...prev.slice(0, 19),
      ]);

      setSeries((prev) => {
        const next = [...prev];
        const idx = next.findIndex((p) => p.sec === timeKey);
        if (idx >= 0) {
          next[idx] = { ...next[idx], count: next[idx].count + 1 };
        } else {
          next.push({
            sec: timeKey,
            label: new Date(timeKey * 1000).toLocaleTimeString(),
            count: 1,
          });
        }
        return next.slice(-40);
      });
    }

    socket.on("connect", onConnect);
    socket.on("disconnect", onDisconnect);
    socket.on("new_process", onNewProcess);

    return () => {
      socket.off("connect", onConnect);
      socket.off("disconnect", onDisconnect);
      socket.off("new_process", onNewProcess);
    };
  }, []);

  const totalEvents = useMemo(
    () => series.reduce((acc, point) => acc + point.count, 0),
    [series]
  );

  return (
    <div className="dashboard">
      <header className="header card">
        <div>
          <h1>Kernel-Stream Dashboard</h1>
          <p>Live process executions from your eBPF agent.</p>
        </div>
        <div className={`status ${connected ? "online" : "offline"}`}>
          <Activity size={16} />
          {connected ? "WebSocket Connected" : "Disconnected"}
        </div>
      </header>

      <section className="stats">
        <div className="card stat">
          <Cpu size={18} />
          <div>
            <span>Total Events</span>
            <strong>{totalEvents}</strong>
          </div>
        </div>
        <div className="card stat">
          <Gauge size={18} />
          <div>
            <span>Latest PPS</span>
            <strong>{series.at(-1)?.count ?? 0}</strong>
          </div>
        </div>
      </section>

      <section className="card chart-card">
        <h2>Processes Per Second</h2>
        <ResponsiveContainer width="100%" height={280}>
          <LineChart data={series}>
            <XAxis dataKey="label" minTickGap={32} stroke="#94a3b8" />
            <YAxis allowDecimals={false} stroke="#94a3b8" />
            <Tooltip
              contentStyle={{
                background: "#0f172a",
                border: "1px solid #334155",
                borderRadius: 8,
              }}
            />
            <Line
              type="monotone"
              dataKey="count"
              stroke="#22d3ee"
              strokeWidth={2.5}
              dot={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </section>

      <section className="card table-card">
        <h2>Latest 20 Processes</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Process</th>
                <th>PID</th>
              </tr>
            </thead>
            <tbody>
              {processes.map((item, idx) => (
                <tr key={`${item.pid}-${item.timestamp}-${idx}`}>
                  <td>{formatTime(item.timestamp)}</td>
                  <td>{item.comm}</td>
                  <td>{item.pid}</td>
                </tr>
              ))}
              {processes.length === 0 && (
                <tr>
                  <td colSpan="3" className="empty">
                    Waiting for process events...
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

export default App;
