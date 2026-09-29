# frozen_string_literal: true

require "json"
require "time"

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

  nice = spec.fetch("nice_fixed")
  @nice_schemas, nice_rules = load_schema_rule_merchants(nice)
  compile_schema_fields!(@nice_schemas)
  @nice_lookup = build_rule_lookup(
    nice_rules,
    %w[text trade message_type direction message_length]
  )

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
  @nice_schema_validation_min_score = fallback_config.fetch("schema_validation_min_score", 8.0).to_f
  @nice_schema_validation_min_margin = fallback_config.fetch("schema_validation_min_margin", 3.0).to_f
  @nice_schema_validation_min_evidence = fallback_config.fetch("schema_validation_min_evidence", 3).to_i
  @nice_schema_validation_require_unique_structure = fallback_config.fetch("schema_validation_require_unique_structure", true) == true
  @nice_unregistered_text_seen_tag = "_nice_pos_unregistered_text_seen".freeze
  @nice_text_code_lookup = build_explicit_condition_lookup(nice_rules, "text").freeze

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

  external = spec.fetch("external_fixed", {})
  @external_root_field_lookup = %w[external_version message_type trade_code cat_id response_code].each_with_object({}) do |key, lookup|
    lookup[key] = true
  end.freeze
  @external_schemas = external.fetch("schemas", {}).each_with_object({}) do |(schema_id, schema), active|
    active[schema_id] = schema unless schema["runtime_enabled"] == false
  end
  compile_external_schema_fields!(@external_schemas)
  external_common = external.fetch("common_fallback", {})
  @external_common_enabled = external_common.fetch("enabled", true) == true
  @external_common_format = external_common.fetch("format", "UNKNOWN").to_s
  @external_common_tag = external_common.fetch("tag", "_nice_pos_common_fields_fallback").to_s
  @external_common_profiles,
    @external_common_profiles_by_merchant_length,
    @external_common_profiles_by_merchant_any_length = compile_external_common_profiles(
    external_common,
    @external_schemas
  )
  @external_rules_by_merchant_length,
    @external_rules_by_merchant_any_length,
    @external_rules_by_merchant_all,
    @external_short_transport_lookup = compile_external_rules(
    external,
    @external_schemas
  )
  @external_source_route_lookup = external.fetch("source_routes", {}).each_with_object({}) do |(source_id, merchant), lookup|
    lookup[source_id.to_s] = merchant.to_s
  end.freeze
  @external_source_route_pattern = if @external_source_route_lookup.empty?
                                     nil
                                   else
                                     alternatives = @external_source_route_lookup.keys.map { |source_id| Regexp.escape(source_id) }
                                     Regexp.new("(?:#{alternatives.join('|')})(?=[^A-Za-z0-9]|$)").freeze
                                   end
  @external_prefix_names = external.fetch("prefix_names", {}).each_with_object({}) do |(prefix, name), lookup|
    lookup[prefix.to_s] = name.to_s
  end
  @external_allowed_trailer_lookup = external.fetch("allowed_transport_trailer_lengths", [0]).each_with_object({}) do |length, lookup|
    lookup[length.to_i] = true
  end

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
  @external_schemas.freeze
  @external_common_profiles.freeze
  @external_common_profiles_by_merchant_length.freeze
  @external_common_profiles_by_merchant_any_length.freeze
  @external_common_format.freeze
  @external_common_tag.freeze
  @external_rules_by_merchant_length.freeze
  @external_rules_by_merchant_any_length.freeze
  @external_rules_by_merchant_all.freeze
  @external_short_transport_lookup.freeze
  @external_source_route_lookup.freeze
  @external_prefix_names.freeze
  @external_allowed_trailer_lookup.freeze
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

def compile_external_schema_fields!(schemas)
  schemas.each_value do |schema|
    compiled_fields = compile_fields(schema.fetch("fields", []))
    schema["_compiled_external_fields"] = compiled_fields.map do |key, start_byte, length, end_byte|
      [key, start_byte, length, end_byte, @external_root_field_lookup.key?(key)].freeze
    end.freeze

    compiled_delimiter_fields = schema.fetch("delimiter_fields", []).map do |field|
      key = field.fetch("key").to_s
      [field.fetch("index").to_i, key, @external_root_field_lookup.key?(key)].freeze
    end.freeze
    schema["_compiled_external_delimiter_fields"] = compiled_delimiter_fields
    default_minimum_length = compiled_fields.empty? ? 0 : compiled_fields[-1][3]
    schema["_compiled_external_minimum_length"] = schema.fetch("min_required_length", default_minimum_length).to_i
    default_minimum_parts = if compiled_delimiter_fields.empty?
                              0
                            else
                              compiled_delimiter_fields.map(&:first).max + 1
                            end
    schema["_compiled_external_minimum_parts"] = schema.fetch("min_required_parts", default_minimum_parts).to_i
  end
