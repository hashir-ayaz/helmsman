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
