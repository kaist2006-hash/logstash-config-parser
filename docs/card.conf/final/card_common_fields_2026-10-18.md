# 카드사별 공통 필드 정의 및 검증 범위

기준: `2026-10-30.final14`. 카드사별 실제 출력 위치·관측 건수는 [FINAL14 필드표](CARD_FIELDS_FINAL14.md), 검증 범위와 남은 제한은 [검증서](VALIDATION_FINAL14.md), 적용은 [안내](APPLY_GUIDE_FINAL14.md)를 따른다. 아래는 공통 필드명 요약이며 모든 이벤트에서 값이 존재한다는 뜻은 아니다. 기존 card_detail.header/detail 경로는 현재 출력 경로가 아니다.

## 먼저 알아야 할 점

- 거래 필드의 실제 경로는 `card_detail.fields.<이름>`이다. 아래 표는 해당 카드사/서비스의 **규격에서 추출하도록 정의한 필드**다. 요청/응답 MTI, bitmap, 정상 수신 범위에 따라 개별 이벤트에는 일부만 나타날 수 있다.
- 카드사끼리 필드 이름을 통일했지만 비트맵·헤더·길이·전송형식의 규격은 카드사와 서비스 프로필마다 독립 정의한다. 동일한 이름은 동일한 업무 의미를 뜻하지 동일한 바이트 위치를 뜻하지 않는다.
- Ruby 블록만 적용하면 출력값은 원칙적으로 문자열이다. 함께 제공한 전체 `card.conf`의 `mutate convert`를 적용할 때에만 금액·할부개월수 등 일부가 정수로 변환된다. 코드·식별자·시각은 선행 0 보존을 위해 문자열로 둔다.
- PAN(카드번호), Track II, PIN/PIN block, 암호문 및 의미가 확정되지 않은 보안 데이터는 별도 업무 필드로 출력하지 않는다. 단, 농협의 `card_detail.rest`에는 이들 원문이 포함될 수 있어 별도 보호가 필요하다.

운영 타입 기준도 BGF와 같이 필드명 기준으로 고정한다. 전체 `card.conf`에는 `transaction_amount`, `settlement_amount`, `billing_amount`, `point_balance`, `installment_months`, `tax_amount`, `service_charge`, `deposit_amount`의 8개만 정수 변환이 정의돼 있다. **Ruby 블록만 넣는 운영 방식에서는 이 변환이 실행되지 않으므로** Elasticsearch 매핑에서 숫자 타입이 필요하면 별도 매핑/변환을 적용해야 한다. 나머지 코드·식별자·일시·원문 필드는 문자열로 유지한다.

## 모든 활성 ISO 프로필에 공통으로 정의된 8개 이름

아래 8개는 BC MS 고정 레코드를 제외한 **활성 ISO 프로필 15개 모두**에 정의돼 있다. 모든 이벤트에서 값이 채워진다는 뜻은 아니다. 예를 들어 요청에는 응답코드 DE39가 없을 수 있다.

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

