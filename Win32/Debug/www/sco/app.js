const state = {
  page: 'start',
  items: [],
  groups: [],
  products: [],
  selectedGroup: null,
  selectedProduct: null,
  modal: null,
  qty: 1,
  manualWeight: '0,250',
  selectedPayment: '',
  paymentComplete: false,
  paymentBusy: false,
  paymentMessage: '',
  paymentOkTimer: null,
  idleTimer: null,
  idleSeconds: 120,
  saleBooked: false,
  saleBonNo: 0,
  receiptPreview: '',
  receiptPreviewLoading: false,
  receiptStatus: '',
  adminTapCount: 0,
  adminTapTimer: null,
  adminPin: '',
  adminPopup: false,
  coupon: 0,
  customerActive: false,
  ratings: [5, 5, 5, 5],
  scanMessage: 'Scanner bereit',
  notice: null,
  exitAlarm: null,
  exitAlarmTimer: null,
  nextRowId: 1,
  lastRfidEventId: 0,
  rfidSessionActive: false,
  rfidStartBusy: false,
  rfidStatus: 'idle',
  rfidLastOk: 0,
  rfidLastPollOk: 0,
  theme: {
    customer: 'Herbst Hofladen',
    subtitle: 'Self-Checkout',
    phone: '06372 50940',
    address: '',
    logo: 'assets/logo.png',
    description: 'Willkommen in unserem Hofladen. Regional, frisch und einfach selbst einkaufen.',
    green: '#107a2a',
    dark: '#101c29',
    dark2: '#0c1824',
    accent: '#f2b01e'
  },
  config: {
    payment_cash: 1,
    payment_ec: 1,
    payment_customer: 0,
    payment_coupon: 0,
    bon_auto_print: 0,
    receipt_width_mm: 80,
    rating_active: 1,
    demo_mode: 0,
    manual_products: 1,
    rfid_active: 0,
    rfid_tag_length: 24,
    rfid_exit_alarm_active: 1,
    rfid_exit_alarm_antenna: 4,
    rfid_exit_alarm_seconds: 20,
    rfid_exit_alarm_system_beep: 1,
    rfid_exit_alarm_sound: '',
    rfid_start_on_scan: 0,
    rating_questions: [
      'Wie zufrieden sind Sie mit unserem Sortiment?',
      'Wie zufrieden sind Sie mit der Abwicklung des Zahlvorgangs?',
      'Wie gefällt Ihnen der Hofladen?',
      'Wie bewerten Sie das Einkaufserlebnis insgesamt?'
    ]
  }
};

const BLANK_IMAGE = 'assets/blanko.svg';
const RFID_RETURN_MESSAGE = 'Artikel wurde entfernt. Bitte stellen Sie den Artikel zurück an seinen Platz.';
const RFID_RETURN_ALL_MESSAGE = 'Alle Artikel wurden entfernt. Bitte stellen Sie alle Artikel zurück an ihren Platz.';
function rfidCustomerMessage(msg){
  const m = String(msg || '').toLowerCase();
  if(m.includes('status') || m.includes('verkauft') || m.includes('gesperrt') || m.includes('entwertet')) return 'Artikel bereits bezahlt oder entwertet.';
  if(m.includes('taginfo') || m.includes('nicht gefunden') || m.includes('fehlt') || m.includes('unvollständig') || m.includes('unvollständig')) return 'Artikel nicht lesbar. Bitte Artikel erneut auflegen oder manuell hinzufügen.';
  return 'Artikel nicht lesbar. Bitte Artikel erneut auflegen oder manuell hinzufügen.';
}
const recentRfidScans = Object.create(null);
const rfidIgnoredUntil = Object.create(null);
const rfidInFlight = Object.create(null);
const rfidAccepted = Object.create(null);