end

def compile_external_common_profiles(section, schemas)
  profiles = {}
  by_merchant_length = {}
  by_merchant_any_length = {}

  section.fetch("profiles", []).each_with_index do |definition, index|
    profile_id = definition.fetch("id").to_s
    raise "duplicate external common profile: #{profile_id}" if profiles.key?(profile_id)

    base_schema_id = definition.fetch("base_schema").to_s
    base_schema = schemas[base_schema_id]
    raise "unknown external common base schema: #{base_schema_id}" if base_schema.nil?

    merchant = definition.fetch("merchant").to_s
    raise "external common merchant mismatch: #{profile_id}" unless base_schema.fetch("merchant").to_s == merchant

    included = definition.fetch("include_fields", []).each_with_object({}) do |key, lookup|
      lookup[key.to_s] = true
    end
    fixed_fields = base_schema.fetch("fields", []).select { |field| included.key?(field.fetch("key").to_s) }
    delimiter_fields = base_schema.fetch("delimiter_fields", []).select do |field|
      included.key?(field.fetch("key").to_s)
    end
    available = (fixed_fields + delimiter_fields).each_with_object({}) do |field, lookup|
      lookup[field.fetch("key").to_s] = true
    end
    missing = included.keys.reject { |key| available.key?(key) }
    raise "unknown external common field #{profile_id}: #{missing.join(',')}" unless missing.empty?

    profile = {
      "id" => profile_id,
      "merchant" => merchant,
      "direction" => definition.fetch("direction").to_s,
      "priority" => (definition.key?("priority") ? definition["priority"].to_i : index),
      "base_schema" => base_schema_id,
      "wire_format" => base_schema["wire_format"],
      "fields" => fixed_fields,
      "delimiter_fields" => delimiter_fields
    }
    %w[
      delimiter delimiter_start min_required_length min_required_parts
      approval_datetime_trim_trailing_zero_length
    ].each do |key|
      profile[key] = base_schema[key] if base_schema.key?(key)
    end

    condition = definition.fetch("when", {})
    profile["_compiled_conditions"] = condition.fetch("fields", []).map do |field|
      values = field.fetch("values", []).each_with_object({}) do |value, lookup|
        lookup[value.to_s] = true
      end.freeze
      [field.fetch("start").to_i, field.fetch("length").to_i, values].freeze
    end.freeze
    profile["_declared_length_lookup"] = condition.fetch("declared_length", []).each_with_object({}) do |length, lookup|
      lookup[length.to_i] = true
    end.freeze
    lengths = condition.fetch("length", []).map(&:to_i)
    profile["_length_lookup"] = lengths.each_with_object({}) { |length, lookup| lookup[length] = true }.freeze
    profiles[profile_id] = profile

    if lengths.empty?
      (by_merchant_any_length[merchant] ||= []) << profile
    else
      merchant_lengths = (by_merchant_length[merchant] ||= {})
      lengths.each { |length| (merchant_lengths[length] ||= []) << profile }
    end
  end

  compile_external_schema_fields!(profiles)
  by_merchant_length.each_value do |length_lookup|
    length_lookup.each_value do |items|
      items.sort_by! { |profile| profile["priority"] }
      items.freeze
    end
    length_lookup.freeze
  end
  by_merchant_any_length.each_value do |items|
    items.sort_by! { |profile| profile["priority"] }
    items.freeze
  end
  profiles.each_value(&:freeze)
  [profiles.freeze, by_merchant_length.freeze, by_merchant_any_length.freeze]
end

