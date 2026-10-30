# 카드 전문 수집 인코딩 수정 안내

> **이 문서는 이전 FINAL10 기준의 안내다.** 사용자가 Filebeat euc-kr 유지를 선택한 현재 FINAL12의 적용 방법은 [새 적용 안내](APPLY_GUIDE_FINAL12.md)를 따른다. FINAL12는 FINAL11의 파싱 결과를 유지하면서 반복 처리를 간소화했다. CP949 역변환과 손실 접두부 fallback을 지원하고 삼성 MS 실로그를 검증했다. 아래의 Filebeat 변경 지침을 FINAL12 구성에 그대로 적용하지 않는다.

확인일: 2026-10-30. 대상 파서: `2026-10-18.final10`.

## 원인

국민 MS 사진의 버전은 final10, 프로필은 kb_ms이며 오류 검색 결과는 28,907건이다. 사용자가 확인한 Filebeat 입력은 `encoding: euc-kr`이고 오류 원인 중 하나는 `input_encoding_not_reversible`이다.

현행 RB는 수신 문자열을 ISO-8859-1로 역변환해 원본 바이트를 복원한다. Filebeat가 EUC-KR로 한글을 디코딩하면 ISO-8859-1로 되돌릴 수 없어 역변환 실패가 발생한다. 추가로 제공 원문에는 EUC-KR 문자가 아닌 바이트 구간도 섞여 있다. 수집 중 해당 구간이 U+FFFD로 치환되면 RB는 `lossy_input_encoding`으로 감지한다. 이 경우 RB만 CP949로 바꿔도 원본 바이트를 복구할 수 없다.

## 국민 MS 71,302건 비교 재생

실제 Logstash 8.17.6 Event/JRuby를 사용했다. EUC-KR 경로는 Filebeat의 euc-kr과 같은 CP949 계열 디코딩 및 잘못된 바이트의 U+FFFD 치환을 모의한 것이며, Filebeat를 직접 실행한 종단 간 시험은 아니다.

| 수집 문자열 생성 / RB 역변환 | ok | fallback | error |
|---|---:|---:|---:|
| EUC-KR 호환 디코딩 / 현행 ISO-8859-1 RB | 39,194 | 3,201 | 28,907 |
| EUC-KR 호환 디코딩 / CP949로만 바꾼 RB | 46,466 | 8,406 | 16,430 |
| ISO-8859-1로 바이트 보존 / 현행 RB | 62,004 | 9,291 | 7 |

첫 번째 경로는 역변환 실패 12,477건, 대체 문자 손실 감지 16,423건, 기존 구조/마스킹 오류 7건이다. 합계 28,907건이 사진의 건수와 일치한다. ISO-8859-1 경로의 원문 바이트 왕복 불일치는 0건이었다. 이는 제공 자료에 대한 결과이며 앞으로의 모든 로그에서 오류가 7건이라는 보장은 아니다.

## 적용할 변경

카드 전문을 읽는 기존 Filebeat input에서 한 값만 변경한다.

```yaml
# 변경 전
encoding: euc-kr

# 변경 후: 카드 전문의 원본 바이트 보존
encoding: iso8859-1
```

RB·JSON은 기존 final10을 유지한다. Ruby script_params에도 CP949/EUC-KR을 추가하지 않는다. 현재 RB의 기본값 ISO-8859-1과 수집 인코딩을 일치시키는 변경이다.

같은 input에서 일반 한글 로그나 다른 업무 로그도 수집한다면 카드 전문 경로만 전용 input으로 분리해 적용한다. 기존 input과 새 input의 paths가 같은 파일을 중복 수집하지 않도록 한다. input 유형·multiline·라우팅 fields·output 등은 이번 인코딩 변경만으로 교체하지 않는다.

이 방식의 message는 한글 표시보다 원본 바이트 보존을 위한 값이다. 한글이 다르게 보일 수 있으며 사람이 읽을 한글은 파싱 후 해당 필드 구간에서 별도로 디코딩해야 한다. 원본 전문 파일 자체는 변경하지 않는다.

## 재시험

1. 실제 Filebeat 환경에서 설정 구문 검사를 수행한다.
2. 원본의 소량 복사본을 별도 테스트 파일/인덱스로 수집한다. 파일 경로의 국민 MS 라우팅 조건은 유지한다. 기존 registry 전체를 삭제할 필요는 없다.
3. 새 이벤트에서 `profile=kb_ms`, `parser_version=2026-10-18.final10`과 두 인코딩 오류의 발생 여부를 확인한다.
4. 이미 저장된 오류 이벤트는 설정 변경으로 소급 수정되지 않는다. U+FFFD로 손실된 이벤트는 원본 파일에서 다시 수집해야 한다.

## 다른 미해결 범위

삼성 MS는 실제 로그가 없어 비활성이다. 과거 win_ms는 bcc_ms와 동일한 BC MS 자료였다. 인코딩 수정이 삼성 MS의 미검증 규격을 해결하지는 않는다. 기존 535건에는 농협 DE118 예약 영역/DE124 위치 문제와 마스킹된 길이 정보 문제도 따로 남아 있다.

## 근거

- Filebeat 8.17 입력 인코딩: https://www.elastic.co/guide/en/beats/filebeat/8.17/filebeat-input-log.html#_encoding
- Filebeat v8.17.6 구현: https://github.com/elastic/beats/blob/v8.17.6/libbeat/reader/readfile/encoding/encoding.go (`iso8859-1`은 charmap.ISO8859_1에 직접 연결)
- Go Korean 디코더: https://pkg.go.dev/golang.org/x/text/encoding/korean (EUC-KR/Code Page 949)
