C.P Eaton UPS Gateway Edge Driver v2.9.3

변경 사항
- 요약정보에 '예상시간' + '부하율'을 같은 대시보드 그룹으로 표시
- 상세정보 UPS Runtime -> 예상시간
- 상세정보 Eaton UPS Load -> 부하율
- 기존 배터리를 프로필 첫 capability로 복원해 상세화면 레이아웃 변화를 최소화
- 설치 시 Custom Capability Presentation/한국어 번역을 Cloud에 실제 업데이트
- 설치 시 새 Device Presentation(VID)을 생성하여 SmartThings UI 캐시 갱신
- 기존 장치도 드라이버 시작 시 버전 v2.9.3 이벤트를 다시 송신
- 기존 Driver ID/packageKey 유지

설치
1. ZIP 압축 해제
2. SETUP-AND-INSTALL.cmd 실행
3. 완료 후 Edge Driver/컨테이너 1회 재시작
4. SmartThings 앱 완전 종료 후 다시 실행