function $(id){ return document.getElementById(id); }
function esc(s){ return String(s ?? '').replace(/[&<>\"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }
function money(v){ return Number(v || 0).toLocaleString('de-DE', { style:'currency', currency:'EUR' }); }
function total(){ return state.items.reduce((s, x) => s + Number(x.gp || 0), 0); }
function kgTotal(){ return state.items.filter(x => String(x.unit).toLowerCase() === 'kg').reduce((s, x) => s + Number(x.qty || 0), 0); }
function qtyText(x){ return String(x.unit).toLowerCase() === 'kg' ? Number(x.qty || 0).toLocaleString('de-DE', { minimumFractionDigits:3, maximumFractionDigits:3 }) + ' kg' : x.qty + ' ' + (x.unit || 'Stck'); }
function payAmount(){ return Math.max(0, total() - state.coupon); }
function paymentEnabled(){ return state.config.payment_cash || state.config.payment_ec || state.config.payment_customer || state.config.payment_coupon; }

function clearIdleTimer(){
  if(state.idleTimer) clearTimeout(state.idleTimer);
  state.idleTimer = null;
}

function shouldRunIdleTimer(){
  if(state.paymentBusy || state.paymentComplete) return false;
  return state.page === 'cart' || state.page === 'payment';
}

function scheduleIdleReset(){
  clearIdleTimer();
  if(!shouldRunIdleTimer()) return;
  const seconds = Math.max(30, Math.min(600, Number(state.idleSeconds || 120)));
  state.idleTimer = setTimeout(() => {
    if(!shouldRunIdleTimer()) return;
    const count = state.items.length;
    if(count > 0){
      logLocalEvent({ art:'ABBRUCH_TIMEOUT', level:'info', message:'Einkauf wegen Inaktivitaet automatisch abgebrochen', qty:count });
      releaseRfidItems(state.items);
    }
    stopRFIDSession();
    resetOrder();
    state.page = 'start';
    render();
    focusScanner();
  }, seconds * 1000);
}

function customerActivity(){
  if(shouldRunIdleTimer()) scheduleIdleReset();
}
function logLocalEvent(payload){
  fetch('/api/event/log', {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify(Object.assign({ source:'sco' }, payload || {}))
  }).catch(e=>console.warn('lokale meldung nicht erreichbar', e));
}
function tagKey(tag){ return String(tag || '').trim().toUpperCase(); }
function hasRfidTag(tag){
  const key = tagKey(tag);
  return !!key && (rfidAccepted[key] || state.items.some(x => tagKey(x.tag) === key));
}
async function releaseRfidTag(tag){
  const key = tagKey(tag);
  if(!key) return;
  try{
    await fetch('/api/rfid/release?tag=' + encodeURIComponent(key), { cache:'no-store' });
  }catch(e){
    console.warn('rfid release nicht erreichbar', e);
  }
}
function forgetRfidTag(tag){
  const key = tagKey(tag);
  if(!key) return;
  delete rfidAccepted[key];
  delete rfidInFlight[key];
  delete recentRfidScans[key];
  delete rfidIgnoredUntil[key];
}
function releaseRfidItems(items){
  (items || []).filter(x => x && x.source === 'rfid' && x.tag).forEach(x => {
    logRfidRemoval(x);
    releaseRfidTag(x.tag);
    forgetRfidTag(x.tag);
  });
}
function logRfidRemoval(item){
  if(!item || item.source !== 'rfid' || !item.tag) return;
  fetch('/api/webui/status', {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({
      status:2, bon:0, pos:0, plu:Number(item.plu||0), tag:item.tag,
      name:item.name||'', message:'Artikel geloescht / zurueckgelegt', qty:Number(item.qty||0),
      ep:Number(item.ep||0), gp:Number(item.gp||0)
    })
  }).catch(e=>console.warn('rfid status entfernen nicht erreichbar',e));
}
async function flushRFIDEvents(){
  if(!state.config.rfid_active) return;
  try{
    const r = await fetch('/api/rfid/events?after=' + encodeURIComponent(state.lastRfidEventId || 0), { cache:'no-store' });
    const j = await r.json();
    if(j.ok && Array.isArray(j.events)){
      for(const ev of j.events) state.lastRfidEventId = Math.max(Number(state.lastRfidEventId || 0), Number(ev.id || 0));
    }
  }catch(e){
    console.warn('rfid flush nicht erreichbar', e);
  }
}
function startRFIDSession(force = false){
  if(!state.config.rfid_active) return;
  customerActivity();
  const now = Date.now();
  if(state.rfidStartBusy && !force && state.rfidStartAt && now - state.rfidStartAt < 4500) return;
  if(state.rfidSessionActive && !force) return;
  state.rfidStartBusy = true;
  state.rfidStartAt = now;
  state.rfidStatus = 'starting';
  state.rfidSessionActive = false;
  if(force){
    Object.keys(rfidAccepted).forEach(k => delete rfidAccepted[k]);
    Object.keys(rfidInFlight).forEach(k => delete rfidInFlight[k]);
    Object.keys(recentRfidScans).forEach(k => delete recentRfidScans[k]);
    Object.keys(rfidIgnoredUntil).forEach(k => delete rfidIgnoredUntil[k]);
    state.lastRfidEventId = 0;
  }
  state.scanMessage = 'Scanner wird gestartet ...';
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3500);
  fetch('/api/rfid/start?t=' + encodeURIComponent(Date.now()) + (force ? '&force=1' : ''), { cache:'no-store', signal:controller.signal })
    .then(r => r.json())
    .then(j => {
      clearTimeout(timeout);
      state.rfidStartBusy = false;
      if(!j.ok){
        state.rfidSessionActive = false;
        state.rfidStatus = 'error';
        state.scanMessage = j.message || 'Scanner konnte nicht gestartet werden';
        if(state.page === 'cart') render();
      }else{
        state.rfidSessionActive = true;
        state.rfidStatus = 'active';
        state.rfidLastOk = Date.now();
        state.scanMessage = 'Scanner aktiv - bitte Artikel auflegen';
        if(state.page === 'cart') render();
      }
    })
    .catch(e => {
      clearTimeout(timeout);
      state.rfidStartBusy = false;
      state.rfidSessionActive = true;
      state.rfidStatus = 'active';
      state.scanMessage = 'Scanner aktiv - bitte Artikel auflegen';
      if(state.page === 'cart') render();
    });
}
function ensureRFIDForCart(){
  if(state.page !== 'cart' || !state.config.rfid_active || state.paymentBusy || state.paymentComplete) return;
  if(!state.rfidSessionActive && !state.rfidStartBusy) startRFIDSession(false);
}
function stopRFIDSession(){
  state.rfidSessionActive = false;
  state.rfidStartBusy = false;
  state.rfidStatus = 'idle';
  Object.keys(rfidInFlight).forEach(k => delete rfidInFlight[k]);
  Object.keys(recentRfidScans).forEach(k => delete recentRfidScans[k]);
  Object.keys(rfidIgnoredUntil).forEach(k => delete rfidIgnoredUntil[k]);
}
function resetRFIDSession(){
  if(!state.config.rfid_active) return;
  stopRFIDSession();
  state.scanMessage = 'RFID wird neu gestartet ...';
  startRFIDSession(true);
  render();
  focusScanner();
}
function applyTheme(){
  document.documentElement.style.setProperty('--green', state.theme.green);
  document.documentElement.style.setProperty('--dark', state.theme.dark);
  document.documentElement.style.setProperty('--accent', state.theme.accent);
}

async function boot(){
  await loadConfig();
  if(state.config.rfid_active) startRFIDSession(false);
  await loadGroupsAndProducts();
  applyTheme();
  render();
  updateClock();
  setInterval(updateClock, 1000);
  focusScanner();
  setInterval(pollRFIDEvents, 350);
  setInterval(ensureRFIDForCart, 2000);
}

async function loadConfig(){
  try{
    const r = await fetch('/api/config', { cache:'no-store' });
    const c = await r.json();
    if(!c) return;

    state.config.manual_products = c.manualProducts !== false ? 1 : 0;

    state.theme.customer = c.customer || c.kunde || c.Kunde || state.theme.customer;
    state.theme.subtitle = c.subtitle || c.Subtitle || state.theme.subtitle;
    state.theme.phone = c.phone || c.telefon || c.Telefon || state.theme.phone;
    state.theme.address = c.address || c.adresse || c.Adresse || state.theme.address || '';
    state.theme.logo = c.logo || state.theme.logo;
    state.theme.description = c.description || c.beschreibung || c.about || state.theme.description;

    if(c.theme){
      state.theme.green = c.theme.green || state.theme.green;
      state.theme.dark = c.theme.dark || state.theme.dark;
      state.theme.accent = c.theme.accent || state.theme.accent;
    }

    if(c.payment){
      state.config.payment_cash = c.payment.cash ? 1 : 0;
      state.config.payment_ec = c.payment.ec ? 1 : 0;
      state.config.payment_customer = c.payment.customer ? 1 : 0;
      state.config.payment_coupon = c.payment.coupon ? 1 : 0;
    }

    state.config.demo_mode = c.demoMode ? 1 : 0;
    state.config.manual_products = c.manualProducts !== false ? 1 : 0;
    if(c.rfid){
      state.config.rfid_active = c.rfid.active ? 1 : 0;
      state.config.rfid_tag_length = Number(c.rfid.tagLength || 24);
      state.config.rfid_exit_alarm_active = c.rfid.exitAlarmActive !== false ? 1 : 0;
      state.config.rfid_exit_alarm_antenna = Number(c.rfid.exitAlarmAntenna || 4);
      state.config.rfid_exit_alarm_seconds = Number(c.rfid.exitAlarmSeconds || 20);
      state.config.rfid_exit_alarm_system_beep = c.rfid.exitAlarmSystemBeep !== false ? 1 : 0;
      state.config.rfid_exit_alarm_sound = c.rfid.exitAlarmSound || '';
      state.config.rfid_start_on_scan = c.rfid.startOnScan ? 1 : 0;
    }
    if(c.receipt){
      state.config.bon_auto_print = c.receipt.autoPrint ? 1 : 0;
      state.config.receipt_width_mm = Number(c.receipt.widthMm || 80);
      state.config.receipt_left_margin_mm = Number(c.receipt.leftMarginMm || 0);
    }
    if(c.rating){
      state.config.rating_active = c.rating.active ? 1 : 0;
      if(Array.isArray(c.rating.questions)) state.config.rating_questions = c.rating.questions;
    }
  }catch(e){
    console.warn('config nicht geladen', e);
  }
}

async function loadGroupsAndProducts(){
  try{
    const gr = await fetch('/api/groups', { cache:'no-store' });
    const groups = await gr.json();
    state.groups = (Array.isArray(groups) ? groups : []).map(g => ({
      id: Number(g.id ?? g.wg ?? g.WG),
      name: g.name ?? g.WG_BEZ ?? g.wg_bez ?? 'Warengruppe',
      icon: g.icon || ''
    })).filter(g => g.id > 0);

    if(!state.selectedGroup && state.groups.length) state.selectedGroup = state.groups[0].id;

    state.products = [];
    for(const g of state.groups){
      try{
        const pr = await fetch('/api/products?wg=' + encodeURIComponent(g.id), { cache:'no-store' });
        const arr = await pr.json();
        if(Array.isArray(arr)){
          arr.forEach(p => state.products.push({
            group: Number(p.group ?? p.wg ?? g.id),
            plu: Number(p.plu ?? p.ELENO ?? p.eleno),
            id: p.id ?? p.ID,
            name: p.name ?? p.BEZEICHNUNG ?? '',
            note: p.note ?? p.name2 ?? p.BEZEICHNUNG2 ?? '',
            unit: p.unit ?? p.ME_BEZ ?? 'Stck',
            ep: Number(p.ep ?? p.price ?? p.PREIS ?? 0),
            vatRate: Number(p.vatRate ?? p.mwst ?? p.MWST ?? 7),
            wg: Number(p.wg ?? p.group ?? 0),
            image: p.image || p.imageUrl || p.bild || BLANK_IMAGE
          }));
        }
      }catch(e){ console.warn('products wg ' + g.id, e); }
    }
  }catch(e){
    console.warn('groups nicht geladen', e);
    state.groups = [];
    state.products = [];
  }
}

function updateClock(){
  const c = $('clock');
  if(c) c.textContent = new Date().toLocaleTimeString('de-DE', { hour:'2-digit', minute:'2-digit' });
}

function currentStep(){
  if(state.page === 'start') return 1;
  if(state.page === 'cart') return 2;
  if(state.page === 'payment') return 3;
  return 4;
}

function stepInfo(){
  const map = {
    start: ['Start', 'Willkommen im SB-Shop', 'Starten Sie hier Ihren Einkauf. Scannen Sie Artikel selbst oder wählen Sie Artikel ohne EAN aus.'],
    cart: ['Einkauf', 'Artikel erfassen', 'Scannen Sie Ihre Artikel. Im Warenkorb können Sie jeden Artikel einzeln entfernen.'],
    payment: ['Zahlung', 'Einkauf prüfen und bezahlen', 'Prüfen Sie Ihre Artikel, gehen Sie bei Bedarf zurück und wählen Sie danach die Zahlungsart.'],
    receipt: ['Bon', 'Bon erhalten', 'Die Zahlung war erfolgreich. Sie können den Bon drucken oder den Einkauf bewerten.'],
    rating: ['Bewertung', 'Ihre Meinung zählt', 'Bewerten Sie kurz Ihren Einkauf. Danach startet der nächste Einkauf.']
  };
  return map[state.page] || map.start;
}

function canUseStep(target){
  if(target === 'start') return true;
  if(target === 'cart') return state.page !== 'start' || state.items.length > 0;
  if(target === 'payment') return state.items.length > 0 && (state.page === 'payment' || state.page === 'receipt' || state.page === 'rating');
  if(target === 'receipt') return state.paymentComplete;
  if(target === 'rating') return state.paymentComplete || state.page === 'receipt' || state.page === 'rating';
  return false;
}

function topBar(){
  const step = currentStep();
  const entries = [['Start',1,'start'], ['Einkauf',2,'cart'], ['Zahlung',3,'payment'], ['Bon',4,'receipt']];
  return `<div class="topBar"><div class="progress">${entries.map(x => `<button class="${step === x[1] ? 'active' : ''}" data-page="${x[2]}" ${canUseStep(x[2]) ? '' : 'disabled'}><b>${x[1]}</b>${x[0]}</button>`).join('')}</div><div class="headRight"><div id="clock"></div><small>Tel. ${esc(state.theme.phone)}</small></div></div>`;
}

function stepHeader(){
  const [kicker, title, text] = stepInfo();
  return `<section class="stepHeader"><img src="${esc(state.theme.logo)}" onerror="this.style.display='none'"><div><span>${esc(kicker)}</span><h1>${esc(title)}</h1><p>${esc(text)}</p></div></section>`;
}

function layout(content, cls = 'workPage'){
  const header = state.page === 'start' ? '' : stepHeader();
  $('app').innerHTML = `<div class="shell">${topBar()}${header}<main class="${cls}">${content}</main>${modalHtml()}</div>`;
  updateClock();
  bind();
  scheduleIdleReset();
}

function render(){
  if(state.page === 'start') return layout(startHtml(), 'startPage');
  if(state.page === 'cart'){ layout(cartHtml(), 'workPage cartPage'); ensureRFIDForCart(); return; }
  if(state.page === 'payment') return layout(paymentHtml(), 'workPage paymentPage');
  if(state.page === 'receipt'){
    layout(receiptHtml(), 'workPage receiptPage');
    if(state.paymentComplete && !state.saleBooked) completeSale();
    else if(!state.paymentComplete || state.saleBonNo) ensureReceiptPreview();
    return;
  }
  if(state.page === 'rating'){ clearSuccessTimer(); return layout(ratingHtml(), 'workPage ratingPage'); }
}

function availablePaymentText(){
  const list = [];
  if(state.config.payment_cash) list.push('Barzahlung am Zahlautomaten');
  if(state.config.payment_ec) list.push('EC- und Kartenzahlung');
  if(state.config.payment_coupon) list.push('Gutschein');
  if(state.config.payment_customer) list.push('Kundenkarte');
  return list.join(' · ') || 'Zahlungsmittel werden am Terminal angezeigt';
}

function startHtml(){
  return `<section class="startImagePage"><img src="assets/startscreen.png" alt="${esc(state.theme.customer)} Self-Checkout" onerror="this.style.display='none';this.parentElement.classList.add('imageMissing')"><button class="startImageButton" data-page="cart" aria-label="Einkauf starten"></button><div class="startImageFallback"><h1>${esc(state.theme.customer)}</h1><p>${esc(state.theme.description)}</p><button class="startBtn" data-page="cart">Einkauf starten &rarr;</button></div></section>`;
}

function rfidIndicatorHtml(){
  if(!state.config.rfid_active) return '';
  const cls = state.rfidStatus === 'error' ? 'error' : (state.rfidStartBusy || state.rfidStatus === 'starting' ? 'starting' : (state.rfidSessionActive ? 'active' : 'idle'));
  const text = cls === 'active' ? 'Scanner aktiv' : (cls === 'starting' ? 'Scanner startet' : (cls === 'error' ? 'Scannerhilfe' : 'Scanner bereit'));
  const sub = cls === 'active' ? 'Artikel werden automatisch gelesen' : (cls === 'starting' ? 'Verbindung wird aufgebaut' : 'Bei Problemen Hilfe tippen');
  return `<div class="rfidIndicator ${cls}"><i></i><strong>${text}</strong><span>${sub}</span></div>`;
}

function cartHtml(){
  const manualEnabled = !!state.config.manual_products;
  const manualButton = manualEnabled ? `<button class="manualAdd" data-action="products"><span>+</span><b>Artikel manuell hinzuf&uuml;gen</b></button>` : '';
  const helpButton = state.config.rfid_active ? '<button class="cartHelp" data-action="rfidHelp"><span>?</span><b>Artikel nicht gelesen?<small>Hier tippen</small></b></button>' : '<button class="clear" data-action="clear"><span>&times;</span><b>Alle entfernen</b></button>';
  return `<section class="cartCard card"><div class="cartTools ${manualEnabled ? '' : 'noManual'}">${manualButton}<button class="scanInfo" data-action="focus"><span>SCAN</span><b>${esc(state.scanMessage)}</b></button>${rfidIndicatorHtml()}${helpButton}</div><div class="cartHeader"><div>Artikel</div><div>Preis</div><div>Menge</div><div>Gesamt</div><div></div></div><div class="cartRows cartRowsModern">${state.items.length ? state.items.map(cartRowHtml).join('') : emptyHtml()}</div><div class="summary"><div><span>Artikel</span><b>${state.items.length}</b></div><div><span>Gewicht</span><b>${kgTotal().toLocaleString('de-DE', { minimumFractionDigits:2, maximumFractionDigits:2 })} kg</b></div><div><span>Status</span><b>${esc(state.scanMessage)}</b></div><div><span>Gesamt</span><b class="green">${money(total())}</b></div></div></section><div class="bottomActions"><button class="secondary" data-action="cancel"><span>&times;</span><b>Einkauf abbrechen</b></button><button class="payWide" data-page="payment" ${state.items.length ? '' : 'disabled'}>Weiter zur Zahlung &rarr;</button></div>`;
}
function emptyHtml(){
  return `<div class="empty"><i>SCAN</i><h2>Scanner bereit</h2><p>Bitte scannen Sie einen Artikel oder wählen Sie „Artikel“.</p></div>`;
}

function articlePic(x){
  const src = x.image || BLANK_IMAGE;
  return `<img src="${esc(src)}" onerror="this.onerror=null;this.parentElement.classList.add('noImage');this.remove();">`;
}

function cartRowHtml(x){
  const safeId = String(x.rowId).replace(/'/g, "\\'");
  return `<div class="cartItem slideIn" data-row-id="${esc(x.rowId)}"><div class="cartThumb">${articlePic(x)}</div><div class="cartName"><b>${esc(x.name)}</b><span>PLU ${esc(x.plu)} - ${esc(x.note || '')}</span></div><div class="cartMeta"><span>Preis</span><b>${money(x.ep)} / ${esc(x.unit)}</b></div><div class="cartMeta"><span>Menge</span><b>${qtyText(x)}</b></div><div class="cartMeta total"><span>Gesamt</span><b>${money(x.gp)}</b></div><button class="rowDel" type="button" data-remove="${esc(x.rowId)}" onclick="removeItem('${safeId}'); return false;" title="Artikel entfernen" aria-label="Artikel entfernen">&times;</button></div>`;
}

function reviewRowHtml(x){
  return `<div class="reviewItem"><div><b>${esc(x.name)}</b><span>${qtyText(x)} - ${money(x.ep)} / ${esc(x.unit)}</span></div><strong>${money(x.gp)}</strong></div>`;
}

function rowHtml(x, readonly = false){
  return readonly ? reviewRowHtml(x) : cartRowHtml(x);
}

function paymentHtml(){
  const amount = payAmount();
  ensurePaymentDefault(false);
  const methods = availablePaymentMethods();
  const singleMethod = methods.length === 1;
  const payButton = singleMethod && state.selectedPayment ? `<button class="payFinal" data-action="startPayment" ${state.paymentBusy ? 'disabled' : ''}>${state.paymentBusy ? 'Zahlung l&auml;uft ...' : money(amount) + ' zahlen'}</button>` : '';
  const methodBlock = singleMethod
    ? `<div class="singleMethod"><span>Zahlungsart</span><b>${esc(methods[0].label)}</b><small>${esc(methods[0].hint)}</small></div>`
    : `<h3>Zahlungsart w&auml;hlen und Zahlung starten</h3><div class="methods">${methods.map(m => method(m.label, m.symbol)).join('')}</div><div class="chooseHint">Tippen Sie auf die gew&uuml;nschte Zahlungsart. Die Zahlung startet direkt.</div>`;
  return `<section class="review card"><div class="payTitle"><div><span>Einkauf pr&uuml;fen</span><h1>Ihre Artikel</h1></div><div class="payTitleActions"><button data-page="cart">&larr; Einkauf bearbeiten</button><button class="dangerMini" data-action="cancel">Abbrechen</button></div></div><div class="reviewList reviewListCompact">${state.items.length ? state.items.map(reviewRowHtml).join('') : emptyHtml()}</div></section><section class="payPanel card"><div class="sumPanel"><h3>Summe</h3>${line('Artikel', state.items.length)}${line('Gesamtgewicht', kgTotal().toLocaleString('de-DE', { minimumFractionDigits:2, maximumFractionDigits:2 }) + ' kg')}${line('Zwischensumme', money(total()))}${state.config.payment_coupon ? line('Gutschein', '- ' + money(state.coupon), 'green') : ''}<div class="payTotal"><b>Zu zahlen</b><strong>${money(amount)}</strong></div></div>${(state.config.payment_coupon || state.config.payment_customer) ? voucherHtml() : ''}${state.config.demo_mode ? '<div class="demoNotice"><b>Testmodus aktiv</b><span>ZVT wird mit Test=1 gestartet.</span></div>' : ''}${methodBlock}${payButton}${state.paymentMessage ? `<div class="paymentMsg ${state.paymentMessage.startsWith('OK') || state.paymentMessage.includes('erfolgreich') ? 'ok' : 'err'}">${esc(state.paymentMessage)}</div>` : ''}</section>`;
}

function line(l, v, c = ''){ return `<div class="line"><span>${l}</span><b class="${c}">${v}</b></div>`; }
function availablePaymentMethods(){
  const methods = [];
  if(state.config.payment_ec) methods.push({ label:'Karte', symbol:'EC', hint:'Kartenterminal' });
  if(state.config.payment_cash) methods.push({ label:'Bargeld', symbol:'BAR', hint:'Zahlautomat' });
  return methods;
}
function method(label, symbol){ return `<button class="method ${state.selectedPayment === label ? 'active' : ''}" data-method="${label}"><i>${symbol}</i><b>${label === 'Bargeld' ? 'Bar bezahlen' : 'Mit Karte bezahlen'}</b><span>${label === 'Bargeld' ? 'Zahlautomat jetzt starten' : 'Kartenterminal jetzt starten'}</span></button>`; }

function voucherHtml(){
  return `<div class="voucher"><h3>Gutschein / Kundenkarte</h3><div class="voucherBtns">${state.config.payment_coupon ? `<button data-action="toggleCoupon">Gutschein ${state.coupon ? 'entfernen' : 'scannen'}</button>` : ''}${state.config.payment_customer ? `<button data-action="toggleCustomer">Kundenkarte ${state.customerActive ? 'aktiv' : 'scannen'}</button>` : ''}</div></div>`;
}

function receiptHtml(){
  const preview = state.receiptPreview ? `<pre class="bonText">${esc(state.receiptPreview)}</pre>` : `<div class="bonLoading">${state.receiptPreviewLoading ? 'Bonvorschau wird geladen ...' : 'Bonvorschau noch nicht geladen.'}</div>`;
  const status = state.receiptStatus ? `<div class="receiptNotice ${state.receiptStatus.startsWith('FEHLER') ? 'err' : 'ok'}">${esc(state.receiptStatus)}</div>` : '';
  const title = state.receiptStatus && !state.receiptStatus.startsWith('FEHLER') ? 'Bon wurde gedruckt' : 'Zahlung erfolgreich';
  const textMm = Math.max(40, Math.min(80, Number(state.config.receipt_width_mm || 80)));
  const leftMm = Math.max(0, Math.min(40, Number(state.config.receipt_left_margin_mm || 0)));
  const textPx = Math.round(302 * textMm / 80);
  const leftPx = Math.round(302 * leftMm / 80);
  const ratingActive = Number(state.config.rating_active || 0) !== 0;
  return `<section class="receiptCard card receiptW80" style="--receipt-text-px:${textPx}px;--receipt-left-px:${leftPx}px"><div class="success">OK</div><h1>${title}</h1><p>Dieser Bon entspricht dem Ausdruck.</p>${status}<div class="bonWrap"><div class="bon">${preview}</div></div><div class="receiptBtns"><button data-action="refreshReceiptPreview">Druckvorschau aktualisieren</button><button class="greenBtn" data-action="print">Bon drucken</button></div>${ratingActive ? `<button class="rateBtn" data-page="rating">Einkauf bewerten</button>` : ''}<button class="plainBtn" data-action="newStart">Neuen Einkauf starten</button></section>`;
}

function bonHtml(){
  const sum = total();
  const vat = sum * 0.07;
  const net = sum - vat;
  return `<div class="bonCenter"><b>${esc(state.theme.customer)}</b><br>${esc(state.theme.phone)}<br>${new Date().toLocaleString('de-DE')}</div>${state.items.map(x => `<div class="bonItem"><b>${esc(x.name)}</b><div><span>${qtyText(x)} · ${money(x.ep)}</span><b>${money(x.gp)}</b></div></div>`).join('')}<div class="bonSum"><div><span>Netto</span><span>${money(net)}</span></div><div><span>MwSt.</span><span>${money(vat)}</span></div><div class="strong"><span>Summe</span><span>${money(sum)}</span></div></div>`;
}

function ratingHtml(){
  const qs = Array.isArray(state.config.rating_questions) && state.config.rating_questions.length
    ? state.config.rating_questions
    : ['Wie zufrieden waren Sie?', 'Wie gut war die Bedienung?', 'Wie bewerten Sie die Auswahl?', 'Wie wahrscheinlich empfehlen Sie uns weiter?'];
  return `<section class="ratingCard card"><h1>Ihre Meinung ist uns wichtig</h1>${qs.map((q, i) => `<div class="question"><b>${esc(q)}</b><div>${[1,2,3,4,5].map(n => `<button class="star ${n <= state.ratings[i] ? 'active' : ''}" data-rating="${i}:${n}">&#9733;</button>`).join('')}</div></div>`).join('')}<button class="payWide" data-action="saveRating">Bewertung speichern</button></section>`;
}

function modalHtml(){
  if(state.adminPopup) return adminPinModal();
  if(state.paymentBusy) return paymentWaitModal();
  if(state.exitAlarm) return exitAlarmModal();
  if(state.notice) return noticeModal();
  if(state.modal === 'products') return productModal();
  if(state.modal === 'qty') return qtyModal();
  if(state.modal === 'weight') return weightModal();
  return '';
}

function showNotice(title, message){
  state.notice = { title, message };
  render();
}

function noticeModal(){
  const n = state.notice || {};
  return `<div class="modal noticeOverlay"><div class="noticeBox card"><div class="noticeIcon">!</div><h1>${esc(n.title || 'Hinweis')}</h1><p>${esc(n.message || '')}</p><button class="noticeOk" data-action="noticeOk">OK, verstanden</button></div></div>`;
}

let exitAlarmSoundStamp = 0;
function showExitAlarm(item, options = {}){
  const seconds = Math.max(5, Math.min(60, Number(options.seconds || state.config.rfid_exit_alarm_seconds || 20)));
  const entry = { name:item?.name || 'Artikel', plu:item?.plu || '', tag:item?.tag || '' };
  const current = state.exitAlarm || { items:[], started:Date.now(), seconds };
  if(!current.items.some(x => String(x.tag || '') === String(entry.tag || '') && String(x.plu || '') === String(entry.plu || ''))) current.items.push(entry);
  current.seconds = seconds;
  current.started = Date.now();
  state.exitAlarm = current;
  if(state.exitAlarmTimer) clearTimeout(state.exitAlarmTimer);
  state.exitAlarmTimer = setTimeout(()=>{ state.exitAlarm = null; state.exitAlarmTimer = null; render(); }, seconds * 1000);
  playExitAlarmSound(options);
  render();
}
function playExitAlarmSound(options = {}){
  const now = Date.now();
  if(now - exitAlarmSoundStamp < 19000) return;
  exitAlarmSoundStamp = now;
  if(options.sound || state.config.rfid_exit_alarm_sound){ try{ new Audio('/api/rfid/alarm/sound?t=' + encodeURIComponent(now)).play().catch(()=>{}); }catch(e){} }
  if(options.systemBeep || state.config.rfid_exit_alarm_system_beep){ fetch('/api/rfid/alarm/beep?t=' + encodeURIComponent(now), { cache:'no-store' }).catch(()=>{}); try{ const ctx = new (window.AudioContext || window.webkitAudioContext)(); const o = ctx.createOscillator(); const g = ctx.createGain(); o.type='sine'; o.frequency.value=880; g.gain.value=.16; o.connect(g); g.connect(ctx.destination); o.start(); setTimeout(()=>{o.stop();ctx.close();},420); }catch(e){} }
}
function closeExitAlarm(){ if(state.exitAlarmTimer) clearTimeout(state.exitAlarmTimer); state.exitAlarmTimer = null; state.exitAlarm = null; render(); }
function exitAlarmModal(){
  const a = state.exitAlarm || { items:[] };
  const items = a.items.map(x => `<li><strong>${esc(x.name)}</strong><span>${x.plu ? 'PLU ' + esc(x.plu) : ''}</span></li>`).join('');
  return `<div class="modal exitAlarmOverlay"><div class="exitAlarmBox card"><div class="exitAlarmIcon">!</div><div class="exitAlarmKicker">Ausgangskontrolle</div><h1>Artikel nicht bezahlt</h1><p>Bitte pr&uuml;fen Sie den Einkauf. Folgende Artikel wurden an der Ausgangsantenne erkannt:</p><ul>${items}</ul><button class="exitAlarmOk" data-action="exitAlarmOk">OK, gepr&uuml;ft</button></div></div>`;
}

function adminPinModal(){
  return `<div class="modal adminModal"><div class="adminPin card"><h1>Admin-Zugang</h1><p>Bitte PIN eingeben.</p><div class="pinDots">${[0,1,2,3].map(i => `<span class="${state.adminPin.length > i ? 'filled' : ''}"></span>`).join('')}</div>${state.paymentMessage ? `<div class="adminError">${esc(state.paymentMessage)}</div>` : ''}<div class="pinPad">${[1,2,3,4,5,6,7,8,9].map(n => `<button data-pin="${n}">${n}</button>`).join('')}<button data-action="adminCancel">Abbruch</button><button data-pin="0">0</button><button data-action="adminBack">&larr;</button></div><button class="adminSubmit" data-action="adminSubmit" ${state.adminPin.length ? '' : 'disabled'}>Öffnen</button></div></div>`;
}
function paymentWaitModal(){
  const method = state.selectedPayment === 'Bargeld' ? 'Zahlautomat' : 'Kartenterminal';
  const instruction = state.selectedPayment === 'Bargeld' ? 'Bitte geben Sie den angezeigten Betrag am Zahlautomaten ein.' : 'Bitte Karte einstecken, auflegen oder den Betrag am Ger&auml;t best&auml;tigen.';
  return `<div class="modal paymentOverlay"><div class="paymentWait card"><div class="spinner"></div><h1>Bitte folgen Sie den Anweisungen auf dem ${method}.</h1>${state.config.demo_mode && state.selectedPayment !== 'Bargeld' ? '<div class="demoNotice wait"><b>Testmodus aktiv</b><span>ZVT Test=1</span></div>' : ''}<p>${instruction}</p><strong>${money(payAmount())}</strong></div></div>`;
}

function productModal(){
  const list = state.products.filter(p => Number(p.group) === Number(state.selectedGroup));
  return `<div class="modal"><div class="productModal card"><aside><h2>Warengruppen</h2><div class="groupList touchScroll">${state.groups.map(g => `<button class="groupBtn ${g.id === state.selectedGroup ? 'active' : ''}" data-group="${g.id}">${esc(g.name)}</button>`).join('')}</div></aside><section><div class="modalTop"><div><h2>Artikel ohne EAN</h2><p>Warengruppe wählen und Artikel übernehmen.</p></div><button data-action="closeModal">&larr; Zurück</button></div><div class="productGrid touchScroll">${list.length ? list.map(p => `<button class="productBtn" data-product="${p.plu}"><div class="prodImg"><img src="${esc(p.image || BLANK_IMAGE)}" alt="" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'"><span class="articleIcon" style="display:none">ART</span></div><b>${esc(p.name)}</b><span>PLU ${p.plu} · ${esc(p.note || '')}</span><strong>${money(p.ep)} / ${esc(p.unit)}</strong></button>`).join('') : '<p>Keine Artikel in dieser Warengruppe gefunden.</p>'}</div></section></div></div>`;
}
function qtyModal(){
  const p = state.selectedProduct;
  if(!p) return '';
  return `<div class="modal"><div class="dialog card"><div class="modalTop"><h2>${esc(p.name)}</h2><button data-action="closeModal">&larr; Zurück</button></div><div class="qtyBox"><button data-action="qtyMinus">-</button><b>${state.qty}</b><button data-action="qtyPlus">+</button></div><div class="dialogSum"><span>Summe</span><b class="green">${money(state.qty * p.ep)}</b></div><button class="payWide" data-action="addQty">Übernehmen</button></div></div>`;
}

function weightModal(){
  const p = state.selectedProduct;
  if(!p) return '';
  const q = Number(String(state.manualWeight).replace(',', '.')) || 0;
  return `<div class="modal"><div class="dialog card"><div class="modalTop"><h2>${esc(p.name)}</h2><button data-action="closeModal">&larr; Zurück</button></div><div class="scaleBox"><span>Gewicht</span><b>${state.manualWeight} kg</b></div><input class="manualInput" id="weightInput" value="${esc(state.manualWeight)}"><div class="dialogSum"><span>Summe</span><b class="green">${money(q * p.ep)}</b></div><button class="payWide" data-action="addWeight">Übernehmen</button></div></div>`;
}

async function submitAdminPin(){
  if(!state.adminPin) return;
  try{
    const r = await fetch('/api/admin/login?password=' + encodeURIComponent(state.adminPin), { cache:'no-store' });
    const j = await r.json();
    if(j.ok){
      window.location.href = '/admin/';
    }else{
      state.paymentMessage = j.message || 'Falsches Passwort';
      state.adminPin = '';
      render();
    }
  }catch(e){
    state.paymentMessage = 'Admin-Anmeldung nicht erreichbar: ' + e.message;
    state.adminPin = '';
    render();
  }
}

function requestAdminAccess(){
  state.adminPin = '';
  state.adminPopup = true;
  state.paymentMessage = '';
  render();
}

function adminHotspotClick(e){
  if(e){ e.preventDefault(); e.stopPropagation(); }
  state.adminTapCount += 1;
  if(state.adminTapTimer) clearTimeout(state.adminTapTimer);
  state.adminTapTimer = setTimeout(() => state.adminTapCount = 0, 3500);
  if(state.adminTapCount >= 5){
    state.adminTapCount = 0;
    if(state.adminTapTimer) clearTimeout(state.adminTapTimer);
    requestAdminAccess();
  }
}
function bind(){
  document.querySelectorAll('[data-page]').forEach(b => b.onclick = async () => {
    customerActivity();
    const wanted = b.dataset.page;
    const fromStartToCart = state.page === 'start' && wanted === 'cart';
    const cartToPayment = wanted === 'payment' && state.page === 'cart' && state.items.length > 0;
    if(!cartToPayment && !canUseStep(wanted) && !fromStartToCart) return;
    if(wanted === 'payment' && !state.items.length) return;
    if(wanted === 'payment') stopRFIDSession();
    state.page = wanted;
    if(fromStartToCart){
      logLocalEvent({ art:'NEUER_KUNDE', level:'info', message:'Neuer Kunde' });
      startRFIDSession(true);
    }else if(wanted === 'cart' && state.config.rfid_active){
      startRFIDSession(false);
    }
    if(state.page === 'start') resetOrder();
    if(state.page === 'rating') clearSuccessTimer();
    if(state.page === 'payment') {
      state.selectedPayment = '';
      state.paymentMessage = '';
      ensurePaymentDefault(false);
    }
    render();
    focusScanner();
  });

  document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => action(b.dataset.action));
  document.querySelectorAll('.productModal').forEach(m => {
    m.addEventListener('touchstart', e => e.stopPropagation(), { passive:true });
    m.addEventListener('wheel', e => e.stopPropagation(), { passive:true });
  });
  document.querySelector('.headRight')?.addEventListener('click', adminHotspotClick);
  document.querySelectorAll('[data-remove]').forEach(b => b.onclick = e => { e.preventDefault(); e.stopPropagation(); removeItem(b.dataset.remove); });
  document.querySelectorAll('[data-pin]').forEach(b => b.onclick = e => { e.preventDefault(); e.stopPropagation(); if(state.adminPin.length < 8) state.adminPin += b.dataset.pin; render(); });
  document.querySelectorAll('[data-method]').forEach(b => b.onclick = () => {
    if(state.paymentBusy) return;
    state.selectedPayment = b.dataset.method;
    render();
    setTimeout(startPayment, 120);
  });
  document.querySelectorAll('[data-group]').forEach(b => b.onclick = () => {
    customerActivity();
    state.selectedGroup = Number(b.dataset.group);
    render();
    focusScanner();
  });
  document.querySelectorAll('[data-product]').forEach(b => b.onclick = () => selectProduct(Number(b.dataset.product)));
  document.querySelectorAll('[data-rating]').forEach(b => b.onclick = () => {
    clearSuccessTimer();
    const [i, n] = b.dataset.rating.split(':').map(Number);
    state.ratings[i] = n;
    render();
  });

  const wi = $('weightInput');
  if(wi) wi.oninput = () => state.manualWeight = wi.value;
}

function ensurePaymentDefault(setDefault = true){
  if(state.selectedPayment) return;
  const methods = availablePaymentMethods();
  if(!methods.length) return;
  if(methods.length === 1 || setDefault) state.selectedPayment = methods[0].label;
}

function paymentApiType(){
  switch(String(state.selectedPayment).toLowerCase()){
    case 'karte': case 'ec': case 'zvt': return 'zvt';
    case 'bargeld': case 'bar': return 'bar';
    default: return 'zvt';
  }
}

async function startPayment(){
  clearIdleTimer();
  if(state.paymentBusy || !state.selectedPayment) return;
  stopRFIDSession();

  const amount = payAmount();
  if(amount <= 0){
    state.paymentMessage = 'Zahlung nicht möglich: Der offene Betrag ist 0,00 EUR. Bitte Artikel/Preise pruefen.';
    render();
    return;
  }

  state.paymentComplete = false;
  state.saleBooked = false;
  state.saleBonNo = 0;
  state.receiptPreview = '';
  state.receiptStatus = '';
  state.paymentBusy = true;
  state.paymentMessage = state.selectedPayment === 'Bargeld' ? 'Bitte folgen Sie den Anweisungen am Zahlautomaten.' : 'Bitte folgen Sie den Anweisungen auf dem Kartenterminal.';
  render();

  try{
    const url = '/api/pay?type=' + encodeURIComponent(paymentApiType()) + '&amount=' + encodeURIComponent(amount.toFixed(2));
    const r = await fetch(url, { cache:'no-store' });
    const j = await r.json();
    state.paymentBusy = false;

    if(j.ok === true){
      state.paymentMessage = j.message || j.text || 'Zahlung erfolgreich';
      state.paymentComplete = true;
      state.page = 'receipt';
      render();
      startSuccessTimer();
      if(state.config.bon_auto_print) setTimeout(printReceipt, 500);
    }else{
      state.paymentMessage = j.message || j.text || 'Zahlung fehlgeschlagen';
      render();
    }
  }catch(e){
    state.paymentBusy = false;
    state.paymentMessage = 'Zahlung/API nicht erreichbar: ' + e.message;
    render();
  }
}

function clearSuccessTimer(){
  if(state.paymentOkTimer) clearTimeout(state.paymentOkTimer);
  state.paymentOkTimer = null;
}

function startSuccessTimer(){
  clearSuccessTimer();
  state.paymentOkTimer = setTimeout(() => newStart(), 10000);
}

function resetOrder(){
  clearIdleTimer();
  state.items = [];
  state.receiptPreview = '';
  state.receiptPreviewLoading = false;
  state.receiptStatus = '';
  state.coupon = 0;
  state.customerActive = false;
  state.paymentMessage = '';
  state.paymentBusy = false;
  state.paymentComplete = false;
  state.saleBooked = false;
  state.saleBonNo = 0;
  state.selectedPayment = '';
  state.rfidSessionActive = false;
  Object.keys(rfidAccepted).forEach(k => delete rfidAccepted[k]);
  Object.keys(rfidInFlight).forEach(k => delete rfidInFlight[k]);
  Object.keys(recentRfidScans).forEach(k => delete recentRfidScans[k]);
  state.scanMessage = 'Scanner bereit';
  state.ratings = [5, 5, 5, 5];
}

function newStart(){
  clearSuccessTimer();
  clearIdleTimer();
  resetOrder();
  state.page = 'start';
  render();
  focusScanner();
}

function receiptPayload(){
  return {
    shop: state.theme.customer,
    phone: state.theme.phone,
    address: state.theme.address || '',
    total: total(),
    payment: state.selectedPayment,
    bonNo: state.saleBonNo || 0,
    items: state.items.map(x => ({
      plu: x.plu,
      name: x.name,
      qty: String(x.qty),
      qtyText: qtyText(x),
      unit: x.unit || '',
      ep: Number(x.ep || 0),
      gp: Number(x.gp || 0),
      vatRate: Number(x.vatRate || x.mwst || 7),
      mwst: Number(x.vatRate || x.mwst || 7),
      wg: Number(x.wg || x.group || 0),
      source: x.source || '',
      tag: x.tag || ''
    }))
  };
}

async function ensureReceiptPreview(force = false){
  if(state.receiptPreviewLoading) return;
  if(state.receiptPreview && !force) return;
  if(!state.items.length) return;
  state.receiptPreviewLoading = true;
  if(force) state.receiptPreview = '';
  try{
    const r = await fetch('/api/receipt/preview', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(receiptPayload()), cache:'no-store' });
    const j = await r.json();
    state.receiptPreview = j.text || '';
    if(!j.ok && j.message) state.receiptPreview = j.message;
  }catch(e){
    state.receiptPreview = 'Bonvorschau/API nicht erreichbar: ' + e.message;
  }finally{
    state.receiptPreviewLoading = false;
    if(state.page === 'receipt') render();
  }
}

async function completeSale(){
  if(state.saleBooked || !state.paymentComplete || !state.items.length) return;
  state.saleBooked = true;
  try{
    const r = await fetch('/api/sale/complete', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(receiptPayload()), cache:'no-store' });
    const j = await r.json();
    if(j.ok){
      state.saleBonNo = Number(j.bonNo || 0);
      if(state.receiptPreview) state.receiptPreview = '';
      ensureReceiptPreview(true);
    }else{
      state.saleBooked = false;
      state.scanMessage = j.message || 'Verkauf konnte nicht verbucht werden';
      console.warn('sale complete failed', j);
    }
  }catch(e){
    state.saleBooked = false;
    state.scanMessage = 'Verkaufsbuchung/API nicht erreichbar';
    console.warn('sale complete error', e);
  }
}
async function saveRating(){
  const payload = { bonNo: Number(state.saleBonNo || 0), ratings: state.ratings || [5,5,5,5] };
  try{
    const r = await fetch('/api/rating/save', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload), cache:'no-store' });
    const j = await r.json();
    if(!j.ok) console.warn('rating save failed', j);
  }catch(e){
    console.warn('rating save error', e);
  }
  newStart();
}
async function printReceipt(){
  const payload = receiptPayload();
  state.receiptStatus = 'Bondruck wird gestartet ...';
  render();
  try{
    const r = await fetch('/api/receipt/print', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload), cache:'no-store' });
    const j = await r.json();
    state.receiptStatus = j.ok ? (j.message || 'Bon wurde gedruckt.') : ('FEHLER: ' + (j.message || 'Bon konnte nicht gedruckt werden.'));
  }catch(e){
    state.receiptStatus = 'FEHLER: Bondruck/API nicht erreichbar: ' + e.message;
  }
  render();
}

