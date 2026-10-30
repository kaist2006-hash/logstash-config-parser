# 카드사별 출력 필드 및 실로그 관측표 — FINAL16

이름은 검색 편의를 위해 표준화한 출력명이며 값은 각 프로필의 DE 또는 하위 구간에서 추출합니다. 카드사·IC/MS별 정의를 독립적으로 사용합니다. 문서 정의를 소비하는 DE 전체와 실제로 출력하는 업무 필드는 서로 다릅니다.

전문 후보 1,265,545건의 최종 프로필별 결과를 기준으로 합니다. `출력 건수`는 ok의 공통·상세 값과 fallback의 공통 값만 포함합니다. error에는 업무 값을 출력하지 않습니다. 빈 값이 허용되는 필드는 출력되어도 비어 있을 수 있어 `비어 있지 않은 건수`를 별도로 표시합니다. 0건은 실로그 미관측이며 검증 완료를 뜻하지 않습니다.

업무 필드의 출력 타입은 문자열입니다. JSON의 `numeric`은 숫자 문자 검증 옵션이며 Elasticsearch의 숫자형 매핑을 변경하지 않습니다. 길이·오프셋 단위는 원문 바이트이며 BCD는 1바이트가 숫자 2자리입니다. 가변 필드의 길이 접두부는 별도로 소비합니다.

공통 출력 대상은 프로필별 DE3~49 emit과 network_code입니다. fallback은 검증한 공통 값만, error는 업무 값 없이 출력합니다. 롯데 MS ISO023400050/0420과 국민 IC ISO023400075/0200은 지정된 조합에서 공통 구간만 복구하며 상세 구간 전에 멈춥니다.

## 기본 출력

| 경로 | 의미 |
|---|---|
| `card_detail.profile / issuer / service` | 서비스 선택 결과 |
| `card_detail.status` | ok / fallback / error / control |
| `card_detail.direction / mti / record_type` | 원문에서 확인된 방향·전문 종류만 출력 |
| `card_detail.fields.*` | 아래 표의 업무 필드 |
| `card_detail.emv.*` | 허용 목록의 EMV 태그를 해석한 값 |
| `card_detail.rest` | 농협에서 정의 구간 뒤에 남은 데이터를 보존한 HEX 문자열 |
| `card_detail.errors / warnings` | 실패 원인 코드·DE 번호 또는 경고 코드 |

`parser_version`, `bitmap`, 바이트 수·오프셋 등의 진단 필드는 기본 출력에서 제외합니다. JSON의 `diagnostics`를 `full`로 바꾸고 파이프라인을 재시작하면 확인할 수 있습니다. 제어 전문에는 거래금액·승인번호 등의 업무 필드가 없는 경우가 있으며 프로필·방향·레코드 종류만 추출됩니다.

| 서비스 | 검증 이벤트 | ok | fallback | error | control |
|---|---:|---:|---:|---:|---:|
| BC IC | 56,134 | 48,892 | 0 | 42 | 7,200 |
| BC MS | 13,456 | 5,776 | 0 | 0 | 7,680 |
| 국민 IC | 302,191 | 302,189 | 2 | 0 | 0 |
| 국민 MS | 71,302 | 49,637 | 21,659 | 6 | 0 |
| 롯데 MS | 51,771 | 44,145 | 7,621 | 5 | 0 |
| 롯데 IC | 12,104 | 10,091 | 2,013 | 0 | 0 |
| 농협 MS | 10,296 | 9,720 | 576 | 0 | 0 |
| 농협 IC | 111,352 | 98,855 | 12,497 | 0 | 0 |
| 삼성 MS | 113,192 | 47,970 | 65,166 | 56 | 0 |
| 삼성 IC | 3,826 | 3,826 | 0 | 0 | 0 |
| 신한 MS | 114,824 | 104,716 | 10,108 | 0 | 0 |
| 신한 IC | 194,098 | 194,098 | 0 | 0 | 0 |
| 우리 통합 | 49,642 | 48,111 | 1,529 | 2 | 0 |
| 하나 통합 | 142,703 | 142,703 | 0 | 0 | 0 |
| 현대 MS | 13,180 | 11,979 | 1,201 | 0 | 0 |
| 현대 IC | 5,474 | 5,474 | 0 | 0 | 0 |

