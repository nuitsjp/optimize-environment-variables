# optimize-environment-variables

Windowsのシステム環境変数およびユーザー環境変数（主に `PATH`）を自動的に整理・最適化・クリーンアップするPowerShellスクリプトです。

重複の削除、パスの正規化、無効なパスの削除、適切なスコープ（System/User）への振り分けを安全かつ自動的に行います。

## 概要 (Features)

このスクリプトは以下の問題を解決します：

*   **重複の排除**: 同じパスが何度も登録されている状態を解消します。
*   **パスの正規化**: 末尾の不要なスラッシュ（`\`）を削除し、表記ゆれを統一します。
*   **無効なパスの削除**: ディスク上に存在しないフォルダ（Dead Link）を削除します。
*   **適切なスコープ管理**:
    *   ユーザーのホームディレクトリ配下のパスがシステム環境変数にある場合、ユーザー環境変数へ移動します。
    *   システムとユーザーで重複している場合、システム側を優先しユーザー側を削除します。
*   **変数の維持**: 可能であれば `%USERPROFILE%` や `%JAVA_HOME%` などの変数表記を維持・復元します。
*   **即時反映**: OS再起動なしで変更を反映させるため、環境変数の更新通知をブロードキャストします。
*   **安全性**: 自動バックアップとDry-Run（試行）モードを標準搭載しています。

## 動作環境 (Requirements)

*   **OS**: Windows 10 / 11 / Server 2016 以降
*   **PowerShell**: 5.1 以上 (または PowerShell Core 7+)
*   **権限**: システム環境変数を操作するため、**管理者権限 (Run as Administrator)** が必須です。

## 使い方 (Usage)

### クイックスタート (ワンライナー)
GitHubから直接スクリプトを読み込み実行します。デフォルトは **Dry-Run（変更なし）** モードで動作し、変更予定の内容を画面に表示します。

```powershell
Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"{Set-ExecutionPolicy RemoteSigned -scope CurrentUser -Force; iwr -useb https://raw.githubusercontent.com/nuitsjp/optimize-environment-variables/master/src/Optimize-EnvironmentVariable.ps1 | iex}`""
```

### 変更を適用する場合
実際に変更を適用するには、スクリプト実行時に `-Apply` スイッチを付与する必要があります（ワンライナーの場合はコード内の引数を修正するか、ローカルにダウンロードして実行してください）。

```powershell
# ローカル実行例
.\src\Optimize-EnvironmentVariable.ps1 -Apply -Verbose
```

## 仕様と設計 (Specification & Design)

### 1. 安全性設計 (Safety First)

*   **Dry-Run デフォルト**: 引数なしで実行した場合、システムに変更を加えません。シミュレーション結果のみを出力します。
*   **自動バックアップ**: `-Apply` 指定時、変更前に現在の `PATH`（User/Machine）を JSON 形式で `$env:TEMP\EnvBackup_<Timestamp>.json` に保存します。
*   **警告機能**: 結合後の環境変数文字列が 2048 文字（古いアプリの互換性目安）を超える場合、警告を表示します。

### 2. パス正規化とデータ構造

内部処理ではカスタムクラス `EnvPathItem` を定義し、以下の状態でパスを管理します。

*   **RawPath**: 環境変数から読み取ったそのままの値（例: `%USERPROFILE%\bin\`）
*   **ExpandedPath**: 変数を展開した絶対パス（例: `C:\Users\Nuits\bin\`）
*   **NormalizedPath**: 比較用の正規化パス
    *   すべて小文字化（Windowsはパスの大文字小文字を区別しないため）
    *   ルートドライブ（`D:\`）以外の末尾スラッシュを削除（`C:\foo\` -> `c:\foo`）
*   **Scope**: 現在の所属（`User` または `Machine`）

### 3. 最適化アルゴリズム

スクリプトは以下の順序でパイプライン処理を実行します。

1.  **収集**: User と Machine の `PATH` を取得しリスト化。
2.  **検証 (Validation)**:
    *   `Test-Path` で存在確認を行い、存在しないパスはリストから除外（削除）します。
3.  **変数の展開と正規化**:
    *   すべてのパスを展開・正規化してプロパティに保持します。
4.  **再配置 (Relocation)**:
    *   **Userへの移動**: パスが `C:\Users\<CurrentUsers>\` 配下であり、かつ `Machine` スコープにある場合、`User` スコープへ移動フラグを立てます。
    *   **Machineへの移動**: パスが `%SystemRoot%` や `%ProgramFiles%` 等のシステム領域、またはシステム変数ベースで定義されている場合、`Machine` スコープへの配置を推奨します。
5.  **重複排除 (Deduplication)**:
    *   各スコープ内で `NormalizedPath` をキーに重複を削除（順序は上位を維持）。
    *   **クロススコープ排除**: `User` と `Machine` で重複する場合、`Machine` を残し `User` 側を削除します。
6.  **変数の復元 (Reverse Lookup)**:
    *   絶対パスになっているものを保存用に変数表記へ戻します。
    *   例: `C:\Users\Nuits` -> `%USERPROFILE%`
7.  **適用 (Commit)**:
    *   レジストリおよび .NET API を通じて保存。
    *   `SendMessageTimeout` (HWND_BROADCAST, WM_SETTINGCHANGE) を実行し、変更をOS全体に通知。

## 開発構成 (Development)

### リポジトリ構造
```text
optimize-environment-variables/
├── .github/
│   └── workflows/
│       └── test.yml                 # GitHub Actions (Pester Test)
├── src/
│   └── Optimize-EnvironmentVariable.ps1  # メインスクリプト
├── tests/
│   └── Optimize-EnvironmentVariable.Tests.ps1 # テストコード
└── README.md
```

### テスト戦略
*   **フレームワーク**: Pester 5.x
*   **カバレージ目標**: 85% 以上（Branch Coverage）
*   **テストシナリオ**:
    *   重複パスが1つになること。
    *   末尾スラッシュ削除の挙動（`C:\` は消えず `C:\foo\` は消えること）。
    *   SystemとUserの競合時にSystemが勝つこと。
    *   Userプロファイル下のパスがSystemからUserへ移動すること。
    *   存在しないパスが消えること。
    *   Dry-Run時に変更が行われないこと。

---