기본 메타데이터는 `profile`, `issuer`, `service`, `status`와 실제 확인한 `direction`, `mti`, `record_type`이다. `parser_version`, `frame_status`, `bitmap`, `present_fields`, 바이트 수는 JSON `diagnostics: full`에서만 출력한다. 제어 레코드는 거래 업무 필드가 없을 수 있다.

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
| 농협 `nh_ic` | IC · 실로그 재생, 응답 꼬리는 `rest`로 보존 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition`; DE38 `approval_number`, DE41 `terminal_id`, DE70 `network_code`; DE118 `installment_months`, `business_id`, `tax_amount`, `service_charge`, `pg_business_id` |
| 농협 `nh_ms` | MS · 실로그 재생 | 위 농협 IC 행과 출력 이름·DE 매핑은 같지만 별도 서비스 프로필로 관리한다. |
| 삼성 `samsung_ic` | IC · 실로그 재생 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE18 `merchant_type`, DE19 `acquirer_country`, DE23 `card_sequence`, DE25 `pos_condition` |
| 삼성 `samsung_ms` | MS · 요청/응답 각각 56,568건 및 포장 없는 56줄 검사 | DE11 `trace_number`, DE12 `local_time`, DE13 `local_date`, DE70 `network_code`, DE55 `installment_months`, DE56 `approval_number`. 전체 원문 euc-kr 호환 결과는 ok 47,970 / fallback 63,538 / error 1,684다. 개별 이벤트는 MTI·bitmap·복원 범위에 따라 일부 필드만 출력한다. F127은 길이 영역을 소비하며 내부 항목을 개별 출력하지 않는다. |
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
| `ok` | 없음 | 알려진 프로필의 정상 처리. 농협 IC·MS는 규격으로 해석한 구간 뒤의 미해석 바이트를 `rest`로 보존한 경우도 포함한다. 이때 `warnings`에 `unparsed_rest`가 남으며, `rest` 내부의 상세 규격까지 검증했다는 뜻은 아니다. **BC MS의 `ok`는 마커·방향·전체 길이만 맞춘 구조 확인**이며 내부 필드 파싱을 뜻하지 않는다. |
| `fallback` | `fallback` | 하나 이상의 `fields`가 있고, 오류가 `truncated_field`, `truncated_length_prefix`, `truncated_transport_payload`만으로 구성되거나 오류 없이 봉투·문서 편차 경고만 있음. 정확한 원인은 `card_detail.errors` / `warnings`에 남는다. |
| `error` | `error` | 그 밖의 형식 오류, 또는 경고·절단 오류가 있어도 추출된 업무 필드가 없음. |
| `control` | 없음 | 확인된 제어/상태 전문. 거래 상세 파싱 대상이 아니다. |
| `disabled` / `unconfigured` | 없음 | 비활성 프로필 / 라우팅되지 않은 별칭. 거래 파싱을 하지 않는다. |

final10에서는 **농협 IC·MS에만** 규격으로 해석한 필드 뒤의 미해석 바이트를 `card_detail.rest` 한 필드에 대문자 16진수로 보존하고 `ok`로 분류한다. `remaining_bytes`는 `rest`의 원본 바이트 길이이며, `warnings`에는 `unparsed_rest`가 남는다. 이는 앞부분의 필드 해석 성공을 뜻하며, `rest`의 내부 구조가 확인됐다는 의미는 아니다. 다른 카드사의 설명되지 않은 후행 바이트는 계속 `trailing_bytes` 오류다. `rest`는 결제정보를 포함할 수 있는 원문이므로 운영 저장소에서는 검색 색인 제외, 접근 제한 및 보존 기간을 검토해야 한다. `fallback`도 모든 필드의 업무 의미가 검증됐다는 뜻은 아니며, 경고가 있는 복구 결과는 `card_detail.warnings`와 함께 검토해야 한다.

여기서 `error`는 **파서가 전문 규격에 맞는 구조라고 보증하지 못한다**는 뜻이다. 카드사 거래가 실제로 거절됐거나 운영 장애였다는 판정과는 다르다.

## 실로그가 증명한 것과 증명하지 못한 것

이전 1,208,914건의 재생에는 삼성의 요청 put_msg_complete 56,568건이 누락돼 있었다. FINAL13은 삼성 원문 113,192줄을 모두 검사했고 다른 15개 서비스는 각각 64건의 표본으로 기존 결과와 비교했다. 모든 카드사의 모든 물리 줄을 FINAL13으로 전량 재생했다는 뜻은 아니다. BC MS는 내부 업무 필드를 출력하지 않는다. 롯데 IC는 제공된 ASCII 형태를 검증했고 문서의 바이너리 IC 형태는 미검증이다. 농협의 알려진 필드를 처리한 후행 데이터는 rest HEX로 보존한다. 농협 IC의 F118/F124 경계 미해결 401건은 이 rest 처리 대상과 별개다. euc-kr로 바이트가 손실되면 확인 가능한 접두부의 업무 필드를 추출해 fallback으로 처리하고, 구조를 확인할 수 없으면 error를 유지한다. 실제 Beats부터 Elasticsearch까지의 운영 연결은 별도 검증 범위다.

세부 카드사별 status 건수와 적용 방법은 [final10 검증 및 적용 안내](VALIDATION_FINAL10.md)를 참조한다. [참고용 엑셀](CARD_CONF_공통필드_카드사별_FINAL10_20261018.xlsx)은 현재 출력 필드 정의를 정리한 문서다. 현재 구현의 최종 근거는 같은 폴더의 `card_detail_parser.rb`와 `card_detail_specs.json`이며, 과거 `card_field_reference_excel.xml`은 2026-10-11 시점 자료라 현 버전의 근거로 사용하지 않는다.

FINAL14의 DE42 출력 경계: 하나 통합은 앞 11자리, 현대 MS·신한 MS는 앞 10자리만 가맹점번호로 출력하고 전체 15바이트를 소비·검증한다. 신한 IC는 문서상 15바이트 정의를 유지한다. 국민 IC의 DE42 HOST ID와 DE118 국내 가맹점번호는 별도 필드다.
