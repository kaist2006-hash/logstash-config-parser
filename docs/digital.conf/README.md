# digital.conf 진행 현황

업데이트: 2026-10-23

## 현재 방식

Filebeat에서 날짜 경계로 multiline 메시지를 완성한 후 Logstash에서 요청 URL·응답 JSON을 파싱합니다. 구간 선택에 쓰던 aggregate·본문 버퍼를 제거했습니다.

- [digital.conf](digital.conf): 현재 전체 Logstash 설정.
- [Filebeat filestream input 예시](filebeat.epay-filestream.input.yml).
- [Filebeat 기존 log input 예시](filebeat.epay-log.input.yml).
- [설정 가이드](GUIDE.md).
- [검증 요약](VALIDATION.md).

Filebeat 파일은 기존 filebeat.inputs에 합칠 input 목록 조각입니다. 두 유형 중 현재 버전에 맞는 하나만 사용하고 실제 epay.out 경로·기존 encoding·ID·읽기 상태를 확인하세요. 실제 Filebeat 설정이 첨부되지 않아 기존 입력을 자동 수정하지는 않았습니다. 공용 VAN input에는 신규 multiline 필터를 적용하지 않습니다.

## 반영 사항

- Filebeat가 새 날짜·시간 시작 전까지를 한 레코드로 조합하고 요청·POST 응답 제목이 있는 레코드만 전송.
- Logstash는 한 이벤트 안에서 구간을 찾아 요청 grok·kv 또는 응답 JSON 처리.
- 응답 TR_ID URL 인코딩과 result_data 배열 구조 유지.
- aggregate·구간 상태·누적 본문·관련 timeout 제거. 신규 설정에 따른 worker 1 제한 제거.
- 기존 VAN·input·output 유지. 접속 password 4곳만 공개용 임시값 00000000 유지.
- 원본 실로그·실거래값·접속 비밀번호는 업로드에 포함하지 않음.

## 검사 상태

첨부 실로그의 오프라인 경계·파싱 재현에서 요청 1,056건과 응답 1,049건을 이전과 같은 값으로 추출했습니다. 닫는 ]가 다음 줄인 응답 110건도 포함됩니다.

실제 Filebeat/Logstash 실행·부하 검증 및 서버 배포는 완료된 항목이 아닙니다. input 범위·registry 이전·파일 인코딩·timeout은 실제 설정을 병합한 환경에서 확인해야 합니다. worker는 기존 2개를 사용할 수 있으며 별도의 순서 의존 필터가 있으면 그 조건을 함께 확인합니다.

## 이력

- 2026-10-18: Logstash aggregate로 구간 기억·본문 조합하던 보완본 게시.
- 2026-10-23: Filebeat multiline + Logstash 이벤트 단위 파싱으로 전환.
