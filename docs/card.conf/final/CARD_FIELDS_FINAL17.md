# 카드사별 출력 필드 및 실로그 관측표 — FINAL17

값은 해당 카드사·IC/MS의 독립된 정의에서 추출합니다. 표의 길이는 값의 고정 여부가 아니라 규격의 바이트/숫자 단위입니다. 가변 필드는 실제 접두값으로 위치를 계산합니다.

출력 건수는 ok의 공통·상세 값과 fallback의 검증된 공통 값입니다. error에는 업무 값을 출력하지 않습니다. 0건은 미관측이며 검증 완료라는 뜻이 아닙니다. Ruby 출력 값은 문자열입니다.

## 비씨카드 IC/통합 — bcc_ic

후보 56,134건. ok 48,892, fallback 0, error 42, control 7,200.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 3 bytes | 예 | 48,892 | 48,892 |
| 4 | `transaction_amount` | 8 bytes | 예 | 48,892 | 48,892 |
| 7 | `transmission_datetime` | 5 bytes | 예 | 48,892 | 48,892 |
| 11 | `trace_number` | 3 bytes | 예 | 48,892 | 48,892 |
| 12 | `local_time` | 3 bytes | 예 | 48,892 | 48,892 |
| 13 | `local_date` | 2 bytes | 예 | 48,892 | 48,892 |
| 18 | `merchant_type` | 2 bytes | 예 | 21,793 | 21,793 |
| 19 | `acquirer_country` | 2 bytes | 예 | 21,793 | 21,793 |
| 22 | `pos_entry_mode` | 2 bytes | 예 | 46,230 | 46,230 |
| 23 | `card_sequence` | 2 bytes | 예 | 14,238 | 14,238 |
| 25 | `pos_condition` | 1 bytes | 예 | 24,446 | 24,446 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 48,892 | 48,892 |
| 39 | `response_code` | 2 bytes | 예 | 27,099 | 27,099 |
| 42 | `merchant_number` | 15 bytes | 예 | 48,892 | 48,892 |
| 49 | `currency_code` | 2 bytes | 예 | 24,446 | 24,446 |
| 118 | `installment_months` | ascii3, 최대 999 bytes, 하위 offset 0 / 2 | 아니오 | 48,892 | 48,892 |
| 118 | `approval_number` | ascii3, 최대 999 bytes, 하위 offset 2 / 8 | 아니오 | 48,892 | 26,820 |
| 118 | `business_id` | ascii3, 최대 999 bytes, 하위 offset 10 / 12 | 아니오 | 48,892 | 46,225 |
| 118 | `terminal_id` | ascii3, 최대 999 bytes, 하위 offset 22 / 16 | 아니오 | 48,892 | 48,823 |
| 118 | `tax_amount` | ascii3, 최대 999 bytes, 하위 offset 53 / 15 | 아니오 | 48,892 | 48,892 |
| 118 | `service_charge` | ascii3, 최대 999 bytes, 하위 offset 68 / 15 | 아니오 | 48,892 | 48,892 |

## 비씨카드 MS(구형 고정전문) — bcc_ms

후보 13,456건. ok 5,776, fallback 0, error 0, control 7,680.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| — | 내부 업무 필드 규격 미제공 | 레코드 표식·길이 검증 | 메타 정보만 | — | — |

## 국민카드 IC — kb_ic

