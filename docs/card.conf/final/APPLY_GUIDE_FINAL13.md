# FINAL13 적용

> 최신 파일과 적용 방법은 [FINAL16 안내](APPLY_GUIDE_FINAL16.md)를 따른다. 아래는 이전 버전 이력이다.

Filebeat의 `encoding: euc-kr`은 유지한다. card_detail_parser.rb와 card_detail_specs.json을 같은 CARD_PARSER_DIR에 둘 다 교체하고 해당 Logstash pipeline을 재로딩한다. 기존 Ruby 블록의 specs_path만 지정하면 된다.

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

삼성 별칭은 기존 `s_service_win_ms`를 유지한다. 새 put 이벤트에서 다음을 확인한다.

- `card_detail.parser_version`: `2026-10-30.final13`
- `card_detail.profile`: `samsung_ms`
- `card_detail.log_encoding`: `completed_text`
- `card_detail.status`와 tags: 새 검증 결과와 대조한다. errors 배열이 존재하는 fallback도 있으며, 배열 존재와 error 태그는 같은 뜻이 아니다.

JSON 버전만 올려도 이전 Ruby가 요청 포장을 인식하게 되는 것은 아니므로 두 파일을 함께 교체한다. 기존 색인 문서는 자동으로 수정되지 않는다. 새로 수집한 이벤트 또는 소량 복사본을 별도 테스트 인덱스로 확인하고, Filebeat registry 전체를 삭제하지 않는다.

현재 사용자의 설정은 put 이벤트가 이미 Ruby에 도달하고 있으므로 기존 수집·라우팅 조건을 유지할 수 있다. GitHub의 참고용 전체 card.conf를 사용하는 경우에는 put_msg_complete[ 입력이 Ruby 전에 drop되지 않는 새 분기가 필요하다. 완성된 입력을 한 이벤트씩 처리하며 서로 다른 전문을 자동 합치거나 여러 이벤트로 분할하지 않는다.

이 버전은 삼성 요청 포장 누락을 보완했다. 원본 전체 재생에서 error는 56,624 → 1,684건이며 **0건은 아니다**. 남은 구형 F55 등 1,628건과 포장 없는 56줄은 VALIDATION_FINAL13.md를 참조한다. EUC-KR 수집 중 잃은 바이트를 복원하거나 알려지지 않은 버퍼를 정상 규격으로 추정하지 않는다.
