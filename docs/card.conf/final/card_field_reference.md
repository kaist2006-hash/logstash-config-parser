# 카드사 상세파싱 공통필드 정리표

기준일: 2026-09-12  
대상: 국민 / 롯데 / 농협 / 삼성 / 신한 / 우리 / 하나 / 현대  
대상 서비스: MS / IC / 통합

> 이 문서는 BGF의 **정리 방식만 참고**한다. BGF의 ES 필드명은 사용하지 않는다. 카드 전문끼리 의미가 같은 항목만 `card_detail` 하위의 공통 필드명으로 통일한다.

## 1. 공통화 원칙

- 원본 ISO8583 DE 위치와 원본 파서 필드 `[card_detail][fields]`는 유지한다.
- 카드사 또는 MS/IC/통합에 따라 DE 위치가 달라도 **업무 의미가 같으면 동일한 최종 필드명**으로 복사한다.
- 카드번호(PAN), Track II, PIN 등 민감 필드는 전문 경계 계산에는 사용하되 공통 ES 필드로 내보내지 않는다.
- `service=IC`라고 해서 반드시 binary wire인 것은 아니다. 농협은 문서상 MS/IC 동일 전문 구조를 사용하므로 두 프로파일 모두 ASCII 규격으로 유지한다.
- 공통필드 생성은 `card.conf`의 후처리 `mutate copy`가 담당하고, 실제 전문 경계/Bitmap/길이 해석은 `card_detail_parser.rb`가 담당한다.

## 2. HEADER 공통필드

| No | 최종 공통 ES 필드 | 영역 | 공통 의미 | 생성 기준 | 공통 구분 |
|---:|---|---|---|---|---|
| 1 | `card_detail.header.profile` | HEADER | 적용 파서 프로파일 | profile id | CARD_CORE |
| 2 | `card_detail.header.issuer` | HEADER | 카드사 | profile issuer | CARD_CORE |
| 3 | `card_detail.header.service` | HEADER | MS / IC / 통합 | profile service | CARD_CORE |
| 4 | `card_detail.header.direction` | HEADER | IN / OUT | S/R 또는 get/put | CARD_CORE |
| 5 | `card_detail.header.message_length` | HEADER | 실제 파싱 payload byte 수 | parser payload_bytes | CARD_CORE |
| 6 | `card_detail.header.iso_header` | HEADER | ISO Header | ISO 12-byte header | CARD_CORE |
| 7 | `card_detail.header.mti` | HEADER | Message Type Indicator | MTI | CARD_CORE |
| 8 | `card_detail.header.bitmap` | HEADER | Primary/Secondary/Third Bitmap | decoded bitmap | CARD_CORE |
| 9 | `card_detail.header.present_fields` | HEADER | Bitmap상 존재 DE 목록 | decoded bitmap | CARD_CORE |

## 3. DETAIL 공통필드

