C.P Eaton UPS Gateway Edge Driver v3.0.0

변경 사항
- 요약정보에 '예상시간' + '부하율'을 같은 대시보드 그룹으로 표시
- 상세정보 UPS Runtime -> 예상시간
- 상세정보 Eaton UPS Load -> 부하율
- 기존 배터리를 프로필 첫 capability로 복원해 상세화면 레이아웃 변화를 최소화
- 설치 시 Custom Capability Presentation/한국어 번역을 Cloud에 실제 업데이트
- 설치 시 새 Device Presentation(VID)을 생성하여 SmartThings UI 캐시 갱신
- 기존 장치도 드라이버 시작 시 버전 v2.9.3 이벤트를 다시 송신
- 기존 Driver ID/packageKey 유지
- SmartThings 토큰 없이 NAS UPS 로거의 로컬 API를 직접 조회
- Gateway 설정에서 NAS IP, 포트 8766, 확인 주기 60초 지정

설치
1. ZIP 압축 해제
2. SETUP-AND-INSTALL.cmd 실행
3. SmartThings 앱 완전 종료 후 다시 실행
4. C.P Eaton UPS Gateway 설정에서 NAS IP와 포트 8766 확인
