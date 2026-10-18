# 카드사별 공통 필드 정의 및 검증 범위

기준: `card_detail_specs.json`의 `2026-10-18.final8` 및 제공 실로그 재생 결과. 이 문서는 실제 RB가 출력하는 경로와 JSON의 `emit` 정의를 기준으로 한다. 이전 정리표의 `card_detail.header.*`, `card_detail.detail.*` 경로는 현재 구현의 출력 경로가 **아니다**.

## 먼저 알아야 할 점

- 거래 필드의 실제 경로는 `card_detail.fields.<이름>`이다. 아래 표는 해당 카드사/서비스의 **규격에서 추출하도록 정의한 필드**다. 요청/응답 MTI, bitmap, 정상 수신 범위에 따라 개별 이벤트에는 일부만 나타날 수 있다.
- 카드사끼리 필드 이름을 통일했지만 비트맵·헤더·길이·전송형식의 규격은 카드사와 서비스 프로필마다 독립 정의한다. 동일한 이름은 동일한 업무 의미를 뜻하지 동일한 바이트 위치를 뜻하지 않는다.
- Ruby 블록만 적용하면 출력값은 원칙적으로 문자열이다. 함께 제공한 전체 `card.conf`의 `mutate convert`를 적용할 때에만 금액·할부개월수 등 일부가 정수로 변환된다. 코드·식별자·시각은 선행 0 보존을 위해 문자열로 둔다.
- PAN(카드번호), Track II, PIN/PIN block, 암호문 및 의미가 확정되지 않은 보안 데이터는 길이 계산에는 쓰더라도 공통 업무 필드로 출력하지 않는다.

## 모든 활성 ISO 프로필에 공통으로 정의된 8개 이름

아래 8개는 BC MS 고정 레코드를 제외한 **활성 ISO 프로필 14개 모두**에 정의돼 있다. 모든 이벤트에서 값이 채워진다는 뜻은 아니다. 예를 들어 요청에는 응답코드 DE39가 없을 수 있다.

| 출력 경로 (`card_detail.fields.` 접두어 생략) | DE | 의미 |
|---|---:|---|
| `processing_code` | 3 | 거래 처리 코드 |
| `transaction_amount` | 4 | 거래 금액 |
| `transmission_datetime` | 7 | 전문 전송 일시 |
| `pos_entry_mode` | 22 | 카드 입력 방식 |
| `retrieval_reference` | 37 | 조회/추적 참조번호 |
| `response_code` | 39 | 승인·거절 응답 코드 |
| `merchant_number` | 42 | 가맹점 번호 |
| `currency_code` | 49 | 거래 통화 코드 |

공통 메타데이터는 `card_detail.parser_version`, `profile`, `issuer`, `service`, `status`, `frame_status`에 출력된다. 봉투 및 ISO 본문을 식별한 경우에만 `direction`, `mti`, `bitmap`, `present_fields`, `payload_bytes` 등이 추가된다. BC MS에는 ISO `mti`·`bitmap`이 없을 수 있다.

## 카드사·서비스별 추가 필드

각 행에는 위 공통 8개 **외에** 해당 프로필이 출력하도록 정의한 이름을 `DE번호 → 필드명`으로 적었다. `DE118.x`처럼 한 DE 안의 부분필드도 실제 출력 경로는 동일하게 `card_detail.fields.<필드명>`이다. 필드가 없는 로그에서 값을 만들어 채우지 않는다.