## BC IC — `bcc_ic`

라우팅: `s_service_bcc_ic` / wire: `binary` / 문서 DE 정의: 43개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 3 | bcd / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 8 | bcd / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 5 | bcd / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `trace_number` | DE11 | 공통 | 3 | bcd / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `local_time` | DE12 | 공통 | 3 | bcd / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `local_date` | DE13 | 공통 | 2 | bcd / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `merchant_type` | DE18 | 공통 | 2 | bcd / 숫자검사 | 21,793 | 21,793 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 2 | bcd / 숫자검사 | 21,793 | 21,793 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 2 | bcd / 숫자검사 | 46,230 | 46,230 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 2 | bcd / 숫자검사 | 14,238 | 14,238 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 1 | bcd / 숫자검사 | 24,446 | 24,446 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 48,892 | 48,892 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 27,099 | 27,099 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 48,892 | 48,892 | 관측됨 |
| `currency_code` | DE49 | 공통 | 2 | bcd / 숫자검사 | 24,446 | 24,446 | 관측됨 |
| `installment_months` | DE118 본문 +0 | 상세 | 2 | ascii / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `approval_number` | DE118 본문 +2 | 상세 | 8 | ascii / 문자 | 48,892 | 26,820 | 관측됨 |
| `business_id` | DE118 본문 +10 | 상세 | 12 | ascii / 문자 | 48,892 | 46,225 | 관측됨 |
| `terminal_id` | DE118 본문 +22 | 상세 | 16 | ascii / 문자 | 48,892 | 48,823 | 관측됨 |
| `tax_amount` | DE118 본문 +53 | 상세 | 15 | ascii / 숫자검사 | 48,892 | 48,892 | 관측됨 |
| `service_charge` | DE118 본문 +68 | 상세 | 15 | ascii / 숫자검사 | 48,892 | 48,892 | 관측됨 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_interchange_profile` | 4,218 |
| `application_version` | 4,232 |
| `cryptogram_information` | 4,233 |
| `currency_code` | 4,218 |
| `cvm_results` | 4,233 |
| `terminal_capabilities` | 4,218 |
| `terminal_country` | 4,218 |
| `terminal_type` | 4,233 |
| `terminal_verification_results` | 4,218 |
| `transaction_counter` | 4,218 |
| `transaction_date` | 4,218 |
| `transaction_type` | 4,218 |

## BC MS — `bcc_ms`

라우팅: `s_service_bcc_ms` / wire: `ascii` / 문서 DE 정의: 0개

구형 BCB/BCA/EPT 레코드의 방향·표식·길이 확인만 구현되어 있습니다. 업무 내부 필드 정의가 없어 상세 업무 필드의 검증 완료로 보지 않습니다.

## 국민 IC — `kb_ic`

라우팅: `s_service_cnb_ic` / wire: `binary` / 문서 DE 정의: 48개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 3 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 6 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `point_balance` | DE5 | 공통 | 6 | bcd / 숫자검사 | 4 | 4 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 5 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `trace_number` | DE11 | 공통 | 3 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `local_time` | DE12 | 공통 | 3 | bcd / 숫자검사 | 0 | 0 | 미관측 |
| `local_date` | DE13 | 공통 | 2 | bcd / 숫자검사 | 0 | 0 | 미관측 |
| `merchant_type` | DE18 | 공통 | 2 | bcd / 숫자검사 | 150,135 | 150,135 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 2 | bcd / 숫자검사 | 150,135 | 150,135 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 2 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 2 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 1 | bcd / 숫자검사 | 302,191 | 302,191 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 302,191 | 302,191 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 152,054 | 152,054 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 302,191 | 302,191 | 관측됨 |
| `currency_code` | DE49 | 공통 | 2 | bcd / 숫자검사 | 302,187 | 302,187 | 관측됨 |
| `fallback_reason` | DE61 본문 +0 | 상세 | 2 | ascii / 문자 | 150,135 | 0 | 관측됨 |
| `encrypted_card_transport` | DE61 본문 +2 | 상세 | 1 | ascii / 문자 | 150,135 | 149,984 | 관측됨 |
| `terminal_software_model` | DE61 본문 +3 | 상세 | 16 | ascii / 문자 | 150,135 | 150,135 | 관측됨 |
| `terminal_reader_model` | DE61 본문 +19 | 상세 | 16 | ascii / 문자 | 150,135 | 150,135 | 관측됨 |
| `network_code` | DE70 | 공통 | 2 | bcd / 숫자검사 | 0 | 0 | 미관측 |
| `original_mti` | DE90 본문 +0 | 상세 | 2 | bcd / 문자 | 963 | 963 | 관측됨 |
| `original_trace` | DE90 본문 +2 | 상세 | 3 | bcd / 문자 | 963 | 963 | 관측됨 |
| `original_date` | DE90 본문 +5 | 상세 | 3 | bcd / 문자 | 963 | 963 | 관측됨 |
| `original_approval_number` | DE90 본문 +10 | 상세 | 8 | ascii / 문자 | 963 | 963 | 관측됨 |
| `domestic_country` | DE118 본문 +0 | 상세 | 2 | bcd / 문자 | 302,189 | 302,189 | 관측됨 |
| `installment_months` | DE118 본문 +2 | 상세 | 2 | ascii / 숫자검사 | 302,189 | 302,189 | 관측됨 |
| `domestic_merchant_number` | DE118 본문 +4 | 상세 | 15 | ascii / 문자 | 302,189 | 302,189 | 관측됨 |
| `approval_number` | DE118 본문 +19 | 상세 | 8 | ascii / 문자 | 302,189 | 150,468 | 관측됨 |
| `business_id` | DE118 본문 +27 | 상세 | 15 | ascii / 문자 | 302,189 | 302,189 | 관측됨 |
| `terminal_id` | DE118 본문 +42 | 상세 | 10 | ascii / 문자 | 302,189 | 302,189 | 관측됨 |
| `tax_amount` | DE118 본문 +52 | 상세 | 12 | ascii / 숫자검사 | 302,189 | 302,189 | 관측됨 |
| `service_charge` | DE118 본문 +64 | 상세 | 12 | ascii / 숫자검사 | 302,189 | 302,189 | 관측됨 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_interchange_profile` | 116,278 |
| `application_version` | 116,278 |
| `cryptogram_information` | 116,278 |
| `currency_code` | 116,278 |
| `cvm_results` | 116,278 |
| `terminal_capabilities` | 116,278 |
| `terminal_country` | 116,278 |
| `terminal_type` | 116,278 |
| `terminal_verification_results` | 116,278 |
| `transaction_counter` | 116,278 |
| `transaction_date` | 116,278 |
| `transaction_type` | 116,278 |

