# digital.conf 진행 현황

업데이트: 2026-10-23

## 현재 수집 대상

- 요청: REQUEST DATA 하위 [url=…].
- 응답: RESULT DATA 하위 JSON.
- POST RESPONSE DATA: 수집 제외.

Filebeat가 날짜·시간 경계로 multiline 메시지를 완성한 후 위 두 제목이 있는 레코드만 전송합니다. Logstash는 한 이벤트 안에서 요청 URL·query 또는 응답 JSON을 파싱하고 응답 첫 객체의 TR_ID만 URL 인코딩합니다.

## 파일

- [digital.conf](digital.conf): 현재 전체 Logstash 설정.
- [Filebeat filestream input 예시](filebeat.epay-filestream.input.yml).
- [Filebeat 기존 log input 예시](filebeat.epay-log.input.yml).
- [설정 가이드](GUIDE.md).
- [검증 요약](VALIDATION.md).

Filebeat 파일은 기존 filebeat.inputs에 합칠 input 목록 조각입니다. 현재 input 유형에 맞는 하나를 고르고 실제 경로·기존 encoding·ID·읽기 상태에 맞춰 병합합니다. 신규 파일을 기존 input과 중복해서 읽지 않도록 분리하며 공용 VAN input에는 이 include_lines를 적용하지 않습니다.

## 이번 변경

Filebeat include_lines와 Logstash 응답 grok의 제목을 RESULT DATA로 바꿨습니다. 종료 별표가 반복되는 실로그에 맞춰 응답 본문은 첫 종료 구분선까지만 추출합니다.

aggregate·구간 상태·Logstash 본문 버퍼는 사용하지 않습니다. 이번 신규 필터는 worker 1을 요구하지 않아 기존 worker 2를 사용할 수 있습니다. 요청 처리, 응답 배열 구조·TR_ID 인코딩, 기존 VAN·input·output은 유지합니다. 공개용 접속 password는 00000000 네 곳입니다.

## 검증 상태

첨부 실로그 순차 재현에서 요청 1,056건과 RESULT 응답 946건을 정상 추출했습니다. 응답은 한 줄 758건, 5줄 181건, 6줄 7건입니다. 빈 배열 응답 7건도 그대로 보존합니다. POST RESPONSE DATA는 0건 선택했습니다.

이전 POST 응답 1,049건과 이번 RESULT 응답 946건은 서로 다른 수집 범위입니다. 같은 내용인 응답이 939건이며, RESULT의 빈 배열 7건과 POST 쪽 추가 내용 110건은 서로 일치하지 않습니다. 따라서 이전 응답 전체와 동일한 수집 결과라고 해석하면 안 됩니다.

실제 Filebeat/Logstash 실행·부하 시험 및 운영 서버 배포는 수행하지 않았습니다. 원본 로그·거래값은 공개하지 않았습니다.

## 이력

- 2026-10-18: Logstash aggregate로 구간 기억·본문 조합.
- 2026-10-23: Filebeat multiline으로 조합 위치 이동.
- 2026-10-23: 사용자 변경 방향에 따라 POST RESPONSE DATA를 제외하고 RESULT DATA 응답 수집으로 전환.
