# digital.conf 최종 적용 가이드

기준일: 2026-10-29. 전제: 각 OUTBOUND 메시지에 시간값과 본문이 같은 물리적 한 줄에 있습니다.

## 1. 처리 흐름

~~~text
Filebeat가 한 줄씩 전달
  → 원본 경로에 epay 포함?
    → OUTBOUND 요청·응답?
      → grok으로 공통 헤더와 본문 분리
      → log_timestamp 날짜 변환
      → 요청: kv → request_data.*
      → 응답: json → result_data.*
    → 일반 로그: 제외
  → epay 이외의 경로: 기존 VAN 조건 검사
  → 기존 공통 처리
  → 해당 output 조건에 따라 Elasticsearch 전송
~~~

정상 대상이 grok에 실패하더라도 일반 로그용 else로 다시 이동하지 않습니다. 실패 태그를 남겨 후속 output으로 전달합니다.

## 2. 저장 구조

공통 필드:

| 필드 | 의미 |
|---|---|
| log_timestamp | 원문 발생시각을 Asia/Seoul로 해석한 날짜 값 |
| loglevel | INFO 등 로그 레벨 |
| logger | PostManager 등 로거 이름 |
| status | OUTBOUND REQUEST DATA 또는 OUTBOUND RESULT TO JSON DATA |
| PARTNER_CODE | 앞부분 [PARTNER_CODE:...] |
| TR_ID | 앞부분 [TR_ID:...] — 공통 매칭키 |
| url | 요청 URL의 첫 & 이전 부분 |
| request_data.* | 요청 파라미터 전체 |
| result_data.* | 응답 JSON 객체 전체 |

헤더 TR_ID와 본문 TR_ID는 서로 다른 값일 수 있습니다. request_data / result_data로 분리해 원문을 보존하고 헤더 필드를 덮어쓰지 않습니다. 본문 PARTNER_CODE도 마찬가지입니다.

## 3. 비식별 예시

다음은 실제 거래값이 아닌 설명용 예시입니다.

