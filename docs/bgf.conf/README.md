# bgf.conf — Ruby · JSON 신규 규격 추가 가이드

**2026-09-09 · Ruby/JSON 네 파일에 집중 · bgf.conf 제어 방법은 제외**

> **먼저 아래 표에서 내 상황 한 줄만 고르세요.** 예시는 ‘열 파일 → Ctrl+F 검색어 → 붙일 위치 → 수정 전/후 → 결과’ 순서입니다. Q99, PTX, ZZNEW01, GCHND_0999_A01과 자리수는 **학습용 가정**입니다. 실제 신규 규격서와 요청·응답 원문을 확인한 뒤 바꾸세요. 예제를 운영에 일괄 추가하지 마세요.

## 1. 내가 수정할 파일부터 고르기

| 새 로그의 변화 | 수정할 곳 | 예시 |
|---|---|---|
| 기존 FS 업체와 구조 동일, 경로만 추가 | FS JSON routes | 4 |
| BGF 폰타처럼 코드만 추가, 모든 위치 동일 | detail JSON 기존 rule | 5 |
| NICE 필드 위치·길이 변경 | detail JSON 새 schema + rule | 6 |
| 사설포스 버전·규격 추가 | detail JSON versions + schemas + rules | 7 |
| 통합 전문 3자리 TAG 추가 | detail JSON tag_specs | 8 |
| FS 기존 분기에 필드 하나 추가 | FS JSON 해당 mapping | 9 |
| SK FS 기존 처리에 거래코드 추가 | FS JSON sk 정규식 | 10 |
| 완전히 새로운 FS 구조 | FS JSON + FS Ruby 분기/함수 | 11 |
| 가변길이 영역 추가 | detail JSON dynamic, 미지원 구조는 Ruby | 12 |
| detail 숫자·날짜 타입 변경 | detail JSON common_field_types | 13 |

**일상 수정은 JSON부터 확인합니다.** Ruby는 JSON을 읽는 처리기입니다. JSON이 표현할 수 없는 분리 방식·조건·헤더 구조가 생기면 Ruby 수정이 필요합니다.

## 2. 네 파일을 이렇게 나눠 보세요

| 파일 | 비유 | 내가 주로 볼 부분 |
|---|---|---|
| nice_pos_detail_specs.json | 고정길이/TAG 규격표 | merchants → schemas/rules, tag_specs |
| nice_pos_detail_parser.rb | 규격표를 읽는 처리기 | register → filter → parse 함수 |
| nice_pos_fs_specs_.json | FS 업체·필드 대응표 | routes, mappings, sk |
| nice_pos_fs_parser_.rb | 업체 선택·조건 처리기 | case vendor → parse_gsx/sk/soil |

첨부 FS 파일명 끝에는 밑줄(_)이 있고 실제 설정이 참조하는 이름에는 없습니다. 아래 명령 예시는 밑줄 없는 실행 파일명 기준입니다. 이 문서는 첨부 Ruby/JSON 내용을 기준으로 설명합니다.

~~~mermaid
flowchart TD
  A["detail JSON"] --> B["schemas: 어디서 읽나"]
  A --> C["rules: 언제 이 규격인가"]
  B --> D["detail Ruby: choose_schema → 추출"]
  C --> D
  E["FS JSON"] --> F["routes: 어느 업체인가"]
  E --> G["mappings: 어디로 복사하나"]
  F --> H["FS Ruby: case → 업체 함수"]
  G --> H
~~~

## 3. JSON과 Ruby를 왕복해서 찾는 법

| 하고 싶은 일 | JSON에서 Ctrl+F | Ruby에서 Ctrl+F | 연결 |
|---|---|---|---|
| NICE 코드 추가 | "ponta_integrated" | def parse_nice | rule로 schema 선택 |
| 새 고정 위치 | "schemas" 안 해당 규격 ID | def extract_compiled_fields | start/length로 추출 |
| 새 사설 버전 | "versions" | def private_message? | 등록 버전 여부로 사설 판정 |
| 새 TAG | "tag_specs" | def append_integrated_value | TAG의 방향별 key로 저장 |
| FS 새 업체 경로 | "routes" | def vendor_for | 경로 포함 문자열로 업체 반환 |
| FS 공통필드 복사 | "gsx_normal_response" | 같은 문자열 | copy_map으로 그 그룹 사용 |
| FS SK 코드 목록 | "request_amount_trades" | 같은 문자열 | 정규식에 맞으면 처리 |

