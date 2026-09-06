C.P Eaton UPS Logger v2.1.1

- SmartThings 토큰과 Gateway Device ID를 사용하지 않습니다.
- UPS 상태를 NAS 로컬 API로 제공합니다.
- API 포트: 8766

설치
1. 이 ZIP의 파일을 기존 UPS 로거 폴더에 덮어씁니다.
2. Synology Container Manager에서 기존 프로젝트를 중지하고 다시 빌드합니다.
3. 아래 주소를 브라우저에서 확인합니다.
   http://NAS_IP:8766/health
   http://NAS_IP:8766/api/ups/latest

정상 응답
- /health: {"ok":true,"version":"2.1.1"}
- /api/ups/latest: "ok":true와 "ups" 배열 표시

config.json의 UPS 주소, NUT 포트, 이름과 정격출력 설정은 기존처럼 사용합니다.
data/latest.json과 UPS별 CSV 기록도 계속 저장됩니다.
compose.yaml이 gateway.py를 직접 마운트하므로 이전 Docker 빌드 파일이 실행되지 않습니다.
