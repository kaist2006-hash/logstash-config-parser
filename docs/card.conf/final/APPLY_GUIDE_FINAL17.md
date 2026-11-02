# CARD FINAL17 적용 안내

버전: `2026-10-30.final17`. `card_detail_parser.rb`와 `card_detail_specs.json`을 함께 교체합니다. Filebeat `encoding: euc-kr`은 유지합니다.

## Ruby 설정

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

현재 카드사별 `[@metadata][target_alias]` 라우팅을 유지합니다. JSON은 등록 시 한 번 읽으므로 파일 교체 후 파이프라인 재시작 또는 설정 재로딩이 필요합니다. 기본 출력은 `minimal`이며 버전은 `[@metadata][card_detail_parser_version]`에 저장됩니다.

## 앞단 공통 처리 — 2026-11-02 간소화

[최신 공통 분기 및 적용 안내](APPLY_SIMPLE_FRONTEND_20261102.md)를 사용합니다. 삼성 전용 긴 첫 분기를 제거하고, 실제 구분자가 있을 때만 legacy dissect를 수행합니다. gateway/status는 원본 message에서 공통 Grok로 추출합니다. Ruby/JSON은 FINAL17 그대로 사용합니다.

운영 input/output·라우팅을 유지하고 기존 텍스트 처리 블록을 교체합니다. 이전 삼성 전용 분기와 공통 처리 블록을 중복 실행하지 않습니다.

## 변경 후 확인

새로 수집한 이벤트에서 `profile=samsung_ms`, 요청 `direction=OUT`, 응답 `direction=IN`을 확인합니다. 이 판정은 로그 함수명 또는 MTI의 끝자리로 추정하지 않고 실제 wrapper로 결정합니다. 기존 인덱스 문서는 파일 교체로 자동 수정되지 않습니다.

사진과 같은 77건은 원문에서 전문이 끊긴 뒤 `uid[] linename[...]`만 남은 응답입니다. 남아 있는 검증된 공통 값은 `fallback`으로 출력하고, 원문에 없는 참조번호·응답코드·가맹점번호는 출력하지 않습니다.

계수된 요청의 `][길이]`와 종료 위치가 일치할 때만 삼성 전송 종료 구간 `FF EF`를 ISO 데이터에서 분리합니다. 길이는 이벤트에서 읽습니다. 일부 바이트가 복원 불가능한 경우에도 종료 구간 밖의 바이트를 업무 필드로 복원하거나 추정하지 않습니다. 내부 필드 검증이 실패하면 `fallback/error` 판정을 유지합니다.

실제 Filebeat→운영 Elasticsearch 연결에 접속한 검증은 아닙니다. 동일 소스의 CP949 호환 디코딩과 실제 Logstash 8.17.6 파이프라인 검증 결과를 제공합니다.