| No | 최종 공통 ES 필드 | 대표 원본 DE/위치 | 공통 의미 | 출력 형태 | 공통 구분 |
|---:|---|---|---|---|---|
| 1 | `card_detail.detail.processing_code` | DE3 | 거래 Processing Code | keyword | CARD_CORE |
| 2 | `card_detail.detail.transaction_amount` | DE4 | 거래금액 | long | CARD_CORE |
| 3 | `card_detail.detail.settlement_amount` | DE5 | 정산금액 | long | CONDITIONAL |
| 4 | `card_detail.detail.billing_amount` | DE6 | 청구금액 | long | CONDITIONAL |
| 5 | `card_detail.detail.point_balance` | DE5/확장 | 포인트/잔액성 금액 | long | CONDITIONAL |
| 6 | `card_detail.detail.transmission_datetime` | DE7 | 전문 전송일시 | keyword | CARD_CORE |
| 7 | `card_detail.detail.trace_number` | DE11 | STAN/추적번호 | keyword | CARD_CORE |
| 8 | `card_detail.detail.local_time` | DE12 | 현지 거래시간 | keyword | CARD_CORE |
| 9 | `card_detail.detail.local_date` | DE13 | 현지 거래일자 | keyword | CARD_CORE |
| 10 | `card_detail.detail.merchant_type` | DE18 | 가맹점 업종/MCC 계열 | keyword | COMMON_WHEN_PRESENT |
| 11 | `card_detail.detail.acquirer_country` | DE19 | 매입기관 국가코드 | keyword | COMMON_WHEN_PRESENT |
| 12 | `card_detail.detail.pos_entry_mode` | DE22 | 카드 입력/Entry Mode | keyword | CARD_CORE |
| 13 | `card_detail.detail.card_sequence` | DE23 | 카드 순번 | keyword | COMMON_WHEN_PRESENT |
| 14 | `card_detail.detail.pos_condition` | DE25 | POS Condition Code | keyword | COMMON_WHEN_PRESENT |
| 15 | `card_detail.detail.acquirer_code` | DE32/카드사 확장 | 매입기관 코드 | keyword | COMMON_WHEN_PRESENT |
| 16 | `card_detail.detail.retrieval_reference` | DE37 | Retrieval Reference Number | keyword | CARD_CORE |
| 17 | `card_detail.detail.approval_number` | DE38 / DE56 / DE118 세부 | 승인번호 | keyword | CARD_CORE_SEMANTIC |
| 18 | `card_detail.detail.response_code` | DE39 | 승인/거절 응답코드 | keyword | CARD_CORE |
| 19 | `card_detail.detail.terminal_id` | DE41 / DE118 세부 | 단말/CAT ID | keyword | CARD_CORE_SEMANTIC |
| 20 | `card_detail.detail.merchant_number` | DE42 / 확장 | 가맹점번호 | keyword | CARD_CORE |
| 21 | `card_detail.detail.currency_code` | DE49 | 거래 통화코드 | keyword | CARD_CORE |
| 22 | `card_detail.detail.network_code` | DE70 | Network Management Code | keyword | COMMON_WHEN_PRESENT |
| 23 | `card_detail.detail.installment_months` | DE55 / DE118 세부 등 | 할부개월수 | integer | CARD_CORE_SEMANTIC |
| 24 | `card_detail.detail.tax_amount` | DE118 세부 등 | 세금/부가세 | long | CARD_COMMON_EXTENSION |
| 25 | `card_detail.detail.service_charge` | DE118 세부 등 | 봉사료 | long | CARD_COMMON_EXTENSION |
| 26 | `card_detail.detail.business_id` | DE43/DE118 세부 | 사업자번호 | keyword | CARD_COMMON_EXTENSION |
| 27 | `card_detail.detail.pg_business_id` | DE118 세부 | PG 사업자번호 | keyword | CONDITIONAL |
| 28 | `card_detail.detail.domestic_country` | DE118 세부 | 국내/국가 구분 | keyword | CONDITIONAL |
| 29 | `card_detail.detail.domestic_merchant_number` | DE118 세부 | 국내 가맹점번호 | keyword | CONDITIONAL |
| 30 | `card_detail.detail.original_mti` | DE90 세부 | 원거래 MTI | keyword | CANCEL_COMMON |
| 31 | `card_detail.detail.original_trace` | DE90 세부 | 원거래 추적번호 | keyword | CANCEL_COMMON |
| 32 | `card_detail.detail.original_date` | DE90 세부 | 원거래 일자/시각 영역 | keyword | CANCEL_COMMON |
| 33 | `card_detail.detail.original_approval_number` | DE90/확장 | 원승인번호 | keyword | CANCEL_COMMON |
| 34 | `card_detail.detail.deposit_sale_type` | 롯데 MS DE57 | 보증금매출 구분 | keyword | LOTTE_EXTENSION |
| 35 | `card_detail.detail.deposit_amount` | 롯데 MS DE57 | 보증금액 | long | LOTTE_EXTENSION |
| 36 | `card_detail.detail.merchant_fee_rate_raw` | 롯데 MS DE48 | 가맹점 수수료율 원문 | keyword | LOTTE_EXTENSION |

## 4. TERMINAL 공통필드

