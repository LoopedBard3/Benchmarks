<#
.SYNOPSIS
Runs the manual container comparison matrix against the remote benchmark agents.

.EXAMPLE
.\scripts\run-container-comparison.ps1 -Mode preflight -TargetHost both -DryRun

.EXAMPLE
.\scripts\run-container-comparison.ps1 -Mode preflight -TargetHost both -ParallelHosts

.EXAMPLE
.\scripts\run-container-comparison.ps1 -Mode full -TargetHost gold-lin

.EXAMPLE
.\scripts\run-container-comparison.ps1 -Mode full -TargetHost both -UseRelay -ParallelHosts -OutputDirectory .\artifacts\container-comparison\full-run -Resume

.EXAMPLE
.\scripts\run-container-comparison.ps1 -Mode full -TargetHost gold-lin -UseRelay -ScenarioFilter json_fasthttp -NormalizeFastHttpGoMaxProcs -OutputDirectory .\artifacts\container-comparison\fasthttp-gomaxprocs
#>

[CmdletBinding()]
param(
    [ValidateSet("preflight", "full")]
    [string]$Mode = "preflight",

    [ValidateSet("gold-lin", "cobalt-cloud-lin", "both")]
    [string]$TargetHost = "both",

    [string]$BenchmarksRepository = "https://github.com/LoopedBard3/Benchmarks.git",

    [string]$BenchmarksRef = "",

    [string]$OutputDirectory = "",

    [string]$Session = "",

    [string]$CrankPath = "crank",

    [ValidateSet("json_aspnet", "fortunes_aspnet", "json_fasthttp", "fortunes_fasthttp", "json_xitca", "fortunes_xitca")]
    [string[]]$ScenarioFilter = @(),

    [switch]$ParallelHosts,

    [switch]$UseRelay,

    [switch]$NormalizeFastHttpGoMaxProcs,

    [switch]$DryRun,

    [switch]$Resume,

    [switch]$SkipRemoteRefCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "scenarios\container-comparison.benchmarks.yml"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputDirectoryWasExplicit = -not [string]::IsNullOrWhiteSpace($OutputDirectory)

if ([string]::IsNullOrWhiteSpace($BenchmarksRef)) {
    $BenchmarksRef = (& git -C $repoRoot branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($BenchmarksRef)) {
        throw "Could not determine the current Git branch. Pass -BenchmarksRef explicitly."
    }
}

if ($Resume -and [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw "-Resume requires an explicit -OutputDirectory that points to an existing run directory."
}

if ($NormalizeFastHttpGoMaxProcs -and -not $outputDirectoryWasExplicit) {
    throw "-NormalizeFastHttpGoMaxProcs requires an explicit -OutputDirectory dedicated to normalized runs so baseline results cannot be overwritten."
}

if ($Resume -and -not (Test-Path $OutputDirectory -PathType Container)) {
    throw "Resume output directory does not exist: $OutputDirectory"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "artifacts\container-comparison\$timestamp"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

if ([string]::IsNullOrWhiteSpace($Session)) {
    $Session = "container-comparison-$timestamp"
}

if (-not (Test-Path $configPath -PathType Leaf)) {
    throw "Crank configuration not found: $configPath"
}

if (-not $DryRun -and -not (Get-Command $CrankPath -ErrorAction SilentlyContinue)) {
    throw "Crank was not found as '$CrankPath'. Install Microsoft.Crank.Controller or pass -CrankPath."
}

if (-not $DryRun -and -not $SkipRemoteRefCheck -and $BenchmarksRef -notmatch "^[0-9a-fA-F]{40}$") {
    & git ls-remote --exit-code $BenchmarksRepository "refs/heads/$BenchmarksRef" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Branch '$BenchmarksRef' is not accessible in '$BenchmarksRepository'. Push it or pass a reachable ref."
    }
}

if (-not $DryRun -and -not $SkipRemoteRefCheck -and $BenchmarksRef -match "^[0-9a-fA-F]{40}$") {
    Write-Warning "A commit SHA cannot be fully verified with ls-remote unless it is a ref tip. Crank will verify that '$BenchmarksRef' is reachable."
}

$hosts = if ($UseRelay) {
    @{
        "gold-lin" = [pscustomobject]@{
            ProfilePath = Join-Path $repoRoot "scenarios\aspnet.profiles.yml"
            Profiles = @("aspnet-gold-lin-relay")
            Arguments = @("--relay")
        }
        "cobalt-cloud-lin" = [pscustomobject]@{
            ProfilePath = Join-Path $repoRoot "build\azure.profile.yml"
            Profiles = @("cobalt-cloud-lin-relay")
            Arguments = @("--relay")
        }
    }
} else {
    @{
        "gold-lin" = [pscustomobject]@{
            ProfilePath = Join-Path $repoRoot "build\ci.profile.yml"
            Profiles = @("gold-lin-app", "gold-load-load", "gold-db-db")
            Arguments = @()
        }
        "cobalt-cloud-lin" = [pscustomobject]@{
            ProfilePath = Join-Path $repoRoot "build\azure.profile.yml"
            Profiles = @("cobalt-cloud-lin-server-app", "cobalt-cloud-lin-client-load", "cobalt-cloud-lin-db-db")
            Arguments = @()
        }
    }
}

$scenarios = @(
    [pscustomobject]@{ Id = "json_aspnet"; Label = "aspnet-json"; IsAspNet = $true; IsFastHttp = $false; ExtraArgs = @("--property", "scenario=JsonAspNetNet11") },
    [pscustomobject]@{ Id = "fortunes_aspnet"; Label = "aspnet-fortunes"; IsAspNet = $true; IsFastHttp = $false; ExtraArgs = @("--property", "scenario=FortunesAspNetNet11", "--application.environmentVariables", "DOTNET_gcServer=1", "--application.environmentVariables", "DOTNET_GCDynamicAdaptationMode=0") },
    [pscustomobject]@{ Id = "json_fasthttp"; Label = "fasthttp-json"; IsAspNet = $false; IsFastHttp = $true; ExtraArgs = @("--property", "scenario=JsonFastHttp") },
    [pscustomobject]@{ Id = "fortunes_fasthttp"; Label = "fasthttp-fortunes"; IsAspNet = $false; IsFastHttp = $true; ExtraArgs = @("--property", "scenario=FortunesFastHttp") },
    [pscustomobject]@{ Id = "json_xitca"; Label = "xitca-web-json"; IsAspNet = $false; IsFastHttp = $false; ExtraArgs = @("--property", "scenario=JsonXitcaWeb") },
    [pscustomobject]@{ Id = "fortunes_xitca"; Label = "xitca-web-fortunes"; IsAspNet = $false; IsFastHttp = $false; ExtraArgs = @("--property", "scenario=FortunesXitcaWeb") }
)

if ($ScenarioFilter.Count -gt 0) {
    $scenarios = @($scenarios | Where-Object Id -in $ScenarioFilter)
}

$allSizes = @(
    [pscustomobject]@{ Id = "quota-0.1-256mb"; Label = "0.1 CPU quota / 256 MB"; FastHttpGoMaxProcs = "1"; Args = @("--property", "cpu=0.1", "--property", "mem=256mb", "--property", "size=100m-256mb", "--application.cpuLimitRatio", "0.1", "--application.memoryLimitInBytes", "256000000") },
    [pscustomobject]@{ Id = "quota-0.25-256mb"; Label = "0.25 CPU quota / 256 MB"; FastHttpGoMaxProcs = "1"; Args = @("--property", "cpu=0.25", "--property", "mem=256mb", "--property", "size=250m-256mb", "--application.cpuLimitRatio", "0.25", "--application.memoryLimitInBytes", "256000000") },
    [pscustomobject]@{ Id = "quota-0.5-256mb"; Label = "0.5 CPU quota / 256 MB"; FastHttpGoMaxProcs = "1"; Args = @("--property", "cpu=0.5", "--property", "mem=256mb", "--property", "size=500m-256mb", "--application.cpuLimitRatio", "0.5", "--application.memoryLimitInBytes", "256000000") },
    [pscustomobject]@{ Id = "quota-1-512mb"; Label = "1 CPU quota / 512 MB"; FastHttpGoMaxProcs = "1"; Args = @("--property", "cpu=1", "--property", "mem=512mb", "--property", "size=1000m-512mb", "--application.cpuLimitRatio", "1", "--application.memoryLimitInBytes", "512000000") },
    [pscustomobject]@{ Id = "quota-4-1gb"; Label = "4 CPU quota / 1 GB"; FastHttpGoMaxProcs = "4"; Args = @("--property", "cpu=4", "--property", "mem=1gb", "--property", "size=4000m-1gb", "--application.cpuLimitRatio", "4", "--application.memoryLimitInBytes", "1000000000") },
    [pscustomobject]@{ Id = "unlimited"; Label = "Unlimited"; FastHttpGoMaxProcs = $null; Args = @("--property", "cpu=unlimited", "--property", "mem=unlimited", "--property", "size=unlimited") },
    [pscustomobject]@{ Id = "pinned-1-512mb"; Label = "Pinned 1 core / 512 MB"; FastHttpGoMaxProcs = "1"; Args = @("--property", "cpu=1", "--property", "mem=512mb", "--property", "size=1core-512mb", "--application.cpuSet", "0", "--application.memoryLimitInBytes", "512000000") },
    [pscustomobject]@{ Id = "pinned-4-1gb"; Label = "Pinned 4 cores / 1 GB"; FastHttpGoMaxProcs = "4"; Args = @("--property", "cpu=4", "--property", "mem=1gb", "--property", "size=4cores-1gb", "--application.cpuSet", "0-3", "--application.memoryLimitInBytes", "1000000000") }
)

$allRates = @(
    [pscustomobject]@{ Id = "1000rps"; Label = "1000 RPS"; Args = @("--variable", "rate=1000", "--property", "rate=1000", "--load.job", "bombardier") },
    [pscustomobject]@{ Id = "10000rps"; Label = "10000 RPS"; Args = @("--variable", "rate=10000", "--property", "rate=10000", "--load.job", "bombardier") },
    [pscustomobject]@{ Id = "unbound"; Label = "Unbound"; Args = @("--property", "rate=0") }
)

if ($Mode -eq "preflight") {
    $sizes = @($allSizes | Where-Object Id -eq "quota-1-512mb")
    $rates = @($allRates | Where-Object Id -eq "1000rps")
} else {
    $sizes = $allSizes
    $rates = $allRates
}

$selectedHosts = if ($TargetHost -eq "both") { @("gold-lin", "cobalt-cloud-lin") } else { @($TargetHost) }

if ($ParallelHosts -and $selectedHosts.Count -gt 1) {
    $scenarioFilterValue = $ScenarioFilter -join ","
    $jobs = foreach ($hostName in $selectedHosts) {
        Start-Job -Name "container-comparison-$hostName" -ScriptBlock {
            param($ScriptPath, $RunMode, $TargetHost, $Repository, $Ref, $Output, $SessionName, $Executable, $FilterValue, $IsRelay, $IsNormalized, $IsDryRun, $IsResume, $SkipCheck)
            $childParameters = @{
                Mode = $RunMode
                TargetHost = $TargetHost
                BenchmarksRepository = $Repository
                BenchmarksRef = $Ref
                OutputDirectory = $Output
                Session = $SessionName
                CrankPath = $Executable
                UseRelay = $IsRelay
                NormalizeFastHttpGoMaxProcs = $IsNormalized
                DryRun = $IsDryRun
                Resume = $IsResume
                SkipRemoteRefCheck = $SkipCheck
            }
            if (-not [string]::IsNullOrWhiteSpace($FilterValue)) {
                $childParameters.ScenarioFilter = @($FilterValue.Split(","))
            }
            & $ScriptPath @childParameters
        } -ArgumentList $PSCommandPath, $Mode, $hostName, $BenchmarksRepository, $BenchmarksRef, $OutputDirectory, $Session, $CrankPath, $scenarioFilterValue, $UseRelay.IsPresent, $NormalizeFastHttpGoMaxProcs.IsPresent, $DryRun.IsPresent, $Resume.IsPresent, $SkipRemoteRefCheck.IsPresent
    }

    $jobs | Wait-Job | Out-Null
    $failedJobs = @($jobs | Where-Object State -ne "Completed")
    $failedJobNames = @($failedJobs | ForEach-Object Name)
    foreach ($job in $jobs) {
        Receive-Job -Job $job -ErrorAction Continue
    }
    $jobs | Remove-Job
    if ($failedJobs.Count -gt 0) {
        throw "One or more host runs failed: $($failedJobNames -join ', ')"
    }
    return
}

function Format-Command {
    param([string[]]$Arguments)

    return ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + $_.Replace('"', '\"') + '"'
        } else {
            $_
        }
    }) -join " "
}

