# Logstash 8.17.x Ruby filter - final single-spec edition.
# The JSON spec is loaded, validated, compiled and frozen once in register().
# No network or per-event disk I/O. Fields without an emit definition are
# normally consumed but not exported. NH profiles explicitly preserve an
# uninterpreted rest as hex; treat that field as sensitive raw payment data.
require 'json'

def card_freeze(value)
  case value
  when Hash then value.each { |k, v| card_freeze(k); card_freeze(v) }
  when Array then value.each { |v| card_freeze(v) }
  end
  value.freeze
end

def register(params)
  document = JSON.parse(File.read(params.fetch('specs_path'), encoding: 'UTF-8'))
  raise ArgumentError, 'unsupported card schema version' unless document['schema_version'] == 1

  @max_message_bytes = Integer(params.fetch('max_message_bytes', 65_536))
  raise ArgumentError, 'invalid max_message_bytes' unless (1024..1_048_576).cover?(@max_message_bytes)
  # Reverse only the extracted payload, using the collector's input encoding.
  # CP949 matches Filebeat euc-kr's mapping family. Lost bytes are never guessed.
  @text_encoding = Encoding.find(params.fetch('text_encoding', document.fetch('text_encoding', 'ISO-8859-1')))
  @recover_lossy_prefix = document.fetch('recover_lossy_prefix', false)
  raise ArgumentError, 'invalid lossy prefix policy' unless [true, false].include?(@recover_lossy_prefix)
  @diagnostics = params.fetch('diagnostics', document.fetch('diagnostics', 'minimal'))
  raise ArgumentError, 'invalid diagnostics mode' unless %w[minimal full].include?(@diagnostics)
  @public_fields = %w[profile issuer service status direction mti record_type fields emv rest errors warnings].freeze
  @fallback_policy = document.fetch('fallback_policy')
  raise ArgumentError, 'invalid common DE limit' unless (3..49).cover?(@fallback_policy.fetch('common_max_de'))
  %w[extra_common_fields minimum_business_fields network_context_fields network_identifier_fields].each do |key|
    names = @fallback_policy.fetch(key)
    raise ArgumentError, 'invalid fallback field list' unless names.is_a?(Array) && names.length <= 32 &&
      names.all? { |name| name.is_a?(String) && /\A[a-z][a-z0-9_]{0,63}\z/.match?(name) } && names.uniq == names
    raise ArgumentError, 'empty fallback evidence list' if key != 'extra_common_fields' && names.empty?
  end

  enabled = params['enabled_profiles']
  enabled = enabled.split(',').map(&:strip).reject(&:empty?) if enabled.is_a?(String)
  raise ArgumentError, 'invalid enabled_profiles' unless enabled.nil? || enabled.is_a?(Array)
  known = document.fetch('profiles').map { |p| p.fetch('id') }
  raise ArgumentError, 'unknown enabled profile' if enabled && !(enabled - known).empty?

  @profiles = {}
  @version = document.fetch('version')
  prefix_width = { 'binary' => 1, 'ascii2' => 2, 'ascii3' => 3 }.freeze

  document.fetch('profiles').each do |profile|
    id = profile.fetch('id')
    raise ArgumentError, 'duplicate profile alias' if @profiles.key?(profile.fetch('alias'))
    profile['format'] ||= 'iso8583'
    raise ArgumentError, 'invalid profile format' unless %w[iso8583 fixed].include?(profile['format'])
    raise ArgumentError, 'invalid wire format' unless %w[ascii binary].include?(profile.fetch('wire'))
    if profile['format'] == 'iso8583'
      raise ArgumentError, 'invalid header offsets' unless profile.fetch('header_offsets').all? { |n| n.is_a?(Integer) && (0..32).cover?(n) }
      raise ArgumentError, 'invalid bitmap bound' unless (1..3).cover?(profile.fetch('max_bitmaps'))
    end
    if (rule = profile['trailing_padding'])
      raise ArgumentError, 'invalid padding headers' unless rule.fetch('headers').all? { |h| /\AISO[0-9]{9}\z/.match?(h) }
      raise ArgumentError, 'invalid padding MTIs' unless rule.fetch('mtis').all? { |m| /\A[0-9]{4}\z/.match?(m) }
      raise ArgumentError, 'invalid padding bounds' unless (2..192).cover?(rule.fetch('after_field')) &&
        (1..64).cover?(rule.fetch('length')) && (0..255).cover?(rule.fetch('byte'))
    end
    profile['enabled'] = enabled.include?(id) unless enabled.nil?
    raise ArgumentError, 'invalid enabled flag' unless [true, false].include?(profile['enabled'])
    raise ArgumentError, 'invalid rest policy' unless [true, false].include?(profile.fetch('allow_unparsed_rest', false))
    profile['_binary'] = profile['wire'] == 'binary'
    if (rule = profile['common_header_fallback'])
      raise ArgumentError, 'common header fallback requires an ISO profile with expected headers' unless profile['format'] == 'iso8583' && profile['expected_headers']
      raise ArgumentError, 'invalid common fallback headers' unless rule['headers'].is_a?(Array) && (1..8).cover?(rule['headers'].size) &&
        rule['headers'].all? { |header| /\AISO[0-9]{9}\z/.match?(header) && !profile['expected_headers'].include?(header) }
      raise ArgumentError, 'invalid common fallback MTIs' unless rule['mtis'].is_a?(Array) && (1..32).cover?(rule['mtis'].size) &&
        rule['mtis'].all? { |mti| /\A[0-9]{4}\z/.match?(mti) && profile['mtis'].include?(mti) }
      profile['_common_header_prefixes'] = {}
      profile['_common_header_width'] = profile['_binary'] ? 14 : 16
      rule['headers'].each do |header|
        rule['mtis'].each do |mti|
          profile['_common_header_prefixes'][header + (profile['_binary'] ? [mti].pack('H*') : mti)] = true
        end
      end
    end

    # Defaults and constant byte strings are prepared once, never per event.
    transport = profile['transport'] = profile.fetch('transport', {})
    transport['embedded_length'] = transport.fetch('embedded_length', {})
    transport['bracket_encoding'] = transport.fetch('bracket_encoding', 'hex')
    transport['_suffix_bytes'] = [transport['strip_suffix_hex']].pack('H*') if transport['strip_suffix_hex']
    profile['control_records'] = profile.fetch('control_records', [])
    if transport.key?('extended_text_marker')
      raise ArgumentError, 'invalid extended text marker flag' unless [true, false].include?(transport['extended_text_marker'])
    end
    if transport.key?('completed_text_envelope')
      raise ArgumentError, 'invalid completed text envelope flag' unless [true, false].include?(transport['completed_text_envelope'])
    end
    if transport['completed_text_trailer_hex']
      hex = transport['completed_text_trailer_hex']
      raise ArgumentError, 'invalid completed text trailer' unless transport['completed_text_envelope'] &&
        hex.is_a?(String) && /\A(?:[0-9a-fA-F]{2}){1,16}\z/.match?(hex)
      transport['_completed_trailer'] = [hex].pack('H*')
      transport['_completed_trailer_text'] = transport['_completed_trailer'].dup.force_encoding(@text_encoding).
        encode('UTF-8', invalid: :replace, undef: :replace, replace: "\uFFFD")
    end
    if transport.key?('outbound_declared_trailer_bytes')
      n = transport['outbound_declared_trailer_bytes']
      raise ArgumentError, 'invalid outbound trailer width' unless n.is_a?(Integer) && (1..64).cover?(n)
    end
    if transport['bracket_encoding']
      raise ArgumentError, 'invalid bracket encoding' unless %w[hex text].include?(transport['bracket_encoding'])
    end
    transport['embedded_length'].each do |encoding, rule|
      raise ArgumentError, 'invalid embedded envelope encoding' unless %w[hex text bracket_text].include?(encoding)
      raise ArgumentError, 'invalid embedded length prefix' unless %w[bcd2 ascii4].include?(rule.fetch('prefix'))
      raise ArgumentError, 'invalid embedded payload encoding' unless %w[binary hex_ascii].include?(rule.fetch('payload_encoding', 'binary'))
    end

    if profile['format'] == 'fixed'
      profile.fetch('records').each do |record|
        raise ArgumentError, 'invalid fixed record direction' unless %w[IN OUT].include?(record.fetch('direction'))
        raise ArgumentError, 'invalid fixed record marker' unless record.fetch('marker').is_a?(String) && !record['marker'].empty?
        raise ArgumentError, 'invalid fixed record offsets' unless record.fetch('offsets').all? { |n| n.is_a?(Integer) && (0..64).cover?(n) }
        raise ArgumentError, 'invalid fixed record lengths' unless record.fetch('lengths').all? { |n| n.is_a?(Integer) && (1..4096).cover?(n) }
        raise ArgumentError, 'invalid fixed record business flag' unless [true, false].include?(record.fetch('business'))
      end
    end
    profile['control_records'].each do |record|
      raise ArgumentError, 'invalid control record direction' unless %w[IN OUT].include?(record.fetch('direction'))
      raise ArgumentError, 'invalid control record marker' unless record.fetch('marker').is_a?(String) && !record['marker'].empty?
      raise ArgumentError, 'invalid control record offsets' unless record.fetch('offsets').all? { |n| n.is_a?(Integer) && (0..64).cover?(n) }
      raise ArgumentError, 'invalid control record lengths' unless record.fetch('lengths').all? { |n| n.is_a?(Integer) && (1..4096).cover?(n) }
    end

    compiled = Array.new(193)
    exported_names = {}
    profile['_fallback_fields'] = {}
    profile.fetch('fields', {}).each do |key, spec|
      spec['parts'] = spec.fetch('parts', [])
      bit = Integer(key, 10)
      raise ArgumentError, 'invalid data element' unless (2..192).cover?(bit) && ![65, 129].include?(bit)
      raise ArgumentError, 'invalid field kind' unless %w[fixed var blocked].include?(spec.fetch('kind'))
      if spec['kind'] == 'fixed'
        raise ArgumentError, 'invalid fixed length' unless (1..4096).cover?(spec.fetch('length'))
      elsif spec['kind'] == 'var'
        raise ArgumentError, 'invalid length prefix' unless prefix_width.key?(spec.fetch('prefix'))
        raise ArgumentError, 'invalid length unit' unless %w[bytes digits].include?(spec.fetch('unit'))
        raise ArgumentError, 'invalid variable maximum' unless (1..4096).cover?(spec.fetch('max'))
        spec['_prefix_bytes'] = prefix_width[spec['prefix']]
      end
      raise ArgumentError, 'invalid field validation encoding' if spec['encoding'] && !%w[ascii bcd hex].include?(spec['encoding'])
      if spec['allow_omitted_when_last_mtis']
        raise ArgumentError, 'invalid omitted-MTI rule' unless spec['allow_omitted_when_last_mtis'].is_a?(Array)
      end
      if spec['skip_when_mtis']
        raise ArgumentError, 'invalid skipped-MTI rule' unless spec['skip_when_mtis'].is_a?(Array)
      end
      if spec['length_includes_prefix']
        raise ArgumentError, 'inclusive length is valid only for variable fields' unless spec['kind'] == 'var'
      end
      if (padding = spec['slot_padding'])
        raise ArgumentError, 'invalid field slot padding' unless spec['kind'] == 'var' && spec['unit'] == 'bytes' &&
          padding.fetch('length').is_a?(Integer) && (1..spec['max']).cover?(padding['length']) &&
          (0..255).cover?(padding.fetch('byte')) && (2..192).cover?(padding.fetch('before_field')) &&
          padding.fetch('mtis').all? { |m| /\A[0-9]{4}\z/.match?(m) }
        padding['_bytes'] = (padding['byte'].chr.b * padding['length'])
      end
      ([spec] + spec['parts']).each do |part|
        next unless part['emit']
        raise ArgumentError, 'invalid exported name' unless /\A[a-z][a-z0-9_]{0,63}\z/.match?(part['emit'])
        raise ArgumentError, 'duplicate exported field name' if exported_names[part['emit']]
        exported_names[part['emit']] = true
        if (3..@fallback_policy['common_max_de']).cover?(bit) || @fallback_policy['extra_common_fields'].include?(part['emit'])
          profile['_fallback_fields'][part['emit']] = true
        end
        raise ArgumentError, 'invalid exported encoding' unless %w[ascii bcd hex].include?(part.fetch('encoding'))
        if part != spec
          raise ArgumentError, 'invalid subfield bounds' unless part.fetch('offset').is_a?(Integer) && part['offset'] >= 0 && (1..512).cover?(part.fetch('length'))
        end
      end
      compiled[bit] = spec
    end
    if profile['format'] == 'iso8583'
      required = @fallback_policy['minimum_business_fields']
      raise ArgumentError, 'fallback evidence is not a common output field' unless required.all? { |name| profile['_fallback_fields'].key?(name) }
      raise ArgumentError, 'no network context field' unless @fallback_policy['network_context_fields'].any? { |name| profile['_fallback_fields'].key?(name) }
      raise ArgumentError, 'no network reference field' unless @fallback_policy['network_identifier_fields'].any? { |name| profile['_fallback_fields'].key?(name) }
    end
    if (layout = profile['network_common_fallback'])
      raise ArgumentError, 'invalid network common profile' unless profile['format'] == 'iso8583' && !profile['_binary'] && profile['expected_headers'].include?(layout.fetch('header'))
      raise ArgumentError, 'invalid network MTIs' unless layout.fetch('mtis').is_a?(Array) && !layout['mtis'].empty? && layout['mtis'].all? { |mti| %w[0800 0810].include?(mti) && profile['mtis'].include?(mti) }
      raise ArgumentError, 'invalid network layout size' unless (64..4096).cover?(layout.fetch('iso_length'))
      raise ArgumentError, 'invalid network bitmap' unless /\A[0-9A-F]{32}\z/.match?(layout.fetch('bitmap'))
      raise ArgumentError, 'invalid network user area' unless layout.fetch('user_area').ascii_only? && (1..32).cover?(layout['user_area'].bytesize)
      raise ArgumentError, 'invalid network common DEs' unless layout.fetch('field_offsets').keys.sort == %w[11 7 70]
      regions = [[0, 48]]
      layout['_fields'] = layout['field_offsets'].map do |key, position|
        bit = Integer(key, 10)
        spec = compiled[bit]
        raise ArgumentError, 'invalid network common field' unless position.is_a?(Integer) && position >= 48 && spec && spec['kind'] == 'fixed' && spec['encoding'] == 'ascii' && spec['numeric'] && profile['_fallback_fields'][spec['emit']]
        regions << [position, spec['length']]
        [bit, position, spec]
      end
      layout['_fields'].sort_by! { |bit, _, _| bit }
      layout['_data_start'] = layout['_fields'].map { |_, position, _| position }.min
      layout['_padding'] = layout.fetch('padding').map do |position, length|
        raise ArgumentError, 'invalid network padding' unless position.is_a?(Integer) && position >= 48 && length.is_a?(Integer) && (1..512).cover?(length)
        regions << [position, length]
        [position, (' '.b * length)]
      end
      boundary = 0
      regions.sort.each do |position, length|
        raise ArgumentError, 'network layout has gaps or overlaps' unless position == boundary
        boundary += length
      end
      raise ArgumentError, 'network layout size mismatch' unless boundary == layout['iso_length']
    end
    profile['compiled'] = compiled
    @profiles[profile['alias']] = profile
  end

  @emv_export = document.fetch('emv_export')
  @bracket_envelope_re = /len\[([0-9]+)\]\[([SR])\]==>\[(.*)\]\s*\z/m.freeze
  @bracket_open_re = /len\[([0-9]+)\]\[([SR])\]==>\[(.*)\z/m.freeze
  @text_marker_re = /\b(get|put)\(data\[/.freeze
  @extended_text_marker_re = /\b(get|put)\([^\r\n)]{0,128}?data\[/.freeze
  @text_tail_re = /\] len\[([0-9]+)\](?: uid\[[^\]]*\])?(?: linename\[[^\]]*\])?\)\s*\z/.freeze
  # Recover the known logger suffix even when the packet/length closing text is absent.
  @orphan_text_tail_re = /(?:\] len\[[^\[\]\r\n]*\]?)? (?:(?:uid|fd)\[[^\]\r\n]*\] )?linename\[[^\]\r\n]*\]\)\s*\z/.freeze
  @completed_text_marker_re = /\bput_msg_complete\[/.freeze
  @completed_text_envelope_re = /\bput_msg_complete\[(.*?)\](?:\[([^\[\]\r\n]*)\])?(?:\s+linename\[[^\]]*\])?\s*\z/m.freeze
  @iso_header_re = /\AISO[0-9]{9}\z/.freeze
  @ascii_bitmap_re = /\A[0-9a-fA-F]{16}\z/.freeze
  @printable_ascii_re = /\A[\x20-\x7E]*\z/n.freeze
  card_freeze(@profiles)
  card_freeze(@emv_export)
  card_freeze(@fallback_policy)
  @version.freeze
