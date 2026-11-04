# BC 필드 참고 — FINAL19

출력 경로: `card_detail.fields.<필드명>`. BC IC/통합 규칙과 MS 고정 인증 규칙은 카드사 프로필 안에서 독립적으로 정의합니다.

BCB 위치는 문서 외부 STRT 기준 0부터 시작합니다. 문서 BCB는 9, 일부 실로그 응답 BCB는 17이므로 해당 응답의 실제 위치에는 8을 더합니다.

## 일반 인증

| 필드 | 문서 위치 | 길이 | 방향 | 공통 |
| --- | ---: | ---: | --- | --- |
| `message_code` | 12 | 4 | IN/OUT | 예 |
| `retrieval_reference` | 16 | 12 | IN/OUT | 예 |
| `transmission_datetime` | 28 | 14 | IN/OUT | 예 |
| `response_code` | 42 | 2 | IN | 예 |
| `authentication_type` | 80 | 4 | IN/OUT | 예 |
| `request_type` | 84 | 1 | IN/OUT | 예 |
| `channel` | 207 | 1 | IN/OUT | 예 |
| `merchant_number` | 215 | 9 | IN/OUT | 예 |
| `actual_merchant_number` | 224 | 9 | IN/OUT |  |
| `customer_category` | 85 | 1 | IN/OUT | 예 |
| `business_id` | 99 | 10 | IN/OUT | 예 |
| `service_provider_code` | 208 | 3 | IN/OUT | 예 |
| `authentication_approval_number` | 276 | 12 | IN |  |
| `processing_result` | 288 | 4 | IN | 예 |
| `card_product_code` | 292 | 10 | IN |  |

## 현장 할인 인증

| 필드 | 문서 위치 | 길이 | 방향 | 공통 |
| --- | ---: | ---: | --- | --- |
| `message_code` | 12 | 4 | IN/OUT | 예 |
| `retrieval_reference` | 16 | 12 | IN/OUT | 예 |
| `transmission_datetime` | 28 | 14 | IN/OUT | 예 |
| `response_code` | 42 | 2 | IN | 예 |
| `authentication_type` | 80 | 4 | IN/OUT | 예 |
| `request_type` | 84 | 1 | IN/OUT | 예 |
| `channel` | 207 | 1 | IN/OUT | 예 |
| `merchant_number` | 215 | 9 | IN/OUT | 예 |
| `actual_merchant_number` | 224 | 9 | IN/OUT |  |
| `service_provider_code` | 208 | 3 | IN/OUT | 예 |
| `service_code` | 211 | 4 | IN/OUT | 예 |
| `request_count` | 233 | 2 | IN/OUT |  |
| `transaction_amount` | 235 | 9 | IN/OUT | 예 |
| `discount_eligible_amount` | 244 | 9 | IN/OUT |  |
| `original_authentication_number` | 253 | 12 | IN/OUT |  |
| `payment_category` | 265 | 1 | IN/OUT |  |
| `service_management_number` | 266 | 10 | IN/OUT |  |
| `partner_share_amount` | 748 | 9 | IN |  |
| `discount_amount` | 757 | 9 | IN/OUT |  |
| `approved_amount` | 766 | 9 | IN/OUT |  |
| `discount_rate` | 775 | 5 | IN |  |
| `member_company_code` | 780 | 2 | IN |  |
| `campaign_code` | 782 | 7 | IN |  |
| `discount_type` | 789 | 1 | IN |  |
| `authentication_approval_number` | 790 | 12 | IN |  |
| `processing_result` | 802 | 4 | IN | 예 |
| `max_discount_amount` | 806 | 9 | IN |  |
| `card_product_code` | 815 | 10 | IN |  |
| `monthly_service_count` | 825 | 2 | IN |  |
| `card_grade` | 827 | 3 | IN/OUT |  |

조건부 출력: 인증승인번호는 정상 응답 조건에 맞을 때, 전인증승인번호는 취소 조건에 맞을 때 출력합니다. 일반 인증의 미사용 금액·예약 영역은 출력하지 않습니다.

BCA/EPT fallback 공통 필드는 message_code / retrieval_reference / transmission_datetime / IN의 response_code입니다. BCA/EPT의 내부 거래금액·승인번호 위치는 확정하지 않았습니다.

BC IC 구형 0540/0550은 문서에서 확인한 공통 DE까지만 해석해 fallback입니다. BC MS 통합은 BCINTMSG0001 별도 프로필이며 BCB/BCA/EPT를 통합전문으로 억지 해석하지 않습니다.

근거: 비씨카드_첨부 1. 0390_0480_인증 전문(배포용)_20250723.xls / 비씨카드_(국내승인통합전문)__BC_승인통합전문_20180420.xlsx / 비씨카드_ (승인)BC_승인통합전문(배포용)_20221124.xlsx.
