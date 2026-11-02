> 이전 대응 방식의 기록입니다. 현재는 [더 짧은 공통 처리 간소화본](APPLY_SIMPLE_FRONTEND_20261102.md)을 사용합니다.

# CARD 앞단 분기 수정 — 2026-11-02

Ruby/JSON 엔진은 `2026-10-30.final17` 그대로 사용합니다. 이번 수정은 `card.conf`의 앞단 분기 순서와 삼성 로그 헤더 추출입니다.

## 현재 조건의 의미

```logstash
if [message] =~ /\b(?:get|put)(?:_msg_complete)?(?:\(|\[)/ and "linename" in [message] {
```

| 부분 | 의미 |
|---|---|
| `[message] =~ /.../` | message 안에서 이 정규식과 맞는 부분을 찾습니다. |
| `\b` | 단어 경계입니다. 반드시 행의 시작이라는 뜻은 아닙니다. |
| `(?:get\|put)` | get 또는 put입니다. `(?:...)`는 캡처를 저장하지 않는 묶음입니다. |
| `(?:_msg_complete)?` | 바로 뒤의 `_msg_complete`가 없어도, 한 번 있어도 됩니다. |
| `(?:\(\|\[)` | 다음 문자가 여는 소괄호 `(` 또는 여는 대괄호 `[`여야 합니다. |
| `and "linename" in [message]` | 같은 message 어디엔가 소문자 linename이라는 문자열도 있어야 합니다. |

예를 들어 `get(`, `put(`, `get[`, `put[`, `put_msg_complete[`에 linename 문자열까지 있으면 조건은 참입니다. 이것은 if 분기의 진입 조건일 뿐, 해당 표기를 모두 상세 파싱할 수 있다는 보장은 아닙니다. 로그 함수명이 `put_msg_info:`인 것만으로는 매칭하지 않습니다.

이 조건은 `] `, `* `, 정상 길이 접두부, ISO 헤더·비트맵을 확인하지 않으며 필드를 자동 생성하지도 않습니다. linename이라는 글자가 전문 내부나 잘린 버퍼에 남아 있어도 참이 될 수 있습니다.

## 사진 경고의 원인

사진의 `Dissector mapping, pattern not found`와 `_dissectfailure`는 아래 구분 패턴을 적용할 수 없다는 뜻입니다.

```logstash
dissect { mapping => { "message" => "%{a_header}] %{b_body}" } }
```

이 패턴에는 **오른쪽 대괄호와 공백 `] `** 이 실제로 필요합니다. 넓힌 get/put 조건이 삼성 요청을 먼저 받더라도, 그 요청에 이 구분자가 있다는 뜻은 아닙니다. 일반 분기에 들어온 이벤트는 뒤에 있는 삼성용 else-if로 다시 내려가지 않습니다.

Logstash 프로세스 중단을 의미하는 로그는 아닙니다. 해당 이벤트의 앞단 추출 실패이며 이후 라우팅·필드 추출에도 영향을 줄 수 있으므로 경고 수준을 숨기는 대신 경로를 수정합니다. [Elastic Dissect 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-dissect)는 구분 패턴과 실패 태그를 설명합니다.

## 적용 방법

현재 같은 if/else-if 체인의 **첫 번째 분기**에 아래 삼성 전용 처리를 두고, 현재 넓힌 get/put 조건을 `else if`로 바꿉니다. 기존의 뒤쪽 `else if ... put_msg_complete` 블록은 이 위치로 옮깁니다.

```logstash
# Match the outer logger header, not matching text inside an ISO field.
  # Must precede every general get/put/dissect branch.
  if [message] =~ /^\([A-Za-z]\)\s*:[^:\r\n]+:[^:\r\n]+:[^:\r\n]+:[^:\r\n]+:put_msg_complete:[0-9]+:\s*(?:\*\s*)?put_msg_complete\[/ {
    grok {
      id => "card_completed_log_header"
      match => { "message" => "^\([A-Za-z]\)\s*:\s*[^:]+:[^:]+:(?<gateway>[^:]+):" }
    }
    mutate { replace => { "status" => "OUT" } }
  }
  else if [message] =~ /\b(?:get|put)(?:_msg_complete)?(?:\(|\[)/ and "linename" in [message] {
    # 이 안에는 기존 일반 전문용 dissect/grok 처리를 유지합니다.
  }
```

위 코드는 순서 설명용입니다. 첨부 `card.conf`에는 나머지 분기와 Ruby 설정까지 포함돼 있습니다. 별도의 filter 파일을 추가해 기존 dissect 체인까지 둘 다 실행하는 방식으로 적용하지 않습니다. 운영 input/output·라우팅은 기존 환경에 맞게 유지하고 앞단을 교체합니다.

삼성 분기는 바깥 logger 헤더의 함수와 wrapper를 확인한 뒤 원래 message에서 gateway를 추출하고 status를 OUT으로 설정합니다. 전문 데이터 안의 우연한 문자열을 요청 헤더로 선택하지 않도록 헤더 시작에 고정했습니다. 기존 `] ` 또는 `* ` dissect를 거치지 않습니다. 카드사명·금액·일시·linename·행 번호를 고정 예외로 사용하지 않습니다.

## 검증 결과

- 실제 Logstash 8.17.6 / 4 workers에서 수정 전후 276입력을 비교했습니다. trace 5행은 동일하게 제외되고 271건이 출력됐습니다.
- 사진과 같은 두 이벤트는 수정 전 `_dissectfailure`와 `_grokparsefailure`가 생겼고, 수정 후 두 태그가 모두 사라졌으며 gateway와 OUT 값이 추출됐습니다.
- 수정 전후 업무 필드 SHA256, 상태, 프로필, 방향, 오류 코드의 차이는 0건입니다.
- 삼성 원본 113,192행 중 wrapper 없는 56행을 제외한 113,136건 처리: IN/OUT 각각 56,568건, ok 95,967건, fallback 17,169건. dissect/grok 실패 0, gateway·방향 오류 0입니다.
- 전체 제공 소스 1,932,571개 물리 행의 분기 조건을 정적으로 비교했습니다. 새로 유입되거나 제외된 후보 0건, 다른 카드사를 삼성 분기로 보낸 건수 0건입니다. 다른 카드사 전체를 실제 파이프라인으로 재실행한 결과라는 뜻은 아닙니다.
- 로컬 CP949 호환 디코딩 및 실제 Logstash 재현입니다. 운영 Filebeat/Elasticsearch에 직접 접속해 검증한 결과는 아닙니다.

기존 `error`/`fallback` 태그와 앞단 `_dissectfailure`/`_grokparsefailure`는 서로 다른 단계의 결과입니다. Filebeat euc-kr, Ruby/JSON, NH rest 정책, 최소 진단 출력 정책은 유지합니다. 이전 인덱스 문서는 자동으로 수정되지 않으므로 재로딩 뒤 새 이벤트로 확인합니다.
