# Lab 11 — Reproducible Builds with Nix

Student: Sofiia Sultanova  
GitHub: `@fsstilerr`  
Branch: `feature/lab11`

---

## Task 1 — Reproducible Go Build via Nix Flake

The root `flake.nix` builds the existing QuickNotes application from `app/` with `buildGoModule`.

### Flake

```nix
{
  description = "Reproducible QuickNotes build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          quicknotes = pkgs.buildGoModule {
            pname = "quicknotes";
            version = "0.1.0";

            src = ./app;

            vendorHash = null;

            env.CGO_ENABLED = 0;

            ldflags = [
              "-s"
              "-w"
            ];
          };

          rootfs = pkgs.runCommand "quicknotes-rootfs" { } ''
            mkdir -p $out/bin $out/etc $out/tmp
            cp ${quicknotes}/bin/quicknotes $out/bin/quicknotes

            cat > $out/etc/passwd <<PASSWD
nonroot:x:65532:65532:nonroot:/tmp:/sbin/nologin
PASSWD

            cat > $out/etc/group <<GROUP
nonroot:x:65532:
GROUP

            chmod 1777 $out/tmp
          '';

          dockerImage = pkgs.dockerTools.buildImage {
            name = "quicknotes-nix";
            tag = "latest";

            copyToRoot = rootfs;

            config = {
              Entrypoint = [ "/bin/quicknotes" ];
              ExposedPorts = {
                "8080/tcp" = { };
              };
              User = "nonroot:nonroot";
              WorkingDir = "/tmp";
              Env = [
                "ADDR=:8080"
                "DATA_PATH=/tmp/notes.json"
                "SEED_PATH=/tmp/seed.json"
              ];
            };
          };
        in
        {
          inherit quicknotes;
          default = quicknotes;
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          docker = dockerImage;
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go
              gopls
              golangci-lint
            ];
          };
        });
    };
}
```

`flake.lock` is committed at the repository root and pins the resolved nixpkgs revision.

QuickNotes has no external Go module dependencies. The initial build reported:

```text
go: no dependencies to vendor
vendor folder is empty, please set 'vendorHash = null;' in your expression
```

Therefore the final flake uses:

```nix
vendorHash = null;
```

### Build and runtime check

```bash
nix build .#quicknotes
```

Resulting binary:

```text
-r-xr-xr-x 1 root wheel 5626768 Jan 1 1970 quicknotes
```

Runtime evidence (`docs/evidence/lab11/health.txt`):

```text
ADDR=:18082 ./result/bin/quicknotes
curl http://localhost:18082/health
```

```json
{"notes":0,"status":"ok"}
```

### Two-environment reproducibility proof

First build (`docs/evidence/lab11/store-hash-1.txt`):

```text
sha256:1d6785h3y6g46qkdsf9c5147in5b2nhr815s8f5qh4kyxnq2iyqc
```

Second build from a fresh clone after deleting the first output from the Nix store (`docs/evidence/lab11/store-hash-2.txt`):

```text
sha256:1d6785h3y6g46qkdsf9c5147in5b2nhr815s8f5qh4kyxnq2iyqc
```

The hashes are identical.

### Design questions

#### a) Why can `go build` differ between machines?
A Git SHA pins source code, but not the complete build environment. Go version, dependency resolution, build IDs, paths, VCS metadata and environment values may differ. Nix makes these inputs explicit and pins the toolchain.

#### b) What does `vendorHash` represent?
For `buildGoModule`, `vendorHash` fixes the fetched Go dependency closure. If dependencies change, the hash changes and the build fails until the expected value is updated. QuickNotes has no external dependencies, so the vendor tree is empty and `vendorHash = null` is required.

#### c) Why is `flake.lock` important?
It pins the exact resolved Nix inputs, including the nixpkgs revision. Without it, the same `flake.nix` may resolve to newer packages and a different Go toolchain, so reproducibility is no longer guaranteed.

#### d) `buildGoModule` vs `buildGoApplication`
`buildGoModule` works directly with a standard Go module and fixed dependency hashing. `buildGoApplication` is commonly paired with a separately generated dependency description such as gomod2nix. QuickNotes already has a normal Go module layout, so `buildGoModule` is the simpler fit.

---

## Task 2 — Deterministic OCI Image

The same flake exposes `.#docker` using `pkgs.dockerTools.buildImage`.

Image configuration:

```text
Entrypoint: /bin/quicknotes
ExposedPorts: 8080/tcp
User: nonroot:nonroot
WorkingDir: /tmp
ADDR=:8080
```

The image is produced by Nix, not by `docker build`.

Runtime evidence:

- `docs/evidence/lab11/docker-load.txt`
- `docs/evidence/lab11/oci-health.txt`
- `docs/evidence/lab11/oci-config.txt`

### Two independent OCI builds

First OCI tarball (`docs/evidence/lab11/oci-sha256-1.txt`):