후보 302,191건. ok 302,189, fallback 2, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 3 bytes | 예 | 302,191 | 302,191 |
| 4 | `transaction_amount` | 6 bytes | 예 | 302,191 | 302,191 |
| 5 | `point_balance` | 6 bytes | 예 | 4 | 4 |
| 7 | `transmission_datetime` | 5 bytes | 예 | 302,191 | 302,191 |
| 11 | `trace_number` | 3 bytes | 예 | 302,191 | 302,191 |
| 12 | `local_time` | 3 bytes | 예 | 0 | 0 |
| 13 | `local_date` | 2 bytes | 예 | 0 | 0 |
| 18 | `merchant_type` | 2 bytes | 예 | 150,135 | 150,135 |
| 19 | `acquirer_country` | 2 bytes | 예 | 150,135 | 150,135 |
| 22 | `pos_entry_mode` | 2 bytes | 예 | 302,191 | 302,191 |
| 23 | `card_sequence` | 2 bytes | 예 | 302,191 | 302,191 |
| 25 | `pos_condition` | 1 bytes | 예 | 302,191 | 302,191 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 302,191 | 302,191 |
| 39 | `response_code` | 2 bytes | 예 | 152,054 | 152,054 |
| 42 | `merchant_number` | 15 bytes | 예 | 302,191 | 302,191 |
| 49 | `currency_code` | 2 bytes | 예 | 302,187 | 302,187 |
| 61 | `fallback_reason` | 2 bytes, 하위 offset 0 / 2 | 아니오 | 150,135 | 0 |
| 61 | `encrypted_card_transport` | 1 bytes, 하위 offset 2 / 1 | 아니오 | 150,135 | 149,984 |
| 61 | `terminal_software_model` | 16 bytes, 하위 offset 3 / 16 | 아니오 | 150,135 | 150,135 |
| 61 | `terminal_reader_model` | 16 bytes, 하위 offset 19 / 16 | 아니오 | 150,135 | 150,135 |
| 70 | `network_code` | 2 bytes | 예 | 0 | 0 |
| 90 | `original_mti` | 2 bytes, 하위 offset 0 / 2 | 아니오 | 963 | 963 |
| 90 | `original_trace` | 3 bytes, 하위 offset 2 / 3 | 아니오 | 963 | 963 |
| 90 | `original_date` | 3 bytes, 하위 offset 5 / 3 | 아니오 | 963 | 963 |
| 90 | `original_approval_number` | 8 bytes, 하위 offset 10 / 8 | 아니오 | 963 | 963 |
| 118 | `domestic_country` | binary, 최대 255 bytes, 하위 offset 0 / 2 | 아니오 | 302,189 | 302,189 |
| 118 | `installment_months` | binary, 최대 255 bytes, 하위 offset 2 / 2 | 아니오 | 302,189 | 302,189 |
| 118 | `domestic_merchant_number` | binary, 최대 255 bytes, 하위 offset 4 / 15 | 아니오 | 302,189 | 302,189 |
| 118 | `approval_number` | binary, 최대 255 bytes, 하위 offset 19 / 8 | 아니오 | 302,189 | 150,468 |
| 118 | `business_id` | binary, 최대 255 bytes, 하위 offset 27 / 15 | 아니오 | 302,189 | 302,189 |
| 118 | `terminal_id` | binary, 최대 255 bytes, 하위 offset 42 / 10 | 아니오 | 302,189 | 302,189 |
| 118 | `tax_amount` | binary, 최대 255 bytes, 하위 offset 52 / 12 | 아니오 | 302,189 | 302,189 |
| 118 | `service_charge` | binary, 최대 255 bytes, 하위 offset 64 / 12 | 아니오 | 302,189 | 302,189 |

## 국민카드 MS — kb_ms

후보 71,302건. ok 49,637, fallback 21,659, error 6, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 71,296 | 71,296 |
| 4 | `transaction_amount` | 12 bytes | 예 | 71,296 | 71,296 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 71,296 | 71,296 |
| 12 | `local_time` | 6 bytes | 예 | 65,316 | 65,316 |
| 13 | `local_date` | 4 bytes | 예 | 65,316 | 65,316 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 29,668 | 29,668 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 51,964 | 51,964 |
| 39 | `response_code` | 2 bytes | 예 | 22,296 | 22,296 |
| 42 | `merchant_number` | 15 bytes | 예 | 51,964 | 51,964 |
| 49 | `currency_code` | 3 bytes | 예 | 51,960 | 51,960 |
| 55 | `installment_months` | ascii3, 최대 2 bytes | 아니오 | 49,637 | 49,637 |
| 56 | `approval_number` | ascii3, 최대 8 bytes | 아니오 | 17,166 | 16,226 |

