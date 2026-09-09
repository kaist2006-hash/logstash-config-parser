# frozen_string_literal: true
# GUIDE_START: 원본 처리 로직 그대로, JSON 예시와 연결되는 위치에 주석만 추가한 가이드 사본.
# GUIDE_D01 새 NICE / D02 사설 / D03 TAG / D04 기존 코드 / D05 가변길이.

require "json"
require "time"


# [1~4] 시작 시 1회: JSON을 읽고 Schema/Rule/TAG/Version을 Lookup 형태로 준비해 메모리에 보관합니다.
def register(params)
  spec_path = params["spec_path"].to_s
  raise "script_params.spec_path is required" if spec_path.empty?

  spec = JSON.parse(File.read(spec_path, encoding: "UTF-8"))
  common_type_section = spec.fetch("common_field_types", {})
  @common_type_converters, @common_date_timezone = load_common_field_types(common_type_section)
  @common_field_types = common_type_section.fetch("types", {}).each_with_object({}) do |(path, type), hash|
    hash[path.to_s] = type.to_s
  end.freeze
  @common_detail_types = @common_field_types.each_with_object({}) do |(path, type), hash|
    next unless path.start_with?("detail.")
    hash[path.delete_prefix("detail.")] = type
  end.freeze

# >>> GUIDE_D01_LOAD / GUIDE_D04: 수정 불필요 — detail JSON nice_fixed 전체를 이미 읽습니다.
# 새 merchant/schema/rule 또는 기존 text 배열은 JSON에서 추가하세요.
# <<< GUIDE_D01_LOAD
  nice = spec.fetch("nice_fixed")
  @nice_schemas, nice_rules = load_schema_rule_merchants(nice)
  compile_schema_fields!(@nice_schemas)
  @nice_lookup = build_rule_lookup(
    nice_rules,
    %w[text trade message_type direction message_length]
  )

  # 미등록 text_code fallback도 시작 시 1회 Lookup으로 컴파일합니다.
  # 정상 Rule 매칭이 실패한 이벤트에만 사용하며, 이벤트마다 Rule 전체를 순회하지 않습니다.
  fallback_config = nice.fetch("unregistered_text_fallback", {})
  @nice_unregistered_text_fallback_enabled = fallback_config.fetch("enabled", true) == true
  @nice_unresolved_format = fallback_config.fetch("unresolved_format", "UNKNOWN").to_s
  @nice_fallback_resolved_tag = fallback_config.fetch("resolved_tag", "_nice_pos_unregistered_text_fallback").to_s
  @nice_fallback_unresolved_tag = fallback_config.fetch("unresolved_tag", "_nice_pos_unmatched_format").to_s
  @nice_known_code_mismatch_tag = fallback_config.fetch("known_code_mismatch_tag", "_nice_pos_rule_mismatch").to_s
  @nice_rule_fallback_tag = fallback_config.fetch("rule_fallback_tag", "_nice_pos_rule_fallback").to_s
  @nice_common_profile_tag = fallback_config.fetch("common_profile_tag", "_nice_pos_common_fields_fallback").to_s
  @nice_incomplete_tag = fallback_config.fetch("incomplete_tag", "_nice_pos_incomplete_message").to_s
  @nice_profile_min_score = fallback_config.fetch("profile_min_score", 5.0).to_f
  @nice_profile_min_margin = fallback_config.fetch("profile_min_margin", 2.0).to_f
  @nice_profile_min_evidence = fallback_config.fetch("profile_min_evidence", 2).to_i
  # 전체 Schema 상세파싱 fallback은 공통필드 fallback보다 더 엄격한 구조 검증을 통과해야 합니다.
  @nice_schema_validation_min_score = fallback_config.fetch("schema_validation_min_score", 8.0).to_f
  @nice_schema_validation_min_margin = fallback_config.fetch("schema_validation_min_margin", 3.0).to_f
  @nice_schema_validation_min_evidence = fallback_config.fetch("schema_validation_min_evidence", 3).to_i
  @nice_schema_validation_require_unique_structure = fallback_config.fetch("schema_validation_require_unique_structure", true) == true
  # JSON에 등록되지 않은 text_code는 정상 Rule이 매칭되더라도 추적 가능하도록 항상 별도 태그를 남깁니다.
  @nice_unregistered_text_seen_tag = "_nice_pos_unregistered_text_seen".freeze
  @nice_text_code_lookup = build_explicit_condition_lookup(nice_rules, "text").freeze

  # v7: 정상 Rule 불일치 시에도 기존 규격을 최대한 재사용할 수 있도록
  # text 중심 / trade 중심 완화 Lookup과 공통필드 구조 Profile을 시작 시 1회 생성합니다.
  @nice_text_relaxed_lookup = build_rule_candidate_lookup(
    nice_rules.select { |rule| explicit_condition?(rule, "text") },
    %w[text message_type direction message_length]
  )
  @nice_trade_relaxed_lookup = build_rule_candidate_lookup(
    nice_rules.select { |rule| explicit_condition?(rule, "trade") },
    %w[trade message_type direction message_length]
  )
  @nice_common_profiles = build_nice_common_profiles(
    @nice_schemas,
    nice_rules,
    @common_detail_types
  )
  # 완화 Rule 후보가 실제 어느 Schema/Profile인지 O(1)로 확인할 수 있도록 시작 시 역 Lookup도 생성합니다.
  @nice_schema_id_by_object_id = @nice_schemas.each_with_object({}) do |(schema_id, schema), lookup|
    lookup[schema.object_id] = schema_id.to_s
  end.freeze
  @nice_common_profile_by_schema_direction = {}
  @nice_common_profiles.each do |profile|
    profile["variants"].each do |variant|
      @nice_common_profile_by_schema_direction[[variant["schema_id"], profile["direction"]].freeze] = profile
    end
  end
  @nice_common_profile_by_schema_direction.freeze
  @nice_common_profiles_by_direction = @nice_common_profiles.group_by { |profile| profile["direction"] }
  @nice_common_profiles_by_direction.each_value(&:freeze)
  @nice_common_profiles_by_direction.freeze

  @nice_header_fields = compile_fields([
    {"key" => "message_length", "start" => 1, "length" => 4},
    {"key" => "text_code", "start" => 5, "length" => 3},
    {"key" => "management_number", "start" => 8, "length" => 20},
    {"key" => "message_type", "start" => 28, "length" => 4},
    {"key" => "trade_code", "start" => 32, "length" => 2},
    {"key" => "equipment_code", "start" => 34, "length" => 2},
    {"key" => "device_number", "start" => 36, "length" => 10},
    {"key" => "cat_id", "start" => 46, "length" => 10}
  ])

  private_spec = spec.fetch("private_fixed")
  @private_schemas, private_rules, private_versions = load_private_merchants(private_spec)
  compile_schema_fields!(@private_schemas)
  @private_lookup = build_rule_lookup(
    private_rules,
    %w[version trade message_type direction]
  )
  @private_version_lookup = private_versions.each_with_object({}) { |version, hash| hash[version] = true }
  @private_ic_schemas = private_spec.fetch("ic_schemas")
  @private_ic_fields = {}
  @private_ic_schemas.each do |schema_key, schema|
    @private_ic_fields[schema_key] = compile_fields(schema.fetch("fields", []))
  end
  @private_header_fields = compile_fields([
    {"key" => "message_length", "start" => 1, "length" => 4},
    {"key" => "version", "start" => 5, "length" => 7},
    {"key" => "management_number", "start" => 12, "length" => 20},
    {"key" => "message_type", "start" => 32, "length" => 4},
    {"key" => "trade_code", "start" => 36, "length" => 2},
    {"key" => "cat_id", "start" => 38, "length" => 10}
  ])

  integrated = spec.fetch("integrated_tag")
  @integrated_header = integrated.fetch("header")
  @integrated_header_fields = compile_fields(
    %w[message_length cat_id serial_number transaction_large business_middle detail_small transaction_id send_receive].map do |key|
      field = @integrated_header.fetch(key)
      {"key" => key, "start" => field.fetch("start"), "length" => field.fetch("length")}
    end
  )
  @integrated_data_start = @integrated_header.fetch("data_start").to_i
  @integrated_tags = integrated.fetch("tag_specs")
  @integrated_special_prefix_lookup = integrated.fetch("special_prefixes").each_with_object({}) do |prefix, hash|
    hash[prefix.to_s] = true
  end

  @nice_schemas.freeze
  @nice_lookup.freeze
  @nice_text_code_lookup.freeze
  @nice_text_relaxed_lookup.freeze
  @nice_trade_relaxed_lookup.freeze
  @nice_common_profiles.freeze
  @nice_common_profiles_by_direction.freeze
  @nice_schema_id_by_object_id.freeze
  @nice_common_profile_by_schema_direction.freeze
  @nice_common_profile_tag.freeze
  @nice_rule_fallback_tag.freeze
  @nice_incomplete_tag.freeze
  @nice_unresolved_format.freeze
  @nice_fallback_resolved_tag.freeze
  @nice_fallback_unresolved_tag.freeze
  @nice_known_code_mismatch_tag.freeze
  @nice_unregistered_text_seen_tag.freeze
  @nice_header_fields.freeze
  @private_schemas.freeze
  @private_lookup.freeze
  @private_version_lookup.freeze
  @private_ic_schemas.freeze
  @private_ic_fields.freeze
  @private_header_fields.freeze
  @integrated_header.freeze
  @integrated_header_fields.freeze
  @integrated_tags.freeze
  @integrated_special_prefix_lookup.freeze
  @common_type_converters.freeze
  @common_date_timezone.freeze
