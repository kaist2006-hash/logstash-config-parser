# FINAL14 적용 안내

이 파일은 진단 출력을 줄이고 확인된 필드 경계를 보완한 검증본입니다. 전체 카드사 모든 전문의 상세 파싱이 완료된 버전으로 안내하지 않습니다. 남은 범위는 VALIDATION_FINAL14.md를 확인하세요.

1. 같은 배포본의 card_detail_parser.rb와 card_detail_specs.json을 함께 교체합니다.
2. 기존 CARD_PARSER_DIR를 유지하고 Logstash 파이프라인을 재시작/재로드합니다. JSON은 register 시 한 번 읽으므로 파일 저장만으로 즉시 반영되지 않습니다.
3. Filebeat encoding: euc-kr을 유지합니다. 파서 JSON의 text_encoding: CP949를 유지합니다.
4. 새로 수집된 이벤트의 _source로 확인합니다. 기존 인덱스 문서·매핑·Kibana 필드 목록은 자동으로 삭제되지 않습니다.

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

위 블록은 서비스별 @metadata.target_alias가 기존 앞단에서 설정되고 한 이벤트의 message에 전문이 수집된 환경을 전제로 합니다. Ruby 필터가 서비스 라우팅이나 Filebeat multiline 수집 자체를 대신하지 않습니다. 기존 앞단의 서비스 선택/수집 구성은 필요합니다.

JSON 기본값은 diagnostics: minimal입니다. card_detail에는 profile·issuer·service·status와 실제 존재하는 direction·mti·record_type, 업무 fields·emv·rest, 원인 errors·warnings만 출력합니다. parser_version·bitmap·consumed_bytes·offset 등의 진단 값은 제외됩니다. 파서 버전은 비인덱싱 @metadata.card_detail_parser_version에 둡니다.

문제 분석 중에는 JSON의 diagnostics 값을 full로 바꾸고 파이프라인을 재로드하면 기존 상세 진단을 볼 수 있습니다. 확인 후 minimal로 복구하고 다시 재로드합니다. full은 업무 필드를 더 많이 해석하는 옵션이 아니며 진단 출력만 늘립니다. 운영 오류를 숨기지 않도록 errors의 code와 field, warnings는 minimal에도 유지합니다.

error 이벤트에 fields가 남는 것은 오류 이전에 읽고 검증한 값이 있기 때문입니다. 현재 버전은 오류 DE와 그 뒤의 값을 내보내지 않습니다. status가 error이면 전체 상세 파싱 성공으로 사용하지 마세요. fallback에는 길이 부족 외에도 디코딩 손실·확인된 문서 차이가 포함될 수 있습니다. control에는 거래 업무 필드가 없을 수 있습니다.

비교 기준은 새 이벤트의 card_detail.status와 errors[].code입니다. tags에는 이번 파서가 error/fallback만 추가하며 다른 필터의 기존 태그는 지우지 않습니다.

업무 필드의 numeric은 숫자 문자 검증 옵션입니다. 출력 문자열을 Elasticsearch 숫자 타입으로 바꾸려면 해당 인덱스 템플릿/변환 정책을 별도로 맞춰야 합니다.
