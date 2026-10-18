# epay 요청·응답 Logstash 설정 가이드

작성일: 2026-10-17 · GitHub 정리: 2026-10-18 · 기준: 저장소 루트 `digital.conf` 보완본

이 문서는 신규로 추가한 필터를 이해하기 위한 설명서입니다. 기존 VAN 파싱·접속 정보는 반복하지 않습니다. 운영 서버에 배포한 문서는 아닙니다. GitHub 공개본은 접속 비밀번호 4곳만 임시값 `00000000`으로 바꾸고, 주소·계정·필터·인덱스 설정은 유지했습니다.

## 1. 먼저 알아둘 핵심

**요청·응답의 필드 이름이 아니라, 로그가 출력된 구간을 기준으로 수집합니다.**

- 요청: `REQUEST DATA` 구간의 `[url=…]` 한 줄을 grok·kv로 파싱합니다.
- 응답: `POST RESPONSE DATA` 구간의 JSON 배열 본문을 모아 JSON 플러그인으로 파싱합니다.
- 요청 TR_ID는 그대로 두고, 응답 첫 번째 객체의 TR_ID만 URL 인코딩합니다.
- `RESULT DATA`의 별도 출력과 일반 로그는 수집 대상으로 삼지 않습니다.
- 요청과 응답은 각각 별도 문서입니다. 이 설정은 두 문서를 결합하거나 재전송 중복을 제거하지 않습니다.

### 관련 파일

- [전체 설정](../../digital.conf): input·기존 VAN·output을 포함한 최신 보완본.
- [진행 현황과 적용 주의](README.md): 공개 범위 및 적용 전제.
- [검증 결과 요약](VALIDATION.md): 원본 거래값을 제외한 오프라인 재현 요약.

현재 저장소에는 보완 전 설정·원본 실로그·실거래값이 담긴 상세 결과 파일을 함께 업로드하지 않았습니다. 아래 보완 전후 설명은 로컬 검증에 사용했던 이전 설정과의 비교입니다.

## 2. 기존 설정과 신규 설정의 관계

| 부분 | 처리 내용 |
|---|---|
| 기존 input | Beats 9900 수신 설정 유지 |
| 신규 파일 분기 | `epay.out`만 신규 요청·응답 처리 |
| 기존 VAN 분기 | 신규 분기 밖의 `else if`에서 기존 grok 패턴으로 처리 |
| 기존 output | 기존 전송 설정 유지. 이 문서에서는 변경하지 않음 |

파일 조건은 다른 파일에 신규 파서가 실행되지 않게 합니다. 다만 같은 파이프라인의 worker·메모리·출력 자원은 공유하므로 성능까지 완전히 격리하는 것은 아닙니다.

## 3. 그룹 A — 어떤 파일을 처리할지 선택

```logstash
if [log][file][path] =~ /(?:^|[\\\/])epay\.out$/ {
```

쉽게 말해 **경로의 마지막 파일명이 정확히 `epay.out`인지 확인**합니다.

- `/logs/epay.out`, `C:\logs\epay.out`, `epay.out`: 조건에 맞음.
- `other_epay.out`, `epay.out.1`, `catalina.out`: 조건에 맞지 않음.
- 실제 수집 파일명이 다르면 이 조건을 맞춰야 합니다. 첨부 `catalina (2).out`은 내용 검증에 사용한 원본이며, 배포 조건의 파일명과는 구분합니다.
- 여러 서버·경로의 동일 파일명을 모두 허용합니다. 특정 디렉터리 하나만 허용하려면 경로 조건을 더 좁혀야 합니다.

## 4. 그룹 B — 구간 제목을 기억

### 왜 기억이 필요한가?

Filebeat가 한 줄씩 전달하면 제목과 본문은 서로 다른 이벤트입니다. 본문 한 줄만 보고는 어느 제목 아래에서 나온 것인지 알 수 없으므로, 잠깐 구간 상태를 보관합니다.

```logstash
task_id => "%{[agent][id]}:%{[log][file][path]}"
```

`task_id`는 **Filebeat 식별자 + 파일 경로**로 기억 공간을 나누는 키입니다. TR_ID로 요청·응답을 매칭하는 키가 아닙니다. 파일 조건은 처리 대상을 고르고, task_id는 그 대상들 사이의 상태를 분리합니다. 역할이 다릅니다.

```ruby
m = event.get("message").to_s
if m == "REQUEST DATA" || m == "POST RESPONSE DATA"
    map.clear
    map["kind"] = m == "REQUEST DATA" ? "request" : "response"
    map_meta.timeout = Time.now - map_meta.creation_timestamp + 10
```

