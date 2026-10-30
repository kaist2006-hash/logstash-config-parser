# CARD 파서 최신 파일 — FINAL17

- [적용 안내 / put 수집 분기](APPLY_GUIDE_FINAL17.md)
- [전체 검증 결과와 남은 제한](VALIDATION_FINAL17.md)
- [가변 필드 처리](FIELD_VARIABILITY_FINAL17.md)
- [카드사별 공통·상세 필드 및 관측 건수](CARD_FIELDS_FINAL17.md)
- [Ruby](card_detail_parser.rb) / [JSON](card_detail_specs.json) / [참고 conf](card.conf)

버전은 2026-10-30.final17입니다. 이전 FINAL 문서는 당시 결과를 보관한 기록입니다. 삼성의 계수된 요청 종료 구간과 사진형 로깅 문구 경계를 보완했습니다. Filebeat euc-kr을 유지합니다. put_msg_complete가 앞단 drop에 걸리면 conf의 분기 추가가 필요합니다.