end

def card_error(result, code, bit = nil, offset = nil, expected = nil, available = nil)
  result['errors'] ||= []
  return if result['errors'].length >= 8
  item = { 'code' => code }
  item['field'] = bit if bit
  item['offset'] = offset unless offset.nil?
  item['expected'] = expected unless expected.nil?
  item['available'] = available unless available.nil?
  result['errors'] << item
end

def card_warn(result, code)
  result['warnings'] ||= []
  result['warnings'] << code unless result['warnings'].include?(code) || result['warnings'].length >= 16
end

def card_publish(event, result)
  if result['status'] == 'fallback'
    profile = @profiles[event.get('[@metadata][target_alias]')]
    result['fields'].delete_if { |name, _| !profile['_fallback_fields'].key?(name) }
    result.delete('emv')
    result.delete('rest')
  elsif result['status'] == 'error'
    result.delete('fields')
    result.delete('emv')
    result.delete('rest')
  end
  event.set('[@metadata][card_detail_parser_version]', @version)
  if @diagnostics == 'minimal'
    output = {}
    @public_fields.each do |key|
      value = result[key]
      output[key] = value unless value.nil?
    end
    if output['errors']
      output['errors'] = output['errors'].map do |error|
        item = { 'code' => error['code'] }
        item['field'] = error['field'] if error.key?('field')
        item
      end
    end
    result = output
  end
  event.set('[card_detail]', result)
  [event]