function Format-StableManifestCommand {
    param([string]$Command)

    return (($Command -replace '(?:^|\s)--session\s+(?:"(?:\\.|[^"])*"|\S+)', "") -replace "\s+", " ").Trim()
}

foreach ($hostName in $selectedHosts) {
    $hostConfig = $hosts[$hostName]
    if (-not (Test-Path $hostConfig.ProfilePath -PathType Leaf)) {
        throw "Host profile not found: $($hostConfig.ProfilePath)"
    }

    $hostOutput = Join-Path $OutputDirectory $hostName
    New-Item -ItemType Directory -Force -Path $hostOutput | Out-Null
    $plan = [System.Collections.Generic.List[object]]::new()

    foreach ($scenario in $scenarios) {
        foreach ($size in $sizes) {
            foreach ($rate in $rates) {
                $resultPath = Join-Path $hostOutput "$($scenario.Label)-$($size.Id)-$($rate.Id).json"
                $description = "$($scenario.Label) - $($size.Label) - $($rate.Label) - $hostName"
                $arguments = @(
                    "--config", $configPath,
                    "--config", $hostConfig.ProfilePath,
                    "--scenario", $scenario.Id
                )

                foreach ($profile in $hostConfig.Profiles) {
                    $arguments += @("--profile", $profile)
                }

                $arguments += $hostConfig.Arguments

                if ($scenario.IsAspNet) {
                    $arguments += @(
                        "--application.source.repository", $BenchmarksRepository,
                        "--application.source.branchOrCommit", $BenchmarksRef
                    )
                }

                $arguments += $scenario.ExtraArgs
                $fastHttpGoMaxProcs = ""
                if ($NormalizeFastHttpGoMaxProcs -and $scenario.IsFastHttp) {
                    $fastHttpGoMaxProcs = if ($null -eq $size.FastHttpGoMaxProcs) { "default" } else { $size.FastHttpGoMaxProcs }
                    $arguments += @("--property", "fastHttpGoMaxProcs=$fastHttpGoMaxProcs")
                    if ($fastHttpGoMaxProcs -ne "default") {
                        $arguments += @("--application.environmentVariables", "GOMAXPROCS=$fastHttpGoMaxProcs")
                    }
                }
                $arguments += $size.Args
                $arguments += $rate.Args
                $arguments += @(
                    "--session", $Session,
                    "--description", $description,
                    "--json", $resultPath,
                    "--load.options.reuseBuild", "true"
                )

                $command = Format-Command -Arguments (@($CrankPath) + $arguments)
                $plan.Add([pscustomobject]@{
                    Host = $hostName
                    Scenario = $scenario.Id
                    Size = $size.Id
                    Rate = $rate.Id
                    NormalizeFastHttpGoMaxProcs = $NormalizeFastHttpGoMaxProcs.IsPresent
                    FastHttpGoMaxProcs = $fastHttpGoMaxProcs
                    Result = $resultPath
                    Command = $command
                    Arguments = $arguments
                })
            }
        }
    }

    $expectedCount = if ($ScenarioFilter.Count -eq 0) {
        if ($Mode -eq "preflight") { 6 } else { 144 }
    } else {
        $scenarios.Count * $sizes.Count * $rates.Count
    }
    if ($plan.Count -ne $expectedCount) {
        throw "Generated $($plan.Count) runs for $hostName; expected $expectedCount."
    }

    $manifestPath = Join-Path $hostOutput "run-manifest.csv"
    if ($NormalizeFastHttpGoMaxProcs -and (Test-Path $manifestPath -PathType Leaf)) {
        $existingManifest = @(Import-Csv $manifestPath)
        if ($existingManifest.Count -ne $plan.Count) {
            throw "Normalized plan does not match the existing manifest at '$manifestPath'. Use a separate output directory for the normalized retest."
        }

        for ($index = 0; $index -lt $plan.Count; $index++) {
            $existing = $existingManifest[$index]
            $generated = $plan[$index]
            if (
                $null -eq $existing.PSObject.Properties["NormalizeFastHttpGoMaxProcs"] -or
                $existing.NormalizeFastHttpGoMaxProcs -ne "True" -or
                $existing.Host -ne $generated.Host -or
                $existing.Scenario -ne $generated.Scenario -or
                $existing.Size -ne $generated.Size -or
                $existing.Rate -ne $generated.Rate -or
                $existing.Result -ne $generated.Result -or
                (Format-StableManifestCommand $existing.Command) -ne (Format-StableManifestCommand $generated.Command)
            ) {
                throw "Normalized plan does not match the existing manifest at '$manifestPath'. Use a separate output directory for the normalized retest."
            }
        }
    } elseif ($NormalizeFastHttpGoMaxProcs -and $Resume) {
        throw "Cannot resume a normalized run without its matching manifest at '$manifestPath'. Use the normalized run's original output directory."
    } elseif ($NormalizeFastHttpGoMaxProcs -and (Get-ChildItem $hostOutput -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        throw "Normalized output directory contains result files but no matching manifest: '$hostOutput'. Use a separate output directory."
    }

    $plan | Select-Object Host, Scenario, Size, Rate, NormalizeFastHttpGoMaxProcs, FastHttpGoMaxProcs, Result, Command | Export-Csv -NoTypeInformation -Path $manifestPath
    Write-Host "[$hostName] $Mode plan: $($plan.Count) runs. Manifest: $manifestPath"

    $runsToExecute = [System.Collections.Generic.List[object]]::new()
    $skippedCount = 0
    foreach ($run in $plan) {
        if (-not $Resume) {
            $runsToExecute.Add($run)
            continue
        }

        $retryReason = $null
        if (-not (Test-Path $run.Result -PathType Leaf)) {
            $retryReason = "result file is missing"
        } else {
            try {
                $existingResult = Get-Content $run.Result -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $existingResult) {
                    $retryReason = "result JSON is empty"
                } elseif ($null -eq $existingResult.PSObject.Properties["returnCode"]) {
                    $retryReason = "result JSON has no top-level returnCode"
                } elseif ($existingResult.PSObject.Properties["returnCode"].Value -ne 0) {
                    $retryReason = "returnCode is $($existingResult.PSObject.Properties["returnCode"].Value)"
                }
            } catch {
                $retryReason = "result JSON is malformed"
            }
        }

        if ($null -eq $retryReason) {
            $skippedCount++
            Write-Host "[$hostName] Skipping $($run.Scenario) / $($run.Size) / $($run.Rate): returnCode is 0."
            continue
        }

        Write-Host "[$hostName] Retrying $($run.Scenario) / $($run.Size) / $($run.Rate): $retryReason."
        $runsToExecute.Add($run)
    }

    Write-Host "[$hostName] Completed/skipped: $skippedCount; remaining: $($runsToExecute.Count)."

    foreach ($run in $runsToExecute) {
        Write-Host "[$hostName] $($run.Scenario) / $($run.Size) / $($run.Rate)"
        Write-Host $run.Command

        if ($DryRun) {
            continue
        }

        [string[]]$crankArguments = $run.Arguments
        & $CrankPath @crankArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Crank failed with exit code $LASTEXITCODE for $($run.Scenario) / $($run.Size) / $($run.Rate) on $hostName."
        }
    }
}