**검색어는 줄 번호보다 오래 유지됩니다.** JSON에서 그룹을 찾은 뒤 Ruby에서 같은 그룹 이름을 검색하면 “언제 이 설정을 사용하는지”가 보입니다. mappings를 추가만 하고 Ruby가 copy_map으로 호출하지 않으면 실행되지 않습니다.

**방향은 주의:** FS는 IN=request, OUT=response입니다. detail 고정길이·사설은 message_type을 우선 사용하며, 미지정 코드에서는 OUT=request, IN=response로 보완합니다. 통합 TAG는 S=request, R=response를 우선합니다.

## 4. 기존 FS 업체와 동일한 새 경로 — routes만 수정

**열 파일:** FS JSON · **Ctrl+F:** "routes"

가정: GCHND_0999_A01이 GSX와 필드 순서·헤더·조건까지 동일합니다. gsx 배열 마지막에 새 경로를 추가합니다.

~~~diff
-      "GSC_0299_A01"
+      "GSC_0299_A01",
+      "GCHND_0999_A01"
~~~

**연결되는 Ruby:** vendor_for가 경로에 포함된 문자열을 찾아 "gsx"를 반환하고, case vendor에서 parse_gsx를 호출합니다. 동일 규격이므로 새 함수와 mapping은 필요 없습니다. routes는 앞에서 먼저 일치한 업체를 선택하므로 여러 업체에 같은 경로를 등록하지 마세요.

이 설명은 해당 이벤트가 FS Ruby까지 들어온 상태를 전제로 합니다. 파이프라인 경로 관리는 사용자가 담당하는 범위입니다.

## 5. 실제 BGF 폰타 rule에 코드 하나 추가

**열 파일:** detail JSON · **Ctrl+F:** "ponta_integrated"  
**위치:** nice_fixed → merchants → bgf_ponta → rules

현재 PTS/PTE/PTC는 schema 21을 사용합니다. **새 PTX도 전체 필드 위치·길이가 같다고 확인한 경우**:

~~~diff
             "text": [
               "PTS",
               "PTE",
-              "PTC"
+              "PTC",
+              "PTX"
             ]
~~~

**수정 후 text 배열:**

~~~json
"text": ["PTS", "PTE", "PTC", "PTX"]
~~~

schema 21과 fields, Ruby는 그대로입니다.

| 실제 schema 21 필드 | start | length | 범위 |
|---|---:|---:|---|
| Member_Id | 56 | 30 | 56~85 |
| 파트너코드 | 86 | 6 | 86~91 |
| display_message | 731 | 100 | 731~830 |

**기대 결과:** nice_pos.text_code는 PTX, format은 기존 BGF 폰타 규격명, Member_Id 등은 기존 위치에서 추출됩니다.

**위치가 다르면 코드만 추가하지 마세요.** 정상 rule은 바로 schema를 적용하므로 잘못된 규격도 값처럼 잘립니다. 이 rule은 text만 조건이므로 새 코드의 거래종류·요청·응답 변형 모두 확인해야 합니다.

## 6. 새 NICE 고정길이 규격 — JSON 한 블록

**열 파일:** detail JSON · **Ctrl+F:** _INSERT_NEW_NICE_MERCHANT_BELOW

마커 객체가 끝나는 닫는 중괄호·쉼표 **바로 다음**, 기존 "gongju_currency" **바로 앞**에 아래 블록을 넣습니다. 마커 내부 schemas에 넣는 것이 아닙니다.

학습용: 기존 NICE 헤더 55자리, text Q99, trade 01, message_type 0200, 전체 73자리.

