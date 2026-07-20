const state = {
  config: null,
  labelingConfig: {
    eanLabel: true,
    rfidLabel: true,
    rfidEncode: true,
    checkEANMod10: true,
    rfidTagLength: 24,
    start: 'EAN_LABEL'
  },

  groups: [],
  groupSort: 'name',
  products: [],
  productSort: 'name',
  taras: [],
  labelTemplates: [],
  activeLabel: null,
  selectedGroup: null,
  selectedProduct: null,

  mode: 'ean',
  search: '',
  searchTimer: null,
  lastScanText: '',
  showPluPad: false,
  searchOpen: false,

  weight: 0,
  manualWeightOpen: false,
  manualWeightText: '',
  stable: false,
  tara: 0,
  scaleRaw: '',
  scaleLastAt: '',
  qty: 1,
  mhd: '',
  template: 0,
  printNormalLabel: false,

  protocolRecent: [],
  protocolAll: [],
  protocolOpen: false,
  recentCollapsed: false,
  previewCollapsed: false,

  rfidSource: 'reader',
  autoMode: true,
  afterSaveMode: 'next',
  waitingForRfid: false,
  rfidAction: 'encode',
  rfidTag: '',
  rfidMessage: '',
  rfidDuplicateTag: '',
  rfidDuplicateId: 0,
  rfidDuplicateStatus: null,
  rfidCheckResult: null,
  encodeCounter: Number(sessionStorage.getItem('labelingEncodeCounter') || 0),

  modal: null,
  message: 'Suchfeld bereit',
  debug: []
};

function $(id){ return document.getElementById(id); }

function esc(s){
  return String(s ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#039;'
  }[c]));
}

function money(v){
  return Number(v || 0).toLocaleString('de-DE', { style:'currency', currency:'EUR' });
}

function num(v, digits){
  return Number(v || 0).toLocaleString('de-DE', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits
  });
}

function firstValue(){
  for(const v of arguments){
    if(v !== undefined && v !== null && v !== '') return v;
  }
  return 0;
}

function protocolWeight(r){ return parseNum(firstValue(r.weight, r.gewicht)); }
function protocolTara(r){ return parseNum(firstValue(r.tara)); }
function protocolGross(r){ return protocolWeight(r) + protocolTara(r); }

const BLANK_IMAGE = '/labeling/assets/blanko.svg';

function parseNum(v){
  const n = Number(v || 0);
  return isNaN(n) ? 0 : n;
}

function debugLog(label, data){
  const entry = {
    time: new Date().toISOString(),
    label,
    data: data === undefined ? null : data
  };

  state.debug.unshift(entry);
  if(state.debug.length > 100)
    state.debug.length = 100;

  try{
    console.log('[LABELING]', label, data || '');
  }catch(e){}
}

async function fetchJsonDebug(url, label, timeoutMs = 8000){
  debugLog(label + ' fetch', { url, timeoutMs });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let response;
  let text;

  try{
    response = await fetch(url, { signal: controller.signal, cache:'no-store' });
    text = await response.text();
  }catch(e){
    debugLog(label + ' fetch-error', { message: e.message, name: e.name });
    if(e.name === 'AbortError')
      return { ok:false, message: label + ': API antwortet nicht innerhalb von ' + Math.round(timeoutMs / 1000) + ' Sekunden.' };
    return { ok:false, message: label + ': API nicht erreichbar: ' + e.message };
  }finally{
    clearTimeout(timer);
  }

  debugLog(label + ' response', {
    url,
    status: response.status,
    ok: response.ok,
    text: text.substring(0, 500)
  });

  let json = {};
  try{
    json = text ? JSON.parse(text) : {};
  }catch(e){
    debugLog(label + ' json-error', { message: e.message, text: text.substring(0, 500) });
    return { ok:false, message: label + ': Antwort ist kein gueltiges JSON: ' + text.substring(0,120) };
  }

  debugLog(label + ' json', json);
  return json;
}

function messageKind(){
  const m = String(state.message || '').toLowerCase();
  if(!m) return 'info';

  if(m.includes('fehler') || m.includes('nicht') || m.includes('kein ') ||
     m.includes('keine ') || m.includes('ungültig') || m.includes('ungueltig') ||
     m.includes('konnte') || m.includes('api nicht erreichbar') ||
     m.includes('bereits vorhanden'))
    return 'error';

  if(m.includes('gespeichert') || m.includes('gefunden') || m.includes('übernommen') ||
     m.includes('gedruckt') || m.includes('bereit') || m.includes('ausgewählt'))
    return 'success';

  return 'info';
}
function productIsKg(p){
  return !!p && String(p.unit || '').toLowerCase() === 'kg';
}

function unitIsKg(){
  return productIsKg(state.selectedProduct);
}

function clearPieceWeight(){
  state.weight = 0;
  state.tara = 0;
  state.stable = false;
  state.scaleRaw = '';
  state.scaleLastAt = '';
}

function netWeight(){
  return Math.max(0, parseNum(state.weight) - parseNum(state.tara));
}

function taraButtonsHtml(){
  if(!state.taras || !state.taras.length) return '';
  return `<div class="taraButtons">${state.taras.map(t => `<button type="button" data-action="tara:${Number(t.value || 0)}">${esc(t.name || t.bezeichnung || ('Tara ' + t.nummer))}<span>${num(t.value || 0, 3)} kg</span></button>`).join('')}</div>`;
}


function qtyText(){
  if(!state.selectedProduct) return '';
  return state.qty + (state.qty === 1 ? ' Etikett' : ' Etiketten');
}

function scaleStatusText(){
  if(!unitIsKg()) return 'Stueckartikel';
  if(!state.scaleLastAt) return 'Noch nicht gewogen';
  return state.stable ? 'Stabil' : 'Nicht stabil';
}

function scaleStatusClass(){
  if(!unitIsKg()) return 'neutral';
  if(!state.scaleLastAt) return 'idle';
  return state.stable ? 'ok' : 'warn';
}

function totalPrice(){
  const p = state.selectedProduct;
  if(!p) return 0;

  if(parseNum(p.eanPrice) > 0)
    return parseNum(p.eanPrice);

  if(unitIsKg())
    return netWeight() * parseNum(p.price);

  return parseNum(p.price);
}

function firstEnabledMode(){
  if(state.labelingConfig.eanLabel) return 'ean';
  if(state.labelingConfig.rfidLabel) return 'rfidprint';
  if(state.labelingConfig.rfidEncode) return 'rfidwrite';
  return 'ean';
}

function modeIsEnabled(mode){
  if(mode === 'ean') return !!state.labelingConfig.eanLabel;
  if(mode === 'rfidprint') return !!state.labelingConfig.rfidLabel;
  if(mode === 'rfidwrite') return !!state.labelingConfig.rfidEncode;
  return false;
}

function modeFromConfigStart(start){
  const s = String(start || '').toUpperCase();
  if(s === 'RFID_LABEL') return 'rfidprint';
  if(s === 'RFID_ENCODE') return 'rfidwrite';
  return 'ean';
}

async function boot(){
  await loadConfig();
  await loadLabelTemplates();
  await loadGroups();
  await loadTaras();
  await loadRecentProtocol();
  render();
}

async function loadConfig(){
  try{
    const r = await fetch('/api/config');
    const cfg = await r.json();

    state.config = cfg;

    if(cfg.labeling){
      state.labelingConfig = {
        eanLabel: cfg.labeling.eanLabel !== false,
        rfidLabel: cfg.labeling.rfidLabel !== false,
        rfidEncode: cfg.labeling.rfidEncode !== false,
        checkEANMod10: cfg.labeling.checkEANMod10 !== false,
        rfidTagLength: Number(cfg.labeling.rfidTagLength || cfg.labeling.tagLength || cfg.labeling.TagLength || 24),
        start: cfg.labeling.start || 'EAN_LABEL'
      };

      const wantedMode = modeFromConfigStart(state.labelingConfig.start);
      state.mode = modeIsEnabled(wantedMode) ? wantedMode : firstEnabledMode();
    }
  }catch(e){
    state.config = {};
  }
}