~~~text
2026-10-26 15:00:00,001 INFO [PostManager] [OUTBOUND REQUEST DATA][PARTNER_CODE:DEMO01][TR_ID:TRACE001][url=https://example.invalid/callback&RESULT_CODE=0000&RESULT_MSG=&TR_ID=token%2Bvalue%3D&PARTNER_CODE=DEMO01]
2026-10-26 15:00:00,501 INFO [PostManager] [OUTBOUND RESULT TO JSON DATA][PARTNER_CODE:DEMO01][TR_ID:TRACE001][{"RESULT_CODE":"0000","RESULT_MSG":"성공","PARTNER_CODE":"DEMO01","TR_ID":"token+value="}]
~~~

요청:

~~~json
{
  "status": "OUTBOUND REQUEST DATA",
  "PARTNER_CODE": "DEMO01",
  "TR_ID": "TRACE001",
  "url": "https://example.invalid/callback",
  "request_data": {
    "RESULT_CODE": "0000",
    "RESULT_MSG": "",
    "TR_ID": "token%2Bvalue%3D",
    "PARTNER_CODE": "DEMO01"
  }
}
~~~

응답:

~~~json
{
  "status": "OUTBOUND RESULT TO JSON DATA",
  "PARTNER_CODE": "DEMO01",
  "TR_ID": "TRACE001",
  "result_data": {
    "RESULT_CODE": "0000",
    "RESULT_MSG": "성공",
    "PARTNER_CODE": "DEMO01",
    "TR_ID": "token+value="
  }
}
~~~

위 예시에서는 공통 시간·레벨·로거 필드만 생략했습니다. 이 필드들도 실제 설정에서는 추출합니다. 원문 message와 Filebeat 기본 필드도 유지합니다.

## 4. 시간 처리와 Elasticsearch 매핑

현재 date의 target은 log_timestamp입니다. 원문 2026-10-26 15:00:00,001을 한국시간으로 해석하면 2026-10-26T06:00:00.001Z로 직렬화됩니다.

@timestamp를 덮어쓰는 mutate copy는 사용자가 제거한 상태를 유지합니다. Kibana 데이터뷰가 @timestamp를 시간 필드로 사용하면 기존 입력 시간 기준입니다. 원문 발생시각을 기준으로 검색하려면 date 매핑이 확인된 log_timestamp를 시간 필드로 사용하거나, 별도 합의 후 @timestamp 반영 정책을 변경해야 합니다.

매핑 확인:

~~~http
GET s_epay2_test-*/_mapping/field/log_timestamp
~~~

신규 인덱스의 매핑/기존 적용 템플릿에는 다음 속성을 명시할 수 있습니다.

~~~json
{
  "properties": {
    "log_timestamp": {
      "type": "date"
    }
  }
}
~~~

이는 매핑 구성 조각이며, 기존 인덱스에 text로 등록된 필드를 date로 제자리 변경하는 명령이 아닙니다. 기존 인덱스는 새 인덱스·재색인 또는 새 날짜 필드 전략이 필요합니다. 기존 데이터를 임의로 삭제하지 마세요. JSON 화면에 날짜가 문자열로 보이는 것만으로 매핑 타입을 판단할 수는 없습니다.

## 5. 기존 digital.conf와의 통합

전체 설정은 [digital.conf](digital.conf)를 사용합니다. 기존 VAN 정규식 48개는 원본 패턴을 유지했고, 기존 공통 TRANS_DT / timestamp / trans_time / event.original 처리도 보존했습니다.

- beats input: 9900
- VAN 출력: 기존 KAMO / DANG / TOSS 인덱스 설정 유지
- 신규 출력: 원본 경로에 epay가 포함된 이벤트 → s_epay2_test-%{+YYYY.MM.dd}
- 기존처럼 LPAY 전용 Elasticsearch output은 별도로 추가하지 않았습니다.
- 비밀번호 4곳: 공개용 00000000. 실제 비밀번호로 복구 필수.
- @timestamp 기반 날짜 인덱싱은 원문 시간 필드와 자동으로 동기화되지 않습니다.

epay 조건은 파일명뿐 아니라 전체 경로의 부분 일치입니다. 다른 서비스 경로도 포함되면 해당 서비스 로그를 제외할 수 있으므로 운영에서는 원본 파일의 정확한 전용 경로로 좁히고 output도 같이 맞추세요.

## 6. 실패 확인

| 태그 | 의미 |
|---|---|
| _outbound_parse_failure | OUTBOUND 마커는 있으나 헤더/본문 프레임 추출 실패 |
| _outbound_date_failure | 시간 문자열을 지정 형식으로 해석하지 못함 |
| _outbound_kv_failure | kv 처리 예외 |
| _kv_filter_timeout | kv 기본 처리 시간 초과 태그 |
| _outbound_json_failure | 추출한 응답 본문이 유효한 JSON이 아님 |

kv 태그가 없다는 것만으로 임의의 비정상 query가 전부 해석됐다는 보장은 없습니다. 첨부 정상 실로그는 전체 key=value와 추출 결과를 별도로 비교했습니다.

필요하면 digital용 output에만 stdout { codec => rubydebug }를 잠시 추가해 경로·태그·필드를 확인하고 제거하세요. stdout 출력은 Elasticsearch 저장 성공 증거가 아니므로 색인 오류와 조회 시간 범위를 별도 확인합니다.

## 7. 검증과 참고

실로그 재현 결과와 한계는 [VALIDATION.md](VALIDATION.md)에 있습니다.

- [Grok](https://www.elastic.co/guide/en/logstash/8.17/plugins-filters-grok.html)
- [KV](https://www.elastic.co/guide/en/logstash/8.17/plugins-filters-kv.html)
- [JSON](https://www.elastic.co/guide/en/logstash/8.17/plugins-filters-json.html)
- [Date](https://www.elastic.co/guide/en/logstash/8.17/plugins-filters-date.html)
- [기존 필드 타입 변경 제한](https://www.elastic.co/guide/en/elasticsearch/reference/8.17/indices-put-mapping.html)