## 롯데카드 MS — lotte_ms

후보 51,771건. ok 44,145, fallback 7,621, error 5, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 51,646 | 51,646 |
| 4 | `transaction_amount` | 12 bytes | 예 | 51,646 | 51,646 |
| 5 | `settlement_amount` | 12 bytes | 예 | 51,646 | 51,646 |
| 6 | `billing_amount` | 12 bytes | 예 | 51,646 | 51,646 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 51,766 | 51,766 |
| 11 | `trace_number` | 6 bytes | 예 | 51,766 | 51,766 |
| 12 | `local_time` | 6 bytes | 예 | 51,646 | 51,646 |
| 13 | `local_date` | 4 bytes | 예 | 51,646 | 51,646 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 51,646 | 51,646 |
| 32 | `acquirer_code` | 6 bytes, 하위 offset 2 / 6 | 예 | 51,646 | 51,646 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 49,024 | 49,024 |
| 39 | `response_code` | 2 bytes | 예 | 25,736 | 25,736 |
| 41 | `terminal_id` | 16 bytes | 예 | 49,024 | 49,024 |
| 42 | `merchant_number` | 15 bytes | 예 | 49,024 | 49,024 |
| 43 | `business_id` | 10 bytes, 하위 offset 0 / 10 | 예 | 49,024 | 49,024 |
| 48 | `merchant_fee_rate_raw` | ascii2, 최대 4 bytes | 예 | 23,128 | 23,128 |
| 49 | `currency_code` | 3 bytes | 예 | 49,021 | 49,021 |
| 55 | `installment_months` | ascii3, 최대 2 bytes | 아니오 | 44,031 | 44,031 |
| 56 | `approval_number` | ascii3, 최대 8 bytes | 아니오 | 23,201 | 22,781 |
| 57 | `deposit_sale_type` | ascii3, 최대 16 bytes, 하위 offset 0 / 2 | 아니오 | 20,830 | 3 |
| 57 | `deposit_amount` | ascii3, 최대 16 bytes, 하위 offset 2 / 14 | 아니오 | 20,830 | 3 |
| 70 | `network_code` | 3 bytes | 예 | 120 | 120 |

## 롯데카드 IC — lotte_ic

후보 12,104건. ok 10,091, fallback 2,013, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 12,104 | 12,104 |
| 4 | `transaction_amount` | 12 bytes | 예 | 12,104 | 12,104 |
| 5 | `settlement_amount` | 12 bytes | 예 | 12,104 | 12,104 |
| 6 | `billing_amount` | 12 bytes | 예 | 12,104 | 12,104 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 12,104 | 12,104 |
| 11 | `trace_number` | 6 bytes | 예 | 12,104 | 12,104 |
| 12 | `local_time` | 6 bytes | 예 | 12,104 | 12,104 |
| 13 | `local_date` | 4 bytes | 예 | 12,104 | 12,104 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 12,104 | 12,104 |
| 32 | `acquirer_code` | 6 bytes, 하위 offset 2 / 6 | 예 | 12,104 | 12,104 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 11,020 | 11,020 |
| 39 | `response_code` | 2 bytes | 예 | 5,794 | 5,794 |
| 41 | `terminal_id` | 16 bytes | 예 | 11,020 | 11,020 |
| 42 | `merchant_number` | 15 bytes | 예 | 11,020 | 11,020 |
| 43 | `business_id` | 10 bytes, 하위 offset 0 / 10 | 예 | 11,020 | 11,020 |
| 48 | `merchant_fee_rate_raw` | ascii2, 최대 4 bytes | 예 | 4,964 | 4,964 |
| 49 | `currency_code` | 3 bytes | 예 | 11,018 | 11,018 |
| 55 | `installment_months` | ascii3, 최대 2 bytes | 아니오 | 10,091 | 10,091 |
| 56 | `approval_number` | ascii3, 최대 8 bytes | 아니오 | 4,968 | 4,781 |
| 57 | `deposit_sale_type` | ascii3, 최대 16 bytes, 하위 offset 0 / 2 | 아니오 | 5,123 | 0 |
| 57 | `deposit_amount` | ascii3, 최대 16 bytes, 하위 offset 2 / 14 | 아니오 | 5,123 | 0 |
| 70 | `network_code` | 3 bytes | 예 | 0 | 0 |

