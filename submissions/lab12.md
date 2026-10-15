# Lab 12 — WebAssembly Containers with Spin

Student: Sofiia Sultanova  
GitHub: `@fsstilerr`  
Branch: `feature/lab12`

---

## Task 1 — WASM Endpoint with Spin SDK

Toolchain used:

```text
Spin 3.6.3
TinyGo 0.41.1 darwin/arm64
Go 1.26.9
Wasmtime 49.0.3
Hyperfine 2.0.0
```

The project was scaffolded from the canonical Spin Go template:

```bash
mkdir -p wasm
cd wasm
spin new -t http-go moscow-time --accept-defaults
```

### `wasm/moscow-time/main.go`

```go
package main

import (
	"fmt"
	"net/http"
	"time"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		nowUTC := time.Now().UTC()
		moscow := nowUTC.Add(3 * time.Hour)

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(
			w,
			`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":"Europe/Moscow","utc_offset":"+03:00"}`,
			nowUTC.Unix(),
			moscow.Format("2006-01-02T15:04:05")+"+03:00",
			moscow.Format("15:04"),
		)
	})
}
```

### `wasm/moscow-time/spin.toml`

```toml
#:schema https://schemas.spinframework.dev/spin/manifest-v2/latest.json

spin_manifest_version = 2

[application]
name = "moscow-time"
version = "0.1.0"
authors = ["Sofiia Sultanova"]
description = "Moscow time endpoint for DevOps Lab 12"

[[trigger.http]]
route = "/time"
component = "moscow-time"

[component.moscow-time]
source = "main.wasm"
allowed_outbound_hosts = []

[component.moscow-time.build]
command = "tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm ."
watch = ["**/*.go", "go.mod"]
```

### Build

```text
Building component moscow-time with `tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .`
Finished building all Spin components
```

Artifact size:

```text
-rw-r--r--  1 sophiyasultanova  staff  359K main.wasm
```

Evidence:

- `docs/evidence/lab12/wasm-size.txt`
- `docs/evidence/lab12/spin-up.log`

### Runtime verification

```text
HTTP/1.1 200 OK
content-type: application/json
content-length: 124
```

```json
{
    "unix": 1792023432,
    "iso": "2026-10-15T03:17:12+03:00",
    "hour_minute": "03:17",
    "timezone": "Europe/Moscow",
    "utc_offset": "+03:00"
}
```

Evidence:

- `docs/evidence/lab12/time-response.txt`
- `docs/evidence/lab12/time-json.txt`

### Design questions

#### a) Browser WASM vs server WASM

`GOOS=js GOARCH=wasm` targets the browser/JavaScript host and depends on JavaScript APIs and the Go JS runtime. A `wasip1` module instead targets WASI: there is no browser DOM or JavaScript environment, but the module gets a small portable system interface that can run under server-side WASM runtimes. The gain is portability, fast instantiation and a much narrower host capability surface.

#### b) Why `-buildmode=c-shared`?

Spin does not run this module as a normal CLI program with a `_start` entrypoint. The Spin Go SDK exports the HTTP handler ABI expected by the Spin wasi-http host. `-buildmode=c-shared` is required so TinyGo emits the exports that Spin expects for the component handler.

#### c) Why `allowed_outbound_hosts = []`?

WASM uses a capability-based model: a component receives only the host capabilities explicitly granted to it. An empty outbound-host list means the component has no network egress capability. Docker `--network none` also removes network connectivity, but it does so at the container/network-namespace layer; Spin expresses the restriction directly as a host capability granted to the component.

#### d) TinyGo stdlib gaps encountered

A real compatibility issue appeared with TinyGo 0.43.0 + Go 1.27.1: the HTTP path crashed inside `net/textproto.CanonicalMIMEHeaderKey` when the Spin handler executed. Rebuilding with TinyGo 0.41.1 + Go 1.26.9 resolved it. I also avoided runtime timezone database dependence and used `UTC + 3h` directly for Moscow time.

---

## Task 2 — Performance vs Lab 6 Docker Container

Test rig:

```text
MacBook Pro
macOS / darwin arm64
Spin 3.6.3
TinyGo 0.41.1
Go 1.26.9
Hyperfine 2.0.0
```

Warm latency was measured with 5 warmup runs and 50 measured runs. Cold start was measured as runtime start → first successful HTTP response, with 5 independent samples for each platform.

### Real measurements

| Dimension | Lab 6 Docker | Lab 12 WASM / Spin |
| --- | ---: | ---: |
| Artifact size | 5.12 MiB | 359.04 KiB |
| Cold start p50 | 173.97 ms | 23.13 ms |
| Warm latency p50 | 6.018 ms | 5.835 ms |
| Warm latency p95 | 8.383 ms | 7.122 ms |

Cold-start samples:

```text
Docker: 0.2676, 0.2085, 0.1740, 0.1464, 0.1717 s
Spin:   0.0806, 0.0123, 0.0373, 0.0231, 0.0183 s
```

Exact artifact sizes:

```text
Docker quicknotes:lab6: 5368449 bytes
Spin main.wasm:         367653 bytes
```

On this machine, the Spin WASM artifact was about **14.6× smaller** and its measured cold-start p50 was about **7.5× faster** than the Docker baseline. Warm latency was similar, with Spin slightly lower in both p50 and p95.

Evidence:

- `docs/evidence/lab12/perf-summary.txt`
- `docs/evidence/lab12/perf-results.json`
- `docs/evidence/lab12/hyperfine-spin.json`
- `docs/evidence/lab12/hyperfine-docker.json`
- `docs/evidence/lab12/test-rig.txt`

### Design questions

#### e) What dominates each platform's cold start?

For Docker, startup includes container creation, namespace/cgroup setup, filesystem/runtime preparation and process startup. For Spin, the dominant work is loading and instantiating the WASM component in Wasmtime and wiring the wasi-http interface. The measured result reflects the lighter-weight Spin path on this machine.

#### f) Where is WASM clearly better, and where is Docker still right?

WASM is especially attractive for small stateless services, plugins, edge functions and multi-tenant workloads where fast startup, small artifacts and strong capability isolation matter. Docker remains the better fit when the application expects a complete Linux userspace, arbitrary native binaries, broad OS APIs, mature container tooling or dependencies that do not compile cleanly to WASI.

#### g) Multi-tenant safety

A WASM guest cannot simply access host files, sockets or syscalls unless the host gives it those capabilities. This makes attacks such as reading arbitrary host filesystem paths or opening unexpected outbound sockets harder by construction. Linux namespaces isolate processes, but the container still exposes a much larger Linux syscall surface.

---

## Bonus — Two WASM Execution Models

A second implementation was built in `wasm-cli/` without the Spin SDK. It reads the request context from `REQUEST_METHOD` and `PATH_INFO`, writes the Moscow-time JSON to stdout.

### `wasm-cli/main.go`

```go
package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
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
```

### Build and run

Spin component:

```bash
tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .
spin up
```

Standalone WASI CLI:

```bash
tinygo build -o main.wasm -target=wasi -no-debug ./main.go

