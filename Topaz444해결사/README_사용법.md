# Topaz Video 444 + 화면꺼짐 원클릭 해결사

토파즈 업데이트 후 생긴 두 가지 문제를 한 번에 고치는 도구입니다.

| 문제 | 원인 | 해결 |
|---|---|---|
| 444(ProRes 4444) 출력 옵션이 사라짐 | 토파즈가 **실행될 때마다 서버에서 인코더 목록(`video-encoders.json`)을 다시 내려받아 덮어씀** → 커스텀 444 항목이 계속 지워짐 | 444 인코더 항목을 다시 추가하고 파일을 **읽기 전용으로 잠가** 덮어쓰기 차단 + 회사 표준 프리셋 재설치 |
| 업스케일 중 화면이 꺼지고 안 돌아옴 | 새 버전이 AI 엔진(TensorRT-RTX)을 교체하면서 GPU 메모리를 100%까지 사용 → 화면 출력용 메모리 부족으로 NVIDIA 드라이버 멈춤 | Topaz VRAM 사용 한도를 85%로 제한 + Windows 그래픽 드라이버 응답 대기시간(TDR) 60초로 연장 |

## 사용법 (3단계)

1. **Topaz Video 를 완전히 종료**합니다. (작업 중인 내보내기가 끝난 뒤에!)
2. `원클릭해결.bat` 을 **더블클릭**합니다.
   - 파란 관리자 확인 창(UAC)이 뜨면 **"예"** 를 누릅니다.
   - 화면 안내를 따라가면 자동으로 끝납니다.
3. 끝나면 **PC를 한 번 재부팅**합니다.

재부팅 후 Topaz Video 를 켜면:

- 출력 코덱 목록에 **ProRes 4444** 가 다시 보입니다.
- 프리셋 목록에 **"Codex Rhea 4K Apollo 24 ProRes4444"** 가 추가되어 있습니다.
  (회사 규칙: 3840x2160 / 정확히 24fps / Rhea 업스케일 / Apollo 보간 / ProRes 4444 MOV / 오디오 copy)

## 자주 묻는 질문

**Q. 토파즈가 또 업데이트되면?**
인코더 파일을 읽기 전용으로 잠가두기 때문에 평소 실행으로는 444가 사라지지 않습니다. 다만 토파즈 **프로그램 업데이트(설치)** 후에는 파일이 교체될 수 있으니, 444가 안 보이면 `원클릭해결.bat` 을 다시 한 번 실행하면 됩니다. (다른 설정은 유지됩니다)

**Q. 토파즈가 새 코덱을 추가했다는데 안 보여요.**
인코더 파일이 잠겨 있으면 서버의 새 인코더 목록도 안 내려옵니다. 그럴 땐 `롤백.bat` → 토파즈 한 번 실행(새 목록 받기) → `원클릭해결.bat` 순서로 하면 됩니다.

**Q. 되돌리고 싶어요.**
`롤백.bat` 을 더블클릭하면 모든 변경 사항(인코더 파일, 메모리 한도, TDR 설정, 프리셋)이 실행 전 상태로 돌아갑니다.

**Q. 그래도 화면이 꺼져요.**
1. NVIDIA 드라이버를 최신 스튜디오 드라이버로 업데이트해주세요. RTX 50 시리즈는 드라이버 영향이 큽니다.
2. Topaz 환경설정(Preferences) > Processing 에서 "Max memory usage" 가 85% 이하인지 확인해주세요. (토파즈가 설정을 다시 100%로 올리는 경우가 있습니다)
3. 그래도 안 되면 업스케일을 GUI 대신 CLI(ffmpeg.exe)로 돌리는 회사 자동화 스크립트(`Invoke-TopazVideoBatch.ps1`) 사용을 권장합니다.

**Q. 뭘 바꾸는지 정확히 알고 싶어요.**
- `C:\ProgramData\Topaz Labs LLC\Topaz Video\models\video-encoders.json`
  - `prores-422-4444-win` 인코더 항목 추가 (변경 전 파일은 같은 폴더에 `video-encoders.backup_444fix_날짜.json` 으로 백업)
  - 토파즈가 서버 목록으로 다시 덮어쓰지 못하도록 파일을 읽기 전용으로 설정 (롤백 시 해제)
  - 2026-06 서버 배포판의 새 인코더 구조(`encoderOpts`)와 이전 구조(`ffmpegOpts`)를 자동 감지해서 맞는 형식으로 추가
- `C:\ProgramData\Topaz Labs LLC\Topaz Video\presets\` 및 `%AppData%\Topaz Labs LLC\Topaz Video\presets\`
  - 회사 표준 프리셋 1개 설치 (토파즈 1.5부터 GUI는 ProgramData 쪽만 읽으므로 두 곳 모두 설치)
- 레지스트리 `HKCU\Software\Topaz Labs LLC\Topaz Video`
  - `maxMemoryUsage`: 100 → 85
- 레지스트리 `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers`
  - `TdrDelay`, `TdrDdiDelay`: 60 (그래픽 드라이버가 멈췄다고 판단하기 전 대기시간 연장, 재부팅 필요)
- 실행 기록은 `logs\` 폴더에, 롤백용 원본 값은 `state\last-state.json` 에 저장됩니다.

## 배포 방법

이 폴더(`Topaz444해결사`) 전체를 압축해서 공유하면 됩니다. 받은 사람은 압축을 풀고 `원클릭해결.bat` 만 더블클릭하면 됩니다. 사용자 계정마다 설정(프리셋, 메모리 한도)이 따로 저장되므로, **실제로 토파즈를 쓰는 Windows 계정으로 로그인한 상태에서** 실행해야 합니다.