| 영역 | 위치 | 길이 | 값 |
|---|---:|---:|---|
| 기존 헤더 | 1~55 | 55 | 길이·코드·CAT-ID 등 |
| transaction_amount | 56~67 | 12 | 000000012300 |
| installment_months | 68~69 | 2 | 00 |
| campaign_code | 70~73 | 4 | AB12 |

**추가할 블록 — 뒤에 기존 merchant가 있으므로 마지막 쉼표 포함:**

~~~json
      "example_new_nice": {
        "schemas": {
          "example_q99_request_v1": {
            "name": "교육용 Q99 요청 v1",
            "direction": "request",
            "fields": [
              {"key": "transaction_amount", "start": 56, "length": 12},
              {"key": "installment_months", "start": 68, "length": 2},
              {"key": "campaign_code", "start": 70, "length": 4}
            ]
          }
        },
        "rules": [
          {
            "id": "example_q99_request_v1",
            "schema": "example_q99_request_v1",
            "when": {
              "text": ["Q99"],
              "trade": ["01"],
              "message_type": ["0200"],
              "direction": ["request"],
              "message_length": ["0073"]
            },
            "priority": 1000
          }
        ]
      },
~~~

이는 부모 객체에 넣는 **JSON 조각**입니다. 단독 JSON 파일이 아닙니다.

**기대 출력 일부:**

~~~json
{
  "parser_type": "nice_fixed",
  "format": "교육용 Q99 요청 v1",
  "direction": "request",
  "message_length": 73,
  "text_code": "Q99",
  "detail": {
    "transaction_amount": 12300,
    "installment_months": 0,
    "campaign_code": "AB12"
  }
}
~~~

| 설정 | 의미 | 실수 방지 |
|---|---|---|
| schemas 내부 ID | 내부 규격 이름 | 다른 merchant와도 중복 금지 |
| rule의 schema | 위 내부 ID 연결 | 철자 정확히 일치 |
| schema의 name | 출력 format | ID와 구분 |
| fields의 key | detail 안 출력 이름 | 기존 공통필드와 이름 맞추기 |
| start | 전문 첫 자리부터 **1 시작** | [OUT]·외부 괄호는 제외 |
| length | 읽을 길이 | 다음 start는 보통 start+length |
| when의 text | 헤더 text_code 조건 | text_code라고 쓰지 않기 |
| message_length | 헤더 4자리 문자열 조건 | "73"이 아닌 "0073" |
| priority | **작은 숫자 우선** | 자세한 조건이 자동 우선은 아님 |

when 생략·빈 배열은 임의 일치입니다. merchant명·파일경로로 rule이 격리되지 않습니다. NICE 전체 merchant의 규칙을 합쳐 조회합니다. 예시 priority 1000은 경쟁 없는 학습용 값이며, 기존 광범위 rule과 겹치면 선택되지 않을 수 있습니다. 겹치는 조건과 우선순위를 함께 확인하세요.

**자리 계산:** ASCII 1, 비ASCII 문자 2로 계산하는 Ruby입니다. UTF-8 실바이트 수와 다릅니다. 한글 중간에 경계를 두지 말고 원문과 규격서의 문자코드 전제를 확인하세요. fields는 start 오름차순, 범위 중복·전문 길이 초과도 직접 확인합니다.

**응답 추가:** 응답용 schema/rule을 별도로 만들고 message_type/direction을 변경합니다. NICE response_code는 기본 56번부터 4자리이며 schema의 response_code_start로 변경 가능합니다. schema direction이 both면 이 경로의 응답코드 자동 추출은 생략되므로 both를 무조건 재사용하지 마세요.

## 7. SK / S-OIL 사설포스 추가

**열 파일:** detail JSON · **Ctrl+F:** _INSERT_NEW_PRIVATE_MERCHANT_BELOW

| 상황 | 수정 위치 |
|---|---|
| SKOIL과 헤더·모든 거래 레이아웃 동일, 버전만 신규 | sk_private_pos → versions 마지막 |
| 새 버전의 레이아웃이 다름 | 마커 다음 새 merchant에 versions + schemas + rules |
| 헤더 위치 자체가 다름 | Ruby의 private_message?, @private_header_fields, parse_private 검토 |

