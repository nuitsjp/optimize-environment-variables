# optimize-environment-variables

Windowsのシステム環境変数およびユーザー環境変数（主に `PATH`）を自動的に整理・最適化・クリーンアップするPowerShellスクリプトです。

重複の削除、パスの正規化、無効なパスの削除、適切なスコープ（System/User）への振り分けを安全かつ自動的に行います。

```powershell
Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb https://raw.githubusercontent.com/nuitsjp/optimize-environment-variables/refs/heads/main/src/Optimize-EnvironmentVariable.ps1 | iex`""
```

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

### 変更を自動適用する場合
対話を介さず適用するには、`-Force` スイッチを付与します（ワンライナーの場合はコード内の引数を修正するか、ローカルにダウンロードして実行してください）。

```powershell
# ローカル実行例（無人適用）
.\src\Optimize-EnvironmentVariable.ps1 -Force -Verbose
```
