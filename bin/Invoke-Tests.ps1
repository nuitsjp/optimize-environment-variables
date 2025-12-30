[CmdletBinding()]
param()

$config = New-PesterConfiguration
$repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path

$artifactsDir = Join-Path -Path $repoRoot -ChildPath "artifacts"
New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null

$config.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath "../tests/Optimize-EnvironmentVariable.Tests.ps1"
$config.TestRegistry.Enabled = $false
$config.Output.Verbosity = 'Normal'

$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(Join-Path -Path $repoRoot -ChildPath "src/Optimize-EnvironmentVariable.ps1")
$config.CodeCoverage.OutputPath = Join-Path -Path $artifactsDir -ChildPath "coverage.xml"

Invoke-Pester -Configuration $config
