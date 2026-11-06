require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',__dir__)
p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
p.register('specs_path'=>File.join(dir,'card_detail_specs.json'))
cases=[]
bitmap=lambda do |bits|
 b=Array.new(8,0);bits.each{|i|b[(i-1)/8]|=128>>((i-1)%8)};b.pack('C*').unpack1('H*').upcase
end
parse=lambda do |name,body,length,status,route='s_service_cnb_ms'|
 e=LogStash::Event.new('message'=>"put(data[#{body}] len[#{length}])",'@metadata'=>{'target_alias'=>route})
 p.filter(e);d=e.get('card_detail');tags=Array(e.get('tags'))
 raise "#{name}: #{d['status']} != #{status}: #{d['errors']}" unless d['status']==status
 raise 'fallback tagged error' if status=='fallback' && (tags.include?('error') || !tags.include?('fallback'))
 raise 'invalid event exported detail' if status=='error' && (d['emv'] || d['rest'])
 cases<<{'name'=>name,'status'=>status,'fields'=>d.fetch('fields',{}).keys,'codes'=>d.fetch('errors',[]).map{|x|x['code']}}
 d
end
head='ISO0234000530200';base='000000'+'000000001000'+'1104123456'
good=head+bitmap.call([3,4,7])+base
parse.call('valid_detail',good,good.bytesize,'ok')
partial=head+bitmap.call([3,4,7,35])+base+"\uE012"
d=parse.call('unreversible_after_common',partial,partial.length+5,'fallback')
raise 'recovered common amount wrong' unless d['fields']['transaction_amount']=='000000001000'
partial=head+bitmap.call([3,4,7])+'000000'+"\uE012"+'bad'
parse.call('unreversible_before_common',partial,partial.length+10,'error')
multi=head+bitmap.call([3,4,7,35])+base+'04가나'
parse.call('unreversible_outside_complete_multibyte_payload',multi+"\uE012",multi.encode('CP949').bytesize,'ok')
unknown='ISO0234000510200'+bitmap.call([3,4,7])+base
d=parse.call('unknown_header_common_only',unknown,unknown.bytesize,'fallback')
raise 'unknown header invented business fields' unless d.fetch('fields',{}).empty?
short='ISO0234000510200'+bitmap.call([3,4,7])
parse.call('unknown_header_no_announced_data',short,short.bytesize,'error')
bad='ISO0234000510200'+'Z'*16+base
parse.call('invalid_unknown_bitmap',bad,bad.bytesize,'error')
bad=head+bitmap.call([3,4,7])+'000000'+'0000X0000000'+'1104123456'
parse.call('invalid_required_amount',bad,bad.bytesize,'error')
legacy='ISO023400053'+['0540'].pack('H*')+[bitmap.call([3,4,7])].pack('H*')+['000000'+'000000001000'+'1104123456'].pack('H*')
wire=['%04d'%legacy.bytesize].pack('H*')+legacy
e=LogStash::Event.new('message'=>"len[#{wire.bytesize}][S]==>[#{wire.unpack1('H*')}]",'@metadata'=>{'target_alias'=>'s_service_bcc_ic'})
p.filter(e);d=e.get('card_detail')
raise 'legacy common amount width incorrect' unless d['status']=='fallback' && d['fields']['transaction_amount']=='000000001000' && d['fields']['transmission_datetime']=='1104123456'
cases<<{'name'=>'documented_legacy_bc_common_width','status'=>d['status'],'fields'=>d['fields'].keys}
%w[BCA6998 EPT6926].each do |marker|
 body=' '*260;body[9,7]=marker;body[16,12]='000001234567';body[28,14]='20261104123456'
 encoded=('%04d'%body.bytesize)+body
 d=parse.call('unknown_bc_fixed_'+marker,encoded,encoded.bytesize,'fallback','s_service_bcc_ms')
 raise 'unknown BC amount invented' if d['fields']['transaction_amount']
 raise 'unknown BC header reference wrong' unless d['fields']['retrieval_reference']=='000001234567'
end
body=' '*512;body[9,7]='BCB0481';body[16,12]='000001234567';body[28,14]='20261104123456';body[80,4]='0000'
encoded=('%04d'%body.bytesize)+body
parse.call('known_fixed_direction_mismatch',encoded,encoded.bytesize,'error','s_service_bcc_ms')
report={'result'=>'passed','cases'=>cases}
File.write(ENV['CARD_REPORT_FILE'],JSON.pretty_generate(report)) if ENV['CARD_REPORT_FILE']
puts JSON.pretty_generate(report)