| 코드 | 쉬운 설명 |
|---|---|
| `event.get("message")` | 현재 들어온 한 줄을 읽음 |
| `map.clear` | 같은 파일의 이전 미완료 상태를 비움 |
| `map["kind"]` | 현재 요청을 기다리는지, 응답을 기다리는지 저장 |
| `map_meta.timeout = … + 10` | 기존 map의 생성 시각을 기준으로 계산되는 만료 시간을 새 제목 시점에 맞춰 갱신 |

제목은 정확히 일치해야 합니다. 현재 코드에는 제목 앞뒤 공백이나 타임스탬프를 자동 제거하는 처리가 없습니다.

### timeout은 대기 명령이 아님

`timeout => 10`은 미완료 상태를 정리하기 위한 설정입니다. worker가 10초 동안 멈춰 있거나 뒤의 로그가 모두 대기하는 구조가 아닙니다. 새 제목에서 만료 시간을 갱신하지만, 본문 한 줄마다 갱신하는 inactivity timeout 방식은 아닙니다.

만료 map은 주기적으로 정리되므로 정확히 10초가 되는 순간의 차단을 보장하지 않습니다. timeout으로 미완료 응답을 출력하는 옵션도 켜지 않았습니다. 종료 구분선이 오지 않은 응답은 정상 문서로 완성되지 않습니다.

aggregate의 task별 map·timeout 역할은 [Elastic aggregate 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-aggregate)를 참고하세요.

## 5. 그룹 C — 요청 한 줄 선택·파싱

### 실제 처리 순서

예시는 설명용 값입니다.

```text
REQUEST DATA
************************
[url=https://example.com/api&RESULT_CODE=0000&RESULT_MSG=OK&TR_ID=ABC%2B123%3D&PARTNER_CODE=TEST]
************************
```

1. 제목에서 요청 상태를 기억합니다.
2. 별표만 있는 구분선은 지나갑니다.
3. 다음 구분선이 아닌 줄에서 요청 상태를 지웁니다.
4. 그 줄이 `[url=`로 시작하면 요청 파싱 대상으로 표시합니다.

```ruby
elsif map["kind"] == "request"
    map.delete("kind")
    if m.start_with?("[url=")
        event.set("[@metadata][epay_kind]", "request")
    end
```

즉, 제목 아래에서 URL이 나올 때까지 일반 로그를 무제한 건너뛰는 방식이 아닙니다. 제목과 URL 사이에 빈 줄이나 일반 로그가 끼면 이 요청 선택이 끝날 수 있습니다. 첨부 실로그에서는 이 조건으로 요청 1,056건을 선택했습니다.

### grok: URL과 파라미터 문자열을 분리

```logstash
grok {
    match => {
        "message" => "^\[url=%{DATA:[data][request_url]}(?:[&?]%{GREEDYDATA:[@metadata][request_query]})?\]$"
    }
}
```

- `[url=`부터 시작해 마지막 `]`까지인 한 줄을 대상으로 합니다.
- 첫 `&` 또는 `?` 앞부분을 `data.request_url`에 저장합니다.
- 뒤의 파라미터 문자열은 `[@metadata][request_query]`에 임시 보관합니다.
- 파라미터 없이 URL만 있는 형태도 허용합니다.

### kv: 파라미터를 필드로 변환

```logstash
if [@metadata][request_query] {
    kv {
        source => "[@metadata][request_query]"
        target => "[data][request_data]"
        field_split => "&"
        value_split => "="
        allow_empty_values => true
        whitespace => "strict"
    }
}
```

| 옵션 | 역할 |
|---|---|
| `source` | grok으로 분리한 파라미터 문자열을 읽음 |
| `target` | 결과를 `data.request_data` 아래에 저장 |
| `field_split => "&"` | 파라미터 항목을 나눔 |
| `value_split => "="` | 각 항목의 이름과 값을 나눔 |
| `allow_empty_values => true` | `KEY=` 같은 빈 값도 보존 |
| `whitespace => "strict"` | 구분자 주변 공백 처리를 엄격하게 하여 빈 값 처리를 지원 |

필드 이름·개수·순서가 달라져도 항목별 grok 패턴을 새로 만들지 않기 위해 kv를 사용합니다. 옵션 의미는 [Elastic kv 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-kv)에 설명돼 있습니다.

결과 예:

```text
data.request_url                  = https://example.com/api
data.request_data.RESULT_CODE     = 0000
data.request_data.RESULT_MSG      = OK
data.request_data.TR_ID           = ABC%2B123%3D
data.request_data.PARTNER_CODE    = TEST
```