end


def load_common_field_types(section)
  converters = {"root" => [], "detail" => []}

  section.fetch("types", {}).each do |path, type|
    value_type = type.to_s
    next unless %w[integer long date].include?(value_type)

    path_text = path.to_s
    if path_text.start_with?("detail.")
      converters["detail"] << [path_text.delete_prefix("detail."), value_type].freeze
    else
      converters["root"] << [path_text, value_type].freeze
    end
  end

  converters.each_value(&:freeze)
  timezone = section.fetch("_date_timezone", "+09:00").to_s
  [converters.freeze, timezone]
end


# [3~4] 초기화 보조: JSON의 Schema/Rule/Version을 register에서 사용할 메모리 구조로 정리합니다.
def load_schema_rule_merchants(section)
  schemas = {}
  rules = []

  section.fetch("merchants").each do |merchant_key, merchant|
    merchant.fetch("schemas", {}).each do |schema_key, schema|
      key = schema_key.to_s
      raise "duplicate schema: #{key}" if schemas.key?(key)
      schemas[key] = schema
    end

    merchant.fetch("rules", []).each do |rule|
      rules << rule.merge("_merchant" => merchant_key)
    end
  end

  [schemas, rules]
end


def load_private_merchants(section)
  schemas = {}
  rules = []
  versions = []

  section.fetch("merchants").each do |merchant_key, merchant|
    merchant_versions = merchant.fetch("versions", []).map(&:to_s)
    versions.concat(merchant_versions)

    merchant.fetch("schemas", {}).each do |schema_key, schema|
      key = schema_key.to_s
      raise "duplicate private schema: #{key}" if schemas.key?(key)
      schemas[key] = schema
    end

    merchant.fetch("rules", []).each do |rule|
      condition = (rule["when"] || {}).dup
      condition["version"] = merchant_versions if condition["version"].nil? || condition["version"].empty?
      rules << rule.merge("when" => condition, "_merchant" => merchant_key)
    end
  end

  [schemas, rules, versions.uniq]
end


def compile_fields(fields)
  compiled = []
  previous_start = 0

  fields.each do |field|
    key = field.fetch("key").to_s
    start_byte = field.fetch("start").to_i
    length = field.fetch("length").to_i
    raise "invalid field range: #{key}" if start_byte <= 0 || length < 0
    raise "field order must be ascending: #{key}" if start_byte < previous_start

    compiled << [key, start_byte, length, start_byte + length - 1]
    previous_start = start_byte
  end

  compiled.freeze
end


def compile_schema_fields!(schemas)
  schemas.each_value do |schema|
    schema["_compiled_fields"] = compile_fields(schema.fetch("fields", []))
  end
end


# [5~9] 이벤트마다 실행: b_body 추출 -> Wrapper 제거 -> 전문 형식 판별 -> 상세 파싱 -> nice_pos 기록 순서입니다.
def filter(event)
  body = event.get("b_body")
  return [event] if body.nil? || body.to_s.empty?

  # [5] b_body 원본은 유지하고 파싱에 필요한 실제 전문(raw)만 따로 추출합니다.
  raw = extract_professional(body.to_s)
  return [event] if raw.nil?

  begin
    # [6] 통합 TAG -> SK/S-OIL 사설 -> 그 외 NICE 순서로 사용할 파서를 결정합니다.
    if integrated_message?(raw)
      parse_integrated(event, raw)
    elsif private_message?(raw)
      parse_private(event, raw)
    else
      parse_nice(event, raw)
    end
  rescue StandardError => error
    event.tag("_nice_pos_parse_error")
    event.set("[nice_pos][parse_error]", "#{error.class}: #{error.message}")
  end

  # 파싱 로직은 v8 그대로 유지하고, 마지막 단계에서 NICE 내부 진단 태그만
  # 운영용 fallback / error 상태로 단순화합니다.
  normalize_nice_pos_operational_tags(event)

  [event]
end


# v10 태그 단순화 전용 후처리.
# 중요: nice_pos 필드/Schema/Rule/공통필드 fallback 결과에는 손대지 않습니다.
# 기존 파이프라인 태그(in_beat 등)는 그대로 두고 _nice_pos_* 내부 진단 태그만 제거한 뒤
# 최종 상태를 fallback 또는 error 하나로 치환합니다.
def normalize_nice_pos_operational_tags(event)
  tags = event.get("tags")
  return if tags.nil?

  current = tags.is_a?(Array) ? tags.map(&:to_s) : [tags.to_s]
  internal = current.select { |tag| tag.start_with?("_nice_pos_") }
  return if internal.empty?

  # error는 실제 비정상 전문/파싱 예외에만 사용합니다.
  # - incomplete_message: Header 선언 길이보다 실제 전문이 짧음
  # - parse_error: Ruby 파싱 중 예외 발생
  # - truncated: 통합 TAG의 후행 가변 TAG가 잘린 경우. 단, 이미 공통 Detail 필드가
  #   정상 추출된 통합 전문은 운영상 실패가 아니므로 fallback으로 분류합니다.
  parse_error = internal.include?("_nice_pos_parse_error")
  incomplete_message = internal.include?("_nice_pos_incomplete_message")
  truncated = internal.include?("_nice_pos_truncated")

  nice_pos = event.get("[nice_pos]")
  integrated_common_recovered = false
  if truncated && nice_pos.is_a?(Hash) && nice_pos["parser_type"].to_s == "integrated_tag"
    detail = nice_pos["detail"]
    if detail.is_a?(Hash)
      integrated_common_recovered = @common_detail_types.keys.any? do |key|
        !match_value(detail[key]).empty?
      end
    end
  end

  hard_error = parse_error || incomplete_message || (truncated && !integrated_common_recovered)

  # 정상 완전 전문에서 Rule/코드/Format이 미등록 또는 미확정인 경우와,
  # 통합 TAG 후행부가 일부 잘렸더라도 공통 Detail 필드가 이미 정상 추출된 경우는
  # 운영상 fallback으로 분류합니다. 내부 진단 태그는 제거하고 최종 상태만 남깁니다.
  fallback_state = !hard_error && (integrated_common_recovered || internal.any? do |tag|
    [
      "_nice_pos_unregistered_text_seen",
      "_nice_pos_unregistered_text_fallback",
      "_nice_pos_rule_fallback",
      "_nice_pos_common_fields_fallback",
      "_nice_pos_unmatched_format",
      "_nice_pos_rule_mismatch",
      "_nice_pos_nit_ec_format_mismatch"
    ].include?(tag)
  end)

  filtered = current.reject { |tag| tag.start_with?("_nice_pos_") }
  filtered << "fallback" if fallback_state && !filtered.include?("fallback")
  filtered << "error" if hard_error && !filtered.include?("error")
  event.set("tags", filtered)
end


# [3] Rule 전체 순회를 줄이기 위해 시작 시 Header 조건별 Hash Lookup을 미리 생성합니다.
def build_rule_lookup(rules, dimensions)
  root = {}

  rules.each_with_index do |rule, index|
    priority = rule.key?("priority") ? rule["priority"].to_i : index
    condition = rule["when"] || {}

    value_sets = dimensions.map do |dimension|
      values = condition[dimension]
      values.nil? || values.empty? ? ["*"] : values.map(&:to_s)
    end

    value_sets[0].product(*value_sets[1..]).each do |combination|
      node = root
      combination.each do |value|
        node[value] ||= {}
        node = node[value]
      end

      previous = node[:_match]
      node[:_match] = [priority, rule] if previous.nil? || priority < previous[0]
    end
  end

  root
