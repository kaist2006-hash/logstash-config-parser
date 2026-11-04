# 롯데 IC 필드 참고 — FINAL19

근거: 롯데카드_VAN IC 전문_20260721.xls / 승인전문. gateway: GILTC_X25A_P01. MS gateway GCLTC_X25A_P01과 별도로 선택합니다.

헤더는 0 또는 User Area 9바이트 뒤에 있으며 MTI 2바이트 BCD, 비트맵은 최대 3단입니다. 고정 위치 한 번으로 바디를 자르지 않고 비트맵 순서와 각 가변 길이를 따라갑니다.

| DE | 형식 | 출력 필드 |
| ---: | --- | --- |
| 3 | 3 bytes | `processing_code` |
| 4 | 6 bytes | `transaction_amount` |
| 7 | 5 bytes | `transmission_datetime` |
| 11 | 3 bytes | `trace_number` |
| 12 | 3 bytes | `local_time` |
| 13 | 2 bytes | `local_date` |
| 18 | 2 bytes | `merchant_type` |
| 19 | 2 bytes | `acquirer_country` |
| 22 | 2 bytes | `pos_entry_mode` |
| 23 | 2 bytes | `card_sequence` |
| 25 | 1 bytes | `pos_condition` |
| 32 | 가변 binary / digits / 최대 6 | `acquirer_code` |
| 37 | 12 bytes | `retrieval_reference` |
| 39 | 2 bytes | `response_code` |
| 42 | 15 bytes | `merchant_number` |
| 48 | 가변 binary / bytes / 최대 4 | `merchant_fee_rate_raw` |
| 49 | 2 bytes | `currency_code` |
| 55 | 가변 binary / bytes / 최대 255 | EMV 허용 태그 |
| 70 | 2 bytes | `network_code` |
| 90 | 21 bytes | `original_mti`, `original_trace`, `original_date`, `original_approval_number` |
| 118 | 가변 binary / bytes / 최대 255 | `domestic_country`, `installment_months`, `approval_number`, `domestic_merchant_number`, `business_id`, `terminal_id`, `tax_amount`, `service_charge`, `cardholder_fee_indicator`, `merchant_fee_indicator`, `dcc_currency_code`, `dcc_conversion_rate_raw`, `dcc_conversion_rate_scale`, `dcc_transaction_amount`, `transaction_identifier`, `approved_card_type`, `fallback_reason`, `ic_transaction_reference`, `fuel_type`, `fuel_volume_raw`, `fuel_unit_price_raw`, `new_terminal_indicator` |

DE118은 문서의 국가코드 2바이트 뒤 할부 2, 승인번호 8, 국내 가맹점번호 15, 사업자번호 12, 단말기번호 12, 세금 12, 봉사료 12 등 순서로 읽습니다. 출력할 때 카드번호·Track2·주민번호·PIN은 포함하지 않습니다.

DE35 평문 길이는 BCD 자릿수로, 문서의 암호화 길이 48은 바이트수로 처리합니다. 해당 내용 자체는 출력하지 않습니다. DE48은 문서의 ASCII 04 길이부와 실로그의 binary 4 길이부를 구분해 뒤 필드 위치를 보존합니다.

fallback에서는 DE49 이하 등 기존 공통 보관 규칙에 맞는 확인된 값만 남기므로 위 상세 필드 전체가 나오지는 않습니다. 구형/상이한 헤더만 확인한 fallback에는 업무 필드를 만들지 않을 수 있습니다.
