# Executed inside the Logstash 8.17.6 RubyUtil runtime using real LogStash::Event.
# The report contains aggregate counts only; payment-field values are never written.
require 'json'
require 'digest'
require 'thread'
Thread.abort_on_exception = true

directory = ENV.fetch('CARD_PARSER_DIR')
parser = Object.new
parser.instance_eval(File.read(File.join(directory, 'card_detail_parser.rb')), 'card_detail_parser.rb')
params = { 'specs_path' => File.join(directory, 'card_detail_specs.json') }
params['text_encoding'] = ENV['CARD_TEXT_ENCODING'] if ENV['CARD_TEXT_ENCODING']
params['enabled_profiles'] = ENV['CARD_ENABLED_PROFILES'] if ENV['CARD_ENABLED_PROFILES']
parser.register(params)
reference = nil
if ENV['CARD_COMPARE_ENCODING']
  reference = Object.new
  reference.instance_eval(File.read(File.join(directory, 'card_detail_parser.rb')), 'card_detail_parser.rb')
  reference.register('specs_path' => File.join(directory, 'card_detail_specs.json'),
                     'text_encoding' => ENV.fetch('CARD_COMPARE_ENCODING'))
end
workers = Integer(ENV.fetch('CARD_CORE_WORKERS', '1'))
raise 'workers must be 1..8' unless (1..8).cover?(workers)

routes = JSON.parse(File.read(ENV.fetch('CARD_REPLAY_MAP'), encoding: 'UTF-8'))
report = {
  'runtime' => RUBY_DESCRIPTION,
  'event_class' => LogStash::Event.name,
  'parser_version' => JSON.parse(File.read(File.join(directory, 'card_detail_specs.json'), encoding: 'UTF-8')).fetch('version'),
  'workers' => workers,
  'files' => []
}

# Public outcome contract mirrors bgf.conf: a hard parse failure is `error`,
# while a same-profile recovery that preserves common fields is `fallback`.
hard_error_event = LogStash::Event.new(
  'message' => 'get(data[)',
  '@metadata' => { 'target_alias' => 's_service_bcc_ic' }
)
parser.filter(hard_error_event)
hard_error_detail = hard_error_event.get('card_detail') || {}
hard_error_tags = Array(hard_error_event.get('tags')).map(&:to_s)
raise 'hard error status contract failed' unless hard_error_detail['status'] == 'error'
raise 'hard error public tag contract failed' unless hard_error_tags.include?('error') && !hard_error_tags.include?('fallback')
report['outcome_contract'] = { 'hard_error' => 'passed' }

short_body = 'ISO02340005302003000000000000000' + '000000' + '0000'
short_event = LogStash::Event.new('message' => "put(data[#{short_body}] len[#{short_body.bytesize}])",
                                   '@metadata' => { 'target_alias' => 's_service_cnb_ms' })
parser.filter(short_event)
raise 'short compatible frame did not fallback' unless short_event.get('[card_detail][status]') == 'fallback'
raise 'short frame fallback tag missing' unless Array(short_event.get('tags')).include?('fallback')
report['outcome_contract']['short_fallback'] = 'passed'

invalid_body = 'ISO02340005302003000000020000000' + '000000' + '000000000000' + 'XX'
invalid_event = LogStash::Event.new('message' => "put(data[#{invalid_body}] len[#{invalid_body.bytesize}])",
                                     '@metadata' => { 'target_alias' => 's_service_cnb_ms' })
parser.filter(invalid_event)
raise 'malformed length did not hard error' unless invalid_event.get('[card_detail][status]') == 'error'
raise 'malformed length error tag missing' unless Array(invalid_event.get('tags')).include?('error')
report['outcome_contract']['malformed_error'] = 'passed'
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
queue = SizedQueue.new(2048)

