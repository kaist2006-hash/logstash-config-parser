require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',__dir__)
p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
p.register('specs_path'=>File.join(dir,'card_detail_specs.json'))
parse=lambda do |body,length|
 message="put(data[#{body}] len[#{length}])"
 e=LogStash::Event.new('message'=>message,'@metadata'=>{'target_alias'=>'s_service_nlc_ic'})
 p.filter(e)
 raise 'message modified' unless e.get('message')==message
 [e.get('card_detail'),Array(e.get('tags'))]
end
body='NHCARD   '+'ISO000000000'+'0100'+'3200000000000000'+'000000'+'000000001000'+'20261104123456'
baseline=parse.call(body,body.bytesize)
raise 'baseline invalid' unless baseline[0]['status']=='ok'
tails=["\uE012","\u{1F600}","\uE012\uFFFD",' '*8+"\uE012",' '*8+"\u{1F600}\uFFFD",' '*8+"\uFFFD"]
tails.each{|tail|raise 'external suffix changed output' unless parse.call(body+tail,body.bytesize)==baseline}
["\uE012","\u{1F600}","\uFFFD"].each do |bad|
 damaged=body.dup;damaged[35]=bad
 raise 'internal damage accepted' if parse.call(damaged,body.bytesize)[0]['status']=='ok'
end
raise 'short internal field accepted' if parse.call(body,body.bytesize-3)[0]['status']=='ok'
multi=body+'가'
multi_result=parse.call(multi,multi.encode('CP949').bytesize)
raise 'multibyte field bytes changed' unless multi_result[0]['status']=='ok' && multi_result[0]['rest']=='B0A1'
puts JSON.generate('result'=>'passed','external_suffix_cases'=>tails.size,'internal_damage_cases'=>3,'short_payload_cases'=>1,'multibyte_rest_cases'=>1)
