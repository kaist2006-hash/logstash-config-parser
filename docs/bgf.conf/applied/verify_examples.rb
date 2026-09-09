# frozen_string_literal: true
# 선택 실행: ruby verify_examples.rb
# Logstash 설치 없이 Ruby로 교육용 샘플의 예상 필드를 비교합니다.
# 실제 Logstash Event/JRuby/인코딩/파이프라인 검증을 대신하지는 않습니다.
require "json"

class GuideEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def keys_for(path)
    path.start_with?("[") ? path.scan(/\[([^\]]+)\]/).flatten : [path]
  end

  def get(path)
    keys_for(path).reduce(@data) { |obj, key| obj.is_a?(Hash) ? obj[key] : nil }
  end

  def set(path, value)
    keys = keys_for(path)
    parent = keys[0...-1].reduce(@data) { |obj, key| obj[key] ||= {} }
    parent[keys[-1]] = value
  end

  def remove(path)
    keys = keys_for(path)
    parent = keys[0...-1].reduce(@data) { |obj, key| obj.is_a?(Hash) ? obj[key] : nil }
    parent.delete(keys[-1]) if parent.is_a?(Hash)
  end

  def tag(tag)
    @data["tags"] ||= []
    @data["tags"] << tag unless @data["tags"].include?(tag)
  end
end

def check_subset(actual, expected, path = "")
  expected.each do |key, wanted|
    location = "#{path}[#{key}]"
    raise "missing #{location}" unless actual.is_a?(Hash) && actual.key?(key)
    got = actual[key]
    if wanted.is_a?(Hash)
      check_subset(got, wanted, location)
    else
      raise "#{location}: expected #{wanted.inspect}, got #{got.inspect}" unless got == wanted
    end
  end
end

root = File.expand_path(__dir__)
configs = {
  "detail" => ["nice_pos_detail_parser.rb", "nice_pos_detail_specs.json"],
  "fs" => ["nice_pos_fs_parser_.rb", "nice_pos_fs_specs_.json"]
}
parsers = {}
configs.each do |name, pair|
  rb_path = File.join(root, "files", pair[0])
  context = Object.new
  context.instance_eval(File.read(rb_path, encoding: "UTF-8"), rb_path, 1)
  context.register("spec_path" => File.join(root, "files", pair[1]))
  parsers[name] = context
end

passed = 0
JSON.parse(File.read(File.join(root, "samples", "events.json"), encoding: "UTF-8")).each do |sample|
  event = GuideEvent.new(sample.fetch("event"))
  parsers.fetch(sample.fetch("parser")).filter(event)
  check_subset(event.data, sample.fetch("expected_subset"))
  sample.fetch("absent_paths", []).each do |path|
    raise "#{sample['id']}: unexpected #{path}" unless event.get(path).nil?
  end
  puts "PASS #{sample.fetch('id')}"
  passed += 1
end
puts "#{passed} samples passed"
