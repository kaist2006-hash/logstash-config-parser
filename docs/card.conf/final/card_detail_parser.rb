# Logstash 8.17.x Ruby filter - final single-spec edition.
# The JSON spec is loaded, validated, compiled and frozen once in register().
# No network or per-event disk I/O. Sensitive payment fields are consumed for
# frame positioning but are not exported unless explicitly defined as safe emit fields.
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
  # The captured text envelopes carry arbitrary 8-bit payload bytes.  The
  # one-to-one Latin-1 round trip was used by the real-log replay as well.
  @text_encoding = Encoding.find(params.fetch('text_encoding', 'ISO-8859-1'))

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
    profile['enabled'] = enabled.include?(id) unless enabled.nil?
    raise ArgumentError, 'invalid enabled flag' unless [true, false].include?(profile['enabled'])
    profile['_binary'] = profile['wire'] == 'binary'

    transport = profile.fetch('transport', {})
    if transport.key?('extended_text_marker')
      raise ArgumentError, 'invalid extended text marker flag' unless [true, false].include?(transport['extended_text_marker'])
    end
    if transport.key?('outbound_declared_trailer_bytes')
      n = transport['outbound_declared_trailer_bytes']
      raise ArgumentError, 'invalid outbound trailer width' unless n.is_a?(Integer) && (1..64).cover?(n)
    end
    if transport['bracket_encoding']
      raise ArgumentError, 'invalid bracket encoding' unless %w[hex text].include?(transport['bracket_encoding'])
    end
    transport.fetch('embedded_length', {}).each do |encoding, rule|
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
    profile.fetch('control_records', []).each do |record|
      raise ArgumentError, 'invalid control record direction' unless %w[IN OUT].include?(record.fetch('direction'))
      raise ArgumentError, 'invalid control record marker' unless record.fetch('marker').is_a?(String) && !record['marker'].empty?
      raise ArgumentError, 'invalid control record offsets' unless record.fetch('offsets').all? { |n| n.is_a?(Integer) && (0..64).cover?(n) }
      raise ArgumentError, 'invalid control record lengths' unless record.fetch('lengths').all? { |n| n.is_a?(Integer) && (1..4096).cover?(n) }
    end

    compiled = Array.new(193)
    profile.fetch('fields', {}).each do |key, spec|
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
      if spec['allow_omitted_when_last_mtis']
        raise ArgumentError, 'invalid omitted-MTI rule' unless spec['allow_omitted_when_last_mtis'].is_a?(Array)
      end
      if spec['skip_when_mtis']
        raise ArgumentError, 'invalid skipped-MTI rule' unless spec['skip_when_mtis'].is_a?(Array)
      end
      if spec['length_includes_prefix']
        raise ArgumentError, 'inclusive length is valid only for variable fields' unless spec['kind'] == 'var'
      end
      ([spec] + spec.fetch('parts', [])).each do |part|
        next unless part['emit']
        raise ArgumentError, 'invalid exported name' unless /\A[a-z][a-z0-9_]{0,63}\z/.match?(part['emit'])
        raise ArgumentError, 'invalid exported encoding' unless %w[ascii bcd hex].include?(part.fetch('encoding'))
        if part != spec
          raise ArgumentError, 'invalid subfield bounds' unless part.fetch('offset').is_a?(Integer) && part['offset'] >= 0 && (1..512).cover?(part.fetch('length'))
        end
      end
      compiled[bit] = spec
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
  @iso_header_re = /\AISO[0-9]{9}\z/.freeze
  @ascii_bitmap_re = /\A[0-9a-fA-F]{16}\z/.freeze
  @recoverable_error_codes = {
    'truncated_field' => true, 'truncated_length_prefix' => true,
    'truncated_transport_payload' => true
  }.freeze
  card_freeze(@profiles)
  card_freeze(@emv_export)
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

def card_value(bytes, spec, result, bit, offset)
  value = case spec['encoding']
          when 'bcd', 'hex' then bytes.unpack1('H*').upcase
          when 'ascii'
            unless bytes.ascii_only? && bytes.each_byte.all? { |b| b >= 32 && b <= 126 }
              card_error(result, 'invalid_ascii_value', bit, offset)
              return nil
            end
            bytes.dup.force_encoding(Encoding::UTF_8).strip
          end
  if spec['encoding'] == 'bcd' && !/\A[0-9]*\z/.match?(value)
    card_error(result, 'invalid_bcd_value', bit, offset)
    return nil
  end
  if spec['numeric'] && !value.empty? && !/\A[0-9]+\z/.match?(value)
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
end