요청 값은 URL 디코딩·인코딩하지 않습니다. `message`도 그대로 둡니다. 값에 구분자로 해석되면 안 되는 `&`가 있다면 원본에서 `%26` 등으로 표현돼 있어야 합니다.

현재 파일은 요청 grok 실패 이벤트를 별도로 drop하는 방어는 넣지 않았습니다. 따라서 요청 형식이 바뀌면 `_grokparsefailure`도 점검해야 합니다.

## 6. 그룹 D — 응답 본문 모으기·완성

```text
POST RESPONSE DATA
************************
[{"RESULT_CODE":"0000","RESULT_MSG":"성공","TR_ID":"ABC+123="}  ← 본문 첫 줄
]                                                                       ← 본문 다음 줄
************************                                                ← 완성 판단
```

위 화살표 설명은 실제 로그에 포함되는 문자열이 아닙니다.

1. 제목에서 응답 상태를 기억합니다.
2. 첫 별표 구분선은 지나갑니다.
3. JSON 배열 시작으로 보이는 줄부터 본문을 모읍니다.
4. 다음 줄의 `]`도 본문에 이어 붙입니다.
5. **본문 다음 별표 구분선에서** JSON 한 건을 완성합니다. `]`를 읽는 즉시 출력하는 방식은 아닙니다.

```ruby
map["json"] = [map["json"], m].compact.join("\n")
```

이전 본문과 현재 줄을 개행 문자 하나로 연결합니다. 원문이 한 줄이면 첫 줄을 넣을 때 별도의 중간 개행이 생기지 않습니다.

구분선 처리:

```ruby
elsif m.strip =~ /^\*+$/
    if map["json"]
        event.set("message", map.delete("json"))
        event.set("[@metadata][epay_kind]", map.delete("kind"))
    end
```

- 모아 둔 본문이 없으면 시작 구분선으로 보고 지나갑니다.
- 본문이 있으면 현재 구분선 이벤트의 `message`를 모아 둔 JSON으로 바꿉니다.
- 응답 파싱 표시를 붙이고 기억해 둔 본문·상태를 지웁니다.
- 별도 이벤트를 새로 만드는 것이 아니라 종료 구분선 이벤트를 재사용합니다. 따라서 `log.offset` 등은 본문 시작 줄이 아니라 종료 구분선 이벤트 기준으로 남을 수 있습니다. 업무 발생 시각을 따로 추출하는 설정은 아닙니다.

### 임시 표시와 drop의 관계

`[@metadata][epay_kind]`는 이 이벤트를 요청 파서 또는 응답 파서로 보낼지 알려주는 임시 표시입니다. 파싱 성공 표시가 아니라 **파싱 전 분류 표시**입니다. 일반적인 Elasticsearch 출력에 metadata는 포함되지 않습니다.

제목·구분선·아직 조합 중인 본문 조각은 마지막 `drop {}`에서 개별 저장을 막습니다. 현재 이벤트를 버려도 aggregate의 map은 별도이므로 다음 줄에서 기억을 참조할 수 있습니다.

## 7. 그룹 E — 응답 JSON 파싱·TR_ID 변환

```logstash
json {
    source => "message"
    target => "[data][result_data]"
    tag_on_failure => ["_epay_response_json_failure"]
}
```

완성된 JSON 배열을 `data.result_data`에 저장합니다. `RESULT_CODE`가 반드시 있어야 하는 조건은 없습니다. 다른 키 이름과 중첩 객체도 JSON에 들어 있는 구조대로 파싱합니다. 동작과 실패 태그 옵션은 [Elastic JSON 필터 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-json)를 참고하세요.

```logstash
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
```

- JSON 파싱에 실패하면 해당 이벤트를 저장하지 않습니다. 실패 경고 자체를 숨기는 설정은 아닙니다.
- `[0]`은 배열의 첫 번째 객체입니다. 첨부의 선택된 응답은 모두 객체 한 개짜리 배열이었습니다.
- 첫 번째 객체의 대문자 `TR_ID`만 인코딩합니다. `TID`, 소문자 `tr_ID`, 중첩 객체의 TR_ID는 변경하지 않습니다.
- 예: `ABC+123=` → `ABC%2B123%3D`. 이 방식에서 공백은 `+`로 변환됩니다.
- 암호화가 아니라 URL 표현 변환입니다. 요청과 비교할 수 있게 값을 맞추는 작업입니다.
- 변환된 값은 추출 필드에만 저장합니다. `message` 안의 원래 응답 값은 바꾸지 않습니다.
- 응답이 이미 `%2B` 등으로 인코딩돼 있으면 `%`가 다시 인코딩될 수 있습니다. 현재 코드는 응답 TR_ID가 디코딩된 상태라는 첨부 로그 특성을 전제로 합니다.