end

def card_common_ready?(profile, result)
  return false unless profile && profile['format'] == 'iso8583' && result['iso_header'] &&
    result['mti'] && result['present_fields'].is_a?(Array) && result['fields'].is_a?(Hash)
  fields = result['fields']
  present = ->(name) { fields[name].is_a?(String) && !fields[name].empty? }
  if result['mti'].start_with?('08')
    @fallback_policy['network_context_fields'].any?(&present) &&
      @fallback_policy['network_identifier_fields'].any?(&present)
  else
    @fallback_policy['minimum_business_fields'].all?(&present)
  end
end

def card_discard_field(values, spec)
  values.delete(spec['emit']) if spec['emit']
  spec['parts'].each { |part| values.delete(part['emit']) }
end

def card_external_input_loss(result)
  return unless result['input_loss_truncated']
  # An independently validated transport length already bounds the complete
  # payload. Replacement characters occur only in the discarded logger buffer.
  result['input_loss_truncated'] = false
  result['input_loss_outside_payload'] = true
  result['errors'].reject! { |item| item['code'] == 'input_decoding_loss' }
  result.delete('errors') if result['errors'].empty?
end

def card_value(bytes, spec, result, bit, offset)
  value = case spec['encoding']
          when 'bcd' then bytes.unpack1('H*')
          when 'hex' then bytes.unpack1('H*').upcase
          when 'ascii'
            unless @printable_ascii_re.match?(bytes)
              card_error(result, 'invalid_ascii_value', bit, offset)
              return nil
            end
            bytes.dup.force_encoding(Encoding::UTF_8).strip
          end
  if spec['encoding'] == 'bcd' && !/\A[0-9]*\z/.match?(value)
    card_error(result, 'invalid_bcd_value', bit, offset)
    return nil
  end
  if spec['numeric'] && spec['encoding'] != 'bcd' && !value.empty? && !/\A[0-9]+\z/.match?(value)
    card_error(result, 'invalid_numeric_value', bit, offset)
    return nil
  end
  value