end


# 미등록 text_code fallback용: text 이외의 Header 조건으로 후보 Schema를 미리 Lookup 형태로 구성합니다.
# 동일 Header 조건에서 서로 다른 Schema가 후보가 되면 안전을 위해 자동 상세파싱하지 않습니다.
def build_rule_candidate_lookup(rules, dimensions)
  root = {}

  rules.each_with_index do |rule, index|
    priority = rule.key?("priority") ? rule["priority"].to_i : index
    condition = rule["when"] || {}

    value_sets = dimensions.map do |dimension|
      values = condition[dimension]
      values.nil? || values.empty? ? ["*"] : values.map(&:to_s)
    end

    value_sets[0].product(*value_sets[1..]).each do |combination|
      node = root
      combination.each do |value|
        node[value] ||= {}
        node = node[value]
      end

      node[:_matches] ||= []
      node[:_matches] << [priority, rule]
    end
  end

  root
end


def build_explicit_condition_lookup(rules, dimension)
  rules.each_with_object({}) do |rule, lookup|
    values = (rule["when"] || {})[dimension]
    next if values.nil? || values.empty?

    values.each { |value| lookup[value.to_s] = true }
  end
end

def explicit_condition?(rule, dimension)
  values = (rule["when"] || {})[dimension]
  !values.nil? && !values.empty?
end


# Schema 전체 Detail 구조가 실제로 동일한지 비교하기 위한 사전 Signature입니다.
# 필드명/위치/길이와 Dynamic 규격까지 포함하여, 공통필드 위치만 같고 나머지 Detail이 다른 Schema는 구분합니다.
def nice_schema_structure_signature(schema)
  fields = schema.fetch("_compiled_fields", []).map do |key, start_byte, length, _end_byte|
    "#{key}@#{start_byte}:#{length}"
  end
  dynamic = schema["dynamic"] ? JSON.generate(schema["dynamic"]) : ""
  [
    schema["direction"].to_s,
    schema.key?("response_code_start") ? schema["response_code_start"].to_i : 0,
    fields.join(","),
    schema["dynamic_start"].to_i,
    dynamic
  ].join("|")
end


# v8 공통필드 구조 fallback용 Profile을 시작 시 1회 생성합니다.
# Profile은 정확한 format을 추측하기 위한 것이 아니라, 정상 완전 전문에서 공통필드 위치가
# 동일한 Schema들을 하나로 묶어 안전하게 공통필드만 추출하기 위한 메모리 구조입니다.
def build_nice_common_profiles(schemas, rules, common_detail_types)
  rule_hints = build_schema_rule_hints(rules)
  profiles = {}

  schemas.each do |schema_id, schema|
    compiled = schema.fetch("_compiled_fields", [])
    common_fields = compiled.select { |field| common_detail_types.key?(field[0]) }
    next if common_fields.empty?

    aux_fields = approval_datetime_aux_fields(compiled, common_fields)
    schema_direction = schema["direction"].to_s
    directions = schema_direction == "both" ? %w[request response] : [schema_direction]
    static_end = compiled.map { |field| field[3] }.max.to_i
    dynamic_start = schema["dynamic_start"].to_i
    dynamic_start = nil if dynamic_start <= 0

    directions.each do |direction|
      response_code_start = if direction == "response" && schema_direction != "both"
                              schema.key?("response_code_start") ? schema["response_code_start"].to_i : 56
                            end

      signature_parts = [direction, response_code_start.to_i]
      signature_parts.concat(common_fields.map { |key, start_byte, length, _end_byte| "#{key}@#{start_byte}:#{length}" })
      signature_parts.concat(aux_fields.map { |key, start_byte, length, _end_byte| "aux:#{key}@#{start_byte}:#{length}" })
      signature = signature_parts.join("|")

      profile = profiles[signature] ||= {
        "direction" => direction,
        "response_code_start" => response_code_start,
        "common_fields" => common_fields.freeze,
        "aux_fields" => aux_fields.freeze,
        "variants" => []
      }

      hints = rule_hints[schema_id.to_s] || empty_schema_rule_hints
      profile["variants"] << {
        "schema_id" => schema_id.to_s,
        "name" => schema["name"].to_s,
        "static_end" => static_end,
        "dynamic_start" => dynamic_start,
        "texts" => hints["texts"],
        "trades" => hints["trades"],
        "message_types" => hints["message_types"],
        "message_type_wildcard" => hints["message_type_wildcard"],
        "structure_signature" => nice_schema_structure_signature(schema)
      }.freeze
    end
  end

  profiles.values.each do |profile|
    profile["variants"].freeze
    profile.freeze
  end
  profiles.values.freeze
end


def build_schema_rule_hints(rules)
  hints = {}

  rules.each do |rule|
    schema_id = rule["schema"].to_s
    next if schema_id.empty?

    hint = hints[schema_id] ||= {
      "texts" => {},
      "trades" => {},
      "message_types" => {},
      "message_type_wildcard" => false
    }
    condition = rule["when"] || {}

    Array(condition["text"]).each { |value| hint["texts"][value.to_s] = true }
    Array(condition["trade"]).each { |value| hint["trades"][value.to_s] = true }

    message_types = condition["message_type"]
    if message_types.nil? || message_types.empty?
      hint["message_type_wildcard"] = true
    else
      message_types.each { |value| hint["message_types"][value.to_s] = true }
    end
  end

  hints.each_value do |hint|
    hint["texts"].freeze
    hint["trades"].freeze
    hint["message_types"].freeze
    hint.freeze
  end
  hints.freeze
end


def empty_schema_rule_hints
  @empty_schema_rule_hints ||= {
    "texts" => {}.freeze,
    "trades" => {}.freeze,
    "message_types" => {}.freeze,
    "message_type_wildcard" => true
  }.freeze
end


def approval_datetime_aux_fields(compiled_fields, common_fields)
  return [] if common_fields.any? { |field| field[0] == "approval_datetime" }

  pairs = [
    ["승인_거래일자", "승인_거래시간"],
    ["거래일자", "거래시간"],
    ["승인일자", "승인일시"]
  ]
  lookup = compiled_fields.each_with_object({}) { |field, hash| hash[field[0]] = field }

  pairs.each do |date_key, time_key|
    date_field = lookup[date_key]
    time_field = lookup[time_key]
    return [date_field, time_field] if date_field && time_field
  end

  []
end

# [5] [OUT]/[IN], 대괄호, 길이값 등 외부 Wrapper를 제거해 실제 전문만 반환합니다.
def extract_professional(body)
  text = body.sub(/\A\[(?:OUT|IN)\]\s*/, "")

  payload = if (match = text.match(/\A\[\d{1,8}\]\[(.*)\]\s*\z/m))
              match[1]
            elsif (match = text.match(/\A\[\d{1,8}\]\[(.*)\z/m))
              match[1]
            elsif text.start_with?("[")
              value = text[1..] || ""
              value = value.sub(/\]\[\d{1,8}\]\s*\z/m, "")
              value.sub(/\]\s*\z/m, "")
            else
              text
            end

  stx_index = payload.index("\u0002")
  if !stx_index.nil? && stx_index.positive?
    prefix = payload[0...stx_index]
    payload = payload[stx_index..] if prefix.match?(/\AEA\d{10}\z/)
  end

  return payload if payload.start_with?("\u0002")
  return payload if payload.match?(/\A\d{4}/m)

  nil
end


# [6] 전문 형식 판별: STX+Length이면 통합 TAG 전문인지 확인합니다.
def integrated_message?(raw)
  raw.start_with?("\u0002") && raw.byteslice(1, 4).to_s.match?(/\A\d{4}\z/)
end


# [6] 전문 형식 판별: 등록된 Version이면 SK/S-OIL 사설포스로 처리합니다.
# >>> GUIDE_D02: 수정 불필요 — JSON versions에 추가한 ZGUIDE1을 아래에서 판별합니다.
# <<< GUIDE_D02
def private_message?(raw)
  version = match_value(logical_byte_slice(raw, 5, 7))
  @private_version_lookup.key?(version)
end


