# TAPS 카드사 전체 규격 반영 및 실로그 검증 — 2026-09-12

## 범위

`taps.7z`의 카드사 규격 모음을 참조해 현재 `card.conf` 상세파싱 대상 14개 프로파일을 모두 규격 문서에 매핑했다.

- KB: `kb_ic`, `kb_ms`
- NH: `nh_ic`, `nh_ms`
- Lotte: `lotte_ic`, `lotte_ms`
- Samsung: `samsung_ic`, `samsung_ms`
- Shinhan: `shinhan_ic`, `shinhan_ms`
- Woori: `woori_sum`
- Hana: `hana_sum`
- Hyundai: `hyundai_ic`, `hyundai_ms`

원본 압축 SHA256:

`d987d7611906f0052417fd7944db090691b3683d0954c9871b26c764d024e215`

## 구현 구조

기존 `card_detail_specs.json`은 이미 14개 프로파일의 기본 field layout을 가지고 있으므로 전면 재작성하지 않았다. 대신 다음 구조로 변경했다.

```text
card.conf
  -> card_detail_parser_v2.rb
       -> card_detail_specs.json               # 기존 base
       -> card_detail_specs_taps_overlay.json  # TAPS 문서에서 확인한 변경/해소 항목
```

이 방식의 목적은 기존에 검증된 규격을 보존하고, 새 문서에서 확인된 차이만 명시적으로 병합하기 위함이다.

## 최적화 검토

`card_detail_parser_v2.rb`는 다음 사항을 적용한다.

1. base JSON과 overlay JSON은 `register()`에서 한 번만 읽는다.
2. 이벤트 처리 중 파일/네트워크 I/O가 없다.
3. 카드사별 field spec은 193-slot array로 compile하여 bit 번호 O(1) lookup을 유지한다.
4. variable-length prefix byte 수와 binary/ascii wire 여부를 register 단계에서 미리 계산한다.
5. envelope/header/bitmap 정규식은 register 단계에서 미리 compile/freeze한다.
6. 병합된 profile과 EMV export map은 freeze하여 worker 간 수정 가능성을 제거한다.
7. 민감한 PAN/Track/PIN 원문은 경계 계산에만 사용하고 export하지 않는 기존 정책을 유지한다.
8. NH F124처럼 ASCII HEX로 전달되는 TLV만 `tlv_hex_ascii` 옵션으로 decode 후 TLV parser에 전달한다.
9. 카드사별 예외 동작은 전역 보정하지 않고 profile option으로 제한한다.

Ruby syntax check: `Syntax OK`.
Overlay register smoke test: 14 profiles 정상 compile 확인.

## 프로파일별 TAPS 반영 핵심

| Profile | 주 규격 | 반영 핵심 | 상태 |
|---|---|---|---|
| `kb_ic` | KB IC 20250523 | 기존 실로그 검증 규칙 유지 | `sample_test` |
| `kb_ms` | KB MS 20260318 | 기존 F3/F4/F32/F35/F46/F47/F55/F56/F61 규칙 재확인 | document verified |
| `nh_ms` | NH Ver.4.1.1 | F118 LLL+111, F124 ASCII-HEX TLV, F126/F127 보강 | document verified |
| `nh_ic` | NH Ver.4.1.1 | MS/IC 동일 전문 구조, F118/F124/F126/F127 보강 | document verified |
| `lotte_ms` | Lotte MS 20230321 | F57, F61, F112 추가 + 실로그 envelope 특성 처리 | `sample_test` |
| `lotte_ic` | Lotte IC 20260721 | source 갱신, F35/F145는 실로그 전 보류 | document verified |
| `samsung_ms` | Samsung MS 20250523 | 최신 source 갱신, 기존 안전 경계 유지 | document verified |
| `samsung_ic` | Samsung IC 250523 | 최신 source 갱신, F49 충돌 보류 | document verified |
| `shinhan_ms` | Shinhan 2025.04.16 | field-level 기준 갱신, 2025.08.13 후속 참조 | document verified |
| `shinhan_ic` | Shinhan 2025.04.16 | F120을 binary 1-byte length + payload <=255로 정리 | document verified |
| `woori_sum` | Woori v1.5 | source 갱신, UserArea/TCP/F47 특수 조건 유지 | document verified |
| `hana_sum` | Hana v6.9 | F118=98, F119=100, F120<=150, F126<=80 | document verified |
| `hyundai_ms` | Hyundai PIA1001 20250501 | 최신 MS source/할부개월수 확장 참조 | document verified |
| `hyundai_ic` | Hyundai PIA1002 20250501 | 기본 + 20260305 전자바우처 확장 참조 | document verified |

