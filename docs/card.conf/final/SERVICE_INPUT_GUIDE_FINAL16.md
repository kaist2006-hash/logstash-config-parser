> 보관 문서입니다. 현재 적용본은 [FINAL17 적용 안내](APPLY_GUIDE_FINAL17.md), [검증 결과](VALIDATION_FINAL17.md), [필드표](CARD_FIELDS_FINAL17.md)를 사용하세요.

# 테스트 입력·서비스 식별 — FINAL16

| gateway | 실제 서비스 | @metadata.target_alias | card_detail.profile |
|---|---|---|---|
| GINST_0005_D01 | BC MS | s_service_bcc_ms | bcc_ms |
| GINST_0005_A01 | 삼성 MS | s_service_win_ms | samsung_ms |
| GINST_0003_A10 | 농협 MS | s_service_nlc_ms | nh_ms |

예전 zip의 win_ms는 bcc_ms와 같은 BC 원본입니다. 사진의 삼성 인덱스에도 이 BC 원문이 있습니다. 나중에 제공한 폴더 안쪽 win_ms/win_ms가 실제 삼성 A01 원본이며 확인본은 SAMSUNG_MS_GINST_0005_A01.log입니다. 확인본의 SHA256은 bd71e484b9ea3bb2b09f2b3736d29b6a927edec4785fe4d08cf946270e280dd1, 물리 줄 수는 113,192입니다. 원문 확인본은 설정 ZIP/GitHub에 포함하지 않습니다.

확인본을 A01이 들어간 새 테스트 파일 경로로 수집하고, 서비스 지정과 ES 출력 대상이 s_service_win_ms인지 확인하세요. 제공한 참고 card.conf는 경로의 GINST_0005_A01/D01을 구분합니다. 사용자 conf가 win_ms라는 파일명만으로 대상을 고정한다면 실제 gateway와 일치하도록 입력/라우팅을 맞춰야 합니다. 삼성으로 지정한 BC 메시지에 삼성 규격을 적용할 수는 없습니다.

현재 삼성 인덱스에서 gateway=GINST_0005_A01인 새 이벤트를 확인하세요. 예전 D01 문서는 설정 교체만으로 바뀌지 않습니다. Filebeat encoding: euc-kr과 Ruby JSON text_encoding: CP949를 유지합니다.

실제 삼성 원본에는 get(data[ 응답과 put_msg_complete[ 요청이 있습니다. 앞단이 get/put(data[만 통과시키고 나머지를 drop하면 요청은 Ruby까지 도착하지 않습니다. 기존 참고 card.conf에는 아래 분기가 마지막 drop 앞에 있습니다. 현재 앞단에도 해당 수집 경로가 있는지 확인해야 합니다.

```logstash
  else if [message] =~ /put_msg_complete\[/ {
    grok { match => { "message" => "^\(I\)\s*[^:]+:[^:]+:[^:]+:%{DATA:gateway}:" } }
    mutate { replace => { "status" => "OUT" } }
  }
```

그 뒤 서비스별 @metadata.target_alias를 지정하고 기존 Ruby 블록을 실행합니다. 출력도 같은 서비스 지정을 따라야 합니다. 농협 NHCARD 0800/0810은 별도 호환 배치에서 실제 전송일시·추적번호·관리코드를 복구하며 fallback입니다. 정상 거래 구간/문서 뒤 rest 정책은 유지합니다.

SOURCE_FILE_IDENTITY.json은 같은 BC 원본을 삼성/BC로 각각 지정했을 때의 재현 결과, NH_NETWORK_SOURCE_REGRESSION.json은 농협 원문과 복구 값의 대조 결과입니다. 원문·카드번호를 이 안내나 보고서에 넣지 않았습니다.
