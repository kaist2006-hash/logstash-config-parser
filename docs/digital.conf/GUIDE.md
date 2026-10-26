# digital.conf 설정 가이드 — Filebeat multiline 방식

기준일: 2026-10-26

상세 문서: [Filebeat 가이드](FILEBEAT_GUIDE.md) · [Logstash 가이드](LOGSTASH_GUIDE.md) · [가변 형식 지원 범위](VARIABLE_FORMATS.md)

## 1. 이번 변경의 핵심

응답 수집 대상은 RESULT DATA입니다. 이전 POST RESPONSE DATA 수집은 제외합니다. 첨부에서 두 구간의 건수·내용이 완전히 같지는 않으므로, 이번 변경은 응답의 수집 위치를 바꾸는 작업입니다.

Filebeat가 같은 로그 레코드의 여러 줄을 하나의 message로 만들어 보냅니다. Logstash는 이벤트 한 개 안에서 REQUEST DATA 하위 URL 또는 RESULT DATA 하위 JSON을 추출합니다.

- Filebeat: 날짜·시간 시작 줄을 경계로 합친 후, 요청·RESULT 응답 제목이 포함된 메시지만 전송.
- Logstash: 파일 조건 → grok으로 구간·본문 추출 → 요청 kv 또는 응답 JSON → 응답 TR_ID URL 인코딩.
- Logstash의 aggregate, 파일별 상태, timeout, 본문 조합 버퍼를 제거.
- 신규 필터는 이벤트 간 상태가 없어 worker 1·ordered true를 요구하지 않음. 기존 worker 2 사용 가능. 기존의 다른 필터가 순서를 요구한다면 그 조건은 별도 확인.
- 응답 배열을 그대로 JSON 파싱하므로 기존 [data][result_data][0][TR_ID] 경로를 유지.

## 2. 파일 구성

- [digital.conf](digital.conf): 기존 VAN·input·output을 포함한 전체 Logstash 설정.
- [filestream 입력 예시](filebeat.epay-filestream.input.yml): 현재 input이 filestream일 때 참고.
- [log 입력 예시](filebeat.epay-log.input.yml): 현재 Filebeat에서 이미 type: log를 사용할 때의 대안.
- [검증 결과](VALIDATION.md): 실로그 재현과 검사 한계.
- [진행 현황](README.md).

두 Filebeat 예시 중 현재 input 유형에 맞는 하나만 사용합니다. 각 파일은 input 목록 조각이며 전체 filebeat.yml이 아닙니다. 기존 filebeat.inputs 아래에 합치거나 inputs.d 로딩 형식에 맞춰 사용합니다. 기존 전역 output.logstash는 그대로 사용합니다.

## 3. Filebeat — 어떤 줄을 합치는가?

