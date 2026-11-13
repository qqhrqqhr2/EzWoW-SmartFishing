# v2.0.17

### 한국어
- 데이터 공유 현황 창을 추가했습니다. `/공유` 또는 `/ezshare`로 열면 받은 기록, 보낸 사람, 보낸 기록, 종류별 현황과 새로 받은 기록만 따로 볼 수 있습니다.
- 공유 데이터를 채널로도 보내 더 빨리 퍼지게 했습니다.
- 데이터 채널의 사용자 명단이 새로 갱신되지 않아 일부 사용자와 귓속말로 공유 기록을 주고받지 못하던 문제를 고쳤습니다.
- 퀘스트 보상, 트레이너가 가르치는 주문, 오브젝트 이름도 다른 사용자와 공유합니다.
- 다른 언어로 쓸 때 지도 확률 표시 설정의 설명이 한국어로 나오던 문제를 고쳤습니다.
- 파티와 길드에 함께 있는 사람이 낚은 물고기가 두 번 세어지던 문제를 고쳤습니다.
- 낚시 위치 공유 설정의 설명을 실제 동작(길드·파티·서버 공유 채널의 EzWoW 사용자)에 맞게 고쳤습니다.
- 언어를 바꾸면 낚시 일지 창의 글자도 바뀌도록 UI 다시 불러오기를 묻습니다.
- 내 낚시 기록이 길드·파티에서 되돌아와 다른 사람 기록으로 한 번 더 저장되던 문제를 고쳤습니다. 이미 저장된 중복은 한 번 정리합니다.
- 게임패드: 전투가 끝나면 EzWoW 창이 패드 조작을 가져가던 문제를 고쳤습니다. 전투 전에 EzWoW 창을 조작하던 경우에만 되돌립니다.
- 미니게임: 카드놀이에서 버린 카드 더미 위에 카드를 놓을 수 있던 문제와, 지뢰찾기에서 깃발부터 누르면 첫 칸이 지뢰일 수 있던 문제를 고쳤습니다.
- 공유 기록을 설치된 EzWoW 애드온 중 최대 2개에만 저장해 접속·다시 불러오기가 빨라지고 저장 파일이 작아집니다. 업데이트 후 게임을 한 번 완전히 다시 시작하면 적용됩니다.

### English
- Added a data sharing window. Open it with `/ezshare` to see received records, players, sent records, totals by kind, and only the newly received records.
- Shared data is now also sent through the channel, so it spreads faster.
- Fixed shared records not being exchanged by whisper with some players because the data channel's player list was not refreshed.
- Quest rewards, trainer spells and object names are now shared with other players too.
- Fixed the map chance option's description showing in Korean in other languages.
- Fixed catches from a player who is in both your party and guild being counted twice.
- The catch sharing options now describe what they do (EzWoW users in guild, party and the shared server channel).
- Changing the language now offers a UI reload so the journal window's labels change too.
- Fixed your own catches coming back from the guild or party and being stored again as someone else's. Existing duplicates are cleaned up once.
- Gamepad: EzWoW windows no longer take over the pad after combat; it returns only if you were using an EzWoW window before the fight.
- Mini-games: fixed cards being placed on the waste pile in solitaire, and the first reveal in minesweeper being a mine after clicking a flag first.
- Shared records are now saved by at most 2 of your installed EzWoW addons, so logins and reloads are faster and save files smaller. Takes effect after one full game restart following the update.
