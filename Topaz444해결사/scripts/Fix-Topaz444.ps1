# =====================================================================
#  Topaz Video 444 + 화면꺼짐 원클릭 해결사  (v1.0.1)
#  - 업데이트로 사라진 ProRes 4444(444) 인코더 옵션 복구 (신/구 스키마 자동 감지)
#  - 토파즈가 실행 시 서버에서 인코더 목록을 다시 내려받아 덮어쓰는 것을
#    막기 위해 video-encoders.json 을 읽기 전용으로 잠금
#  - 회사 표준 프리셋(Rhea 4K / Apollo 24fps / ProRes 4444) 설치
#  - 화면 꺼짐(블랙스크린) 완화: Topaz VRAM 사용률 85% 제한 + TDR 대기시간 연장
#  모든 변경은 백업/기록되며, 롤백.bat 으로 되돌릴 수 있습니다.
# =====================================================================
[CmdletBinding()]
param(
  [switch]$WhatIfOnly   # 실제로 아무것도 바꾸지 않고 점검만
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ---------- 관리자 권한 자동 상승 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $WhatIfOnly) {
  Write-Host "관리자 권한이 필요해서 관리자 창을 새로 엽니다. (UAC 창에서 '예'를 눌러주세요)"
  $psArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $psArgs
  exit
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$toolRoot   = Split-Path -Parent $scriptRoot
$logDir     = Join-Path $toolRoot 'logs'
$stateDir   = Join-Path $toolRoot 'state'
$stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath    = Join-Path $logDir "fix_$stamp.log"

New-Item -ItemType Directory -Force -Path $logDir, $stateDir | Out-Null

function Log {
  param([string]$Message, [string]$Color = 'Gray')
  Write-Host $Message -ForegroundColor $Color
  Add-Content -Path $logPath -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message) -Encoding UTF8
}

function Done { param([string]$m) Log ("  [완료] " + $m) 'Green' }
function Skip { param([string]$m) Log ("  [건너뜀] " + $m) 'DarkYellow' }
function Fail { param([string]$m) Log ("  [실패] " + $m) 'Red' }

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   Topaz Video 444 + 화면꺼짐 원클릭 해결사 v1.0.1" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
if ($WhatIfOnly) { Log "** 점검 모드: 실제 변경 없이 상태만 확인합니다 **" 'Yellow' }

$state = [ordered]@{
  timestamp        = $stamp
  encoderBackup    = $null
  encoderReadOnly  = $false
  maxMemoryBefore  = $null
  maxMemoryKind    = $null
  tdrDelayBefore   = $null
  tdrDdiBefore     = $null
}