function action(a){
  customerActivity();
  if(a === 'noticeOk'){ state.notice = null; render(); focusScanner(); }
  if(a === 'exitAlarmOk'){ closeExitAlarm(); focusScanner(); }
  if(a === 'adminCancel'){ state.adminPopup = false; state.adminPin = ''; state.paymentMessage = ''; render(); focusScanner(); }
  if(a === 'adminBack'){ state.adminPin = state.adminPin.slice(0, -1); render(); }
  if(a === 'adminSubmit') submitAdminPin();
  if(a === 'clear'){
    const hadItems = state.items.length > 0;
    releaseRfidItems(state.items);
    state.items = [];
    state.scanMessage = RFID_RETURN_ALL_MESSAGE;
    if(hadItems) showNotice('Alle Artikel entfernt', RFID_RETURN_ALL_MESSAGE); else render();
  }
  if(a === 'focus') focusScanner();
  if(a === 'rfidReset') resetRFIDSession();
  if(a === 'rfidHelp'){
    const hadItems = state.items.length > 0;
    releaseRfidItems(state.items);
    state.items = [];
    resetRFIDSession();
    state.scanMessage = 'Scanner wird neu gestartet. Bitte legen Sie die Artikel erneut auf.';
    showNotice('Bitte Artikel neu auflegen', hadItems ? 'Wir starten die Artikelerfassung neu. Bitte legen Sie alle Artikel noch einmal auf die gekennzeichnete Fläche.' : 'Wir starten die Artikelerfassung neu. Bitte legen Sie Ihre Artikel auf die gekennzeichnete Fläche.');
  }
  if(a === 'products'){
    if(!state.config.manual_products) return;
    state.modal = 'products';
    render();
    focusScanner();
  }
  if(a === 'closeModal'){
    state.modal = null;
    state.selectedProduct = null;
    render();
    focusScanner();
  }
  if(a === 'cancel'){
    const hadItems = state.items.length > 0;
    releaseRfidItems(state.items);
    stopRFIDSession();
    resetOrder();
    state.scanMessage = RFID_RETURN_ALL_MESSAGE;
    state.page = 'start';
    if(hadItems) showNotice('Alle Artikel entfernt', RFID_RETURN_ALL_MESSAGE); else render();
  }
  if(a === 'toggleCoupon'){
    state.coupon = state.coupon ? 0 : 5;
    render();
  }
  if(a === 'toggleCustomer'){
    state.customerActive = !state.customerActive;
    render();
  }
  if(a === 'qtyMinus'){
    state.qty = Math.max(1, state.qty - 1);
    render();
  }
  if(a === 'qtyPlus'){
    state.qty++;
    render();
  }
  if(a === 'addQty') addManualQty();
  if(a === 'addWeight') addManualWeight();
  if(a === 'print') printReceipt();
  if(a === 'refreshReceiptPreview') ensureReceiptPreview(true);
  if(a === 'startPayment') startPayment();
  if(a === 'newStart') newStart();
  if(a === 'saveRating') saveRating();
}

