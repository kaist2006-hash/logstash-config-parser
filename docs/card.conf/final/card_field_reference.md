# 카드사 공통 필드 정리표

> 현재 기본 출력과 실로그 관측 범위는 [FINAL14 필드표](CARD_FIELDS_FINAL14.md)를 따른다. 아래 내용은 기존 참조 자료이며 모든 정의가 실로그에서 관측·검증되었다는 뜻은 아니다.

현재 적용 버전 `2026-10-18.final10`의 카드사·서비스별 필드명, 실제 `card_detail.fields.*` 출력 경로, 검증 상태는 [카드사별 공통 필드 정의 및 검증 범위](card_common_fields_2026-10-18.md)를 참조한다. 농협 IC·MS의 미해석 후행 데이터는 `card_detail.rest`로 보존하며 알려진 구간의 파싱이 유효하면 `ok`다.

[참고용 엑셀](CARD_CONF_공통필드_카드사별_FINAL10_20261018.xlsx) · [final10 검증 및 적용 안내](VALIDATION_FINAL10.md)

이전 2026-10-11 정리표에는 현재 코드에 없는 `card_detail.header.*` / `card_detail.detail.*` 경로와 실로그 수령 전의 활성화 상태가 섞여 있어, 적용 기준으로 사용하지 않는다. `card_field_reference_excel.xml`도 같은 이전 시점 자료다.