end

def card_tlv(bytes, result, bit, start)
  pos = 0
  exported = {}
  count = 0
  while pos < bytes.bytesize
    tag_start = pos
    first = bytes.getbyte(pos)
    pos += 1
    if (first & 31) == 31
      loop do
        if pos >= bytes.bytesize || pos - tag_start >= 4
          card_error(result, 'invalid_tlv_tag', bit, start + pos)
          return
        end
        last = bytes.getbyte(pos)
        pos += 1
        break if (last & 128).zero?
      end
    end
    tag = bytes.byteslice(tag_start, pos - tag_start).unpack1('H*').upcase
    if pos >= bytes.bytesize
      card_error(result, 'truncated_tlv_length', bit, start + pos)
      return
    end
    length = bytes.getbyte(pos)
    pos += 1
    if length >= 128
      n = length & 127
      if n.zero? || n > 2 || pos + n > bytes.bytesize
        card_error(result, 'invalid_tlv_length', bit, start + pos - 1)
        return
      end
      length = 0
      n.times { length = (length << 8) | bytes.getbyte(pos); pos += 1 }
    end
    if pos + length > bytes.bytesize
      card_error(result, 'truncated_tlv_value', bit, start + pos, length, bytes.bytesize - pos)
      return
    end
    rule = @emv_export[tag]
    if rule
      if length != rule['length']
        card_error(result, 'invalid_tlv_export_length', bit, start + pos, rule['length'], length)
        return
      end
      if exported.key?(rule['name'])
        card_error(result, 'duplicate_tlv_export_tag', bit, start + tag_start)
        return
      end
      exported[rule['name']] = bytes.byteslice(pos, length).unpack1('H*').upcase
    end
    pos += length
    count += 1
  end
  result['emv'] = exported unless exported.empty?
  result['tlv_count'] = count
  true
end

def card_optional_tail_omission?(spec, mti, pos, raw_size, field_index, active_size)
  mtis = spec['allow_omitted_when_last_mtis']
  mtis && field_index == active_size - 1 && pos == raw_size && mtis.include?(mti)
end