`merchant_number`는 DE42의 Card Acceptor ID이며 HOST가 응답에 설정합니다. DE118의 `domestic_merchant_number`와 별도 항목입니다.

## 국민 MS — `kb_ms`

라우팅: `s_service_cnb_ms` / wire: `ascii` / 문서 DE 정의: 24개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 71,296 | 71,296 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 71,296 | 71,296 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 71,296 | 71,296 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 65,316 | 65,316 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 65,316 | 65,316 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 29,668 | 29,668 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 52,016 | 52,016 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 22,348 | 22,348 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 52,016 | 52,016 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 51,960 | 51,960 | 관측됨 |
| `installment_months` | DE55 | 상세 | 가변 ≤2 | ascii / 숫자검사 | 49,637 | 49,637 | 관측됨 |
| `approval_number` | DE56 | 상세 | 가변 ≤8 | ascii / 문자 | 17,166 | 16,226 | 관측됨 |

## 롯데 MS — `lotte_ms`

라우팅: `s_service_ltc_ms` / wire: `ascii` / 문서 DE 정의: 27개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `settlement_amount` | DE5 | 공통 | 12 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `billing_amount` | DE6 | 공통 | 12 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 51,766 | 51,766 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 51,766 | 51,766 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 51,646 | 51,646 | 관측됨 |
| `acquirer_code` | DE32 본문 +2 | 공통 | 6 | ascii / 문자 | 51,646 | 51,646 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 49,024 | 49,024 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 25,736 | 25,736 | 관측됨 |
| `terminal_id` | DE41 | 공통 | 16 | ascii / 문자 | 49,024 | 49,024 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 49,024 | 49,024 | 관측됨 |
| `business_id` | DE43 본문 +0 | 공통 | 10 | ascii / 문자 | 49,024 | 49,024 | 관측됨 |
| `merchant_fee_rate_raw` | DE48 | 공통 | 가변 ≤4 | ascii / 숫자검사 | 23,128 | 23,128 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 49,021 | 49,021 | 관측됨 |
| `installment_months` | DE55 | 상세 | 가변 ≤2 | ascii / 숫자검사 | 44,031 | 44,031 | 관측됨 |
| `approval_number` | DE56 | 상세 | 가변 ≤8 | ascii / 문자 | 23,201 | 22,781 | 관측됨 |
| `deposit_sale_type` | DE57 본문 +0 | 상세 | 2 | ascii / 문자 | 20,830 | 3 | 관측됨 |
| `deposit_amount` | DE57 본문 +2 | 상세 | 14 | ascii / 숫자검사 | 20,830 | 3 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 120 | 120 | 관측됨 |

