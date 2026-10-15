# AI Sites 一键更新 —— 流程对齐 UFO2 Console 的 install-latest.ps1：
#   读 latest.json（机器可读清单）-> 比对本地版本 -> 下载 zip -> 校验 SHA-256 -> 解压落盘 -> 提示切换
#
#   powershell -File scripts\update-latest.ps1                          # 从 GitHub 更新仓拉最新版
#   powershell -File scripts\update-latest.ps1 -Tag v0.2.0              # 指定版本
#   powershell -File scripts\update-latest.ps1 -SourceDir \\nas\aisites # 内网镜像目录（含 latest.json + zip），不访问外网
param(
    [string]$Repo = "nowindxdw-spec/aisites-updates",
    [string]$Tag = "",
    [string]$ManifestUrl = "",
    [string]$SourceDir = "",
    [switch]$DownloadOnly
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
function Say($m) { Write-Host "[aisites-update] $m" }
function Die($m) { Write-Host "[aisites-update] x $m" -ForegroundColor Red; exit 1 }

# 1) 清单
if ($SourceDir) {
    $manifest = Get-Content (Join-Path $SourceDir "latest.json") -Raw | ConvertFrom-Json
} else {
    $u = if ($ManifestUrl) { $ManifestUrl } elseif ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$Tag" } else { "https://api.github.com/repos/$Repo/releases/latest" }
    $rel = Invoke-RestMethod -Uri $u -Headers @{ Accept = "application/vnd.github+json" }
    $manifest = $rel.assets | Where-Object { $_.name -eq "latest.json" } | ForEach-Object { Invoke-RestMethod -Uri $_.browser_download_url }
    if (-not $manifest) { Die "该 Release 未附带 latest.json 清单" }
}
Say ("清单版本：" + $manifest.tag + "（" + $manifest.publishedAt + "）")

# 2) 比对本地版本
$local = (Get-Content (Join-Path $root "package.json") -Raw | ConvertFrom-Json).version
if ("v" + $local -eq $manifest.tag) { Say ("已是本地同版本 v$local，如要强装请换目录或改版本") }

# 3) 下载
$asset = $manifest.assets | Select-Object -First 1
$zipPath = Join-Path $env:TEMP $asset.name
if ($SourceDir) { Copy-Item (Join-Path $SourceDir $asset.name) $zipPath -Force }
else {
    Say ("下载：" + $manifest.download)
    curl.exe -sL -H "Expect:" --speed-limit 4096 --speed-time 60 -o $zipPath $manifest.download
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zipPath)) { Die "下载失败" }
}

# 4) SHA-256 校验，不过不落盘
$sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
if ($sha -ne $manifest.sha256) { Remove-Item $zipPath -Force; Die ("SHA-256 复核失败！期望 " + $manifest.sha256 + " 实际 " + $sha) }
Say ("SHA-256 复核通过 " + $sha.Substring(0, 16) + "...")
if ($DownloadOnly) { Say ("-DownloadOnly：包在 " + $zipPath); exit 0 }

# 5) 解压到 releases/<tag>/，npm 依赖需在新目录重装
$dest = Join-Path (Join-Path $root "releases") $manifest.tag
if (Test-Path $dest) { Die ("目标目录已存在：" + $dest + "（同版本重复更新？先手动移除）") }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Expand-Archive -LiteralPath $zipPath -DestinationPath $dest
Say ("已落盘：" + $dest)
Say "后续：cd " + $dest + " ; npm install ; npm start"
Say "web 编辑器产物已内置（web/dist），可直接 :9787 访问"