def card_transport(raw, profile, result)
  transport = profile['transport']
  rule = transport['embedded_length'][result['log_encoding']]
  if rule
    prefix_bytes = rule['prefix'] == 'bcd2' ? 2 : 4
    if raw.bytesize < prefix_bytes
      card_error(result, 'truncated_transport_length', nil, 0, prefix_bytes, raw.bytesize)
      return nil
    end
    prefix = raw.byteslice(0, prefix_bytes)
    if rule['prefix'] == 'bcd2'
      digits = prefix.unpack1('H*')
      unless /\A[0-9]{4}\z/.match?(digits)
        card_error(result, 'invalid_transport_length', nil, 0)
        return nil
      end
      count = digits.to_i
    else
      unless /\A[0-9]{4}\z/.match?(prefix)
        card_error(result, 'invalid_transport_length', nil, 0)
        return nil
      end
      count = prefix.to_i
    end
    body = raw.byteslice(prefix_bytes, raw.bytesize - prefix_bytes)
    response_prefix = transport['response_prefix']
    if response_prefix && body.start_with?(response_prefix)
      body = body.byteslice(response_prefix.bytesize, body.bytesize - response_prefix.bytesize)
      result['response_prefix_bytes'] = response_prefix.bytesize
    end
    encoded_bytes = rule.fetch('payload_encoding', 'binary') == 'hex_ascii' ? count * 2 : count
    card_external_input_loss(result) if body.bytesize >= encoded_bytes
    if body.bytesize < encoded_bytes
      card_error(result, 'truncated_transport_payload', nil, prefix_bytes, encoded_bytes, body.bytesize)
      result['embedded_available_bytes'] = body.bytesize
    elsif body.bytesize > encoded_bytes
      result['transport_trimmed_bytes'] = body.bytesize - encoded_bytes
      body = body.byteslice(0, encoded_bytes)
    end
    if rule.fetch('payload_encoding', 'binary') == 'hex_ascii'
      unless body.bytesize.even? && /\A[0-9a-fA-F]*\z/.match?(body)
        card_error(result, 'invalid_transport_hex_payload')
        return nil
      end
      body = [body].pack('H*')
    end
    result['embedded_bytes'] = count
    raw = body
  else
    response_prefix = transport['response_prefix']
    if response_prefix && raw.start_with?(response_prefix)
      raw = raw.byteslice(response_prefix.bytesize, raw.bytesize - response_prefix.bytesize)
      result['response_prefix_bytes'] = response_prefix.bytesize
    end
  end

  suffix = transport['_suffix_bytes']
  if suffix && raw.end_with?(suffix)
    raw = raw.byteslice(0, raw.bytesize - suffix.bytesize)
    result['transport_suffix_bytes'] = suffix.bytesize
  end
  raw
end

def card_parse_fixed(raw, profile, result)
  result['payload_bytes'] = raw.bytesize
  direction = result['direction']
  record = profile['records'].find do |candidate|
    next false unless candidate['direction'] == direction && candidate['lengths'].include?(raw.bytesize)
    candidate['offsets'].any? do |offset|
      raw.byteslice(offset, candidate['marker'].bytesize) == candidate['marker']
    end
  end
  unless record
    card_error(result, 'unknown_fixed_record')
    return
  end
  result['record_type'] = record['name']
  unless record['business']
    result['status'] = 'control'
    result['control_frame'] = true
  end
  result['consumed_bytes'] = raw.bytesize
  result['remaining_bytes'] = 0
  result['frame_status'] = 'complete'
end

def card_network_common(raw, offset, profile, result)
  layout = profile['network_common_fallback']
  return false unless layout && layout['header'] == result['iso_header'] &&
    layout['mtis'].include?(result['mti']) && layout['bitmap'] == result['bitmap']
  user = layout['user_area']
  user_offset = offset - user.bytesize
  return false unless [0, 4].include?(user_offset) && raw.byteslice(user_offset, user.bytesize) == user
  if user_offset == 4
    length = raw.byteslice(0, 4)
    return false unless /\A[0-9]{4}\z/.match?(length) && length.to_i == user.bytesize + layout['iso_length']
  end
  available = raw.bytesize - offset
  available = [available, result['declared_bytes'] - offset].min if result['declared_bytes']
  return false if available < layout['_data_start']
  layout['_padding'].each do |position, bytes|
    width = [[available - position, 0].max, bytes.bytesize].min
    return false unless raw.byteslice(offset + position, width).to_s == bytes.byteslice(0, width)
  end
  values = {}
  layout['_fields'].each do |bit, position, spec|
    if position + spec['length'] > available
      card_error(result, 'truncated_field', bit, offset + position, spec['length'], [available - position, 0].max)
      break
    end
    value = card_value(raw.byteslice(offset + position, spec['length']), spec, result, bit, offset + position)
    break if value.nil?
    values[spec['emit']] = value
  end
  result['fields'] = values unless values.empty?
  result['parsed_field_count'] = values.size
  result['consumed_bytes'] = offset + [available, layout['iso_length']].min
  result['remaining_bytes'] = raw.bytesize - result['consumed_bytes']
  result['frame_status'] = 'partial'
  card_warn(result, 'network_layout_common_only')
  true
end

