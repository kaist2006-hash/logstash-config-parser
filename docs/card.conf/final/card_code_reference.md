# 카드사 규격문서 코드 참조표

기준일: 2026-09-12  
대상: 국민 / 롯데 / 농협 / 삼성 / 신한 / 우리 / 하나 / 현대

> 원칙: 카드사 원본 규격/TAPS에서 실제 확인된 값과 최종 parser가 명시적으로 사용하는 값만 기록한다. 문서에 없는 ISO 일반값이나 카드사별 응답코드를 추정해서 채우지 않는다.

## 1. 전체 Profile / 허용 MTI 참조

아래 값은 최종 `card_detail_specs.json`에서 profile별 허용값으로 관리한다. MTI의 세부 업무 의미는 카드사별 원문 규격을 우선한다.

| Profile | 카드사 | 서비스 | 허용 MTI |
|---|---|---|---|
| `kb_ic` | 국민 | IC | `0200, 0210, 0420, 0430, 0500, 0600, 0610, 0800, 0810` |
| `kb_ms` | 국민 | MS | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `lotte_ms` | 롯데 | MS | `0200, 0210, 0420, 0430, 0800, 0810` |
| `lotte_ic` | 롯데 | IC | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `nh_ms` | 농협 | MS | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `nh_ic` | 농협 | IC | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `samsung_ms` | 삼성 | MS | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `samsung_ic` | 삼성 | IC | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `shinhan_ms` | 신한 | MS | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `shinhan_ic` | 신한 | IC | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `woori_sum` | 우리 | 통합 | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `hana_sum` | 하나 | 통합 | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `hyundai_ms` | 현대 | MS | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |
| `hyundai_ic` | 현대 | IC | `0100, 0110, 0120, 0130, 0200, 0210, 0220, 0230, 0400, 0410, 0420, 0430, 0500, 0510, 0600, 0610, 0800, 0810` |

### 실로그에서 확인된 MTI 특이사항

- 롯데 MS 실로그의 `0420` 중 2,145건은 Bitmap상 DE61이 설정되어 있으나 DE61이 실제 payload 마지막에서 0 byte로 끝난다. 최종 parser는 **DE61이 마지막 필드이고 MTI=0420일 때만** omission warning으로 허용한다.
- 이 예외는 다른 MTI나 다른 필드로 일반화하지 않는다.

## 2. 공통 코드성 필드

| DE/영역 | 최종 ES 필드 | 코드 성격 | parser 처리 | 코드 의미 확인 위치 |
|---|---|---|---|---|
| MTI | `card_detail.header.mti` | 전문 종류 | 원문값 그대로 출력 | 카드사별 승인/취소/망관리 전문 |
| DE3 | `card_detail.detail.processing_code` | Processing Code | 원문값 그대로 출력 | 카드사별 Layout/승인전문 |
| DE18 | `card_detail.detail.merchant_type` | MCC/업종 | 원문값 그대로 출력 | 카드사별 Layout |
| DE22 | `card_detail.detail.pos_entry_mode` | POS Entry Mode | 원문값 그대로 출력 | 국민 `POS Entry Mode구분 의미`, 기타 카드사 Layout/코드표 |
| DE25 | `card_detail.detail.pos_condition` | POS Condition | 원문값 그대로 출력 | 각 카드사 Layout/코드표 |
| DE39 | `card_detail.detail.response_code` | 승인/거절 응답코드 | 원문값 그대로 출력 | 각 카드사 응답코드표 |
| DE49 | `card_detail.detail.currency_code` | 통화코드 | 원문값 그대로 출력 | 각 카드사 Layout |
| DE70 | `card_detail.detail.network_code` | Network Management Code | 원문값 그대로 출력 | 통신망관리 전문 |
| EMV TLV | `card_detail.emv.*` | EMV Tag | 선택 태그 해석 | IC/Chip Data/DE55 문서 |

> DE22/DE39/DE70 등은 카드사마다 코드표가 다를 수 있으므로 parser에서 임의로 한글 의미를 치환하지 않고 원문 코드를 보존한다.

## 3. 롯데 MS — 문서에서 직접 확인한 코드/값

기준 문서: `롯데카드 VAN MS 전문_20230321.xlsx`  
후속 확인: `롯데카드_VAN MS 전문_20250812.xlsx`, `롯데카드_VAN MS 전문_20260721.xlsx`

### DE57 DEPOSIT-INFO

| 필드 | 값 | 의미/구조 |
|---|---|---|
| Length | `016` | 뒤 payload 16 byte |
| 보증금매출 구분값 | `SB` | 보증금매출 정보 구분 |
| 보증금금액 | 14자리 숫자 | 금액 |
| 전체 예시 | `016SB00000000001000` | LLL + 16 byte payload |

### DE61 ARTCL_INFO

DE61은 234 byte 고정 영역이다.

`물품분류수<4> + ((물품구매건수<4> + 물품코드<4> + 물품코드별금액<15>) × 10)`

문서에서 확인한 물품코드 예시는 다음과 같다.

| 코드값 | 코드내용 |
|---|---|
| `1110` | 기저귀 |
| `1210` | 분유 |
| `3110` | 위생용품 |

