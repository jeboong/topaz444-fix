# =====================================================================
#  Topaz 444 해결사 - 롤백 (해결사가 바꾼 것을 원래대로 되돌립니다)
# =====================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "관리자 권한이 필요해서 관리자 창을 새로 엽니다. (UAC 창에서 '예'를 눌러주세요)"
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  exit
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$toolRoot   = Split-Path -Parent $scriptRoot
$statePath  = Join-Path $toolRoot 'state\last-state.json'

Write-Host ""
Write-Host "=== Topaz 444 해결사 롤백 ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $statePath)) {
  Write-Host "롤백할 기록(state\last-state.json)이 없습니다." -ForegroundColor Yellow
  Write-Host "해결사를 실행한 적이 없는 PC이거나, 기록이 삭제되었습니다." -ForegroundColor Yellow
  Read-Host "아무 키나 누르면 종료합니다"
  exit 1
}
$state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json

# 1. video-encoders.json 백업 복원 (+ 읽기 전용 잠금 해제)
if ($state.encoderBackup -and (Test-Path $state.encoderBackup)) {
  $target = Join-Path (Split-Path -Parent $state.encoderBackup) 'video-encoders.json'
  if (Test-Path $target) { (Get-Item -LiteralPath $target).IsReadOnly = $false }
  Copy-Item -LiteralPath $state.encoderBackup -Destination $target -Force
  (Get-Item -LiteralPath $target).IsReadOnly = $false
  Write-Host "[완료] video-encoders.json 을 백업본으로 복원하고 잠금을 해제했습니다." -ForegroundColor Green
} else {
  $target = Join-Path $env:ProgramData 'Topaz Labs LLC\Topaz Video\models\video-encoders.json'
  if (Test-Path $target) {
    (Get-Item -LiteralPath $target).IsReadOnly = $false
    Write-Host "[완료] 복원할 백업은 없지만 video-encoders.json 잠금은 해제했습니다." -ForegroundColor Green
  } else {
    Write-Host "[건너뜀] 복원할 인코더 백업이 없습니다." -ForegroundColor DarkYellow
  }
}

# 2. Topaz 메모리 사용 한도 복원
$tvKey = 'HKCU:\Software\Topaz Labs LLC\Topaz Video'
if ($state.maxMemoryBefore) {
  if ($state.maxMemoryKind -eq 'DWord') {
    Set-ItemProperty -Path $tvKey -Name 'maxMemoryUsage' -Value ([int]$state.maxMemoryBefore) -Type DWord
  } else {
    Set-ItemProperty -Path $tvKey -Name 'maxMemoryUsage' -Value "$($state.maxMemoryBefore)" -Type String
  }
  Write-Host "[완료] Topaz 메모리 사용 한도를 $($state.maxMemoryBefore)% 로 복원했습니다." -ForegroundColor Green
}

# 3. TDR 설정 복원 (원래 값이 없었다면 삭제)
$tdrKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
if ($null -ne $state.tdrDelayBefore) {
  Set-ItemProperty -Path $tdrKey -Name 'TdrDelay' -Value ([int]$state.tdrDelayBefore) -Type DWord
} else {
  Remove-ItemProperty -Path $tdrKey -Name 'TdrDelay' -ErrorAction SilentlyContinue
}
if ($null -ne $state.tdrDdiBefore) {
  Set-ItemProperty -Path $tdrKey -Name 'TdrDdiDelay' -Value ([int]$state.tdrDdiBefore) -Type DWord
} else {
  Remove-ItemProperty -Path $tdrKey -Name 'TdrDdiDelay' -ErrorAction SilentlyContinue
}
Write-Host "[완료] TDR 설정을 원래대로 되돌렸습니다. (재부팅 후 적용)" -ForegroundColor Green

# 4. 설치했던 프리셋 삭제
$presetPath = Join-Path $env:APPDATA 'Topaz Labs LLC\Topaz Video\presets\Codex Rhea 4K Apollo 24 ProRes4444.json'
if (Test-Path $presetPath) {
  Remove-Item $presetPath -Force
  Write-Host "[완료] 설치했던 프리셋을 삭제했습니다." -ForegroundColor Green
}

Write-Host ""
Write-Host "롤백이 끝났습니다. PC를 한 번 재부팅해주세요." -ForegroundColor Cyan
Read-Host "아무 키나 누르면 종료합니다"
