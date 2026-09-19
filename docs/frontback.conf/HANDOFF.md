# 다음 작업용 인수인계

## 현재 상태

기존 카드 작업은 GitHub `docs/card.conf/`에 보존돼 있으며 commit은 `fced0783f9dde31f3a6db2e5dcfa9b827ba3e3ad`입니다. 이번 작업은 별도 `docs/frontback.conf/` 묶음입니다.

Front/Back 1차 파서는 완료됐습니다. 공통 132-byte 채널 헤더를 검증해 기관·상관키·요청/응답·라우팅·코드·파트너·내부 형식을 분리합니다. 내부 결제 본문은 원문이나 민감 필드를 새 필드로 복제하지 않고 형식만 분류합니다.

## 검증 완료

- Logstash 8.17.6 conf 문법 통과
- 합성 계약 8/8 통과
- 실로그 25,707 거래행: 실패 0, parser error 0
- `message` 변경 0, 경로 변경 0, 상관키 불일치 0
- 1-worker/4-worker digest 동일
- 경고 1건: Front 요청 code 위치가 공백인 변형

자세한 숫자는 `validation/REPORT.md`와 `validation/checks.json`에 있습니다.

## 문서 결론

`taps.7z` 안에는 독립된 공통 채널 규격서가 없습니다. S-OIL XLS 2개에 실제 Front/Back 로그 예시와 특정 512-byte 상위전문 정의가 있지만 전체 채널 공통 규격은 아닙니다. 그래서 `soil_bonus_coupon` 후보는 JSON에서 비활성화했습니다.

## 다음에 할 일

1. 특정 내부 전문을 상세 파싱할 우선순위를 정합니다. 현재 실로그 분류는 ISO8583 ASCII 11,819건, binary/STX 8,656건, custom/opaque 3,757건입니다.
2. 후보별로 `institution_code`, `partner_code`, `route_code`, `inner_kind` 조합을 selector로 고정합니다.
3. 동일 selector의 요청/응답 원시 표본과 정확히 대응하는 규격 문서를 선택합니다.
4. 새 내부 프로파일은 기본 `enabled: false`로 추가하고 1-worker/4-worker 전체 재생 결과가 같을 때만 켭니다.
5. S-OIL 상위전문은 실제 BackChannel `SOIN` 표본이 확보되기 전에는 활성화하지 않습니다.

## 운영 반영 전 확인

- `FRONTBACK_PARSER_DIR` 절대경로
- 원래 내부 ES 주소를 `FRONTBACK_ES_HOST_1..3`으로 주입
- 비밀번호는 `FRONTBACK_ES_PASSWORD` 또는 Logstash keystore로 주입
- Filebeat가 CP949/혼합 binary 행을 어떻게 문자열화하는지 확인
- 기존 인덱스 템플릿에 `frontback_detail.mapping.json`의 필요한 속성만 병합

원본 로그와 규격 문서는 저장소에 넣지 않았고, 운영 ES 주소·평문 비밀번호도 제거했습니다.
