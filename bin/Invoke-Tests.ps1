[CmdletBinding()]
param()

$config = New-PesterConfiguration
$config.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath "../tests/Optimize-EnvironmentVariable.Tests.ps1"
$config.TestRegistry.Enabled = $false
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
