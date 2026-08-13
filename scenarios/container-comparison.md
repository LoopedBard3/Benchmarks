# Manual container comparison

This local-only harness compares .NET 11 ASP.NET, TechEmpower FastHTTP, and Rust xitca-web for JSON and Fortunes. It invokes Crank directly from this computer and does not use Azure Pipelines or Service Bus scheduling. The controller can connect through the repository's established Azure Service Bus relays or directly to the agents.

## Matrix

`full` runs 6 scenarios x 8 sizes x 3 rates: 144 runs per host and 288 total. `preflight` runs all 6 scenarios at 1 CPU quota / 512 MB and 1000 RPS: 6 runs per host and 12 total.

The unlimited size uses each host's available core count, so it is not a like-for-like CPU comparison. Fortunes also crosses different application, load, and database machines on each pod, so network and database-host differences remain part of those results.

## Run locally

Install the Crank controller. Use `-UseRelay` when this computer cannot reach the private agent network:

```powershell
dotnet tool install Microsoft.Crank.Controller --version "0.2.0-*" --global
.\scripts\run-container-comparison.ps1 -Mode preflight -TargetHost both -UseRelay -DryRun
.\scripts\run-container-comparison.ps1 -Mode preflight -TargetHost both -UseRelay -ParallelHosts
.\scripts\run-container-comparison.ps1 -Mode full -TargetHost both -UseRelay -ParallelHosts
```

Run one host by setting `-TargetHost gold-lin` or `-TargetHost cobalt-cloud-lin`. Omit `-ParallelHosts` to run selected hosts sequentially. Omit `-UseRelay` to use the direct endpoints; direct mode requires access to the private network or VPN. Results and a command manifest are written under `artifacts/container-comparison/<timestamp>` by default.

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