## 롯데 IC — `lotte_ic`

라우팅: `s_service_ltc_ic` / wire: `ascii` / 문서 DE 정의: 27개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `settlement_amount` | DE5 | 공통 | 12 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `billing_amount` | DE6 | 공통 | 12 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 12,104 | 12,104 | 관측됨 |
| `acquirer_code` | DE32 본문 +2 | 공통 | 6 | ascii / 문자 | 12,104 | 12,104 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 11,020 | 11,020 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 5,794 | 5,794 | 관측됨 |
| `terminal_id` | DE41 | 공통 | 16 | ascii / 문자 | 11,020 | 11,020 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 11,020 | 11,020 | 관측됨 |
| `business_id` | DE43 본문 +0 | 공통 | 10 | ascii / 문자 | 11,020 | 11,020 | 관측됨 |
| `merchant_fee_rate_raw` | DE48 | 공통 | 가변 ≤4 | ascii / 숫자검사 | 4,964 | 4,964 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 11,018 | 11,018 | 관측됨 |
| `installment_months` | DE55 | 상세 | 가변 ≤2 | ascii / 숫자검사 | 10,091 | 10,091 | 관측됨 |
| `approval_number` | DE56 | 상세 | 가변 ≤8 | ascii / 문자 | 4,968 | 4,781 | 관측됨 |
| `deposit_sale_type` | DE57 본문 +0 | 상세 | 2 | ascii / 문자 | 5,123 | 0 | 관측됨 |
| `deposit_amount` | DE57 본문 +2 | 상세 | 14 | ascii / 숫자검사 | 5,123 | 0 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 0 | 0 | 미관측 |

실로그의 ASCII 전문 경로를 검증했습니다. 별도 최신 binary IC 문서까지 구현·검증되었다는 뜻은 아닙니다.

## 농협 MS — `nh_ms`

