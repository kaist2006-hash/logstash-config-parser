> 이전 대응 방식의 기록입니다. 현재는 [실제 헤더·바디 경계를 수정한 적용본](APPLY_HEADER_BODY_20261102.md)을 사용합니다.

# CARD 앞단 공통 처리 간소화 — 2026-11-02

버전: frontend `2026-11-02.simple`, Ruby/JSON `2026-10-30.final17` 유지.

별도 삼성 전용 분기와 긴 헤더 판별 조건을 제거했습니다. 기존 get/put 공통 조건에서 필요한 구분자가 실제로 있는 경우에만 dissect를 수행하고, gateway/status는 원본 message에서 Grok 한 번으로 추출합니다.

## 실제 앞단 코드

```logstash
# Shared text handling: separate only legacy envelopes with a real delimiter.
  if [message] =~ /\b(?:get|put)(?:_msg_complete)?(?:\(|\[)/ {
    if [message] =~ /(get|put)\(/ {
      if "linename" in [message] and "] " in [message] {
        dissect { mapping => { "message" => "%{a_header}] %{b_body}" } }
      }
      else if "* " in [message] {
        dissect { mapping => { "message" => "%{a_header}* %{b_body}" } }
      }
    }
    grok {
      id => "card_text_header"
      match => { "message" => "^\([A-Za-z]\)\s*:\s*[^:]+:[^:]+:(?<gateway>[^:]+):[^:]+:(?<status>get|put)" }
    }
    mutate { gsub => [ "b_body", "^get", "IN", "b_body", "^put", "OUT", "status", "^get", "IN", "status", "^put", "OUT" ] }
  }
```

이후 hex 분기, drop, 카드사 라우팅, Ruby 및 운영 input/output은 기존 구성대로 이어집니다. 첨부 card.conf는 전체 참고본입니다. 운영의 input/output·라우팅을 덮어쓰지 말고 기존 텍스트 처리 분기를 위 공통 블록으로 교체합니다. 이전 삼성 전용 분기는 함께 제거합니다. 별도 filter 파일을 추가해 두 체인을 동시에 실행하지 않습니다.

## 바뀐 부분

1. 첫 조건은 기존의 넓은 get/put 정규식입니다. linename 조건은 바깥에서 제거하고 dissect 선택 조건 안으로 옮겼습니다. linename 없는 요청도 헤더와 방향을 읽습니다.
2. 기존 `get(`/`put(` 형식에서만 legacy dissect를 사용합니다. `linename`이 있고 `] ` 구분자도 있으면 기존 첫 패턴, 그렇지 않고 `* ` 구분자가 있으면 기존 두 번째 패턴을 사용합니다. 둘 다 없으면 억지로 dissect하지 않습니다.
3. `put_msg_complete[`는 위 legacy `get(`/`put(` 조건에 해당하지 않으므로, 별도 긴 삼성 조건 없이 바로 공통 Grok로 갑니다.
4. Grok 대상을 `a_header`에서 `message`로 바꿨습니다. dissect를 생략한 이벤트에도 gateway/status를 추출할 수 있습니다. 조건만 추가하면서 Grok가 계속 a_header를 읽으면 다시 추출 실패가 발생할 수 있습니다.
5. 중복된 텍스트 Grok·mutate를 공통 처리 한 벌로 합쳤습니다. 기존 `a_header`/`b_body`가 생성되던 정상 legacy 로그의 값은 유지합니다. 상태는 get→IN, put→OUT입니다.

첫 정규식은 분기 진입 여부를 판단합니다. `get[`, `put[` 같은 표기도 조건에는 맞을 수 있지만, 제공되지 않은 새 전문 형식까지 Ruby 상세 파싱이 검증됐다는 뜻은 아닙니다. 실제 바이트 해석과 ok/fallback/error 판정은 기존 FINAL17 Ruby/JSON이 담당합니다.

## 검증

- 실제 Logstash 8.17.6, 4 workers에서 990개 입력을 전후 비교했습니다. 양쪽 모두 984개 출력, trace/비-wrapper 입력 6개 제외입니다.
- 16개 프로필 표본에서 업무 필드·EMV·rest·message 해시, 프로필·상태·방향, gateway 및 기존 a_header/b_body 차이 0건입니다.
- 태그 변화는 가짜 심각 절단/잘못된 공통 데이터 2개 합성 사례의 불필요한 `_dissectfailure`만 제거된 것입니다. 해당 사례의 `_grokparsefailure`와 `error` 판정은 유지합니다. 실제 로그의 실패 태그를 일괄 지우지 않습니다.
- 삼성 원본 113,192행 → 실제 wrapper 113,136건 처리. IN/OUT 각각 56,568건, ok 95,967건, fallback 17,169건입니다. wrapper 없는 조각 56행 제외입니다.
- 삼성 전체에서 dissect/grok/mutate 실패, gateway·방향 오류는 모두 0건입니다. 업무 필드별 출력 건수는 기존 FINAL17과 일치합니다.
- 삼성 외 전체 소스의 텍스트 헤더 정규식을 정적으로 비교했으며, 기존에 읽던 gateway/status를 잃거나 바꾼 건수는 0입니다. 다른 카드사 전체를 실제 파이프라인으로 다시 실행했다고 주장하지 않습니다.
- 긴 삼성 전용 판별 정규식과 중복 Grok를 줄였지만 운영 TPS 향상 수치를 측정한 것은 아닙니다. Filebeat euc-kr은 유지합니다.

운영 Filebeat/Elasticsearch 직접 접속 검증은 아닙니다. 로컬 CP949 호환 디코딩 및 실제 Logstash 검증입니다. 이전 인덱스 문서는 자동 변경되지 않으므로, 적용 후 새로 들어오는 이벤트로 확인합니다.
