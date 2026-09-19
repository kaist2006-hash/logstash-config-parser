# frontback.conf 파서 — 1차 검증본

이 묶음은 기존 `frontback.conf`의 수집·인덱스 분기를 유지하면서 `FrontChannelMgr`와 `BackChannelMgr` 거래행에 검증 가능한 공통 상세 필드를 추가합니다. Logstash 8.17.6에서 문법과 실제 이벤트 처리를 확인했으며 Beats·Elasticsearch에는 접속하지 않았습니다.

## 1차 결론

`taps.7z`에는 Front/Back 채널 전체를 정의하는 독립 규격서가 없습니다. 대신 S-OIL 개발요건 XLS 2개에서 두 매니저의 실제 로그 예시와 특정 업무 필드표를 확인했습니다. 제공 로그는 카드사·업무·ASCII ISO8583·binary ISO8583·기타 고정 전문이 섞여 있으므로 특정 문서 하나를 전체 로그에 적용하면 필드가 밀립니다.

따라서 이번 버전은 다음 범위만 활성화합니다.

- 공통 132-byte 채널 헤더
- Front/Back 요청·응답 방향과 endpoint
- transaction/correlation key 및 기존 `nice_number` 일치 여부
- Back 기관 코드와 확인된 카드사 이름 매핑
- route/code/partner/protocol marker
- 내부 전문의 안전한 형식 분류

카드번호·Track2·PIN·내부 본문 원문은 `frontback_detail` 아래에 복제하지 않습니다. 기존 `message` 자체에는 민감정보가 있을 수 있으므로 이 파서는 저장 원문의 마스킹 기능이 아닙니다.

## 구성

| 파일 | 역할 |
|---|---|
| `frontback.conf` | 기존 Beats 8805, alias 분기, ES 출력 구조와 신규 Ruby 호출 |
| `frontback_detail_parser.rb` | 공통 헤더·형식 파서 |
| `frontback_detail_specs.json` | 고정 위치, 기관 매핑, 비활성 내부 후보 |
| `frontback_detail.mapping.json` | 신규 필드의 ES 매핑 참고 본문; 자동 적용하지 않음 |
| `validation/REPORT.md` | 문서 조사 및 실로그 검증 결과 |
| `HANDOFF.md` | 다음 채팅/다음 단계 인수인계 |
| `tests/` | Logstash 8.17.6 Event/JRuby 오프라인 재생 도구 |

## 기존 설정 보존 범위

- Beats port `8805`
- FrontMessage, FrontChannel, BackMessage, BackChannel, JeusServer의 기존 alias
- 기존 Front 응답 root `code` 추출
- `ilm_enabled => false`, `manage_template => false`
- 기존 ECS 필드 제거 목록

추가 파서는 `FrontChannelMgr`와 `BackChannelMgr`에만 실행됩니다. 운영 상태 로그·스택 트레이스·MessageMgr·JeusServer는 변경하지 않습니다. 파싱 실패가 생겨도 이벤트를 drop하지 않습니다.

## 신규 필드

주요 값은 `[frontback_detail]` 아래에 생성됩니다.

| 필드 | 의미 |
|---|---|
| `status` | `ok`, `warning`, `failed` |
| `channel`, `direction` | `front/back`, `request/response` |
| `transaction_id`, `correlation_id` | 채널 공통 식별·상관키 |
| `correlation_match` | 로그 헤더 `nice_number`와 상관키 일치 여부 |
| `institution_code/name` | Back 기관 코드와 확인된 카드사 이름 |
| `route_code`, `code`, `code_role` | 공통 위치의 라우팅·응답/네트워크 코드 |
| `partner_code` | 검증 가능한 파트너 구간 |
| `protocol_marker(_offset)` | Back `ISO` marker와 위치 |
| `inner_kind` | 내부 전문 형식 분류 |

`inner_kind=iso8583_*`는 세부 비트필드 파싱 완료를 뜻하지 않습니다. `custom_or_opaque`도 실패가 아니라 아직 업무별 규격이 연결되지 않은 상태입니다.

## 검증 결과

| 항목 | 결과 |
|---|---:|
| 합성 계약 | 8/8 통과 |
| Front 실거래행 | 992 |
| Back 실거래행 | 24,715 |
| 전체 실거래행 | 25,707 |
| ok / warning / failed | 25,706 / 1 / 0 |
| parser error | 0 |
| message/path 변경 | 0 / 0 |
| correlation 불일치 | 0 |
| 1-worker/4-worker digest | 동일 |

경고 1건은 일반 Front 요청 code `8373` 위치가 공백인 변형입니다. 추정 파싱하지 않고 확인 대상으로 남겼습니다.

## 운영 배치

세 핵심 파일을 같은 디렉터리에 둡니다.

```text
/etc/logstash/frontback/
  frontback_detail_parser.rb
  frontback_detail_specs.json
  frontback.conf
```

필수 환경 또는 Logstash keystore 값을 준비합니다.

```text
FRONTBACK_PARSER_DIR=/etc/logstash/frontback
FRONTBACK_ES_HOST_1=<기존 첫 번째 ES URL>
FRONTBACK_ES_HOST_2=<기존 두 번째 ES URL>
FRONTBACK_ES_HOST_3=<기존 세 번째 ES URL>
FRONTBACK_ES_PASSWORD=<keystore 권장>
FRONTBACK_ES_USER=elastic
FRONTBACK_SOURCE_ENCODING=UTF-8
```

운영 원본의 내부 주소와 평문 비밀번호는 공개 파일에 복사하지 않았습니다. `FRONTBACK_SOURCE_ENCODING`은 수집 단계에서 실제로 생성되는 문자열 인코딩에 맞춰야 합니다. 이번 원시 파일은 CP949로 읽히면서 일부 binary가 섞여 있었고, 로컬 검증은 원바이트 보존을 위해 ISO-8859-1 운반 방식으로 수행했습니다. 공통 132-byte 헤더는 ASCII라 이번 활성 범위는 본문 문자 해석에 의존하지 않습니다.

## 오프라인 재검증

```text
python tests/run_core.py --logstash-home C:/tools/logstash-8.17.6 --report C:/temp/frontback-contracts.json

python tests/run_core.py --logstash-home C:/tools/logstash-8.17.6 --logs-dir C:/samples/frontback --workers 1 --report C:/temp/frontback-w1.json

python tests/run_core.py --logstash-home C:/tools/logstash-8.17.6 --logs-dir C:/samples/frontback --workers 4 --report C:/temp/frontback-w4.json
```

같은 보고서 경로를 덮어쓰지 않도록 도구가 기존 파일이 있으면 중단합니다. 원시 로그는 읽기만 하며 ES나 네트워크를 사용하지 않습니다.

## 다음 상세 파싱 원칙

내부 업무 프로파일은 `institution_code + partner_code + route_code + inner_kind`처럼 충돌하지 않는 selector를 먼저 고정해야 합니다. 그 다음 정확히 대응하는 문서와 요청/응답 표본을 함께 검증합니다. JSON만 수정해도 실행 중인 파서에 즉시 반영되지 않으므로 파이프라인 reload/restart가 필요합니다.

S-OIL 후보는 문서는 있지만 제공 Back 표본이 없어 비활성입니다. 카드사별 ISO8583 상세 파싱은 중단해 둔 `card.conf` 작업과 규격 범위가 겹치므로, 우선순위를 정한 뒤 재사용 가능한 core와 채널 wrapper를 분리해 연결하는 편이 안전합니다.