| 최종 공통 ES 필드 | 대표 위치 | 의미 | 공통 구분 |
|---|---|---|---|
| `card_detail.terminal.fallback_reason` | KB IC DE61 세부 | IC FallBack 사유 | TERMINAL_COMMON |
| `card_detail.terminal.encrypted_card_transport` | KB IC DE61 세부 | 카드정보 암호화 전달 구분 | TERMINAL_COMMON |
| `card_detail.terminal.software_model` | KB IC DE61 세부 | 단말 SW 모델/버전 | TERMINAL_COMMON |
| `card_detail.terminal.reader_model` | KB IC DE61 세부 | Reader 모델 | TERMINAL_COMMON |

## 5. EMV 공통필드

EMV TLV가 존재하는 프로파일은 카드사별 원본 DE 위치가 달라도 다음 태그를 같은 `card_detail.emv.*` 경로로 출력한다.

| EMV Tag | 최종 필드 | 길이(byte) | 의미 |
|---|---|---:|---|
| `95` | `card_detail.emv.terminal_verification_results` | 5 | Terminal Verification Results |
| `9F33` | `card_detail.emv.terminal_capabilities` | 3 | Terminal Capabilities |
| `9F34` | `card_detail.emv.cvm_results` | 3 | CVM Results |
| `9F35` | `card_detail.emv.terminal_type` | 1 | Terminal Type |
| `9F09` | `card_detail.emv.application_version` | 2 | Application Version |
| `9F36` | `card_detail.emv.transaction_counter` | 2 | Application Transaction Counter |
| `82` | `card_detail.emv.application_interchange_profile` | 2 | Application Interchange Profile |
| `9F27` | `card_detail.emv.cryptogram_information` | 1 | Cryptogram Information Data |
| `9A` | `card_detail.emv.transaction_date` | 3 | Transaction Date |
| `9C` | `card_detail.emv.transaction_type` | 1 | Transaction Type |
| `5F2A` | `card_detail.emv.currency_code` | 2 | Transaction Currency Code |
| `9F1A` | `card_detail.emv.terminal_country` | 2 | Terminal Country Code |

## 6. 프로파일별 규격/파싱 요약

| Profile | 카드사 | 서비스 | Wire | 검증단계 | 주요 공통 DE | 카드사/규격 확장 및 보류 |
|---|---|---|---|---|---|---|
| `kb_ic` | 국민 | IC | binary | **실로그 검증** | 3,4,7,11,12,13,18,19,22,23,25,37,39,42,49,70 | DE55 EMV, DE61 terminal, DE90 original, DE118 승인/가맹점/할부/세금/봉사료 |
| `kb_ms` | 국민 | MS | ASCII | 문서검증/실로그없음 | 3,4,7,12,13,22,37,39,42,49 | DE55 할부, DE56 승인번호, DE46/47/61 확장 |
| `lotte_ms` | 롯데 | MS | ASCII | **실로그 검증** | 3,4,5,6,7,11,12,13,22,37,39,41,42,49,70 | DE48 수수료, DE55 할부, DE56 승인, DE57 보증금, DE61 바우처, DE112 단말정보 |
| `lotte_ic` | 롯데 | IC | binary | 문서검증/실로그없음 | 3,4,7,11,12,13,18,19,22,23,25,37,39,42,49,70 | DE55 EMV; DE35/145는 실로그 전 보류 |
| `nh_ms` | 농협 | MS | ASCII | 문서검증/실로그없음 | 3,4,7,11,12,13,18,19,22,23,25,37,38,39,41,42,49,70 | DE118 할부/사업자/세금/봉사료, DE124 ASCII-HEX EMV TLV |
| `nh_ic` | 농협 | IC | ASCII | 문서검증/실로그없음 | **MS와 동일 전문 구조** | DE118/124/126/127도 MS와 동일 규칙 |
| `samsung_ms` | 삼성 | MS | ASCII | 문서검증/실로그없음 | 3,4,7,11,12,13,22,37,39,42,49,70 | DE82/83, DE126; DE90/127 거래별 형식 보류 |
| `samsung_ic` | 삼성 | IC | binary | 문서검증/실로그없음 | 3,4,7,11,12,13,18,19,22,23,25,37,39,42 | DE55 EMV; DE49 문서 충돌 보류 |
| `shinhan_ms` | 신한 | MS | ASCII | 문서검증/실로그없음 | 3,4,7,12,13,22,37,39,42,49 | DE44/46/55/56/61 확장 |
| `shinhan_ic` | 신한 | IC | binary | 문서검증/실로그없음 | 3,4,7,11,18,19,22,23,25,37,39,42,49 | DE55 EMV, DE120 binary-length 가변 |
| `woori_sum` | 우리 | 통합 | ASCII | 문서검증/실로그없음 | 3,4,7,11,12,13,22,23,25,37,38,39,42,49,70 | DE47 binary-length 특수, DE55 EMV, DE118/126 확장 |
| `hana_sum` | 하나 | 통합 | binary | 문서검증/실로그없음 | 3,4,7,11,22,23,25,37,39,42,49,70 | DE55 EMV, DE118/119/120/126; DE52 보류 |
| `hyundai_ms` | 현대 | MS | ASCII | 문서검증/실로그없음 | 3,4,7,11,12,13,18,22,37,39,41,42,49,70 | DE54/55/56/61/126/127; DE90 보류 |
| `hyundai_ic` | 현대 | IC | binary | 문서검증/실로그없음 | 3,4,7,11,12,13,18,19,22,23,25,37,39,42,49,70 | DE55 EMV, DE118/126/127/134/135/142/143 |