function selectProduct(plu){
  if(!state.config.manual_products) return;
  const p = state.products.find(x => Number(x.plu) === Number(plu));
  if(!p) return;
  state.selectedProduct = p;
  state.qty = 1;
  state.manualWeight = '0,250';
  state.modal = String(p.unit).toLowerCase() === 'kg' ? 'weight' : 'qty';
  render();
}

function addManualQty(){
  const p = state.selectedProduct;
  if(!p) return;
  addItem({ plu:p.plu, name:p.name, note:p.note, unit:p.unit, qty:state.qty, ep:p.ep, gp:state.qty * p.ep, vatRate:p.vatRate || p.mwst || 7, wg:p.wg || p.group || 0, source:'manual', image:p.image || p.imageUrl || p.bild || BLANK_IMAGE });
}

function addManualWeight(){
  const p = state.selectedProduct;
  if(!p) return;
  const q = Number(String(state.manualWeight).replace(',', '.')) || 0;
  addItem({ plu:p.plu, name:p.name, note:p.note, unit:p.unit, qty:q, ep:p.ep, gp:q * p.ep, vatRate:p.vatRate || p.mwst || 7, wg:p.wg || p.group || 0, source:'manual', image:p.image || p.imageUrl || p.bild || BLANK_IMAGE });
}