def compile_external_rules(section, schemas)
  by_merchant_length = {}
  by_merchant_any_length = {}
  by_merchant_all = {}
  short_transport_by_merchant = {}

  section.fetch("rules", []).each_with_index do |rule, index|
    schema_id = rule.fetch("schema").to_s
    schema = schemas[schema_id]
    next if schema.nil?

    merchant = schema.fetch("merchant").to_s
    merchant_lengths = (by_merchant_length[merchant] ||= {})
    merchant_any_length = (by_merchant_any_length[merchant] ||= [])
    merchant_all = (by_merchant_all[merchant] ||= [])

    condition = rule.fetch("when", {})
    compiled_conditions = condition.fetch("fields", []).map do |field|
      values = field.fetch("values", []).each_with_object({}) do |value, lookup|
        lookup[value.to_s] = true
      end.freeze
      [field.fetch("start").to_i, field.fetch("length").to_i, values].freeze
    end.freeze
    declared_length_lookup = condition.fetch("declared_length", []).each_with_object({}) do |length, lookup|
      lookup[length.to_i] = true
    end.freeze

    compiled = {
      "schema" => schema_id,
      "priority" => (rule.key?("priority") ? rule["priority"].to_i : index),
      "_compiled_conditions" => compiled_conditions,
      "_declared_length_lookup" => declared_length_lookup
    }.freeze
    merchant_all << compiled

    lengths = condition["length"]
    if lengths.nil? || lengths.empty?
      merchant_any_length << compiled
    else
      lengths.each do |length|
        merchant_lengths[length.to_i] ||= []
        merchant_lengths[length.to_i] << compiled
      end

      declared_lengths = condition.fetch("declared_length", [])
      unless declared_lengths.empty?
        short_lookup = (short_transport_by_merchant[merchant] ||= {})
        declared_lengths.each do |declared_length|
          lengths.each do |body_length|
            declared = declared_length.to_i
            actual = body_length.to_i
            short_lookup[[declared, actual].freeze] = true if actual < declared
          end
        end
      end
    end
  end

  by_merchant_length.each_value do |length_lookup|
    length_lookup.each_value do |rules|
      rules.sort_by! { |rule| rule["priority"] }
      rules.freeze
    end
    length_lookup.freeze
  end
  by_merchant_any_length.each_value do |rules|
    rules.sort_by! { |rule| rule["priority"] }
    rules.freeze
  end
  by_merchant_all.each_value do |rules|
    rules.sort_by! { |rule| rule["priority"] }
    rules.freeze
  end
  short_transport_by_merchant.each_value(&:freeze)
  [by_merchant_length, by_merchant_any_length, by_merchant_all, short_transport_by_merchant]
end

def filter(event)
  body = event.get("b_body")
  return [event] if body.nil? || body.to_s.empty?

  external_merchant = external_source_merchant(event)
  raw = extract_professional(body.to_s, external_merchant)
  return [event] if raw.nil?

  begin
    external_match = external_merchant.nil? ? nil : match_external_message(raw, external_merchant)
    if external_match && external_match["incomplete"]
      reject_incomplete_external(event, external_match, external_merchant)
    elsif external_match
      parse_external_fixed(event, external_match)
    elsif !external_merchant.nil?
      mark_unmatched_external(event, raw, external_merchant)
    elsif integrated_message?(raw)
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

  normalize_nice_pos_operational_tags(event)

  [event]
end

def normalize_nice_pos_operational_tags(event)
  tags = event.get("tags")
  return if tags.nil?

  current = tags.is_a?(Array) ? tags.map(&:to_s) : [tags.to_s]
  internal = current.select { |tag| tag.start_with?("_nice_pos_") }
  return if internal.empty?

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

def build_rule_lookup(rules, dimensions)
  root = {}

  rules.each_with_index do |rule, index|
    priority = rule.key?("priority") ? rule["priority"].to_i : index
    condition = rule["when"] || {}

    value_sets = dimensions.map do |dimension|
      values = condition[dimension]
      values.nil? || values.empty? ? ["*"] : values.map(&:to_s)
    end

    value_sets[0].product(*value_sets[1..-1]).each do |combination|
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

def build_rule_candidate_lookup(rules, dimensions)
  root = {}

  rules.each_with_index do |rule, index|
    priority = rule.key?("priority") ? rule["priority"].to_i : index
    condition = rule["when"] || {}

    value_sets = dimensions.map do |dimension|
      values = condition[dimension]
      values.nil? || values.empty? ? ["*"] : values.map(&:to_s)
    end

    value_sets[0].product(*value_sets[1..-1]).each do |combination|
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