| 카드사 / 프로필 | 서비스·검증 상태 | 공통 8개 외 추가 `emit` 정의 |
|---|---|---|
| 비씨 `bcc_ic` | IC/통합 · 실로그 재생 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition`; DE118 부분필드 `installment_months`, `approval_number`, `business_id`, `terminal_id`, `tax_amount`, `service_charge` |
| 비씨 `bcc_ms` | MS · **구조만 확인** | **없음.** 고정 레코드의 내부 업무 필드 offset이 확정되지 않아 `card_detail.fields`를 내보내지 않는다. |
| 국민 `kb_ic` | IC · 실로그 재생 | DE5 `point_balance`; DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition`; DE61 `fallback_reason`, `encrypted_card_transport`, `terminal_software_model`, `terminal_reader_model`; DE70 `network_code`; DE90 `original_mti`, `original_trace`, `original_date`, `original_approval_number`; DE118 `domestic_country`, `installment_months`, `domestic_merchant_number`, `approval_number`, `business_id`, `terminal_id`, `tax_amount`, `service_charge` |
| 국민 `kb_ms` | MS · 실로그 재생 | DE12 `local_time`, DE13 `local_date`; DE55 `installment_months`; DE56 `approval_number` |
| 롯데 `lotte_ic` | IC · 제공 ASCII 로그 재생 | DE5 `settlement_amount`, DE6 `billing_amount`; DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`; DE32 `acquirer_code`; DE41 `terminal_id`, DE43 `business_id`; DE70 `network_code`; DE48 `merchant_fee_rate_raw`, DE55 `installment_months`, DE56 `approval_number`; DE57 `deposit_sale_type`, `deposit_amount` |
| 롯데 `lotte_ms` | MS · 실로그 재생 | 위 롯데 IC 행과 출력 이름·DE 매핑은 같지만 별도 카드사/서비스 프로필로 관리한다. |
| 농협 `nh_ic` | IC · 실로그 재생, 응답 꼬리 미확정 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition`; DE38 `approval_number`, DE41 `terminal_id`, DE70 `network_code`; DE118 `installment_months`, `business_id`, `tax_amount`, `service_charge`, `pg_business_id` |
| 농협 `nh_ms` | MS · 실로그 재생 | 위 농협 IC 행과 출력 이름·DE 매핑은 같지만 별도 서비스 프로필로 관리한다. |
| 삼성 `samsung_ic` | IC · 실로그 재생 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition` |
| 삼성 `samsung_ms` | MS · **비활성/실로그 없음** | JSON 정의상 DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE70 `network_code`가 추가 후보이나 **실제 출력 검증이 아니다**. 현재는 `disabled`이므로 거래 필드를 출력하지 않는다. |
| 신한 `shinhan_ic` | IC · 실로그 재생 | DE11 `trace_number`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition` |
| 신한 `shinhan_ms` | MS · 실로그 재생 | DE12 `local_time`, DE13 `local_date`, DE41 `terminal_id` |
| 우리 `woori_sum` | 통합 · 실로그 재생 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE23 `card_sequence`, DE25 `pos_condition`, DE38 `approval_number`, DE70 `network_code` |
| 하나 `hana_sum` | 통합 · 실로그 재생 | DE11 `trace_number`, DE23 `card_sequence`, DE25 `pos_condition`, DE70 `network_code` |
| 현대 `hyundai_ic` | IC · 실로그 재생 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition`, DE70 `network_code` |
| 현대 `hyundai_ms` | MS · 실로그 재생 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE41 `terminal_id`, DE70 `network_code` |

### BC MS의 “구조 확인”을 풀어 쓰면

로그 봉투와 내부 4자리 길이부를 해제한 뒤 **요청/응답 방향, 고정 위치의 표식, 전체 payload 길이**가 JSON의 한 레코드 종류와 맞는지 확인한다. BCB 거래 요청/응답이 각각 2,557건, BCA 각각 114건, EPT 300-byte 각각 154건, EPT 450-byte 각각 63건으로, 업무 레코드 합계가 5,776건이다. 별도로 health 4,800건과 network 2,880건은 `control`이다. 현재 코드는 표식과 길이가 맞으면 레코드 전체를 소비한 것으로 표시하지만, **레코드 내부의 거래금액·승인번호·가맹점번호 위치를 해석하거나 값의 의미를 검증하지 않는다.** 그래서 BC MS의 `ok`를 “상세 파싱 성공”으로 세면 안 된다.

EMV TLV 필드가 있는 경우에는 JSON의 `emv_export` 정의에 따라 별도 `card_detail.emv.*`가 출력될 수 있다. 이것은 위 `fields.*` 공통 8개에 포함되지 않으며, 해당 TLV가 실로그에 있을 때만 생성된다.

## `status`와 `tags`의 현재 정확한 의미

| `card_detail.status` | 공개 tag | 현재 RB의 판정 |
|---|---|---|
| `ok` | 없음 | 알려진 프로필에서 처리 중 기록된 오류·경고가 없음. **BC MS의 `ok`는 마커·방향·전체 길이만 맞춘 구조 확인**이며 내부 필드 파싱을 뜻하지 않는다. |
| `fallback` | `fallback` | 오류가 `truncated_field`, `truncated_length_prefix`, `truncated_transport_payload`, `trailing_bytes`만으로 구성되고 하나 이상의 `fields`가 추출됐거나, 오류는 없지만 경고가 있음. 즉 **짧은 로그만을 뜻하지 않는다**. |
| `error` | `error` | 그 밖의 형식 오류, 또는 회복 가능한 절단 오류여도 추출된 업무 필드가 없음. |
| `control` | 없음 | 확인된 제어/상태 전문. 거래 상세 파싱 대상이 아니다. |
| `disabled` / `unconfigured` | 없음 | 비활성 프로필 / 라우팅되지 않은 별칭. 거래 파싱을 하지 않는다. |

따라서 현재 `fallback`을 “짧지만 규격이 확실한 정상 로그”와 동일시하면 안 된다. 특히 `trailing_bytes`는 선언된 필드 뒤에 해석되지 않은 데이터가 남았다는 뜻이어서, 전문 규격과의 일치가 입증되지 않는다. 제공 로그의 농협 IC에는 이런 잔여 바이트가 대량으로 있으며 일부는 비공백 데이터다. 이를 무조건 패딩으로 버려 `ok`로 만들지 않았다. 사용자가 원하는 엄격한 BGF 의미로 맞추려면 `trailing_bytes`의 분류와 해당 전문의 확정 규격을 별도로 결정한 뒤 재검증해야 한다.

## 실로그가 증명한 것과 증명하지 못한 것

전체 재생 대상 1,152,346건의 status는 `ok` 1,037,170건, `fallback` 99,761건, `control` 14,880건, `error` 535건이었다. 이 숫자는 **현재 JSON 프로필에 대한 구조적 재생 결과**이며, 모든 카드사의 모든 거래유형·필드값이 문서와 100% 일치한다는 증명이 아니다. BC MS는 내부 업무 필드 0개, 삼성 MS는 실제 자료 0건이다. 롯데 IC 제공 로그는 최신 바이너리 IC 문서와 다른 ASCII 형태이며, 농협 IC 응답의 잔여 구간은 미확정이다. 운영 Beats 인코딩·멀티라인·라우팅은 별도 검증이 필요하다.

세부 카드사별 status 건수는 `VALIDATION_2026-10-18.md`를 참조한다. 현재 구현의 최종 근거는 같은 폴더의 `card_detail_parser.rb`와 `card_detail_specs.json`이며, 과거 `card_field_reference_excel.xml`은 2026-10-11 시점 자료라 현 버전의 근거로 사용하지 않는다.
