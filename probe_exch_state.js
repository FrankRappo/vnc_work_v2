var OUT=[]; function W(s){OUT.push(String(s));}
function S(v){try{return String(v);}catch(e){return '(?)';}}
function E(e){return (e && (e.message||e.description))?(e.message||e.description):String(e);}
function write(){var s=new ActiveXObject('ADODB.Stream'); s.Type=2; s.Charset='utf-8'; s.Open(); s.WriteText(OUT.join('\r\n')); s.SaveToFile('C:\\kso\\_probe_out.txt',2); s.Close();}
function rows(ib,title,text,params,fields,limit){W('--- '+title+' ---'); try{var q=ib.NewObject('Query'); q.Text=text; if(params){for(var k in params)q.SetParameter(k,params[k]);} var s=q.Execute().Choose(); var n=0; while(s.Next()&&n<(limit||50)){var a=[]; for(var i=0;i<fields.length;i++){var f=fields[i]; try{a.push(f+'='+S(s[f]));}catch(e){a.push(f+'=<err>');}} W(a.join(' | ')); n++;} W('rows='+n);}catch(e){W('ERROR '+E(e));}}
try{
 var ib=new ActiveXObject('V83.COMConnector').Connect('Srvr="DESKTOP-VGVHEOU";Ref="torg11_che";Usr="ОтрошенкоЛВ";Pwd="30061982";');
 W('CONNECT_OK '+new Date());
 // enum values of ДействияПриОбмене
 W('--- ENUM ДействияПриОбмене ---');
 try{var m=ib.Метаданные.Перечисления.ДействияПриОбмене; for(var i=0;i<m.ЗначенияПеречисления.Количество();i++){var ev=m.ЗначенияПеречисления.Получить(i); W(i+': name='+S(ev.Имя)); }}catch(e){W('enum err '+E(e));}
 try{ W('enum val ВыгрузкаДанных pres='+S(ib.Перечисления.ДействияПриОбмене.ВыгрузкаДанных)); }catch(e){W('ВыгрузкаДанных err '+E(e));}
 try{ W('enum val ЗагрузкаДанных pres='+S(ib.Перечисления.ДействияПриОбмене.ЗагрузкаДанных)); }catch(e){W('ЗагрузкаДанных err '+E(e));}
 // recent states with enum name AND presentation
 rows(ib,'СостоянияОбменовДанными (recent 15)',
   'ВЫБРАТЬ ПЕРВЫЕ 15 ПРЕДСТАВЛЕНИЕ(УзелИнформационнойБазы) КАК Node, ДействиеПриОбмене КАК ActVal, ПРЕДСТАВЛЕНИЕ(ДействиеПриОбмене) КАК Action, ПРЕДСТАВЛЕНИЕ(РезультатВыполненияОбмена) КАК Result, ДатаНачала КАК Start, ДатаОкончания КАК Finish ИЗ РегистрСведений.СостоянияОбменовДанными УПОРЯДОЧИТЬ ПО ДатаОкончания УБЫВ',
   {},['Node','ActVal','Action','Result','Start','Finish'],15);
 // successful-exchange register recent
 rows(ib,'СостоянияУспешныхОбменовДанными (recent 10)',
   'ВЫБРАТЬ ПЕРВЫЕ 10 ПРЕДСТАВЛЕНИЕ(УзелИнформационнойБазы) КАК Node, ПРЕДСТАВЛЕНИЕ(ДействиеПриОбмене) КАК Action, ДатаОкончания КАК Finish ИЗ РегистрСведений.СостоянияУспешныхОбменовДанными УПОРЯДОЧИТЬ ПО ДатаОкончания УБЫВ',
   {},['Node','Action','Finish'],10);
 // node list for the universal format plan
 rows(ib,'Узлы СинхронизацияДанныхЧерезУниверсальныйФормат',
   'ВЫБРАТЬ ПРЕДСТАВЛЕНИЕ(Ссылка) КАК Node, Код КАК Code, ЭтотУзел КАК ThisNode, ПометкаУдаления КАК Del ИЗ ПланОбмена.СинхронизацияДанныхЧерезУниверсальныйФормат УПОРЯДОЧИТЬ ПО Код',
   {},['Node','Code','ThisNode','Del'],20);
 // pending objects to send (backlog signal)
 rows(ib,'ОбъектыКОтправке by handler',
   'ВЫБРАТЬ ПРЕДСТАВЛЕНИЕ(УзелИнформационнойБазы) КАК Node, КОЛИЧЕСТВО(*) КАК C ИЗ РегистрСведений.ОбъектыКОтправке СГРУППИРОВАТЬ ПО УзелИнформационнойБазы',
   {},['Node','C'],20);
}catch(e){W('FATAL '+E(e));}
write();