**새 버전·새 레이아웃 교육용 블록:** 마커 객체 다음, sk_private_pos 앞에 추가합니다.

~~~json
      "example_private": {
        "versions": ["ZZNEW01"],
        "schemas": {
          "example_private_request": {
            "name": "교육용 사설 요청",
            "direction": "request",
            "fields": [
              {"key": "transaction_amount", "start": 48, "length": 12}
            ]
          }
        },
        "rules": [
          {
            "id": "example_private_request",
            "schema": "example_private_request",
            "when": {
              "trade": ["01"],
              "message_type": ["0200"],
              "direction": ["request"]
            },
            "priority": 1000
          }
        ]
      },
~~~

**가정:** 기존 사설 헤더 구조 그대로, 버전은 5~11번 7자리, type 32~35번, trade 36~37번, CAT-ID 38~47번, 금액 48~59번. 기대 parser_type은 private_fixed, 금액 문자열 000000012300은 12300입니다.

versions를 빠뜨리면 private로 판별되지 않고 NICE 쪽으로 갑니다. when.version 생략 시 해당 merchant의 versions가 자동 적용됩니다. **기존 버전을 새 merchant에 중복 등록하면 기존 포괄 rule과 충돌**할 수 있습니다. SK 기본 요청 priority 4, 기본 응답 5 같은 기존 rule도 확인하세요. private은 message_length로 rule을 선택하지 않습니다.

사설 응답 response_code는 Ruby에서 48번부터 4자리로 고정입니다. 사설 JSON에 response_code_start만 넣어서는 바뀌지 않습니다. IC 세부 필드는 private_fixed → ic_schemas이며 start는 전체 전문이 아니라 **추출된 IC데이터 내부 1번** 기준입니다.

## 8. 통합 TAG 하나 추가 — 위치 계산 대신 TAG 이름

**열 파일:** detail JSON · **Ctrl+F:** _INSERT_NEW_TAG_BELOW  
**위치:** integrated_tag → tag_specs → 마커 객체 다음, A01 앞

새 일반 TAG Q99가 쿠폰코드를 담는다는 가정입니다.

~~~json
      "Q99": {
        "request": {"key": "coupon_code", "attribute": "A/N", "max_length": 12},
        "response": {"key": "coupon_code", "attribute": "A/N", "max_length": 12}
      },
~~~

| 원문 일부 (표시용) | 해석 | 출력 |
|---|---|---|
| Q99ABC123〈FS〉 | TAG Q99 + 값 ABC123 | detail.coupon_code = "ABC123" |
| Q99ABC123〈FS〉Q99XYZ〈ETX〉 | 같은 TAG 반복 | detail.coupon_code = ["ABC123", "XYZ"] |

〈FS〉는 실제 0x1C, 〈ETX〉는 0x03이며 그 글자를 입력하는 것이 아닙니다. 통합 파서는 STX와 4자리 숫자로 판별하고 기본 TAG 영역은 61번부터입니다.

request/response 대신 both도 코드상 지원됩니다. 등록되지 않은 일반 TAG는 출력하지 않습니다. **max_length·attribute는 현재 읽는 길이의 강제 검증 값이 아닙니다.** 실제 값은 FS/ETX까지 읽습니다.

P/Z로 시작하는 특수 TAG는 4자리 길이 + 1자리 추가 구분영역을 고려하는 별도 처리입니다. 새 접두사가 정확히 동일한 길이 규칙이라면 special_prefixes 추가를 검토할 수 있지만, 일반 TAG를 P/Z 이름으로 임의 등록하면 같은 뜻이 아닙니다. 다른 길이 체계는 parse_integrated_tags 수정 대상입니다.

## 9. FS 필드 하나 추가 — com_N을 먼저 세기

**FS 분리 공식: 첫 조각은 com_9, 두 번째 com_10, N번째 com_(N+8).**

