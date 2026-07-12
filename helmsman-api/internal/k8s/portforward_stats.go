package k8s

import (
	"net"
	"sync/atomic"
)

type sessionStats struct {
	connections   atomic.Int32
	bytesSent     atomic.Int64
	bytesReceived atomic.Int64
}

func (s *sessionStats) snapshot() (connections int, sent, received int64) {
	return int(s.connections.Load()), s.bytesSent.Load(), s.bytesReceived.Load()
}

type countingConn struct {
	net.Conn
	stats *sessionStats
}

func (c *countingConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if n > 0 {
		c.stats.bytesReceived.Add(int64(n))
	}
	return n, err
}

func (c *countingConn) Write(b []byte) (int, error) {
	n, err := c.Conn.Write(b)
	if n > 0 {
		c.stats.bytesSent.Add(int64(n))
	}
	return n, err
}

func wrapCountingConn(conn net.Conn, stats *sessionStats) net.Conn {
	stats.connections.Add(1)
	return &countingConn{Conn: conn, stats: stats}
}

func releaseCountingConn(stats *sessionStats) {
	stats.connections.Add(-1)
}
