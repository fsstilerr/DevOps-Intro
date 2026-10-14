# Lab 11 — Reproducible Builds with Nix

Student: Sofiia Sultanova  
GitHub: `@fsstilerr`  
Branch: `feature/lab11`

---

## Task 1 — Reproducible Go Build with Nix

Root files:

- `flake.nix`
- `flake.lock`

QuickNotes is built from the existing `app/` directory with `buildGoModule`.

Build settings:

```nix
vendorHash = null;
env.CGO_ENABLED = 0;

ldflags = [
  "-s"
  "-w"
];
```

`vendorHash = null` is used because QuickNotes currently has no external Go module dependencies. During the first build Nix reported:

```text
go: no dependencies to vendor
vendor folder is empty, please set 'vendorHash = null;' in your expression
```

The flake also provides a development shell with:

```text
go
gopls
golangci-lint
```

### Runtime check

```bash
ADDR=:18082 ./result/bin/quicknotes
curl http://localhost:18082/health
```

Result (`docs/evidence/lab11/health.txt`):

```json
{"notes":0,"status":"ok"}
```

### Reproducibility proof

First build (`docs/evidence/lab11/store-hash-1.txt`):

```text
sha256:1d6785h3y6g46qkdsf9c5147in5b2nhr815s8f5qh4kyxnq2iyqc
```

Second build from a fresh clone after deleting the first output from the Nix store (`docs/evidence/lab11/store-hash-2.txt`):

```text
sha256:1d6785h3y6g46qkdsf9c5147in5b2nhr815s8f5qh4kyxnq2iyqc
```

The store hashes are identical.

### Design questions

#### a) Why can plain `go build` differ between machines?
The Git commit does not fully describe the build environment. Different Go versions, dependency state, build paths, VCS metadata and environment settings can affect the result. Nix pins the build inputs and toolchain.

#### b) What does `vendorHash` represent?
It fixes the dependency set used by `buildGoModule`. If dependencies change, the expected hash changes and Nix refuses the build until the new dependency closure is explicitly accepted. QuickNotes currently has no third-party modules, so `vendorHash = null`.

#### c) Why is `flake.lock` important?
It pins the exact resolved Nix inputs, including the nixpkgs revision. Without it, the same `flake.nix` can resolve to newer packages and a different build environment.

#### d) `buildGoModule` vs `buildGoApplication`
`buildGoModule` works directly with the normal Go module layout and fixed dependency hashing. `buildGoApplication` is commonly used with a separately generated dependency description such as gomod2nix. `buildGoModule` is simpler for QuickNotes.

---

## Task 2 — Deterministic OCI Image

The OCI image is built with `pkgs.dockerTools.buildImage`, not `docker build`.

Image configuration:

- entrypoint: `/bin/quicknotes`
- exposed port: `8080/tcp`
- user: `nonroot:nonroot`
- application address: `:8080`

Runtime evidence:

- `docs/evidence/lab11/docker-load.txt`
- `docs/evidence/lab11/oci-health.txt`
- `docs/evidence/lab11/oci-config.txt`

### Nix OCI reproducibility

First OCI build (`docs/evidence/lab11/oci-sha256-1.txt`):

```text
1ba3c65e4db8a4a7ed39e667cfa561608cb562e69988502571f1069c54f899c4
```

Second independent OCI build (`docs/evidence/lab11/oci-sha256-2.txt`):

```text
1ba3c65e4db8a4a7ed39e667cfa561608cb562e69988502571f1069c54f899c4
```

Comparison (`docs/evidence/lab11/oci-digest-compare.txt`):

```text
MATCH: YES
```

The two independently produced OCI tarballs are byte-identical.

### Comparison with normal Docker build

Two fresh `docker build --no-cache` runs produced different image IDs.

Run 1:

```text
sha256:6993b86afeb47fe2a1419b951d8adf17fdff599ac8ff40dca3ce0cb95d9e0276
Size: 5368461 bytes
```

Run 2:

```text
sha256:92ab8f632501e5b967d15831c3f002101f15b0d0ac1dc27df19f6624297145b0
Size: 5368461 bytes
```

Nix-built image:

```text
sha256:933d0d41adbe3c40e4c02bdb76ce029f41e5b1bec5e840148bec164a0bdc1fd5
Size: 9186315 bytes
```

Evidence:

- `docs/evidence/lab11/docker-image-ids.txt`
- `docs/evidence/lab11/docker-run1-info.txt`
- `docs/evidence/lab11/docker-run2-info.txt`
- `docs/evidence/lab11/nix-image-info.txt`

The regular Docker builds produced different IDs, while the two Nix OCI builds produced the same SHA-256.

### Design questions

#### e) Why can normal Docker builds be non-reproducible?
Docker image metadata can include build-time values such as timestamps. Base image tags, package repositories and downloaded dependencies may also change unless every input is pinned.

#### f) What does reproducibility add for a security auditor?
A signature proves who signed an artifact. Reproducibility lets an auditor independently rebuild it from the reviewed source and compare the resulting digest, providing evidence that the distributed artifact corresponds to the declared build.

#### g) What is the trade-off?
Nix adds another build language, toolchain, store and operational model. Dockerfiles are more familiar and broadly integrated, while Nix provides stronger control over build inputs and reproducibility.

---

## Bonus — CI-Verified Reproducibility

Workflow:

```text
.github/workflows/nix-repro.yml
```

The workflow uses two parallel fresh GitHub-hosted runners:

- `build-a`
- `build-b`

Each runner independently builds `.#docker` and calculates the OCI tarball SHA-256. A third `compare` job fails when the digests differ.

### Red → green proof

Deliberately broken run:

https://github.com/fsstilerr/DevOps-Intro/actions/runs/38654077396

```text
build-a   PASS
build-b   PASS
compare   FAIL
```

A temporary divergence was introduced only in one build. The comparison job detected the mismatch and exited with code 1.

After removing the temporary divergence:

https://github.com/fsstilerr/DevOps-Intro/actions/runs/38654244688

```text
build-a   PASS
build-b   PASS
compare   PASS
```

The fixed workflow successfully verified matching builds on two independent runners.

### Design questions

#### h) Why is CI reproducibility stronger than “reproducible on my laptop”?
Two local builds can share the same Nix store, cache and machine state. Separate CI runners reconstruct the artifact in independent fresh environments, giving stronger evidence that the result depends only on declared inputs.

#### i) Why two parallel jobs?
Two builds in one job share the same runner and Nix store, so the second build may simply reuse the first result. Separate jobs force independent reconstruction before comparison.

#### j) Where can timestamps leak into an OCI image?
Creation timestamps and layer/config metadata can make otherwise identical image archives differ. Deterministic image metadata avoids embedding the current wall-clock time and allows identical OCI tarballs to be reproduced.

---

## Result

- Task 1: completed — reproducible Nix Go build, identical store hashes and runtime check
- Task 2: completed — deterministic OCI image, identical SHA-256 across independent builds and Docker comparison
- Bonus: completed — parallel CI reproducibility gate with RED → GREEN proof
