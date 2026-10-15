package main

import (
	"fmt"
	"io"
	"os"
	"time"
)

func main() {
	_, _ = io.ReadAll(os.Stdin)

	method := os.Getenv("REQUEST_METHOD")
	path := os.Getenv("PATH_INFO")

	if method != "GET" || path != "/time" {
		fmt.Fprint(os.Stderr, "unsupported request\n")
		os.Exit(1)
	}

	nowUTC := time.Now().UTC()
	moscow := nowUTC.Add(3 * time.Hour)

	fmt.Printf(
		`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":"Europe/Moscow","utc_offset":"+03:00"}`+"\n",
		nowUTC.Unix(),
		moscow.Format("2006-01-02T15:04:05")+"+03:00",
		moscow.Format("15:04"),
	)
}