`document verified`는 문서 기반 설정이 존재한다는 뜻이며 실로그 검증 완료를 의미하지 않는다.

## 런타임 활성화 방식

모든 14개 프로파일 설정은 존재하지만, 기본 활성화는 실로그로 검증한 두 프로파일만 유지한다.

```text
CARD_ENABLED_PROFILES=kb_ic,lotte_ms
```

추가 카드사 실로그를 받으면 파일 수정 없이 환경변수에 profile id만 추가하여 단계적으로 활성화할 수 있다.

## KB IC 실로그 전체 재검증

대상:

`GICNB_X25A_P01.06242025.12.log`

| 항목 | 결과 |
|---|---:|
| Physical rows | 453,297 |
| Selected transactions | 302,191 |
| Excluded rows | 151,106 |
| Frame complete | 302,191 |
| OK | 151,241 |
| Warning | 150,950 |
| Partial | 0 |
| Failed | 0 |

Warning 집계:

- `document_length_deviation_f60`: 150,475
- `document_length_deviation_f55`: 107,814
- `header_differs_from_document`: 2

KB IC는 이번 TAPS overlay에서 파싱 길이 규칙을 변경하지 않았다. 전체 재생 결과도 기존 검증 결과와 동일하다.

## Lotte MS 실로그 전체 재검증

대상:

`GCLTC_X25A_P01.06152025.12.log`

### 기존 상태

| Status | Count |
|---|---:|
| OK | 23,989 |
| Partial | 24,913 |
| Failed | 2,864 |

기존 partial의 주요 원인은 20211021 문서에 없었던 F57/F61이었다.

### TAPS 문서 확인

2025-06-15 실로그보다 이전인 `롯데카드 VAN MS 전문_20230321.xlsx`를 실로그 검증 기준으로 선택했다.

- F57 `DEPOSIT-INFO`: `LLL(016) + SB(2) + deposit amount(14)`
- F61 `ARTCL_INFO`: 234 bytes fixed
- F112 `IC_CAT_INF`: `LLL(032) + terminal info(32)`

### 실로그에서 추가로 확인한 envelope 특성

1. 23,875건은 `len[...]`보다 실제 `data[...]` capture가 길며, 뒤쪽에 잔여 버퍼가 붙는다.
   - `lotte_ms`에만 `trim_to_declared_length=true`를 적용한다.
   - 불일치 사실은 warning으로 남긴다.
2. 2,145건의 MTI `0420`은 bitmap F61이 설정되어 있지만 F61이 마지막 field이고 실제 payload가 0 bytes다.
   - `F61`이 마지막이고 MTI가 `0420`이며 남은 byte가 정확히 0일 때만 omission warning으로 허용한다.
   - 다른 위치/MTI에는 적용하지 않는다.

### 변경 후 결과

| 항목 | 결과 |
|---|---:|
| Physical rows | 51,818 |
| Selected transactions | 51,766 |
| Frame complete | 46,984 |
| OK | 23,989 |
| Warning | 22,995 |
| Partial | 1,918 |
| Failed | 2,864 |

기존 `Partial 24,913` -> `Partial 1,918`로 감소했다.

남은 parse error:

- `truncated_field_f35`: 1,915
- `invalid_numeric_value_f49`: 3

Envelope 자체가 불완전하여 parser payload를 만들 수 없는 `incomplete_text_envelope`: 2,864건은 Failed로 유지한다.

주요 warning:

- `declared_length_mismatch`: 23,875
- `trimmed_to_declared_length`: declared length보다 긴 동일 이벤트에 기록
- `omitted_document_field_f61`: 2,145

원본 로그에 없는 데이터를 추정하여 F35/F49를 보정하지 않았다.

## 남아 있는 문서/실로그 검증 게이트

- Lotte IC: F35 인코딩/길이, F145 문서 표기
- Samsung MS: F127 확장 및 거래별 F90
- Samsung IC: F49 길이/BCD byte 해석
- Woori: TCP length/UserArea 포함 여부, F47 특수 binary length
- Hana: F52 `16 BCD` 해석, F123/F124 fixed512
- Hyundai MS: 취소 F90 거래별 original data
- Hyundai IC: F118/F127 상세 subfield
- KB MS / NH / Shinhan / 기타: 실로그 sample 검증

이 항목들은 문서만으로 확정하기 어려운 부분이며, 임의 규칙을 추가하지 않고 실제 raw log가 들어오면 profile별로 해소한다.
