# FINAL15 적용 안내

> 최신 파일과 적용 방법은 [FINAL16 안내](APPLY_GUIDE_FINAL16.md)를 따른다. 아래는 이전 버전 이력이다.

FINAL14를 대체합니다. 상세 불일치 시 공통필드를 복구하는 fallback 기준을 바로잡았습니다. fallback은 공통 값만, error는 업무 값 없이 원인만 출력합니다. 상세 규격을 모르는 상태를 ok로 승격한 버전이 아닙니다.

1. 같은 배포본의 card_detail_parser.rb와 card_detail_specs.json을 함께 교체합니다.
2. 기존 CARD_PARSER_DIR를 유지하고 Logstash 파이프라인을 재시작/재로드합니다. JSON은 시작 시 한 번 읽으므로 파일 저장만으로 반영되지 않습니다.
3. Filebeat encoding: euc-kr과 JSON text_encoding: CP949를 유지합니다.
4. 새로 수집한 이벤트의 card_detail.status와 _source를 확인합니다. 기존 문서·매핑·Kibana 필드 목록은 자동으로 삭제되지 않습니다.

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

이 블록은 앞단에서 서비스별 @metadata.target_alias를 설정하고 message에 전문을 수집한 환경을 전제로 합니다. 기존 서비스 라우팅/멀티라인 수집 구성은 필요합니다.

tags의 실제 문자열은 fallback입니다. status=ok/control에는 새 태그를 추가하지 않습니다. 다른 필터의 tags는 유지합니다. errors 배열은 fallback에서도 복구 사유로 남을 수 있으므로 분류는 card_detail.status를 기준으로 봅니다.

기본 diagnostics: minimal은 parser_version·bitmap·바이트 수·offset 등의 진단 값을 숨깁니다. 파서 버전은 @metadata.card_detail_parser_version에 둡니다. 문제 분석 때 JSON diagnostics를 full로 바꾸고 재로드하면 상세 진단을 볼 수 있습니다. full에서도 fallback은 공통필드만, error는 업무 값 없이 출력합니다.

fallback_policy는 공통 출력 범위와 최소 복구 증거를 지정합니다. 거래 전문은 처리코드·금액·전송일시가 필요하고, 망관리는 식별값과 시간/관리 정보의 조합으로 판단합니다. 상세 불일치 자체만으로 error로 내리지 않으며, 공통 증거가 부족한 입력을 일괄 fallback으로 변경하지 않습니다. 카드사별 공통/상세 분류와 원문 위치는 CARD_FIELDS_FINAL15.md를 확인하세요.

업무 출력은 문자열입니다. numeric은 숫자 문자 검증 옵션이며 ES 숫자형 매핑을 바꾸는 옵션이 아닙니다. 숫자 타입이 필요하면 인덱스 템플릿/변환 정책을 별도로 맞춰야 합니다.
