package handler

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var kubeAgePart = regexp.MustCompile(`(\d+)([smhdwMy])`)

// parseKubeAge converts kubectl-style relative ages (e.g. "49s", "2m", "1h30m")
// to approximate seconds since last observation. Smaller values mean newer.
func parseKubeAge(s string) (secs int64, ok bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false
	}
	matches := kubeAgePart.FindAllStringSubmatch(s, -1)
	if len(matches) == 0 {
		return 0, false
	}
	var total int64
	for _, m := range matches {
		n, err := strconv.ParseInt(m[1], 10, 64)
		if err != nil {
			return 0, false
		}
		switch m[2] {
		case "s":
			total += n
		case "m":
			total += n * 60
		case "h":
			total += n * 3600
		case "d":
			total += n * 86400
		case "w":
			total += n * 604800
		case "M":
			total += n * 2592000
		case "y":
			total += n * 31536000
		default:
			return 0, false
		}
	}
	return total, true
}

// sortPayloadByLastSeenDesc orders rows by the "Last Seen" column, newest first.
// Rows with unparseable ages are placed at the end. No-op when the column is absent.
func sortPayloadByLastSeenDesc(p *TablePayload) {
	if p == nil || len(p.Rows) < 2 {
		return
	}
	idx := lastSeenColumnIndex(p.Columns)
	if idx < 0 {
		return
	}
	const unknownAge = int64(1 << 62)
	sort.SliceStable(p.Rows, func(i, j int) bool {
		si, oki := lastSeenSeconds(p.Rows[i], idx)
		sj, okj := lastSeenSeconds(p.Rows[j], idx)
		if !oki {
			si = unknownAge
		}
		if !okj {
			sj = unknownAge
		}
		return si < sj
	})
}

func lastSeenColumnIndex(cols []TableColumn) int {
	for i, c := range cols {
		if strings.EqualFold(c.Name, "Last Seen") {
			return i
		}
	}
	return -1
}

func lastSeenSeconds(row TableRow, col int) (int64, bool) {
	if col >= len(row.Cells) {
		return 0, false
	}
	switch v := row.Cells[col].(type) {
	case string:
		return parseKubeAge(v)
	default:
		return parseKubeAge(fmt.Sprint(v))
	}
}