wasmtime run \
  --env REQUEST_METHOD=GET \
  --env PATH_INFO=/time \
  main.wasm
```

Output:

```json
{"unix":1792024807,"iso":"2026-10-15T03:40:07+03:00","hour_minute":"03:40","timezone":"Europe/Moscow","utc_offset":"+03:00"}
```

### Size + cold-start comparison

| Execution model | Module size | Cold-start measurement |
| --- | ---: | ---: |
| Spin wasi-http component | 359 KiB | 23.13 ms p50 |
| Bare `wasmtime run` WASI CLI | 194 KiB | 13.2 ms mean over 5 runs |

Standalone Wasmtime benchmark:

```text
Benchmark 1: wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time main.wasm (5 runs)

Wall Time [ms]  13.2 ± 19.4
min … max       4.1 … 47.8
Memory [MiB]    11.9
```

The first invocation was much slower than the following runs (47.8 ms vs a minimum of 4.1 ms), so Hyperfine warned that filesystem/runtime caches affected the small sample. The result is therefore reported with its full range rather than treating 13.2 ms as a perfectly stable value.

The two measurements represent different execution models: the CLI number includes a fresh `wasmtime` process for each invocation, while Spin's 23.13 ms figure measures starting the persistent HTTP runtime and reaching the first successful response.

### Design questions

#### h) Why can't the Spin component run under bare `wasmtime run`?

The Task 1 artifact is a wasi-http component exporting the HTTP handler interface expected by a wasi-http host. It is not a command-style WASI module whose execution begins at `_start`. Bare `wasmtime run` therefore does not provide the HTTP server/handler environment required by the Spin component.

#### i) What does Spin add on top of Wasmtime?

Spin uses Wasmtime as its execution engine but adds the application layer around it: the persistent wasi-http server loop, routing from `spin.toml`, component lifecycle and instance management, application configuration and capability policies such as `allowed_outbound_hosts`.

#### j) When does each model fit?

Per-invocation `wasmtime run` fits short command-style jobs such as transformation utilities, hooks or isolated batch tasks where one process handles one invocation and exits. Spin's persistent wasi-http model fits network services and APIs that should stay listening and handle many HTTP requests without restarting a runtime process for every request.

---

## Result

- Task 1: completed — Spin SDK component builds and serves valid Moscow-time JSON at `/time`
- Task 2: completed — real Docker vs WASM measurements for artifact size, cold start and warm latency
- Bonus: completed — standalone WASI CLI runs under bare Wasmtime with size and cold-start comparison
