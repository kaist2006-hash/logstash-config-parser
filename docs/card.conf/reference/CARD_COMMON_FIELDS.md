# Card common output fields

## 목적

카드사별 MS/IC/통합 전문의 물리 규격은 그대로 유지하면서, 의미가 같은 업무 필드는 카드사와 전문 종류에 관계없이 동일한 Elasticsearch 필드 경로로 제공한다.

기존 Ruby parser의 `[card_detail][fields]`는 호환성을 위해 유지하고 `card.conf`에서 아래 표준 경로로 `copy`한다. 따라서 기존 실로그 검증의 bitmap/offset/length/frame 판정에는 영향을 주지 않는다.

## BGF와 동일 의미로 통일한 필드

| BGF 공통 필드 | 카드 공통 필드 | 카드 parser 원본 | 비고 |
|---|---|---|---|
| `parser_type` | `[card_detail][parser_type]` | 고정값 `card_iso8583` | parser 종류 |
| `format` | `[card_detail][format]` | `[card_detail][profile]` | `kb_ic`, `lotte_ms` 등 |
| `message_length` | `[card_detail][message_length]` | `[card_detail][payload_bytes]` | integer |
| `cat_id` | `[card_detail][cat_id]` | `terminal_id` | 존재하는 전문에서만 |
| `direction` | `[card_detail][direction]` | parser envelope 판정 | S/put=OUT, R/get=IN |
| `response_code` | `[card_detail][response_code]` | `response_code` | 응답 전문에서 주로 존재 |
| `detail.transaction_amount` | `[card_detail][detail][transaction_amount]` | `amount` | integer |
| `detail.installment_months` | `[card_detail][detail][installment_months]` | `installments` | integer |
| `detail.tax_amount` | `[card_detail][detail][tax_amount]` | `tax_amount` | integer |
| `detail.service_charge` | `[card_detail][detail][service_charge]` | `service_amount` | integer |
| `detail.approval_number` | `[card_detail][detail][approval_number]` | `approval_code` | 승인번호 |
| `detail.merchant_number` | `[card_detail][detail][merchant_number]` | `merchant_id` | 가맹점번호 |
| `detail.issuer_name` | `[card_detail][detail][issuer_name]` | profile issuer | 국민/롯데/... |
| `detail.acquirer_code` | `[card_detail][detail][acquirer_code]` | `acquirer_id` | 존재하는 전문에서만 |
| `detail.original_approval_number` | `[card_detail][detail][original_approval_number]` | `original_approval_code` | 취소/원거래 정보 |

## BGF 이름으로 강제 통합하지 않은 필드

다음은 이름이 비슷해도 의미가 동일하다고 단정할 수 없어 카드 ISO8583 공통 영역으로 유지한다.

- `processing_code` → `[card_detail][iso8583][processing_code]`
- `trace_number` → `[card_detail][iso8583][trace_number]`
- `retrieval_reference` → `[card_detail][iso8583][retrieval_reference]`
- `pos_entry_mode` → `[card_detail][iso8583][pos_entry_mode]`
- `pos_condition` → `[card_detail][iso8583][pos_condition]`
- `currency_code` → `[card_detail][iso8583][currency_code]`
- `network_code` → `[card_detail][iso8583][network_code]`
- `local_date`, `local_time`, `transmission_datetime` → `[card_detail][iso8583][...]`

특히 `processing_code`를 BGF의 `trade_code`로, ISO8583 F37을 BGF의 `transaction_unique_number`로 강제 매핑하지 않는다. 서로 유사해 보여도 업무 의미가 완전히 같다고 현재 제공 문서만으로 확정할 수 없기 때문이다.

## 카드 공통 확장 필드

- 정산금액: `[card_detail][detail][settlement_amount]`
- 청구금액: `[card_detail][detail][billing_amount]`
- 포인트잔액: `[card_detail][detail][point_balance]`
- 사업자번호: `[card_detail][detail][business_id]`
- 국내가맹점번호: `[card_detail][detail][domestic_merchant_number]`
- 보증금구분/금액: `[card_detail][detail][deposit_sale_type]`, `[card_detail][detail][deposit_amount]`
- 단말정보: `[card_detail][terminal][...]`
- EMV TLV: `[card_detail][emv][...]`

## 운영 원칙

1. 카드사별 wire/layout 차이는 JSON profile에서 유지한다.
2. 공통 필드명은 `card.conf` 출력 정규화 단계에서 통일한다.
3. 기존 `[card_detail][fields]`는 초기 운영에서 삭제하지 않는다. 대시보드/쿼리 전환 후 제거 여부를 결정한다.
4. 실로그가 없는 profile은 문서 규격 설정은 존재하지만 기본 활성화하지 않는다.
5. 실제 Logstash 배포 전 `--config.test_and_exit`와 샘플/실로그 replay를 통과해야 운영 승인으로 간주한다.