function addItem(item){
  customerActivity();
  if(item && (item.source === 'rfid' || item.source === 'ean') && state.page !== 'cart') return;
  if(item && item.source === 'rfid' && !state.rfidSessionActive) return;
  if(item && item.source === 'rfid') item.tag = tagKey(item.tag);
  if(item && item.source === 'rfid' && hasRfidTag(item.tag)){
    state.scanMessage = item.name + ' ist bereits im Warenkorb';
    render();
    focusScanner();
    return;
  }
  item.rowId = 'r' + Date.now() + '_' + (state.nextRowId++);
  if(item && item.source === 'rfid' && item.tag) rfidAccepted[tagKey(item.tag)] = true;
  state.items.push(item);
  state.modal = null;
  state.selectedProduct = null;
  state.scanMessage = item.name + ' wurde hinzugefügt';
  state.page = 'cart';
  render();
  focusScanner();
}

function removeItem(id){
  customerActivity();
  const row = Array.from(document.querySelectorAll('[data-row-id]')).find(el => el.dataset.rowId === String(id));
  if(row){
    row.classList.add('slideOut');
    setTimeout(() => removeItemNow(id), 180);
    return;
  }
  removeItemNow(id);
}

function removeItemNow(id){
  const item = state.items.find(x => String(x.rowId) === String(id));
  if(item && item.source === 'rfid'){
    logRfidRemoval(item);
    releaseRfidTag(item.tag);
    forgetRfidTag(item.tag);
  }
  state.items = state.items.filter(x => String(x.rowId) !== String(id));
  state.scanMessage = item && item.source === 'rfid' ? RFID_RETURN_MESSAGE : (state.items.length ? 'Artikel entfernt' : 'Scanner bereit');
  if(item && item.source === 'rfid') showNotice('Artikel entfernt', RFID_RETURN_MESSAGE); else render();
}

