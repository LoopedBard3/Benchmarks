# Manual container comparison

This harness compares .NET 11 ASP.NET, TechEmpower FastHTTP, and Rust xitca-web for JSON and Fortunes. It is isolated from the generated scheduled pipelines and has `trigger: none` and `pr: none`.

## Matrix

`full` runs 6 scenarios x 8 sizes x 3 rates: 144 runs per host and 288 total. `preflight` runs all 6 scenarios at 1 CPU quota / 512 MB and 1000 RPS: 6 runs per host and 12 total. The Intel Gold Linux and cobalt-cloud-lin jobs have no dependency on each other, so their service bus queues can process them in parallel.

The unlimited size uses each host's available core count, so it is not a like-for-like CPU comparison. Fortunes also crosses different application, load, and database machines on each pod, so network and database-host differences remain part of those results.

## Queue manually

The Azure agents and remote Crank agents must download both the YAML configuration and the ASP.NET source. A branch that exists only in a local worktree cannot run remotely.

1. Push this branch (or an equivalent commit) to a GitHub repository that the agents can read.
2. In Azure Pipelines, create or select a pipeline whose YAML path is `build/container-comparison.yml` on that branch.
3. Choose **Run pipeline**, select the same branch, and leave `runMode` as `preflight`.
4. Set `benchmarksRepository` to that repository's clone URL, `benchmarksRef` to the pushed branch or commit, and `rawBaseUrl` to the matching raw-content root without a trailing slash.
5. Queue the 12-run preflight. After all scenarios succeed on both hosts, queue again with `runMode: full` for the 288-run matrix.

For example, a pushed branch named `owner/container-comparison` in `owner/Benchmarks` uses:

```text
benchmarksRepository = https://github.com/owner/Benchmarks.git
benchmarksRef        = owner/container-comparison
rawBaseUrl           = https://raw.githubusercontent.com/owner/Benchmarks/owner/container-comparison
```

The Gold job loads `build/ci.profile.yml` and uses `citrine1` with `gold-lin-app`, `gold-load-load`, and `gold-db-db`. The cobalt job loads `build/azure.profile.yml` and uses `azure` with `cobalt-cloud-lin-server-app`, `cobalt-cloud-lin-client-load`, and `cobalt-cloud-lin-db-db`.
