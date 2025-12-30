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
        Mock Out-Host {}
    }

    AfterEach {
        $env:USERPROFILE = $script:originalProfile
    }

    It "Dry-Runでは環境変数を書き換えない" {
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = 0

        Invoke-OptimizeEnvironmentVariable -UserPath "C:\Tools" -MachinePath "C:\Tools;C:\Windows" -PromptHandler { $false } -BackupHandler { $null = $backupCalls.Add(@($args)) } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $sendCalls++ }

        $backupCalls.Count | Should -Be 0
        $setCalls.Count | Should -Be 0
        $sendCalls | Should -Be 0
    }

    It "Force指定時に最適化結果を保存し、確認を行わない" {
        $backupDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("pester-backup-" + [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $promptCalls = New-Object System.Collections.ArrayList
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = New-Object System.Collections.ArrayList

        $result = Invoke-OptimizeEnvironmentVariable -UserPath "%USERPROFILE%\bin;D:\LocalTools" -MachinePath "C:\Tools;D:\LocalTools;C:\Windows" -Force -BackupDirectory $backupDir -PromptHandler { param($summary) $null = $promptCalls.Add($summary); throw "Force指定時に確認が呼ばれました" } -BackupHandler { param($u, $m, $dir) $null = $backupCalls.Add([PSCustomObject]@{ User = $u; Machine = $m; Directory = $dir }); Backup-EnvironmentPaths -UserPaths $u -MachinePaths $m -DestinationDirectory $dir } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $null = $sendCalls.Add($true) }

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
        $promptCalls.Count | Should -Be 0
    }

    It "Forceなしではサマリーを表示した上で確認する" {
        $promptCalls = New-Object System.Collections.ArrayList
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = New-Object System.Collections.ArrayList

        $result = Invoke-OptimizeEnvironmentVariable -UserPath "%USERPROFILE%\bin;D:\LocalTools" -MachinePath "C:\Tools;D:\LocalTools;C:\Windows" -PromptHandler { param($summary) $null = $promptCalls.Add($summary); return $false } -BackupHandler { param($u, $m, $dir) $null = $backupCalls.Add([PSCustomObject]@{ User = $u; Machine = $m; Directory = $dir }) } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $null = $sendCalls.Add($true) }

        $promptCalls.Count | Should -Be 1
        $summaryLines = $promptCalls[0]
        ($summaryLines -join "`n") | Should -Match 'User PATH \(chars: before .* -> after .*'
        ($summaryLines -join "`n") | Should -Match 'Machine PATH \(chars: before .* -> after .*'
        $backupCalls.Count | Should -Be 0
        $setCalls.Count | Should -Be 0
        $sendCalls.Count | Should -Be 0
    }

    It "Forceなしで確認がYなら保存する" {
        $promptCalls = New-Object System.Collections.ArrayList
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = New-Object System.Collections.ArrayList

        $result = Invoke-OptimizeEnvironmentVariable -UserPath "%USERPROFILE%\bin;D:\LocalTools" -MachinePath "C:\Tools;D:\LocalTools;C:\Windows" -PromptHandler { param($summary) $null = $promptCalls.Add($summary); $true } -BackupHandler { param($u, $m, $dir) $null = $backupCalls.Add([PSCustomObject]@{ User = $u; Machine = $m; Directory = $dir }) } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $null = $sendCalls.Add($true) }

        $promptCalls.Count | Should -Be 1
        $backupCalls.Count | Should -Be 1
        ($setCalls | Where-Object { $_.Scope -eq 'User' }).Count | Should -Be 1
        ($setCalls | Where-Object { $_.Scope -eq 'Machine' }).Count | Should -Be 1
        $sendCalls.Count | Should -Be 1
        $result.Summary | Should -Not -BeNullOrEmpty
    }

    It "Forceなしで確認がNなら保存しない" {
        $promptCalls = New-Object System.Collections.ArrayList
        $backupCalls = New-Object System.Collections.ArrayList
        $setCalls = New-Object System.Collections.ArrayList
        $sendCalls = New-Object System.Collections.ArrayList

        $result = Invoke-OptimizeEnvironmentVariable -UserPath "%USERPROFILE%\bin;D:\LocalTools" -MachinePath "C:\Tools;D:\LocalTools;C:\Windows" -PromptHandler { param($summary) $null = $promptCalls.Add($summary); $false } -BackupHandler { param($u, $m, $dir) $null = $backupCalls.Add([PSCustomObject]@{ User = $u; Machine = $m; Directory = $dir }) } -SetEnvironmentPathHandler { param($s, $p) $null = $setCalls.Add([PSCustomObject]@{ Scope = $s; Paths = $p }) } -SendEnvironmentChangeHandler { $null = $sendCalls.Add($true) }

        $promptCalls.Count | Should -Be 1
        $backupCalls.Count | Should -Be 0
        $setCalls.Count | Should -Be 0
        $sendCalls.Count | Should -Be 0
        $result.Summary | Should -Not -BeNullOrEmpty
    }

    It "Forceなしのサマリー出力はOut-Host経由で行う" {
        Invoke-OptimizeEnvironmentVariable -UserPath "%USERPROFILE%\bin;D:\LocalTools" -MachinePath "C:\Tools;D:\LocalTools;C:\Windows" -PromptHandler { $false }

        Assert-MockCalled -CommandName Out-Host
    }
}