```text
1ba3c65e4db8a4a7ed39e667cfa561608cb562e69988502571f1069c54f899c4
```

Second independent OCI tarball (`docs/evidence/lab11/oci-sha256-2.txt`):

```text
1ba3c65e4db8a4a7ed39e667cfa561608cb562e69988502571f1069c54f899c4
```

Comparison (`docs/evidence/lab11/oci-digest-compare.txt`):

```text
FIRST:  1ba3c65e4db8a4a7ed39e667cfa561608cb562e69988502571f1069c54f899c4
SECOND: 1ba3c65e4db8a4a7ed39e667cfa561608cb562e69988502571f1069c54f899c4
MATCH: YES
```

The two independently produced OCI tarballs are byte-identical.

### Comparison with the Lab 6 Dockerfile build

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

The regular Docker builds produced different IDs, while the independent Nix OCI builds produced the same tarball SHA-256.

### Design questions

#### e) Why can normal `docker build` be non-reproducible?
Docker builds can embed build-time metadata such as timestamps. Base-image tags, package repositories and downloaded dependencies can also move unless every input is pinned.

#### f) What does reproducibility add for a security auditor?
A signature proves who signed a particular artifact, but not independently that the artifact corresponds exactly to the reviewed source. A reproducible build lets an auditor rebuild the artifact from the pinned source and inputs and compare digests.

#### g) What is the trade-off?
Nix adds another language, store, build model and toolchain for the team to learn and operate. Dockerfiles are more familiar and widely integrated, while Nix provides stronger control over build inputs and reproducibility.

---

## Bonus — CI-Verified Reproducibility

CI workflow: `.github/workflows/nix-repro.yml`

```yaml
name: Nix Reproducibility

on:
  push:
  pull_request:

permissions:
  contents: read

jobs:
  build-a:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.digest.outputs.digest }}

    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa

      - name: Build OCI image
        run: nix build .#docker

      - name: Compute digest
        id: digest
        run: |
          DIGEST=$(sha256sum result | awk '{print $1}')
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
          echo "Build A digest: $DIGEST"

  build-b:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.digest.outputs.digest }}

    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa

      - name: Build OCI image
        run: nix build .#docker

      - name: Compute digest
        id: digest
        run: |
          DIGEST=$(sha256sum result | awk '{print $1}')
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
          echo "Build B digest: $DIGEST"

  compare:
    runs-on: ubuntu-latest
    needs:
      - build-a
      - build-b

    steps:
      - name: Compare digests
        env:
          DIGEST_A: ${{ needs.build-a.outputs.digest }}
          DIGEST_B: ${{ needs.build-b.outputs.digest }}
        run: |
          echo "Build A: $DIGEST_A"
          echo "Build B: $DIGEST_B"

          if [ "$DIGEST_A" != "$DIGEST_B" ]; then
            echo "Reproducibility check FAILED"
            exit 1
          fi

          echo "Reproducibility check PASSED"
```

The checkout and Nix installer actions are pinned by full commit SHA.

### Red → green proof

**Deliberately broken run**

https://github.com/fsstilerr/DevOps-Intro/actions/runs/38654077396

The two build jobs completed, but the third comparison job detected the deliberately introduced divergence and failed:

```text
build-a   PASS
build-b   PASS
compare   FAIL
Process completed with exit code 1
```

**Fixed green run**

https://github.com/fsstilerr/DevOps-Intro/actions/runs/38654244688

Both fresh runners completed successfully and the comparison gate passed:

```text
build-a   PASS
build-b   PASS
compare   PASS
Reproducibility check PASSED
```

The workflow passes only when `DIGEST_A == DIGEST_B`; the successful `compare` job is the CI assertion that both independently produced digests matched.

### Design questions

#### h) Why is CI reproducibility stronger than “reproducible on my laptop”?
Two local builds can share the same Nix store, caches and host state. Separate GitHub-hosted runners reconstruct the artifact independently, so matching results are stronger evidence that the output is determined by the declared inputs rather than local machine state.

#### i) Why two parallel jobs instead of building twice in one job?
Two builds in one job share the same runner and Nix store, so the second build may simply reuse the first result. Parallel jobs use independent fresh runners and therefore provide a stronger reproducibility test.

#### j) Where can timestamps leak, and how does `dockerTools.buildImage` handle them?
OCI image configuration and layer metadata can contain creation timestamps. Embedding the current wall-clock time makes otherwise identical archives differ. `dockerTools.buildImage` uses deterministic image construction rather than relying on the current build time, which allows independently generated image tarballs to match.

---

## Result

- Task 1: completed — `flake.nix`, `flake.lock`, runtime proof and identical store hashes
- Task 2: completed — loadable deterministic OCI image, identical independent SHA-256 values and Docker comparison
- Bonus: completed — two-parallel-job CI gate with deliberate RED → GREEN proof