async function loadLabelTemplates(){
  try{
    const r=await fetch('/api/admin/labels',{cache:'no-store'});
    const j=await r.json();
    state.labelTemplates=(Array.isArray(j)?j:[]).map((x,i)=>Object.assign({},x,{number:Number(x.number)>0?Number(x.number):i+1}));
  }catch(e){state.labelTemplates=[]}
}
async function loadActiveLabel(number){
  const n=Number(number||0);
  state.activeLabel=null;
  if(!n){render();return}
  const meta=state.labelTemplates.find(x=>Number(x.number)===n);
  if(!meta){state.message='Zugewiesene Etikettenvorlage '+n+' wurde nicht gefunden';render();return}
  try{
    const r=await fetch('/api/admin/label?id='+encodeURIComponent(meta.id),{cache:'no-store'});
    const j=await r.json();
    if(j.ok===false)throw new Error(j.message||'Vorlage nicht gefunden');
    state.activeLabel=j;
  }catch(e){state.message='Etikettenvorlage konnte nicht geladen werden: '+e.message}
  render();
}
const previewAllergens=['gluten','weizen','roggen','gerste','hafer','krebstiere','ei','eier','fisch','erdnuss','erdnüsse','soja','milch','laktose','schalenfrüchte','mandel','haselnuss','walnuss','cashew','pecannuss','paranuss','pistazie','macadamia','sellerie','sellere','senf','sesam','sulfite','lupine','weichtiere'];
function labelEanCheck(s){let n=0;for(let i=0;i<12;i++)n+=Number(s[i]||0)*(i%2?3:1);return String((10-n%10)%10)}
function labelPad(n,c){return String(Math.max(0,Math.round(n))).padStart(c,'0').slice(-c)}
function labelEan(pattern,p){let f=String(pattern||'22NNNNNPPPPPQ').toUpperCase(),base='';for(let i=0;i<f.length;i++){const ch=f[i];if(ch==='Q')continue;if('NPG'.includes(ch)){let j=i;while(f[j]===ch)j++;const c=j-i,v=ch==='N'?p.plu:ch==='P'?totalPrice()*100:netWeight()*1000;base+=labelPad(v,c);i=j-1}else if(/\d/.test(ch))base+=ch}base=base.slice(0,12).padEnd(12,'0');return base+labelEanCheck(base)}
function previewAllergenHtml(text,list,style){const a=(list||previewAllergens).map(x=>x.toLocaleLowerCase('de-DE'));return String(text||'').split(/(\p{L}+[\p{L}-]*)/u).map(part=>a.includes(part.toLocaleLowerCase('de-DE'))?'<strong class="'+(style==='underline'?'under':'')+'">'+esc(part)+'</strong>':esc(part)).join('')}
function previewValue(o,p){
 const values={preis100g:money((p.price||0)/10)+' / 100 g',fuellgewichtG:num((p.nenngewicht||0)*1000,0)+' g',artikel:p.name||'',artikel2:p.name2||'',plu:String(p.plu||''),ean:p.ean||'4012345678901',gewicht:num(netWeight(),3)+' kg',tara:num(state.tara,3)+' kg',netto:num(netWeight(),3)+' kg',fuellgewicht:num(p.nenngewicht||0,3)+' kg',preisKg:money(p.price)+' / '+(p.unit||'kg'),preis:money(totalPrice()),mhd:state.mhd?new Date(state.mhd+'T00:00:00').toLocaleDateString('de-DE'):'-',einheit:p.unit||'',zutaten:p.ingredients||'',temperatur:p.temperature||''};
 if(o.type==='field'){const v=o.displayUnit==='100g'&&o.variable==='preisKg'?'preis100g':o.displayUnit==='100g'&&o.variable==='fuellgewicht'?'fuellgewichtG':o.variable;return (o.prefix||'')+(values[v]||'')+(o.suffix||'')}
 if(o.type==='barcode')return o.eanMode&&o.eanMode!=='direct'?labelEan(o.eanPattern,p):(values[o.variable||'ean']||'');
 return o.value||'Text';
}
function nutritionPreview(o,p){
 const n=p.nutrition||{},rows=[['Energie',num(n.kjoule,0)+' kJ / '+num(n.kcal,0)+' kcal'],['Fett',num(n.fat,2)+' g'],['davon gesättigt',num(n.saturates,2)+' g'],['Kohlenhydrate',num(n.carbs,2)+' g'],['davon Zucker',num(n.sugar,2)+' g'],['Eiweiß',num(n.protein,2)+' g'],['Salz',num(n.salt,2)+' g']];
 return '<div class="lpNutrition"><b>'+esc(o.value||'Nährwerte je 100 g')+'</b>'+rows.map(r=>'<span>'+esc(r[0])+'<strong>'+esc(r[1])+'</strong></span>').join('')+'</div>';
}
function realLabelPreview(p){
 const l=state.activeLabel;
 if(!l)return '<div class="realLabelEmpty"><b>Keine Etikettenvorlage zugewiesen</b><span>Im Admin beim Artikel eine Vorlage auswählen.</span></div>';
 const dpm=Number(l.dpi||300)/25.4,w=Math.round(Number(l.widthMm||44)*dpm),h=Math.round(Number(l.heightMm||19)*dpm),scale=Math.min(420/w,300/h,1.4);
 const objs=(l.objects||[]).map(o=>{const st='left:'+(o.x*scale)+'px;top:'+(o.y*scale)+'px;width:'+(o.w*scale)+'px;height:'+(o.h*scale)+'px;transform:rotate('+(o.rotation||0)+'deg)';
  if(o.type==='text'||o.type==='field')return '<div class="lpObj lpText" style="'+st+';font-size:'+Math.max(8,(o.fontSize||30)*scale)+'px;text-align:'+(o.align==='C'?'center':o.align==='R'?'right':'left')+';font-weight:'+(o.bold?'900':'500')+';font-style:'+(o.italic?'italic':'normal')+';white-space:'+(Number(o.maxLines||1)>1?'normal':'nowrap')+'">'+esc(previewValue(o,p))+'</div>';
  if(o.type==='ingredients')return '<div class="lpObj lpIngredients" style="'+st+';font-size:'+Math.max(8,(o.fontSize||24)*scale)+'px">'+esc(o.prefix||'Zutaten: ')+previewAllergenHtml(p.ingredients||'Keine Zutaten hinterlegt',o.allergens,o.allergenStyle)+'</div>';
  if(o.type==='nutrition')return '<div class="lpObj" style="'+st+'">'+nutritionPreview(o,p)+'</div>';
  if(o.type==='barcode')return '<div class="lpObj lpBarcode" style="'+st+'"><i></i><span>'+(o.humanReadable?esc(previewValue(o,p)):'')+'</span></div>';
  if(o.type==='line')return '<div class="lpObj lpLine" style="'+st+';height:'+Math.max(1,(o.thickness||2)*scale)+'px"></div>';
  if(o.type==='box')return '<div class="lpObj lpBox" style="'+st+';border-width:'+Math.max(1,(o.thickness||2)*scale)+'px"></div>';
  if(o.type==='image')return '<img class="lpObj lpImage" style="'+st+'" src="'+esc(o.dataUrl||'')+'" alt="">';return ''}).join('');
 return '<div class="realLabelStage"><div class="realLabelPaper" style="width:'+Math.round(w*scale)+'px;height:'+Math.round(h*scale)+'px">'+objs+'</div></div>';
}
async function loadProductFoodDetails(p){
 if(!p?.id)return;
 try{const r=await fetch('/api/admin/article?id='+encodeURIComponent(p.id),{cache:'no-store'}),j=await r.json(),a=j.article||{};p.ingredients=a.zutatentext||p.ingredients||'';p.nutrition={kcal:Number(a.rz_kcal||0),kjoule:Number(a.rz_kjoule||0),protein:Number(a.rz_eiweiss||0),carbs:Number(a.rz_kohlenhydrate||0),sugar:Number(a.rz_zucker||0),fat:Number(a.rz_fett||0),saturates:Number(a.rz_fettges||0),salt:Number(a.rz_salz||0),fiber:Number(a.rz_ballast||0)};render()}catch(e){}
}
async function loadGroups(){
  try{
    const r = await fetch('/api/labeling/groups', {cache:'no-store'});
    state.groups = await r.json();
    sortLabelingGroups();

    if(state.groups.length){
      state.selectedGroup = Number(state.groups[0].wg ?? state.groups[0].id);
      await loadProducts(state.selectedGroup);
    }
  }catch(e){
    state.groups = [];
    state.products = [];
    state.message = 'Warengruppen konnten nicht geladen werden';
  }
}

function sortLabelingGroups(){state.groups.sort((a,b)=>{const ai=Number(a.wg??a.id??0),bi=Number(b.wg??b.id??0);return state.groupSort==='number'?ai-bi:String(a.name||'').localeCompare(String(b.name||''),'de',{sensitivity:'base'})})}
function setGroupSort(mode){state.groupSort=mode==='number'?'number':'name';sortLabelingGroups();render()}

