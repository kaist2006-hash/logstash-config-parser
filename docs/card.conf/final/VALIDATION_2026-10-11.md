# 카드 상세파서 실로그 재검증 결과

검증일: 2026-10-11

대상 parser version: `2026-10-11.final3`

런타임: Logstash 8.17.6 내장 JRuby + 실제 `LogStash::Event`

## 결론

- 카드사별 profile은 분리되어 있다. BC는 `bcc_ic`/`bcc_ms`, 삼성은 `samsung_ic`/`samsung_ms`이며 서로 필드 규격을 공유하지 않는다.
- 593,335개 후보 로그 행을 재생했고 580,856개는 업무전문 완전 파싱 또는 명시된 제어전문 인식으로 처리됐다.
- 완전한 envelope 안에서 규격 미정의 때문에 실패한 업무전문은 없다.
- 나머지 12,479개 행은 닫는 envelope 누락, 선언 길이보다 짧은 payload, 또는 `***` 마스킹으로 분류됐다.
- `card.conf`는 Logstash의 `--config.test_and_exit`에서 `Configuration OK`를 통과했다.

## 카드사별 재생 결과

| 로그 | Profile | 후보 행 | 완전 envelope | 정상 업무/망관리 | 제어전문 인식 | 원본 로그 문제 |
|---|---|---:|---:|---:|---:|---:|
| `bcc_ic` | `bcc_ic` | 56,134 | 56,134 | 48,892 | 7,242 | 0 |
| `bcc_ms` | `bcc_ms` | 13,456 | 13,419 | 5,776 | 7,643 | envelope 누락 37 |
| `din_ic` | `hyundai_ic` | 5,474 | 5,474 | 5,474 | 0 | 0 |
| `din_ms` | `hyundai_ms` | 13,180 | 12,754 | 12,375 | 0 | envelope 누락 426, payload 절단 379 |
| `keb_통합` | `hana_sum` | 142,703 | 142,703 | 142,703 | 0 | 0 |
| `lgc_ic` | `shinhan_ic` | 194,098 | 194,098 | 194,098 | 0 | 0 |
| `lgc_ms` | `shinhan_ms` | 114,824 | 104,719 | 104,716 | 0 | envelope 누락 10,105, DE46 마스킹 3 |
| `win_ic` | `samsung_ic` | 3,826 | 3,826 | 3,826 | 0 | 0 |
| `wrc` | `woori_sum` | 49,640 | 48,148 | 48,111 | 0 | envelope 누락 1,492, 마스킹 37 |

`din_ms`의 51개 0800 요청은 실로그 bitmap에는 DE39가 켜져 있지만 원문 규격과 payload에는 DE39가 없다. 현대 MS profile에 MTI 한정 예외를 명시했으며 모두 frame complete로 처리된다.

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
- 현대 MS: 선언 payload보다 실제 행이 164~180 byte 짧은 379건의 원본 수집 경로 확인이 필요하다.

## 파일 동일성 확인

`bcc_ms`와 `win_ms`의 SHA-256:

`459DFCAF3CD803A0B17FE2D704CAFBFF65250C0FC414AC271E4BC8F33E588BE2`

## 재현

`tests/run_core.py`와 `tests/replay_map.json`을 사용하면 Logstash 8.17.6 런타임에서 동일한 aggregate-only 검증을 재현할 수 있다. 테스트 보고서에는 카드번호나 전문 원문을 기록하지 않는다.