def card_optional_tail_omission?(spec, mti, pos, raw_size, field_index, active_size)
  mtis = spec['allow_omitted_when_last_mtis']
  mtis && field_index == active_size - 1 && pos == raw_size && mtis.include?(mti)
end

def card_transport(raw, profile, result)
  transport = profile.fetch('transport', {})
  rule = transport.fetch('embedded_length', {})[result['log_encoding']]
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

  suffix = transport['strip_suffix_hex']
  if suffix
    bytes = [suffix].pack('H*')
    if raw.end_with?(bytes)
      raw = raw.byteslice(0, raw.bytesize - bytes.bytesize)
      result['transport_suffix_bytes'] = bytes.bytesize
    end
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
  if record['business']
    result['consumed_bytes'] = raw.bytesize
    result['remaining_bytes'] = 0
    result['frame_status'] = 'complete'
  else
    result['status'] = 'control'
    result['frame_status'] = 'complete'
    result['control_frame'] = true
    result['consumed_bytes'] = raw.bytesize
    result['remaining_bytes'] = 0
  end
end

def card_parse(raw, profile, result)
  result['payload_bytes'] = raw.bytesize
  expected_headers = profile['expected_headers']
  offset = profile['header_offsets'].find do |candidate|
    header = raw.byteslice(candidate, 12)
    expected_headers ? expected_headers.include?(header) : @iso_header_re.match?(header)
  end
  unless offset && raw.bytesize >= offset + 12
    control = profile.fetch('control_records', []).find do |candidate|
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
    card_error(result, 'missing_iso_header')
    return
  end
  header = raw.byteslice(offset, 12)
  unless expected_headers ? expected_headers.include?(header) : @iso_header_re.match?(header)
    card_error(result, 'invalid_iso_header')
    return
  end
  result['iso_header'] = header.dup.force_encoding(Encoding::UTF_8)
  result['header_offset'] = offset
  card_warn(result, 'header_differs_from_document') if profile['expected_headers'] && !profile['expected_headers'].include?(header)

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
      8.times do |j|
        bit = group * 64 + index * 8 + j + 1
        active << bit if (byte & (128 >> j)) != 0 && ![1, 65, 129].include?(bit)
      end
    end
  end
  result['present_fields'] = active

  values = {}
  consumed_fields = 0
  active.each_with_index do |bit, field_index|
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

    if spec['emit']
      value = card_value(bytes, spec, result, bit, pos)
      values[spec['emit']] = value unless value.nil?
    end
    spec.fetch('parts', []).each do |part|
      next if part['offset'] + part['length'] > length
      value = card_value(bytes.byteslice(part['offset'], part['length']), part, result, bit, pos + part['offset'])
      values[part['emit']] = value unless value.nil?
    end

    if spec['tlv']
      tlv_bytes = bytes
      if spec['tlv_hex_ascii']
        unless bytes.bytesize.even? && /\A[0-9a-fA-F]*\z/.match?(bytes)
          card_error(result, 'invalid_ascii_hex_tlv', bit, pos)
          break
        end
        tlv_bytes = [bytes].pack('H*')
      end
      card_tlv(tlv_bytes, result, bit, pos)
    end
    pos += length
    consumed_fields += 1
  end

  result['fields'] = values unless values.empty?
  result['parsed_field_count'] = consumed_fields
  result['consumed_bytes'] = pos
  result['remaining_bytes'] = raw.bytesize - pos
  result['frame_status'] = consumed_fields == active.length ? 'complete' : 'partial'
  if result['frame_status'] == 'complete' && pos != raw.bytesize
    trailing = raw.byteslice(pos, raw.bytesize - pos)
    if result['outer_envelope_recovered']
      # Every bitmap-announced field was consumed. The remaining bytes belong to
      # the missing outer logger trailer/buffer, not to another ISO data element.
      result['recovered_trailing_bytes'] = trailing.bytesize
      card_warn(result, 'recovered_outer_trailing_bytes')
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
    event.set('[card_detail]', result)
    return [event]
  end
  result['profile'] = profile['id']
  result['issuer'] = profile['issuer']
  result['service'] = profile['service']
  unless profile['enabled']
    result['status'] = 'disabled'
    result['frame_status'] = 'not_parsed'
    event.set('[card_detail]', result)
    return [event]
  end

  message = event.get('message')
  if !message.is_a?(String)
    card_error(result, 'message_not_string')
  elsif message.bytesize > @max_message_bytes
    card_error(result, 'message_too_large', nil, nil, @max_message_bytes, message.bytesize)
  elsif message.include?("\uFFFD")
    card_error(result, 'lossy_input_encoding')
  else
    wire_message = message.encode(@text_encoding).b
    raw = nil
    if wire_message.include?('==>[')
      match = @bracket_envelope_re.match(wire_message)
      bracket_encoding = profile.fetch('transport', {}).fetch('bracket_encoding', 'hex')
      if match && bracket_encoding == 'text'
        raw = match[3]
        result['declared_bytes'] = match[1].to_i
        result['direction'] = match[2] == 'S' ? 'OUT' : 'IN'
        result['log_encoding'] = 'bracket_text'
      elsif match && match[3].bytesize.even? && /\A[0-9a-fA-F]*\z/.match?(match[3])
        raw = [match[3]].pack('H*')
        result['declared_bytes'] = match[1].to_i
        result['direction'] = match[2] == 'S' ? 'OUT' : 'IN'
        result['log_encoding'] = 'hex'
      else
        open_match = @bracket_open_re.match(wire_message)
        if open_match && bracket_encoding == 'text'
          raw = open_match[3]
          result['declared_bytes'] = open_match[1].to_i
          result['direction'] = open_match[2] == 'S' ? 'OUT' : 'IN'
          result['log_encoding'] = 'bracket_text'
          result['outer_envelope_recovered'] = true
          card_warn(result, 'missing_bracket_envelope_tail')
        elsif open_match && open_match[3].bytesize.even? && /\A[0-9a-fA-F]*\z/.match?(open_match[3])
          raw = [open_match[3]].pack('H*')
          result['declared_bytes'] = open_match[1].to_i
          result['direction'] = open_match[2] == 'S' ? 'OUT' : 'IN'
          result['log_encoding'] = 'hex'
          result['outer_envelope_recovered'] = true
          card_warn(result, 'missing_bracket_envelope_tail')
        else
          card_error(result, 'invalid_bracket_envelope')
        end
      end
    else
      marker_re = profile.fetch('transport', {})['extended_text_marker'] ? @extended_text_marker_re : @text_marker_re
      marker = marker_re.match(wire_message)
      tail = @text_tail_re.match(wire_message)
      if marker && tail && tail.begin(0) >= marker.end(0)
        raw = wire_message.byteslice(marker.end(0), tail.begin(0) - marker.end(0))
        result['declared_bytes'] = tail[1].to_i
        result['direction'] = marker[1] == 'put' ? 'OUT' : 'IN'
        result['log_encoding'] = 'text'
      elsif marker
        raw = wire_message.byteslice(marker.end(0), wire_message.bytesize - marker.end(0))
        result['direction'] = marker[1] == 'put' ? 'OUT' : 'IN'
        result['log_encoding'] = 'text'
        result['outer_envelope_recovered'] = true
        card_warn(result, 'missing_text_envelope_tail')
      else
        card_error(result, 'incomplete_text_envelope')
      end
    end

    if raw
      result['logged_bytes'] = raw.bytesize
      embedded_rule = profile.fetch('transport', {}).fetch('embedded_length', {})[result['log_encoding']]
      trailer_bytes = profile.fetch('transport', {})['outbound_declared_trailer_bytes']
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

  if result['status'] == 'control'
    # Control/health frames are structurally validated but not business-parsed.
  elsif result['errors'] && !result['errors'].empty?
    common_recovered = result['fields'].is_a?(Hash) && !result['fields'].empty?
    recoverable = result['errors'].all? { |item| @recoverable_error_codes[item['code']] }
    result['status'] = common_recovered && recoverable ? 'fallback' : 'error'
    event.tag(result['status'])
  elsif result['warnings'] && !result['warnings'].empty?
    common_recovered = result['fields'].is_a?(Hash) && !result['fields'].empty?
    unless common_recovered
      card_error(result, 'no_common_fields_recovered')
    end
    result['status'] = common_recovered ? 'fallback' : 'error'
    event.tag(result['status'])
  else
    result['status'] = 'ok'
  end
  event.set('[card_detail]', result)
  [event]
rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
  card_error(result, 'input_encoding_not_reversible')
  result['status'] = 'error'
  event.set('[card_detail]', result)
  event.tag('error')
  [event]
rescue StandardError
  result ||= { 'parser_version' => @version }
  result['status'] = 'error'
  card_error(result, 'unexpected_parser_exception')
  event.set('[card_detail]', result)
  event.tag('error')
  [event]
end