## 7. 민감정보/소비만 하는 필드

다음 계열은 전문 위치 계산을 위해 parser가 길이를 소비하지만 공통 출력 대상으로 만들지 않는다.

- DE2 PAN/카드번호 계열
- DE35 Track II 계열
- DE52 PIN/PIN block 계열
- 카드번호 암호문/보안키/보안 데이터 계열
- 문서상 의미가 확정되지 않은 확장영역

## 8. 실로그 검증 기준

- 국민 IC: 업로드 로그에서 대상 302,191건 모두 frame complete. partial/failed 0.
- 롯데 MS: 대상 51,766건 중 46,984건 frame complete. 남은 partial/failed는 원본 envelope 불완전, F35 절단, F49 원본값 이상으로 분류되며 미정의 F57/F61 문제는 최신 규격 반영 후 해소했다.
- 나머지 12개 프로파일은 문서 규격은 설정되어 있으나 실로그가 없어 기본 `CARD_ENABLED_PROFILES`에서는 비활성 상태로 유지한다.

## 9. 기준 규격문서

| 카드사 | 서비스 | 우선 참조 문서 |
|---|---|---|
| 국민 | IC | `국민카드 250000035524_1_★KB국민카드 IC승인 전문 Layout_20250523.xlsx` |
| 국민 | MS | `국민카드 국내승인FORMAT_MS(... )_VAN사_전문_20260318.xlsx` + Bitmap 43 세부 문서 |
| 농협 | MS/IC | `농협(251128)농협VAN전문-Ver.4.1.1.xlsx` |
| 롯데 | MS | `롯데카드 VAN MS 전문_20230321.xlsx` (실로그 시점 기준), 후속 20250812/20260721 참조 |
| 롯데 | IC | `롯데카드_VAN IC 전문_20260721.xls` |
| 삼성 | MS | `삼성카드_(승인) MS승인VAN사전문_20250523.xlsx` |
| 삼성 | IC | `삼성카드_(승인) IC승인전문 Spec_직승인 반영_250523.xlsx` |
| 신한 | MS/IC | `신한카드_국내신판_승인전문_VAN(2025.04.16)1.xlsx` + 2025.08.13 후속 참조 |
| 우리 | 통합 | `우리카드_1. 국내승인_통합전문_v1.5(20241212).xlsx` |
| 하나 | 통합 | `하나카드_국내승인_통합전문_v6.9_260223.xlsx` |
| 현대 | MS | `현대카드_1.국내_VAN_MS전문_PIA1001_20250501_할부개월수.docx` |
| 현대 | IC | `현대카드_2.국내_VAN_IC카드Layout_PIA1002_20250501.docx` + 20260305 전자바우처 확장 |
