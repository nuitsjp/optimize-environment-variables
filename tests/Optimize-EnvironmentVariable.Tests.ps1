Param()

Describe "Optimize-EnvironmentPaths" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../src/Optimize-EnvironmentVariable.ps1")
    }

    Context "重複排除" {
        It "NormalizedPathが同じ要素は1つにまとめる" {
            Mock Test-Path { $true }

            $result = Optimize-EnvironmentPaths -UserPaths @() -MachinePaths @("C:\Tools\", "c:\tools")

            $result.Machine | Should -Be @("C:\Tools")
        }
    }

    Context "末尾スラッシュの扱い" {
        It "ルート以外の末尾スラッシュを削除する" {
            Mock Test-Path { $true }

            $result = Optimize-EnvironmentPaths -UserPaths @() -MachinePaths @("C:\", "C:\foo\", "C:\foo\\")

            $result.Machine | Should -Be @("C:\", "C:\foo")
        }
    }

    Context "クロススコープの重複" {
        It "MachineのパスがUserに優先して残る" {
            Mock Test-Path { $true }

            $result = Optimize-EnvironmentPaths -UserPaths @("C:\Tools", "D:\Apps") -MachinePaths @("c:\tools")

            $result.Machine | Should -Be @("C:\Tools")
            $result.User | Should -Be @("D:\Apps")
        }
    }

    Context "スコープ移動" {
        It "ユーザープロファイル配下のパスはMachineからUserへ移動する" {
            $originalProfile = $env:USERPROFILE
            $env:USERPROFILE = "C:\Users\PesterUser"

            Mock Test-Path { $true }

            $result = Optimize-EnvironmentPaths -UserPaths @() -MachinePaths @("%USERPROFILE%\\bin\\")

            $result.Machine | Should -Be @()
            $result.User | Should -Be @("%USERPROFILE%\bin")

            $env:USERPROFILE = $originalProfile
        }
    }

    Context "変数復元" {
        It "ユーザープロファイル配下の絶対パスは%USERPROFILE%表記に戻す" {
            $originalProfile = $env:USERPROFILE
            $env:USERPROFILE = "C:\Users\PesterUser"

            Mock Test-Path { $true }

            $result = Optimize-EnvironmentPaths -UserPaths @() -MachinePaths @("C:\Users\PesterUser\bin")

            $result.User | Should -Be @("%USERPROFILE%\bin")

            $env:USERPROFILE = $originalProfile
        }
    }

}

Describe "Invoke-OptimizeEnvironmentVariable" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../src/Optimize-EnvironmentVariable.ps1")
    }

    BeforeEach {
        $script:originalProfile = $env:USERPROFILE
        $env:USERPROFILE = "C:\Users\PesterUser"
        Mock Test-Path { $true }
    }

    AfterEach {
        $env:USERPROFILE = $script:originalProfile
    }

    It "Dry-Runでは環境変数を書き換えない" {
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = 0

        Invoke-OptimizeEnvironmentVariable -UserPath "C:\Tools" -MachinePath "C:\Tools;C:\Windows" -BackupHandler { $null = $backupCalls.Add(@($args)) } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $sendCalls++ }

        $backupCalls.Count | Should -Be 0
        $setCalls.Count | Should -Be 0
        $sendCalls | Should -Be 0
    }

    It "Apply指定時に最適化結果を保存する" {
        $backupDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("pester-backup-" + [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = New-Object System.Collections.ArrayList

        $result = Invoke-OptimizeEnvironmentVariable -UserPath "%USERPROFILE%\bin;D:\LocalTools" -MachinePath "C:\Tools;D:\LocalTools;C:\Windows" -Apply -BackupDirectory $backupDir -BackupHandler { param($u, $m, $dir) $null = $backupCalls.Add([PSCustomObject]@{ User = $u; Machine = $m; Directory = $dir }); Backup-EnvironmentPaths -UserPaths $u -MachinePaths $m -DestinationDirectory $dir } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $null = $sendCalls.Add($true) }

        Get-ChildItem -Path $backupDir -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue

        $backupCalls.Count | Should -Be 1
        $result.UserBefore | Should -Contain "%USERPROFILE%\bin"
        $result.MachineBefore | Should -Contain "C:\Windows"
        ($setCalls | Where-Object { $_.Scope -eq 'User' }).Count | Should -Be 1
        ($setCalls | Where-Object { $_.Scope -eq 'User' }).Paths | Should -Contain "%USERPROFILE%\bin"
        ($setCalls | Where-Object { $_.Scope -eq 'Machine' }).Count | Should -Be 1
        ($setCalls | Where-Object { $_.Scope -eq 'Machine' }).Paths | Should -Contain "%SystemRoot%"
        $sendCalls.Count | Should -Be 1
    }
}
