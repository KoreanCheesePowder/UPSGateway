C.P Eaton UPS Gateway Edge Driver v2.9.3

외부 게이트웨이가 전달하는 Eaton UPS 상태를 SmartThings의 UPS별 LAN 기기로 생성하고 표시하는 Edge 드라이버입니다.

주요 기능
- C.P Eaton UPS Gateway 검색 및 자동 생성
- upsId별 Eaton UPS 기기 생성과 기존 기기 갱신
- 배터리 잔량 표시
- powerSource를 mains, battery, unknown으로 표시
- 정격 출력과 부하율로 현재 소비 전력(W) 계산
- UPS 상태를 정상 전원, 배터리 운전, 배터리 부족, 통신 오류로 표시
- 예상시간을 시간·분·초 또는 분·초 형식으로 표시
- 부하율 표시
- 대시보드 요약에 예상시간과 부하율을 함께 표시
- 저장된 예상시간과 부하율로 드라이버 시작 시 대시보드 요약 복원
- 기존 UPS 기기를 현재 cp-eaton-ups-device-dashboard 프로필로 갱신
- Driver Information에 제작자와 버전 표시

설치
1. ZIP 압축을 풉니다.
2. SETUP-AND-INSTALL.cmd를 실행합니다.
3. 완료 후 Edge Driver/컨테이너를 한 번 재시작합니다.
4. SmartThings 앱을 완전히 종료한 뒤 다시 실행합니다.

드라이버 정보
- 제작자: 치즈가루
- 버전: v2.9.3
- packageKey: cp-eaton-ups-gateway-v212
