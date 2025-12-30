[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Apply
)

class EnvPathItem {
    [string]$RawPath
    [string]$CleanPath
    [string]$ExpandedPath
    [string]$NormalizedPath
    [string]$Scope

    EnvPathItem([string]$rawPath, [string]$scope) {
        $this.RawPath = $rawPath
        $this.Scope = $scope
        $this.CleanPath = [EnvPathItem]::RemoveTrailingSeparator($rawPath)
        $this.ExpandedPath = [Environment]::ExpandEnvironmentVariables($this.CleanPath)
        $this.NormalizedPath = [EnvPathItem]::NormalizePath($this.ExpandedPath)
    }

    static [string] RemoveTrailingSeparator([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $path
        }

        $trimmed = [EnvPathItem]::CollapseSeparators($path.Trim())
        $isDriveRoot = $trimmed -match '^[A-Za-z]:\\$'

        if ($isDriveRoot) {
            return $trimmed
        }

        return $trimmed.TrimEnd('\', '/')
    }

    static [string] NormalizePath([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $null
        }

        $normalized = [EnvPathItem]::CollapseSeparators($path.Trim().Replace('/', '\'))
        $isDriveRoot = $normalized -match '^[A-Za-z]:\\$'

        if (-not $isDriveRoot) {
            $normalized = $normalized.TrimEnd('\')
        }

        return $normalized.ToLowerInvariant()
    }

    static [string] CollapseSeparators([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $path
        }

        $isUnc = $path.StartsWith('\\')

        if ($isUnc) {
            $withoutPrefix = $path.TrimStart('\')
            $collapsed = ($withoutPrefix -replace '\\{2,}', '\')
            return "\\\\$collapsed"
        }

        return ($path -replace '\\{2,}', '\')
    }
}

function Get-PathVariableMap {
    $names = @(
        'USERPROFILE',
        'SystemRoot',
        'ProgramFiles',
        'ProgramFiles(x86)',
        'ProgramData',
        'LOCALAPPDATA',
        'APPDATA',
        'TEMP',
        'TMP',
        'JAVA_HOME'
    )

    $map = @{}
    foreach ($name in $names) {
        $value = [Environment]::GetEnvironmentVariable($name)

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $map[$name] = [EnvPathItem]::RemoveTrailingSeparator($value)
        }
    }

    return $map
}

function Get-PreferredPath {
    param(
        [EnvPathItem]$Item,
        [hashtable]$VariableMap
    )

    $rawClean = [EnvPathItem]::RemoveTrailingSeparator($Item.RawPath)

    if ($rawClean -like '%*%') {
        return $rawClean
    }

    $expandedNormalized = [EnvPathItem]::CollapseSeparators($Item.ExpandedPath)

    foreach ($entry in ($VariableMap.GetEnumerator() | Sort-Object { $_.Value.Length } -Descending)) {
        $baseValue = [EnvPathItem]::CollapseSeparators($entry.Value)

        if ([string]::IsNullOrWhiteSpace($baseValue)) {
            continue
        }

        if ($expandedNormalized.StartsWith($baseValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $suffix = $expandedNormalized.Substring($baseValue.Length).TrimStart('\')

            if ([string]::IsNullOrWhiteSpace($suffix)) {
                return "%$($entry.Key)%"
            }

            return "%$($entry.Key)%\$suffix"
        }
    }

    return $rawClean
}

function Split-PathList {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return @()
    }

    return $PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Join-PathList {
    param(
        [string[]]$Paths
    )

    return ($Paths -join ';')
}

function Optimize-EnvironmentPaths {
    [CmdletBinding()]
    param(
        [string[]]$UserPaths,
        [string[]]$MachinePaths
    )

    $userProfile = [EnvPathItem]::NormalizePath([EnvPathItem]::RemoveTrailingSeparator([Environment]::GetEnvironmentVariable('USERPROFILE')))
    $variableMap = Get-PathVariableMap

    $userItems = @()
    foreach ($path in ($UserPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $item = [EnvPathItem]::new($path, 'User')

        if (Test-Path -LiteralPath $item.ExpandedPath) {
            $userItems += $item
        }
    }

    $machineItems = @()
    foreach ($path in ($MachinePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $item = [EnvPathItem]::new($path, 'Machine')

        if (Test-Path -LiteralPath $item.ExpandedPath) {
            $machineItems += $item
        }
    }

    $relocated = @()
    foreach ($item in $machineItems) {
        if ($null -ne $userProfile -and $item.NormalizedPath -like "$userProfile*") {
            $item.Scope = 'User'
            $relocated += $item
        }
    }

    if ($relocated.Count -gt 0) {
        $machineItems = $machineItems | Where-Object { $_ -notin $relocated }
        $userItems += $relocated
    }

    $machineSeen = New-Object 'System.Collections.Generic.HashSet[string]'
    $machineResult = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $machineItems) {
        if ($null -ne $item.NormalizedPath -and $machineSeen.Add($item.NormalizedPath)) {
            $machineResult.Add((Get-PreferredPath -Item $item -VariableMap $variableMap))
        }
    }

    $userSeen = New-Object 'System.Collections.Generic.HashSet[string]'
    $userResult = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $userItems) {
        if ($machineSeen.Contains($item.NormalizedPath)) {
            continue
        }

        if ($null -ne $item.NormalizedPath -and $userSeen.Add($item.NormalizedPath)) {
            $userResult.Add((Get-PreferredPath -Item $item -VariableMap $variableMap))
        }
    }

    return [PSCustomObject]@{
        User    = $userResult.ToArray()
        Machine = $machineResult.ToArray()
    }
}

function Backup-EnvironmentPaths {
    [CmdletBinding()]
    param(
        [string[]]$UserPaths,
        [string[]]$MachinePaths,
        [string]$DestinationDirectory
    )

    $targetDirectory = if (-not [string]::IsNullOrWhiteSpace($DestinationDirectory)) { $DestinationDirectory } else { [IO.Path]::GetTempPath() }

    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $backupPath = Join-Path -Path $targetDirectory -ChildPath "EnvBackup_$timestamp.json"
    $content = [PSCustomObject]@{
        User    = $UserPaths
        Machine = $MachinePaths
    }

    $content | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backupPath -Encoding utf8

    return $backupPath
}

function Set-EnvironmentPath {
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Machine')]
        [string]$Scope,
        [string[]]$Paths
    )

    $value = Join-PathList -Paths $Paths
    [Environment]::SetEnvironmentVariable('PATH', $value, $Scope)
}

function Send-EnvironmentChange {
    if (-not ([System.Management.Automation.PSTypeName]'OptimizeEnv.NativeMethods').Type) {
        Add-Type -Namespace OptimizeEnv -Name NativeMethods -MemberDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeMethods
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);
}
"@ -ErrorAction SilentlyContinue | Out-Null
    }

    $result = [UIntPtr]::Zero
    [OptimizeEnv.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 0x0002, 1000, [ref]$result) | Out-Null
}

function Invoke-OptimizeEnvironmentVariable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$UserPath,
        [string]$MachinePath,
        [switch]$Apply,
        [string]$BackupDirectory,
        [ScriptBlock]$BackupHandler,
        [ScriptBlock]$SetEnvironmentPathHandler,
        [ScriptBlock]$SendEnvironmentChangeHandler
    )

    $currentUserPath = if ($PSBoundParameters.ContainsKey('UserPath')) { $UserPath } else { [Environment]::GetEnvironmentVariable('PATH', 'User') }
    $currentMachinePath = if ($PSBoundParameters.ContainsKey('MachinePath')) { $MachinePath } else { [Environment]::GetEnvironmentVariable('PATH', 'Machine') }

    $userPaths = Split-PathList -PathValue $currentUserPath
    $machinePaths = Split-PathList -PathValue $currentMachinePath

    $optimized = Optimize-EnvironmentPaths -UserPaths $userPaths -MachinePaths $machinePaths

    $result = [PSCustomObject]@{
        UserBefore    = $userPaths
        MachineBefore = $machinePaths
        UserAfter     = $optimized.User
        MachineAfter  = $optimized.Machine
    }

    if ($Apply) {
        if ($WhatIfPreference) {
            Write-Verbose 'WhatIf指定のため適用をスキップします。'
        }
        else {
            $backupAction = if ($BackupHandler) { $BackupHandler } else { { param($u, $m, $dir) Backup-EnvironmentPaths -UserPaths $u -MachinePaths $m -DestinationDirectory $dir } }
            $setAction = if ($SetEnvironmentPathHandler) { $SetEnvironmentPathHandler } else { { param($s, $p) Set-EnvironmentPath -Scope $s -Paths $p } }
            $sendAction = if ($SendEnvironmentChangeHandler) { $SendEnvironmentChangeHandler } else { { Send-EnvironmentChange } }

            Write-Verbose 'Applying optimized paths'
            & $backupAction $userPaths $machinePaths $BackupDirectory | Out-Null
            & $setAction 'User' $optimized.User
            & $setAction 'Machine' $optimized.Machine
            & $sendAction
        }
    }
    else {
        Write-Verbose 'Dry-Runモード。-Apply を指定すると変更を保存します。'
    }

    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-OptimizeEnvironmentVariable @PSBoundParameters
}