def extract_professional(body, external_merchant = nil)
  text = body.sub(/\A\[(?:OUT|IN)\]\s*/, "")

  payload = if (match = text.match(/\A\[\d{1,8}\]\[(.*)\]\s*\z/m))
              match[1]
            elsif (match = text.match(/\A\[\d{1,8}\]\[(.*)\z/m))
              match[1]
            elsif text.start_with?("[")
              value = text[1..-1] || ""
              value = value.sub(/\]\[\d{1,8}\]\s*\z/m, "")
              value.sub(/\]\s*\z/m, "")
            else
              text
            end

  stx_index = payload.index("\u0002")
  if !stx_index.nil? && stx_index.positive?
    prefix = payload[0...stx_index]
    payload = payload[stx_index..-1] if prefix.match?(/\AEA\d{10}\z/)
  end

  return payload unless external_merchant.nil?
  return payload if payload.start_with?("\u0002")
  return payload if payload.match?(/\A\d{4}/m)

  nil
end

def external_source_merchant(event)
  return nil if @external_source_route_pattern.nil?

  path = event.get("[log][file][path]")
  return nil if path.nil?

  match = @external_source_route_pattern.match(path.to_s)
  match.nil? ? nil : @external_source_route_lookup[match[0]]
end

def match_external_message(raw, external_merchant)
  return nil if external_merchant.nil?
  return nil if @external_rules_by_merchant_length.nil? || @external_rules_by_merchant_any_length.nil?

  candidates = external_message_candidates(raw, external_merchant)
  incomplete_candidate = nil
  candidates.each do |candidate|
    body = candidate["body"]
    body_length = logical_byte_length(body)
    rule, incomplete_rule = choose_external_rule(body, body_length, candidate["declared_length"].to_i, external_merchant)
    if !rule.nil? && candidate["force_incomplete"]
      incomplete_rule = rule
      rule = nil
    end
    if rule.nil? && !incomplete_rule.nil?
      incomplete_candidate ||= candidate.merge(
        "rule" => incomplete_rule,
        "schema" => @external_schemas[incomplete_rule["schema"]],
        "incomplete" => true
      )
    end
    next if rule.nil?

    schema = @external_schemas[rule["schema"]]
    next if schema.nil?

    candidate["rule"] = rule
    candidate["schema"] = schema
    candidate["incomplete"] = false
    return candidate
  end

  incomplete_candidate
end

def external_message_candidates(raw, external_merchant)
  candidates = []
  raw_length = logical_byte_length(raw)
  length_text = logical_byte_slice(raw, 1, 4)

  if length_text.match?(/\A\d{4}\z/)
    declared_length = length_text.to_i
    available_length = raw_length - 4
    trailer_length = available_length - declared_length
    if declared_length.positive? && trailer_length >= 0 && @external_allowed_trailer_lookup.key?(trailer_length)
      candidates << {
        "body" => logical_byte_slice(raw, 5, declared_length),
        "declared_length" => declared_length,
        "transport_prefix_length" => 4,
        "transport_trailer_length" => trailer_length,
        "transport_missing_length" => 0
      }
    elsif declared_length.positive? && available_length.positive? && available_length < declared_length
      allowed_short = (@external_short_transport_lookup[external_merchant] || {}).key?([declared_length, available_length])
      candidates << {
        "body" => logical_byte_slice(raw, 5, available_length),
        "declared_length" => declared_length,
        "transport_prefix_length" => 4,
        "transport_trailer_length" => 0,
        "transport_missing_length" => declared_length - available_length,
        "force_incomplete" => !allowed_short
      }
    end
  end

  candidates << {
    "body" => raw,
    "declared_length" => raw_length,
    "transport_prefix_length" => 0,
    "transport_trailer_length" => 0,
    "transport_missing_length" => 0
  }
  candidates
end

def choose_external_rule(body, body_length, declared_length, external_merchant)
  incomplete_rule = nil
  merchant_lengths = @external_rules_by_merchant_length[external_merchant]
  exact_rules = merchant_lengths.nil? ? nil : merchant_lengths[body_length]
  unless exact_rules.nil?
    exact_rules.each do |rule|
      status = external_rule_match_status(body, body_length, rule, declared_length)
      return [rule, nil] if status == :complete
      incomplete_rule ||= rule if status == :incomplete
    end
  end

  any_length_rules = @external_rules_by_merchant_any_length[external_merchant] || []
  any_length_rules.each do |rule|
    status = external_rule_match_status(body, body_length, rule, declared_length)
    return [rule, nil] if status == :complete
    incomplete_rule ||= rule if status == :incomplete
  end

  if incomplete_rule.nil?
    (@external_rules_by_merchant_all[external_merchant] || []).each do |rule|
      if external_rule_identity_match?(body, rule, declared_length)
        incomplete_rule = rule
        break
      end
    end
  end

  [nil, incomplete_rule]
