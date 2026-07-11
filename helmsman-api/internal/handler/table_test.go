package handler

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

func TestTableToPayload(t *testing.T) {
	table := &metav1.Table{
		ColumnDefinitions: []metav1.TableColumnDefinition{
			{Name: "Name", Type: "string", Priority: 0},
			{Name: "Status", Type: "string", Priority: 0},
		},
		Rows: []metav1.TableRow{
			{
				Cells:  []any{"nginx-abc", "Running"},
				Object: runtime.RawExtension{Raw: []byte(`{"metadata":{"name":"nginx-abc","namespace":"default","uid":"u-1"}}`)},
			},
		},
	}

	got := tableToPayload(table)

	if len(got.Columns) != 2 || got.Columns[0].Name != "Name" {
		t.Fatalf("columns = %+v", got.Columns)
	}
	if len(got.Rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(got.Rows))
	}
	row := got.Rows[0]
	if row.Cells[0] != "nginx-abc" || row.Cells[1] != "Running" {
		t.Errorf("cells = %+v", row.Cells)
	}
	if row.Object.Name != "nginx-abc" || row.Object.Namespace != "default" || row.Object.UID != "u-1" {
		t.Errorf("object stub = %+v", row.Object)
	}
}

func TestParseKubeAge(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"0s", 0, true},
		{"3s", 3, true},
		{"49s", 49, true},
		{"2m", 120, true},
		{"1h", 3600, true},
		{"2d", 172800, true},
		{"1h30m", 5400, true},
		{"", 0, false},
		{"unknown", 0, false},
		{"  14s  ", 14, true},
	}
	for _, tc := range tests {
		got, ok := parseKubeAge(tc.in)
		if ok != tc.ok {
			t.Errorf("parseKubeAge(%q) ok = %v, want %v", tc.in, ok, tc.ok)
			continue
		}
		if ok && got != tc.want {
			t.Errorf("parseKubeAge(%q) = %d, want %d", tc.in, got, tc.want)
		}
	}
}

func TestSortPayloadByLastSeenDesc(t *testing.T) {
	payload := TablePayload{
		Columns: []TableColumn{
			{Name: "Last Seen", Type: "string", Priority: 0},
			{Name: "Reason", Type: "string", Priority: 0},
		},
		Rows: []TableRow{
			{Cells: []any{"49s", "Scheduled"}, Object: RowObject{Name: "old"}},
			{Cells: []any{"0s", "Failed"}, Object: RowObject{Name: "newest"}},
			{Cells: []any{"3s", "Pulling"}, Object: RowObject{Name: "mid"}},
		},
	}
	sortPayloadByLastSeenDesc(&payload)
	if got := payload.Rows[0].Object.Name; got != "newest" {
		t.Fatalf("first row = %q, want newest", got)
	}
	if got := payload.Rows[1].Object.Name; got != "mid" {
		t.Fatalf("second row = %q, want mid", got)
	}
	if got := payload.Rows[2].Object.Name; got != "old" {
		t.Fatalf("third row = %q, want old", got)
	}
}

func TestSortPayloadByLastSeenDesc_noColumn(t *testing.T) {
	payload := TablePayload{
		Columns: []TableColumn{{Name: "Name", Type: "string", Priority: 0}},
		Rows: []TableRow{
			{Cells: []any{"a"}, Object: RowObject{Name: "first"}},
			{Cells: []any{"b"}, Object: RowObject{Name: "second"}},
		},
	}
	sortPayloadByLastSeenDesc(&payload)
	if payload.Rows[0].Object.Name != "first" || payload.Rows[1].Object.Name != "second" {
		t.Fatalf("order changed without Last Seen column: %+v", payload.Rows)
	}
}