라우팅: `s_service_nlc_ms` / wire: `ascii` / 문서 DE 정의: 33개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 10,110 | 10,110 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 10,110 | 10,110 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 14 | ascii / 숫자검사 | 10,296 | 10,296 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 10,296 | 10,296 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 10,110 | 9,406 | 관측됨 |
| `local_date` | DE13 | 공통 | 8 | ascii / 숫자검사 | 10,110 | 9,406 | 관측됨 |
| `merchant_type` | DE18 | 공통 | 4 | ascii / 숫자검사 | 10,110 | 10,109 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 3 | ascii / 숫자검사 | 10,110 | 9,406 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 4 | ascii / 숫자검사 | 10,110 | 10,110 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 3 | ascii / 숫자검사 | 10,110 | 0 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 2 | ascii / 숫자검사 | 10,110 | 10,110 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 10,110 | 10,110 | 관측됨 |
| `approval_number` | DE38 | 공통 | 8 | ascii / 문자 | 10,110 | 3,999 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 10,110 | 4,778 | 관측됨 |
| `terminal_id` | DE41 | 공통 | 12 | ascii / 문자 | 10,110 | 591 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 10,110 | 10,110 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 10,110 | 9,406 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 186 | 186 | 관측됨 |
| `installment_months` | DE118 본문 +0 | 상세 | 2 | ascii / 숫자검사 | 9,720 | 9,720 | 관측됨 |
| `business_id` | DE118 본문 +2 | 상세 | 10 | ascii / 문자 | 9,720 | 9,720 | 관측됨 |
| `tax_amount` | DE118 본문 +12 | 상세 | 12 | ascii / 숫자검사 | 9,720 | 9,720 | 관측됨 |
| `service_charge` | DE118 본문 +24 | 상세 | 12 | ascii / 숫자검사 | 9,720 | 9,720 | 관측됨 |
| `pg_business_id` | DE118 본문 +37 | 상세 | 10 | ascii / 문자 | 9,720 | 8,694 | 관측됨 |

문서 뒤 `rest` 보존: 1,075건 / 14,750바이트. 의미를 해석한 필드는 아닙니다.

## 농협 IC — `nh_ic`