end

def external_rule_match_status(body, body_length, rule, declared_length)
  return :none unless external_rule_identity_match?(body, rule, declared_length)

  schema = @external_schemas[rule["schema"]]
  external_schema_complete?(body, body_length, schema) ? :complete : :incomplete
end

def external_rule_identity_match?(body, rule, declared_length)
  declared_lookup = rule.fetch("_declared_length_lookup", {})
  return false if !declared_lookup.empty? && !declared_lookup.key?(declared_length)

  rule.fetch("_compiled_conditions", []).all? do |start_byte, length, allowed_values|
    value = logical_byte_slice(body, start_byte, length)
    allowed_values.key?(value)
  end
end

def external_schema_complete?(body, body_length, schema)
  return false if schema.nil?
  return false if body_length < schema.fetch("_compiled_external_minimum_length", 0).to_i

  minimum_parts = schema.fetch("_compiled_external_minimum_parts", 0).to_i
  return true if minimum_parts <= 0

  delimiter = schema.fetch("delimiter", "\u001c").to_s
  delimiter_start = schema.fetch("delimiter_start", 1).to_i
  segment = logical_byte_drop(body, delimiter_start - 1)
  segment.split(delimiter, -1).length >= minimum_parts
end

def match_external_common_profile(raw, external_merchant)
  return nil unless @external_common_enabled

  merchant_lengths = @external_common_profiles_by_merchant_length[external_merchant]
  merchant_any_length = @external_common_profiles_by_merchant_any_length[external_merchant] || []
  return nil if merchant_lengths.nil? && merchant_any_length.empty?

  candidates = external_message_candidates(raw, external_merchant)
  normalized = candidates.select do |candidate|
    candidate["transport_prefix_length"].to_i.positive? && !candidate["force_incomplete"]
  end
  candidates = normalized unless normalized.empty?

  candidates.each do |candidate|
    next if candidate["force_incomplete"]

    body = candidate["body"]
    body_length = logical_byte_length(body)
    profiles = []
    profiles.concat(merchant_lengths[body_length]) unless merchant_lengths.nil? || merchant_lengths[body_length].nil?
    profiles.concat(merchant_any_length)
    matched = profiles.select do |profile|
      external_common_profile_match?(body, body_length, candidate["declared_length"].to_i, profile)
    end
    next if matched.empty?

    return nil unless matched.length == 1

    return candidate.merge("schema" => matched.first, "incomplete" => false)
  end

  nil
end

def external_common_profile_match?(body, body_length, declared_length, profile)
  declared_lookup = profile.fetch("_declared_length_lookup", {})
  return false if !declared_lookup.empty? && !declared_lookup.key?(declared_length)

  identity_match = profile.fetch("_compiled_conditions", []).all? do |start_byte, length, allowed_values|
    value = logical_byte_slice(body, start_byte, length)
    allowed_values.key?(value)
  end
  return false unless identity_match

  external_schema_complete?(body, body_length, profile)
end

def reject_incomplete_external(event, match, external_merchant)
  body = match.fetch("body", "")
  schema = match["schema"] || {}
  event.set("[nice_pos]", {
    "parser_type" => "external_rejected",
    "format" => schema["name"].to_s,
    "merchant" => external_merchant.to_s,
    "message_length" => logical_byte_length(body),
    "declared_message_length" => match["declared_length"].to_i,
    "parse_error" => "incomplete external message"
  })
  event.tag("_nice_pos_incomplete_message")
end

def mark_unmatched_external(event, raw, external_merchant)
  common_match = match_external_common_profile(raw, external_merchant)
  unless common_match.nil?
    parse_external_common(event, common_match, external_merchant)
    return
  end

  event.set("[nice_pos]", {
    "parser_type" => "external_unmatched",
    "format" => "UNKNOWN",
    "merchant" => external_merchant.to_s,
    "direction" => professional_direction("", event.get("status")),
    "message_length" => logical_byte_length(raw),
    "detail" => {}
  })
  event.tag("_nice_pos_unmatched_format")
