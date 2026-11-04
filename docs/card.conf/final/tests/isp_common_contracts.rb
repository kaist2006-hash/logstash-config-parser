require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',__dir__)
p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
p.register('specs_path'=>File.join(dir,'card_detail_specs.json'))
cases=[]
check=lambda do |name,direction,body,expected,route='s_service_cnb_ms'|
 operation=direction=='OUT' ? 'put' : 'get'
 message="#{operation}(data[#{body}] len[#{body.bytesize}])"
 e=LogStash::Event.new('message'=>message,'@metadata'=>{'target_alias'=>route})
 p.filter(e);d=e.get('card_detail');tags=Array(e.get('tags'))
 raise "#{name}: #{d['status']}" unless d['status']==expected
 raise 'opaque record invented business fields' unless d.fetch('fields',{}).empty?
 raise 'message modified' unless e.get('message')==message
 if expected=='fallback'
  raise 'wrong fallback tag' unless tags.include?('fallback') && !tags.include?('error')
  raise 'missing recognition warning' unless d.fetch('warnings',[]).include?('unregistered_record_common_header_only')
 else
  raise 'wrong error tag' unless tags.include?('error') && !tags.include?('fallback')
 end
 cases<<{'name'=>name,'status'=>d['status'],'record_type'=>d['record_type']}
end
24.times do |i|
 request='ISP'+('%036d'%(i*731+1))+('A'..'Z').to_a[i,3].to_a.join.ljust(3,'Z')+' '*37+('%04d'%i)+'ABC'
 response='CCNBCCRDISP'+('%034d'%(i*937+1))
 check.call('observed_isp_request_variable_'+i.to_s,'OUT',request,'fallback')
 check.call('observed_isp_response_variable_'+i.to_s,'IN',response,'fallback')
end
request='ISP'+'0'*36+'ABC'+' '*37+'1234'+'DEF'
response='CCNBCCRDISP'+'0'*34
check.call('wrong_request_direction','IN',request,'error')
check.call('short_response','IN',response[0...-1],'error')
check.call('non_numeric_response','IN',response.sub('0','X'),'error')
check.call('wrong_request_numeric_slot','OUT',request.sub('0','X'),'error')
check.call('other_issuer_does_not_inherit_isp','OUT',request,'error','s_service_win_ms')
report={'result'=>'passed','observed_signature_only'=>true,'internal_business_layout_verified'=>false,'cases'=>cases}
File.write(ENV['CARD_REPORT_FILE'],JSON.pretty_generate(report)) if ENV['CARD_REPORT_FILE']
puts JSON.generate('result'=>'passed','cases'=>cases.size)
