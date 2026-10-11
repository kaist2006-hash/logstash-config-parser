# 카드 상세파서 실로그 재검증 결과

검증일: 2026-10-11

대상 parser version: `2026-10-11.final5`

런타임: Logstash 8.17.6 내장 JRuby + 실제 `LogStash::Event`

## 결론

- 카드사별 profile은 분리되어 있다. BC는 `bcc_ic`/`bcc_ms`, 삼성은 `samsung_ic`/`samsung_ms`이며 서로 필드 규격을 공유하지 않는다.
- 593,335개 후보 로그 행을 재생했다. `ok` 565,920건, 공통필드 복구 `fallback` 12,493건, 제어전문 `ignored` 14,922건이며 실로그 `error`는 0건이다.
- `fallback` 12,493건은 모두 같은 카드사 profile의 내부 길이/Bitmap을 사용했고, 모든 건에 `card_detail.fields.*` 공통필드가 남았다.
- 닫는 envelope가 없거나 선언 길이보다 짧아도 같은 규격에서 공통필드를 안전하게 확보하면 공개 tag `fallback`을 붙인다. 공통필드도 확보할 수 없는 hard failure만 `error` tag를 붙인다.
- 별도의 손상 전문 계약 테스트로 `error` 경로도 확인했다. 다른 카드사 profile로 재시도하지 않는다.
- `card.conf`는 Logstash의 `--config.test_and_exit`에서 `Configuration OK`를 통과했다.

## 카드사별 재생 결과

| 로그 | Profile | 후보 행 | `ok` | `fallback` | `ignored` | `error` |
|---|---|---:|---:|---:|---:|---:|
| `bcc_ic` | `bcc_ic` | 56,134 | 48,892 | 0 | 7,242 | 0 |
| `bcc_ms` | `bcc_ms` | 13,456 | 5,776 | 0 | 7,680 | 0 |
| `din_ic` | `hyundai_ic` | 5,474 | 5,474 | 0 | 0 | 0 |
| `din_ms` | `hyundai_ms` | 13,180 | 12,324 | 856 | 0 | 0 |
| `keb_통합` | `hana_sum` | 142,703 | 142,703 | 0 | 0 | 0 |
| `lgc_ic` | `shinhan_ic` | 194,098 | 194,098 | 0 | 0 | 0 |
| `lgc_ms` | `shinhan_ms` | 114,824 | 104,716 | 10,108 | 0 | 0 |
| `win_ic` | `samsung_ic` | 3,826 | 3,826 | 0 | 0 | 0 |
| `wrc` | `woori_sum` | 49,640 | 48,111 | 1,529 | 0 | 0 |

`din_ms`의 62개 0800 요청은 실로그 bitmap에는 DE39가 켜져 있지만 원문 규격과 payload에는 DE39가 없다. 현대 MS profile에 MTI 한정 예외를 명시했으며 모두 공통필드를 복구해 `fallback`으로 처리된다.

## BGF 방식의 공개 결과 tag

- 정상 전문: `card_detail.status=ok`, `error`/`fallback` tag 없음.
- 같은 카드사 규격에서 공통필드를 확보한 불완전 전문: `card_detail.status=fallback`, tag `fallback`.
- 공통필드도 확보할 수 없는 비정상 전문: `card_detail.status=error`, tag `error`.
- `partial`, `failed`, `_card_detail_parse_failure`, `_card_detail_warning`은 공개 결과로 사용하지 않는다. `frame_status`는 완전/부분 프레임 진단값으로만 유지한다.
- 실제 수집 로그의 `fallback` 12,493건 전부 공통필드가 존재했다. 손상 전문 계약 테스트에서 `error` tag 경로도 통과했다.

## BC 전용 정의

### BC IC/통합

- Header: `BCINTMSG0001`
- 확인 MTI: `0300`, `0310`, `0400`, `0410`
- 전송 포장:
  - 송신 HEX: 2-byte BCD 길이 + binary payload
  - 수신 text: 4자리 ASCII 길이 + ASCII-HEX payload
- 최신 BC 통합전문 규격에 맞춰 DE2/3/4/7/11/12/13/14/18/19/22/23/25/32/35/37/39/42/44/47/49/52/55/60/90/118/126 및 tertiary field를 독립 정의했다.
- DE118의 ASCII 3자리 길이는 길이부 자체를 포함하고, DE126은 길이부를 포함하지 않는 차이를 실로그로 확인했다.

### BC MS 구형 고정전문

- 수집 로그는 최신 BC 통합 ISO 전문이 아니라 BCB/BCA/EPT 고정 record다.
- 4자리 ASCII 길이로 payload를 정확히 자른 후 BCB/BCA/EPT request/response의 방향, record code, 선언 길이를 구조 검증한다.
- 구형 MS 원문 필드 규격이 없으므로 의미 필드 offset은 추정해서 출력하지 않는다. 최신 BC IC 규격이나 삼성 규격을 재사용하지 않는다.

## 실로그로 확정한 보정

- 하나 DE52: 문서 설명의 16BCD가 아니라 실제 wire에서 16 byte. 142,703건 전부 일치.
- 삼성 IC: 삼성 전용 DE35, DE49(2 byte BCD), DE60을 반영해 3,826건 전부 일치.
- 신한 IC: 신한 전용 DE62(16 byte), DE142, DE143을 반영해 194,098건 전부 일치.
- 신한 MS: 응답의 8-byte channel prefix, ETX suffix, DE41/47/48/52/54/57/58/63/126/127을 반영.
- 우리 통합: `==>[...]` 내부가 HEX가 아닌 ASCII text이며 선언 길이 뒤의 stale buffer를 제거.
- 현대 IC/MS: IC BCD2 길이, IC DE128 가변영역, MS ASCII4 길이와 `RESPDATA` prefix를 반영.

## 추가로 필요한 로그/자료

- 이번 묶음에 없음: 국민 MS, 롯데 IC/MS, 농협 IC/MS.
- 국민 IC와 롯데 MS는 이전 검증 이력이 있으나 이번 압축파일에는 포함되지 않았다.
- 삼성 MS: `win_ms`가 `bcc_ms`와 SHA-256이 완전히 동일하다. 삼성 MS 샘플로 사용할 수 없으므로 실제 삼성 MS 로그가 필요하다.
- BC MS: BCB/BCA/EPT 구형 고정전문의 공식 필드 layout 문서가 필요하다. 현재는 안전하게 구조 검증만 한다.
- 현대 MS: 선언 payload보다 실제 행이 164~180 byte 짧은 379건은 공통필드를 복구해 `fallback` 처리했지만 원본 수집 경로 확인은 필요하다.

## 파일 동일성 확인

`bcc_ms`와 `win_ms`의 SHA-256:

`459DFCAF3CD803A0B17FE2D704CAFBFF65250C0FC414AC271E4BC8F33E588BE2`

## 재현

`tests/run_core.py`와 `tests/replay_map.json`을 사용하면 Logstash 8.17.6 런타임에서 동일한 aggregate-only 검증을 재현할 수 있다. 테스트 보고서에는 카드번호나 전문 원문을 기록하지 않는다.