라우팅: `s_service_nlc_ic` / wire: `ascii` / 문서 DE 정의: 33개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 111,228 | 111,228 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 111,228 | 111,228 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 14 | ascii / 숫자검사 | 111,352 | 111,352 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 111,352 | 111,352 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 111,228 | 110,811 | 관측됨 |
| `local_date` | DE13 | 공통 | 8 | ascii / 숫자검사 | 111,228 | 110,811 | 관측됨 |
| `merchant_type` | DE18 | 공통 | 4 | ascii / 숫자검사 | 111,228 | 111,227 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 3 | ascii / 숫자검사 | 111,228 | 110,811 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 4 | ascii / 숫자검사 | 111,228 | 111,228 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 3 | ascii / 숫자검사 | 111,228 | 111,228 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 2 | ascii / 숫자검사 | 111,228 | 111,228 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 111,352 | 111,352 | 관측됨 |
| `approval_number` | DE38 | 공통 | 8 | ascii / 문자 | 111,228 | 55,207 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 111,352 | 56,036 | 관측됨 |
| `terminal_id` | DE41 | 공통 | 12 | ascii / 문자 | 111,228 | 72,504 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 111,228 | 111,228 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 111,226 | 110,809 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 124 | 124 | 관측됨 |
| `installment_months` | DE118 본문 +0 | 상세 | 2 | ascii / 숫자검사 | 98,739 | 98,739 | 관측됨 |
| `business_id` | DE118 본문 +2 | 상세 | 10 | ascii / 문자 | 98,739 | 98,739 | 관측됨 |
| `tax_amount` | DE118 본문 +12 | 상세 | 12 | ascii / 숫자검사 | 98,739 | 98,739 | 관측됨 |
| `service_charge` | DE118 본문 +24 | 상세 | 12 | ascii / 숫자검사 | 98,739 | 98,739 | 관측됨 |
| `pg_business_id` | DE118 본문 +37 | 상세 | 10 | ascii / 문자 | 98,739 | 2,088 | 관측됨 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_interchange_profile` | 44,423 |
| `application_version` | 44,422 |
| `cryptogram_information` | 44,423 |
| `currency_code` | 44,423 |
| `cvm_results` | 44,422 |
| `terminal_capabilities` | 44,423 |
| `terminal_country` | 44,423 |
| `terminal_type` | 44,422 |
| `terminal_verification_results` | 44,423 |
| `transaction_counter` | 98,638 |
| `transaction_date` | 44,423 |
| `transaction_type` | 44,423 |

문서 뒤 `rest` 보존: 55,617건 / 41,990,088바이트. 의미를 해석한 필드는 아닙니다.

## 삼성 MS — `samsung_ms`

라우팅: `s_service_win_ms` / wire: `ascii` / 문서 DE 정의: 23개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 112,648 | 112,648 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 112,648 | 112,648 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 113,136 | 113,136 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 3,702 | 3,702 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 57,931 | 57,931 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 57,931 | 57,931 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 97,167 | 97,167 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 105,733 | 105,733 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 56,591 | 56,591 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 105,733 | 105,733 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 93,988 | 93,988 | 관측됨 |
| `installment_months` | DE55 | 상세 | 가변 ≤2 | ascii / 숫자검사 | 42,995 | 42,995 | 관측됨 |
| `approval_number` | DE56 | 상세 | 가변 ≤8 | ascii / 문자 | 42,995 | 41,862 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 488 | 488 | 관측됨 |

## 삼성 IC — `samsung_ic`

라우팅: `s_service_win_ic` / wire: `binary` / 문서 DE 정의: 48개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 3 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 6 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 5 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `trace_number` | DE11 | 공통 | 3 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `local_time` | DE12 | 공통 | 3 | bcd / 숫자검사 | 1,913 | 1,913 | 관측됨 |
| `local_date` | DE13 | 공통 | 2 | bcd / 숫자검사 | 1,913 | 1,913 | 관측됨 |
| `merchant_type` | DE18 | 공통 | 2 | bcd / 숫자검사 | 3,796 | 3,796 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 2 | bcd / 숫자검사 | 3,796 | 3,796 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 2 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 2 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 1 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 3,826 | 3,826 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 1,928 | 1,928 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 3,826 | 3,826 | 관측됨 |
| `currency_code` | DE49 | 공통 | 2 | bcd / 숫자검사 | 3,826 | 3,826 | 관측됨 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_interchange_profile` | 973 |
| `application_version` | 973 |
| `cryptogram_information` | 973 |
| `currency_code` | 973 |
| `cvm_results` | 973 |
| `terminal_capabilities` | 973 |
| `terminal_country` | 973 |
| `terminal_type` | 973 |
| `terminal_verification_results` | 973 |
| `transaction_counter` | 973 |
| `transaction_date` | 973 |
| `transaction_type` | 973 |

## 신한 MS — `shinhan_ms`

라우팅: `s_service_lgc_ms` / wire: `ascii` / 문서 DE 정의: 28개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 114,824 | 114,824 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 114,824 | 114,824 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 114,824 | 114,824 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 114,824 | 114,824 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 114,824 | 114,824 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 57,410 | 57,410 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 114,824 | 114,824 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 65,970 | 65,970 | 관측됨 |
| `terminal_id` | DE41 | 공통 | 16 | ascii / 문자 | 4 | 4 | 관측됨 |
| `merchant_number` | DE42 본문 +0 | 공통 | 10 | ascii / 문자 | 114,824 | 114,824 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 114,817 | 114,817 | 관측됨 |

## 신한 IC — `shinhan_ic`