2026-07-21 후속 문서에는 취소 시에도 물품코드 세팅 필요 주석이 추가되어 있다.

### DE112

| 값/구조 | 의미 |
|---|---|
| Length `032` | 뒤 단말기정보 payload 32 byte |

## 4. EMV TAG 공통 참조

최종 parser가 안전하게 공통 추출하는 태그만 아래에 기재한다.

| Tag | 최종 ES 필드 | 길이(byte) | 내용 |
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

### 카드사별 EMV 위치

| Profile | EMV 원본 위치 | 해석 방식 |
|---|---|---|
| `kb_ic` | DE55 | binary TLV |
| `lotte_ic` | DE55 | binary TLV |
| `nh_ms` / `nh_ic` | DE124 | **ASCII HEX → binary 변환 후 TLV** |
| `samsung_ic` | DE55 | binary TLV |
| `shinhan_ic` | DE55 | binary TLV |
| `woori_sum` | DE55 | TLV |
| `hana_sum` | DE55 | binary TLV |
| `hyundai_ic` | DE55 | binary TLV |

## 5. 카드사별 코드표 원문 위치

아래는 TAPS 전체 전문 모음에서 코드값/응답값을 확인할 때 우선 볼 문서/시트다. **원문에 있는 모든 코드값을 parser에 하드코딩하지 않고, parser는 원문 code를 보존하는 구조**다.

| 카드사 | 서비스 | 코드 참조 문서/시트 | 주요 대상 |
|---|---|---|---|
| 국민 | IC | `국민카드 ... IC승인 전문 Layout_20250523.xlsx` / `POS Entry Mode구분 의미` | DE22 Entry Mode |
| 국민 | MS | `국민카드 국내승인FORMAT_MS...20260318.xlsx` + Bitmap 43 세부 | DE3/22 및 확장 구분값 |
| 롯데 | MS | `롯데카드 VAN MS 전문_20230321.xlsx` / 승인전문·응답코드 계열 | DE39, DE57, DE61 등 |
| 롯데 | IC | `롯데카드_VAN IC 전문_20260721.xls` / 코드목록 계열 | IC 코드/응답값 |
| 농협 | MS/IC | `농협(251128)농협VAN전문-Ver.4.1.1.xlsx` / 응답코드·통신망관리·Chip Data | DE39, DE70, Chip Data |
| 삼성 | MS | `삼성카드_(승인) MS승인VAN사전문_20250523.xlsx` | MS 승인/취소/통신망 코드 |
| 삼성 | IC | `삼성카드_(승인) IC승인전문 Spec_직승인 반영_250523.xlsx` | IC/EMV 코드 |
| 신한 | MS/IC | `신한카드_국내신판_승인전문_VAN(2025.04.16)1.xlsx` + 2025.08.13 | 국내신판 승인 코드 |
| 우리 | 통합 | `우리카드_1. 국내승인_통합전문_v1.5(20241212).xlsx` / BITMAP #39, VAN사별 기관코드 | 응답코드/기관코드 |
| 하나 | 통합 | `하나카드_국내승인_통합전문_v6.9_260223.xlsx` + `하나카드_VAN 승인응답코드_20260813.xlsx` | 승인응답코드/확장 구분값 |
| 현대 | MS | `현대카드_1.국내_VAN_MS전문_PIA1001_20250501_할부개월수.docx` | MS 거래/확장 코드 |
| 현대 | IC | `현대카드_2.국내_VAN_IC카드Layout_PIA1002_20250501.docx` + 20260305 전자바우처 | IC/전자바우처 코드 |

## 6. 보류/주의 코드 영역

실로그가 없는 상태에서 문서 표현이 충돌하는 필드는 코드 의미까지 임의 확정하지 않는다.

| Profile | 필드 | 상태 | 이유 |
|---|---:|---|---|
| `lotte_ic` | DE35 | BLOCKED | 평문 nibble 길이/암호문 byte 길이 판별에 실로그 필요 |
| `lotte_ic` | DE145 | BLOCKED | 문서 필드 표기 오류 확인 필요 |
| `samsung_ms` | DE90 | BLOCKED | 취소/대행 거래별 original data 형식 확인 필요 |
| `samsung_ms` | DE127 | BLOCKED | 하위항목 합계/거래별 확장 확인 필요 |
| `samsung_ic` | DE49 | BLOCKED | 문서 길이와 BCD 설명 충돌 |
| `hana_sum` | DE52 | BLOCKED | 표 길이와 BCD byte 해석 충돌 |
| `hyundai_ms` | DE90 | BLOCKED | 취소전문 거래별 original data 확인 필요 |

## 7. 운영 사용 방법

- 검색/대시보드에서는 `card_detail.detail.response_code`, `pos_entry_mode`, `processing_code`, `network_code`의 **원문 code값**을 기준으로 집계한다.
- 의미가 필요한 경우 이 문서의 카드사별 원문 코드표 위치와 대조한다.
- 실로그가 추가되면 해당 카드사의 코드값 출현 빈도와 규격 코드표를 대조한 뒤 문서에 승격한다.
- 규격문서에 없는 값은 임의로 의미를 붙이지 않는다.