# [7~9] NICE: Header -> 정상 Rule -> 완화 Rule 후보 -> 구조검증 -> 공통필드 Profile 순서로 처리합니다.
# Rule 완전일치가 아닌 경우에는 text/trade 유사성만으로 전체 Detail을 바로 적용하지 않습니다.
# 정상 완전 전문 + 공통필드 구조 검증 + Schema 전체구조 유일성까지 통과한 경우에만 전체 Detail을 적용하고,
# 그렇지 않으면 format=UNKNOWN 상태로 검증된 공통필드만 추출합니다. 잘린/비정상 전문은 Header-only입니다.
def parse_nice(event, raw)
  header = extract_compiled_fields(raw, @nice_header_fields)

  text = match_value(header["text_code"])
  trade = match_value(header["trade_code"])
  message_type = match_value(header["message_type"])
  message_length = match_value(header["message_length"])
  direction = professional_direction(message_type, event.get("status"))
  text_registered = !text.empty? && @nice_text_code_lookup.key?(text)

  if !text.empty? && !text_registered && !@nice_unregistered_text_seen_tag.empty?
    event.tag(@nice_unregistered_text_seen_tag)
  end

# >>> GUIDE_D01_SELECT / GUIDE_D04: 수정 불필요 — Q99/99/0200/request/0073으로 JSON rule 선택.
# rule.schema → guide_d01_request, 또는 PTX → 기존 schema 21.
# <<< GUIDE_D01_SELECT
  # 1순위: 기존 JSON Rule 완전일치. 정상 등록 전문은 기존 동작을 그대로 유지합니다.
  schema = choose_schema(
    @nice_lookup,
    @nice_schemas,
    [text, trade, message_type, direction, message_length]
  )

  if schema
    parse_nice_with_schema(event, raw, header, direction, schema)
    return
  end

  if text == "NIT" && trade == "EC"
    event.tag("_nice_pos_nit_ec_format_mismatch")
    write_nice_header_only(event, header, direction, "NIT/EC 미확인 Length")
    return
  end

  unless @nice_unregistered_text_fallback_enabled
    event.tag(@nice_known_code_mismatch_tag) if text_registered && !@nice_known_code_mismatch_tag.empty?
    event.tag(@nice_fallback_unresolved_tag) unless @nice_fallback_unresolved_tag.empty?
    write_nice_header_only(event, header, direction, @nice_unresolved_format)
    return
  end

  # fallback 상세 파싱은 잘리거나 비정상 길이인 전문에는 적용하지 않습니다.
  complete, declared_length, effective_raw = complete_nice_message(raw, message_length)
  unless complete
    event.tag(@nice_incomplete_tag) unless @nice_incomplete_tag.empty?
    event.tag(@nice_known_code_mismatch_tag) if text_registered && !@nice_known_code_mismatch_tag.empty?
    event.tag(@nice_fallback_unresolved_tag) unless @nice_fallback_unresolved_tag.empty?
    write_nice_header_only(event, header, direction, @nice_unresolved_format)
    return
  end

  # 2순위: Rule 일부 값만 새롭게 등장한 정상 전문은 기존 규격 후보를 역으로 찾습니다.
  # 단, text/trade/Header가 비슷하다는 이유만으로 전체 Detail을 바로 적용하지 않습니다.
  # 후보 Schema의 공통필드 구조가 실제 전문과 명확히 일치하고, 같은 Profile 안의 전체 Detail 구조까지 유일할 때만 전체 파싱합니다.
  inferred_schema = infer_nice_schema_from_relaxed_rules(
    text,
    trade,
    message_type,
    direction,
    message_length
  )

  validated_profile_result = nil
  if inferred_schema
    validation = validate_inferred_nice_schema_structure(
      effective_raw,
      declared_length,
      direction,
      message_type,
      text,
      trade,
      inferred_schema
    )
    validated_profile_result = validation["profile_result"]

    if validation["full_schema_safe"]
      event.tag(@nice_rule_fallback_tag) unless @nice_rule_fallback_tag.empty?
      if !text_registered && !@nice_fallback_resolved_tag.empty?
        event.tag(@nice_fallback_resolved_tag)
      elsif text_registered && !@nice_known_code_mismatch_tag.empty?
        event.tag(@nice_known_code_mismatch_tag)
      end
      parse_nice_with_schema(event, effective_raw, header, direction, inferred_schema)
      return
    end
  end

  # 3순위: 전체 Schema까지 확정하기 어렵더라도 정상 완전 전문이면 JSON Schema의 공통필드 위치 Profile을 비교합니다.
  # 2순위의 엄격한 구조검증에서 이미 Profile을 확정했다면 그 결과를 재사용하여 동일 전문을 두 번 분석하지 않습니다.
  # 정확한 format을 확정하지 못하더라도 Profile이 충분히 명확하면 21개 공통필드 중 해당 규격에 존재하는 값은 추출합니다.
  profile_result = validated_profile_result || choose_nice_common_profile(
    effective_raw,
    declared_length,
    direction,
    message_type,
    text,
    trade
  )

  if profile_result
    event.tag(@nice_common_profile_tag) unless @nice_common_profile_tag.empty?
    event.tag(@nice_known_code_mismatch_tag) if text_registered && !@nice_known_code_mismatch_tag.empty?
    event.tag(@nice_fallback_unresolved_tag) unless @nice_fallback_unresolved_tag.empty?
    write_nice_common_profile(
      event,
      header,
      direction,
      @nice_unresolved_format,
      profile_result
    )
    return
  end

  event.tag(@nice_known_code_mismatch_tag) if text_registered && !@nice_known_code_mismatch_tag.empty?
  event.tag(@nice_fallback_unresolved_tag) unless @nice_fallback_unresolved_tag.empty?
  write_nice_header_only(event, header, direction, @nice_unresolved_format)
end


# >>> GUIDE_D01_READ: 수정 불필요 — JSON fields의 start/length를 읽어 detail을 만듭니다.
# D01 요청: 56~67 금액 / 68~69 할부 / 70~73 campaign_code.
# <<< GUIDE_D01_READ
def parse_nice_with_schema(event, raw, header, direction, schema)
  detail = extract_compiled_fields(raw, schema.fetch("_compiled_fields"))

  if schema["dynamic_start"] && schema["dynamic"]
    parse_dynamic_fields(raw, schema["dynamic_start"].to_i, schema["dynamic"], detail)
  end

  apply_common_detail_fields!(detail, direction)

  nice_pos = build_nice_header_hash(header, direction, schema["name"].to_s)

  if direction == "response" && schema["direction"].to_s != "both"
    response_code_start = schema.key?("response_code_start") ? schema["response_code_start"].to_i : 56
    nice_pos["response_code"] = logical_byte_slice(raw, response_code_start, 4) if response_code_start.positive?
  end

  nice_pos["detail"] = detail
  apply_common_field_types!(nice_pos, direction)
  event.set("[nice_pos]", nice_pos)
end


def build_nice_header_hash(header, direction, format_name)
  {
    "parser_type" => "nice_fixed",
    "format" => format_name.to_s,
    "direction" => direction,
    "message_length" => header["message_length"],
    "text_code" => header["text_code"],
    "management_number" => header["management_number"],
    "message_type" => header["message_type"],
    "trade_code" => header["trade_code"],
    "equipment_code" => header["equipment_code"],
    "device_number" => header["device_number"],
    "cat_id" => header["cat_id"]
  }
end


def complete_nice_message(raw, message_length)
  declared_length = match_value(message_length).to_i
  return [false, declared_length, raw] if declared_length < 56

  actual_length = logical_byte_length(raw)
  return [false, declared_length, raw] if actual_length < declared_length

  [true, declared_length, logical_byte_slice(raw, 1, declared_length)]
end


def infer_nice_schema_from_relaxed_rules(text, trade, message_type, direction, message_length)
  text_candidate = nil
  trade_candidate = nil

  unless text.empty?
    text_candidate = choose_best_candidate_schema(
      @nice_text_relaxed_lookup,
      @nice_schemas,
      [text, message_type, direction, message_length]
    )
  end

  unless trade.empty?
    trade_candidate = choose_best_candidate_schema(
      @nice_trade_relaxed_lookup,
      @nice_schemas,
      [trade, message_type, direction, message_length]
    )
  end

  return text_candidate if text_candidate && trade_candidate.nil?
  return trade_candidate if trade_candidate && text_candidate.nil?
  return text_candidate if text_candidate && trade_candidate && text_candidate.equal?(trade_candidate)

  nil
end


