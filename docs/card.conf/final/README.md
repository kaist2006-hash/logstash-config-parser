# CARD 파서 현재 파일 — FINAL18

현재 Ruby/JSON 버전은 `2026-11-04.final18`입니다. Filebeat euc-kr / JSON CP949를 유지합니다.

- [FINAL18 적용 안내](APPLY_GUIDE_FINAL18.md) / [이번 검증 범위](VALIDATION_FINAL18.md)
- [Ruby](card_detail_parser.rb) / [JSON](card_detail_specs.json)
- [헤더·바디 분리 안내](APPLY_HEADER_BODY_20261102.md): 2026-11-02 방식 유지, 이번 변경으로 conf의 분리 로직을 교체할 필요 없음
- [이전 전체 규격 검증과 남은 제한](VALIDATION_FINAL17.md)
- [카드사별 공통·상세 필드](CARD_FIELDS_FINAL17.md) / [가변 필드 처리](FIELD_VARIABILITY_FINAL17.md): 필드 규격은 FINAL17과 동일

FINAL18은 전문 밖 문자까지 먼저 역변환하다가 실패하는 경로를 보완합니다. 기존 trim 정책이 있는 일반 텍스트에서 선언 길이까지 전부 ASCII인 경우만 경계를 먼저 자릅니다. 농협 rest, 업무 필드 검증, 오류 분류 정책, IC HEX 및 삼성 완료 요청 처리는 유지합니다.

이전 FINAL 문서는 당시 결과를 보관한 기록입니다. 운영의 변환 후 message 원본은 받지 않았으므로 사진의 8건을 동일 디코딩으로 전부 재현했다고 주장하지 않습니다.
