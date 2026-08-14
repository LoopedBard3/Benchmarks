# Manual container comparison

This local-only harness compares .NET 11 ASP.NET, TechEmpower FastHTTP, and Rust xitca-web for JSON and Fortunes. It invokes Crank directly from this computer and does not use Azure Pipelines or Service Bus scheduling. The controller can connect through the repository's established Azure Service Bus relays or directly to the agents.

## Matrix

`full` runs 6 scenarios x 8 sizes x 3 rates: 144 runs per host and 288 total. `preflight` runs all 6 scenarios at 1 CPU quota / 512 MB and 1000 RPS: 6 runs per host and 12 total.

ASP.NET JSON and xitca-web JSON are database-free. FastHTTP JSON still requires PostgreSQL because the pinned TechEmpower process initializes its database connection at startup. All Fortunes scenarios are database-backed and include the database host in the measurement topology.

The unlimited size uses each host's available core count, so it is not a like-for-like CPU comparison. Fortunes also crosses different application, load, and database machines on each pod, so network and database-host differences remain part of those results.

## Run locally

Install the Crank controller. Use `-UseRelay` when this computer cannot reach the private agent network:

```powershell
dotnet tool install Microsoft.Crank.Controller --version "0.2.0-*" --global
.\scripts\run-container-comparison.ps1 -Mode preflight -TargetHost both -UseRelay -DryRun
.\scripts\run-container-comparison.ps1 -Mode preflight -TargetHost both -UseRelay -ParallelHosts
$outputDirectory = Join-Path $PWD "artifacts\container-comparison\full-run"
.\scripts\run-container-comparison.ps1 -Mode full -TargetHost both -UseRelay -ParallelHosts -OutputDirectory $outputDirectory
```

Run one host by setting `-TargetHost gold-lin` or `-TargetHost cobalt-cloud-lin`. Omit `-ParallelHosts` to run selected hosts sequentially. Omit `-UseRelay` to use the direct endpoints; direct mode requires access to the private network or VPN. Results and a command manifest are written under `artifacts/container-comparison/<timestamp>` by default.

If a full run stops, resume it with the same explicit output directory:

```powershell
$outputDirectory = Join-Path $PWD "artifacts\container-comparison\full-run"
.\scripts\run-container-comparison.ps1 -Mode full -TargetHost both -UseRelay -ParallelHosts -OutputDirectory $outputDirectory -Resume
```

`-Resume` requires an existing, explicitly supplied `-OutputDirectory`. It regenerates the complete deterministic manifest, skips only result files that contain valid JSON with a top-level `returnCode` of `0`, and retries missing, malformed, incomplete, or failed results. A newly attempted failure still stops the run immediately.

## Targeted FastHTTP GOMAXPROCS retest

`-ScenarioFilter` selects one or more of the six scenario IDs without changing the default matrix. For example, this generates the 24-run full FastHTTP JSON matrix only:

```powershell
$normalizedOutput = Join-Path $PWD "artifacts\container-comparison\fasthttp-json-gomaxprocs"
.\scripts\run-container-comparison.ps1 `
  -Mode full `
  -TargetHost gold-lin `
  -UseRelay `
  -ScenarioFilter json_fasthttp `
  -NormalizeFastHttpGoMaxProcs `
  -OutputDirectory $normalizedOutput `
  -DryRun
```

`-NormalizeFastHttpGoMaxProcs` affects FastHTTP scenarios only. It sets integer `GOMAXPROCS` from the CPU entitlement: quotas 0.1, 0.25, 0.5, and 1 plus pinned 1 use `1`; quota 4 and pinned 4 use `4`; unlimited leaves `GOMAXPROCS` unset so Go keeps its default. Each affected command also records `fastHttpGoMaxProcs=<n|default>` as a Crank property, and the manifest records both the normalization switch and effective value.

This is a modified comparison, not the pinned TechEmpower implementation's default runtime behavior. Normalized runs require an explicit, separate `-OutputDirectory`; do not reuse the baseline output root. Resume with the same options and normalized output directory. The runner refuses normalized resume when the existing manifest is absent, belongs to a baseline run, or otherwise differs from the regenerated normalized plan.

The ASP.NET container is built by the remote application agent, so its repository and ref must be remotely accessible even though the Crank configuration is local. A branch that exists only in this worktree cannot run. Push it first, then override the defaults when needed:

```powershell
.\scripts\run-container-comparison.ps1 `
  -Mode preflight `
  -TargetHost both `
  -BenchmarksRepository https://github.com/owner/Benchmarks.git `
  -BenchmarksRef owner/container-comparison
```

Relay mode passes Crank's `--relay` option. Gold loads `scenarios/aspnet.profiles.yml` with `aspnet-gold-lin-relay`, which maps application/load/db to `goldlin`, `goldload`, and `golddb`. cobalt loads the live-verified checked-in `build/azure.profile.yml` with `cobalt-cloud-lin-relay`, which maps those roles to `cobaltcloudlinserver`, `cobaltcloudlinclient`, and `cobaltcloudlindb` and uses the current `10.0.4.17`, `10.0.4.18`, and `10.0.4.19` private addresses. This intentionally uses the standard cobalt-cloud-lin server rather than the Azure Linux 3 relay.

Direct mode keeps the original profile wiring: Gold loads `build/ci.profile.yml` with `gold-lin-app`, `gold-load-load`, and `gold-db-db`; cobalt loads `build/azure.profile.yml` with `cobalt-cloud-lin-server-app`, `cobalt-cloud-lin-client-load`, and `cobalt-cloud-lin-db-db`.
