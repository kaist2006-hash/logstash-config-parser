# 실로그 120바이트 헤더 결과

민감 식별자인 `nice_serial_no`와 `message_correlation_id`는 마스킹했습니다. offset 120 이후 값은 확인·기록하지 않았습니다.

## 대표 결과

### Back 요청

```json
{
  "msg_length": 561,
  "msg_type": "0200",
  "network_response_code": "0000",
  "process_code": "01010038",
  "nice_serial_no": "25************7283",
  "message_correlation_id": "<masked:51 chars>",
  "direction": "B",
  "transaction_date": "20250828",
  "transaction_time": "135959",
  "msg_format_code": "0101010200",
  "service_instance_id": "2",
  "response_code": "8373"
}
```

### Back 응답

```json
{
  "msg_length": 1323,
  "msg_type": "0110",
  "network_response_code": "0000",
  "process_code": "01010011",
  "nice_serial_no": "25************7182",
  "message_correlation_id": "<masked:51 chars>",
  "direction": "B",
  "transaction_date": "20250828",
  "transaction_time": "135959",
  "msg_format_code": "0101011111",
  "service_instance_id": "2",
  "response_code": "8373"
}
```

### Front 요청

```json
{
  "msg_length": 606,
  "msg_type": "0200",
  "network_response_code": "0000",
  "process_code": "010100ZZ",
  "nice_serial_no": "T1************7226",
  "message_correlation_id": "<blank>",
  "direction": "B",
  "transaction_date": "20250618",
  "transaction_time": "000114",
  "msg_format_code": "010100ZZ00",
  "service_instance_id": "",
  "response_code": "8373"
}
```

### Front 응답

```json
{
  "msg_length": 791,
  "msg_type": "0210",
  "network_response_code": "0000",
  "process_code": "010100ZZ",
  "nice_serial_no": "T1************7226",
  "message_correlation_id": "<masked:51 chars>",
  "direction": "B",
  "transaction_date": "20250618",
  "transaction_time": "000114",
  "msg_format_code": "010100ZZ01",
  "service_instance_id": "2",
  "response_code": "7575"
}
```

## 주요 필드 분포

| 필드 | Back 24,715건 | Front 992건 |
|---|---|---|
| flow | 요청 12,358 / 응답 12,357 | 요청 496 / 응답 496 |
| `msg_type` | `0200` 12,358 / `0110` 12,357 | `0200` 519 / `0210` 473 |
| `network_response_code` | `0000` 24,715 | `0000` 969 / `NETC` 23 |
| `process_code` 종류 | 66종 | 24종 |
| `message_correlation_id` | 존재 24,715 | 공백 496 / 존재 496 |
| `direction` | `B` 24,715 | `B` 883 / `F` 109 |
| `transaction_date` | `20250828` 24,715 | `20250618` 992 |
| `msg_format_code` 종류 | 72종 | 59종 |
| `service_instance_id` | `2` 24,715 | 공백 519 / `2` 374 / `1` 99 |
| `response_code` | `8373` 24,715 | 49종 (`8373` 531, `0000` 243, `6666` 50, `9000` 39 등) |

`msg_length`는 Back 218종, Front 80종입니다. 숫자로 변환해 저장하지만 로그 문자열 전체 길이와의 일치 여부는 검증하지 않습니다.