def choose_best_candidate_schema(lookup, schemas, values)
  states = traverse_candidate_lookup(lookup, values)
  return nil if states.empty?

  best_priority = nil
  best_schema_ids = {}

  states.each do |node|
    (node[:_matches] || []).each do |priority, rule|
      schema_id = rule["schema"].to_s
      next if schema_id.empty?

      if best_priority.nil? || priority < best_priority
        best_priority = priority
        best_schema_ids = {schema_id => true}
      elsif priority == best_priority
        best_schema_ids[schema_id] = true
      end
    end
  end

  return nil unless best_schema_ids.length == 1
  schemas[best_schema_ids.keys.first]
end


def traverse_candidate_lookup(lookup, values)
  states = [lookup]

  values.each do |value|
    value = value.to_s
    next_states = []

    states.each do |node|
      exact = node[value]
      wildcard = node["*"]
      next_states << exact unless exact.nil?
      next_states << wildcard unless wildcard.nil? || wildcard.equal?(exact)
    end

    return [] if next_states.empty?
    states = next_states
  end

  states
end


# 완화 Rule로 찾은 Schema를 전체 Detail 파싱에 사용하기 전 구조 안전성을 한 번 더 검증합니다.
# 1) 후보 Schema의 공통필드 Profile이 구조점수 1위인지
# 2) 공통필드 값/길이 증거가 충분한지
# 3) 같은 Profile에서 현재 전문에 호환되는 Schema들의 전체 Detail 구조가 하나뿐인지
# 를 모두 만족해야 true를 반환합니다.
def validate_inferred_nice_schema_structure(raw, declared_length, direction, message_type, text, trade, schema)
  empty_result = {"full_schema_safe" => false, "profile_result" => nil}.freeze
  schema_id = @nice_schema_id_by_object_id[schema.object_id]
  return empty_result if schema_id.nil?

  target_profile = @nice_common_profile_by_schema_direction[[schema_id, direction]]
  return empty_result if target_profile.nil?

  structural_result = choose_nice_common_profile(
    raw,
    declared_length,
    direction,
    message_type,
    text,
    trade,
    {
      "min_score" => @nice_schema_validation_min_score,
      "min_margin" => @nice_schema_validation_min_margin,
      "min_evidence" => @nice_schema_validation_min_evidence,
      "include_header_hints" => false
    }
  )
  return empty_result if structural_result.nil?

  safe = structural_result["profile"].equal?(target_profile)
  if safe
    compatible_variants = target_profile["variants"].select do |variant|
      nice_profile_variant_compatible?(variant, declared_length, message_type)
    end
    safe = compatible_variants.any? { |variant| variant["schema_id"] == schema_id }

    if safe && @nice_schema_validation_require_unique_structure
      structures = compatible_variants.map { |variant| variant["structure_signature"] }.uniq
      safe = structures.length == 1
    end
  end

  {"full_schema_safe" => safe, "profile_result" => structural_result}
end


def choose_nice_common_profile(raw, declared_length, direction, message_type, text, trade, options = nil)
  options ||= {}
  min_score = options.fetch("min_score", @nice_profile_min_score).to_f
  min_margin = options.fetch("min_margin", @nice_profile_min_margin).to_f
  min_evidence = options.fetch("min_evidence", @nice_profile_min_evidence).to_i
  include_header_hints = options.fetch("include_header_hints", true) == true
  scored = []

  profiles = @nice_common_profiles_by_direction[direction] || []
  profiles.each do |profile|
    compatible_variants = profile["variants"].select do |variant|
      nice_profile_variant_compatible?(variant, declared_length, message_type)
    end
    next if compatible_variants.empty?

    values = extract_nice_common_profile_values(raw, profile, direction)
    score, evidence = score_nice_common_profile(
      values,
      profile,
      compatible_variants,
      declared_length,
      text,
      trade,
      message_type,
      include_header_hints
    )
    next if evidence < min_evidence

    scored << [score, evidence, profile, values]
  end

  return nil if scored.empty?
  scored.sort_by! { |entry| [-entry[0], -entry[1]] }
  best = scored[0]
  second = scored[1]

  # 구조 증거가 약하거나 후보 간 점수 차이가 작으면 잘못된 공통필드 생성을 막기 위해 포기합니다.
  return nil if best[0] < min_score
  return nil if second && (best[0] - second[0]) < min_margin

  {
    "profile" => best[2],
    "detail" => best[3]["detail"],
    "response_code" => best[3]["response_code"],
    "score" => best[0]
  }
end


def nice_profile_variant_compatible?(variant, declared_length, message_type)
  return false if variant["static_end"].to_i > declared_length

  message_types = variant["message_types"]
  return true if variant["message_type_wildcard"]
  return true if message_types.empty?

  message_types.key?(message_type.to_s)
end


def extract_nice_common_profile_values(raw, profile, direction)
  detail = extract_compiled_fields(raw, profile["common_fields"])

  unless profile["aux_fields"].empty?
    aux = extract_compiled_fields(raw, profile["aux_fields"])
    combined = detail.merge(aux)
    apply_common_detail_fields!(combined, direction)
    approval_datetime = combined["approval_datetime"]
    detail["approval_datetime"] = approval_datetime unless match_value(approval_datetime).empty?
  end

  response_code = nil
  response_code_start = profile["response_code_start"].to_i
  if direction == "response" && response_code_start.positive?
    response_code = logical_byte_slice(raw, response_code_start, 4)
  end

  {"detail" => detail, "response_code" => response_code}
end


def score_nice_common_profile(values, profile, variants, declared_length, text, trade, message_type, include_header_hints = true)
  score = 0.0
  evidence = 0
  detail = values["detail"]

  profile["common_fields"].each do |key, _start_byte, length, _end_byte|
    value = detail[key]
    type = @common_detail_types[key]
    field_score, field_evidence = common_profile_field_score(key, value, type, length)
    score += field_score
    evidence += field_evidence
  end

  if detail.key?("approval_datetime") && !profile["common_fields"].any? { |field| field[0] == "approval_datetime" }
    field_score, field_evidence = common_profile_field_score(
      "approval_datetime",
      detail["approval_datetime"],
      @common_detail_types["approval_datetime"],
      match_value(detail["approval_datetime"]).length
    )
    score += field_score
    evidence += field_evidence
  end

  response_code = match_value(values["response_code"])
  unless response_code.empty?
    if response_code.match?(/\A[[:alnum:] _-]{2,4}\z/)
      score += 0.5
      evidence += 1
    else
      score -= 1.0
    end
  end

  # 길이 적합도는 항상 구조 점수에 포함합니다. text/trade/message_type 일치는 일반 공통필드 fallback의 보조 힌트로만 사용하며,
  # 전체 Schema 상세파싱 검증 시에는 include_header_hints=false로 호출하여 Header 유사성이 구조 검증을 대신하지 못하게 합니다.
  best_variant_bonus = variants.map do |variant|
    bonus = 0.0
    if include_header_hints
      bonus += 3.0 if !text.empty? && variant["texts"].key?(text)
      bonus += 2.0 if !trade.empty? && variant["trades"].key?(trade)
      bonus += 1.0 if variant["message_types"].key?(message_type.to_s)
    end

    slack = declared_length - variant["static_end"].to_i
    bonus += 5.0 if slack.between?(0, 8)
    bonus += 3.0 if slack.between?(9, 32)
    bonus += 1.0 if slack.between?(33, 64)
    bonus += 0.5 if slack.between?(65, 128)
    if !variant["dynamic_start"].nil? && declared_length >= variant["dynamic_start"].to_i && slack > 128
      bonus += 0.3
    end
    bonus
  end.max.to_f

  score += best_variant_bonus
  [score, evidence]
end


def common_profile_field_score(key, value, type, expected_length = nil)
  raw_text = value.to_s
  text = match_value(raw_text)
  return [0.0, 0] if text.empty?

  case type.to_s
  when "integer", "long"
    return [-4.0, 1] unless text.match?(/\A[+-]?\d+\z/)

    # 고정길이 숫자 필드는 정상 전문에서 대부분 자리수를 채워 들어오므로,
    # 다른 Profile의 중간 영역을 우연히 숫자로 읽은 경우(앞/뒤 공백 포함)는 낮은 점수만 부여합니다.
    full_width = expected_length.nil? || raw_text.length == expected_length.to_i && raw_text == text
    return full_width ? [2.0, 1] : [0.4, 1]
  when "date"
    return normalize_common_datetime(text).nil? ? [-5.0, 1] : [4.0, 1]
  end

  if %w[issuer_code acquirer_code].include?(key)
    return text.match?(/\A[[:alnum:] _-]{1,4}\z/) ? [1.5, 1] : [-2.0, 1]
  end

  if %w[approval_number original_approval_number transaction_unique_number merchant_number].include?(key)
    return text.match?(/\A[[:alnum:] _-]+\z/) ? [1.2, 1] : [-2.0, 1]
  end

  if %w[issuer_name acquirer_name display_message].include?(key)
    return common_profile_printable?(text) ? [0.5, 1] : [-2.0, 1]
  end

  common_profile_printable?(text) ? [0.3, 1] : [-1.0, 1]