| 표시용 본문 | 조각 순서 | 결과 |
|---|---:|---|
| HEADER〈FS〉1234567890〈FS〉〈FS〉0000012300 | 1 | com_9 = HEADER |
| 동일 본문 | 2 | com_10 = 1234567890 |
| 동일 본문 | 3 (빈 값) | com_11은 생성 안 됨, **번호는 차지** |
| 동일 본문 | 4 | com_12 = 0000012300 |

Ruby가 SOH/STX를 제거하고 0x1C를 분리자로, 0x1F를 /로 바꾼 뒤 나눕니다. 빈 칸을 빼고 번호를 세면 뒤 필드가 모두 틀립니다. FS 처리 후 b_body는 배열로 바뀌며 com_N은 현재 삭제되지 않습니다.

**열 파일:** FS JSON · **Ctrl+F:** "gsx_normal_response"

가정: 기존 일반 응답의 조건은 그대로이고 com_83이 새 쿠폰코드입니다. 해당 mapping 마지막에 추가:

~~~diff
-      "com_72": "[nice_pos][detail][service_charge]"
+      "com_72": "[nice_pos][detail][service_charge]",
+      "com_83": "[nice_pos][detail][coupon_code]"
~~~

**결과:** 기존 GSX 일반 응답 분기에 들어간 이벤트만 coupon_code를 갖습니다. 현재 그 분기는 OUT, com_49의 10자리 CAT-ID, com_48 숫자, com_82 존재를 확인합니다. **그 판정 필드 자체가 이동했다면 JSON 매핑만 바꾸면 안 됩니다.** Ruby parse_gsx의 조건도 함께 수정하거나 새 규격으로 분리하세요.

숫자 변환 후처리도 필요하면 13번을 함께 봅니다. 한 mapping에 동일 com_N 키를 두 번 쓰지 마세요. 같은 원본을 두 대상으로 복사하려면 Ruby copy_field 등을 사용해야 합니다.

## 10. SK FS 거래코드 추가 — 같은 레이아웃일 때만

**열 파일:** FS JSON · **Ctrl+F:** "request_amount_trades"

가정: 새 코드 T1의 요청 금액도 com_13이고 기존 금액 처리와 같습니다.

~~~diff
-    "request_amount_trades": "^(?:[DdVvFfGg][125]|[HhKk][1-5]|[MmJj][34]|PA|PC)$",
+    "request_amount_trades": "^(?:[DdVvFfGg][125]|[HhKk][1-5]|[MmJj][34]|PA|PC|T1)$",
~~~

| JSON 항목 | 추가하면 켜지는 동작 | 먼저 확인할 원문 위치 |
|---|---|---|
| request_amount_trades | IN 금액, / 있으면 금액·세금 분리 | com_13 |
| installment_trades | IN 할부 | com_12 |
| cancel_trades | IN 원승인번호 | com_14 |
| common_response_trades | OUT 공통 응답 매핑·날짜·발급사 처리 | sk_common_response 및 com_14/com_18 |
| hk_response_trades | OUT HK 응답 매핑·날짜 | sk_hk_response 및 com_14 |

필요한 항목만 추가합니다. 승인 코드를 cancel_trades까지 넣으면 com_14가 원승인번호로 잘못 복사될 수 있습니다. T1 추출은 com_9 안의 “T1=” 형태 등 기존 코드 추출 방식도 맞아야 합니다.

표현식의 |는 “또는”, [125]는 1/2/5 중 하나입니다. 전체 정규식을 새 코드로 덮지 말고 기존 목록 끝에 대안을 추가하세요.

## 11. 완전히 새로운 FS 업체 — JSON 두 곳 + Ruby 두 곳

교육용 업체명 test, 경로 GCHND_0999_A01. **이 함수는 경로 내 모든 IN/OUT 로그가 아래 한 종류의 구조라는 가정**입니다. 여러 규격이 섞이면 코드·길이 조건을 더 넣어야 합니다.

### ① FS JSON routes의 soil 다음에 test 추가

