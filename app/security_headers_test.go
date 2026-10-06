package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSecurityHeadersAppliedToAllRoutes(t *testing.T) {
	store, err := NewStore("")
	if err != nil {
		t.Fatal(err)
	}

	server := NewServer(store)

	tests := []struct {
		name string
		path string
	}{
		{"health", "/health"},
		{"notes", "/notes"},
		{"not-found", "/does-not-exist"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			rec := httptest.NewRecorder()

			server.Routes().ServeHTTP(rec, req)

			if got := rec.Header().Get("Cache-Control"); got != "no-store" {
				t.Fatalf("Cache-Control = %q, want %q", got, "no-store")
			}

			if got := rec.Header().Get("Content-Security-Policy"); got != "default-src 'none'" {
				t.Fatalf("Content-Security-Policy = %q, want %q", got, "default-src 'none'")
			}

			if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
				t.Fatalf("X-Content-Type-Options = %q, want %q", got, "nosniff")
			}
		})
	}
}