end

def parse_external_common(event, match, external_merchant)
  body = match.fetch("body")
  profile = match.fetch("schema")
  root_fields, detail = extract_external_schema_fields(body, profile)
  normalize_external_approval_datetime!(detail, profile)
  detail.delete_if { |_key, value| value.nil? || match_value(value).empty? }

  external_version = match_value(root_fields["external_version"])
  message_type = match_value(root_fields["message_type"])
  trade_code = match_value(root_fields["trade_code"])
  cat_id = match_value(root_fields["cat_id"])
  response_code = match_value(root_fields["response_code"])

  merchant = @external_prefix_names[external_version]
  merchant = external_merchant.to_s if merchant.nil? || merchant.empty?
  direction = profile["direction"].to_s
  direction = professional_direction(message_type, event.get("status")) if direction.empty? || direction == "both"

  nice_pos = {
    "parser_type" => "external_common",
    "format" => @external_common_format,
    "merchant" => merchant,
    "direction" => direction,
    "message_length" => logical_byte_length(body),
    "detail" => detail
  }
  nice_pos["external_version"] = external_version unless external_version.empty?
  nice_pos["message_type"] = message_type unless message_type.empty?
  nice_pos["trade_code"] = trade_code unless trade_code.empty?
  nice_pos["cat_id"] = cat_id unless cat_id.empty?
  nice_pos["response_code"] = response_code unless response_code.empty?

  declared_length = match["declared_length"].to_i
  actual_length = logical_byte_length(body)
  nice_pos["declared_message_length"] = declared_length if declared_length.positive? && declared_length != actual_length
  trailer_length = match["transport_trailer_length"].to_i
  nice_pos["transport_trailer_length"] = trailer_length if trailer_length.positive?
  missing_length = match["transport_missing_length"].to_i
  nice_pos["transport_missing_length"] = missing_length if missing_length.positive?

  apply_common_field_types!(nice_pos, direction)
  detail.delete_if { |_key, value| value.nil? || match_value(value).empty? }
  event.set("[nice_pos]", nice_pos)
  event.tag(@external_common_tag) unless @external_common_tag.empty?
end

def parse_external_fixed(event, match)
  body = match.fetch("body")
  schema = match.fetch("schema")
  root_fields, detail = extract_external_schema_fields(body, schema)
  normalize_external_approval_datetime!(detail, schema)
  detail.delete_if { |_key, value| value.nil? || match_value(value).empty? }

  external_version = match_value(root_fields["external_version"])
  message_type = match_value(root_fields["message_type"])
  trade_code = match_value(root_fields["trade_code"])
  cat_id = match_value(root_fields["cat_id"])
  response_code = match_value(root_fields["response_code"])

  merchant = @external_prefix_names[external_version]
  merchant = schema["merchant"].to_s if merchant.nil? || merchant.empty?
  direction = schema["direction"].to_s
  direction = professional_direction(message_type, event.get("status")) if direction.empty? || direction == "both"

  nice_pos = {
    "parser_type" => (schema["wire_format"].to_s == "field_separator" ? "external_delimited" : "external_fixed"),
    "format" => schema["name"].to_s,
    "merchant" => merchant,
    "direction" => direction,
    "message_length" => logical_byte_length(body),
    "detail" => detail
  }
  nice_pos["external_version"] = external_version unless external_version.empty?
  nice_pos["message_type"] = message_type unless message_type.empty?
  nice_pos["trade_code"] = trade_code unless trade_code.empty?
  nice_pos["cat_id"] = cat_id unless cat_id.empty?
  nice_pos["response_code"] = response_code unless response_code.empty?

  declared_length = match["declared_length"].to_i
  actual_length = logical_byte_length(body)
  nice_pos["declared_message_length"] = declared_length if declared_length.positive? && declared_length != actual_length
  trailer_length = match["transport_trailer_length"].to_i
  nice_pos["transport_trailer_length"] = trailer_length if trailer_length.positive?
  missing_length = match["transport_missing_length"].to_i
  nice_pos["transport_missing_length"] = missing_length if missing_length.positive?

  apply_common_field_types!(nice_pos, direction)
  detail.delete_if { |_key, value| value.nil? || match_value(value).empty? }
  event.set("[nice_pos]", nice_pos)
end

