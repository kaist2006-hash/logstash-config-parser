> Ruby/JSON 최신 적용본은 [FINAL18](APPLY_GUIDE_FINAL18.md)입니다. 아래의 2026-11-02 헤더·바디 분리 방식은 유지합니다.

# 카드 헤더·바디 분리 수정 — 2026-11-02

현재 적용본입니다. 사용자가 주신 첫 linename 조건을 유지하며, MS 텍스트의 분리 경계를 수정했습니다. Ruby/JSON은 2026-10-30.final17 그대로입니다.

## 원인과 수정

- 기존의 오른쪽 대괄호+공백 기준은 linename이 본문 뒤에 있는 로그에서 전문 끝을 잘라 버렸습니다. 그래서 a_header에 전문까지 들어가고 b_body에는 len/uid/linename만 남았습니다.
- 단순히 구분자 유무를 확인하는 수정으로는 잘못된 경계가 해결되지 않습니다.
- 수정본은 로그 시간·PID·gateway·파일·함수·행 번호와 본문 앞의 선택적 linename까지만 a_header에 담습니다.
- 실제 get(...), put(...), put_msg_complete[...] 시작부터 끝까지 b_body로 잡습니다. 뒤쪽 len/uid/linename은 바디 끝에 그대로 남습니다.
- 별표는 로그 헤더와 본문 사이의 구분자로만 처리합니다. 전문 내부의 마스킹 별표로 자르지 않습니다.
- 앞쪽 linename[...]이 있는 농협 수신 형식과, 뒤쪽에 linename이 있는 롯데·삼성 형식을 모두 처리합니다. 값·길이·행 번호는 고정하지 않습니다.
- get→IN, put→OUT 변환을 유지합니다. 끝의 대괄호가 없어도 이 외부 로그 분리는 가능합니다. 내부 전문의 부족 여부는 Ruby가 별도로 판단합니다.
- IC의 기존 ==> HEX 분기는 그대로 유지합니다. 텍스트로 찍힌 IC도 새 텍스트 분리를 사용합니다.

```text
a_header: (I) ...:G/W:파일.c:put_msg_info:행번호:
b_body:   OUT(data[ISO... ] len[...] uid[] linename[...])

a_header: (I) ...:G/W:파일.c:put_msg_complete:행번호:
b_body:   OUT_msg_complete[ISO...][길이] linename[...]

a_header: (I) ...:G/W:파일.c:get_msg_info:행번호:linename[...]
b_body:   IN(data[...])
```

## 적용

[텍스트 분기 교체 블록](REPLACE_TEXT_BRANCHES_20261102.conf.txt)으로 기존 텍스트 get/put 부분을 교체합니다. 첫 if의 linename 조건은 그대로이며, linename 없는 로그는 다음 else-if에서 처리합니다. 이전 별도 삼성 전용 블록은 이 두 조건에 포함되므로 제거합니다.

IC HEX 분기, 마지막 drop, 카드사별 라우팅, Ruby 및 운영 input/output은 유지합니다. 전체 card.conf는 참고본이므로 운영 주소·포트·인증·경로를 무작정 덮어쓰지 않습니다. 별도 filter를 추가해 구형·신형 체인을 중복 실행하지 않습니다. 기존 회사별 후속 구분 조건은 유지해야 합니다.

## 검증

- 실제 Logstash 8.17.6 / 4 workers에서 전체 원본 1,932,571행을 스트리밍 처리했습니다.
- 수집 조건에 해당하는 1,265,482건에서 헤더 전문 혼입, 분리 필드 누락, IN/OUT 오류, 분리 후 원문 복원 오류, gateway·방향 오류, 필터 실패 태그가 모두 0건입니다.
- 전체 실행은 앞단 분리 검증입니다. 상세 Ruby 전체 파싱을 새로 실행했다는 뜻은 아닙니다.
- 별도로 16개 프로필 990입력을 기존 Ruby까지 포함해 전후 비교했습니다. 출력 984건 중 실제 소스 982건과 잘못된 합성 사례 2건이며, 업무 필드·EMV·rest·상태·방향·원본 message 해시 차이 0건입니다.
- 실제 소스 982건에서는 헤더 전문 혼입·바디 방향·원문 복원·필터 실패가 모두 0건입니다.
- 삼성 두 문제 이벤트도 올바르게 분리되고 OUT으로 변환됩니다. 기존 상세 상태 fallback은 유지하며 없는 전문 값을 복원하거나 ok로 올리지 않습니다.
- Moneytree/Hecto의 실로그를 이 카드 데이터셋으로 검증했다고 주장하지 않습니다. 해당 업체를 구분하던 후속 규칙은 그대로 유지합니다.

원본 message, Filebeat euc-kr, Ruby/JSON은 변경하지 않습니다. CP949 호환 디코딩을 이용한 로컬 실제 Logstash 검증이며 운영 Filebeat/Elasticsearch 접속 검증은 아닙니다. 기존 인덱스 문서는 자동 수정되지 않으므로 설정 재로딩 후 새 이벤트로 확인합니다.

파일별 전체 수량은 ALL_CARD_HEADER_BODY_20261102.json, 상세 영향 비교는 SAMPLE_HEADER_BODY_20261102.json, 형식별 정적 진단은 STATIC_HEADER_BODY_20261102.json에 있습니다.