라우팅: `s_service_lgc_ic` / wire: `binary` / 문서 DE 정의: 43개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 3 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 6 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 5 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `trace_number` | DE11 | 공통 | 3 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `merchant_type` | DE18 | 공통 | 2 | bcd / 숫자검사 | 103,989 | 103,989 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 2 | bcd / 숫자검사 | 96,324 | 96,324 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 2 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 2 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 1 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 194,098 | 194,098 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 97,774 | 97,774 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 194,098 | 194,098 | 관측됨 |
| `currency_code` | DE49 | 공통 | 2 | bcd / 숫자검사 | 194,098 | 194,098 | 관측됨 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_interchange_profile` | 57,889 |
| `application_version` | 57,788 |
| `cryptogram_information` | 57,889 |
| `currency_code` | 57,889 |
| `cvm_results` | 57,888 |
| `terminal_capabilities` | 57,879 |
| `terminal_country` | 57,889 |
| `terminal_type` | 57,888 |
| `terminal_verification_results` | 57,889 |
| `transaction_counter` | 57,913 |
| `transaction_date` | 57,889 |
| `transaction_type` | 57,889 |

IC 문서의 DE42 15바이트 정의를 유지합니다. MS의 10자리+플래그 분리를 IC에 적용하지 않습니다.

## 우리 통합 — `woori_sum`

라우팅: `s_service_wrc_sum` / wire: `ascii` / 문서 DE 정의: 27개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 49,616 | 49,616 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 49,616 | 49,616 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 49,640 | 49,640 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 49,640 | 49,640 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 46,785 | 46,785 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 46,785 | 46,785 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 49,616 | 49,616 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 4 | ascii / 숫자검사 | 24,808 | 0 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 2 | ascii / 숫자검사 | 49,616 | 49,616 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 49,628 | 49,628 | 관측됨 |
| `approval_number` | DE38 | 공통 | 8 | ascii / 문자 | 24,273 | 24,273 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 27,650 | 27,650 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 49,616 | 49,616 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 49,578 | 49,578 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 23 | 23 | 관측됨 |

## 하나 통합 — `hana_sum`

라우팅: `s_service_keb_sum` / wire: `binary` / 문서 DE 정의: 29개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 3 | bcd / 숫자검사 | 142,459 | 142,459 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 6 | bcd / 숫자검사 | 142,459 | 142,459 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 5 | bcd / 숫자검사 | 142,703 | 142,703 | 관측됨 |
| `trace_number` | DE11 | 공통 | 3 | bcd / 숫자검사 | 142,703 | 142,703 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 2 | bcd / 숫자검사 | 142,459 | 142,459 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 2 | bcd / 숫자검사 | 49,702 | 49,702 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 1 | bcd / 숫자검사 | 71,232 | 71,232 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 142,703 | 142,703 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 79,501 | 79,501 | 관측됨 |
| `merchant_number` | DE42 본문 +0 | 공통 | 11 | ascii / 문자 | 142,459 | 142,459 | 관측됨 |
| `currency_code` | DE49 | 공통 | 2 | bcd / 숫자검사 | 142,459 | 142,459 | 관측됨 |
| `network_code` | DE70 | 공통 | 2 | bcd / 숫자검사 | 244 | 244 | 관측됨 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_interchange_profile` | 24,957 |
| `application_version` | 24,957 |
| `cryptogram_information` | 24,957 |
| `currency_code` | 24,957 |
| `cvm_results` | 24,956 |
| `terminal_capabilities` | 24,957 |
| `terminal_country` | 24,957 |
| `terminal_type` | 24,957 |
| `terminal_verification_results` | 24,957 |
| `transaction_counter` | 24,957 |
| `transaction_date` | 24,957 |
| `transaction_type` | 24,957 |

## 현대 MS — `hyundai_ms`

라우팅: `s_service_din_ms` / wire: `ascii` / 문서 DE 정의: 27개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 6 | ascii / 숫자검사 | 13,056 | 13,056 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 12 | ascii / 숫자검사 | 13,056 | 13,056 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 10 | ascii / 숫자검사 | 13,180 | 13,180 | 관측됨 |
| `trace_number` | DE11 | 공통 | 6 | ascii / 숫자검사 | 13,180 | 13,180 | 관측됨 |
| `local_time` | DE12 | 공통 | 6 | ascii / 숫자검사 | 13,056 | 13,056 | 관측됨 |
| `local_date` | DE13 | 공통 | 4 | ascii / 숫자검사 | 13,056 | 13,056 | 관측됨 |
| `merchant_type` | DE18 | 공통 | 4 | ascii / 숫자검사 | 6,528 | 6,527 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 3 | ascii / 숫자검사 | 13,056 | 13,056 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 12,332 | 12,332 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 6,912 | 6,912 | 관측됨 |
| `terminal_id` | DE41 | 공통 | 16 | ascii / 문자 | 12,332 | 12,332 | 관측됨 |
| `merchant_number` | DE42 본문 +0 | 공통 | 10 | ascii / 문자 | 12,332 | 12,332 | 관측됨 |
| `currency_code` | DE49 | 공통 | 3 | ascii / 숫자검사 | 12,332 | 12,332 | 관측됨 |
| `network_code` | DE70 | 공통 | 3 | ascii / 숫자검사 | 124 | 124 | 관측됨 |

