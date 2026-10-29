# Logstash 최종 필터 설명과 괄호 배치

기준일: 2026-10-29. [전체 설정](digital.conf) · [적용 가이드](GUIDE.md)

## 1. 현재 필터 구성

1. 원본 log.file.path에 epay 포함 여부 확인.
2. OUTBOUND REQUEST DATA / OUTBOUND RESULT TO JSON DATA 마커만 파싱.
3. grok으로 시간·레벨·로거·status·공통 헤더와 URL/본문을 분리.
4. date로 log_timestamp 자체를 날짜로 변환. @timestamp는 유지.
5. 요청은 kv → request_data, 응답은 json → result_data.
6. 해당 경로의 일반 로그만 drop. 대상의 파싱 실패 이벤트는 태그와 message 유지.
7. 파일 조건이 불일치하면 기존 VAN else if로 이어짐.

필터와 Elasticsearch output의 경로 조건은 반드시 같은 실제 원본을 가리켜야 합니다. 설정 파일명 digital.conf는 log.file.path와 무관합니다.

## 2. 헷갈렸던 괄호

아래는 배치 설명용 축약 코드입니다. 실제 전체 파일을 대체하는 설정은 아닙니다.

~~~logstash
filter {                                      # FILTER 열기
    if [log][file][path] =~ /epay/ {           # FILE 열기
        if [message] =~ /OUTBOUND/ {           # MESSAGE 참 분기 열기
            # 실제 파싱
        } else {                              # 참 분기 닫고 else 열기
            drop {}
        }                                     # else 닫기, MESSAGE if/else 완료
    }                                         # FILE 닫기

    else if [message] =~ /RECV VAN MSG|SEND VAN MSG/ {
        # 기존 VAN
    } else {
        drop {}
    }

    # 기존 공통 처리
}                                             # FILTER 닫기
~~~

파일 조건과 메시지 조건을 하나의 괄호로 닫는 것이 아닙니다. MESSAGE의 참 분기는 "} else {"의 앞쪽 "}"에서 이미 닫혔습니다. else의 닫힘 뒤에 FILE 닫힘이 하나 더 있으며, 그 다음 기존 VAN else if가 연결됩니다. FILTER는 공통 처리 뒤에 별도로 닫힙니다.

전체 digital.conf의 주석 [MESSAGE] END, [FILE] END, [FILTER] END를 확인하세요. mutate 바로 뒤에서 FILTER를 먼저 닫고 if를 블록 밖에 놓으면 최상위 input/filter/output을 기대한다는 컴파일 오류가 납니다.

## 3. 정규식 안의 괄호는 설정 블록이 아님

~~~text
\[(?=\{)%{DATA:[@metadata][response_json]}\]?\r?$
~~~

- \[ : 실제 대괄호 문자.
- (?=\{) : 다음 문자가 중괄호인지 확인하는 정규식 lookahead. 입력을 소비하지 않음.
- \{ : 실제 중괄호 문자. Logstash 설정 블록을 여는 문법이 아님.
- %{DATA:...} : grok 패턴/필드 지정 문법.
- \]? : 표시용 닫는 대괄호가 없어도 허용.
- \r?$ : 선택적 CR 이후 메시지 끝.

이 문자열 내부의 중괄호를 설정 블록의 열림/닫힘으로 세지 마세요. 편집기의 단순 괄호 강조 때문에 실제 균형과 다르게 보일 수 있습니다.

## 4. 요청 kv 옵션

~~~logstash
target => "[request_data]"
field_split => "&"
value_split => "="
allow_empty_values => true
whitespace => "strict"
include_brackets => false
~~~

- field_split / value_split: query를 &로 나누고 =로 키·값 분리.
- allow_empty_values: A=&B=1에서 A도 빈 문자열로 보존. 원문에 없는 키를 생성하지 않음.
- whitespace strict: = 주변 공백을 관대하게 무시하지 않음. 빈 값 수집을 위해 함께 사용.
- include_brackets false: 값의 (), [], <>를 감싸는 기호라고 자동 제거하지 않음. 로그 바깥 대괄호를 제거하는 옵션은 아니며 바깥 프레임은 grok에서 분리.
- 중복 키는 kv 기본 동작에 따라 배열이 될 수 있음.
- URL 인코딩 문자열을 자동 디코딩하거나 다시 인코딩하지 않음.

## 5. JSON 대상 분리

result_data 전체를 JSON 구조로 생성합니다. 최상위 TR_ID / PARTNER_CODE를 JSON 값으로 덮어쓰지 않습니다. 중첩 객체·배열·숫자·boolean·null은 JSON 값의 구조와 타입에 따라 처리됩니다. 다만 현재 외곽 프레임은 JSON 객체 하나를 기준으로 합니다. 외곽 자체가 다중 객체 배열로 변경되는 경우는 별도 검토 대상입니다.

## 6. 날짜와 타임스탬프

date target은 log_timestamp입니다. @timestamp 복사는 의도적으로 없습니다. Elasticsearch 매핑을 수정하는 필터가 아니므로 기존 text 필드의 타입은 그대로입니다.

Kibana 시간 필드 및 output의 %{+YYYY.MM.dd} 기준은 별개입니다. 날짜 인덱스는 @timestamp를 사용합니다. 자세한 매핑 확인 방법은 [GUIDE.md](GUIDE.md)를 보세요.

## 7. 검증 수준

현재 실로그 요청 2건·응답 2건 재현 성공입니다. 실제 Logstash -t / JRuby 실행과 운영 부하 검증이 완료됐다는 의미는 아닙니다. 상태 없는 파싱이므로 이 신규 분기 때문에 workers 1을 강제할 필요는 없지만 전체 파이프라인의 다른 상태 의존 필터는 별도 확인해야 합니다.