end


def common_profile_printable?(text)
  text.each_char.all? do |character|
    code = character.ord
    code >= 0x20 || character == "	"
  end
end


def write_nice_common_profile(event, header, direction, format_name, profile_result)
  nice_pos = build_nice_header_hash(header, direction, format_name)
  response_code = profile_result["response_code"]
  nice_pos["response_code"] = response_code unless match_value(response_code).empty?

  detail = profile_result["detail"] || {}
  nice_pos["detail"] = detail unless detail.empty?
  apply_common_field_types!(nice_pos, direction)
  event.set("[nice_pos]", nice_pos)
end


# [7~9] 사설포스: Version/Header로 Rule/Schema 선택 -> 필드 추출 -> nice_pos Hash 구성 -> event.set 합니다.
def parse_private(event, raw)
  header = extract_compiled_fields(raw, @private_header_fields)

  version = match_value(header["version"])
  trade = match_value(header["trade_code"])
  message_type = match_value(header["message_type"])
  direction = professional_direction(message_type, event.get("status"))

  schema = choose_schema(
    @private_lookup,
    @private_schemas,
    [version, trade, message_type, direction]
  )
  return if schema.nil?

  effective_raw = trim_to_declared_length(raw, header["message_length"])
  detail = extract_compiled_fields(effective_raw, schema.fetch("_compiled_fields"))

  if schema["dynamic_start"] && schema["dynamic"]
    parse_dynamic_fields(effective_raw, schema["dynamic_start"].to_i, schema["dynamic"], detail)
  end

  parse_private_ic_fields(detail, direction, message_type)
  apply_common_detail_fields!(detail, direction)

  nice_pos = {
    "parser_type" => "private_fixed",
    "format" => schema["name"].to_s,
    "direction" => direction,
    "message_length" => header["message_length"],
    "version" => header["version"],
    "management_number" => header["management_number"],
    "message_type" => header["message_type"],
    "trade_code" => header["trade_code"],
    "cat_id" => header["cat_id"]
  }
  nice_pos["response_code"] = logical_byte_slice(effective_raw, 48, 4) if direction == "response"
  nice_pos["detail"] = detail
  apply_common_field_types!(nice_pos, direction)

  event.set("[nice_pos]", nice_pos)
end


# [7~9] 통합 TAG: Header로 방향 확인 -> TAG 순차 파싱 -> nice_pos Hash 구성 -> event.set 합니다.
def parse_integrated(event, raw)
  header = extract_compiled_fields(raw, @integrated_header_fields)
  direction = integrated_direction(header["send_receive"], event.get("status"))

  data = raw.byteslice(@integrated_data_start - 1, raw.bytesize) || ""
  detail, truncated = parse_integrated_tags(data, direction)
  event.tag("_nice_pos_truncated") if truncated

  trade_code = detail.delete("trade_code")
  response_code = detail.delete("response_code")
  apply_common_integrated_fallbacks!(detail, direction)

  nice_pos = {
    "parser_type" => "integrated_tag",
    "format" => "통합스펙 TAG-VALUE",
    "direction" => direction,
    "message_length" => header["message_length"],
    "cat_id" => header["cat_id"],
    "serial_number" => header["serial_number"],
    "transaction_large" => header["transaction_large"],
    "business_middle" => header["business_middle"],
    "detail_small" => header["detail_small"],
    "transaction_id" => header["transaction_id"],
    "send_receive" => header["send_receive"],
    "detail" => detail
  }

  nice_pos["trade_code"] = trade_code unless trade_code.nil?
  nice_pos["response_code"] = response_code unless response_code.nil?
  apply_common_field_types!(nice_pos, direction)
  event.set("[nice_pos]", nice_pos)
end


def parse_integrated_tags(data, direction)
  detail = {}
  truncated = false
  source_encoding = data.encoding
  binary = data.dup.force_encoding(Encoding::BINARY)
  cursor = 0

  while cursor < binary.bytesize
    cursor += 1 while cursor < binary.bytesize && binary.getbyte(cursor) == 0x1c
    break if cursor >= binary.bytesize || binary.getbyte(cursor) == 0x03

    tag_bytes = binary.byteslice(cursor, 3)
    break if tag_bytes.nil? || tag_bytes.bytesize < 3

    tag = tag_bytes.dup.force_encoding(Encoding::US_ASCII).to_s
    definition = @integrated_tags[tag]

    if @integrated_special_prefix_lookup.key?(tag[0]) && cursor + 8 <= binary.bytesize
      length_text = binary.byteslice(cursor + 3, 4)

      if length_text.match?(/\A\d{4}\z/)
        block_length = length_text.to_i
        value_length = [block_length - 1, 0].max
        available = [value_length, binary.bytesize - (cursor + 8)].min
        truncated = true if available < value_length
        value = restore_encoding(
          binary.byteslice(cursor + 8, available) || "".b,
          source_encoding
        )

        append_integrated_value(detail, definition, direction, value)
        cursor += 7 + block_length
        cursor += 1 if cursor < binary.bytesize && binary.getbyte(cursor) == 0x1c
        next
      end
    end

    value_start = cursor + 3
    fs_index = binary.index("\x1c".b, value_start)
    etx_index = binary.index("\x03".b, value_start)
    end_candidates = [fs_index, etx_index].compact
    value_end = end_candidates.empty? ? binary.bytesize : end_candidates.min

    value = restore_encoding(
      binary.byteslice(value_start, value_end - value_start) || "".b,
      source_encoding
    )
    append_integrated_value(detail, definition, direction, value)

    cursor = value_end
    if cursor < binary.bytesize && binary.getbyte(cursor) == 0x1c
      cursor += 1
    elsif cursor < binary.bytesize && binary.getbyte(cursor) == 0x03
      break
    end
  end

  [detail, truncated]
end


# 최종 21개 공통필드 중, 단순 key rename만으로 만들 수 없는 공통 필드를 보완합니다.
# 원문 파싱 위치/길이/Rule은 변경하지 않습니다. 숫자/date 타입 변환은 최종 nice_pos 단계에서만 수행합니다.
def apply_common_detail_fields!(detail, direction)
  return unless direction == "response"
  return unless match_value(detail["approval_datetime"]).empty?

  [["승인_거래일자", "승인_거래시간"],
   ["거래일자", "거래시간"],
   ["승인일자", "승인일시"]].each do |date_key, time_key|
    date_value = match_value(detail[date_key])
    time_value = match_value(detail[time_key])
    next if date_value.empty? || time_value.empty?

    detail["approval_datetime"] = "#{date_value}#{time_value}"
    break
  end
end


def apply_common_integrated_fallbacks!(detail, direction)
  apply_common_detail_fields!(detail, direction)
  return unless direction == "response"
  return unless match_value(detail["display_message"]).empty?

  # 일부 통합 전문은 대표 화면메시지가 A71 대신 B56에 존재합니다.
  fallback = detail["B56_응답메시지"]
  detail["display_message"] = fallback unless match_value(fallback).empty?
end


# 응답 화면메시지에 별도 필드인 승인번호가 뒤에 중복된 경우, 메시지에서만 제거합니다.
# approval_number 필드는 변경하지 않고 그대로 유지합니다.
def remove_approval_number_from_message!(detail, direction)
  return unless direction == "response"

  approval_number = match_value(detail["approval_number"]).strip
  display_message = match_value(detail["display_message"]).strip
  return if approval_number.empty? || display_message.empty?
  return unless display_message.end_with?(approval_number)

  message_only = display_message[0, display_message.length - approval_number.length].to_s.strip
  detail["display_message"] = message_only unless message_only.empty?
end


# JSON의 요청/응답별 공통 타입 정의를 최종 nice_pos Hash에만 적용합니다.
# keyword/text_keyword는 원문 문자열을 그대로 유지하고 숫자/date만 타입에 맞게 변환합니다.
def apply_common_field_types!(nice_pos, direction = nil)
  @common_type_converters["root"].each do |key, type|
    next unless nice_pos.key?(key)
    nice_pos[key] = convert_common_field_value(nice_pos[key], type)
  end

  detail = nice_pos["detail"]
  return unless detail.is_a?(Hash)

  remove_approval_number_from_message!(detail, direction)

  @common_type_converters["detail"].each do |key, type|
    next unless detail.key?(key)
    detail[key] = convert_common_field_value(detail[key], type)
  end