async function loadProducts(wg){
  try{
    const r = await fetch('/api/labeling/products?wg=' + encodeURIComponent(wg), {cache:'no-store'});
    const arr = await r.json();
    state.products = arr.map(mapProduct);
    sortLabelingProducts();
  }catch(e){
    state.products = [];
    state.message = 'Artikel konnten nicht geladen werden';
  }
}

function sortLabelingProducts(){state.products.sort((a,b)=>state.productSort==='number'?Number(a.plu)-Number(b.plu):String(a.name||'').localeCompare(String(b.name||''),'de',{sensitivity:'base'}))}
function setProductSort(mode){state.productSort=mode==='number'?'number':'name';sortLabelingProducts();render()}

function mapProduct(p){
  return {
    id: p.id,
    plu: Number(p.plu ?? p.nummer ?? p.number ?? 0),
    name: p.name || p.bezeichnung || '',
    name2: p.name2 || '',
    unit: p.unit || p.me || 'Stck',
    group: Number(p.wg || p.group || 0),
    price: parseNum(p.price || p.ep || p.preis || 0),
    eanPrice: parseNum(p.eanprice || p.eanPrice || p.totalPrice || 0),
    nenngewicht: parseNum(p.nenngewicht || p.nennGewicht || 0),
    taranr: Number(p.taranr || p.taraNr || 0),
    mhd: p.mhd || '',
    mhdDays: Number(p.mhdDays || 0),
    labelNumber: Number(p.labelNumber || p.standardEtikett || 0),
    ean: p.ean || '',
    ingredients: p.ingredients || '',
    source: p.source || ''
  };
}

function defaultMhdForProduct(p, fallback){
  if(!p) return fallback || '';
  if(p.mhd) return p.mhd;
  const days = Number(p.mhdDays || 0);
  if(days > 0){
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() + days);
    return d.toISOString().slice(0, 10);
  }
  return fallback || '';
}

async function selectProductByPlu(pluText){
  const plu = Number(String(pluText || '').trim());

  if(!plu || isNaN(plu)){
    state.message = 'Keine gültige PLU eingegeben';
    render();
    return;
  }

  let p = state.products.find(x => Number(x.plu) === plu);
  if(p){
    state.searchOpen = false;
    state.search = '';
    selectProduct(p);
    return;
  }

  try{
    const r = await fetch('/api/labeling/search?q=' + encodeURIComponent(String(plu)), {cache:'no-store'});
    const arr = await r.json();
    const list = arr.map(mapProduct);
    p = list.find(x => Number(x.plu) === plu);

    if(p){
      state.products = list.length ? list : state.products;
      state.searchOpen = false;
      state.search = '';
      selectProduct(p);
      return;
    }

    state.products = list;
    state.message = 'PLU ' + plu + ' nicht gefunden';
    render();
  }catch(e){
    state.message = 'PLU-Suche/API nicht erreichbar';
    render();
  }
}

async function searchProducts(qOverride){
  const q = (qOverride !== undefined ? qOverride : state.search).trim();

  try{
    if(!q){
      await loadProducts(state.selectedGroup);
      render();
      return;
    }

    const r = await fetch('/api/labeling/search?q=' + encodeURIComponent(q), {cache:'no-store'});
    const arr = await r.json();
    state.products = arr.map(mapProduct);
    render();
  }catch(e){
    state.message = 'Suche/API nicht erreichbar';
    render();
  }
}

async function loadTaras(){
  try{
    const r = await fetch('/api/labeling/taras', {cache:'no-store'});
    state.taras = await r.json();
  }catch(e){
    state.taras = [];
  }
}

function setTaraByNr(taraNr){
  const t = state.taras.find(x => Number(x.nummer) === Number(taraNr));
  state.tara = t ? parseNum(t.value) : 0;
}

function setTaraValue(v){
  state.tara = Math.max(0, parseNum(v));
  state.message = state.tara > 0 ? 'Tara uebernommen: ' + num(state.tara, 3) + ' kg' : 'Tara geloescht';
  render();
}


async function loadRecentProtocol(){
  try{
    const r = await fetch('/api/labeling/protocol?limit=5');
    state.protocolRecent = await r.json();
  }catch(e){
    state.protocolRecent = [];
  }
}

async function openFullProtocol(){
  try{
    const r = await fetch('/api/labeling/protocol');
    state.protocolAll = await r.json();
    state.protocolOpen = true;
  }catch(e){
    state.message = 'Protokoll konnte nicht geladen werden';
  }
  render();
}

function selectProduct(p){
  state.selectedProduct = p;
  state.searchOpen = false;
  state.message = p ? (p.name + ' ausgewählt') : 'Suchfeld bereit';

  if(p){
    if(productIsKg(p)){
      if(parseNum(p.nenngewicht) > 0 && parseNum(state.weight) <= 0)
        state.weight = parseNum(p.nenngewicht);
      if(p.taranr)
        setTaraByNr(p.taranr);
      else
        state.tara = 0;
    }else{
      clearPieceWeight();
    }
    state.template = Number(p.labelNumber || 0);
    loadActiveLabel(state.template);
    loadProductFoodDetails(p);

    if(String(p.unit || '').toLowerCase() === 'kg' && state.config?.scale?.active)
      setTimeout(() => readWeight(false), 120);

    state.mhd = defaultMhdForProduct(p, '');
  }

  if(state.mode === 'rfidwrite' && state.autoMode)
    startRfidWait('next');
  else
    render();
}

function render(){
  const app = $('app');
  if(!app) return;

  app.innerHTML = `
    <div class="shell">
      ${headerHtml()}
      <main class="main">
        ${leftHtml()}
        ${centerHtml()}
        ${rightHtml()}
      </main>
      ${bottomHtml()}
      ${searchPopupHtml()}
      ${rfidPopupHtml()}
      ${manualWeightPopupHtml()}
      ${state.protocolOpen ? protocolModalHtml() : ''}
      ${state.modal ? modalHtml() : ''}

      <input id="rfidInput" autocomplete="off" inputmode="none"
        style="position:fixed;left:-1000px;top:-1000px;width:1px;height:1px;opacity:0;border:0;">
    </div>
  `;
  bind();
}

function headerHtml(){
  const c = state.config || {};

  return `
    <header class="top">
      <div>
        <div class="title">FOODWARE <span>12</span></div>
        <div class="sub">Labeling · Codierung · Waage · Etiketten</div>
      </div>

      <div class="modes">
        ${state.labelingConfig.eanLabel ? `
          <button class="${state.mode==='ean' ? 'active':''}" data-mode="ean">EAN Etikett</button>` : ''}

        ${state.labelingConfig.rfidLabel ? `
          <button class="${state.mode==='rfidprint' ? 'active':''}" data-mode="rfidprint">RFID + Etikett</button>` : ''}

        ${state.labelingConfig.rfidEncode ? `
          <button class="${state.mode==='rfidwrite' ? 'active':''}" data-mode="rfidwrite">RFID codieren</button>` : ''}



        <button class="invalidateMode" data-action="invalidatePopup">Artikel entwerten</button>
        <button class="counterMode" data-action="resetEncodeCounter" title="Codierungszähler zurücksetzen">Codiert: ${state.encodeCounter}</button>

        <a class="helpButton" href="/admin/?tab=articles" target="_blank" rel="noopener">Artikel</a>

        <a class="helpButton" href="/help/" target="_blank" rel="noopener">Hilfe</a>
      </div>

      <div class="customer">
        <b>${esc(c.customer || 'Foodware')}</b>
        <span>${esc(c.subtitle || 'Labeling Station')}</span>
      </div>
    </header>
  `;
}

function leftHtml(){
  return `
    <section class="panel left">
      <div class="groupHead"><h2>Warengruppen</h2><div class="groupSort" aria-label="Warengruppensortierung"><button class="${state.groupSort==='number'?'active':''}" data-group-sort="number">Nummer</button><button class="${state.groupSort==='name'?'active':''}" data-group-sort="name">Bezeichnung</button></div></div>

      <div class="groups">
        ${state.groups.map(g => {
          const id = Number(g.wg ?? g.id);
          return `<button class="${id === state.selectedGroup ? 'active' : ''}" data-group="${id}">${esc(g.name)}</button>`;
        }).join('')}
      </div>
    </section>
  `;
}

function pluKeyboardHtml(){
  return `
    <div class="pluPad">
      ${['1','2','3','4','5','6','7','8','9'].map(n => `<button data-plu-key="${n}">${n}</button>`).join('')}
      <button data-plu-key="clear">C</button>
      <button data-plu-key="0">0</button>
      <button data-plu-key="back">⌫</button>
      <button class="pluEnter" data-plu-key="enter">Suchen</button>
    </div>
  `;
}