## 농협카드 MS — nh_ms

후보 10,296건. ok 9,720, fallback 576, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 10,110 | 10,110 |
| 4 | `transaction_amount` | 12 bytes | 예 | 10,110 | 10,110 |
| 7 | `transmission_datetime` | 14 bytes | 예 | 10,296 | 10,296 |
| 11 | `trace_number` | 6 bytes | 예 | 10,296 | 10,296 |
| 12 | `local_time` | 6 bytes | 예 | 10,110 | 9,406 |
| 13 | `local_date` | 8 bytes | 예 | 10,110 | 9,406 |
| 18 | `merchant_type` | 4 bytes | 예 | 10,110 | 10,109 |
| 19 | `acquirer_country` | 3 bytes | 예 | 10,110 | 9,406 |
| 22 | `pos_entry_mode` | 4 bytes | 예 | 10,110 | 10,110 |
| 23 | `card_sequence` | 3 bytes | 예 | 10,110 | 0 |
| 25 | `pos_condition` | 2 bytes | 예 | 10,110 | 10,110 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 10,110 | 10,110 |
| 38 | `approval_number` | 8 bytes | 예 | 10,110 | 3,999 |
| 39 | `response_code` | 2 bytes | 예 | 10,110 | 4,778 |
| 41 | `terminal_id` | 12 bytes | 예 | 10,110 | 591 |
| 42 | `merchant_number` | 15 bytes | 예 | 10,110 | 10,110 |
| 49 | `currency_code` | 3 bytes | 예 | 10,110 | 9,406 |
| 70 | `network_code` | 3 bytes | 예 | 186 | 186 |
| 118 | `installment_months` | ascii3, 최대 111 bytes, 하위 offset 0 / 2 | 아니오 | 9,720 | 9,720 |
| 118 | `business_id` | ascii3, 최대 111 bytes, 하위 offset 2 / 10 | 아니오 | 9,720 | 9,720 |
| 118 | `tax_amount` | ascii3, 최대 111 bytes, 하위 offset 12 / 12 | 아니오 | 9,720 | 9,720 |
| 118 | `service_charge` | ascii3, 최대 111 bytes, 하위 offset 24 / 12 | 아니오 | 9,720 | 9,720 |
| 118 | `pg_business_id` | ascii3, 최대 111 bytes, 하위 offset 37 / 10 | 아니오 | 9,720 | 8,694 |

## 농협카드 IC — nh_ic