end


def convert_common_field_value(value, type)
  if value.is_a?(Array)
    converted = value.map { |item| convert_common_field_scalar(item, type) }.compact
    return converted.empty? ? nil : converted
  end

  convert_common_field_scalar(value, type)
end


def convert_common_field_scalar(value, type)
  return nil if value.nil?

  case type.to_s
  when "keyword", "text_keyword"
    value
  when "integer"
    parse_common_integer(value, -2_147_483_648, 2_147_483_647)
  when "long"
    parse_common_integer(value, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807)
  when "date"
    normalize_common_datetime(value)
  else
    value
  end
end


def parse_common_integer(value, min_value, max_value)
  text = match_value(value)
  return nil if text.empty? || !text.match?(/\A[+-]?\d+\z/)

  number = Integer(text, 10)
  return nil if number < min_value || number > max_value

  number
rescue ArgumentError, TypeError
  nil
end


def normalize_common_datetime(value)
  text = match_value(value)
  return nil if text.empty?

  # 이미 ISO-8601 형식이면 의미를 바꾸지 않고 그대로 둡니다.
  begin
    return Time.iso8601(text).iso8601 if text.match?(/\A\d{4}-\d{2}-\d{2}T/)
  rescue ArgumentError
    return nil
  end

  return nil unless text.match?(/\A\d+\z/)

  candidates = []
  case text.length
  when 12
    # 일반 승인: YYMMDDHHMMSS
    candidates << [
      2000 + text[0, 2].to_i, text[2, 2].to_i, text[4, 2].to_i,
      text[6, 2].to_i, text[8, 2].to_i, text[10, 2].to_i
    ]
    # 현금IC 등 일부 전문: YYYYMMDDHHMM (초 없음)
    candidates << [
      text[0, 4].to_i, text[4, 2].to_i, text[6, 2].to_i,
      text[8, 2].to_i, text[10, 2].to_i, 0
    ]
  when 14 # YYYYMMDDHHMMSS
    candidates << [
      text[0, 4].to_i, text[4, 2].to_i, text[6, 2].to_i,
      text[8, 2].to_i, text[10, 2].to_i, text[12, 2].to_i
    ]
  else
    return nil
  end

  candidates.each do |parts|
    begin
      return Time.new(*parts, @common_date_timezone).iso8601
    rescue ArgumentError
      next
    end
  end

  nil
end

# >>> GUIDE_D03: 수정 불필요 — JSON tag_specs.Q99의 request/response.key=coupon_code로 저장.
# <<< GUIDE_D03
def append_integrated_value(detail, definition, direction, value)
  return if definition.nil?

  field_spec = definition[direction] || definition["both"]
  return if field_spec.nil?

  append_value(detail, field_spec.fetch("key"), value)
end


def restore_encoding(value, encoding)
  value.dup.force_encoding(encoding)
end


# [7] Header 식별값으로 미리 만든 Lookup을 조회해 적용할 Schema를 선택합니다.
def choose_schema(lookup, schemas, values)
  states = [lookup]

  values.each do |value|
    value = value.to_s
    next_states = []

    states.each do |node|
      exact = node[value]
      wildcard = node["*"]
      next_states << exact unless exact.nil?
      next_states << wildcard unless wildcard.nil? || wildcard.equal?(exact)
    end

    return nil if next_states.empty?
    states = next_states
  end

  best = nil
  states.each do |node|
    candidate = node[:_match]
    next if candidate.nil?
    best = candidate if best.nil? || candidate[0] < best[0]
  end

  return nil if best.nil?
  schemas[best[1]["schema"].to_s]
end


def write_nice_header_only(event, header, direction, format_name)
  nice_pos = build_nice_header_hash(header, direction, format_name)
  apply_common_field_types!(nice_pos, direction)
  event.set("[nice_pos]", nice_pos)
end


def extract_compiled_fields(value, fields)
  detail = {}
  return detail if fields.empty?

  text = value.to_s

  if text.ascii_only?
    fields.each do |key, start_byte, length, _end_byte|
      detail[key] = text.byteslice(start_byte - 1, length) || ""
    end
    return detail
  end

  outputs = fields.map { +"" }
  field_index = 0
  position = 1
  last_end = fields[-1][3]

  text.each_char do |character|
    width = character.ord <= 0x7f ? 1 : 2
    character_start = position
    character_end = position + width - 1

    while field_index < fields.length && fields[field_index][3] < character_start
      field_index += 1
    end
    break if field_index >= fields.length || character_start > last_end

    index = field_index
    while index < fields.length && fields[index][1] <= character_end
      field_start = fields[index][1]
      field_end = fields[index][3]
      outputs[index] << character if field_end >= character_start && field_start <= character_end
      index += 1
    end

    position += width
  end

  fields.each_with_index { |field, index| detail[field[0]] = outputs[index] }
  detail
end


# [7~8] JSON에 dynamic 규격이 있는 경우에만 가변길이 영역을 추가로 파싱해 detail Hash에 넣습니다.
def parse_dynamic_fields(raw, cursor, definitions, detail)
  definitions.each do |field|
    case field["type"]
    when "fixed"
      detail[field["key"]] = logical_byte_slice(raw, cursor, field["length"].to_i)
      cursor += field["length"].to_i

# >>> GUIDE_D05: 수정 불필요 — JSON dynamic에 type=length_prefixed를 추가하면 이 기존 분기 사용.
# length_size=3으로 003을 읽고 다음 ABC를 extra_data에 넣습니다.
# <<< GUIDE_D05
    when "length_prefixed"
      length_text = logical_byte_slice(raw, cursor, field["length_size"].to_i)
      break if length_text.empty? && field["optional"]

      length = length_text.strip.to_i
      detail[field["length_key"]] = length_text
      cursor += field["length_size"].to_i
      detail[field["key"]] = logical_byte_slice(raw, cursor, length)
      cursor += length

    when "conditional_length_prefixed"
      next unless match_value(detail[field["when_key"]]) == field["equals"].to_s

      length_text = logical_byte_slice(raw, cursor, field["length_size"].to_i)
      length = length_text.strip.to_i
      detail[field["length_key"]] = length_text
      cursor += field["length_size"].to_i
      detail[field["key"]] = logical_byte_slice(raw, cursor, length)
      cursor += length

    when "length_from_previous"
      length = match_value(detail[field["length_key"]]).to_i
      detail[field["key"]] = logical_byte_slice(raw, cursor, length)
      cursor += length

    when "conditional_remaining"
      next unless match_value(detail[field["when_key"]]) == field["equals"].to_s

      tail_length = field.fetch("tail_length", 0).to_i
      remaining_length = logical_byte_length(raw) - cursor + 1 - tail_length
      remaining_length = 0 if remaining_length.negative?
      detail[field["key"]] = logical_byte_slice(raw, cursor, remaining_length)
      cursor += remaining_length

    when "remaining"
      detail[field["key"]] = logical_byte_drop(raw, cursor - 1)
      cursor = logical_byte_length(raw) + 1

    when "nice_common_request_tail"
      cursor = parse_nice_common_request_tail(raw, cursor, field, detail)

    when "nice_royalty_ic_tail"
      cursor = parse_nice_royalty_ic_tail(raw, cursor, field, detail)

    when "nice_cash_ic_tail"
      cursor = parse_nice_cash_ic_tail(raw, cursor, field, detail)

    when "nice_ifc_members"
      cursor = parse_nice_ifc_members(raw, cursor, field, detail)
    end
  end
end


def parse_nice_ifc_members(raw, cursor, field, detail)
  count = match_value(detail[field.fetch("count_key")]).to_i
  count = [count, field.fetch("max_count", 32).to_i].min
  number_length = field.fetch("member_number_length", 20).to_i
  name_length = field.fetch("member_name_length", 20).to_i

  count.times do
    number = logical_byte_slice(raw, cursor, number_length)
    break if number.empty?
    append_value(detail, field.fetch("member_number_key"), number)
    cursor += number_length

    name = logical_byte_slice(raw, cursor, name_length)
    append_value(detail, field.fetch("member_name_key"), name)
    cursor += name_length
  end

  cursor
end