## 현대 IC — `hyundai_ic`

라우팅: `s_service_din_ic` / wire: `binary` / 문서 DE 정의: 50개

| 출력명 (`card_detail.fields.*`) | 원문 위치 | 분류 | 출력 구간 바이트 수 | 형식 | 출력 건수 | 비어 있지 않은 건수 | 관측 여부 |
|---|---|---|---:|---|---:|---:|---|
| `processing_code` | DE3 | 공통 | 3 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `transaction_amount` | DE4 | 공통 | 6 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `transmission_datetime` | DE7 | 공통 | 5 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `trace_number` | DE11 | 공통 | 3 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `local_time` | DE12 | 공통 | 3 | bcd / 숫자검사 | 0 | 0 | 미관측 |
| `local_date` | DE13 | 공통 | 2 | bcd / 숫자검사 | 0 | 0 | 미관측 |
| `merchant_type` | DE18 | 공통 | 2 | bcd / 숫자검사 | 5,465 | 5,465 | 관측됨 |
| `acquirer_country` | DE19 | 공통 | 2 | bcd / 숫자검사 | 2,728 | 2,728 | 관측됨 |
| `pos_entry_mode` | DE22 | 공통 | 2 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `card_sequence` | DE23 | 공통 | 2 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `pos_condition` | DE25 | 공통 | 1 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `retrieval_reference` | DE37 | 공통 | 12 | ascii / 문자 | 5,474 | 5,474 | 관측됨 |
| `response_code` | DE39 | 공통 | 2 | ascii / 문자 | 2,746 | 2,746 | 관측됨 |
| `merchant_number` | DE42 | 공통 | 15 | ascii / 문자 | 5,474 | 5,474 | 관측됨 |
| `currency_code` | DE49 | 공통 | 2 | bcd / 숫자검사 | 5,474 | 5,474 | 관측됨 |
| `network_code` | DE70 | 공통 | 2 | bcd / 숫자검사 | 0 | 0 | 미관측 |

| EMV 출력명 (`card_detail.emv.*`) | 출력 건수 |
|---|---:|
| `application_version` | 668 |
| `cryptogram_information` | 668 |
| `cvm_results` | 668 |
| `terminal_type` | 668 |


## 농협 MS 망관리 배치의 공통 복구

사진의 0800/0810은 문서의 94바이트 망관리 배열과 다른 예약영역 배치입니다. 지정된 ISO 헤더·bitmap·NHCARD 사용자영역과 앞/뒤 60/80바이트 공백 패턴을 확인한 경우에만 아래 공통 값을 복구합니다. 오프셋은 ISO 헤더 시작 기준입니다. 해당 경우는 fallback이며 상세 거래 필드는 출력하지 않습니다.

| 출력명 | 의미 | 오프셋 | 길이 | 실로그 |
|---|---|---:|---:|---:|
| transmission_datetime | 전송일시 YYYYMMDDhhmmss | 108 | 14 | 186 |
| trace_number | 전문추적번호 | 122 | 6 | 186 |
| network_code | 망관리코드(실로그 301) | 128 | 3 | 186 |

위 호환 배치의 논리 DE 의미는 7/11/70이지만 실제 bitmap은 거래용 템플릿을 포함하므로 일반적인 bitmap 순서로 필드 위치를 계산한 결과가 아닙니다. warnings에 network_layout_common_only를 표시합니다.