function centerHtml(){
  return `
    <section class="panel center">
      <div class="centerSearch">
        <div>
          <label>Suche / Scanner / EAN / PLU</label>
          <input
            id="searchInput"
            value="${esc(state.search)}"
            placeholder="EAN scannen, PLU oder Text eingeben..."
            autocomplete="off"
          >
          <small>13 Stellen = EAN-Scan · Text = Suche · PLU über Zahlenfeld</small>
        </div>
        <button class="clearSearchBtn" data-action="clearSearch">X</button>
        <button data-action="openSearchPopup">Zahlenfeld / PLU</button>
      </div>

      <div class="message message-${messageKind()}">${esc(state.message)}</div>

      <div class="panelHead">
        <h2>Artikel auswaehlen</h2>
        <div class="productSort" aria-label="Artikelsortierung">
          <button class="${state.productSort==='number'?'active':''}" data-product-sort="number">Nummer</button>
          <button class="${state.productSort==='name'?'active':''}" data-product-sort="name">Bezeichnung</button>
        </div>
        <span>${state.products.length} Artikel</span>
      </div>

      <div class="productGrid">
        ${state.products.map(p => `
          <button class="product ${state.selectedProduct && state.selectedProduct.plu === p.plu ? 'active' : ''}"
                  data-product="${p.plu}">
            <b>${esc(p.name)}</b>
            <span>PLU ${p.plu} · ${esc(p.unit)}</span>
            <strong>${money(p.price)} / ${esc(p.unit)}</strong>
          </button>
        `).join('')}
      </div>
    </section>
  `;
}

function recentProtocolHtml(){
  return `
    <div class="recentCard collapsibleCard ${state.recentCollapsed?'collapsed':''}">
      <div class="recentHead">
        <b>Letzte Verwiegungen</b>
        <div class="cardHeadActions"><button data-action="protocol">Gesamtprotokoll</button><button class="collapseBtn" data-action="toggleRecent" title="Ein- oder ausklappen">${state.recentCollapsed?'▾':'▴'}</button></div>
      </div>
      <div class="collapsibleBody">
      ${state.protocolRecent.length ? `
        <div class="recentList">
          ${state.protocolRecent.map(r => `
            <div class="recentRow">
              <span>${esc(r.time || r.createdate || '')}</span>
              <b>${esc(r.number || r.nummer || '')}</b>
              <em><span>Netto</span>${num(protocolWeight(r), 3)} kg</em>
              <small>Tara ${num(protocolTara(r), 3)} kg</small>
              <strong>${money(firstValue(r.price, r.preis))}</strong>
            </div>
          `).join('')}
        </div>
      ` : `<div class="recentEmpty">Heute noch keine Verwiegung</div>`}
      </div>
    </div>
  `;
}

function labelPreviewCard(p){
  if(!p)return '';
  const options=state.labelTemplates.map(x=>'<option value="'+x.number+'" '+(Number(state.template)===Number(x.number)?'selected':'')+'>#'+x.number+' - '+esc(x.name)+' ('+x.widthMm+' x '+x.heightMm+' mm)</option>').join('');
  return `<div class="panel previewCard collapsibleCard ${state.previewCollapsed?'collapsed':''}">
    <div class="previewCardHead"><h2>Etikett-Vorschau</h2><button class="collapseBtn" data-action="togglePreview" title="Ein- oder ausklappen">${state.previewCollapsed?'▾':'▴'}</button></div>
    <div class="collapsibleBody">
      <label class="templatePicker">Etikettenvorlage<select id="templateSelect"><option value="0">Keine Vorlage</option>${options}</select></label>
      <div class="labelPreview realPreview" aria-label="Etikett Vorschau">
        <div class="labelPreviewTop"><span>Vorschau</span><b>${esc(state.activeLabel?.name||'Keine Vorlage')}</b></div>
        ${realLabelPreview(p)}
        <div class="labelPreviewFoot">${money(p.price)} / ${esc(p.unit)} · Netto ${num(netWeight(),3)} kg · MHD ${state.mhd?esc(state.mhd):'-'}</div>
      </div>
    </div>
  </div>`;
}

function rightHtml(){
  const p = state.selectedProduct;
  return `
    <section class="right">
      ${recentProtocolHtml()}
      ${labelPreviewCard(p)}
      <div class="panel weighCard">
        <h2>Verwiegung / Codierung</h2>
        <div class="message">${esc(state.message)}</div>
        ${p ? selectedHtml(p) : emptyHtml()}
      </div>
    </section>
  `;
}

function selectedHtml(p){
  return `
    <div class="fields">
      <label>Brutto-Gewicht</label>
      <div class="weightLine"><strong>${num(state.weight,3)} kg</strong><button data-action="weight">Gewicht holen</button><button class="manualWeightBtn" data-action="manualWeight">Gewicht eintragen</button></div>
      <div class="scaleInfo ${scaleStatusClass()}"><b>${scaleStatusText()}</b><span>${state.scaleLastAt?esc(state.scaleLastAt):'Waage bereit zum Lesen'}</span></div>
      <label>Tara</label>
      <div class="taraLine"><strong>${num(state.tara,3)} kg</strong><button type="button" data-action="taraClear">Keine Tara</button></div>
      ${taraButtonsHtml()}
      <div class="netLine"><span>Netto-Gewicht für Etikett</span><b>${num(netWeight(),3)} kg</b></div>
      ${state.scaleRaw?`<small class="scaleRaw">${esc(state.scaleRaw)}</small>`:''}
      <label>Menge</label>
      <div class="qtyLine"><button data-action="qtyMinus">−</button><strong>${state.qty}</strong><button data-action="qtyPlus">+</button></div>
      <label>MHD</label><input id="mhdInput" type="date" value="${esc(state.mhd)}">
      ${state.mode==='rfidprint'?`<label class="checkLine"><input id="normalLabelCheck" type="checkbox" ${state.printNormalLabel?'checked':''}> zusätzlich normales Etikett mitdrucken</label>`:''}
    </div>
    <div class="sum"><span>${qtyText()}</span><b>${money(totalPrice())}</b></div>
  `;
}
function emptyHtml(){
  return `<div class="empty"><div>□</div><b>Artikel scannen oder auswählen</b><span>Suchfeld links bleibt aktiv.</span></div>`;
}

function bottomHtml(){
  const disabled = state.selectedProduct ? '' : 'disabled';

  if(state.mode === 'ean'){
    return `<footer class="bottom ean"><button data-action="protocol">Gesamtprotokoll</button><button class="mainAction" data-action="weightPrint" ${disabled}>Gewicht holen & Etikett drucken</button><button data-action="reset">Neu</button></footer>`;
  }

  if(state.mode === 'rfidwrite'){
    return `<footer class="bottom rfidwrite"><button data-action="protocol">Gesamtprotokoll</button><button data-action="rfidCheckPopup">Artikel prüfen</button><button class="mainAction rfid" data-action="rfidPopup" ${disabled}>RFID codieren</button><button data-action="reset">Neu</button></footer>`;
  }

  return `<footer class="bottom rfidprint"><button data-action="protocol">Gesamtprotokoll</button><button class="mainAction" data-action="rfidPrintFlow" ${disabled}>Gewicht holen, Tag drucken & codieren</button><button data-action="reset">Neu</button></footer>`;
}

function searchPopupHtml(){
  if(!state.searchOpen) return '';

  return `
    <div class="modalBack">
      <div class="searchModal">
        <h2>Artikel suchen</h2>

        <div class="searchModalInput">
          <label>PLU / EAN / Suchtext</label>
          <input id="searchPopupInput" value="${esc(state.search)}" placeholder="PLU, EAN oder Artikelname...">
        </div>

        <div class="pluPad modalPluPad">
          ${['1','2','3','4','5','6','7','8','9'].map(n => `<button data-plu-key="${n}">${n}</button>`).join('')}
          <button data-plu-key="clear">C</button>
          <button data-plu-key="0">0</button>
          <button data-plu-key="back">⌫</button>
          <button class="pluEnter" data-plu-key="enter">Suchen / PLU wählen</button>
        </div>

        <div class="modalButtons">
          <button data-action="closeSearchPopup">Schließen</button>
        </div>
      </div>
    </div>
  `;
}