def parse_nice_common_request_tail(raw, cursor, field, detail)
  total_length = logical_byte_length(raw)
  return total_length + 1 if cursor > total_length

  tail = logical_byte_drop(raw, cursor - 1)
  local_cursor = 1
  moneyplus = field["moneyplus"]

  if !moneyplus.nil? && nice_moneyplus_block?(tail, local_cursor)
    local_cursor = parse_nice_moneyplus_block(tail, local_cursor, moneyplus, detail)
  end

  sign_key = field.fetch("sign_key")
  sign_value = logical_byte_slice(tail, local_cursor, 1)
  if !sign_value.empty?
    detail[sign_key] = sign_value
    local_cursor += 1
  end

  if match_value(sign_value) == "Y"
    sign_total_length = field.fetch("sign_total_length", 1084).to_i
    available = logical_byte_length(tail) - local_cursor + 1
    sign_length = [sign_total_length, [available, 0].max].min
    detail[field.fetch("sign_data_key")] = logical_byte_slice(tail, local_cursor, sign_length)
    local_cursor += sign_length
  end

  parse_nice_royalty_ic_segment(logical_byte_drop(tail, local_cursor - 1), field, detail)
  cursor + logical_byte_length(tail)
end


def parse_nice_royalty_ic_tail(raw, cursor, field, detail)
  total_length = logical_byte_length(raw)
  return total_length + 1 if cursor > total_length

  tail = logical_byte_drop(raw, cursor - 1)
  parse_nice_royalty_ic_segment(tail, field, detail)
  total_length + 1
end


def parse_nice_cash_ic_tail(raw, cursor, field, detail)
  total_length = logical_byte_length(raw)
  return total_length + 1 if cursor > total_length

  tail = logical_byte_drop(raw, cursor - 1)
  local_cursor = 1
  moneyplus = field["moneyplus"]

  if !moneyplus.nil? && nice_moneyplus_block?(tail, local_cursor)
    local_cursor = parse_nice_moneyplus_block(tail, local_cursor, moneyplus, detail)
  end

  cr_value = logical_byte_slice(tail, local_cursor, 1)
  detail[field.fetch("cr_key")] = cr_value unless cr_value.empty?
  cursor + logical_byte_length(tail)
end


def nice_moneyplus_block?(tail, cursor)
  return false unless logical_byte_slice(tail, cursor, 3) == "NVC"

  info_flag = match_value(logical_byte_slice(tail, cursor + 19, 1))
  info_flag == "Y" || info_flag == "N"
end


def parse_nice_moneyplus_block(tail, cursor, config, detail)
  detail[config.fetch("device_rom_key")] = logical_byte_slice(tail, cursor, 19)
  cursor += 19
  detail[config.fetch("info_flag_key")] = logical_byte_slice(tail, cursor, 1)
  cursor += 1
  detail[config.fetch("merchant_code_key")] = logical_byte_slice(tail, cursor, 3)
  cursor += 3
  detail[config.fetch("extra_info_key")] = logical_byte_slice(tail, cursor, 100)
  cursor += 100

  cursor + config.fetch("filler_length").to_i
end


def parse_nice_royalty_ic_segment(segment, field, detail)
  return if segment.nil? || segment.empty? || match_value(segment).empty?

  ic_start = find_nice_ic_block_start(segment)
  royalty_key = field["royalty_key"]

  if ic_start.nil?
    detail[royalty_key] = segment if !royalty_key.nil? && !match_value(segment).empty?
    return
  end

  if ic_start > 1 && !royalty_key.nil?
    royalty = logical_byte_slice(segment, 1, ic_start - 1)
    detail[royalty_key] = royalty unless match_value(royalty).empty?
  end

  parse_nice_ic_block(segment, ic_start, field, detail)
end


def find_nice_ic_block_start(segment)
  total_length = logical_byte_length(segment)
  return nil if total_length < 4

  position = 1
  while position <= total_length - 3
    length_text = logical_byte_slice(segment, position, 4)
    if length_text.match?(/\A\d{4}\z/)
      data_length = length_text.to_i
      suffix_start = position + 4 + data_length
      if suffix_start <= total_length + 1 && nice_ic_suffix_valid?(segment, suffix_start, total_length)
        return position
      end
    end
    position += 1
  end

  nil
end


def nice_ic_suffix_valid?(segment, cursor, total_length)
  return true if cursor > total_length

  remainder = logical_byte_slice(segment, cursor, total_length - cursor + 1)
  return true if match_value(remainder).empty?

  if logical_byte_slice(segment, cursor, 3) == "PID"
    return false if cursor + 3 + 15 - 1 > total_length
    cursor += 18
  end

  if logical_byte_slice(segment, cursor, 3) == "MAC"
    return false if cursor + 3 + 32 - 1 > total_length
    cursor += 35
  end

  return true if logical_byte_slice(segment, cursor, 6) == "IPADDR"
  return true if cursor > total_length

  match_value(logical_byte_slice(segment, cursor, total_length - cursor + 1)).empty?
end


def parse_nice_ic_block(segment, cursor, field, detail)
  total_length = logical_byte_length(segment)
  length_text = logical_byte_slice(segment, cursor, 4)
  return cursor unless length_text.match?(/\A\d{4}\z/)

  data_length = length_text.to_i
  detail[field.fetch("ic_length_key")] = length_text
  cursor += 4
  detail[field.fetch("ic_key")] = logical_byte_slice(segment, cursor, data_length) if data_length.positive?
  cursor += data_length

  if logical_byte_slice(segment, cursor, 3) == "PID"
    cursor += 3
    detail[field.fetch("pid_key")] = logical_byte_slice(segment, cursor, 15)
    cursor += 15
  end

  if logical_byte_slice(segment, cursor, 3) == "MAC"
    cursor += 3
    detail[field.fetch("mac_key")] = logical_byte_slice(segment, cursor, 32)
    cursor += 32
  end

  if logical_byte_slice(segment, cursor, 6) == "IPADDR"
    cursor += 6
    detail[field.fetch("ip_key")] = logical_byte_slice(segment, cursor, total_length - cursor + 1)
    cursor = total_length + 1
  end

  cursor
end


def parse_private_ic_fields(detail, direction, message_type)
  ic_data = detail["IC데이터"]
  return if ic_data.nil? || ic_data.empty?

  schema_key = if direction == "request"
                 "request"
               elsif %w[0430 0330].include?(message_type)
                 "response_cancel"
               else
                 "response_approval"
               end

  fields = @private_ic_fields[schema_key]
  return if fields.nil?

  extract_compiled_fields(ic_data, fields).each { |key, value| detail[key] = value }
end


def append_value(hash, key, value)
  current = hash[key]

  if current.nil?
    hash[key] = value
  elsif current.is_a?(Array)
    current << value
  else
    hash[key] = [current, value]
  end
end


def professional_direction(message_type, status)
  return "request" if %w[0200 0300 0320 0420 0480].include?(message_type)
  return "response" if %w[0210 0310 0330 0430 0490].include?(message_type)
  return "request" if status.to_s == "OUT"
  return "response" if status.to_s == "IN"

  "unknown"
end


def integrated_direction(send_receive, status)
  value = match_value(send_receive)
  return "request" if value == "S"
  return "response" if value == "R"
  return "request" if status.to_s == "OUT"
  return "response" if status.to_s == "IN"

  "unknown"
end


def trim_to_declared_length(raw, length_text)
  length = match_value(length_text).to_i
  return raw if length <= 0

  logical_byte_slice(raw, 1, length)
end


def logical_byte_slice(value, start_byte, length)
  return "" if start_byte <= 0 || length <= 0

  text = value.to_s
  return text.byteslice(start_byte - 1, length) || "" if text.ascii_only?

  end_byte = start_byte + length - 1
  output = +""
  position = 1

  text.each_char do |character|
    width = character.ord <= 0x7f ? 1 : 2
    character_start = position
    character_end = position + width - 1
    output << character if character_end >= start_byte && character_start <= end_byte
    position += width
    break if position > end_byte
  end

  output
end


def logical_byte_drop(value, byte_count)
  text = value.to_s
  return text.byteslice(byte_count, text.bytesize) || "" if text.ascii_only?

  output = +""
  position = 1

  text.each_char do |character|
    width = character.ord <= 0x7f ? 1 : 2
    character_end = position + width - 1
    output << character if character_end > byte_count
    position += width
  end

  output
end


def logical_byte_length(value)
  text = value.to_s
  return text.bytesize if text.ascii_only?

  text.each_char.sum { |character| character.ord <= 0x7f ? 1 : 2 }
end


def match_value(value)
  value.to_s.strip
end