function looksLikeRfidTag(value){
  if(!state.config.rfid_active) return false;
  const tag = String(value || '').trim().toUpperCase();
  const needLen = Number(state.config.rfid_tag_length || 24);
  return needLen > 0 && tag.length >= needLen && /^[0-9A-F]+$/.test(tag);
}

async function scanRFID(tag, antenna = 0){
  customerActivity();
  if(!state.rfidSessionActive || state.page !== 'cart') return;
  const key = tagKey(tag);
  if(!key) return;
  if(hasRfidTag(key) || rfidInFlight[key]) return;
  const now = Date.now();
  if(rfidIgnoredUntil[key] && now < rfidIgnoredUntil[key]) return;
  if(recentRfidScans[key] && now - recentRfidScans[key] < 4500) return;
  recentRfidScans[key] = now;
  rfidInFlight[key] = true;
  state.scanMessage = 'RFID-Tag wird gelesen ...';
  render();
  try{
    const r = await fetch('/api/rfid/scan?tag=' + encodeURIComponent(key) + '&antenna=' + encodeURIComponent(antenna), { cache:'no-store' });
    const j = await r.json();
    if(j.ok){
      const acceptedKey = tagKey(j.tag || key);
      if(j.alarm){
        showExitAlarm({ name:j.name, plu:j.plu, tag:acceptedKey }, { seconds:j.alarmSeconds, systemBeep:j.alarmSystemBeep, sound:j.alarmSound });
        return;
      }
      addItem({
        plu: j.plu,
        name: j.name,
        note: 'RFID',
        unit: j.unit || 'Stck',
        qty: Number(j.qty || 1),
        ep: Number(j.ep || 0),
        gp: Number(j.gp || j.ep || 0),
        vatRate: Number(j.vatRate || j.mwst || 7),
        wg: Number(j.wg || 0),
        source: 'rfid',
        tag: acceptedKey,
        image: BLANK_IMAGE
      });
      return;
    }
    const msg = String(j.message || '');
    const status = Number(j.status || 0);
    if(status !== 0 || msg.toLowerCase().includes('verkauft') || msg.toLowerCase().includes('gesperrt') || msg.toLowerCase().includes('entwertet')){
      rfidIgnoredUntil[key] = Date.now() + 30000;
    }else{
      rfidIgnoredUntil[key] = Date.now() + 10000;
    }
    state.scanMessage = rfidCustomerMessage(j.message);
    render();
  }catch(e){
    state.scanMessage = 'RFID/API nicht erreichbar';
    render();
  }finally{
    delete rfidInFlight[key];
  }
}
let eanScanBusy = false;
let queuedEan = '';