try {

# =====================================================================
# 0단계. Topaz Video 설치/모델 폴더 확인
# =====================================================================
Log "0단계. Topaz Video 설치 확인" 'White'

$modelDir = $null
try {
  $reg = Get-ItemProperty 'HKCU:\Software\Topaz Labs LLC\Topaz Video' -ErrorAction Stop
  if ($reg.veaiDataFolder) { $modelDir = $reg.veaiDataFolder.TrimEnd('\') }
} catch {}
if (-not $modelDir -or -not (Test-Path $modelDir)) {
  $modelDir = Join-Path $env:ProgramData 'Topaz Labs LLC\Topaz Video\models'
}
$encoderPath = Join-Path $modelDir 'video-encoders.json'

if (-not (Test-Path $encoderPath)) {
  Fail "video-encoders.json 을 찾을 수 없습니다: $encoderPath"
  Fail "Topaz Video 가 설치된 PC가 맞는지 확인해주세요."
  Read-Host "아무 키나 누르면 종료합니다"
  exit 1
}
Done "모델 폴더: $modelDir"

# Topaz Video 가 실행 중이면 종료 요청
$proc = Get-Process -Name 'Topaz Video' -ErrorAction SilentlyContinue
if ($proc -and -not $WhatIfOnly) {
  Write-Host ""
  Write-Host "  Topaz Video 가 실행 중입니다. 설정을 고치려면 먼저 꺼야 합니다." -ForegroundColor Yellow
  Write-Host "  (작업 중인 내보내기가 있다면 N 을 누르고, 끝난 뒤 다시 실행해주세요)" -ForegroundColor Yellow
  $answer = Read-Host "  지금 Topaz Video 를 종료할까요? (Y/N)"
  if ($answer -match '^[yY]') {
    $proc | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 5
    $proc = Get-Process -Name 'Topaz Video' -ErrorAction SilentlyContinue
    if ($proc) { $proc | Stop-Process -Force; Start-Sleep -Seconds 2 }
    Done "Topaz Video 종료"
  } else {
    Fail "Topaz Video 를 끄지 않아 중단합니다. 끄신 뒤 다시 더블클릭해주세요."
    Read-Host "아무 키나 누르면 종료합니다"
    exit 1
  }
}

# =====================================================================
# 1단계. 444 (ProRes 4444) 인코더 옵션 복구
# =====================================================================
Write-Host ""
Log "1단계. 444 (ProRes 4444) 출력 옵션 복구" 'White'

# 토파즈 2026-06 서버 배포판부터 인코더 항목 구조가 ffmpegOpts(문자열)에서
# encoderOpts(객체)로 바뀌었으므로, 현재 파일의 구조를 보고 맞는 항목을 사용한다.
$newSchemaEntryJson = @'
{
  "id": "prores-422-4444-win",
  "encoder": "ProRes",
  "profile": "4444",
  "allowsAlpha": 0,
  "ext": [ "mov" ],
  "os": "windows|linux",
  "minSize": [ 1, 1 ],
  "maxSize": [ 16386, 16386 ],
  "maxBitDepth": 12,
  "doNotScaleFullColorRange": "transcode",
  "encoderOpts": {
    "profile:v": "4",
    "vendor": "apl0",
    "tag:v": "ap4h"
  },
  "pixFmt": "yuv444p10le",
  "encoderName": "prores_ks"
}
'@
$oldSchemaEntryJson = @'
{
  "id": "prores-422-4444-win",
  "encoder": "ProRes",
  "profile": "4444",
  "allowsAlpha": 0,
  "ffmpegOpts": "-c:v prores_ks -profile:v 4 -vendor apl0 -tag:v ap4h -pix_fmt yuv444p10le",
  "ext": [ "mov" ],
  "os": "windows|linux",
  "minSize": [ 1, 1 ],
  "maxSize": [ 16386, 16386 ],
  "maxBitDepth": 12,
  "doNotScaleFullColorRange": "transcode"
}
'@

$raw      = Get-Content -LiteralPath $encoderPath -Raw -Encoding UTF8
$encoders = ConvertFrom-Json $raw
# PowerShell 5.1 은 JSON 배열을 단일 객체로 돌려주므로 배열로 강제하되,
# @() 로 감싸지 말고 -is [Array] 검사로 처리한다 (감싸면 1개 덩어리가 됨)
if ($encoders -isnot [Array]) { $encoders = @($encoders) }
Log ("  현재 인코더 항목 수: " + $encoders.Count) 'DarkGray'

$sample = $encoders | Where-Object { $_.id -eq 'prores-422-hq-win' } | Select-Object -First 1
$useNewSchema = -not ($sample -and $sample.PSObject.Properties['ffmpegOpts'])
Log ("  인코더 파일 구조: " + $(if ($useNewSchema) { "신형(encoderOpts)" } else { "구형(ffmpegOpts)" })) 'DarkGray'

$entry     = $(if ($useNewSchema) { $newSchemaEntryJson } else { $oldSchemaEntryJson }) | ConvertFrom-Json
$entryFlat = $entry | ConvertTo-Json -Depth 20 -Compress
$existing  = $encoders | Where-Object { $_.id -eq $entry.id } | Select-Object -First 1
$fileItem  = Get-Item -LiteralPath $encoderPath

$alreadyOk = $existing -and (($existing | ConvertTo-Json -Depth 20 -Compress) -eq $entryFlat)

if ($WhatIfOnly) {
  if ($alreadyOk) { Log "  -> 444 인코더가 이미 들어있습니다." 'Yellow' }
  else { Log ("  -> 444 인코더가 " + $(if ($existing) { "구버전입니다. 갱신 대상." } else { "없습니다. 추가 대상." })) 'Yellow' }
  Log ("  -> 파일 잠금(읽기 전용) 상태: " + $fileItem.IsReadOnly) 'Yellow'
} else {
  if (-not $alreadyOk) {
    $backupPath = Join-Path $modelDir "video-encoders.backup_444fix_$stamp.json"
    Copy-Item -LiteralPath $encoderPath -Destination $backupPath -Force
    (Get-Item -LiteralPath $backupPath).IsReadOnly = $false
    $state.encoderBackup = $backupPath
    Done "원본 백업: $backupPath"

    $updated  = New-Object System.Collections.Generic.List[object]
    $inserted = $false
    foreach ($enc in $encoders) {
      if ($enc.id -eq $entry.id) { $updated.Add($entry); $inserted = $true; continue }
      $updated.Add($enc)
      if (-not $inserted -and $enc.id -eq 'prores-422-hq-win') { $updated.Add($entry); $inserted = $true }
    }
    if (-not $inserted) { $updated.Add($entry) }

    $newJson = ConvertTo-Json -InputObject $updated.ToArray() -Depth 20
    $fileItem.IsReadOnly = $false
    [IO.File]::WriteAllText($encoderPath, $newJson, (New-Object Text.UTF8Encoding($false)))

    # 저장 후 JSON 이 정상인지 + 444 항목이 실제로 들어갔는지 검증
    $verify = ConvertFrom-Json ([IO.File]::ReadAllText($encoderPath))
    if ($verify -isnot [Array]) { $verify = @($verify) }
    $check = $verify | Where-Object { $_.id -eq 'prores-422-4444-win' } | Select-Object -First 1
    if (-not $check) { throw "저장 후 검증 실패: 444 항목이 보이지 않습니다." }
    Done ("video-encoders.json 에 ProRes 4444 (444) 항목 추가 완료 (총 " + $verify.Count + "개 항목)")
  } else {
    Skip "444 인코더가 이미 최신 상태입니다."
  }

  # 토파즈는 실행될 때 서버에서 이 파일을 다시 내려받아 덮어쓰므로(444가 사라졌던 진짜 원인),
  # 읽기 전용으로 잠가서 덮어쓰기를 차단한다.
  $fileItem = Get-Item -LiteralPath $encoderPath
  if (-not $fileItem.IsReadOnly) {
    $fileItem.IsReadOnly = $true
    $state.encoderReadOnly = $true
    Done "video-encoders.json 읽기 전용 잠금 (토파즈가 다시 덮어쓰는 것 방지)"
  } else {
    $state.encoderReadOnly = $true
    Skip "이미 읽기 전용으로 잠겨 있습니다."
  }
}

# =====================================================================
# 2단계. 회사 표준 프리셋 설치 (Rhea 4K / Apollo 24fps / ProRes 4444)
# =====================================================================
Write-Host ""
Log "2단계. 회사 표준 프리셋 설치" 'White'

# 주의: Topaz Video 1.5 부터 GUI 는 ProgramData\presets 폴더의 json 만 프리셋으로
# 로드한다 (Roaming\presets 는 더 이상 읽지 않음). 호환을 위해 두 곳 모두에 설치한다.
$presetJson = @'
{
    "name": "Codex Rhea 4K Apollo 24 ProRes4444",
    "description": "4K Rhea upscale, Apollo frame interpolation at 24 fps, duplicate-frame replacement off. CLI uses MOV ProRes 4444 and audio copy.",
    "author": "Codex",
    "path": "C:/ProgramData/Topaz Labs LLC/Topaz Video/presets/Codex Rhea 4K Apollo 24 ProRes4444.json",
    "saveOutputSettings": true,
    "date": "Tue May 19 16:31:09 2026 GMT+0900",
    "veaiversion": "1.5.0",
    "editable": true,
    "enabled": true,
    "settings": {
        "stabilize": { "active": false, "smooth": 50, "method": 1, "rsc": false, "reduceMotion": false, "reduceMotionIteration": 2 },
        "motionblur": { "active": false, "model": "thm-2" },
        "slowmo": { "active": true, "model": "apo-8", "factor": 1, "duplicate": false, "duplicateThreshold": 0 },
        "enhance": {
            "active": true, "model": "rhea-1", "videoType": 1, "auto": 1, "fieldOrder": 0,
            "compress": 0, "detail": 0, "sharpen": 0, "denoise": 0, "dehalo": 0, "deblur": 0, "addNoise": 0,
            "recoverOriginalDetailValue": 20,
            "isArtemis": false, "isGaia": false, "isTheia": false, "isProteus": false, "isIris": false,
            "isSecondEnhancement": false, "focusFixLevel": "Off"
        },
        "grain": { "active": false, "grainStrength": 50, "grainSigma": 0.5, "grainSize": 2, "grainType": 0 },
        "output": {
            "active": true, "outSizeMethod": 7, "cropToFit": false, "outputPAR": 0,
            "outFPS": 24, "outputFps": 24, "lockAspectRatio": true, "customResolutionPriority": 0,
            "width": 3840, "height": 2160,
            "encoderId": "prores-422-4444-win", "container": "mov", "audioMode": "copy"
        }
    }
}
'@

$presetName    = 'Codex Rhea 4K Apollo 24 ProRes4444.json'
$presetTargets = @(
  (Join-Path $env:ProgramData 'Topaz Labs LLC\Topaz Video\presets'),  # GUI 가 실제로 읽는 곳 (1.5+)
  (Join-Path $env:APPDATA     'Topaz Labs LLC\Topaz Video\presets')   # 구버전 호환
)
foreach ($dir in $presetTargets) {
  $presetPath = Join-Path $dir $presetName
  if ($WhatIfOnly) {
    Log ("  -> 프리셋 설치 대상: " + $presetPath) 'Yellow'
  } else {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText($presetPath, $presetJson, (New-Object Text.UTF8Encoding($false)))
    Done "프리셋 설치: $presetPath"
  }
}

# =====================================================================
# 3단계. 화면 꺼짐(블랙스크린) 방지 설정
# =====================================================================
Write-Host ""
Log "3단계. 화면 꺼짐(블랙스크린) 방지 설정" 'White'
Log "  원인: 업데이트 후 새 AI 엔진이 그래픽카드 메모리(VRAM)를 100%까지 쓰면서" 'DarkCyan'
Log "        화면 출력용 메모리까지 뺏어가 NVIDIA 드라이버가 멈추는 현상입니다." 'DarkCyan'

# 3-1. Topaz VRAM 사용률 100% -> 85%
$tvKey = 'HKCU:\Software\Topaz Labs LLC\Topaz Video'
try {
  $regKey  = Get-Item $tvKey -ErrorAction Stop
  $curMem  = $regKey.GetValue('maxMemoryUsage', $null)
  $memKind = if ($null -ne $curMem) { $regKey.GetValueKind('maxMemoryUsage').ToString() } else { 'String' }
  $state.maxMemoryBefore = "$curMem"
  $state.maxMemoryKind   = $memKind

  if ("$curMem" -eq '85') {
    Skip "Topaz 메모리 사용 한도가 이미 85% 입니다."
  } elseif ($WhatIfOnly) {
    Log ("  -> Topaz 메모리 사용 한도: 현재 {0}% -> 85% 로 변경 대상" -f $curMem) 'Yellow'
  } else {
    if ($memKind -eq 'DWord') { Set-ItemProperty -Path $tvKey -Name 'maxMemoryUsage' -Value ([int]85) -Type DWord }
    else                      { Set-ItemProperty -Path $tvKey -Name 'maxMemoryUsage' -Value '85' -Type String }
    Done ("Topaz 메모리 사용 한도: {0}% -> 85%" -f $curMem)
  }
} catch {
  Skip "Topaz 설정 레지스트리가 없습니다 (이 PC에서 Topaz 를 한 번도 실행 안 했을 수 있음)."
}

# 3-2. Windows TDR(그래픽 드라이버 응답 대기시간) 연장: 기본 2초 -> 60초
$tdrKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$curTdr    = (Get-ItemProperty -Path $tdrKey -Name 'TdrDelay'    -ErrorAction SilentlyContinue).TdrDelay
$curTdrDdi = (Get-ItemProperty -Path $tdrKey -Name 'TdrDdiDelay' -ErrorAction SilentlyContinue).TdrDdiDelay
$state.tdrDelayBefore = $curTdr
$state.tdrDdiBefore   = $curTdrDdi

if ($curTdr -eq 60 -and $curTdrDdi -eq 60) {
  Skip "TDR 대기시간이 이미 60초로 설정되어 있습니다."
} elseif ($WhatIfOnly) {
  $tdrShow    = if ($null -ne $curTdr)    { $curTdr }    else { '기본(2초)' }
  $tdrDdiShow = if ($null -ne $curTdrDdi) { $curTdrDdi } else { '기본(5초)' }
  Log ("  -> TDR 대기시간: 현재 TdrDelay={0}, TdrDdiDelay={1} -> 둘 다 60 으로 변경 대상" -f $tdrShow, $tdrDdiShow) 'Yellow'
} else {
  Set-ItemProperty -Path $tdrKey -Name 'TdrDelay'    -Value ([int]60) -Type DWord
  Set-ItemProperty -Path $tdrKey -Name 'TdrDdiDelay' -Value ([int]60) -Type DWord
  Done "그래픽 드라이버 응답 대기시간(TDR) 60초로 연장 (재부팅 후 적용)"
}

# =====================================================================
# 상태 저장(롤백용) 및 마무리
# =====================================================================
if (-not $WhatIfOnly) {
  $statePath = Join-Path $stateDir 'last-state.json'
  $state | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  모든 작업이 끝났습니다!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  남은 일 딱 2가지:" -ForegroundColor White
Write-Host "   1. PC를 한 번 재부팅해주세요. (TDR 설정 적용)" -ForegroundColor White
Write-Host "   2. Topaz Video 를 켜고 Codec: ProRes 의 Profile 목록에" -ForegroundColor White
Write-Host "      '4444' 가 보이는지 확인해주세요." -ForegroundColor White
Write-Host ""
Write-Host "  ※ 그래도 화면이 꺼지면 NVIDIA 드라이버를 최신으로" -ForegroundColor DarkCyan
Write-Host "    업데이트해주세요. (RTX 50 시리즈는 드라이버 영향이 큽니다)" -ForegroundColor DarkCyan
Write-Host "  ※ 되돌리고 싶으면 같은 폴더의 '롤백.bat' 을 실행하세요." -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  기록 파일: $logPath" -ForegroundColor DarkGray
Write-Host ""

} catch {
  Write-Host ""
  Fail "예상치 못한 오류가 발생했습니다:"
  Fail $_.Exception.Message
  Fail ("위치: " + $_.ScriptStackTrace)
  Write-Host ""
  Write-Host "  이 창을 캡처해서 담당자에게 보내주세요." -ForegroundColor Yellow
  Write-Host "  기록 파일: $logPath" -ForegroundColor Yellow
}

Read-Host "아무 키나 누르면 창이 닫힙니다"
