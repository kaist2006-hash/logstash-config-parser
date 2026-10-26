# Filebeat 설정 가이드 — type: log

기준일: 2026-10-26 · 수집 대상: REQUEST DATA와 RESULT DATA

## 1. 적용할 설정

아래는 전체 filebeat.yml이 아니라 기존 filebeat.inputs에 합칠 신규 파일 전용 입력입니다.

~~~yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /실제/로그/경로/epay.out

    multiline.type: pattern
    multiline.pattern: '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}'
    multiline.negate: true
    multiline.match: after
    multiline.timeout: 5s

    include_lines: ['(?m)^(REQUEST DATA|RESULT DATA)\r?$']
~~~

이미 filebeat.inputs가 있으면 그 아래에 - type: log 블록만 병합합니다. input을 별도 파일로 로딩한다면 [입력 목록 조각](filebeat.epay-log.input.yml)을 참고하세요. 현재 운영 input이 log인지 실제 설정으로 확인해야 하며, 이번 예시는 input 유형을 전환하는 작업이 아닙니다.

## 2. 옵션별 의미

| 옵션 | 동작 |
|---|---|
| paths | 이 multiline·필터를 적용할 파일 범위 |
| multiline.type | 정규식 기반으로 줄 연결 여부 판단 |
| pattern | 날짜·시간으로 시작하는 줄을 새 레코드의 시작으로 판단 |
| negate: true / match: after | 날짜로 시작하지 않는 줄을 앞 레코드에 연결 |
| timeout: 5s | 새 경계가 없어도 timeout 후 대기 중인 메시지 전송 |
| include_lines | 완성된 메시지에 REQUEST DATA 또는 RESULT DATA 독립 행이 있는 경우만 전송 |

include_lines는 multiline 조합 뒤에 적용합니다. 제목 한 줄만 남기는 옵션이 아니라, 제목이 포함된 완성 메시지 전체의 전송 여부를 결정합니다. POST RESPONSE DATA만 있는 메시지와 일반 로그는 제외합니다.

## 3. 실제 로그 형태와 전송 결과

아래는 첨부 RESULT 응답과 같은 구조이며 구분선 길이를 줄였습니다.

~~~text
2026-10-01 13:04:43,165 INFO [PostManager]
********************
RESULT DATA
********************
[{
  "RESULT_CODE": "0000",
  "RESULT_MSG": "성공",
  "PARTNER_CODE": "MKED1"
}]
********************
~~~

다음 날짜·시간 시작 줄이 오면 위 전체가 message 필드 하나인 이벤트 한 건이 됩니다. 문자열 안의 줄바꿈은 유지합니다. 개행을 없애 한 줄 문자열로 붙이는 설정이 아닙니다.

요청도 날짜 행·별표·REQUEST DATA·별표·[url=…]·별표가 하나의 message가 됩니다. 날짜 정규식은 레코드 경계 판단에 쓰이며 날짜를 별도 업무 필드로 파싱하는 설정은 아닙니다. 현재 Logstash는 전체 message를 보존하므로 날짜·제목·구분선도 message에는 남습니다.

## 4. 기존 파일 수집에 영향 없게 적용

- 신규 epay.out 전용 input에만 적용합니다. 공용 VAN input에 include_lines를 넣으면 VAN 레코드가 제외될 수 있습니다.
- 기존 input의 glob도 epay.out을 읽는다면 paths를 분리하거나 기존 input에서 이 파일을 제외합니다.
- 기존 encoding, 업무 라우팅용 fields·tags·processors 중 필요한 항목을 유지합니다.
- 기존 output.logstash를 사용합니다. 이번 입력 예시에 전역 output을 중복 추가하지 않습니다.
- 실제 파일명과 Logstash의 epay.out 경로 조건을 함께 맞춥니다.
- input 유형·식별자·registry 변경은 기존 읽기 위치와 재수집 여부에 영향을 줄 수 있으므로 기존 상태를 확인합니다.

기존 log input에서 신규 파일을 제외할 때의 예시는 다음입니다. 이 옵션은 신규 epay 전용 input이 아니라 기존 중복 입력에 적용합니다.

~~~yaml
exclude_files: ['(^|[\\/])epay\.out$']
~~~

## 5. 적용 전 확인

기존 Filebeat 실행 명령의 설정 경로·옵션을 기준으로 설정 검사를 수행하고, 실제 전송 이벤트에 제목부터 마지막 별표까지 있는지 확인합니다. 날짜 형식이 바뀌거나 본문 완성 전에 timeout되면 메시지가 잘못 나뉠 수 있습니다. 최대 줄·바이트 제한 초과, 회전·재시작 동작도 실제 환경에서 확인해야 합니다.

첨부 파일 재현에서는 요청 1,056건·RESULT 응답 946건이 선택됐고, RESULT의 여러 줄 본문 188건을 모두 처리했습니다. 실제 Filebeat 실행·부하 검사를 완료한 결과는 아닙니다.

## 관련 문서

- [Logstash 가이드](LOGSTASH_GUIDE.md)
- [가변 형식 지원 범위](VARIABLE_FORMATS.md)
- [검증 결과](VALIDATION.md)
- [Filebeat log input 공식 문서](https://www.elastic.co/guide/en/beats/filebeat/8.17/filebeat-input-log.html)
- [multiline 공식 문서](https://www.elastic.co/docs/reference/beats/filebeat/multiline-examples)
