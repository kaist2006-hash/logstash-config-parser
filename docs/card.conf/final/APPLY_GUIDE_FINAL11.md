# FINAL11 적용: Filebeat euc-kr 유지

사용자 환경의 `encoding: euc-kr`은 그대로 둔다. `card_detail_parser.rb`와 `card_detail_specs.json`을 **둘 다 FINAL11로 교체**하고 Logstash 파이프라인을 재로딩한다. JSON의 버전은 `2026-10-30.final11`이다.

JSON 기본값:

```json
"text_encoding": "CP949",
"recover_lossy_prefix": true
```

기존 카드사 alias 라우팅이 적용된 filter 안에 다음 Ruby 블록을 사용한다.

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

추가 script_params는 필요 없다. 기존에 `text_encoding => "ISO-8859-1"`을 별도로 넣었다면 제거해야 JSON의 CP949 기본값이 적용된다. 서로 다른 수집 인코딩의 입력을 이 기본값으로 섞으면 안 된다. 바이트 보존 입력을 별도로 사용하는 환경은 이에 맞는 JSON/파이프라인별 text_encoding을 명시한다.

새로 수집되는 이벤트에서 parser_version, profile, status, tags와 errors의 code를 확인한다. 삼성 MS alias는 `s_service_win_ms`이며 기존 card.conf의 `GINST_0005_A01` 경로 규칙을 유지한다. alias가 없으면 unconfigured이므로 파일 이름만으로 자동 추정하지 않는다.

EUC-KR로 이미 잃은 바이트는 복구할 수 없다. 이 경우 검증 가능한 접두부에서 업무 필드를 추출해 fallback으로 남긴다. 헤더까지 손실됐거나 다른 구조 오류가 있으면 error를 유지한다. 원문 전체의 상세 파싱이 반드시 필요하면 바이트 보존 수집이 필요하며, FINAL11이 손실된 값을 복원해 주는 것은 아니다.

fallback에는 errors 배열의 진단 코드가 있을 수 있다. 상태 판단은 `card_detail.status`와 tags를 기준으로 한다. 기존에 인덱싱된 error 이벤트는 파일 교체로 자동 변경되지 않는다. 시험은 원본의 소량 복사본/별도 테스트 인덱스에서 수행하고, 기존 Filebeat registry 전체를 삭제하지 않는다.

업무 필드 타입은 이번 버전에서도 문자열이다. numeric은 문자 내용 검증이며 숫자 타입 변환 옵션이 아니다. 기존 Elasticsearch 매핑과 mutate 변환은 유지한다.

전체 결과와 제한은 [검증서](VALIDATION_FINAL11.md)를 참조한다. 이전 FINAL10용 iso8859-1 변경 안내는 이번 euc-kr 유지 구성의 적용 지침이 아니다.

근거: [Filebeat 입력 인코딩](https://www.elastic.co/guide/en/beats/filebeat/8.17/filebeat-input-log.html#_encoding), [Filebeat 8.17.6 인코딩 구현](https://github.com/elastic/beats/blob/v8.17.6/libbeat/reader/readfile/encoding/encoding.go), [Go EUC-KR/CP949](https://pkg.go.dev/golang.org/x/text/encoding/korean).
