(function(){
const oldRender=render;
tabs.splice(3,0,['labels','Etikettendesigner']);
Object.assign(state,{labels:[],label:null,labelSelected:null,labelSelectedIds:[],labelLoaded:false,labelMessage:'',labelZpl:'',labelUnit:'dots',labelTestPlu:'',labelTestWeight:.5});
const variables=[
 ['artikel','Artikelbezeichnung','Bergkaese natur'],['artikel2','Bezeichnung 2','aus Heumilch'],
 ['plu','PLU / Nummer','1024'],['ean','EAN','4012345678901'],['gewicht','Bruttogewicht','0,600 kg'],
 ['tara','Tara','0,050 kg'],['netto','Nettogewicht','0,550 kg'],['fuellgewicht','Füllgewicht','0,350 kg'],['preisKg','Preis je kg','16,90 EUR/kg'],
 ['preis','Gesamtpreis','9,30 EUR'],['mhd','MHD','01.07.2026'],['einheit','Mengeneinheit','kg'],
 ['zutaten','Zutaten','Milch, Salz, Kulturen'],['temperatur','Lagerung','bei 7 C Lagerung']
];
const sample=Object.fromEntries(variables.map(v=>[v[0],v[2]]));
sample.preis100g='1,69 EUR/100 g';sample.fuellgewichtG='350 g';
function effectiveFieldVariable(o){if(o?.displayUnit==='100g'&&o.variable==='preisKg')return 'preis100g';if(o?.displayUnit==='100g'&&o.variable==='fuellgewicht')return 'fuellgewichtG';return o?.variable||'artikel'}
const defaultAllergens=['gluten','weizen','roggen','gerste','hafer','krebstiere','ei','eier','fisch','erdnuss','erdnüsse','soja','milch','laktose','schalenfrüchte','mandel','haselnuss','walnuss','cashew','pecannuss','paranuss','pistazie','macadamia','sellerie','sellere','senf','sesam','sulfite','lupine','weichtiere'];
const nutritionSample={kj:'1250',kcal:'300',fat:'24,0 g',saturates:'15,0 g',carbs:'1,0 g',sugar:'0,5 g',protein:'22,0 g',salt:'1,8 g'};
const zebraFonts=[['0','Zebra 0 - skalierbar'],['A','Zebra A'],['B','Zebra B'],['D','Zebra D'],['E','Zebra E'],['F','Zebra F']];
function eanCheck(s){let sum=0;for(let i=0;i<12;i++)sum+=Number(s[i]||0)*(i%2?3:1);return String((10-sum%10)%10)}
function fillRun(ch,count){const values={N:'01024',P:'00930',G:'00550'};return (values[ch]||'0'.repeat(count)).padStart(count,'0').slice(-count)}
function previewEan(pattern){let p=String(pattern||'22NNNNNPPPPPQ').toUpperCase(),base='';for(let i=0;i<p.length;i++){const ch=p[i];if(ch==='Q')continue;if('NPG'.includes(ch)){let j=i;while(p[j]===ch)j++;base+=fillRun(ch,j-i);i=j-1}else if(/\d/.test(ch))base+=ch}base=base.slice(0,12).padEnd(12,'0');return base+eanCheck(base)}
function allergenHtml(text,list,style){const a=(list||defaultAllergens).map(x=>x.toLocaleLowerCase('de-DE'));return String(text||'').split(/(\p{L}+[\p{L}-]*)/u).map(part=>a.includes(part.toLocaleLowerCase('de-DE'))?'<strong class="'+(style==='underline'?'under':'')+'">'+esc(part)+'</strong>':esc(part)).join('')}
function labelId(){return 'label-'+Date.now()}
function objectId(){return 'obj-'+Date.now()+'-'+Math.floor(Math.random()*9999)}
function newLabel(){
 return {id:labelId(),number:0,name:'Neues Etikett',labelType:'standard',widthMm:44,heightMm:19,dpi:300,darkness:12,speed:3,orientation:'N',rfidZpl:'$WRITE_RFID$',objects:[]};
}
function dotsPerMm(l){return Number(l?.dpi||300)/25.4}
function unitValue(v){return state.labelUnit==='mm'?Number((Number(v||0)/dotsPerMm(state.label)).toFixed(2)):Math.round(Number(v||0))}
function unitStep(){return state.labelUnit==='mm'?0.1:1}
function unitName(){return state.labelUnit==='mm'?'mm':'Dots'}
function fromUnit(v){return state.labelUnit==='mm'?Math.round(Number(v||0)*dotsPerMm(state.label)):Math.round(Number(v||0))}
function setLabelUnit(unit){state.labelUnit=unit==='mm'?'mm':'dots';render()}
function labelDots(l){const d=dotsPerMm(l);return {w:Math.max(1,Math.round(Number(l.widthMm||44)*d)),h:Math.max(1,Math.round(Number(l.heightMm||19)*d))}}
function selectedObj(){return state.label?.objects?.find(o=>o.id===state.labelSelected)||null}
function selectedObjects(){const ids=new Set(state.labelSelectedIds||[]);return (state.label?.objects||[]).filter(o=>ids.has(o.id))}
function setObjectSelection(id,toggle){const ids=new Set(state.labelSelectedIds||[]);if(toggle){ids.has(id)?ids.delete(id):ids.add(id)}else{ids.clear();ids.add(id)}state.labelSelectedIds=[...ids];state.labelSelected=state.labelSelectedIds.includes(id)?id:(state.labelSelectedIds[0]||null)}
function barcodeModuleWidth(o){return o.fitWidth===false?Math.max(1,Number(o.moduleWidth||2)):Math.max(1,Math.min(10,Math.floor(Number(o.w||190)/95)))}
function zplLiteral(v){return String(v||'').replace(/[\\^~\r\n]/g,' ')}
function valueFor(o){
 if(o.type==='field'){const v=effectiveFieldVariable(o);return (o.prefix||'')+(sample[v]||('$'+v+'$'))+(o.suffix||'')}
 if(o.type==='barcode')return o.eanMode&&o.eanMode!=='direct'?previewEan(o.eanPattern):(sample[o.variable||'ean']||'4012345678901');
 return o.value||'Text';
}
function loadLabels(){
 state.labelLoaded=true;
 fetch(apiUrl('/api/admin/labels'),{cache:'no-store'}).then(readJsonResponse).then(x=>{state.labels=Array.isArray(x)?x:[];render()}).catch(e=>{state.labelMessage=e.message;render()});
}
async function openLabel(id){
 try{const j=await readJsonResponse(await fetch(apiUrl('/api/admin/label?id='+encodeURIComponent(id)),{cache:'no-store'}));if(j.ok===false)throw new Error(j.message);state.label=j;state.labelSelected=null;state.labelSelectedIds=[];state.labelZpl=generateZplSync(j);render()}catch(e){state.labelMessage=e.message;render()}
}
function createLabel(){state.label=newLabel();state.labelSelected=null;state.labelZpl=generateZplSync(state.label);render()}
function duplicateLabel(){if(!state.label)return;const n=JSON.parse(JSON.stringify(state.label));n.id=labelId();n.number=0;n.name+=' - Kopie';n.objects.forEach(o=>o.id=objectId());state.label=n;state.labelSelected=null;state.labelSelectedIds=[];render()}
async function deleteLabelTemplate(){
 if(!state.label||!confirm('Etikettenvorlage wirklich loeschen?'))return;
 const j=await readJsonResponse(await fetch(apiUrl('/api/admin/label/delete?id='+encodeURIComponent(state.label.id)),{cache:'no-store'}));
 state.labelMessage=j.message||'';state.label=null;state.labelSelected=null;await loadLabels();
}
function addObject(type){
 if(!state.label)return;
 const base={id:objectId(),type,x:20,y:20,w:220,h:48,rotation:0};
 if(type==='text')Object.assign(base,{value:'Text',font:'0',fontSize:34,fontWidth:30,align:'L',bold:false,italic:false,maxLines:1,lineSpacing:0});
 if(type==='field')Object.assign(base,{variable:'artikel',prefix:'',suffix:'',font:'0',fontSize:34,fontWidth:30,align:'L',bold:false,italic:false,maxLines:2,lineSpacing:2});
 if(type==='barcode')Object.assign(base,{variable:'ean',barcodeType:'ean13',eanMode:'direct',eanPattern:'22NNNNNPPPPPQ',humanReadable:true,h:80,w:300,moduleWidth:2});
 if(type==='ingredients')Object.assign(base,{prefix:'Zutaten: ',font:'0',fontSize:24,fontWidth:22,align:'L',bold:false,italic:false,maxLines:6,lineSpacing:3,w:380,h:150,allergenStyle:'bold',allergens:[...defaultAllergens]});
 if(type==='nutrition')Object.assign(base,{value:'Nährwerte je 100 g',font:'0',fontSize:22,fontWidth:20,align:'L',bold:false,italic:false,maxLines:9,lineSpacing:2,w:380,h:240,nutritionBorder:true});
 if(type==='line')Object.assign(base,{w:240,h:3,thickness:3});
 if(type==='box')Object.assign(base,{w:240,h:90,thickness:3});
 if(type==='image')return document.getElementById('labelImageUpload')?.click();
 state.label.objects.push(base);state.labelSelected=base.id;state.labelSelectedIds=[base.id];render();
}
function escAttr(s){return esc(s).replace(/'/g,'&#39;')}
function renderObject(o,scale){
 const common='left:'+(o.x*scale)+'px;top:'+(o.y*scale)+'px;width:'+(o.w*scale)+'px;height:'+(o.h*scale)+'px;transform:rotate('+(o.rotation||0)+'deg)';
 let body='';
 if(o.type==='text'||o.type==='field')body='<div class="ldTextFrame"><div class="ldText" style="font-size:'+Math.max(8,(o.fontSize||30)*scale)+'px;text-align:'+(o.align==='C'?'center':o.align==='R'?'right':'left')+';font-weight:'+(o.bold?'900':'500')+';font-style:'+(o.italic?'italic':'normal')+';white-space:'+(Number(o.maxLines||1)>1?'normal':'nowrap')+'">'+esc(valueFor(o))+'</div></div>';
 if(o.type==='ingredients')body='<div class="ldText ldIngredients" style="font-size:'+Math.max(8,(o.fontSize||24)*scale)+'px;font-style:'+(o.italic?'italic':'normal')+'">'+esc(o.prefix||'Zutaten: ')+allergenHtml(sample.zutaten+', Sellerie, Senf, Ei, Weizen',o.allergens,o.allergenStyle)+'</div>';
 if(o.type==='nutrition')body='<div class="ldNutrition"><b>'+esc(o.value||'Nährwerte je 100 g')+'</b>'+[['Energie',nutritionSample.kj+' kJ / '+nutritionSample.kcal+' kcal'],['Fett',nutritionSample.fat],['davon gesättigt',nutritionSample.saturates],['Kohlenhydrate',nutritionSample.carbs],['davon Zucker',nutritionSample.sugar],['Eiweiß',nutritionSample.protein],['Salz',nutritionSample.salt]].map(r=>'<span>'+esc(r[0])+'<strong>'+esc(r[1])+'</strong></span>').join('')+'</div>';
 if(o.type==='barcode'){const mw=barcodeModuleWidth(o),bw=Math.min(o.w,Math.max(1,95*mw));body='<div class="ldBarcode" style="width:'+(bw*scale)+'px"><i style="background-size:'+Math.max(2,mw*4*scale)+'px 100%"></i><span>'+(o.humanReadable?esc(valueFor(o)):'')+'</span></div>'}
 if(o.type==='line')body='<div class="ldLine" style="height:'+Math.max(1,(o.thickness||2)*scale)+'px"></div>';
 if(o.type==='box')body='<div class="ldBox" style="border-width:'+Math.max(1,(o.thickness||2)*scale)+'px"></div>';
 if(o.type==='image')body='<img src="'+escAttr(o.dataUrl||'')+'" alt="Bild">';
 return '<div class="ldObject '+((state.labelSelectedIds||[]).includes(o.id)?'selected':'')+'" data-oid="'+escAttr(o.id)+'" style="'+common+'">'+body+'<b class="ldHandle"></b></div>';
}
function numInput(id,label,val,min=0,step=1){return '<label>'+label+'<input id="'+id+'" type="number" min="'+min+'" step="'+step+'" value="'+esc(val)+'"></label>'}
function fontValue(v){return state.labelUnit==='mm'?Number((Number(v||0)/dotsPerMm(state.label)).toFixed(2)):Math.round(Number(v||0))}
function fontUnitName(){return state.labelUnit==='mm'?'mm':'Dots (Druckpunkte)'}
function fontControls(o){
 return '<div class="ldUnitHint">Schriftmasse werden in '+fontUnitName()+' angezeigt. Zebra druckt intern immer in Dots.</div><label>Schrift<select id="op_font">'+zebraFonts.map(f=>'<option value="'+f[0]+'" '+((o.font||'0')===f[0]?'selected':'')+'>'+f[1]+'</option>').join('')+'</select></label><label class="ldCheck"><input id="op_bold" type="checkbox" '+(o.bold?'checked':'')+'> Fett</label><label class="ldCheck"><input id="op_italic" type="checkbox" '+(o.italic?'checked':'')+'> Kursiv</label>'+numInput('op_fontSize','Schrifthoehe ('+fontUnitName()+')',fontValue(o.fontSize||30),state.labelUnit==='mm'?.5:8,unitStep())+numInput('op_fontWidth','Schriftbreite ('+fontUnitName()+')',fontValue(o.fontWidth||o.fontSize||30),state.labelUnit==='mm'?.5:8,unitStep())+numInput('op_maxLines','Zeilen',o.maxLines||1,1,1)+numInput('op_lineSpacing','Zeilenabstand ('+fontUnitName()+')',fontValue(o.lineSpacing||0),0,unitStep());
}
function objectProperties(){
 const o=selectedObj();if(!o)return '<div class="ldEmpty">Objekt anklicken, um Position und Format zu bearbeiten.</div>';
 let special='';
 if(o.type==='text')special='<label>Text<textarea id="op_value">'+esc(o.value||'')+'</textarea></label>';
 if(o.type==='field')special='<label>Datenfeld<select id="op_variable">'+variables.map(v=>'<option value="'+v[0]+'" '+(v[0]===o.variable?'selected':'')+'>'+esc(v[1])+'</option>').join('')+'</select></label><label>Text davor<input id="op_prefix" value="'+escAttr(o.prefix||'')+'"></label><label>Text danach<input id="op_suffix" value="'+escAttr(o.suffix||'')+'"></label><label>Anzeige<select id="op_displayUnit"><option value="standard" '+(o.displayUnit!=='100g'?'selected':'')+'>Standard (kg / EUR je kg)</option><option value="100g" '+(o.displayUnit==='100g'?'selected':'')+'>Gramm / EUR je 100 g</option></select></label>';
 if(o.type==='ingredients')special='<label>Überschrift<input id="op_prefix" value="'+escAttr(o.prefix||'Zutaten: ')+'"></label><label>Allergene, kommagetrennt<textarea id="op_allergens">'+esc((o.allergens||defaultAllergens).join(', '))+'</textarea></label><label>Hervorhebung<select id="op_allergenStyle"><option value="bold" '+(o.allergenStyle==='bold'?'selected':'')+'>Fett</option><option value="underline" '+(o.allergenStyle==='underline'?'selected':'')+'>Unterstrichen</option></select></label>';
 if(o.type==='nutrition')special='<label>Überschrift<input id="op_value" value="'+escAttr(o.value||'Nährwerte je 100 g')+'"></label><label class="ldCheck"><input id="op_nutritionBorder" type="checkbox" '+(o.nutritionBorder?'checked':'')+'> Tabellenlinien</label>';
 if(o.type==='barcode')special='<label>Inhalt<select id="op_variable">'+variables.map(v=>'<option value="'+v[0]+'" '+(v[0]===o.variable?'selected':'')+'>'+esc(v[1])+'</option>').join('')+'</select></label><label>Barcode<select id="op_barcodeType"><option value="ean13" '+(o.barcodeType==='ean13'?'selected':'')+'>EAN-13</option><option value="code128" '+(o.barcodeType==='code128'?'selected':'')+'>Code 128</option></select></label><label>EAN-Codierung<select id="op_eanMode"><option value="direct" '+(o.eanMode==='direct'?'selected':'')+'>EAN aus Artikel</option><option value="price" '+(o.eanMode==='price'?'selected':'')+'>Preis-EAN</option><option value="weight" '+(o.eanMode==='weight'?'selected':'')+'>Gewichts-EAN</option><option value="custom" '+(o.eanMode==='custom'?'selected':'')+'>Eigenes Muster</option></select></label><label>Codiermuster<input id="op_eanPattern" value="'+escAttr(o.eanPattern||'22NNNNNPPPPPQ')+'"></label><div class="eanLegend"><b>Ziffern</b> Kennzahl · <b>N</b> Nummer · <b>P</b> Preis · <b>G</b> Gewicht · <b>Q</b> Prüfziffer<br>Vorschau: <code>'+previewEan(o.eanPattern)+'</code></div><label class="ldCheck"><input id="op_humanReadable" type="checkbox" '+(o.humanReadable?'checked':'')+'> lesbaren Text drucken</label><label class="ldCheck"><input id="op_fitWidth" type="checkbox" '+(o.fitWidth!==false?'checked':'')+'> Breite an Objekt anpassen</label>'+numInput('op_moduleWidth','Modulbreite (Dots)',o.moduleWidth||2,1,1);
 if(['text','field','ingredients','nutrition'].includes(o.type))special+=fontControls(o)+'<label>Ausrichtung<select id="op_align"><option value="L" '+(o.align==='L'?'selected':'')+'>Links</option><option value="C" '+(o.align==='C'?'selected':'')+'>Zentriert</option><option value="R" '+(o.align==='R'?'selected':'')+'>Rechts</option></select></label>';
 if(o.type==='line'||o.type==='box')special+=numInput('op_thickness','Linienstärke',o.thickness||2,1,1);
 const names={text:'Text',field:'Datenfeld',barcode:'Barcode / EAN',ingredients:'Zutaten mit Allergenen',nutrition:'Nährwerttabelle',image:'Bild',line:'Linie',box:'Rahmen'};
 return '<div class="ldPropTitle">'+esc(names[o.type]||o.type)+'</div><div class="ldPropGrid">'+numInput('op_x','X ('+unitName()+')',unitValue(o.x),0,unitStep())+numInput('op_y','Y ('+unitName()+')',unitValue(o.y),0,unitStep())+numInput('op_w','Breite ('+unitName()+')',unitValue(o.w),state.labelUnit==='mm'?.1:1,unitStep())+numInput('op_h','Höhe ('+unitName()+')',unitValue(o.h),state.labelUnit==='mm'?.1:1,unitStep())+numInput('op_rotation','Drehung',o.rotation||0,0,90)+special+'</div><div class="ldPropActions"><button onclick="applyLabelObject()">Übernehmen</button><button onclick="cloneLabelObject()">Duplizieren</button><button class="danger" onclick="removeLabelObject()">Löschen</button></div>';
}
function labelsDesigner(){
 if(!state.labelLoaded)setTimeout(loadLabels,0);if(!state.articleTried&&!state.articleBusy)setTimeout(loadArticleData,0);
 const l=state.label;
 const list=state.labels.map(x=>'<button class="'+(l?.id===x.id?'active':'')+'" onclick="openLabel(\''+escAttr(x.id)+'\')"><b>#'+esc(x.number||'-')+' - '+esc(x.name)+'</b><span>'+esc(x.labelType==='rfid'?'RFID':'Standard')+' | '+esc(x.widthMm)+' x '+esc(x.heightMm)+' mm</span></button>').join('');
 if(!l)return '<h1 class="sectionTitle">Etikettendesigner ZPL2</h1><div class="ldShell empty"><aside class="ldTemplates"><div class="ldListHead"><b>Vorlagen</b><button onclick="createLabel()">+ Neu</button></div>'+list+'</aside><section class="ldWelcome"><h2>Etikett gestalten</h2><p>Vorlage auswaehlen oder ein neues Etikett anlegen.</p><button class="save" onclick="createLabel()">Neue Vorlage</button></section></div>';
 const d=labelDots(l), maxW=780,maxH=590,scale=Math.min(maxW/d.w,maxH/d.h,1.35);
 const canvas='<div class="ldCanvasWrap"><div class="ldRulers"><span>'+d.w+' x '+d.h+' dots</span><b>'+l.widthMm+' x '+l.heightMm+' mm bei '+l.dpi+' dpi</b></div><div id="labelCanvas" class="ldCanvas" style="width:'+Math.round(d.w*scale)+'px;height:'+Math.round(d.h*scale)+'px" data-scale="'+scale+'">'+l.objects.map(o=>renderObject(o,scale)).join('')+'</div></div>';
 return '<h1 class="sectionTitle">Etikettendesigner ZPL2</h1><div class="ldTopActions"><button onclick="createLabel()">+ Neu</button><button onclick="duplicateLabel()">Duplizieren</button><button class="saveInline" onclick="saveLabelTemplate()">Speichern</button><button class="danger" onclick="deleteLabelTemplate()">Loeschen</button><span>'+esc(state.labelMessage||'')+'</span><div class="ldUnitSwitch" aria-label="Maßeinheit"><button class="'+(state.labelUnit==='dots'?'active':'')+'" onclick="setLabelUnit(\'dots\')">Dots</button><button class="'+(state.labelUnit==='mm'?'active':'')+'" onclick="setLabelUnit(\'mm\')">mm</button></div></div><div class="ldShell"><aside class="ldTemplates"><div class="ldListHead"><b>Vorlagen</b><button onclick="loadLabels()">Neu laden</button></div>'+list+'</aside><section class="ldWork"><div class="ldBasics">'+numInput('ld_number','Nummer (0 = automatisch)',l.number||0,0,1)+'<label>Name<input id="ld_name" value="'+escAttr(l.name)+'"></label><label>Typ<select id="ld_type"><option value="standard" '+(l.labelType==='standard'?'selected':'')+'>Standard</option><option value="rfid" '+(l.labelType==='rfid'?'selected':'')+'>RFID</option></select></label>'+numInput('ld_width','Breite mm',l.widthMm,5,.1)+numInput('ld_height','Hoehe mm',l.heightMm,5,.1)+'<label>DPI<select id="ld_dpi"><option '+(l.dpi==203?'selected':'')+'>203</option><option '+(l.dpi==300?'selected':'')+'>300</option><option '+(l.dpi==600?'selected':'')+'>600</option></select></label>'+numInput('ld_darkness','Drucktemperatur (0-30)',l.darkness??12,0,1)+'<label>Geschwindigkeit<select id="ld_speed">'+[[2,'5,0 cm/s'],[3,'7,6 cm/s'],[4,'10,1 cm/s'],[5,'12,7 cm/s'],[6,'15,2 cm/s']].map(v=>'<option value="'+v[0]+'" '+(Number(l.speed||3)===v[0]?'selected':'')+'>'+v[1]+' ('+v[0]+' ips)</option>').join('')+'</select></label></div><div class="ldToolbar"><button onclick="addObject(\'text\')" title="Freitext">T Text</button><button onclick="addObject(\'field\')" title="Artikeldaten">[] Datenfeld</button><button onclick="addObject(\'barcode\')" title="EAN oder Code 128">||| EAN</button><button onclick="addObject(\'ingredients\')" title="Zutaten mit Allergenkennzeichnung">Zutaten</button><button onclick="addObject(\'nutrition\')" title="Nährwerttabelle">Nährwerte</button><button onclick="addObject(\'image\')" title="Bild einfuegen">Bild</button><button onclick="addObject(\'line\')" title="Linie">- Linie</button><span class="ldToolsSep"></span><button onclick="alignLabelObjects(\'left\')">Links</button><button onclick="alignLabelObjects(\'center\')">Mitte</button><button onclick="alignLabelObjects(\'right\')">Rechts</button><button onclick="alignLabelObjects(\'top\')">Oben</button><button onclick="alignLabelObjects(\'middle\')">Zentrum</button><button onclick="alignLabelObjects(\'bottom\')">Unten</button><span class="ldToolsSep"></span><button onclick="addObject(\'box\')" title="Rahmen">□ Rahmen</button><input id="labelImageUpload" hidden type="file" accept="image/png,image/jpeg,image/webp"></div><div class="ldEditor">'+canvas+'<aside class="ldProperties">'+objectProperties()+'</aside></div>'+(l.labelType==='rfid'?'<div class="ldRfid"><label>RFID-ZPL / Schreibbefehl<textarea id="ld_rfid">'+esc(l.rfidZpl||'$WRITE_RFID$')+'</textarea></label></div>':'')+'<section class="ldTestPrint"><b>Testdruck mit Artikeldaten</b><select id="ld_test_article"><option value="">Artikel waehlen</option>'+state.articles.map(a=>'<option value="'+escAttr(a.nummer)+'">#'+esc(a.nummer)+' - '+esc(a.name)+'</option>').join('')+'</select><label>Testgewicht (kg)<input id="ld_test_weight" type="number" min="0.001" step="0.001" value="0.500"></label><button onclick="testPrintLabel()">Testetikett drucken</button></section><details class="ldZpl" open><summary>ZPL2-Ausgabe</summary><div><button onclick="refreshLabelZpl()">ZPL aktualisieren</button><button onclick="copyLabelZpl()">Kopieren</button></div><textarea id="ld_zpl" spellcheck="false">'+esc(state.labelZpl||generateZplSync(l))+'</textarea></details></section></div>';
}
render=function(){if(state.tab==='labels'){layout(labelsDesigner());bindLabelDesigner();return}oldRender()};
function syncBasics(){
 const l=state.label;if(!l)return;
 l.number=Number(document.getElementById('ld_number')?.value||0);l.name=document.getElementById('ld_name')?.value||l.name;l.labelType=document.getElementById('ld_type')?.value||l.labelType;
 l.widthMm=Number(document.getElementById('ld_width')?.value||l.widthMm);l.heightMm=Number(document.getElementById('ld_height')?.value||l.heightMm);
 l.dpi=Number(document.getElementById('ld_dpi')?.value||l.dpi);l.darkness=Number(document.getElementById('ld_darkness')?.value||l.darkness);l.speed=Number(document.getElementById('ld_speed')?.value||l.speed);
 if(document.getElementById('ld_rfid'))l.rfidZpl=document.getElementById('ld_rfid').value;
}
function bindLabelDesigner(){
 if(state.tab!=='labels'||!state.label)return;
 ['ld_width','ld_height','ld_dpi','ld_type'].forEach(id=>{const e=document.getElementById(id);if(e)e.onchange=()=>{syncBasics();state.labelZpl=generateZplSync(state.label);render()}});
 const upload=document.getElementById('labelImageUpload');if(upload)upload.onchange=async()=>{const f=upload.files?.[0];if(!f)return;const dataUrl=await fileDataUrl(f);const o={id:objectId(),type:'image',x:20,y:20,w:180,h:100,rotation:0,dataUrl,name:f.name};state.label.objects.push(o);state.labelSelected=o.id;render()};
 document.querySelectorAll('.ldObject').forEach(el=>{
   el.onpointerdown=e=>{if(e.target.closest('.ldHandle'))startObjectResize(e,el);else startObjectDrag(e,el)};
   el.onclick=e=>{e.stopPropagation();setObjectSelection(el.dataset.oid,e.ctrlKey||e.shiftKey);render()};
 });
 const c=document.getElementById('labelCanvas');if(c)c.onclick=e=>{if(e.target===c){state.labelSelected=null;state.labelSelectedIds=[];render()}};
}
function startObjectDrag(e,el){
 e.preventDefault();e.stopPropagation();const o=state.label.objects.find(x=>x.id===el.dataset.oid);if(!o)return;
 setObjectSelection(o.id,e.ctrlKey||e.shiftKey);const scale=Number(document.getElementById('labelCanvas').dataset.scale||1),sx=e.clientX,sy=e.clientY,ox=o.x,oy=o.y;
 el.setPointerCapture(e.pointerId);
 el.onpointermove=ev=>{o.x=Math.max(0,Math.round(ox+(ev.clientX-sx)/scale));o.y=Math.max(0,Math.round(oy+(ev.clientY-sy)/scale));el.style.left=(o.x*scale)+'px';el.style.top=(o.y*scale)+'px'};
 el.onpointerup=()=>{el.onpointermove=null;state.labelZpl=generateZplSync(state.label);render()};
}
function alignLabelObjects(mode){const a=selectedObjects();if(a.length<2){state.labelMessage='Mindestens zwei Objekte mit Strg oder Umschalt auswaehlen.';render();return}const l=Math.min(...a.map(o=>o.x)),r=Math.max(...a.map(o=>o.x+o.w)),t=Math.min(...a.map(o=>o.y)),b=Math.max(...a.map(o=>o.y+o.h));a.forEach(o=>{if(mode==='left')o.x=l;if(mode==='right')o.x=r-o.w;if(mode==='center')o.x=Math.round((l+r-o.w)/2);if(mode==='top')o.y=t;if(mode==='bottom')o.y=b-o.h;if(mode==='middle')o.y=Math.round((t+b-o.h)/2)});state.labelZpl=generateZplSync(state.label);render()}
function startObjectResize(e,el){e.preventDefault();e.stopPropagation();const o=state.label.objects.find(x=>x.id===el.dataset.oid);if(!o)return;state.labelSelected=o.id;const c=document.getElementById('labelCanvas'),scale=Number(c.dataset.scale||1),sx=e.clientX,sy=e.clientY,ow=o.w,oh=o.h,d=labelDots(state.label);el.setPointerCapture(e.pointerId);el.onpointermove=ev=>{o.w=Math.max(8,Math.min(d.w-o.x,Math.round(ow+(ev.clientX-sx)/scale)));o.h=Math.max(8,Math.min(d.h-o.y,Math.round(oh+(ev.clientY-sy)/scale)));el.style.width=(o.w*scale)+'px';el.style.height=(o.h*scale)+'px'};el.onpointerup=()=>{el.onpointermove=null;state.labelZpl=generateZplSync(state.label);render()}}
function applyLabelObject(){
 const o=selectedObj();if(!o)return;
 ['x','y','w','h'].forEach(k=>{const e=document.getElementById('op_'+k);if(e)o[k]=fromUnit(e.value)});
 ['rotation','moduleWidth','thickness','maxLines'].forEach(k=>{const e=document.getElementById('op_'+k);if(e)o[k]=Number(e.value||0)});
 ['fontSize','fontWidth','lineSpacing'].forEach(k=>{const e=document.getElementById('op_'+k);if(e)o[k]=state.labelUnit==='mm'?fromUnit(e.value):Number(e.value||0)});
 ['value','variable','prefix','suffix','barcodeType','align','font','eanMode','eanPattern','allergenStyle','displayUnit'].forEach(k=>{const e=document.getElementById('op_'+k);if(e)o[k]=e.value});
 const allergens=document.getElementById('op_allergens');if(allergens)o.allergens=allergens.value.split(',').map(x=>x.trim().toLocaleLowerCase('de-DE')).filter(Boolean);
 const flags={humanReadable:'op_humanReadable',bold:'op_bold',italic:'op_italic',nutritionBorder:'op_nutritionBorder',fitWidth:'op_fitWidth'};Object.entries(flags).forEach(([k,id])=>{const e=document.getElementById(id);if(e)o[k]=e.checked});
 if(o.type==='barcode'){if(o.eanMode==='price')o.eanPattern='22NNNNNPPPPPQ';if(o.eanMode==='weight')o.eanPattern='21NNNNNGGGGGQ'}
 state.labelZpl=generateZplSync(state.label);render();
}
function cloneLabelObject(){const o=selectedObj();if(!o)return;const n=JSON.parse(JSON.stringify(o));n.id=objectId();n.x+=12;n.y+=12;state.label.objects.push(n);state.labelSelected=n.id;state.labelSelectedIds=[n.id];render()}
function removeLabelObject(){state.label.objects=state.label.objects.filter(o=>o.id!==state.labelSelected);state.labelSelected=null;render()}
function zplValue(o){
 if(o.type==='field')return zplLiteral(o.prefix)+'$'+effectiveFieldVariable(o)+'$'+zplLiteral(o.suffix);
 if(o.type==='barcode'&&o.barcodeType==='ean13'&&o.eanMode&&o.eanMode!=='direct')return '$EAN_'+String(o.eanPattern||'22NNNNNPPPPPQ').toUpperCase()+'$';
 if(o.type==='barcode')return '$'+(o.variable||'ean')+'$';
 return String(o.value||'').replace(/\^/g,' ');
}
function textZpl(o,x,y,w,rot){
 const font=String(o.font||'0').substring(0,1),h=Math.round(o.fontSize||30),fw=Math.round(o.fontWidth||h),lines=Math.max(1,Math.round(o.maxLines||1)),gap=Math.round(o.lineSpacing||0);
 const cmd='^FO'+x+','+y+'^A'+font+rot+','+h+','+fw+'^FB'+w+','+lines+','+gap+','+(o.align||'L')+',0^FD'+zplValue(o)+'^FS';
 return o.bold?cmd+'\n^FO'+(x+1)+','+y+'^A'+font+rot+','+h+','+fw+'^FB'+w+','+lines+','+gap+','+(o.align||'L')+',0^FD'+zplValue(o)+'^FS':cmd;
}
function generateZplSync(l){
 const d=labelDots(l);let z='^XA\n^CI28\n^PW'+d.w+'\n^LL'+d.h+'\n^PR'+(l.speed||3)+'\n~SD'+(l.darkness||12)+'\n';
 for(const o of l.objects||[]){
  const x=Math.round(o.x||0),y=Math.round(o.y||0),w=Math.round(o.w||10),h=Math.round(o.h||10),rot=['N','R','I','B'][Math.round((o.rotation||0)/90)%4]||'N';
  if(o.type==='text'||o.type==='field')z+=textZpl(o,x,y,w,rot)+'\n';
  if(o.type==='ingredients')z+='^FXFW_INGREDIENTS|'+x+'|'+y+'|'+w+'|'+h+'|'+Math.round(o.fontSize||24)+'|'+Math.round(o.fontWidth||o.fontSize||24)+'|'+Math.round(o.lineSpacing||2)+'|'+(o.allergenStyle||'bold')+'|'+(o.allergens||defaultAllergens).join(',')+'|'+String(o.prefix||'Zutaten: ').replace(/[|\r\n]/g,' ')+'\n';
  if(o.type==='nutrition')z+='^FXFW_NUTRITION|'+x+'|'+y+'|'+w+'|'+h+'|'+Math.round(o.fontSize||22)+'|'+Math.round(o.fontWidth||o.fontSize||22)+'|'+Math.round(o.lineSpacing||2)+'|'+(o.nutritionBorder?'1':'0')+'|'+String(o.value||'Nährwerte je 100 g').replace(/[|\r\n]/g,' ')+'\n';
  if(o.type==='barcode'){const hr=o.humanReadable?'Y':'N';z+='^FO'+x+','+y+'^BY'+barcodeModuleWidth(o)+',3,'+h+(o.barcodeType==='code128'?'^BC'+rot+','+h+','+hr+',N,N':'^BE'+rot+','+h+','+hr+',N')+'^FD'+zplValue(o)+'^FS\n'}
  if(o.type==='line')z+='^FO'+x+','+y+'^GB'+w+','+Math.max(1,o.thickness||2)+','+Math.max(1,o.thickness||2)+'^FS\n';
  if(o.type==='box')z+='^FO'+x+','+y+'^GB'+w+','+h+','+Math.max(1,o.thickness||2)+'^FS\n';
  if(o.type==='image')z+='^FX IMAGE '+(o.name||'Bild')+' wird beim Speichern als GFA erzeugt\n';
 }
 if(l.labelType==='rfid'&&l.rfidZpl)z+=l.rfidZpl.trim()+'\n';
 return z+'^PQ1,0,1,Y\n^XZ';
}
async function imageGfa(o){
 const img=new Image();img.src=o.dataUrl;await img.decode();const w=Math.max(1,Math.round(o.w)),h=Math.max(1,Math.round(o.h)),row=Math.ceil(w/8),c=document.createElement('canvas');c.width=w;c.height=h;const x=c.getContext('2d',{willReadFrequently:true});x.fillStyle='#fff';x.fillRect(0,0,w,h);x.drawImage(img,0,0,w,h);const p=x.getImageData(0,0,w,h).data;let hex='';
 for(let yy=0;yy<h;yy++)for(let b=0;b<row;b++){let n=0;for(let bit=0;bit<8;bit++){const xx=b*8+bit;if(xx<w){const i=(yy*w+xx)*4,lum=p[i]*.299+p[i+1]*.587+p[i+2]*.114;if(p[i+3]>20&&lum<150)n|=(128>>bit)}}hex+=n.toString(16).padStart(2,'0').toUpperCase()}
 const total=row*h;return '^FO'+Math.round(o.x||0)+','+Math.round(o.y||0)+'^GFA,'+total+','+total+','+row+','+hex+'^FS';
}
async function generateZpl(l){
 let z=generateZplSync(l);for(const o of l.objects||[])if(o.type==='image'&&o.dataUrl){const marker='^FX IMAGE '+(o.name||'Bild')+' wird beim Speichern als GFA erzeugt';z=z.replace(marker,await imageGfa(o))}return z;
}
async function refreshLabelZpl(){syncBasics();state.labelZpl=await generateZpl(state.label);const e=document.getElementById('ld_zpl');if(e)e.value=state.labelZpl}
async function saveLabelTemplate(reloadList=true){
 syncBasics();state.labelZpl=await generateZpl(state.label);state.label.generatedZpl=state.labelZpl;
 try{
  const j=await readJsonResponse(await fetch(apiUrl('/api/admin/label/save'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(state.label)}));
  if(j.ok===false)throw Error(j.message||'Vorlage konnte nicht gespeichert werden.');
  state.labelMessage=j.message||'Vorlage gespeichert.';
  if(j.id)state.label.id=j.id;if(j.number)state.label.number=Number(j.number);
  if(reloadList)loadLabels();
  return true;
 }catch(e){state.labelMessage='Speichern fehlgeschlagen: '+e.message;render();return false}
}
async function testPrintLabel(){
 const plu=document.getElementById('ld_test_article')?.value||'',weight=Number(document.getElementById('ld_test_weight')?.value||.5);
 if(!plu){state.labelMessage='Bitte zuerst einen Testartikel auswählen.';render();return}
 state.labelMessage='Testetikett wird vorbereitet und an den Etikettendrucker gesendet...';
 if(!await saveLabelTemplate(false))return;
 try{
  if(!state.label.number)throw Error('Die Etikettenvorlage hat keine gültige Nummer.');
  const u='/api/labeling/print?plu='+encodeURIComponent(plu)+'&weight='+encodeURIComponent(weight)+'&tara=0&qty=1&mhd=&template='+encodeURIComponent(state.label.number);
  const j=await readJsonResponse(await fetch(apiUrl(u),{method:'POST',cache:'no-store'}));
  if(j.ok===false)throw Error(j.message||'Testdruck fehlgeschlagen.');
  state.labelMessage=(j.message||'Testetikett wurde gedruckt.')+(j.printer?' Drucker: '+j.printer:'');
 }catch(e){state.labelMessage='Testdruck fehlgeschlagen: '+e.message}
 render();
}async function copyLabelZpl(){await refreshLabelZpl();try{await navigator.clipboard.writeText(state.labelZpl);state.labelMessage='ZPL wurde kopiert.'}catch(e){state.labelMessage='Kopieren nicht moeglich.'}render()}
function fileDataUrl(f){return new Promise((ok,no)=>{const r=new FileReader();r.onload=()=>ok(r.result);r.onerror=no;r.readAsDataURL(f)})}
Object.assign(window,{openLabel,createLabel,duplicateLabel,deleteLabelTemplate,loadLabels,addObject,applyLabelObject,cloneLabelObject,removeLabelObject,saveLabelTemplate,refreshLabelZpl,copyLabelZpl,setLabelUnit,alignLabelObjects,testPrintLabel});
if(state.tab==='labels')render();
})();