~~~yaml
multiline.type: pattern
multiline.pattern: '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}'
multiline.negate: true
multiline.match: after
multiline.timeout: 5s
include_lines: ['(?m)^(REQUEST DATA|RESULT DATA)\r?
~~~

위 문법은 현재 사용 방향인 type: log용입니다. 신규 파일 전용 input 안에 설정합니다. filestream용 예시는 별도 파일이며 input 유형을 무조건 전환할 필요는 없습니다.

| 설정 | 의미 |
|---|---|
| pattern | 날짜·시간으로 시작하면 새 로그 레코드 시작 |
| negate: true / match: after | 날짜·시간으로 시작하지 않는 줄은 앞 레코드에 연결 |
| timeout: 5s | 다음 경계가 안 와도 대기 중인 메시지를 timeout 후 내보냄 |
| include_lines | multiline 이후 REQUEST DATA 또는 RESULT DATA라는 제목 행이 들어 있는 메시지만 전송 |

예를 들어 아래 전체가 Filebeat 이벤트 한 개가 됩니다.

~~~text
2026-10-01 12:00:00,000 INFO [PostManager]
************************
RESULT DATA
************************
[{"RESULT_CODE":"0000","RESULT_MSG":"성공","TR_ID":"ABC+123="}
]
************************
~~~

다음 날짜·시간 시작 줄을 읽으면 앞 이벤트가 완성됩니다. 마지막 레코드는 timeout에 의해 나갈 수 있습니다.

별표는 시작·종료에 같은 형태로 반복되므로 별표만 flush_pattern으로 쓰면 본문 전의 구분선에서 먼저 끊깁니다. 이 설정은 날짜 경계로 합치고, Logstash에서 제목·별표·본문 구조를 검증합니다.

multiline 버퍼는 Filebeat에 존재합니다. 이번 변경은 조합 위치를 Filebeat로 옮기는 것이며 전체 시스템에서 버퍼를 없애는 것은 아닙니다. 본문 작성 중 5초 이상 지연되면 부분 메시지가 먼저 나갈 수 있으므로 실제 수집 시험에서 확인해야 합니다. 이 예시는 Filebeat의 기본 최대 줄·최대 바이트 제한을 변경하지 않습니다. 첨부 원본의 대상 레코드는 최대 11줄·1,124 UTF-8바이트였고 전체 레코드는 최대 51줄이었습니다.

참고: [multiline 공식 문서](https://www.elastic.co/docs/reference/beats/filebeat/multiline-examples), [filestream include_lines](https://www.elastic.co/docs/reference/beats/filebeat/filebeat-input-filestream).

## 4. 다른 파일에 영향 없이 연결하는 방법

epay.out만 별도 input에 넣습니다. 여러 VAN 파일이 들어 있는 기존 공용 input에 이 multiline·include_lines를 적용하면 그 파일들의 합치기·필터링 동작도 바뀝니다.

1. 예시의 /CHANGE_ME/epay.out을 실제 운영 경로로 교체.
2. 현재 input 유형·ID·encoding 설정을 확인해 유지할 수 있는 것은 유지.
3. 기존 input의 glob이 epay.out도 읽는지 확인. 겹치면 기존 input에서 epay.out을 제외하거나 paths를 분리.
4. 기존에 쓰던 fields, tags, processors가 라우팅에 필요하면 전용 input에도 필요한 값을 유지.
5. 기존 전역 output은 유지. Filebeat 설정과 Logstash 설정은 서로 맞는 버전으로 전환.

기존 input의 제외 옵션은 유형에 따라 다릅니다.

~~~yaml
# 기존 filestream input에 적용하는 제외 예시
prospector.scanner.exclude_files: ['(^|[\\/])epay\.out$']

# 기존 type: log input에 적용하는 제외 예시
exclude_files: ['(^|[\\/])epay\.out$']
~~~

해당 유형의 옵션 하나만 사용합니다. epay.out이 이미 읽히는 파일이라면 input ID·유형·registry 변경은 읽기 위치와 재수집에 영향을 줄 수 있습니다. 실제 Filebeat 설정을 받지 않았으므로 이번 예시는 registry 이전이나 운영 input 교체를 자동 수행하지 않습니다. 검증에 사용한 CP949 원본에 맞춰 입력 문자셋을 새로 지정한 것도 아니므로 현재 한글이 정상 처리되는 encoding을 유지·확인하세요.

## 5. Logstash — 한 이벤트 안에서 구간 추출

파일 조건은 그대로 epay.out만 선택합니다.

~~~logstash
if [log][file][path] =~ /(?:^|[\\\/])epay\.out$/ {
~~~

grok의 match 배열에는 두 패턴이 있습니다. 실제 전문은 [digital.conf](digital.conf)를 참고하세요.

- 요청 패턴: REQUEST DATA → 별표 구분선 → [url=…] 한 줄 → 별표 구분선.
- 응답 패턴: RESULT DATA → 별표 구분선 → JSON 본문 전체 → 별표 구분선.

응답 본문 캡처에는 DATA를 사용해 첫 종료 별표 행까지만 가져옵니다. 종료 별표가 연속으로 나오는 실로그에서도 뒤의 구분선을 JSON에 포함하지 않도록 했습니다.

grok이 한 이벤트의 문자열을 보는 동안 그 안의 여러 줄에 접근합니다. 따라서 이전 이벤트를 기억하거나 다음 이벤트를 기다리지 않습니다. 구간 제목과 별표의 독립 행을 기준으로 선택하므로 단독 URL, POST RESPONSE DATA, 일반 로그는 해당 패턴으로 통과하지 않습니다.

(?m)은 이 grok 정규식에서 점(.)이 개행까지 포함하도록 하므로 응답의 여러 줄을 캡처할 수 있습니다. 요청 URL·query는 기존과 같은 분리 규칙을 사용합니다.

공통 추출에 실패하면 _epay_section_parse_failure로 판정해 해당 이벤트를 drop합니다. 실패를 숨겨 정상 데이터처럼 저장하는 처리가 아닙니다. 태그가 붙은 이벤트는 drop되므로 색인에서 실패 태그를 조회해 집계할 수는 없습니다. 실제 로그와 실패 모니터링으로 확인해야 합니다.

## 6. 요청 — URL 분리 + kv

grok이 URL을 data.request_url로, 파라미터 문자열을 임시 metadata에 저장합니다.

~~~logstash
kv {
    source => "[@metadata][request_query]"
    target => "[data][request_data]"
    field_split => "&"
    value_split => "="
    allow_empty_values => true
    whitespace => "strict"
}
~~~

예시:

~~~text
[url=https://example.com/api&RESULT_CODE=0000&TR_ID=ABC%2B123%3D]
~~~

추출 결과:

~~~text
data.request_url               = https://example.com/api
data.request_data.RESULT_CODE  = 0000
data.request_data.TR_ID        = ABC%2B123%3D
~~~

필드 이름·개수·순서가 달라도 kv로 추출합니다. 요청 TR_ID는 인코딩 상태를 유지하며, URL 디코딩·재인코딩하지 않습니다. URL만 있고 query가 없으면 kv를 실행하지 않습니다.

## 7. 응답 — JSON 파싱 + TR_ID 인코딩

~~~logstash
json {
    source => "[@metadata][response_json]"
    target => "[data][result_data]"
    tag_on_failure => ["_epay_response_json_failure"]
}
~~~

JSON 원문만 metadata에서 읽으므로 제목·일반 로그를 JSON 파서에 넣지 않습니다. 본문이 5~6줄로 나뉘거나 ]가 다음 줄이어도 같은 source 문자열 안에 들어 있습니다. 빈 배열 []도 정상 JSON으로 보존합니다. 특정 RESULT_CODE 필드의 존재는 요구하지 않습니다.

실패한 JSON은 drop합니다. 성공하면 첫 번째 배열 객체에 대문자 TR_ID가 있을 때만 Java URLEncoder로 UTF-8 URL 인코딩합니다.

~~~text
응답 원문 TR_ID: ABC+123=
추출·변환 결과:  ABC%2B123%3D
저장 경로:      data.result_data[0].TR_ID
~~~

TID, 중첩 객체의 tr_ID 등 다른 필드는 그대로입니다. 중첩 EPayReturnReq도 원문 JSON 구조대로 추출됩니다. 응답 배열에 객체가 여러 개면 인코딩은 첫 객체에만 적용하는 기존 동작을 유지합니다. 이미 인코딩된 TR_ID가 들어오면 중복 인코딩될 수 있다는 기존 전제도 같습니다.

JSON 파싱은 응답 필드를 추출하는 것이며 요청과 응답을 한 문서로 합치거나 재전송 중복을 제거하는 기능은 아닙니다.

## 8. message와 기존 설정의 차이

| 항목 | 이전 Logstash 조합 방식 | 이번 방식 |
|---|---|---|
| Logstash에 들어오는 단위 | 원본 한 줄 | Filebeat가 완성한 레코드 한 개 |
| 구간 선택 | 제목을 map에 기억 | 한 message 안에서 grok |
| 응답 조합 | map에 본문 누적 | Filebeat에서 조합 완료 |
| 신규 필터의 worker 조건 | worker 1·순서 유지 필요 | 이벤트 간 상태가 없어 제한 제거 |
| 응답 결과 | result_data 배열 | result_data 배열 유지 |
| message | 요청 한 줄 또는 조합한 응답 JSON | 날짜·제목·구분선·본문을 포함한 원본 레코드 |

이번 설정은 message를 덮어쓰지 않습니다. Kibana에서 message가 여러 줄로 보이는 것은 Filebeat가 합친 레코드에 실제 줄바꿈이 있기 때문입니다. 추출된 필드 경로는 유지됩니다.

기존 input·VAN grok·output은 그대로 유지하며 접속 비밀번호 4곳은 공개용 임시값 00000000입니다. output에는 기존 테스트 인덱스·목적지가 남아 있으므로 실제 적용 대상은 별도로 확인합니다. 이번 파일 작성·GitHub 업데이트는 운영 서버 배포가 아닙니다.

## 9. 적용과 검증

- 현재 Filebeat input 유형·버전·정확한 경로에 맞춰 예시를 병합.
- 동일 파일을 두 input이 동시에 읽지 않도록 범위를 분리.
- 실제 Filebeat 설정 검사 및 메시지 출력으로 제목·본문·마지막 구분선이 한 이벤트인지 확인.
- 실제 Logstash에서 문법 검사 및 재수집 시험. 기존 VAN과 함께 처리량·오류를 확인.
- 이전에 신규 aggregate 때문에만 worker 1로 줄였다면 이번 필터는 worker 2를 허용. 다른 필터 제약이 있는지 확인한 뒤 파이프라인 설정을 반영.
- Filebeat timeout·재시작·registry·회전·배포 중 미완료 레코드는 실제 환경에서 확인.

완료된 재현 결과와 한계는 [VALIDATION.md](VALIDATION.md)에 기재했습니다.
]
~~~

위 parsers 문법은 filestream용입니다. type: log용 multiline.* 문법은 별도 파일을 참고합니다. 현재 설치 버전·input 유형을 확인하고 맞는 문법을 사용하세요. 이번 변경 때문에 type이나 ID를 무조건 교체하는 작업은 아닙니다.

| 설정 | 의미 |
|---|---|
| pattern | 날짜·시간으로 시작하면 새 로그 레코드 시작 |
| negate: true / match: after | 날짜·시간으로 시작하지 않는 줄은 앞 레코드에 연결 |
| timeout: 5s | 다음 경계가 안 와도 대기 중인 메시지를 timeout 후 내보냄 |
| include_lines | multiline 이후 REQUEST DATA 또는 RESULT DATA라는 제목 행이 들어 있는 메시지만 전송 |

예를 들어 아래 전체가 Filebeat 이벤트 한 개가 됩니다.

~~~text
2026-10-01 12:00:00,000 INFO [PostManager]
************************
RESULT DATA
************************
[{"RESULT_CODE":"0000","RESULT_MSG":"성공","TR_ID":"ABC+123="}
]
************************
~~~

다음 날짜·시간 시작 줄을 읽으면 앞 이벤트가 완성됩니다. 마지막 레코드는 timeout에 의해 나갈 수 있습니다.

별표는 시작·종료에 같은 형태로 반복되므로 별표만 flush_pattern으로 쓰면 본문 전의 구분선에서 먼저 끊깁니다. 이 설정은 날짜 경계로 합치고, Logstash에서 제목·별표·본문 구조를 검증합니다.

multiline 버퍼는 Filebeat에 존재합니다. 이번 변경은 조합 위치를 Filebeat로 옮기는 것이며 전체 시스템에서 버퍼를 없애는 것은 아닙니다. 본문 작성 중 5초 이상 지연되면 부분 메시지가 먼저 나갈 수 있으므로 실제 수집 시험에서 확인해야 합니다. 이 예시는 Filebeat의 기본 최대 줄·최대 바이트 제한을 변경하지 않습니다. 첨부 원본의 대상 레코드는 최대 11줄·1,124 UTF-8바이트였고 전체 레코드는 최대 51줄이었습니다.

참고: [multiline 공식 문서](https://www.elastic.co/docs/reference/beats/filebeat/multiline-examples), [filestream include_lines](https://www.elastic.co/docs/reference/beats/filebeat/filebeat-input-filestream).

## 4. 다른 파일에 영향 없이 연결하는 방법

epay.out만 별도 input에 넣습니다. 여러 VAN 파일이 들어 있는 기존 공용 input에 이 multiline·include_lines를 적용하면 그 파일들의 합치기·필터링 동작도 바뀝니다.

1. 예시의 /CHANGE_ME/epay.out을 실제 운영 경로로 교체.
2. 현재 input 유형·ID·encoding 설정을 확인해 유지할 수 있는 것은 유지.
3. 기존 input의 glob이 epay.out도 읽는지 확인. 겹치면 기존 input에서 epay.out을 제외하거나 paths를 분리.
4. 기존에 쓰던 fields, tags, processors가 라우팅에 필요하면 전용 input에도 필요한 값을 유지.
5. 기존 전역 output은 유지. Filebeat 설정과 Logstash 설정은 서로 맞는 버전으로 전환.

기존 input의 제외 옵션은 유형에 따라 다릅니다.

~~~yaml
# 기존 filestream input에 적용하는 제외 예시
prospector.scanner.exclude_files: ['(^|[\\/])epay\.out$']

# 기존 type: log input에 적용하는 제외 예시
exclude_files: ['(^|[\\/])epay\.out$']
~~~

해당 유형의 옵션 하나만 사용합니다. epay.out이 이미 읽히는 파일이라면 input ID·유형·registry 변경은 읽기 위치와 재수집에 영향을 줄 수 있습니다. 실제 Filebeat 설정을 받지 않았으므로 이번 예시는 registry 이전이나 운영 input 교체를 자동 수행하지 않습니다. 검증에 사용한 CP949 원본에 맞춰 입력 문자셋을 새로 지정한 것도 아니므로 현재 한글이 정상 처리되는 encoding을 유지·확인하세요.

## 5. Logstash — 한 이벤트 안에서 구간 추출

파일 조건은 그대로 epay.out만 선택합니다.

~~~logstash
if [log][file][path] =~ /(?:^|[\\\/])epay\.out$/ {
~~~

grok의 match 배열에는 두 패턴이 있습니다. 실제 전문은 [digital.conf](digital.conf)를 참고하세요.

- 요청 패턴: REQUEST DATA → 별표 구분선 → [url=…] 한 줄 → 별표 구분선.
- 응답 패턴: RESULT DATA → 별표 구분선 → JSON 본문 전체 → 별표 구분선.

응답 본문 캡처에는 DATA를 사용해 첫 종료 별표 행까지만 가져옵니다. 종료 별표가 연속으로 나오는 실로그에서도 뒤의 구분선을 JSON에 포함하지 않도록 했습니다.

grok이 한 이벤트의 문자열을 보는 동안 그 안의 여러 줄에 접근합니다. 따라서 이전 이벤트를 기억하거나 다음 이벤트를 기다리지 않습니다. 구간 제목과 별표의 독립 행을 기준으로 선택하므로 단독 URL, POST RESPONSE DATA, 일반 로그는 해당 패턴으로 통과하지 않습니다.

(?m)은 이 grok 정규식에서 점(.)이 개행까지 포함하도록 하므로 응답의 여러 줄을 캡처할 수 있습니다. 요청 URL·query는 기존과 같은 분리 규칙을 사용합니다.

공통 추출에 실패하면 _epay_section_parse_failure로 판정해 해당 이벤트를 drop합니다. 실패를 숨겨 정상 데이터처럼 저장하는 처리가 아닙니다. 태그가 붙은 이벤트는 drop되므로 색인에서 실패 태그를 조회해 집계할 수는 없습니다. 실제 로그와 실패 모니터링으로 확인해야 합니다.

## 6. 요청 — URL 분리 + kv

grok이 URL을 data.request_url로, 파라미터 문자열을 임시 metadata에 저장합니다.

~~~logstash
kv {
    source => "[@metadata][request_query]"
    target => "[data][request_data]"
    field_split => "&"
    value_split => "="
    allow_empty_values => true
    whitespace => "strict"
}
~~~

예시:

~~~text
[url=https://example.com/api&RESULT_CODE=0000&TR_ID=ABC%2B123%3D]
~~~

추출 결과:

~~~text
data.request_url               = https://example.com/api
data.request_data.RESULT_CODE  = 0000
data.request_data.TR_ID        = ABC%2B123%3D
~~~

필드 이름·개수·순서가 달라도 kv로 추출합니다. 요청 TR_ID는 인코딩 상태를 유지하며, URL 디코딩·재인코딩하지 않습니다. URL만 있고 query가 없으면 kv를 실행하지 않습니다.

## 7. 응답 — JSON 파싱 + TR_ID 인코딩

~~~logstash
json {
    source => "[@metadata][response_json]"
    target => "[data][result_data]"
    tag_on_failure => ["_epay_response_json_failure"]
}
~~~

JSON 원문만 metadata에서 읽으므로 제목·일반 로그를 JSON 파서에 넣지 않습니다. 본문이 5~6줄로 나뉘거나 ]가 다음 줄이어도 같은 source 문자열 안에 들어 있습니다. 빈 배열 []도 정상 JSON으로 보존합니다. 특정 RESULT_CODE 필드의 존재는 요구하지 않습니다.

실패한 JSON은 drop합니다. 성공하면 첫 번째 배열 객체에 대문자 TR_ID가 있을 때만 Java URLEncoder로 UTF-8 URL 인코딩합니다.

~~~text
응답 원문 TR_ID: ABC+123=
추출·변환 결과:  ABC%2B123%3D
저장 경로:      data.result_data[0].TR_ID
~~~

TID, 중첩 객체의 tr_ID 등 다른 필드는 그대로입니다. 중첩 EPayReturnReq도 원문 JSON 구조대로 추출됩니다. 응답 배열에 객체가 여러 개면 인코딩은 첫 객체에만 적용하는 기존 동작을 유지합니다. 이미 인코딩된 TR_ID가 들어오면 중복 인코딩될 수 있다는 기존 전제도 같습니다.

JSON 파싱은 응답 필드를 추출하는 것이며 요청과 응답을 한 문서로 합치거나 재전송 중복을 제거하는 기능은 아닙니다.

## 8. message와 기존 설정의 차이

| 항목 | 이전 Logstash 조합 방식 | 이번 방식 |
|---|---|---|
| Logstash에 들어오는 단위 | 원본 한 줄 | Filebeat가 완성한 레코드 한 개 |
| 구간 선택 | 제목을 map에 기억 | 한 message 안에서 grok |
| 응답 조합 | map에 본문 누적 | Filebeat에서 조합 완료 |
| 신규 필터의 worker 조건 | worker 1·순서 유지 필요 | 이벤트 간 상태가 없어 제한 제거 |
| 응답 결과 | result_data 배열 | result_data 배열 유지 |
| message | 요청 한 줄 또는 조합한 응답 JSON | 날짜·제목·구분선·본문을 포함한 원본 레코드 |

이번 설정은 message를 덮어쓰지 않습니다. Kibana에서 message가 여러 줄로 보이는 것은 Filebeat가 합친 레코드에 실제 줄바꿈이 있기 때문입니다. 추출된 필드 경로는 유지됩니다.

기존 input·VAN grok·output은 그대로 유지하며 접속 비밀번호 4곳은 공개용 임시값 00000000입니다. output에는 기존 테스트 인덱스·목적지가 남아 있으므로 실제 적용 대상은 별도로 확인합니다. 이번 파일 작성·GitHub 업데이트는 운영 서버 배포가 아닙니다.

## 9. 적용과 검증

- 현재 Filebeat input 유형·버전·정확한 경로에 맞춰 예시를 병합.
- 동일 파일을 두 input이 동시에 읽지 않도록 범위를 분리.
- 실제 Filebeat 설정 검사 및 메시지 출력으로 제목·본문·마지막 구분선이 한 이벤트인지 확인.
- 실제 Logstash에서 문법 검사 및 재수집 시험. 기존 VAN과 함께 처리량·오류를 확인.
- 이전에 신규 aggregate 때문에만 worker 1로 줄였다면 이번 필터는 worker 2를 허용. 다른 필터 제약이 있는지 확인한 뒤 파이프라인 설정을 반영.
- Filebeat timeout·재시작·registry·회전·배포 중 미완료 레코드는 실제 환경에서 확인.

완료된 재현 결과와 한계는 [VALIDATION.md](VALIDATION.md)에 기재했습니다.
