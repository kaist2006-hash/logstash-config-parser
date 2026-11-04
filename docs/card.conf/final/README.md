# CARD 파서 FINAL19

현재 제공본: `2026-11-04.final19`.

- [적용과 처리 순서](APPLY_GUIDE_FINAL19.md) / [전체 검증 결과와 한계](VALIDATION_FINAL19.md)
- [FINAL18 → FINAL19 처리 흐름](PROCESS_FLOW_FINAL19.md)
- [Ruby](card_detail_parser.rb) / [JSON](card_detail_specs.json)
- [gateway 선택 적용](GATEWAY_ROUTING_REPLACEMENT.conf.txt) / [참고 conf](reference/card.conf)
- [BC 필드](BC_FIELDS_FINAL19.md) / [롯데 IC 필드](LOTTE_IC_FIELDS_FINAL19.md)

파일명으로 선택하지 않습니다. 상세 규격 적용 뒤 공통정보 fallback을 사용하고, 복구가 불가능하면 error입니다. 새 롯데 IC BCD 로그를 포함해 1,291,227건을 검증했습니다. ok와 fallback을 모두 상세파싱 완료로 해석하지 않습니다. 이전 문서의 ‘롯데 IC 실로그 검증 완료’ 표기는 실제 IC 첨부를 재검증한 이번 결과로 대체합니다.
