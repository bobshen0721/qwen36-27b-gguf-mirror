# Qwen3.6 27B GGUF GitHub Mirror

這個 repo 用來鏡像多個 Qwen3.6 27B GGUF 檔案，做法是：

- `Code -> Download ZIP`：提供說明、切檔腳本、驗證腳本與 `merge-model.bat`
- `Releases`：提供實際的 `.gguf.001`, `.gguf.002`, `.gguf.003` 分片與 `checksums.sha256`

模型本體不會直接 commit 進 git，也不使用 Git LFS。

## Models

| Model file | Release tag | Merge BAT |
| --- | --- | --- |
| `Qwen3.6-27B-UD-IQ2_XXS.gguf` | `v1-qwen3.6-27b-ud-iq2-xxs` | `merge-model.bat` |
| `Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf` | `v1-qwen3.6-27b-uncensored-hauhaucs-aggressive-iq3-m` | `merge-aggressive-iq3m.bat` |

## 檔案清單

- `split-model.ps1`：把原始 `.gguf` 直接切成多個 `1900 MiB` 分片
- `merge-model.bat`：在 Windows 合併下載好的分片；可接受模型檔名參數
- `merge-aggressive-iq3m.bat`：合併 `Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf`
- `verify-model.ps1`：比對單一檔案的 SHA256 是否符合 `checksums.sha256`
- `checksums.sha256`：原始模型與每個分片的 SHA256 manifest
- `UPSTREAM.md`：上游來源與授權說明

## 一般使用者流程

1. 下載這個 repo 的 `Code ZIP`
2. 到 `Releases` 下載全部 `Qwen3.6-27B-UD-IQ2_XXS.gguf.00n` 分片與 `checksums.sha256`
3. 把 `merge-model.bat` 放到分片資料夾，或在分片資料夾裡執行它
4. 合併完成後，用 `verify-model.ps1` 驗證

### Windows 合併

在分片資料夾中執行：

```bat
merge-model.bat
```

如果要合併 aggressive IQ3_M 版本，可執行：

```bat
merge-aggressive-iq3m.bat
```

或直接傳入模型檔名：

```bat
merge-model.bat Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf
```

`merge-model.bat` 會：

- 依序檢查 `.001`, `.002`, `.003`...
- 合併成 `Qwen3.6-27B-UD-IQ2_XXS.gguf`
- 顯示合併後檔案的 SHA256

### 驗證 SHA256

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-model.ps1 -File .\Qwen3.6-27B-UD-IQ2_XXS.gguf
```

如果 `checksums.sha256` 不在同一個資料夾，可額外指定：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-model.ps1 -File .\Qwen3.6-27B-UD-IQ2_XXS.gguf -ManifestPath .\checksums.sha256
```

## 發布者流程

### 1. 從 Hugging Face 下載原始模型

```powershell
hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ2_XXS.gguf --local-dir .\staging
```

Aggressive IQ3_M:

```powershell
hf download HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Aggressive Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf --local-dir .\staging
```

### 2. 切檔並產生 SHA256 manifest

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\split-model.ps1 `
  -InputFile .\staging\Qwen3.6-27B-UD-IQ2_XXS.gguf `
  -OutputDir .\release-assets `
  -PartSizeMiB 1900 `
  -UpdateManifest
```

Aggressive IQ3_M:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\split-model.ps1 `
  -InputFile .\staging\Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf `
  -OutputDir .\release-assets `
  -PartSizeMiB 1900 `
  -UpdateManifest
```

輸出結果會放在 `.\release-assets\`：

- `Qwen3.6-27B-UD-IQ2_XXS.gguf.001`
- `Qwen3.6-27B-UD-IQ2_XXS.gguf.002`
- `Qwen3.6-27B-UD-IQ2_XXS.gguf.003`
- ...
- `checksums.sha256`

### 3. 建立 GitHub Release

```powershell
$tag = 'v1-qwen3.6-27b-ud-iq2-xxs'
$assets = Get-ChildItem .\release-assets\Qwen3.6-27B-UD-IQ2_XXS.gguf.* , .\release-assets\checksums.sha256 | ForEach-Object FullName
gh release create $tag $assets --repo bobshen0721/qwen36-27b-gguf-mirror --title $tag --notes "Split GGUF mirror for GitHub distribution."
```

## 注意事項

- GitHub 一般 repo 不支援直接存放這個 9.39 GB 單檔模型
- GitHub Release 的每個 asset 也要小於你帳號方案的單檔限制，所以分片尺寸固定採 `1900 MiB`
- 分片只做切割，不做壓縮
- `checksums.sha256` 以最終 release 內容為準
- 如果系統禁止直接執行 `.ps1`，請用 `powershell -ExecutionPolicy Bypass -File ...` 的形式呼叫
