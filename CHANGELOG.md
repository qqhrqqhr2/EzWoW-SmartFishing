# Changelog - EzWoW - Smart Fishing

## v2.0.0

### English

- Fixed icon and window dragging offsets at different UI scales.
- Improved World Map fishing buttons and the fish-species legend.
- Made zone catch-rate lookups and fishing tooltips more responsive.
- Added instant switching among eight interface languages.

### 한국어

- UI 배율에 따라 아이콘·창을 끌 때 위치가 어긋나는 문제를 수정했습니다.
- 세계지도 낚시 버튼 정렬과 어종 범례 표시를 개선했습니다.
- 지역별 어종 확률 조회와 낚시 툴팁 응답 속도를 개선했습니다.
- 8개 표시 언어를 실시간으로 전환할 수 있습니다.

## v1.1.0
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **모듈 아키텍처 재구성 (`Core/`, `Data/`, `Modules/`, `UI/`) 및 성능 개선**:
  - `Core/Init.lua`, `Core/Locales.lua`(8개 언어), `Core/Style.lua`, `Core/UIKit.lua`, `Core/Widgets.lua`, `Core/WorldMapDock.lua`
  - `Data/FishData.lua`, `Modules/CatchLog.lua`, `Modules/ExpectedRates.lua`, `Modules/FishingCast.lua`, `Modules/GearManager.lua`, `Modules/PartyGuildSync.lua`, `Modules/TooltipHook.lua`
  - `UI/HUD.lua`, `UI/JournalWindow.lua`, `UI/MapDockButton.lua`, `UI/MapLegend.lua`, `UI/MapPins.lua`, `UI/MinimapButton.lua`, `UI/OptionsWindow.lua`, `UI/DonateModal.lua`
  - 지역별 어종 기대 확률(`ExpectedRates`) 메모이제이션 캐시 적용으로 월드맵 전환 및 툴팁 표시 속도 개선
- **월드맵 도킹 및 다국어 확장**:
  - `EzWoWWorldMapDock`(순번 4) 월드맵 좌하단 자동 정렬 및 우측 어종 범례 펼침 지원
  - `Auto` 포함 8개 언어(`koKR`, `enUS`, `deDE`, `frFR`, `esES`, `ruRU`, `zhCN`, `zhTW`) 실시간 전환 지원
  - 슬래시 명령어 `/ezsf`, `/스마트낚시` 및 `EzWoW_SmartFishingDB` 정비

## v1.0.0
- 원버튼 낚시(찌 탐지 및 챔질, 자동 미끼, 자동 루팅), 낚싯대/무기 스왑, 실시간 세션 HUD, 낚시 일지·도감, 월드맵 어종 핀 및 파티·길드 공유 출시
