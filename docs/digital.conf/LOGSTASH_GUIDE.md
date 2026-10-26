# Logstash 신규 필터 가이드

기준일: 2026-10-26 · 전제: Filebeat가 레코드 전체를 한 message로 조합해서 전송

## 1. 현재 신규 필터

아래 코드는 신규 파일용 부분만 보여줍니다. 기존 VAN·input·output을 포함한 전체 설정은 [digital.conf](digital.conf)를 기준으로 합니다.

~~~logstash
filter {
        # Filebeat sends one complete timestamp-delimited record per event.
        if [log][file][path] =~ /(?:^|[\\\/])epay\.out$/ {
            grok {
                match => {
                    "message" => [
                        "(?m)^REQUEST DATA\r?\n[ \t]*\*+[ \t]*\r?\n\[url=%{DATA:[data][request_url]}(?:[&?]%{DATA:[@metadata][request_query]})?\][ \t]*\r?\n[ \t]*\*+[ \t]*\r?$",
                        "(?m)^RESULT DATA\r?\n[ \t]*\*+[ \t]*\r?\n%{DATA:[@metadata][response_json]}\r?\n[ \t]*\*+[ \t]*\r?$"
                    ]
                }
                tag_on_failure => ["_epay_section_parse_failure"]
            }

            if "_epay_section_parse_failure" in [tags] {
                drop {}
            } else if [@metadata][response_json] {
                json {
                    source => "[@metadata][response_json]"
                    target => "[data][result_data]"
                    tag_on_failure => ["_epay_response_json_failure"]
                }

                if "_epay_response_json_failure" in [tags] {
                    drop {}
                } else if [data][result_data][0][TR_ID] {
                    ruby {
                        code => '
                            path = "[data][result_data][0][TR_ID]"
                            event.set(path, java.net.URLEncoder.encode(event.get(path).to_s, "UTF-8"))
                        '
                    }
                }
            } else if [@metadata][request_query] {
                kv {
                    source => "[@metadata][request_query]"
                    target => "[data][request_data]"
                    field_split => "&"
                    value_split => "="
                    allow_empty_values => true
                    whitespace => "strict"
                }
            }
        }
}
~~~

기존 filter 전체를 위 코드로 덮어쓰면 VAN 분기가 빠집니다. 전체 설정에서는 신규 if 다음에 기존 VAN else if가 연결돼 있습니다.

## 2. 그룹별 동작

| 그룹 | 역할 |
|---|---|
| 파일 경로 if | epay.out 이벤트만 신규 파싱 |
| grok 패턴 두 개 | 요청 URL 행 또는 RESULT JSON 본문 추출 |
| 실패 조건 | 구간 추출 실패 이벤트 저장 제외 |
| response_json 분기 | 추출한 응답 JSON을 구조화 |
| JSON 실패 조건 | JSON 문법 오류 이벤트 저장 제외 |
| TR_ID Ruby | 첫 번째 응답 객체의 TR_ID만 URL 인코딩 |
| request_query kv | 요청 파라미터를 &와 = 기준으로 필드화 |

정상 요청은 grok·kv, 정상 응답은 grok·JSON·필요할 때 Ruby를 실행합니다. grok은 기본 break_on_match: true이므로 첫 패턴에 성공하면 뒤의 패턴을 검사하지 않습니다.

aggregate·이벤트 간 상태·본문 누적·Logstash timeout을 쓰지 않습니다. metadata는 현재 이벤트의 추출값을 잠깐 전달하는 필드이며 다음 이벤트를 기다리는 기억 공간이 아닙니다. 이 신규 필터 자체는 worker 1·순서 유지를 요구하지 않습니다.

## 3. grok 패턴 읽기

- (?m): Logstash grok에서 점(.)이 줄바꿈까지 포함해 응답 여러 줄을 캡처하도록 함.
- ^REQUEST DATA / ^RESULT DATA: 해당 제목 행에서 시작.
- \r?\n: LF 또는 CRLF 줄 구분 처리.
- [ \t]*\*+[ \t]*: 별표 개수와 구분선 앞뒤 공백·탭 허용.
- 요청의 DATA: URL 값과 query 문자열을 추출.
- (?:[&?]…)? : 첫 query 구분자가 & 또는 ?인 경우, query 없는 경우 허용.
- 응답의 DATA: 첫 종료 별표 행까지 JSON 본문을 추출. 키별로 패턴을 나열하지 않음.