function manualWeightPopupHtml(){
 if(!state.manualWeightOpen)return '';
 const keys=['1','2','3','4','5','6','7','8','9',',','0','back'];
 return `<div class="modalBack"><div class="smallModal manualWeightModal"><h2>Gewicht eintragen</h2><p>Gewicht in Kilogramm</p><div class="manualWeightDisplay">${esc(state.manualWeightText||'0,000')} kg</div><div class="manualWeightPad">${keys.map(k=>`<button data-weight-key="${k}">${k==='back'?'⌫':k}</button>`).join('')}</div><div class="modalButtons"><button data-action="manualWeightCancel">Abbrechen</button><button class="mainAction" data-action="manualWeightApply">Übernehmen</button></div></div></div>`;
}
function rfidPopupHtml(){
  if(!state.waitingForRfid) return '';

  const p = state.selectedProduct;
  const invalidate = state.rfidAction === 'invalidate';
  const check = state.rfidAction === 'check';
  const title = check ? 'Artikel prüfen' : (invalidate ? 'Artikel entwerten' : 'RFID codieren');
  const waitText = check
    ? 'Scannen oder legen Sie ein RFID-Tag auf. Es wird nur geprüft und nichts verändert.'
    : (invalidate
      ? 'Legen Sie das RFID-Tag auf die gekennzeichnete Fläche. Der Tag wird in TAGINFO auf Status 9 gesetzt und ist damit entwertet.'
      : `Legen Sie das RFID-Tag / den Artikel auf die gekennzeichnete Fläche.
         Gespeichert wird erst bei vollständigem RFID-Code
         (${Number(state.labelingConfig.rfidTagLength || 24)} Zeichen).
         Für den gleichen Artikel legen Sie einfach ein weiteres Tag auf.
         Für einen anderen Artikel gehen Sie auf Abbrechen.`);

  return `
    <div class="modalBack">
      <div class="smallModal rfidModalBig ${invalidate ? 'invalidateModal' : ''} ${check ? 'checkModal' : ''}">
        <h2>${title}</h2>

        ${check ? `
          <div class="rfidArticleBox checkBox">
            <div>
              <h3>Prüfung</h3>
              <p>Zeigt Artikel, Status, Menge/Gewicht und Preis des gelesenen Tags.</p>
            </div>
          </div>` : (invalidate ? `
          <div class="rfidArticleBox invalidateBox">
            <div>
              <h3>Entwertung</h3>
              <p>Der gelesene RFID-Tag wird gesucht und als entwertet markiert.</p>
            </div>
          </div>` : `
          <div class="rfidArticleBox">
            <div>
              <h3>${p ? esc(p.name) : ''}</h3>
              <p>PLU ${p ? p.plu : ''}</p>
              <div class="rfidFacts">
                <span>Gewicht: <b>${num(state.weight, 3)} kg</b></span>
                <span>Preis: <b>${money(totalPrice())}</b></span>
                <span>MHD: <b>${esc(state.mhd || '-')}</b></span>
              </div>
            </div>
          </div>`)}

        <div class="rfidWaitText">
          <b>${esc(state.rfidMessage || (check ? 'Warte auf RFID-Tag zur Prüfung...' : (invalidate ? 'Warte auf RFID-Tag zur Entwertung...' : 'Warte auf RFID-Tag...')))}</b>
          <span>${waitText}</span>
        </div>

        ${state.rfidCheckResult ? rfidCheckResultHtml(state.rfidCheckResult) : ''}

        ${check ? '' : `<div class="rfidModeLine">
          <button class="${state.afterSaveMode === 'next' ? 'active' : ''}" data-action="rfidSingle">${invalidate ? 'Einzelentwertung' : 'Einzelcodierung'}</button>
          <button class="${state.afterSaveMode === 'same' ? 'active' : ''}" data-action="rfidMulti">${invalidate ? 'Mehrfachentwertung' : 'Mehrfachcodierung'}</button>
        </div>`}

        ${(!invalidate && !check && state.rfidDuplicateTag) ? `<div class="rfidOverwriteLine"><button class="danger" data-action="rfidOverwrite">RFID-Tag ueberschreiben und freigeben</button></div>` : ''}

        <div class="modalButtons">
          <button data-action="cancelRfid">Abbrechen</button>
        </div>
      </div>
    </div>
  `;
}

function normalizeRfidTagInput(value){
  const needLen = Number(state.labelingConfig.rfidTagLength || 24);
  const raw = String(value || '').toUpperCase().replace(/[^0-9A-F]/g, '');
  const ePos = raw.indexOf('E');
  let tag = ePos >= 0 ? raw.substring(ePos) : raw;
  if(needLen > 0 && tag.length > needLen) tag = tag.substring(0, needLen);
  return tag;
}