pool = workers.times.map do
  Thread.new do
    local = {
      'counts' => Hash.new(0), 'errors' => Hash.new(0), 'warnings' => Hash.new(0), 'tags' => Hash.new(0),
      'first_error_line' => {}, 'events' => 0, 'message_mutations' => 0,
      'route_mutations' => 0, 'events_with_exported_fields' => 0,
      'comparison_status' => Hash.new(0), 'comparison_fields' => Hash.new(0),
      'first_error_context' => {}
    }
    loop do
      item = queue.pop
      break unless item
      message, route, number, filename = item
      event = LogStash::Event.new('message' => message, '@metadata' => { 'target_alias' => route })
      returned = parser.filter(event)
      raise 'event lost or duplicated' unless returned.length == 1 && returned[0].equal?(event)
      local['message_mutations'] += 1 unless event.get('message') == message
      local['route_mutations'] += 1 unless event.get('[@metadata][target_alias]') == route
      detail = event.get('card_detail') || {}
      if reference
        reference_event = LogStash::Event.new('message' => message, '@metadata' => { 'target_alias' => route })
        reference.filter(reference_event)
        reference_detail = reference_event.get('card_detail') || {}
        if detail['status'] != reference_detail['status']
          local['comparison_status'][[filename, detail['profile'], detail['status'], reference_detail['status']].join('|')] += 1
        end
        actual_fields = detail['fields'] || {}
        reference_fields = reference_detail['fields'] || {}
        (actual_fields.keys | reference_fields.keys).each do |field|
          if actual_fields[field] != reference_fields[field]
            local['comparison_fields'][[filename, detail['profile'], field].join('|')] += 1
          end
        end
      end
      raise 'legacy result status leaked' if %w[partial failed warning ignored].include?(detail['status'])
      tags = Array(event.get('tags')).map(&:to_s)
      raise 'legacy internal card tag leaked' if tags.any? { |tag| tag.start_with?('_card_detail_') }
      raise 'conflicting public outcome tags' if tags.include?('error') && tags.include?('fallback')
      expected_tag = %w[error fallback].include?(detail['status']) ? detail['status'] : nil
      raise 'missing public outcome tag' if expected_tag && !tags.include?(expected_tag)
      raise 'unexpected public outcome tag' if !expected_tag && tags.any? { |tag| %w[error fallback].include?(tag) }
      if detail['status'] == 'control'
        raise 'invalid control result' unless detail['control_frame'] == true && !detail['record_type'].to_s.empty?
        raise 'control frame exported business fields' if detail['fields'] && !detail['fields'].empty?
      end
      tags.each { |tag| local['tags'][[filename, detail['profile'], tag].join('|')] += 1 }
      key = [filename, detail['profile'], detail['mti'], detail['record_type'], detail['status'], detail['frame_status']].join('|')
      local['counts'][key] += 1
      local['events_with_exported_fields'] += 1 if detail['fields'] && !detail['fields'].empty?
      detail.fetch('errors', []).each do |error|
        name = [filename, detail['profile'], error['code'], error['field']].join('|')
        local['errors'][name] += 1
        local['first_error_line'][name] ||= number
        if ENV['CARD_CORE_DIAGNOSTICS'] && !local['first_error_context'].key?(name)
          local['first_error_context'][name] = {
            'line' => number, 'offset' => error['offset'], 'expected' => error['expected'],
            'available' => error['available'], 'payload_bytes' => detail['payload_bytes'],
            'remaining_bytes' => detail['remaining_bytes'], 'parsed_field_count' => detail['parsed_field_count'],
            'present_fields' => detail['present_fields'], 'header_offset' => detail['header_offset'],
            'mti' => detail['mti'], 'declared_bytes' => detail['declared_bytes'],
            'logged_bytes' => detail['logged_bytes']
          }
        end
      end
      detail.fetch('warnings', []).each do |warning|
        local['warnings'][[filename, detail['profile'], warning].join('|')] += 1
      end
      local['events'] += 1
    end
    local
  end
end

routes.each do |filename, route|
  path = File.join(ENV.fetch('CARD_LOG_DIR'), filename)
  raise "missing replay file #{filename}" unless File.file?(path)
  physical = 0
  selected = 0
  sha = Digest::SHA256.new
  File.open(path, 'rb') do |file|
    file.each_line do |raw|
      physical += 1
      sha.update(raw)
      next unless /(?:get|put)\(/.match?(raw) || (raw.include?('==>') && /\[[SR]\]/.match?(raw))
      message = raw.sub(/\r?\n\z/, '').force_encoding('ISO-8859-1').encode('UTF-8')
      queue.push([message, route, physical, filename])
      selected += 1
    end
  end
  report['files'] << {
    'name' => filename, 'physical_lines' => physical, 'selected' => selected,
    'excluded' => physical - selected, 'sha256' => sha.hexdigest
  }
end

workers.times { queue.push(nil) }
merged = {
  'counts' => Hash.new(0), 'errors' => Hash.new(0), 'warnings' => Hash.new(0), 'tags' => Hash.new(0),
  'first_error_line' => {}, 'events' => 0, 'message_mutations' => 0,
  'route_mutations' => 0, 'events_with_exported_fields' => 0,
  'comparison_status' => Hash.new(0), 'comparison_fields' => Hash.new(0),
  'first_error_context' => {}
}
pool.each do |thread|
  local = thread.value
  %w[counts errors warnings tags comparison_status comparison_fields].each do |key|
    local[key].each { |name, value| merged[key][name] += value }
  end
  local['first_error_line'].each do |name, value|
    merged['first_error_line'][name] = [merged['first_error_line'].fetch(name, value), value].min
  end
  local['first_error_context'].each do |name, value|
    if !merged['first_error_context'].key?(name) || value['line'] < merged['first_error_context'][name]['line']
      merged['first_error_context'][name] = value
    end
  end
  %w[events message_mutations route_mutations events_with_exported_fields].each { |key| merged[key] += local[key] }
end
report['summary'] = merged
report['elapsed_seconds'] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
File.write(ENV.fetch('CARD_CORE_REPORT'), JSON.pretty_generate(report))
puts JSON.generate({ 'events' => merged['events'], 'errors' => merged['errors'].values.sum, 'elapsed_seconds' => report['elapsed_seconds'] })
raise 'parser mutated input events' unless merged['message_mutations'].zero? && merged['route_mutations'].zero?