def card_parse(raw, profile, result)
  result['payload_bytes'] = raw.bytesize
  common_only = false
  expected_headers = profile['expected_headers']
  offset = profile['header_offsets'].find do |candidate|
    header = raw.byteslice(candidate, 12)
    expected_headers ? expected_headers.include?(header) : @iso_header_re.match?(header)
  end
  if !offset && profile['_common_header_prefixes']
    offset = profile['header_offsets'].find { |candidate| profile['_common_header_prefixes'].key?(raw.byteslice(candidate, profile['_common_header_width'])) }
    if offset
      common_only = true
      card_warn(result, 'header_variant_common_only')
    end
  end
  unless offset && raw.bytesize >= offset + 12
    control = profile['control_records'].find do |candidate|
      next false unless candidate['direction'] == result['direction'] && candidate['lengths'].include?(raw.bytesize)
      candidate['offsets'].any? do |candidate_offset|
        raw.byteslice(candidate_offset, candidate['marker'].bytesize) == candidate['marker']
      end
    end
    if control
      result['status'] = 'control'
      result['frame_status'] = 'complete'
      result['control_frame'] = true
      result['record_type'] = control['name']
      result['consumed_bytes'] = raw.bytesize
      result['remaining_bytes'] = 0
      return
    end
    has_iso_header = profile['header_offsets'].any? do |candidate|
      header = raw.byteslice(candidate, 12)
      header && @iso_header_re.match?(header)
    end
    card_error(result, has_iso_header ? 'unexpected_iso_header' : 'missing_iso_header')
    return
  end
  header = raw.byteslice(offset, 12)
  result['iso_header'] = header.dup.force_encoding(Encoding::UTF_8)
  result['header_offset'] = offset

  binary = profile['_binary']
  pos = offset + 12
  width = binary ? 2 : 4
  if raw.bytesize < pos + width
    card_error(result, 'truncated_mti', nil, pos, width, raw.bytesize - pos)
    return
  end
  mti = binary ? raw.byteslice(pos, width).unpack1('H*') : raw.byteslice(pos, width)
  unless /\A[0-9]{4}\z/.match?(mti)
    card_error(result, 'invalid_mti', nil, pos)
    return
  end
  result['mti'] = mti.dup.force_encoding(Encoding::UTF_8)
  card_warn(result, 'mti_not_in_document') unless profile['mtis'].include?(mti)
  pos += width

  maps = []
  profile['max_bitmaps'].times do |index|
    width = binary ? 8 : 16
    if pos + width > raw.bytesize
      card_error(result, 'truncated_bitmap', nil, pos, width, raw.bytesize - pos)
      return
    end
    chunk = raw.byteslice(pos, width)
    if !binary && !@ascii_bitmap_re.match?(chunk)
      card_error(result, 'invalid_bitmap', nil, pos)
      return
    end
    map = binary ? chunk : [chunk].pack('H*')
    maps << map
    pos += width
    break if (map.getbyte(0) & 128).zero?
    if index == profile['max_bitmaps'] - 1
      card_error(result, 'unsupported_bitmap_extension', nil, pos)
      return
    end
  end

  result['bitmap'] = maps.join.unpack1('H*').upcase
  active = []
  maps.each_with_index do |map, group|
    map.each_byte.with_index do |byte, index|
      next if byte.zero?
      8.times do |j|
        bit = group * 64 + index * 8 + j + 1
        active << bit if (byte & (128 >> j)) != 0 && (index != 0 || j != 0)
      end
    end
  end
  result['present_fields'] = active
  return if profile['network_common_fallback'] && card_network_common(raw, offset, profile, result)

  values = {}
  consumed_fields = 0
  active.each_with_index do |bit, field_index|
    # A configured header variant establishes only the documented common prefix.
    # Stop before detailed DEs instead of assuming their layout is unchanged.
    break if common_only && bit > @fallback_policy['common_max_de']
    spec = profile['compiled'][bit]
    if spec.nil? || spec['kind'] == 'blocked'
      card_error(result, spec.nil? ? 'unknown_field' : 'unresolved_spec_field', bit, pos)
      break
    end

    if spec['skip_when_mtis'] && spec['skip_when_mtis'].include?(mti)
      card_warn(result, "bitmap_field_omitted_f#{bit}")
      consumed_fields += 1
      next
    end

    if card_optional_tail_omission?(spec, mti, pos, raw.bytesize, field_index, active.length)
      card_warn(result, "omitted_document_field_f#{bit}")
      consumed_fields += 1
      next
    end

    length = spec['length']
    if spec['kind'] == 'var'
      prefix_bytes = spec['_prefix_bytes']
      if pos + prefix_bytes > raw.bytesize
        card_error(result, 'truncated_length_prefix', bit, pos, prefix_bytes, raw.bytesize - pos)
        break
      end
      if spec['prefix'] == 'binary'
        count = raw.getbyte(pos)
      else
        prefix = raw.byteslice(pos, prefix_bytes)
        unless /\A[0-9]+\z/.match?(prefix)
          card_error(result, /\A\*+\z/.match?(prefix) ? 'redacted_length_prefix' : 'invalid_length_prefix', bit, pos)
          break
        end
        count = prefix.to_i
      end
      if count > spec['max']
        card_error(result, 'field_length_exceeds_limit', bit, pos, spec['max'], count)
        break
      end
      card_warn(result, "document_length_deviation_f#{bit}") if spec['document_max'] && count > spec['document_max']
      if spec['length_includes_prefix']
        if count < prefix_bytes
          card_error(result, 'invalid_inclusive_length', bit, pos, prefix_bytes, count)
          break
        end
        count -= prefix_bytes
      end
      length = spec['unit'] == 'digits' ? (count + 1) / 2 : count
      pos += prefix_bytes
    end

    if pos + length > raw.bytesize
      card_error(result, 'truncated_field', bit, pos, length, raw.bytesize - pos)
      break
    end
    bytes = raw.byteslice(pos, length)

    if spec['encoding']
      value = card_value(bytes, spec, result, bit, pos)
      break if value.nil?
      values[spec['emit']] = value if spec['emit']
    end
    field_valid = true
    spec['parts'].each do |part|
      next if part['offset'] + part['length'] > length
      value = card_value(bytes.byteslice(part['offset'], part['length']), part, result, bit, pos + part['offset'])
      if value.nil?
        field_valid = false
        break
      end
      values[part['emit']] = value
    end
    unless field_valid
      card_discard_field(values, spec)
      break
    end

    if spec['tlv']
      tlv_bytes = bytes
      if spec['tlv_hex_ascii']
        unless bytes.bytesize.even? && /\A[0-9a-fA-F]*\z/.match?(bytes)
          card_error(result, 'invalid_ascii_hex_tlv', bit, pos)
          card_discard_field(values, spec)
          break
        end
        tlv_bytes = [bytes].pack('H*')
      end
      unless card_tlv(tlv_bytes, result, bit, pos)
        card_discard_field(values, spec)
        break
      end
    end
    pos += length
    padding = spec['slot_padding']
    if padding && padding['mtis'].include?(mti) && active[field_index + 1] == padding['before_field'] && length < padding['length']
      width = padding['length'] - length
      if pos + width > raw.bytesize
        card_error(result, 'truncated_field', bit, pos, width, raw.bytesize - pos)
        card_discard_field(values, spec)
        break
      end
      unless raw.byteslice(pos, width) == padding['_bytes'].byteslice(0, width)
        card_error(result, 'invalid_field_slot_padding', bit, pos, width)
        card_discard_field(values, spec)
        break
      end
      pos += width
      result['document_padding_bytes'] = result.fetch('document_padding_bytes', 0) + width
      card_warn(result, "padded_field_f#{bit}")
    end
    consumed_fields += 1
  end

  result['fields'] = values unless values.empty?
  result['parsed_field_count'] = consumed_fields
  result['consumed_bytes'] = pos
  result['remaining_bytes'] = raw.bytesize - pos
  result['frame_status'] = consumed_fields == active.length ? 'complete' : 'partial'
  if result['frame_status'] == 'complete' && pos != raw.bytesize
    trailing = raw.byteslice(pos, raw.bytesize - pos)
    rule = profile['trailing_padding']
    if rule && rule['headers'].include?(header) && rule['mtis'].include?(mti) &&
       active.last == rule['after_field'] && trailing.bytesize == rule['length'] &&
       trailing.each_byte.all? { |byte| byte == rule['byte'] }
      # Only this exact legacy response's space padding is recognized. Keep
      # the document deviation visible as fallback; do not invent a DE56 value.
      result['padding_bytes'] = trailing.bytesize
      result['consumed_bytes'] = raw.bytesize
      result['remaining_bytes'] = 0
      card_warn(result, 'legacy_space_padding')
    elsif result['outer_envelope_recovered']
      # Every bitmap-announced field was consumed. The remaining bytes belong to
      # the missing outer logger trailer/buffer, not to another ISO data element.
      result['recovered_trailing_bytes'] = trailing.bytesize
      card_warn(result, 'recovered_outer_trailing_bytes')
    elsif profile['allow_unparsed_rest']
      # Preserve the exact uninterpreted payload bytes without assuming a DE layout.
      # Hex is byte-safe for LogStash::Event and Elasticsearch string fields.
      result['rest'] = trailing.unpack1('H*').upcase
      card_warn(result, 'unparsed_rest')
    else
      card_error(result, 'trailing_bytes', nil, pos, pos, raw.bytesize)
      result['frame_status'] = 'partial'
    end
  end