def extract_external_schema_fields(body, schema)
  fields = schema.fetch("_compiled_external_fields", [])
  root_fields = {}
  detail = {}

  unless fields.empty?
    text = body.to_s
    if text.ascii_only?
      fields.each do |key, start_byte, length, _end_byte, root_field|
        target = root_field ? root_fields : detail
        target[key] = text.byteslice(start_byte - 1, length) || ""
      end
    else
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

      fields.each_with_index do |field, index|
        target = field[4] ? root_fields : detail
        target[field[0]] = outputs[index]
      end
    end
  end

  extract_external_delimited_fields(body, schema, root_fields, detail)
  [root_fields, detail]
end

def extract_external_delimited_fields(body, schema, root_fields, detail)
  fields = schema.fetch("_compiled_external_delimiter_fields", [])
  return if fields.empty?

  delimiter = schema.fetch("delimiter", "\u001c").to_s
  delimiter_start = schema.fetch("delimiter_start", 1).to_i
  segment = logical_byte_drop(body, delimiter_start - 1)
  parts = segment.split(delimiter, -1)

  fields.each do |index, key, root_field|
    next if index.negative? || index >= parts.length

    target = root_field ? root_fields : detail
    target[key] = parts[index]
  end
end

def normalize_external_approval_datetime!(detail, schema)
  value = detail["approval_datetime"]
  return if value.nil?

  text = match_value(value)
  digits = text.gsub(/[^0-9]/, "")
  trim_length = schema.fetch("approval_datetime_trim_trailing_zero_length", 0).to_i
  if trim_length.positive? && digits.length == trim_length && digits.end_with?("0")
    digits = digits[0, 12]
  end
  detail["approval_datetime"] = digits if [12, 14].include?(digits.length)
end

def integrated_message?(raw)
  raw.start_with?("\u0002") && raw.byteslice(1, 4).to_s.match?(/\A\d{4}\z/)
end

def private_message?(raw)
  version = match_value(logical_byte_slice(raw, 5, 7))
  @private_version_lookup.key?(version)
end

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

  complete, declared_length, effective_raw = complete_nice_message(raw, message_length)
  unless complete
    event.tag(@nice_incomplete_tag) unless @nice_incomplete_tag.empty?
    event.tag(@nice_known_code_mismatch_tag) if text_registered && !@nice_known_code_mismatch_tag.empty?
    event.tag(@nice_fallback_unresolved_tag) unless @nice_fallback_unresolved_tag.empty?
    write_nice_header_only(event, header, direction, @nice_unresolved_format)
    return
  end

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

  fallback = detail["B56_응답메시지"]
  detail["display_message"] = fallback unless match_value(fallback).empty?
end

def remove_approval_number_from_message!(detail, direction)
  return unless direction == "response"

  approval_number = match_value(detail["approval_number"]).strip
  display_message = match_value(detail["display_message"]).strip
  return if approval_number.empty? || display_message.empty?
  return unless display_message.end_with?(approval_number)

  message_only = display_message[0, display_message.length - approval_number.length].to_s.strip
  detail["display_message"] = message_only unless message_only.empty?
end

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

  begin
    return Time.iso8601(text).iso8601 if text.match?(/\A\d{4}-\d{2}-\d{2}T/)
  rescue ArgumentError
    return nil
  end

  return nil unless text.match?(/\A\d+\z/)

  candidates = []
  case text.length
  when 12
    candidates << [
      2000 + text[0, 2].to_i, text[2, 2].to_i, text[4, 2].to_i,
      text[6, 2].to_i, text[8, 2].to_i, text[10, 2].to_i
    ]
    candidates << [
      text[0, 4].to_i, text[4, 2].to_i, text[6, 2].to_i,
      text[8, 2].to_i, text[10, 2].to_i, 0
    ]
  when 14
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

def append_integrated_value(detail, definition, direction, value)
  return if definition.nil?

  field_spec = definition[direction] || definition["both"]
  return if field_spec.nil?

  append_value(detail, field_spec.fetch("key"), value)
end

def restore_encoding(value, encoding)
  value.dup.force_encoding(encoding)
end

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

def parse_dynamic_fields(raw, cursor, definitions, detail)
  definitions.each do |field|
    case field["type"]
    when "fixed"
      detail[field["key"]] = logical_byte_slice(raw, cursor, field["length"].to_i)
      cursor += field["length"].to_i

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
