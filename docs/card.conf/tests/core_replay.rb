# Executed INSIDE the Logstash 8.17.6 RubyUtil runtime, using real LogStash::Event.
# This is a parser/core test, not a substitute for Beats/file/Elasticsearch integration.
require 'json'
require 'digest'
require 'thread'
Thread.abort_on_exception = true

def canonical(value)
  case value
  when Hash then value.keys.sort.map { |k| [k, canonical(value[k])] }.to_h
  when Array then value.map { |v| canonical(v) }
  else value
  end
end

directory = ENV.fetch('CARD_PARSER_DIR')
parser = Object.new
parser.instance_eval(File.read(File.join(directory, 'card_detail_parser.rb')), 'card_detail_parser.rb')
parser.register('specs_path' => File.join(directory, 'card_detail_specs.json'), 'text_encoding' => 'ISO-8859-1')
workers = Integer(ENV.fetch('CARD_CORE_WORKERS', '1'))
raise 'workers must be 1..8' unless (1..8).cover?(workers)
report = { 'runtime' => RUBY_DESCRIPTION, 'event_class' => LogStash::Event.name, 'workers' => workers }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

if ENV['CARD_CONTRACT_FILE']
  results = []
  File.foreach(ENV['CARD_CONTRACT_FILE']) do |line|
    test = JSON.parse(line)
    event = LogStash::Event.new('message' => test['message'], '@metadata' => { 'target_alias' => test['route_alias'] })
    before = event.get('message')
    returned = parser.filter(event)
    detail = event.get('card_detail') || {}
    error_codes = detail.fetch('errors', []).map { |e| e['code'] }
    checks = {
      'status' => test['expected_status'].nil? || detail['status'] == test['expected_status'],
      'error' => test['expected_error'].nil? || error_codes.include?(test['expected_error']),
      'values' => test.fetch('expected_fields', {}).all? { |k,v| detail.fetch('fields', {})[k] == v },
      'retained' => returned.length == 1 && returned[0].equal?(event) && before == event.get('message'),
      'alias_unchanged' => event.get('[@metadata][target_alias]') == test['route_alias']
    }
    results << { 'id' => test['test_id'], 'checks' => checks, 'status' => detail['status'], 'errors' => error_codes }
  end
  # Collision must not destroy an existing object owned by another pipeline.
  event = LogStash::Event.new('message' => 'test', 'card_detail' => { 'keep' => 'existing' })
  parser.filter(event)
  results << { 'id' => 'target_collision', 'checks' => { 'preserved' => event.get('[card_detail][keep]') == 'existing', 'tagged' => event.get('tags').include?('_card_detail_target_collision') } }
  # Invalid configuration must fail register instead of silently ignoring a typo.
  invalid = Object.new
  invalid.instance_eval(File.read(File.join(directory, 'card_detail_parser.rb')))
  rejected = false
  begin
    invalid.register('specs_path' => File.join(directory, 'card_detail_specs.json'), 'enabled_profiles' => 'typo_profile')
  rescue ArgumentError
    rejected = true
  end
  results << { 'id' => 'invalid_profile_rejected', 'checks' => { 'rejected' => rejected } }
  report['contracts'] = results
  report['passed'] = results.count { |r| r['checks'].values.all? }
  report['failed'] = results.length - report['passed']
else
  routes = { 'GICNB_X25A_P01' => 's_service_cnb_ic', 'GCLTC_X25A_P01' => 's_service_ltc_ms' }
  queue = SizedQueue.new(1024)
  # One shared parser instance, as in a multiworker Ruby filter. Only counters are local.
  pool = workers.times.map do
    Thread.new do |; local, item, message, route, number, event, returned, detail, key, digest|
      local = { 'counts' => Hash.new(0), 'errors' => Hash.new(0), 'warnings' => Hash.new(0), 'first_error_line' => {}, 'digest_sum' => 0, 'digest_xor' => 0, 'events' => 0, 'message_mutations' => 0, 'route_mutations' => 0 }
      loop do
        item = queue.pop
        break unless item
        message, route, number = item
        event = LogStash::Event.new('message' => message, '@metadata' => { 'target_alias' => route })
        returned = parser.filter(event)
        raise 'event lost or duplicated' unless returned.length == 1 && returned[0].equal?(event)
        local['message_mutations'] += 1 unless event.get('message') == message
        local['route_mutations'] += 1 unless event.get('[@metadata][target_alias]') == route
        detail = event.get('card_detail')
        key = [detail['profile'],detail['mti'],detail['status'],detail['frame_status']].join('|')
        local['counts'][key] += 1
        detail.fetch('errors', []).each do |e|
          k = [detail['profile'],e['code'],e['field']].join('|')
          local['errors'][k] += 1
          local['first_error_line'][k] ||= number
        end
        detail.fetch('warnings', []).each { |w| local['warnings'][[detail['profile'],w].join('|')] += 1 }
        digest = Digest::SHA256.hexdigest(JSON.generate(canonical(detail))).to_i(16)
        local['digest_sum'] = (local['digest_sum'] + digest) % (1 << 256)
        local['digest_xor'] ^= digest
        local['events'] += 1
      end
      local
    end
  end
  report['files'] = []
  routes.each do |stem,route|
    files = Dir.glob(File.join(ENV.fetch('CARD_LOG_DIR'), stem + '*.log'))
    raise "expected one file for #{stem}" unless files.length == 1
    physical = 0
    selected = 0
    sha = Digest::SHA256.new
    File.open(files[0], 'rb') do |file|
      file.each_line do |raw|
        physical += 1
        sha.update(raw)
        # Same selection as original conf; envelope filters themselves are not run here.
        next unless /(?:get|put)\(/.match?(raw) || (raw.include?('==>') && /\[[SR]\]/.match?(raw))
        message = raw.sub(/\r?\n\z/, '').force_encoding('ISO-8859-1').encode('UTF-8')
        queue.push([message,route,physical])
        selected += 1
        puts "read #{stem}: #{selected} transactions" if (selected % 50_000).zero?
      end
    end
    report['files'] << { 'name' => File.basename(files[0]), 'physical_lines' => physical, 'selected' => selected, 'excluded_by_original_selection' => physical-selected, 'sha256' => sha.hexdigest }
  end
  workers.times { queue.push(nil) }
  merged = { 'counts' => Hash.new(0), 'errors' => Hash.new(0), 'warnings' => Hash.new(0), 'first_error_line' => {}, 'digest_sum' => 0, 'digest_xor' => 0, 'events' => 0, 'message_mutations' => 0, 'route_mutations' => 0 }
  pool.each do |thread|
    local = thread.value
    %w[counts errors warnings].each { |k| local[k].each { |n,v| merged[k][n] += v } }
    local['first_error_line'].each { |k,v| merged['first_error_line'][k] = [merged['first_error_line'].fetch(k,v),v].min }
    %w[events message_mutations route_mutations].each { |k| merged[k] += local[k] }
    merged['digest_sum'] = (merged['digest_sum'] + local['digest_sum']) % (1 << 256)
    merged['digest_xor'] ^= local['digest_xor']
  end
  %w[digest_sum digest_xor].each { |k| merged[k] = merged[k].to_s(16).rjust(64,'0') }
  report['summary'] = merged
end
report['elapsed_seconds'] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
File.write(ENV.fetch('CARD_CORE_REPORT'), JSON.pretty_generate(report))
puts JSON.generate(report.reject { |k,v| k == 'contracts' })
raise 'contract failures' if report.fetch('failed',0) > 0