Describe "Format-OptimizationResult" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../src/Optimize-EnvironmentVariable.ps1")
    }

    It "ユーザー/マシンの追加・維持・削除が縦に整形される" {
        $result = [PSCustomObject]@{
            UserBefore    = @("C:\Tools", "D:\Local")
            MachineBefore = @("C:\System", "D:\Local")
            UserAfter     = @("D:\Local", "E:\New")
            MachineAfter  = @("C:\System")
        }

        $formatted = Format-OptimizationResult -Result $result
        $formatted | Should -Contain "User PATH (chars: before 17 -> after 15, delta -2)"
        $formatted | Should -Contain "  Keep:"
        $formatted | Should -Contain "    - D:\Local"
        $formatted | Should -Contain "  Add:"
        $formatted | Should -Contain "    - E:\New"
        $formatted | Should -Contain "  Remove:"
        $formatted | Should -Contain "    - C:\Tools"
        $formatted | Should -Contain "Machine PATH (chars: before 18 -> after 9, delta -9)"
        $formatted | Should -Contain "    - D:\Local"
    }

    It "環境変数表記と絶対パスが同一でも、表記が変わるならUpdateとして表示する" {
        $originalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = "C:\Users\PesterUser\AppData\Local"
        $result = [PSCustomObject]@{
            UserBefore    = @("C:\Users\PesterUser\AppData\Local\Programs\Tool")
            MachineBefore = @()
            UserAfter     = @("%LOCALAPPDATA%\Programs\Tool")
            MachineAfter  = @()
        }

        $formatted = Format-OptimizationResult -Result $result
        $formatted | Should -Contain "  Update:"
        $formatted | Where-Object { $_ -like "*%LOCALAPPDATA%\Programs\Tool*" } | Should -Not -BeNullOrEmpty
        $formatted | Where-Object { $_ -like "*C:\Users\PesterUser\AppData\Local\Programs\Tool*" } | Should -BeNullOrEmpty
        $env:LOCALAPPDATA = $originalLocalAppData
    }

}

Describe "Send-EnvironmentChange" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../src/Optimize-EnvironmentVariable.ps1")
    }

    It "NativeMethods を追加しても例外を投げない" {
        { Send-EnvironmentChange } | Should -Not -Throw
    }
}

Describe "Invoke-Tests" {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
        $script:expectedCoverageOutput = Join-Path -Path $script:repoRoot -ChildPath "artifacts/coverage.xml"
        $script:expectedCoverageTarget = Join-Path -Path $script:repoRoot -ChildPath "src/Optimize-EnvironmentVariable.ps1"
        $script:invokeTestsScript = Join-Path -Path $PSScriptRoot -ChildPath "../bin/Invoke-Tests.ps1"
    }

    BeforeEach {
        $script:capturedConfig = $null
        Mock Invoke-Pester { param($Configuration) $script:capturedConfig = $Configuration }

        . $script:invokeTestsScript
    }

    It "既定ではVerbosity Normalで実行する" {
        $script:capturedConfig.Output.Verbosity.Value | Should -Be 'Normal'
    }

    It "PesterのCodeCoverageを有効にする" {
        $script:capturedConfig.CodeCoverage.Enabled.Value | Should -BeTrue
    }

    It "カバレージ出力先をartifacts/coverage.xmlにする" {
        $script:capturedConfig.CodeCoverage.OutputPath.Value | Should -Be $script:expectedCoverageOutput
    }

    It "カバレージ対象をsrc/Optimize-EnvironmentVariable.ps1に限定する" {
        $script:capturedConfig.CodeCoverage.Path.Value | Should -Be @($script:expectedCoverageTarget)
    }
}