async function scanEAN(ean){
  customerActivity();
  const code = String(ean || '').replace(/\D/g, '');
  if(!/^\d{8}$|^\d{13}$/.test(code)) return;
  if(state.page === 'start' && !state.config.rfid_active){
    state.page = 'cart';
    state.scanMessage = 'EAN wird gelesen ...';
    render();
  }
  if(state.page !== 'cart') return;
  if(eanScanBusy){
    queuedEan = code;
    return;
  }

  eanScanBusy = true;
  const scanController = new AbortController();
  const scanTimeout = setTimeout(() => scanController.abort(), 8000);
  state.scanMessage = 'Scanne Artikel ...';
  render();
  try{
    const r = await fetch('/api/scan?ean=' + encodeURIComponent(code), { cache:'no-store', signal:scanController.signal });
    const j = await r.json();
    if(j.ok){
      addItem({
        plu: j.plu,
        name: j.name,
        note: j.type === 'scale' ? 'Waagen-EAN' : 'EAN',
        unit: j.unit || 'Stck',
        qty: Number(j.qty || 1),
        ep: Number(j.ep || 0),
        gp: Number(j.gp || j.ep || 0),
        vatRate: Number(j.vatRate || j.mwst || 7),
        source: 'ean',
        image: j.image || j.imageUrl || j.bild || BLANK_IMAGE
      });
    }else{
      state.scanMessage = j.message || 'Artikel nicht gefunden';
      render();
    }
  }catch(e){
    state.scanMessage = 'Scanner/API nicht erreichbar';
    render();
  }finally{
    clearTimeout(scanTimeout);
    eanScanBusy = false;
    focusScanner();
    if(queuedEan && (state.page === 'cart' || (state.page === 'start' && !state.config.rfid_active))){
      const next = queuedEan;
      queuedEan = '';
      setTimeout(() => scanEAN(next), 0);
    }
  }
}
function isExitAlarmEvent(ev){
  return state.config.rfid_exit_alarm_active && Number(ev?.antenna || 0) === Number(state.config.rfid_exit_alarm_antenna || 4);
}
async function scanRFIDExitAlarm(tag, antenna){
  const key = tagKey(tag);
  if(!key) return;
  try{
    const r = await fetch('/api/rfid/scan?tag=' + encodeURIComponent(key) + '&antenna=' + encodeURIComponent(antenna), { cache:'no-store' });
    const j = await r.json();
    if(!j.alarm) return;
    if(j.ok){
      showExitAlarm({ name:j.name || 'RFID-Artikel', plu:j.plu || '', tag:key }, { seconds:j.alarmSeconds, systemBeep:j.alarmSystemBeep, sound:j.alarmSound });
      return;
    }
    if(Number(j.status || 0) === 0 || String(j.message || '').toLowerCase().includes('nicht gefunden')){
      showExitAlarm({ name:'RFID-Artikel nicht zugeordnet', plu:j.plu || '', tag:key }, { seconds:state.config.rfid_exit_alarm_seconds, systemBeep:state.config.rfid_exit_alarm_system_beep, sound:state.config.rfid_exit_alarm_sound });
    }
  }catch(e){
    console.warn('rfid ausgangskontrolle nicht erreichbar', e);
  }
}
async function pollRFIDEvents(){
  if(!state.config.rfid_active) return;
  try{
    const r = await fetch('/api/rfid/events?after=' + encodeURIComponent(state.lastRfidEventId || 0), { cache:'no-store' });
    const j = await r.json();
    if(!j.ok || !Array.isArray(j.events)) return;
    state.rfidLastPollOk = Date.now();
    if(state.page === 'cart' && state.rfidSessionActive && state.rfidStatus !== 'active') state.rfidStatus = 'active';
    const autoStartByRfid = !!state.config.rfid_start_on_scan;
    const shoppingActive = state.rfidSessionActive && (state.page === 'cart' || (state.page === 'start' && autoStartByRfid));
    const jobs = [];
    for(const ev of j.events){
      state.lastRfidEventId = Math.max(Number(state.lastRfidEventId || 0), Number(ev.id || 0));
      if(Number(ev.status || 0) !== 1 || !ev.tag) continue;
      if(isExitAlarmEvent(ev)){
        jobs.push(scanRFIDExitAlarm(ev.tag, Number(ev.antenna || 0)));
        continue;
      }
      if(!shoppingActive) continue;
      if(state.page === 'start' && autoStartByRfid){
        state.page = 'cart';
        state.scanMessage = 'Artikel wird gelesen ...';
        render();
      }
      if(rfidIgnoredUntil[tagKey(ev.tag)] && Date.now() < rfidIgnoredUntil[tagKey(ev.tag)]) continue;
      jobs.push(scanRFID(ev.tag, Number(ev.antenna || 0)));
    }
    if(jobs.length) await Promise.allSettled(jobs);
  }catch(e){
    console.warn('rfid events nicht erreichbar', e);
  }
}
let scannerCommitTimer = null;
let scannerGlobalBuffer = '';
let scannerGlobalTimer = null;

