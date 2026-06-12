package handler

import (
	"encoding/json"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// TableColumn mirrors a server-side printer column.
type TableColumn struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	Priority int32  `json:"priority"`
}

// RowObject is the minimal object identity the client needs to build follow-up URLs.
type RowObject struct {
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
	UID       string `json:"uid"`
}

// TableRow is one printed row plus its object identity.
type TableRow struct {
	Cells  []any     `json:"cells"`
	Object RowObject `json:"object"`
}

// TablePayload is the list response shape (Data field of APIResponse).
type TablePayload struct {
	Columns []TableColumn `json:"columns"`
	Rows    []TableRow    `json:"rows"`
}

// tableToPayload reshapes a server-side metav1.Table into the API payload.
func tableToPayload(t *metav1.Table) TablePayload {
	cols := make([]TableColumn, 0, len(t.ColumnDefinitions))
	for _, c := range t.ColumnDefinitions {
		cols = append(cols, TableColumn{Name: c.Name, Type: c.Type, Priority: c.Priority})
	}

	rows := make([]TableRow, 0, len(t.Rows))
	for _, r := range t.Rows {
		var meta struct {
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
				UID       string `json:"uid"`
			} `json:"metadata"`
		}
		if len(r.Object.Raw) > 0 {
			_ = json.Unmarshal(r.Object.Raw, &meta)
		}
		rows = append(rows, TableRow{
			Cells: r.Cells,
			Object: RowObject{
				Namespace: meta.Metadata.Namespace,
				Name:      meta.Metadata.Name,
				UID:       meta.Metadata.UID,
			},
		})
	}
	return TablePayload{Columns: cols, Rows: rows}
}