### EPayReturnReq 필드가 생기는 이유

첨부 원문의 61,503행 등 실제 `POST RESPONSE DATA` 본문에 `EPayReturnReq` 객체가 있습니다. JSON 파서가 그 내부 항목까지 읽어 다음과 같이 생성합니다.

```text
data.result_data.EPayReturnReq.card_TYPE
data.result_data.EPayReturnReq.card_BIN
data.result_data.EPayReturnReq.card_IMG_URL
```

고정된 4~5개 필드만 추출하는 설정이 아닙니다. 수집 대상 위치의 본문에 필드가 많으면 그만큼 생성됩니다. Kibana 데이터 뷰의 필드 목록은 여러 문서·인덱스의 필드를 함께 보여줄 수 있으므로, 문서 한 건의 필드 수와 구분해야 합니다.

## 8. 그룹 F — 이번 보완에서 추가한 방어

기본 수집 위치·grok·kv·인코딩 방식은 유지했습니다. 보완 전과 다른 부분은 다음입니다.

| 항목 | 보완 전 | 보완 후 |
|---|---|---|
| 응답 시작 | `[`로 시작하는 일반 로그도 받아들일 여지 | 객체 배열 시작, 빈 배열, 단독 `[` 형태부터 시작 |
| 본문 수집 중 일반 로그 | 이미 본문이 있으면 이어 붙일 여지 | 식별 가능한 일반 로그를 만나면 경고 후 상태 초기화 |
| 본문 크기 | 명시적 크기 제한 없음 | 1MiB 초과 시 경고 후 상태 초기화 |
| JSON 실패 | 실패 이벤트가 후속 output으로 갈 여지 | 실패 태그 확인 후 drop |

### 응답 시작 조건

```ruby
m =~ /\A\s*\[\s*(?:\{|\]|\z)/
```

앞쪽 공백을 허용하고 `[{`, `[ {`, `[]`, 단독 `[` 형태를 받습니다. 임의의 모든 JSON 종류를 받는 파서는 아닙니다. 예를 들어 `{...}`만 있는 객체 본문이나 `[1,2]`로 바로 시작하는 숫자 배열은 현재 시작 조건의 대상이 아닙니다.

### 일반 로그 혼입 감지

```ruby
m =~ /\A\s*(?:\d{4}-\d{2}-\d{2}[ T]|\[\s*(?!(?:true|false|null)(?:\s|,|\]))[A-Za-z_]|(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\b|RESULT DATA\z)/
```

행 시작의 날짜, `[필드명…]`, 로그 레벨, `RESULT DATA` 같은 형태를 감지합니다. `true`·`false`·`null` 배열은 정상 JSON 내부에 나올 수 있어 해당 대괄호 감지에서 예외로 둡니다.

모든 일반 로그 형태를 정규식으로 판별하는 것은 아닙니다. 남는 잘못된 본문은 최종 JSON 파서에서 거부할 수 있습니다. 혼입된 응답을 복원하거나 다른 요청과 재매칭하는 기능이 아니라 **잘못된 문서 저장을 막는 방어**입니다.

### 크기 상한

```ruby
if map["json"].bytesize > 1048576
    @logger.warn("Epay response exceeds 1 MiB buffer limit",
                 :path => event.get("[log][file][path]"))
    map.clear
end
```

한 응답의 누적 본문이 1MiB를 넘으면 폐기합니다. 전체 파이프라인 메모리를 1MiB로 제한한다는 뜻은 아닙니다. 첨부 대상 응답의 최대 UTF-8 크기는 2,373바이트였지만, 향후 정상 응답이 커지면 기준을 재검토해야 합니다.

## 9. 검증된 범위와 검증되지 않은 범위

| 첨부 실로그를 순서대로 재현한 검사 | 결과 |
|---|---:|
| 요청 선택·추출 | 1,056건 |
| 응답 선택·JSON 파싱 | 1,049건 |
| 응답 중 한 줄 형태 | 939건 |
| 응답 중 두 줄 형태 | 110건 |
| 정상 대상 grok 상당 처리·JSON 파싱 실패 | 0건 |
| 별도 예외 상황 검사 | 총 34개 통과 |

보완 전·후 모두 정상 실로그의 선택 건수는 같았습니다. 별도 34개는 일반 로그 혼입·다른 파일의 상태 분리·JSON 오류 등을 인위적으로 만든 시험이며 실로그 34건을 뜻하지 않습니다. 버려야 하는 이벤트를 버린 것도 통과입니다.

