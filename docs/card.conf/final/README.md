# CARD 파서 FINAL20

현재 제공 파서 식별자: `2026-11-04.final20`. 문서 갱신: 2026-11-06.

- [적용 안내와 검증](APPLY_GUIDE_FINAL20.md) / [처리 흐름](PROCESS_FLOW_FINAL20.md)
- [Ruby](card_detail_parser.rb) / [JSON](card_detail_specs.json)
- [공통·요청·응답 엑셀](CARD_CONF_공통필드_요청응답_FINAL20_20261106.xlsx)
- [전체 ZIP](downloads/CARD_PARSER_FINAL20_20261106.zip)

17개 시트: 전체 공통 기준과 16개 IC/MS/통합 프로필. 각 프로필은 공통 보관 목록 → 요청 OUT → 응답 IN 순서입니다.

공통 최소조건을 만족하지 못하면 error를 유지하되, 완전히 읽혀 검증된 공통 값은 남깁니다. 상세 전용 값·손상 값·EMV·rest는 error에 남기지 않습니다. 사진의 농협 0810 관리 응답은 전송일시·추적번호·망관리코드가 확보되어 기존처럼 fallback입니다.

카드사 선택·상세 규격·인코딩·농협 rest는 FINAL19를 유지합니다. 1,291,227건 재생 결과의 상태·출력 개수는 FINAL19와 같았고, 짧음·손상 경계 시험 69개도 통과했습니다. 이전 FINAL 문서는 당시 결과를 보관한 기록입니다.