후보 111,352건. ok 98,855, fallback 12,497, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 111,228 | 111,228 |
| 4 | `transaction_amount` | 12 bytes | 예 | 111,228 | 111,228 |
| 7 | `transmission_datetime` | 14 bytes | 예 | 111,352 | 111,352 |
| 11 | `trace_number` | 6 bytes | 예 | 111,352 | 111,352 |
| 12 | `local_time` | 6 bytes | 예 | 111,228 | 110,811 |
| 13 | `local_date` | 8 bytes | 예 | 111,228 | 110,811 |
| 18 | `merchant_type` | 4 bytes | 예 | 111,228 | 111,227 |
| 19 | `acquirer_country` | 3 bytes | 예 | 111,228 | 110,811 |
| 22 | `pos_entry_mode` | 4 bytes | 예 | 111,228 | 111,228 |
| 23 | `card_sequence` | 3 bytes | 예 | 111,228 | 111,228 |
| 25 | `pos_condition` | 2 bytes | 예 | 111,228 | 111,228 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 111,352 | 111,352 |
| 38 | `approval_number` | 8 bytes | 예 | 111,228 | 55,207 |
| 39 | `response_code` | 2 bytes | 예 | 111,352 | 56,036 |
| 41 | `terminal_id` | 12 bytes | 예 | 111,228 | 72,504 |
| 42 | `merchant_number` | 15 bytes | 예 | 111,228 | 111,228 |
| 49 | `currency_code` | 3 bytes | 예 | 111,226 | 110,809 |
| 70 | `network_code` | 3 bytes | 예 | 124 | 124 |
| 118 | `installment_months` | ascii3, 최대 111 bytes, 하위 offset 0 / 2 | 아니오 | 98,739 | 98,739 |
| 118 | `business_id` | ascii3, 최대 111 bytes, 하위 offset 2 / 10 | 아니오 | 98,739 | 98,739 |
| 118 | `tax_amount` | ascii3, 최대 111 bytes, 하위 offset 12 / 12 | 아니오 | 98,739 | 98,739 |
| 118 | `service_charge` | ascii3, 최대 111 bytes, 하위 offset 24 / 12 | 아니오 | 98,739 | 98,739 |
| 118 | `pg_business_id` | ascii3, 최대 111 bytes, 하위 offset 37 / 10 | 아니오 | 98,739 | 2,088 |

## 삼성카드 MS — samsung_ms

후보 113,192건. ok 95,967, fallback 17,169, error 56, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 112,648 | 112,648 |
| 4 | `transaction_amount` | 12 bytes | 예 | 112,648 | 112,648 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 113,136 | 113,136 |
| 11 | `trace_number` | 6 bytes | 예 | 3,702 | 3,702 |
| 12 | `local_time` | 6 bytes | 예 | 57,931 | 57,931 |
| 13 | `local_date` | 4 bytes | 예 | 57,931 | 57,931 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 97,167 | 97,167 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 105,656 | 105,656 |
| 39 | `response_code` | 2 bytes | 예 | 56,514 | 56,514 |
| 42 | `merchant_number` | 15 bytes | 예 | 105,656 | 105,656 |
| 49 | `currency_code` | 3 bytes | 예 | 93,988 | 93,988 |
| 55 | `installment_months` | ascii3, 최대 2 bytes | 아니오 | 84,917 | 84,917 |
| 56 | `approval_number` | ascii3, 최대 8 bytes | 아니오 | 48,884 | 47,751 |
| 70 | `network_code` | 3 bytes | 예 | 488 | 488 |

## 삼성카드 IC — samsung_ic

후보 3,826건. ok 3,826, fallback 0, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 3 bytes | 예 | 3,826 | 3,826 |
| 4 | `transaction_amount` | 6 bytes | 예 | 3,826 | 3,826 |
| 7 | `transmission_datetime` | 5 bytes | 예 | 3,826 | 3,826 |
| 11 | `trace_number` | 3 bytes | 예 | 3,826 | 3,826 |
| 12 | `local_time` | 3 bytes | 예 | 1,913 | 1,913 |
| 13 | `local_date` | 2 bytes | 예 | 1,913 | 1,913 |
| 18 | `merchant_type` | 2 bytes | 예 | 3,796 | 3,796 |
| 19 | `acquirer_country` | 2 bytes | 예 | 3,796 | 3,796 |
| 22 | `pos_entry_mode` | 2 bytes | 예 | 3,826 | 3,826 |
| 23 | `card_sequence` | 2 bytes | 예 | 3,826 | 3,826 |
| 25 | `pos_condition` | 1 bytes | 예 | 3,826 | 3,826 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 3,826 | 3,826 |
| 39 | `response_code` | 2 bytes | 예 | 1,928 | 1,928 |
| 42 | `merchant_number` | 15 bytes | 예 | 3,826 | 3,826 |
| 49 | `currency_code` | 2 bytes | 예 | 3,826 | 3,826 |