end

def filter(event)
  result = { 'parser_version' => @version, 'status' => 'error', 'frame_status' => 'invalid' }
  if event.include?('[card_detail]')
    event.tag('error')
    return [event]
  end

  profile = @profiles[event.get('[@metadata][target_alias]')]
  unless profile
    result['status'] = 'unconfigured'
    result['frame_status'] = 'not_parsed'
    return card_publish(event, result)
  end
  result['profile'] = profile['id']
  result['issuer'] = profile['issuer']
  result['service'] = profile['service']
  unless profile['enabled']
    result['status'] = 'disabled'
    result['frame_status'] = 'not_parsed'
    return card_publish(event, result)
  end

  message = event.get('message')
  if !message.is_a?(String)
    card_error(result, 'message_not_string')
  elsif message.bytesize > @max_message_bytes
    card_error(result, 'message_too_large', nil, nil, @max_message_bytes, message.bytesize)
  else
    # Envelope markers are ASCII. Slice this Unicode string by character
    # offsets first; byte offsets become valid only after reversing its payload.
    wire_message = message
    transport = profile['transport']
    raw = nil
    if wire_message.include?('==>[')
      match = @bracket_envelope_re.match(wire_message)
      recovered = match.nil?
      match ||= @bracket_open_re.match(wire_message)
      if match
        if transport['bracket_encoding'] == 'text'
          raw = match[3]
          result['log_encoding'] = 'bracket_text'
        elsif match[3].bytesize.even? && /\A[0-9a-fA-F]*\z/.match?(match[3])
          raw = [match[3]].pack('H*')
          result['log_encoding'] = 'hex'
        end
        if raw
          result['declared_bytes'] = match[1].to_i
          result['direction'] = match[2] == 'S' ? 'OUT' : 'IN'
          if recovered
            result['outer_envelope_recovered'] = true
            card_warn(result, 'missing_bracket_envelope_tail')
          end
        end
      end
      card_error(result, 'invalid_bracket_envelope') unless raw
    else
      marker_re = transport['extended_text_marker'] ? @extended_text_marker_re : @text_marker_re
      marker = marker_re.match(wire_message)
      completed_marker = @completed_text_marker_re.match(wire_message) if transport['completed_text_envelope']
      if completed_marker && (!marker || completed_marker.begin(0) < marker.begin(0))
        completed = @completed_text_envelope_re.match(wire_message, completed_marker.begin(0))
        raw = completed ? completed[1] : wire_message[completed_marker.end(0)..-1]
        if completed && completed[2]
          if /\A[0-9]+\z/.match?(completed[2])
            result['declared_bytes'] = completed[2].to_i
          else
            card_warn(result, 'invalid_completed_text_length')
          end
        end
        result['direction'] = 'OUT'
        result['log_encoding'] = 'completed_text'
        unless completed
          result['outer_envelope_recovered'] = true
          card_warn(result, 'missing_completed_text_envelope_tail')
        end
      else
        tail = @text_tail_re.match(wire_message)
        if marker && tail && tail.begin(0) >= marker.end(0)
          raw = wire_message[marker.end(0)...tail.begin(0)]
          result['declared_bytes'] = tail[1].to_i
          result['direction'] = marker[1] == 'put' ? 'OUT' : 'IN'
          result['log_encoding'] = 'text'
        elsif marker
          logger_tail = @orphan_text_tail_re.match(wire_message, marker.end(0))
          raw = logger_tail ? wire_message[marker.end(0)...logger_tail.begin(0)] : wire_message[marker.end(0)..-1]
          result['direction'] = marker[1] == 'put' ? 'OUT' : 'IN'
          result['log_encoding'] = 'text'
          result['outer_envelope_recovered'] = true
          card_warn(result, 'missing_text_envelope_tail')
        else
          card_error(result, 'incomplete_text_envelope')
        end
      end
    end

    completed_loss_tail = false
    if raw && result['log_encoding'] != 'hex'
      result['input_text_encoding'] = @text_encoding.name
      loss_offset = raw.index("\uFFFD")
      if loss_offset
        suffix = transport['_completed_trailer_text']
        completed_loss_tail = result['log_encoding'] == 'completed_text' && suffix &&
          suffix.include?("\uFFFD") && raw[loss_offset, suffix.length] == suffix
        if @recover_lossy_prefix
          # Everything after the first replacement character has unknown byte
          # positions. Parse only the reversible prefix and force fallback/error.
          raw = raw[0...loss_offset].encode(@text_encoding).b
          result['input_loss_truncated'] = true
          result['logged_bytes_exact'] = false
          result['input_recovered_prefix_bytes'] = raw.bytesize
          card_error(result, 'input_decoding_loss', nil, raw.bytesize)
        else
          card_error(result, 'lossy_input_encoding')
          raw = nil
        end
      else
        raw = raw.encode(@text_encoding).b
      end
    end

    if raw
      result['logged_bytes'] = raw.bytesize
      # Only the counted completed-request form defines this transport boundary.
      # Invalid bytes inside the ISO payload still cause fallback/error.
      trailer = transport['_completed_trailer']
      if result['log_encoding'] == 'completed_text' && result['declared_bytes'] && trailer
        length = result['declared_bytes'] - trailer.bytesize
        if length >= 0 && ((raw.bytesize >= result['declared_bytes'] && raw.byteslice(length, trailer.bytesize) == trailer) ||
            (result['input_loss_truncated'] && completed_loss_tail && raw.bytesize == length))
          result['envelope_declared_bytes'] = result['declared_bytes']
          result['declared_bytes'] = length
          result['transport_trailer_bytes'] = trailer.bytesize
        end
      end
      embedded_rule = transport['embedded_length'][result['log_encoding']]
      trailer_bytes = transport['outbound_declared_trailer_bytes']
      if result['declared_bytes'] && !embedded_rule && result['direction'] == 'OUT' &&
         trailer_bytes && raw.bytesize == result['declared_bytes'] + trailer_bytes
        result['transport_trailer_bytes'] = trailer_bytes
        raw = raw.byteslice(0, result['declared_bytes'])
      elsif result['declared_bytes'] && !embedded_rule && raw.bytesize != result['declared_bytes']
        if profile['trim_to_declared_length'] && raw.bytesize > result['declared_bytes']
          result['trimmed_bytes'] = raw.bytesize - result['declared_bytes']
          raw = raw.byteslice(0, result['declared_bytes'])
        else
          card_warn(result, 'declared_length_mismatch')
        end
      end
      if !embedded_rule && profile['trim_to_declared_length'] && result['declared_bytes'] &&
         raw.bytesize >= result['declared_bytes']
        card_external_input_loss(result)
      end
      raw = card_transport(raw, profile, result)
      if raw
        if profile['format'] == 'fixed'
          card_parse_fixed(raw, profile, result)
        else
          card_parse(raw, profile, result)
        end
      end
    end
  end

  if result['status'] == 'control' && !result['input_loss_truncated']
    # Control/health frames are structurally validated but not business-parsed.
  elsif result['errors'] && !result['errors'].empty?
    common_recovered = card_common_ready?(profile, result)
    result['status'] = common_recovered ? 'fallback' : 'error'
    card_error(result, 'insufficient_common_fields') if !common_recovered && result['fields'] && !result['fields'].empty?
    event.tag(result['status'])
  elsif result['warnings'] && !result['warnings'].empty?
    common_recovered = result['fields'].is_a?(Hash) && !result['fields'].empty?
    rest_accepted = common_recovered && result.key?('rest') && profile['allow_unparsed_rest'] &&
                    result['warnings'].all? { |warning| %w[unparsed_rest bitmap_field_omitted_f127].include?(warning) }
    result['status'] = rest_accepted ? 'ok' : (card_common_ready?(profile, result) ? 'fallback' : 'error')
    card_error(result, 'insufficient_common_fields') if result['status'] == 'error'
    event.tag(result['status']) unless result['status'] == 'ok'
  else
    result['status'] = 'ok'
  end
  card_publish(event, result)
rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
  card_error(result, 'input_encoding_not_reversible')
  result['status'] = 'error'
  event.tag('error')
  card_publish(event, result)
rescue StandardError
  result ||= { 'parser_version' => @version }
  result['status'] = 'error'
  card_error(result, 'unexpected_parser_exception')
  event.tag('error')
  card_publish(event, result)
end