~~~diff
     "soil": [
       "GCHND_0216_A01"
-    ]
+    ],
+    "test": ["GCHND_0999_A01"]
~~~

### ② FS JSON mappings 시작 중괄호 다음에 두 그룹 추가

~~~json
    "test_request": {
      "com_10": "[nice_pos][cat_id]",
      "com_11": "[nice_pos][trade_code]",
      "com_12": "[nice_pos][detail][transaction_amount]",
      "com_13": "[nice_pos][detail][installment_months]"
    },
    "test_response": {
      "com_10": "[nice_pos][cat_id]",
      "com_11": "[nice_pos][response_code]",
      "com_12": "[nice_pos][detail][approval_number]"
    },
~~~

### ③ FS Ruby · Ctrl+F case vendor · soil 다음에 두 줄

~~~ruby
  when "soil"
    parse_soil(event, status)
  when "test"
    parse_test(event, status)
~~~

기존 case의 end **앞**에 추가합니다. when을 함수 바깥에 붙이지 마세요. JSON의 test와 Ruby의 "test"는 같아야 합니다.

### ④ FS Ruby 맨 아래에 함수 추가

~~~ruby
def parse_test(event, status)
  if status == "IN"
    copy_map(event, "test_request")
  elsif status == "OUT"
    copy_map(event, "test_response")
  end
end
~~~

아래쪽에 있는 주석 예시와 비슷하지만, 위 코드는 앞에 #가 없는 **실행 코드**입니다. parse_soil 함수 내부가 아니라 그 함수가 끝난 뒤에 붙입니다.

| 입력 (Ruby filter에 들어갈 시점) | 기대 출력 일부 |
|---|---|
| path가 GCHND_0999_A01 포함, status IN | direction=request |
| b_body = HEADER〈FS〉1234567890〈FS〉T1〈FS〉0000012300〈FS〉00 | cat_id="1234567890", trade_code="T1", 금액=12300, 할부=0 |
| 같은 경로, status OUT | direction=response |
| b_body = HEADER〈FS〉1234567890〈FS〉0000〈FS〉APR00001 | response_code="0000", approval_number="APR00001" |

위 금액·할부 숫자는 기존 파이프라인 후처리까지 거친 결과이며, **FS Ruby 단독 출력에서는 "0000012300", "00" 문자열**입니다. FS는 현재 parser_type·format을 자동 생성하지 않습니다.

### Ruby를 읽을 때 이 다섯 줄만 먼저 이해하세요

| 코드 | 하는 일 |
|---|---|
| when "test" | routes가 test로 판정한 로그 선택 |
| parse_test(event, status) | 아래 정의한 함수 실행 |
| status == "IN" | FS 요청 선택 |
| copy_map(event, "test_request") | JSON의 그 이름 매핑 일괄 복사 |
| end | if/case/함수의 끝 |

route 이름과 함수 호출만 추가하고 함수 정의를 빠뜨리면 오류가 납니다. mapping 이름이 다르면 fetch에서 오류가 납니다. 현재 FS filter에는 detail처럼 자체 rescue/운영태그 정규화가 없으므로 Ruby 플러그인 오류도 확인하세요.

## 12. 고정 영역 뒤 가변 데이터 추가

**열 파일:** detail JSON · **위치:** 해당 schema 안, fields와 같은 깊이에 dynamic_start/dynamic 추가

학습용: 6번의 73자리 뒤에 “003ABC”를 붙이고 전체 길이가 79가 된 별도 버전입니다. **새 schema로 복제**하고 rule의 schema·message_length를 새 규격에 맞춥니다.

~~~json
"dynamic_start": 74,
"dynamic": [
  {
    "type": "length_prefixed",
    "length_size": 3,
    "length_key": "extra_length",
    "key": "extra_data"
  }
]
~~~

| 위치 | 내용 | 읽는 방법 |
|---|---|---|
| 74~76 | 003 | 다음 데이터 길이는 3 |
| 77~79 | ABC | detail.extra_data = "ABC" |