## 신한카드 MS — shinhan_ms

후보 114,824건. ok 104,716, fallback 10,108, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 114,824 | 114,824 |
| 4 | `transaction_amount` | 12 bytes | 예 | 114,824 | 114,824 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 114,824 | 114,824 |
| 12 | `local_time` | 6 bytes | 예 | 114,824 | 114,824 |
| 13 | `local_date` | 4 bytes | 예 | 114,824 | 114,824 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 57,410 | 57,410 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 114,824 | 114,824 |
| 39 | `response_code` | 2 bytes | 예 | 65,970 | 65,970 |
| 41 | `terminal_id` | 16 bytes | 예 | 4 | 4 |
| 42 | `merchant_number` | 10 bytes, 하위 offset 0 / 10 | 예 | 114,824 | 114,824 |
| 49 | `currency_code` | 3 bytes | 예 | 114,817 | 114,817 |

## 신한카드 IC — shinhan_ic

후보 194,098건. ok 194,098, fallback 0, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 3 bytes | 예 | 194,098 | 194,098 |
| 4 | `transaction_amount` | 6 bytes | 예 | 194,098 | 194,098 |
| 7 | `transmission_datetime` | 5 bytes | 예 | 194,098 | 194,098 |
| 11 | `trace_number` | 3 bytes | 예 | 194,098 | 194,098 |
| 18 | `merchant_type` | 2 bytes | 예 | 103,989 | 103,989 |
| 19 | `acquirer_country` | 2 bytes | 예 | 96,324 | 96,324 |
| 22 | `pos_entry_mode` | 2 bytes | 예 | 194,098 | 194,098 |
| 23 | `card_sequence` | 2 bytes | 예 | 194,098 | 194,098 |
| 25 | `pos_condition` | 1 bytes | 예 | 194,098 | 194,098 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 194,098 | 194,098 |
| 39 | `response_code` | 2 bytes | 예 | 97,774 | 97,774 |
| 42 | `merchant_number` | 15 bytes | 예 | 194,098 | 194,098 |
| 49 | `currency_code` | 2 bytes | 예 | 194,098 | 194,098 |

## 우리카드 통합 — woori_sum

후보 49,642건. ok 48,111, fallback 1,529, error 2, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 49,616 | 49,616 |
| 4 | `transaction_amount` | 12 bytes | 예 | 49,616 | 49,616 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 49,640 | 49,640 |
| 11 | `trace_number` | 6 bytes | 예 | 49,640 | 49,640 |
| 12 | `local_time` | 6 bytes | 예 | 46,785 | 46,785 |
| 13 | `local_date` | 4 bytes | 예 | 46,785 | 46,785 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 49,616 | 49,616 |
| 23 | `card_sequence` | 4 bytes | 예 | 24,808 | 0 |
| 25 | `pos_condition` | 2 bytes | 예 | 49,616 | 49,616 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 49,628 | 49,628 |
| 38 | `approval_number` | 8 bytes | 예 | 24,273 | 24,273 |
| 39 | `response_code` | 2 bytes | 예 | 27,650 | 27,650 |
| 42 | `merchant_number` | 15 bytes | 예 | 49,616 | 49,616 |
| 49 | `currency_code` | 3 bytes | 예 | 49,578 | 49,578 |
| 70 | `network_code` | 3 bytes | 예 | 23 | 23 |

## 하나카드 통합 — hana_sum