검증은 Python으로 선택·grok/kv 상당 동작·JSON 조합을 재현하고 실제 Java URLEncoder를 사용한 검사입니다. 실제 Logstash/JRuby에서의 전체 실행 검사나 운영 부하 시험은 아닙니다. 처리 속도·누락 없음·정확히 한 번 수집을 보증하는 결과로 해석하면 안 됩니다.

## 10. 운영 적용 전 확인할 사항

### 순서 유지

```yaml
pipeline.workers: 1
pipeline.ordered: true
```

위 항목은 filter `.conf` 안이 아니라 해당 파이프라인을 정의하는 설정에 적용합니다. aggregate는 worker 1 사용을 요구하며, ordered 설정은 파이프라인 내부의 순서 유지에 관련됩니다. 이미 상류에서 뒤섞이거나 누락된 로그를 복구하지는 않습니다. [aggregate 안내](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-aggregate), [이벤트 순서 안내](https://www.elastic.co/docs/reference/logstash/processing)

- 같은 파일에서 여러 요청·응답 구간이 서로 끼어들면 파일별 기억 하나로 완벽히 구분할 수 없습니다.
- 프로세스 재시작 시 미완료 메모리 상태 복구를 이 설정에서 구성하지 않았습니다.
- 현재 운영 worker 2를 1로 바꾸면 기존 VAN도 같이 영향을 받습니다. 기존 사용률 약 30%만으로 변경 후 안전성을 확정하지 않습니다.
- 별도 신규 파이프라인 분리는 이 파일에 포함되지 않았습니다.

### 적용 체크리스트

- [ ] 실제 파일명·경로가 대상 조건과 일치하는지 확인.
- [ ] `agent.id`, `log.file.path`, 한 줄 단위 `message`가 기대대로 들어오는지 확인.
- [ ] 제목·별표 구분선·본문 순서와 문자 인코딩 확인. 첨부 파일은 CP949로 읽어 검사했으며 입력 인코딩 설정은 변경하지 않았음.
- [ ] 실제 설치된 Logstash·aggregate 버전으로 설정 문법 검사 수행.
- [ ] worker 1·ordered true로 실제 요청·응답 재수집 검사 수행.
- [ ] 기존 VAN도 함께 넣고 지연·처리량·큐 누적·오류 확인.
- [ ] `_grokparsefailure`, `_aggregateexception`, JSON 파싱 경고와 신규 중단·크기 초과 경고 확인. drop된 이벤트의 태그는 색인에서 조회되지 않을 수 있으므로 Logstash 로그도 확인.
- [ ] 시험용 output을 그대로 운영에 배포하지 않는지 확인. 기존 output 구조는 유지했으며, 공개본의 접속 비밀번호만 임시값으로 치환했음.
- [ ] 기존 설정 백업과 되돌리는 절차 준비. 이 문서 제공만으로 운영 반영이 완료된 것은 아님.

## 11. 자주 헷갈리는 부분

**Q. 상태를 기억한 제목 이벤트를 drop하면 기억도 사라지나?**

A. 아닙니다. 이벤트와 aggregate map은 별도입니다. 이벤트를 drop해도 map에 남긴 상태는 다음 이벤트에서 참조합니다.

**Q. JSON 파서만 쓰면 안 되나?**

A. 완성된 JSON 한 건에는 JSON 파서만으로 충분합니다. 현재 추가 처리는 어느 구간의 본문인지 고르고, 여러 이벤트로 나뉜 JSON을 먼저 완성하기 위한 것입니다.

**Q. RESULT DATA 중복은 제외되는데 재전송 중복도 막나?**

A. 아닙니다. 앞의 RESULT DATA와 POST RESPONSE DATA 중 수집 위치를 선택할 뿐입니다. Filebeat 재전송 등으로 같은 구간이 다시 오면 다시 수집될 수 있습니다.

**Q. Kibana에서 정상처리·URL 중간이 내려가 보이는 이유는?**

A. 확인한 사진에서는 화면 자동 줄바꿈이었습니다. JSON 보기의 message에는 중간 개행이 없고 마지막 `}\n]`만 있었습니다. 요청 message에는 이 설정이 개행을 추가하지 않습니다. 응답은 원문의 여러 줄을 합치는 지점에만 개행을 유지합니다.

**Q. 보완 전 설정은 틀린 설정인가?**

A. 첨부 정상 실로그의 순차 재현에서는 처리됐습니다. 보완 후는 예외 방어를 추가한 것입니다. 어느 쪽이든 실제 운영 실행·부하 검증을 거치기 전에는 무조건 안전한 최종 설정이라고 단정하지 않습니다.

