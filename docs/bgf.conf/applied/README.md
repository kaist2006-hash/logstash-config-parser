# BGF · 실제 설정이 들어간 가이드 사본

**먼저 START.html을 여세요.** 예시와 단계를 누르면 원본과 설정이 삽입된 사본을 해당 줄에서 비교합니다. 인터넷 연결 없이 볼 수 있습니다.

직접 파일을 보려면 files 폴더의 네 파일을 여세요. 생략 없는 전체 설정이며, 교육용 예시가 실제 코드로 들어가 있습니다.

| 검색어 | 실제 추가한 내용 |
|---|---|
| GUIDE_F04 | 새 FS 업체: JSON 경로/매핑 + Ruby 분기/함수 |
| GUIDE_F01 | 기존 GSX 구조의 새 경로 |
| GUIDE_F02 | 기존 GSX 응답 매핑에 com_83 추가 |
| GUIDE_F03 | SK 기존 금액 처리에 T1 코드 추가 |
| GUIDE_D01 | 새 NICE 요청/응답 schema + rules |
| GUIDE_D02 | 새 사설 versions + schema + rule |
| GUIDE_D03 | 새 통합 Q99 TAG |
| GUIDE_D04 | 기존 BGF 폰타 text 배열에 PTX 추가 |
| GUIDE_D05 | 고정 영역 뒤 length_prefixed 설정 |

**가장 먼저 GUIDE_F04를 보세요.** JSON에 적은 이름이 Ruby의 when과 copy_map에서 어떻게 연결되는지 네 단계로 볼 수 있습니다.

- JSON의 _GUIDE… 속성은 설명입니다. 옆에 들어간 실제 routes/schemas/rules/mappings가 실행 설정입니다. 매핑과 routes의 반복 대상 안에는 설명용 가짜 필드를 넣지 않았습니다.
- detail Ruby는 기존 JSON 지원 기능을 쓰는 예시이므로 로직을 그대로 두고 연결되는 처리 위치에 주석을 넣었습니다.
- FS Ruby의 GUIDE_F04_3/4는 새 when 분기와 함수가 실제 추가된 부분입니다.
- GUIDE_ONLY… 경로, Q99/PTX/ZGUIDE1/T1 및 자리수는 학습용 가정입니다. 운영 파일에 사본 전체를 덮어쓰지 마세요.
- FS 파일명은 첨부와 같은 밑줄(_)을 유지했습니다. 실제 적용 경로의 파일명은 별도로 맞추세요. bgf.conf는 작업 범위에서 제외했습니다.

samples/events.json에 12개 입력과 예상 필드가 있습니다. FS 예상값은 Ruby 단독 출력이므로 금액·날짜도 문자열입니다.

Ruby가 있는 환경에서는 이 폴더에서 아래 명령을 실행할 수 있습니다.

~~~bash
ruby verify_examples.rb
~~~

검사기는 Logstash Event의 필요한 부분만 흉내 내며 실제 Logstash/JRuby 실행을 대신하지 않습니다. 이 제작 환경에는 Ruby 실행기가 없어 실행 검증은 수행하지 못했습니다. 정적 확인 결과는 VALIDATION.md를 보세요.