제목·구분선·본문의 배치는 고정하고, 그 안의 업무 값을 가변적으로 받습니다. 지원 범위와 한계는 [가변 형식 문서](VARIABLE_FORMATS.md)에 상세히 적었습니다.

## 4. 요청 예시와 생성값

설명용 식별값입니다.

~~~text
[url=https://example.com/api&RESULT_CODE=0000&TR_ID=ABC%2B123%3D&PARTNER_CODE=TEST]
~~~

~~~json
{
  "data": {
    "request_url": "https://example.com/api",
    "request_data": {
      "RESULT_CODE": "0000",
      "TR_ID": "ABC%2B123%3D",
      "PARTNER_CODE": "TEST"
    }
  }
}
~~~

query 키 이름·개수·순서는 kv가 처리하므로 RESULT_CODE·TR_ID·PARTNER_CODE를 필수로 지정하지 않습니다. 요청 URL·값은 디코딩하거나 재인코딩하지 않습니다. KEY= 같은 빈 값을 보존하고 query가 없으면 kv를 건너뜁니다.

## 5. 응답 예시와 생성값

~~~json
[{"RESULT_CODE":"0000","RESULT_MSG":"성공","TR_ID":"ABC+123="}]
~~~

JSON 파싱과 TR_ID 변환 뒤의 업무 필드:

~~~json
{
  "data": {
    "result_data": [
      {
        "RESULT_CODE": "0000",
        "RESULT_MSG": "성공",
        "TR_ID": "ABC%2B123%3D"
      }
    ]
  }
}
~~~

Logstash의 TR_ID 접근 경로는 [data][result_data][0][TR_ID]이며, Kibana에서는 data.result_data.TR_ID로 확인합니다. 원문 배열의 객체가 여러 개면 JSON 파싱은 전체를 하지만 TR_ID 인코딩은 첫 객체에만 적용합니다.

EPayReturnReq·그 안의 카드 필드 등은 JSON 본문에 있으면 구조대로 추출됩니다. RESULT_CODE나 TR_ID가 없다고 응답 전체를 버리지는 않습니다. 빈 배열 []도 정상 JSON으로 유지합니다.

## 6. 저장되는 내용과 실패 처리

message는 Filebeat가 만든 날짜·제목·구분선·본문 전체로 유지합니다. 파싱된 업무 필드는 data 아래에 추가합니다. TR_ID 인코딩은 추출 필드만 바꾸므로 message의 원문 값은 유지합니다. metadata는 일반적인 Elasticsearch 출력에 포함되지 않습니다.

에러 태그 _epay_section_parse_failure 또는 _epay_response_json_failure를 확인해 drop합니다. drop된 이벤트의 태그는 색인에서 검색할 수 없습니다. JSON 파서는 실패 경고를 남길 수 있지만 모든 grok 실패가 개별 경고 로그로 남는 것은 아니므로, 운영 실패 건수 집계가 필요하면 별도 관측 경로를 설계해야 합니다. 현재 설정에 오류 이벤트 전용 저장소는 포함되지 않았습니다.

전체 설정의 접속 비밀번호는 공개용 임시값 00000000 네 곳입니다. 운영 목적지·인덱스·비밀번호는 실제 환경에서 확인합니다.

## 7. 검증과 한계

첨부 원문의 독립적인 구간 추출값과 비교하여 요청 1,056건·RESULT 응답 946건이 일치했습니다. POST RESPONSE DATA는 제외합니다. 응답 여러 줄 188건, 빈 배열 7건도 포함됩니다.

이 검사는 Python 재현과 실제 Java URLEncoder 기준이며 실제 Filebeat·Logstash/JRuby 실행·부하 검사는 아닙니다. 업무 문서 간 TR_ID를 자동 결합하거나 전송 재시도 중복을 제거하는 설정도 아닙니다.

- [Filebeat 가이드](FILEBEAT_GUIDE.md)
- [가변 형식 지원 범위](VARIABLE_FORMATS.md)
- [검증 결과](VALIDATION.md)
- [grok 공식 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-grok)
- [kv 공식 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-kv)
- [JSON 공식 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-json)
