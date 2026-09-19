# frontback.conf — NICE 공통 120바이트 헤더 파서

이 묶음은 기존 `frontback.conf`의 수집·인덱스 분기를 유지하면서 `FrontChannelMgr`와 `BackChannelMgr` 거래행의 앞 120바이트 `SYSTEM_HEADER`만 상세 파싱합니다. Logstash 8.17.6에서 설정 문법, 합성 계약, 실제 로그 전체 재생을 검증했습니다. Beats와 Elasticsearch에는 접속하지 않았습니다.

## 구현 선택

고정폭 헤더에는 `dissect`를 사용하지 않습니다. `dissect`는 구분자를 기준으로 필드를 분리하므로 구분자가 없는 120바이트 연속 필드에 적합하지 않습니다.

- `frontback.conf`: 대상 파일 선택과 Ruby 호출, 기존 인덱스 분기
- `frontback_detail_specs.json`: 문서의 12개 필드 offset·length·형식
- `frontback_detail_parser.rb`: `byteslice` 기반 고정폭 파싱과 방어 검증

JSON은 파이프라인 시작 시 한 번만 읽고 동결합니다. 이벤트 처리 중 파일 I/O·네트워크 호출·본문 복사는 없습니다.

## 활성 파싱 범위

| Offset | 길이 | 결과 필드 |
|---:|---:|---|
| 0–3 | 4 | `nice_header.msg_length` |
| 4–7 | 4 | `nice_header.msg_type` |
| 8–11 | 4 | `nice_header.network_response_code` |
| 12–19 | 8 | `nice_header.process_code` |
| 20–37 | 18 | `nice_header.nice_serial_no` |
| 38–89 | 52 | `nice_header.message_correlation_id` |
| 90 | 1 | `nice_header.direction` |
| 91–98 | 8 | `nice_header.transaction_date` |
| 99–104 | 6 | `nice_header.transaction_time` |
| 105–114 | 10 | `nice_header.msg_format_code` |
| 115 | 1 | `nice_header.service_instance_id` |
| 116–119 | 4 | `nice_header.response_code` |

Offset 120 이후는 파싱·분류·복제하지 않습니다. 카드번호·Track2·PIN·업무 본문이 신규 필드에 복제되지 않습니다. 원래 `message`는 변경하거나 삭제하지 않습니다.

Excel의 `DEFAULT_VAL`은 고정 검증값으로 사용하지 않습니다. 실제 Front 로그에는 `direction=F`, 빈 service instance, `8373` 이외의 응답코드가 존재하기 때문입니다. `msg_length`도 길이 산정 범위가 문서에 추가로 정의되기 전까지 로그 문자열의 전체 바이트 수와 비교하지 않습니다.

## 생성 필드

`[frontback_detail]` 아래에 다음 값을 생성합니다.

- `schema_version`, `status`
- `channel`: `front` 또는 `back`
- `flow_direction`: 로그 화살표 기준 `request` 또는 `response`
- `source_endpoint`, `target_endpoint`, `timestamp_text`, `level`
- `header_bytes`: 항상 `120`
- `nice_number_match`: 외부 로그의 `nice_number`와 `nice_serial_no` 일치 여부
- `nice_header.*`: 문서에 정의된 12개 필드
- 이상 시 `warnings`, `errors`

파싱 실패가 발생해도 이벤트는 drop하지 않고 `_frontback_parse_failure` 태그와 오류 코드만 추가합니다. 기존 `[frontback_detail]`이 있으면 덮어쓰지 않습니다.

## 운영 최적화

- 로그 외피는 최대 512바이트까지만 검사합니다.
- 실제 헤더 120바이트만 복사하며 긴 본문 전체를 정규식으로 캡처하지 않습니다.
- 스펙은 `register`에서 한 번 검증·컴파일·동결합니다.
- 120바이트 전체가 누락·중복 없이 정의됐는지 시작 시 검사합니다.
- 최대 이벤트 크기 128KiB 제한으로 비정상 대형 이벤트의 처리 비용을 제한합니다.
- 이벤트별 공유 상태 쓰기와 잠금이 없어 멀티워커에서 결정적으로 동작합니다.
- 비ASCII 헤더, 짧은 헤더, 잘못된 외피는 안전하게 실패 처리하며 원문은 유지합니다.

## 검증 결과

| 항목 | 결과 |
|---|---:|
| Logstash 8.17.6 설정 문법 | 통과 |
| 합성 계약 | 8/8 통과 |
| Back 거래행 | 24,715 |
| Front 거래행 | 992 |
| 합계 | 25,707 |
| ok / warning / failed | 25,707 / 0 / 0 |
| 원본 message/path 변경 | 0 / 0 |
| `nice_number` 불일치 | 0 |
| 1-worker/4-worker 결과 digest | 동일 |

필드별 분포와 마스킹된 대표 결과는 `validation/HEADER_VALUES.md`, 상세 검증은 `validation/REPORT.md`를 봅니다.

## 운영 배치

```text
/etc/logstash/frontback/
  frontback.conf
  frontback_detail_parser.rb
  frontback_detail_specs.json
```

필수 환경 또는 Logstash keystore 값을 준비합니다.

```text
FRONTBACK_PARSER_DIR=/etc/logstash/frontback
FRONTBACK_ES_HOST_1=<기존 첫 번째 ES URL>
FRONTBACK_ES_HOST_2=<기존 두 번째 ES URL>
FRONTBACK_ES_HOST_3=<기존 세 번째 ES URL>
FRONTBACK_ES_USER=elastic
FRONTBACK_ES_PASSWORD=<Logstash keystore 권장>
```

`manage_template => false`를 유지하므로 운영 적용 전에 `frontback_detail.mapping.json`의 필드를 기존 인덱스 템플릿에 병합해야 합니다. 이 단계 없이 동적 매핑에 의존하면 날짜처럼 보이는 문자열의 타입이 환경별로 달라질 수 있습니다.

## 오프라인 재검증

```text
python tests/run_core.py --logstash-home C:/tools/logstash-8.17.6 --report C:/temp/frontback-contracts.json

python tests/run_core.py --logstash-home C:/tools/logstash-8.17.6 --logs-dir C:/samples/frontback --workers 1 --report C:/temp/frontback-w1.json

python tests/run_core.py --logstash-home C:/tools/logstash-8.17.6 --logs-dir C:/samples/frontback --workers 4 --report C:/temp/frontback-w4.json
```

JSON이나 Ruby를 변경하면 pipeline reload/restart가 필요합니다.