후보 142,703건. ok 142,703, fallback 0, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 3 bytes | 예 | 142,459 | 142,459 |
| 4 | `transaction_amount` | 6 bytes | 예 | 142,459 | 142,459 |
| 7 | `transmission_datetime` | 5 bytes | 예 | 142,703 | 142,703 |
| 11 | `trace_number` | 3 bytes | 예 | 142,703 | 142,703 |
| 22 | `pos_entry_mode` | 2 bytes | 예 | 142,459 | 142,459 |
| 23 | `card_sequence` | 2 bytes | 예 | 49,702 | 49,702 |
| 25 | `pos_condition` | 1 bytes | 예 | 71,232 | 71,232 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 142,703 | 142,703 |
| 39 | `response_code` | 2 bytes | 예 | 79,501 | 79,501 |
| 42 | `merchant_number` | 11 bytes, 하위 offset 0 / 11 | 예 | 142,459 | 142,459 |
| 49 | `currency_code` | 2 bytes | 예 | 142,459 | 142,459 |
| 70 | `network_code` | 2 bytes | 예 | 244 | 244 |

## 현대카드 MS — hyundai_ms

후보 13,180건. ok 11,979, fallback 1,201, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 6 bytes | 예 | 13,056 | 13,056 |
| 4 | `transaction_amount` | 12 bytes | 예 | 13,056 | 13,056 |
| 7 | `transmission_datetime` | 10 bytes | 예 | 13,180 | 13,180 |
| 11 | `trace_number` | 6 bytes | 예 | 13,180 | 13,180 |
| 12 | `local_time` | 6 bytes | 예 | 13,056 | 13,056 |
| 13 | `local_date` | 4 bytes | 예 | 13,056 | 13,056 |
| 18 | `merchant_type` | 4 bytes | 예 | 6,528 | 6,527 |
| 22 | `pos_entry_mode` | 3 bytes | 예 | 13,056 | 13,056 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 12,332 | 12,332 |
| 39 | `response_code` | 2 bytes | 예 | 6,912 | 6,912 |
| 41 | `terminal_id` | 16 bytes | 예 | 12,332 | 12,332 |
| 42 | `merchant_number` | 10 bytes, 하위 offset 0 / 10 | 예 | 12,332 | 12,332 |
| 49 | `currency_code` | 3 bytes | 예 | 12,332 | 12,332 |
| 70 | `network_code` | 3 bytes | 예 | 124 | 124 |

## 현대카드 IC — hyundai_ic

후보 5,474건. ok 5,474, fallback 0, error 0, control 0.

| DE/하위구간 | 출력명 | 규격 길이 | fallback 공통 | 출력 건수 | 비어 있지 않은 건수 |
|---|---|---|---|---:|---:|
| 3 | `processing_code` | 3 bytes | 예 | 5,474 | 5,474 |
| 4 | `transaction_amount` | 6 bytes | 예 | 5,474 | 5,474 |
| 7 | `transmission_datetime` | 5 bytes | 예 | 5,474 | 5,474 |
| 11 | `trace_number` | 3 bytes | 예 | 5,474 | 5,474 |
| 12 | `local_time` | 3 bytes | 예 | 0 | 0 |
| 13 | `local_date` | 2 bytes | 예 | 0 | 0 |
| 18 | `merchant_type` | 2 bytes | 예 | 5,465 | 5,465 |
| 19 | `acquirer_country` | 2 bytes | 예 | 2,728 | 2,728 |
| 22 | `pos_entry_mode` | 2 bytes | 예 | 5,474 | 5,474 |
| 23 | `card_sequence` | 2 bytes | 예 | 5,474 | 5,474 |
| 25 | `pos_condition` | 1 bytes | 예 | 5,474 | 5,474 |
| 37 | `retrieval_reference` | 12 bytes | 예 | 5,474 | 5,474 |
| 39 | `response_code` | 2 bytes | 예 | 2,746 | 2,746 |
| 42 | `merchant_number` | 15 bytes | 예 | 5,474 | 5,474 |
| 49 | `currency_code` | 2 bytes | 예 | 5,474 | 5,474 |
| 70 | `network_code` | 2 bytes | 예 | 0 | 0 |