이 조각은 fields 배열이 끝난 뒤 쉼표를 넣어 연결합니다. extra_length는 별도 타입 등록이 없으면 "003" 문자열입니다.

| 이미 구현된 일반 type | 용도 | 주요 설정 |
|---|---|---|
| fixed | 현재 위치부터 고정 길이 | key, length |
| length_prefixed | 길이값 후 데이터 | length_size, length_key, key |
| conditional_length_prefixed | 앞 값이 조건과 같을 때 위 처리 | when_key, equals + 위 항목 |
| length_from_previous | 이미 추출한 길이 사용 | length_key, key |
| conditional_remaining | 조건 일치 시 끝 일부 제외하고 나머지 | when_key, equals, tail_length, key |
| remaining | 남은 전문 전체 | key |

nice_common_request_tail, nice_royalty_ic_tail, nice_cash_ic_tail, nice_ifc_members도 구현되어 있지만 해당 NICE 특수 규격 전용입니다. 임의의 가변 구조에 이름만 재사용하지 마세요.

Ruby의 **Ctrl+F: def parse_dynamic_fields**에서 지원 여부를 찾을 수 있습니다. 새 type 이름을 JSON에만 적으면 처리되지 않습니다. 현재 case에는 미지원 type에 대한 명시적 오류 처리도 없으므로 “오류가 없다”가 성공은 아닙니다.

## 13. detail 공통 타입 — key 이름과 types 연결

**열 파일:** detail JSON · **Ctrl+F:** "common_field_types"

새 reward_amount를 fields/TAG로 추출했다면 types 마지막 항목에 쉼표를 넣고 아래 속성을 추가합니다.

~~~json
"detail.reward_amount": "long"
~~~

| JSON 설정 | 실제 효과 |
|---|---|
| fields의 key 또는 TAG의 key | 필드 값 생성 |
| common_field_types.types | 최종 값에 숫자·날짜 변환 |
| request_fields/response_fields | 설명 목록, 타입 적용 범위를 제한하지 않음 |
| keyword/text_keyword | 문자열 유지, Elasticsearch 매핑을 생성하지 않음 |
| FS numeric_fields | **현재 FS Ruby에서 읽지 않음** |

types에 이름만 추가하면 필드가 생기지 않습니다. detail Ruby의 load_common_field_types가 타입 목록을 읽고 apply_common_field_types!가 적용합니다. 숫자 문자열 "0000012300"은 12300, 잘못된 숫자·범위 초과는 nil이 될 수 있습니다. CAT-ID·승인번호·응답코드는 앞자리 0을 보존하도록 문자열을 유지하세요.

detail 날짜는 14자리·12자리와 ISO 형식을 처리하며 12자리는 YYMMDDHHMMSS를 먼저 시도합니다. 새 형식이 지원되지 않으면 normalize_common_datetime이 Ruby 수정 위치입니다. FS의 타입 후처리는 네 파일 밖의 기존 운영 설정 범위입니다.

## 14. 네 파일 수정 후 확인할 것

**JSON은 register에서 한 번 읽습니다. 저장만으로 실행 중인 규격이 바뀌지 않으므로 실제 파서 재로딩 여부를 확인하세요.**

| 확인 | 합격 기준 |
|---|---|
| JSON 문법 | 쉼표·괄호 오류 없음 |
| schema ID | 전체 같은 계열 merchant 안에서 유일, rule 참조와 일치 |
| rule 조건 | 신규 샘플 선택, 기존 rule과 충돌 없음 |
| start/length | 오름차순, 겹침·범위 초과 없음 |
| FS mapping | Ruby가 해당 이름으로 copy_map 호출 |
| FS 분기 조건 | 옮긴 필드가 조건에도 쓰였는지 확인 |
| 신규 요청·응답 | 원문의 금액·코드·날짜와 결과 일치 |
| 기존 승인·취소 | 변경 전과 동일 |
| 중간 빈 FS·한글 고정길이 | 번호·위치 밀림 없음 |

네 파일을 작업 폴더의 schema 디렉터리에 두었을 때 실행할 수 있는 문법 검사:

~~~bash
python3 -m json.tool schema/nice_pos_detail_specs.json > /dev/null
python3 -m json.tool schema/nice_pos_fs_specs.json > /dev/null
ruby -c schema/nice_pos_detail_parser.rb
ruby -c schema/nice_pos_fs_parser.rb
~~~

JSON 명령 종료코드 0, Ruby Syntax OK가 문법 합격입니다. 실제 파싱 정확성까지 보장하지 않습니다. JSON에는 // 주석을 넣지 말고, 같은 키를 중복 작성하지 마세요. 백업 사본과 테스트 환경에서 신규·기존 샘플을 비교한 뒤 사용하세요.

## 15. 값이 안 나올 때 빠른 진단

| 증상 | 먼저 찾을 곳 |
|---|---|
| nice_pos 없음 | FS routes, private rule, detail wrapper |
| FS direction만 있고 상세 없음 | 업체 함수 분기 조건 / mapping 이름 |
| FS 값이 한 칸씩 밀림 | 중간 빈 FS 조각을 빼고 세었는지 |
| format UNKNOWN 또는 fallback | NICE rule의 text/trade/type/direction/길이 |
| 숫자만 null 또는 누락 | 값이 실제 정수인지·범위·타입 key |
| JSON 고쳤는데 결과 동일 | 실제 spec_path / 재로딩 여부 |
| rule 추가 후 기존 값 변화 | 조건 중첩, 작은 priority, 공유 schema 수정 |
| error 없음에도 잘못된 값 | 원문 대조 — 정상 rule은 완전성 검사 전에 적용될 수 있음 |

detail 내부 _nice_pos_* 태그는 후처리에서 대부분 제거되고 운영용 fallback/error로 정리됩니다. **fallback은 정식 규격 등록 완료가 아닙니다.** error가 없다는 것도 모든 필드 정확성 보장이 아닙니다. private의 rule 미일치와 미등록 TAG 등은 상세값 없이 끝날 수 있습니다. FS에는 이 detail 전용 태그 처리를 그대로 기대하지 마세요.

## 16. Ruby 수정이 정말 필요할 때 찾을 함수

| 바뀐 구조 | 파일 / Ctrl+F | 수정 영향 |
|---|---|---|
| 외부 괄호·접두사 | detail / def extract_professional | 모든 detail 입력 |
| NICE 헤더 위치 | detail / @nice_header_fields | NICE 판정·필드 추출 |
| 사설 버전 위치 | detail / def private_message? 및 @private_header_fields | 사설 판정과 헤더 모두 |
| 새 가변 처리 방식 | detail / def parse_dynamic_fields | 해당 type |
| 통합 TAG 분리·길이 체계 | detail / def parse_integrated_tags | 통합 TAG 전체 |
| 요청·응답 코드 체계 | detail / def professional_direction | 고정길이·사설 방향 |
| FS 제어문자·분리 방식 | FS / parts = cleaned.split | 모든 FS 업체 |
| 새 FS 업체 | FS / case vendor 및 새 parse 함수 | 해당 vendor |
| 기존 업체 헤더·분기 | FS / def parse_gsx, def parse_sk, def parse_soil | 해당 업체 |

이 범위는 임의 복붙으로 끝낼 수 없습니다. 새 원문·필드 정의·기존 회귀 샘플을 확보한 뒤 해당 함수만 좁혀 수정하세요. 그 외 평소 추가는 앞의 JSON 예시를 먼저 적용합니다.

---

**작성·검증 범위:** 첨부 설정 및 Ruby가 실제로 읽는 키와 분기를 기준으로 작성했습니다. 원본 Ruby/JSON을 임의 리팩터링하지 않았습니다. 이 작업 환경에는 Ruby/Logstash 실행기가 없어 실제 Ruby 실행·운영 전문 재생 검증은 수행하지 못했습니다. JSON 구조, 예시 위치·길이, rule 연결은 정적 확인 대상입니다. 신규 규격서·실제 신규 로그는 제공되지 않아 예시는 교육용입니다.
