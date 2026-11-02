> 2026-11-02 현재 적용본: [전체 카드 헤더·바디 분리 수정](APPLY_HEADER_BODY_20261102.md). 첫 linename 조건과 IN/OUT 변환을 유지합니다. 전체 대상 1,265,482건의 앞단 분리 오류 0건. Ruby/JSON은 FINAL17입니다.

# CARD 파서 최신 파일 — FINAL17

- [적용 안내 / put 수집 분기](APPLY_GUIDE_FINAL17.md)
- [전체 검증 결과와 남은 제한](VALIDATION_FINAL17.md)
- [가변 필드 처리](FIELD_VARIABILITY_FINAL17.md)
- [카드사별 공통·상세 필드 및 관측 건수](CARD_FIELDS_FINAL17.md)
- [Ruby](card_detail_parser.rb) / [JSON](card_detail_specs.json) / [참고 conf](card.conf)

버전은 2026-10-30.final17입니다. 이전 FINAL 문서는 당시 결과를 보관한 기록입니다. 삼성의 계수된 요청 종료 구간과 사진형 로깅 문구 경계를 보완했습니다. Filebeat euc-kr을 유지합니다. 텍스트 로그는 실제 get/put 전문 시작 위치로 헤더·바디를 나누며, IC HEX 분리는 유지합니다.