function validateRfidTag(tag){
  const needLen = Number(state.labelingConfig.rfidTagLength || 24);
  const cleanTag = normalizeRfidTagInput(tag);
  if(cleanTag === '') return { ok:false, tag:cleanTag, message:'Kein RFID-Tag gelesen.' };
  if(needLen > 0 && cleanTag.length < needLen)
    return { ok:false, tag:cleanTag, message:'RFID-Tag unvollständig: ' + cleanTag.length + ' / ' + needLen + ' Zeichen' };
  if(needLen > 0 && cleanTag.length !== needLen)
    return { ok:false, tag:cleanTag, message:'RFID-Tag hat falsche Länge: ' + cleanTag.length + ' / ' + needLen + ' Zeichen' };
  if(!/^E[0-9A-F]+$/.test(cleanTag))
    return { ok:false, tag:cleanTag, message:'RFID-Tag ungültig: Bitte Tag erneut auflegen. Der Code muss mit E beginnen.' };
  return { ok:true, tag:cleanTag, message:'' };
}
function rfidCheckResultHtml(r){
  const ok = !!(r && r.ok && r.found !== false);
  return `<div class="rfidCheckResult ${ok ? 'ok' : 'bad'}">
    <h3>${ok ? 'Tag gefunden' : 'Tag nicht lesbar / nicht gefunden'}</h3>
    <div class="rfidCheckGrid">
      <span>Tag</span><b>${esc(r?.tag || '-')}</b>
      <span>Status</span><b>${esc(r?.statusText || r?.message || '-')}</b>
      <span>Artikel</span><b>PLU ${esc(r?.plu || '-')} · ${esc(r?.name || '-')}</b>
      <span>Menge/Gewicht</span><b>${num(r?.weight || 0, 3)} ${esc(r?.unit || 'kg')}</b>
      <span>Tara</span><b>${num(r?.tara || 0, 3)} kg</b>
      <span>Preis</span><b>${money(r?.price || 0)}</b>
      <span>Preis/Stamm</span><b>${money(r?.unitPrice || 0)} / ${esc(r?.unit || '')}</b>
      <span>MHD</span><b>${esc(r?.mhd || '-')}</b>
      <span>Charge</span><b>${esc(r?.charge || '-')}</b>
    </div>
  </div>`;
}
function protocolModalHtml(){
  return `
    <div class="modalBack">
      <div class="protocolModal">
        <div class="modalHead"><h2>Gesamtprotokoll TAGINFO</h2><button data-action="closeProtocol">Schließen</button></div>
        <div class="protocolTableWrap">
          <table class="protocolTable">
            <thead><tr><th>Zeit</th><th>Tag</th><th>Nummer</th><th>MHD</th><th>Brutto</th><th>Tara</th><th>Netto</th><th>Preis</th><th>Status</th><th>Aktion</th></tr></thead>
            <tbody>
              ${state.protocolAll.map(r => `
                <tr>
                  <td>${esc(r.createdate || '')}</td>
                  <td>${esc(r.tag || '')}</td>
                  <td>${esc(r.number || r.nummer || '')}</td>
                  <td>${esc(r.mhd || '')}</td>
                  <td>${num(protocolGross(r), 3)} kg</td>
                  <td>${num(protocolTara(r), 3)} kg</td>
                  <td><b>${num(protocolWeight(r), 3)} kg</b></td>
                  <td>${money(firstValue(r.price, r.preis))}</td>
                  <td>
                    <select data-protocol-status="${r.id}">
                      <option value="0" ${Number(r.status) === 0 ? 'selected' : ''}>0 offen</option>
                      <option value="1" ${Number(r.status) === 1 ? 'selected' : ''}>1 OK</option>
                      <option value="9" ${Number(r.status) === 9 ? 'selected' : ''}>9 gesperrt</option>
                    </select>
                  </td>
                  <td><button class="danger" data-protocol-delete="${r.id}">Löschen</button></td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>
    </div>`;
}

function modalHtml(){
  return `<div class="modalBack"><div class="smallModal"><h2>${esc(state.modal.title)}</h2><p>${esc(state.modal.text)}</p><div class="modalButtons">${state.modal.cancel ? `<button data-action="closeModal">Abbrechen</button>` : ''}<button class="mainAction" data-action="modalOk">OK</button></div></div></div>`;
}

function bind(){
  document.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => {
    const wanted = b.dataset.mode;
    if(!modeIsEnabled(wanted)) return;
    state.mode = wanted;
    state.waitingForRfid = false;
    state.modal = null;
    render();
  });

  document.querySelectorAll('[data-group-sort]').forEach(b => b.onclick = () => setGroupSort(b.dataset.groupSort));

  const groupList=document.querySelector('.groups');
  let groupTouchStartY=0,groupTouchMoved=false;
  if(groupList){groupList.onpointerdown=e=>{groupTouchStartY=e.clientY;groupTouchMoved=false};groupList.onpointermove=e=>{if(Math.abs(e.clientY-groupTouchStartY)>8)groupTouchMoved=true}}

  document.querySelectorAll('[data-group]').forEach(b => b.onclick = async () => {
    if(groupTouchMoved){groupTouchMoved=false;return}
    clearTimeout(state.searchTimer);
    state.selectedGroup = Number(b.dataset.group);
    state.search = '';
    state.lastScanText = '';
    await loadProducts(state.selectedGroup);
    render();
  });

  document.querySelectorAll('[data-product-sort]').forEach(b => b.onclick = () => setProductSort(b.dataset.productSort));

  document.querySelectorAll('[data-product]').forEach(b => b.onclick = () => {
    const plu = Number(b.dataset.product);
    const p = state.products.find(x => x.plu === plu);
    if(p) selectProduct(p);
  });

  document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => action(b.dataset.action));
  document.querySelectorAll('[data-weight-key]').forEach(b=>b.onclick=()=>manualWeightKey(b.dataset.weightKey));
  document.querySelectorAll('[data-plu-key]').forEach(b => b.onclick = () => pluKey(b.dataset.pluKey));

  document.querySelectorAll('[data-protocol-delete]').forEach(b => {
    b.onclick = () => deleteProtocol(Number(b.dataset.protocolDelete));
  });

  document.querySelectorAll('[data-protocol-status]').forEach(s => {
    s.onchange = () => setProtocolStatus(Number(s.dataset.protocolStatus), Number(s.value));
  });

  const si = $('searchInput');
  if(si){
    si.oninput = () => onSearchInput(si.value);
    si.onkeydown = e => {
      if(e.key === 'Enter')
        handleSearchText(si.value, true);
    };
  }

  const spi = $('searchPopupInput');
  if(spi){
    spi.oninput = () => onSearchInput(spi.value);
    spi.onkeydown = e => {
      if(e.key === 'Enter')
        handleSearchText(spi.value, true);
    };
    setTimeout(() => {
      const x = $('searchPopupInput');
      if(x) x.focus();
    }, 80);
  }

  const rfid = $('rfidInput');
  if(rfid){
    rfid.oninput = async e => {
      const raw = e.target.value;
      const tag = normalizeRfidTagInput(raw);
      const needLen = Number(state.labelingConfig.rfidTagLength || 24);
      debugLog('rfid input', { rawLength: raw.length, length: tag.length, needLen, tag });
      if(tag.length >= needLen){
        e.target.value = '';
        await handleRfidTag(tag);
      }
    };

    rfid.onkeydown = async e => {
      if(e.key === 'Enter'){
        const raw = e.target.value;
        const tag = normalizeRfidTagInput(raw);
        e.target.value = '';
        const needLen = Number(state.labelingConfig.rfidTagLength || 24);
        debugLog('rfid enter', { rawLength: raw.length, length: tag.length, needLen, tag });
        if(tag.length >= needLen)
          await handleRfidTag(tag);
        else if(raw){
          const check = validateRfidTag(raw);
          state.rfidMessage = check.message;
          render();
          setTimeout(() => $('rfidInput')?.focus(), 100);
        }
      }
    };
    if(state.waitingForRfid){
      setTimeout(() => {
        const x = $('rfidInput');
        if(x){ x.value = ''; x.focus(); debugLog('rfid focus', { waiting: state.waitingForRfid }); }
      }, 100);
    }
  }

  const mhd = $('mhdInput');
  if(mhd) mhd.oninput = () => state.mhd = mhd.value;

  const tpl = $('templateSelect');
  if(tpl) tpl.onchange = () => {state.template=Number(tpl.value||0);loadActiveLabel(state.template)};

  const chk = $('normalLabelCheck');
  if(chk) chk.onchange = () => state.printNormalLabel = chk.checked;
}

function pluKey(k){
  if(k === 'clear'){
    state.search = '';
    render();
    return;
  }

  if(k === 'back'){
    state.search = state.search.slice(0, -1);
    render();
    return;
  }

  if(k === 'enter'){
    handleSearchText(state.search, true);
    return;
  }

  state.search += k;
  render();
}

function looksLikeRfidTag(text){
  const len = Number(state.labelingConfig.rfidTagLength || 24);
  const s = String(text || '').trim();
  const digits = s.replace(/\D/g, '');

  // 13-stellige reine Zahlen sind immer EAN und dürfen nie als RFID blockiert werden.
  if(digits.length === 13 && digits === s) return false;

  if(!len || len <= 0) return false;
  return s.length >= len;
}

function onSearchInput(value){
  const v = String(value || '').trim();

  // Schutz: RFID-Tag darf nicht in die Artikelsuche laufen.
  // Wenn wir gerade auf RFID warten, speichern wir es direkt.
  if(looksLikeRfidTag(v)){
    clearTimeout(state.searchTimer);

    if(state.waitingForRfid){
      state.search = '';
      handleRfidTag(v);
      return;
    }

    state.search = '';
    state.message = 'RFID-Tag erkannt. Bitte erst Artikel auswählen und RFID codieren starten.';
    render();
    return;
  }

  state.search = value;
  clearTimeout(state.searchTimer);
  state.searchTimer = setTimeout(() => handleSearchText(value, false), 350);
}

async function handleSearchText(value, force){
  const text = String(value || '').trim();
  const digits = text.replace(/\D/g, '');

  if(digits.length >= 13 && digits === text){
    await searchByScan(digits.substring(0, 13));
    state.search = '';
    state.lastScanText = '';
    state.searchOpen = false;
    render();
    return;
  }

  if(text.length === 0){
    state.lastScanText = '';
    await searchProducts('');
    return;
  }

  if(digits.length > 0 && digits.length < 13 && digits === text){
    if(force)
      await selectProductByPlu(digits);
    else
      await searchProducts(digits);
    return;
  }

  if(force || text.length > 1)
    await searchProducts(text);
}

function manualWeightKey(key){
 let v=String(state.manualWeightText||'');
 if(key==='back')v=v.slice(0,-1);else if(key===','){if(!v.includes(',')&&!v.includes('.'))v+=','}else if(/\d/.test(key)&&v.replace(/\D/g,'').length<7)v+=key;
 state.manualWeightText=v;render();
}
async function action(a){
  if(a === 'protocol'){ await openFullProtocol(); return; }
  if(a === 'toggleRecent'){ state.recentCollapsed=!state.recentCollapsed; render(); return; }
  if(a === 'togglePreview'){ state.previewCollapsed=!state.previewCollapsed; render(); return; }

  if(a === 'openSearchPopup'){
    state.searchOpen = true;
    render();
    return;
  }

  if(a === 'closeSearchPopup'){
    state.searchOpen = false;
    render();
    return;
  }

  if(a === 'clearSearch'){
    clearTimeout(state.searchTimer);
    state.search = '';
    state.lastScanText = '';
    await searchProducts('');
    return;
  }

  if(a === 'searchNow'){
    await handleSearchText(state.search, true);
    return;
  }
  if(a === 'togglePluPad'){
    state.searchOpen = true;
    render();
    return;
  }
  if(a === 'closeProtocol'){ state.protocolOpen = false; render(); return; }
  if(a === 'closeModal'){ state.modal = null; render(); return; }

  if(a === 'cancelRfid'){
    state.waitingForRfid = false;
    state.rfidAction = 'encode';
    state.rfidMessage = '';
    state.rfidDuplicateTag = '';
    state.rfidDuplicateId = 0;
    state.rfidDuplicateStatus = null;
    render();
    setTimeout(() => $('searchInput')?.focus(), 100);
    return;
  }

  if(a === 'rfidSingle'){
    state.afterSaveMode = 'next';
    state.rfidMessage = state.rfidAction === 'invalidate' ? 'Einzelentwertung aktiv. Warte auf RFID-Tag...' : 'Einzelcodierung aktiv. Warte auf RFID-Tag...';
    render();
    return;
  }

  if(a === 'rfidMulti'){
    state.afterSaveMode = 'same';
    state.rfidMessage = state.rfidAction === 'invalidate' ? 'Mehrfachentwertung aktiv. Warte auf RFID-Tag...' : 'Mehrfachcodierung aktiv. Warte auf RFID-Tag...';
    render();
    return;
  }

  if(a === 'rfidOverwrite'){
    const tag = state.rfidDuplicateTag || state.rfidTag;
    if(tag) await saveRfidTag(tag, true);
    return;
  }

  if(a === 'modalOk'){ await modalOk(); return; }
  if(a === 'qtyMinus'){ state.qty = Math.max(1, state.qty - 1); render(); return; }
  if(a === 'qtyPlus'){ state.qty++; render(); return; }
  if(a === 'weight'){ await readWeight(); return; }
  if(a === 'manualWeight'){state.manualWeightText=Number(state.weight||0).toFixed(3).replace('.',',');state.manualWeightOpen=true;render();return}
  if(a === 'manualWeightCancel'){state.manualWeightOpen=false;render();return}
  if(a === 'manualWeightApply'){const v=parseNum(String(state.manualWeightText).replace(',','.'));if(v>0){state.weight=v;state.stable=true;state.scaleRaw='Manuell eingetragen';state.scaleLastAt=new Date().toLocaleTimeString('de-DE');state.message='Gewicht manuell übernommen.'}state.manualWeightOpen=false;render();return}
  if(a === 'taraClear'){ setTaraValue(0); return; }
  if(a && a.startsWith('tara:')){ setTaraValue(Number(a.slice(5))); return; }

  if(a === 'weightPrint'){
    if(unitIsKg()) await readWeight();
    await printLabel();
    await loadRecentProtocol();
    render();
    return;
  }

  if(a === 'rfidPrintFlow'){ await rfidPrintFlow(); return; }
  if(a === 'rfidPopup'){ startRfidWait(state.afterSaveMode || 'next'); return; }
  if(a === 'rfidCheckPopup'){ startRfidCheckWait(); return; }
  if(a === 'invalidatePopup'){ startRfidInvalidateWait(state.afterSaveMode || 'next'); return; }
  if(a === 'resetEncodeCounter'){ state.encodeCounter = 0; sessionStorage.setItem('labelingEncodeCounter','0'); state.message = 'Codierungszähler zurückgesetzt.'; render(); return; }
  if(a === 'reset'){ resetSelection(); return; }
}

function resetSelection(){
  state.selectedProduct = null;
  state.weight = 0;
  state.stable = false;
  state.tara = 0;
  state.scaleRaw = '';
  state.scaleLastAt = '';
  state.qty = 1;
  state.search = '';
  state.waitingForRfid = false;
  state.rfidMessage = '';
  state.rfidDuplicateTag = '';
  state.rfidDuplicateId = 0;
  state.rfidDuplicateStatus = null;
  state.showPluPad = false;
  state.searchOpen = false;
  state.mhd = '';
  state.template = 0;
  state.activeLabel = null;
  state.message = 'Suchfeld bereit';
  render();
}

async function readWeight(showBusy = true){
  try{
    if(showBusy){
      state.message = 'Gewicht wird gelesen...';
      render();
    }

    const r = await fetch('/api/labeling/weight');
    const j = await r.json();

    if(j.ok){
      state.weight = Number(j.weight || 0);
      state.stable = !!j.stable;
      state.scaleRaw = j.raw || '';
      state.scaleLastAt = new Date().toLocaleTimeString('de-DE', {hour:'2-digit', minute:'2-digit', second:'2-digit'});
      state.message = (j.message || 'Gewicht uebernommen') + (state.stable ? '' : ' - bitte Stabilitaet pruefen');
    }else{
      state.scaleRaw = j.raw || '';
      state.message = j.message || 'Waage nicht bereit';
    }
    render();
  }catch(e){
    state.message = 'Waage/API nicht erreichbar';
    render();
  }
}

async function ensureWeightForPrint(){
  if(!unitIsKg()) return true;
  if(parseNum(state.weight) <= 0)
    await readWeight();
  if(parseNum(state.weight) <= 0){
    state.message = 'Kein Gewicht vorhanden. Bitte Artikel auf die Waage legen.';
    render();
    return false;
  }
  if(netWeight() <= 0){
    state.message = 'Netto-Gewicht ist 0 kg. Bitte Tara pruefen oder Artikel neu wiegen.';
    render();
    return false;
  }
  return true;
}


async function printLabel(templateOverride){
  const p = state.selectedProduct;
  if(!p) return false;
  if(!await ensureWeightForPrint()) return false;

  const url =
    '/api/labeling/print?plu=' + encodeURIComponent(p.plu) +
    '&weight=' + encodeURIComponent(Number(netWeight() || 0).toFixed(3)) +
    '&tara=' + encodeURIComponent(Number(state.tara || 0).toFixed(3)) +
    '&qty=' + encodeURIComponent(state.qty) +
    '&mhd=' + encodeURIComponent(state.mhd) +
    '&template=' + encodeURIComponent(Number(templateOverride || state.template || 0));

  try{
    state.message = 'Etikett wird gedruckt...';
    render();

    const r = await fetch(url);
    const j = await r.json();

    state.message = j.message || (j.ok ? 'Etikett gedruckt' : 'Fehler beim Druck');
    return !!j.ok;
  }catch(e){
    state.message = 'Druck/API nicht erreichbar';
    render();
    return false;
  }
}

async function writeRfid(){
  const p = state.selectedProduct;
  if(!p) return false;

  const url =
    '/api/labeling/rfid/write?plu=' + encodeURIComponent(p.plu) +
    '&weight=' + encodeURIComponent(Number(unitIsKg() ? (netWeight() || 0) : 0).toFixed(3));

  try{
    state.message = 'RFID wird codiert...';
    render();

    const j = await fetchJsonDebug(url, 'rfid write');

    state.message = j.message || (j.ok ? 'RFID codiert' : 'RFID Fehler');
    return !!j.ok;
  }catch(e){
    debugLog('rfid write error', { message: e.message });
    state.message = 'RFID/API nicht erreichbar';
    render();
    return false;
  }
}

async function rfidPrintFlow(){
  if(unitIsKg()) await readWeight();

  const tagOk = await printLabel();
  if(tagOk)
    await writeRfid();

  if(state.printNormalLabel)
    await printLabel();

  await loadRecentProtocol();
  render();
}

function startRfidWait(mode){
  state.rfidAction = 'encode';
  if(!state.selectedProduct){
    state.message = 'Kein Artikel ausgewählt.';
    render();
    return;
  }

  if(mode === 'same' || mode === 'next')
    state.afterSaveMode = mode;

  state.waitingForRfid = true;
  state.rfidTag = '';
  state.rfidDuplicateTag = '';
  state.rfidDuplicateId = 0;
  state.rfidDuplicateStatus = null;
  state.rfidMessage =
    state.afterSaveMode === 'same'
      ? 'Mehrfachcodierung aktiv. Warte auf RFID-Tag...'
      : 'Einzelcodierung aktiv. Warte auf RFID-Tag...';

  debugLog('rfid wait start', { mode: state.afterSaveMode, plu: state.selectedProduct.plu, needLen: state.labelingConfig.rfidTagLength });
  render();
  setTimeout(() => $('rfidInput')?.focus(), 100);
}

function startRfidCheckWait(){
  state.rfidAction = 'check';
  state.waitingForRfid = true;
  state.rfidTag = '';
  state.rfidDuplicateTag = '';
  state.rfidDuplicateId = 0;
  state.rfidDuplicateStatus = null;
  state.rfidCheckResult = null;
  state.rfidMessage = 'Prüfmodus aktiv. Warte auf RFID-Tag...';
  debugLog('rfid check wait start', { needLen: state.labelingConfig.rfidTagLength });
  render();
  setTimeout(() => $('rfidInput')?.focus(), 100);
}

function startRfidInvalidateWait(mode){
  if(mode === 'same' || mode === 'next')
    state.afterSaveMode = mode;

  state.rfidAction = 'invalidate';
  state.waitingForRfid = true;
  state.rfidTag = '';
  state.rfidDuplicateTag = '';
  state.rfidDuplicateId = 0;
  state.rfidDuplicateStatus = null;
  state.rfidMessage =
    state.afterSaveMode === 'same'
      ? 'Mehrfachentwertung aktiv. Warte auf RFID-Tag...'
      : 'Einzelentwertung aktiv. Warte auf RFID-Tag...';

  debugLog('rfid invalidate wait start', { mode: state.afterSaveMode, needLen: state.labelingConfig.rfidTagLength });
  render();
  setTimeout(() => $('rfidInput')?.focus(), 100);
}

async function handleRfidTag(tag){
  if(state.rfidAction === 'check')
    return checkRfidTag(tag);
  if(state.rfidAction === 'invalidate')
    return invalidateRfidTag(tag);
  return saveRfidTag(tag);
}

async function checkRfidTag(tag){
  const check = validateRfidTag(tag);
  const cleanTag = check.tag;
  if(!check.ok){
    state.rfidMessage = check.message;
    state.rfidCheckResult = { ok:false, tag: cleanTag, message: check.message };
    render();
    setTimeout(() => $('rfidInput')?.focus(), 100);
    return;
  }
  state.rfidMessage = 'RFID-Tag wird geprüft...';
  state.rfidCheckResult = null;
  render();
  try{
    const j = await fetchJsonDebug('/api/labeling/rfid/check?tag=' + encodeURIComponent(cleanTag), 'rfid check', 15000);
    state.rfidCheckResult = Object.assign({ tag: cleanTag }, j);
    state.rfidMessage = j.ok ? 'RFID-Tag gefunden.' : (j.message || 'RFID-Tag nicht gefunden.');
    state.message = state.rfidMessage;
    render();
    setTimeout(() => $('rfidInput')?.focus(), 100);
  }catch(e){
    state.rfidMessage = 'RFID/API nicht erreichbar';
    state.rfidCheckResult = { ok:false, tag: cleanTag, message: state.rfidMessage };
    render();
  }
}

async function invalidateRfidTag(tag){
  if(state.savingRfid){
    debugLog('rfid invalidate ignored', { reason: 'already saving' });
    return;
  }

  const check = validateRfidTag(tag);
  const cleanTag = check.tag;
  if(!check.ok){
    state.rfidMessage = check.message;
    render();
    setTimeout(() => $('rfidInput')?.focus(), 100);
    return;
  }

  state.savingRfid = true;
  state.rfidMessage = 'RFID-Tag wird entwertet...';
  render();

  try{
    const j = await fetchJsonDebug('/api/labeling/rfid/invalidate?tag=' + encodeURIComponent(cleanTag), 'rfid invalidate', 15000);
    state.message = j.ok ? 'RFID-Tag entwertet.' : (j.message || 'RFID-Tag konnte nicht entwertet werden.');
    state.rfidMessage = state.message;

    if(j.ok){
      await loadRecentProtocol();
      if(state.afterSaveMode === 'same'){
        render();
        setTimeout(() => startRfidInvalidateWait('same'), 700);
      }else{
        setTimeout(() => {
          state.waitingForRfid = false;
          state.rfidAction = 'encode';
          state.rfidMessage = '';
          render();
          setTimeout(() => $('searchInput')?.focus(), 100);
        }, 900);
      }
    }else{
      state.waitingForRfid = true;
      render();
      setTimeout(() => $('rfidInput')?.focus(), 100);
    }
  }catch(e){
    debugLog('rfid invalidate error', { message: e.message });
    state.rfidMessage = 'RFID/API nicht erreichbar';
    render();
  }finally{
    state.savingRfid = false;
  }
}
async function saveRfidTag(tag, overwrite = false){
  if(state.savingRfid){
    debugLog('rfid save ignored', { reason: 'already saving' });
    return;
  }

  const p = state.selectedProduct;
  if(!p) return;

  const check = validateRfidTag(tag);
  const cleanTag = check.tag;
  const needLen = Number(state.labelingConfig.rfidTagLength || 24);
  if(!check.ok){
    state.rfidMessage = check.message;
    render();
    setTimeout(() => $('rfidInput')?.focus(), 100);
    return;
  }

  const url =
    '/api/labeling/rfid/save?plu=' + encodeURIComponent(p.plu) +
    '&tag=' + encodeURIComponent(cleanTag) +
    '&weight=' + encodeURIComponent(Number(unitIsKg() ? (netWeight() || 0) : 0).toFixed(3)) +
    '&tara=' + encodeURIComponent(Number(unitIsKg() ? (state.tara || 0) : 0).toFixed(3)) +
    '&price=' + encodeURIComponent(Number(totalPrice() || p.price || 0).toFixed(2)) +
    '&mhd=' + encodeURIComponent(state.mhd || '') +
    '&source=' + encodeURIComponent(p.source || state.rfidSource || 'reader') +
    (overwrite ? '&overwrite=1' : '');

  debugLog('rfid save start', {
    plu: p.plu,
    tag: cleanTag,
    length: cleanTag.length,
    needLen,
    weight: state.weight,
    price: totalPrice(),
    mhd: state.mhd
  });

  state.savingRfid = true;
  state.rfidMessage = 'RFID-Tag wird gespeichert...';
  render();

  try{
    const j = await fetchJsonDebug(url, 'rfid save', 15000);
    state.message = j.ok
      ? 'RFID-Tag gespeichert.'
      : (j.message || 'RFID-Tag konnte nicht gespeichert werden.');
    state.rfidMessage = state.message;

    if(j.duplicate || j.canOverwrite){
      state.rfidDuplicateTag = j.tag || cleanTag;
      state.rfidDuplicateId = Number(j.id || 0);
      state.rfidDuplicateStatus = j.status ?? null;
    }

    if(j.ok){
      state.rfidDuplicateTag = '';
      state.rfidDuplicateId = 0;
      state.rfidDuplicateStatus = null;
      state.waitingForRfid = false;
      state.encodeCounter = Number(state.encodeCounter || 0) + 1;
      sessionStorage.setItem('labelingEncodeCounter', String(state.encodeCounter));
      debugLog('rfid save ok', { plu: p.plu, tag: cleanTag, counter: state.encodeCounter });
      await loadRecentProtocol();

      if(state.afterSaveMode === 'same'){
        state.rfidMessage = 'RFID-Tag gespeichert. Nächstes Tag auflegen...';
        render();
        setTimeout(() => startRfidWait('same'), 700);
      }else{
        state.rfidMessage = 'RFID-Tag gespeichert.';
        render();
        setTimeout(() => {
          state.waitingForRfid = false;
          state.rfidMessage = '';
          state.selectedProduct = null;
          state.search = '';
          render();
          setTimeout(() => $('searchInput')?.focus(), 100);
        }, 900);
      }
    }else{
      state.waitingForRfid = true;
      render();
      setTimeout(() => $('rfidInput')?.focus(), 100);
    }
    state.savingRfid = false;
  }catch(e){
    state.savingRfid = false;
    state.waitingForRfid = false;
    debugLog('rfid save error', { message: e.message });
    state.rfidMessage = 'RFID/API nicht erreichbar';
    render();
    setTimeout(() => $('searchInput')?.focus(), 100);
  }
}

async function modalOk(){
  state.modal = null;
  render();
}

async function searchByScan(ean){
  state.message = 'EAN wird gesucht: ' + ean;
  render();

  try{
    const j = await fetchJsonDebug('/api/labeling/scan?ean=' + encodeURIComponent(ean), 'ean scan');

    if(j.ok){
      const p = mapProduct(j);
      state.selectedProduct = p;
      if(productIsKg(p)){
        state.weight = Number(j.weight || j.qty || p.nenngewicht || 0);
        if(p.taranr)
          setTaraByNr(p.taranr);
        else
          state.tara = 0;
      }else{
        clearPieceWeight();
      }
      state.mhd = defaultMhdForProduct(Object.assign({}, p, { mhd: j.mhd || p.mhd }), '');
      state.message = j.name + ' gefunden' + (j.source ? ' (' + j.source + ')' : '');

      if(state.mode === 'rfidwrite' && state.autoMode)
        startRfidWait('next');
      else
        render();

      return;
    }

    state.message = j.message || 'Artikel nicht gefunden';
    render();
  }catch(e){
    state.message = 'Scanner/API nicht erreichbar';
    render();
  }
}

async function deleteProtocol(id){
  if(!confirm('Eintrag aus TAGINFO löschen?')) return;

  await fetch('/api/labeling/protocol/delete?id=' + encodeURIComponent(id));
  await loadRecentProtocol();
  await openFullProtocol();
}

async function setProtocolStatus(id, status){
  await fetch('/api/labeling/protocol/status?id=' + encodeURIComponent(id) + '&status=' + encodeURIComponent(status));
  await loadRecentProtocol();
  await openFullProtocol();
}

document.addEventListener('DOMContentLoaded', boot);
