function focusScanner(){
  setTimeout(() => $('scannerInput')?.focus(), 100);
}

function submitScannerValue(value, force){
  const raw = String(value || '').toUpperCase().replace(/[^0-9A-F]/g, '');
  const needLen = Number(state.config.rfid_tag_length || 24);
  clearTimeout(scannerCommitTimer);

  if(looksLikeRfidTag(raw)){
    const tag = raw.substring(0, needLen);
    if(state.rfidSessionActive && state.page === 'cart') scanRFID(tag);
    return '';
  }

  if(/^\d{13}$/.test(raw)){
    if(state.page === 'cart' || (state.page === 'start' && !state.config.rfid_active)) scanEAN(raw);
    return '';
  }

  if(force && /^\d{8}$/.test(raw)){
    if(state.page === 'cart' || (state.page === 'start' && !state.config.rfid_active)) scanEAN(raw);
    return '';
  }
  if(force) return '';
  if(/^\d+$/.test(raw) && raw.length > 13 && !state.config.rfid_active) return '';
  return raw;
}

function scheduleScannerCommit(inp){
  clearTimeout(scannerCommitTimer);
  scannerCommitTimer = setTimeout(() => {
    inp.value = submitScannerValue(inp.value, true);
  }, 600);
}

document.addEventListener('DOMContentLoaded', () => {
  const inp = $('scannerInput');

  inp.addEventListener('keydown', e => {
    customerActivity();
    if(e.key === 'Enter' || e.key === 'Tab'){
      e.preventDefault();
      e.stopPropagation();
      inp.value = submitScannerValue(inp.value, true);
    }
  });

  inp.addEventListener('input', () => {
    customerActivity();
    inp.value = submitScannerValue(inp.value, false);
    if(inp.value) scheduleScannerCommit(inp);
  });

  // Handscanner senden wie eine sehr schnelle Tastatur. Dieser Fallback arbeitet
  // auch dann, wenn nach einer Touch-Eingabe gerade ein Button den Fokus besitzt.
  document.addEventListener('keydown', e => {
    customerActivity();
    if(e.target === inp || e.ctrlKey || e.altKey || e.metaKey) return;
    const tag = String(e.target?.tagName || '').toLowerCase();
    if(tag === 'input' || tag === 'textarea' || tag === 'select') return;

    if(e.key === 'Enter' || e.key === 'Tab'){
      clearTimeout(scannerGlobalTimer);
      if(scannerGlobalBuffer){
        e.preventDefault();
        scannerGlobalBuffer = submitScannerValue(scannerGlobalBuffer, true);
      }
      return;
    }

    if(!/^[0-9A-Fa-f]$/.test(e.key)) return;
    scannerGlobalBuffer += e.key.toUpperCase();
    clearTimeout(scannerGlobalTimer);
    scannerGlobalBuffer = submitScannerValue(scannerGlobalBuffer, false);
    if(scannerGlobalBuffer){
      scannerGlobalTimer = setTimeout(() => {
        scannerGlobalBuffer = submitScannerValue(scannerGlobalBuffer, true);
      }, 600);
    }
  }, true);

  document.body.addEventListener('click', e => {
    customerActivity();
    const r = e.target.closest('[data-remove]');
    if(r){ e.preventDefault(); e.stopPropagation(); removeItem(r.dataset.remove); return; }
    focusScanner();
  });
  boot();
});
