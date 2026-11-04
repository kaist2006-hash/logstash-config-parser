require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',__dir__)
p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
p.register('specs_path'=>File.join(dir,'card_detail_specs.json'))
bitmap=lambda do |bits|
 width=bits.max>128 ? 192 : (bits.max>64 ? 128 : 64)
 active=bits.dup;active<<1 if width>64;active<<65 if width>128
 bytes=Array.new(width/8,0);active.each{|bit|bytes[(bit-1)/8]|=128>>((bit-1)%8)};bytes.pack('C*')
end
cases=[]
parse=lambda do |name,wire,status,direction='OUT'|
 message="(I) :123:456:GILTC_X25A_P01:source.c:put_msg_complete:123: len[#{wire.bytesize}][#{direction=='OUT' ? 'S' : 'R'}]==>[#{wire.unpack1('H*').upcase}]"
 e=LogStash::Event.new('message'=>message,'log'=>{'file'=>{'path'=>'/opaque/not-lotte.bin'}})
 p.filter(e);d=e.get('card_detail');tags=Array(e.get('tags'))
 raise "#{name}: #{d['status']} #{d['errors']}" unless d['status']==status && d['profile']=='lotte_ic' && e.get('[@metadata][target_alias]')=='s_service_ltc_ic'
 raise 'message modified' unless e.get('message')==message
 raise 'error leaked fields' if status=='error' && d['fields']
 raise 'fallback tagged error' if status=='fallback' && (!tags.include?('fallback') || tags.include?('error'))
 cases<<{'name'=>name,'status'=>d['status'],'fields'=>d.fetch('fields',{}).keys}
 d
end
4.times do |i|
 [0,9].each do |area|
  [37,48].each do |track_count|
   domestic='0'*(i.even? ? 254 : 255);domestic[0,2]=['0410'].pack('H*');domestic[4,8]='A1234567'
   reference='%012d'%(123456789000+i)
   tlv=['9F3303E0F0C8'].pack('H*')
   fields={3=>['003000'].pack('H*'),4=>['%012d'%(1000+i)].pack('H*'),7=>['1104123456'].pack('H*'),11=>['123456'].pack('H*'),32=>[6].pack('C')+['879018'].pack('H*'),35=>[track_count].pack('C')+'X'*(track_count==48 ? 48 : (track_count+1)/2),37=>reference,39=>'00',42=>'123456789012345',49=>['0410'].pack('H*'),55=>[tlv.bytesize].pack('C')+tlv,118=>[domestic.bytesize].pack('C')+domestic,130=>['E0F0C8'].pack('H*'),131=>['0000000000'].pack('H*'),137=>['1234'].pack('H*')}
   fields[48]=(i.even? ? [4].pack('C') : '04')+('%04d'%i)
   direction=i.even? ? 'OUT' : 'IN';mti=direction=='OUT' ? '0200' : '0210'
   wire=' '*area+'ISO023400053'+[mti].pack('H*')+bitmap.call(fields.keys)+fields.sort.map{|_,value|value}.join
   d=parse.call("variable_area#{area}_track#{track_count}_#{i}",wire,'ok',direction)
   raise 'amount width or BCD wrong' unless d['fields']['transaction_amount']=='%012d'%(1000+i)
   raise 'variable track shifted following reference' unless d['fields']['retrieval_reference']==reference
   raise 'fee prefix variant shifted following fields' unless d['fields']['merchant_fee_rate_raw']=='%04d'%i
   raise 'domestic approval offset wrong' unless d['fields']['approval_number']=='A1234567'
   raise 'EMV parsing wrong' unless d['emv']['terminal_capabilities']=='E0F0C8'
  end
 end
end
base={3=>['003000'].pack('H*'),4=>['000000001000'].pack('H*'),7=>['1104123456'].pack('H*')}
make=lambda{|fields|'ISO023400053'+['0200'].pack('H*')+bitmap.call(fields.keys)+fields.sort.map{|_,value|value}.join}
parse.call('unknown_detail_after_complete_common',make.call(base.merge(57=>'UNREGISTERED')),'fallback')
parse.call('short_compound_after_complete_common',make.call(base.merge(118=>[254].pack('C')+'short')),'fallback')
parse.call('invalid_required_bcd_amount',make.call(base.merge(4=>['FA0000001000'].pack('H*'))),'error')
parse.call('missing_iso_header','garbage','error')
report={'result'=>'passed','source_document':'롯데카드_VAN IC 전문_20260721.xls','cases'=>cases}
File.write(ENV['CARD_REPORT_FILE'],JSON.pretty_generate(report)) if ENV['CARD_REPORT_FILE']
puts JSON.generate('result'=>'passed','cases'=>cases.size)
