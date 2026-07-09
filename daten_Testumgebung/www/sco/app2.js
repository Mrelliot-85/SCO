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
    payment: 'Karte',
    coupon: 0,
    customerActive: false,
    ratings: [5, 5, 5, 5],
    scanMessage: 'Scanner bereit',
    theme: {
        customer: 'Herbst Hofladen',
        subtitle: 'Self-Checkout',
        phone: '06372 50940',
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
        rating_active: 1,
        rating_questions: ['Wie zufrieden sind Sie mit unserem Sortiment?', 'Wie zufrieden sind Sie mit der Abwicklung des Zahlvorgangs?', 'Wie gefällt Ihnen der Hofladen?', 'Wie bewerten Sie das Einkaufserlebnis insgesamt?']
    }
};
function $(id) {
    return document.getElementById(id)
}
function esc(s) {
    return String(s ?? '').replace(/[&<>\"]/g, c => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;'
        }
            [c]))
}
function money(v) {
    return Number(v || 0).toLocaleString('de-DE', {
        style: 'currency',
        currency: 'EUR'
    })
}
function total() {
    return state.items.reduce((s, x) => s + Number(x.gp || 0), 0)
}
function kgTotal() {
    return state.items.filter(x => String(x.unit).toLowerCase() === 'kg').reduce((s, x) => s + Number(x.qty || 0), 0)
}
function qtyText(x) {
    return String(x.unit).toLowerCase() === 'kg' ? Number(x.qty || 0).toLocaleString('de-DE', {
        minimumFractionDigits: 3,
        maximumFractionDigits: 3
    }) + ' kg' : x.qty + ' ' + (x.unit || 'Stck')
}
function icon(n) {
    return {
        scan: '▦',
        card: '💳',
        cash: '💶',
        cart: '🛒',
        receipt: '🧾',
        back: '←',
        trash: '⌫',
        close: '×',
        weight: '⚖',
        star: '★',
        ok: '✓'
    }
    [n] || '•'
}
function points(x) {
    return state.config.payment_customer ? Math.max(1, Math.round(Number(x.gp || 0))) : 0
}
function applyTheme() {
    document.documentElement.style.setProperty('--green', state.theme.green);
    document.documentElement.style.setProperty('--dark', state.theme.dark);
    document.documentElement.style.setProperty('--accent', state.theme.accent)
}
async function boot() {
    await loadConfig();
    await loadGroupsAndProducts();
    applyTheme();
    render();
    updateClock();
    setInterval(updateClock, 1000);
    focusScanner()
}
async function loadConfig() {
    try {
        const r = await fetch('/api/config');
        const c = await r.json();
        if (!c)
            return;
        state.theme.customer = c.customer || c.kunde || c.Kunde || state.theme.customer;
        state.theme.subtitle = c.subtitle || c.Subtitle || state.theme.subtitle;
        state.theme.phone = c.phone || c.telefon || c.Telefon || state.theme.phone;
        state.theme.logo = c.logo || state.theme.logo;
        state.theme.description = c.description || c.beschreibung || c.about || state.theme.description;
        if (c.theme) {
            state.theme.green = c.theme.green || state.theme.green;
            state.theme.dark = c.theme.dark || state.theme.dark;
            state.theme.accent = c.theme.accent || state.theme.accent
        }
        if (c.payment) {
            state.config.payment_cash = c.payment.cash ? 1 : 0;
            state.config.payment_ec = c.payment.ec ? 1 : 0;
            state.config.payment_customer = c.payment.customer ? 1 : 0;
            state.config.payment_coupon = c.payment.coupon ? 1 : 0
        }
        if (c.receipt)
            state.config.bon_auto_print = c.receipt.autoPrint ? 1 : 0;
        if (c.rating) {
            state.config.rating_active = c.rating.active ? 1 : 0;
            if (Array.isArray(c.rating.questions))
                state.config.rating_questions = c.rating.questions
        }
    } catch (e) {
        console.warn('config nicht geladen', e)
    }
}
async function loadGroupsAndProducts() {
    try {
        const gr = await fetch('/api/groups');
        const groups = await gr.json();
        state.groups = (Array.isArray(groups) ? groups : []).map(g => ({
                id: Number(g.id ?? g.wg ?? g.WG),
                name: g.name ?? g.WG_BEZ ?? g.wg_bez ?? 'Warengruppe',
                icon: g.icon || '▦'
            })).filter(g => g.id > 0);
        if (!state.selectedGroup && state.groups.length)
            state.selectedGroup = state.groups[0].id;
        state.products = [];
        for (const g of state.groups) {
            try {
                const pr = await fetch('/api/products?wg=' + encodeURIComponent(g.id));
                const arr = await pr.json();
                if (Array.isArray(arr)) {
                    arr.forEach(p => state.products.push({
                            group: Number(p.group ?? p.wg ?? g.id),
                            plu: Number(p.plu ?? p.ELENO ?? p.eleno),
                            id: p.id ?? p.ID,
                            name: p.name ?? p.BEZEICHNUNG ?? '',
                            note: p.note ?? p.name2 ?? p.BEZEICHNUNG2 ?? '',
                            unit: p.unit ?? p.ME_BEZ ?? 'Stck',
                            ep: Number(p.ep ?? p.price ?? p.PREIS ?? 0),
                            image: p.image || ''
                        }))
                }
            } catch (e) {
                console.warn('products wg ' + g.id, e)
            }
        }
    } catch (e) {
        console.warn('groups nicht geladen', e);
        state.groups = [];
        state.products = []
    }
}
function updateClock() {
    const c = $('clock');
    if (c)
        c.textContent = new Date().toLocaleTimeString('de-DE', {
            hour: '2-digit',
            minute: '2-digit'
        })
}
function currentStep() {
    return state.page === 'start' ? 1 : state.page === 'cart' ? 2 : state.page === 'payment' ? 3 : 4
}
function topBar() {
    const step = currentStep();
    return `<div class="topBar"><div class="progress">${[['Start', 1], ['Einkauf', 2], ['Zahlung', 3], ['Bon', 4]].map(x => `<button class="${step === x[1] ? 'active' : ''}" data-page="${x[1] === 1 ? 'start' : x[1] === 2 ? 'cart' : x[1] === 3 ? 'payment' : 'receipt'}"><b>${x[1]}</b>${x[0]}</button>`).join('')}</div><div class="headRight"><div id="clock"></div><small>☎ ${esc(state.theme.phone)}</small></div></div>`
}
function shopInfo() {
    return `<section class="shopInfo card"><img class="shopLogo" src="${esc(state.theme.logo)}" onerror="this.style.display='none'"><div><h2>${esc(state.theme.customer)}</h2><p>${esc(state.theme.description)}</p><small>${esc(state.theme.subtitle)}</small></div></section>`
}
function layout(content, cls = 'workPage') {
    $('app').innerHTML = `<div class="shell">${topBar()}<main class="${cls}">${content}</main>${modalHtml()}</div>`;
    updateClock();
    bind()
}
function render() {
    if (state.page === 'start')
        return layout(startHtml(), 'startPage');
    if (state.page === 'cart')
        return layout(cartHtml());
    if (state.page === 'payment')
        return layout(paymentHtml(), 'workPage paymentPage');
    if (state.page === 'receipt')
        return layout(receiptHtml(), 'workPage receiptPage');
    if (state.page === 'rating')
        return layout(ratingHtml(), 'workPage ratingPage')
}
function startHtml() {
    return `${shopInfo()}<section class="startHero card"><div class="badge">Schnell · Einfach · Übersichtlich</div><div class="heroText"><h1>Willkommen im SB-Shop</h1><p>Scannen Sie Ihre Artikel selbst, prüfen Sie den Einkauf und bezahlen Sie bequem direkt am Terminal.</p></div><button class="startBtn" data-page="cart">Einkauf starten →</button></section><section class="how card"><h2>So funktioniert Ihr Einkauf</h2><div class="steps"><div><i>▦</i><b>1. Artikel scannen</b><span>EAN-Code am Scanner einlesen oder Artikel ohne EAN auswählen.</span></div><div><i>💳</i><b>2. Einkauf prüfen</b><span>Summe kontrollieren und Zahlungsart auswählen.</span></div><div><i>🧾</i><b>3. Bon erhalten</b><span>Bon drucken, anzeigen oder später digital nutzen.</span></div></div></section>`
}
function cartHtml() {
    return `${shopInfo()}<section class="cartCard card"><div class="cartTop"><h1>${icon('cart')} Ihr Einkauf</h1><div class="pill">${state.items.length}<br>Artikel</div><div class="pill ok">${esc(state.scanMessage)}</div><button class="clear" data-action="clear">⌫ Alle entfernen</button></div><div class="cartHead"><div>Artikel</div><div>Preis</div><div>Menge</div><div>Gesamt</div><div></div></div><div class="cartRows">${state.items.length ? state.items.map(rowHtml).join('') : emptyHtml()}</div><div class="summary"><div><span>Gewicht gesamt</span><b>${kgTotal().toLocaleString('de-DE', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    })} kg</b></div><div><span>Artikel</span><b>${state.items.length}</b></div><div><span>Info</span><b>${esc(state.scanMessage)}</b></div><div><span>Gesamtsumme</span><b class="green">${money(total())}</b></div></div></section><div class="bottomActions"><button data-action="focus"><span>▦</span><b>Scanner</b><span>EAN scannen</span></button><button data-action="products"><span>▦</span><b>Artikel ohne EAN</b><span>Aus Liste wählen</span></button><button class="danger" data-action="cancel"><span>×</span><b>Abbrechen</b><span>Vorgang beenden</span></button><button class="payWide" data-page="payment">💳 Zahlen</button></div>`
}
function emptyHtml() {
    return `<div class="empty"><i>▦</i><h2>Scanner bereit</h2><p>Bitte scannen Sie einen Artikel oder wählen Sie „Artikel ohne EAN“.</p></div>`
}
function articlePic(x) {
    return x.image ? `<img src="${esc(x.image)}" onerror="this.remove();this.parentElement.textContent='${String(x.unit).toLowerCase() === 'kg' ? '⚖' : '🛒'}'">` : (String(x.unit).toLowerCase() === 'kg' ? '⚖' : '🛒')
}
function rowHtml(x, readonly = false) {
    return `<div class="row"><div class="art"><div class="pic">${articlePic(x)}</div><div><b>${esc(x.name)}</b><span>Artikel · PLU ${esc(x.plu)}</span></div></div><div>${money(x.ep)} / ${esc(x.unit)}</div><div>${qtyText(x)}</div><div class="green">${money(x.gp)}</div>${readonly ? `<div>${points(x) ? '+' + points(x) + 'P' : ''}</div>` : `<button class="rowDel" data-remove="${x.rowId}">×</button>`}</div>`
}
function paymentHtml() {
    const pay = Math.max(0, total() - state.coupon);
    return `${shopInfo()}<section class="review card"><div class="sectionTitle"><span>Einkauf prüfen</span><h1>Ihre Artikel</h1></div><div class="reviewList">${state.items.length ? state.items.map(x => rowHtml(x, true)).join('') : emptyHtml()}</div></section><section class="payPanel card"><div class="payTitle"><div><span>Zahlung</span><h1>Zahlungsmethode wählen</h1></div><button data-page="cart">← Zurück</button></div>${(state.config.payment_coupon || state.config.payment_customer) ? voucherHtml() : ''}<div class="sumPanel"><h3>Summe</h3>${line('Artikel', state.items.length)}${line('Gesamtgewicht', kgTotal().toLocaleString('de-DE', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }) + ' kg')}${line('Zwischensumme', money(total()))}${state.config.payment_coupon ? line('Gutschein', '- ' + money(state.coupon), 'green') : ''}<div class="payTotal"><b>Zu zahlen</b><strong>${money(pay)}</strong></div></div><h3>Zahlungsart</h3><div class="methods">${state.config.payment_ec ? method('Karte', 'card') : ''}${state.config.payment_cash ? method('Bargeld', 'cash') : ''}</div><button class="payFinal" data-page="receipt">${state.payment === 'Bargeld' ? '💶' : '💳'} ${money(pay)} zahlen</button></section>`
}
function line(l, v, c = '') {
    return `<div class="line"><span>${l}</span><b class="${c}">${v}</b></div>`
}
function method(l, i) {
    return `<button class="method ${state.payment === l ? 'active' : ''}" data-method="${l}"><i>${icon(i)}</i>${l}</button>`
}
function voucherHtml() {
    return `<div class="voucher"><h3>Gutschein / Kundenkarte</h3><div class="voucherBtns">${state.config.payment_coupon ? `<button data-action="toggleCoupon">Gutschein ${state.coupon ? 'entfernen' : 'scannen'}</button>` : ''}${state.config.payment_customer ? `<button data-action="toggleCustomer">Kundenkarte ${state.customerActive ? 'aktiv' : 'scannen'}</button>` : ''}</div><div class="voucherInfo"><div><span>Gutscheinwert</span><b>${money(state.coupon)}</b></div><div><span>Gesammelte Punkte</span><b>${state.customerActive ? state.items.reduce((s, x) => s + points(x), 0) + ' P' : 'nicht aktiv'}</b></div></div></div>`
}
function receiptHtml() {
    return `${shopInfo()}<section class="receiptCard card"><div class="success">✓</div><h1>Zahlung erfolgreich</h1><p>Bon anzeigen oder drucken.</p><div class="bonWrap"><div class="bon">${bonHtml()}</div></div><div class="receiptBtns"><button>🧾 Vorschau</button><button class="greenBtn" data-action="print">🖨 Bon drucken</button></div>${state.config.rating_active ? `<button class="rateBtn" data-page="rating">Einkauf bewerten</button>` : ''}<button class="plainBtn" data-page="start">Neuen Einkauf starten</button></section>`
}
function bonHtml() {
    const sum = total(),
    vat = sum * 0.07,
    net = sum - vat;
    return `<div class="bonCenter"><b>${esc(state.theme.customer)}</b><br>${esc(state.theme.phone)}<br>Bon Nr. 10415752-000128</div>${state.items.map(x => `<div class="bonItem"><b>${esc(x.name)}</b><div><span>${qtyText(x)} · ${money(x.ep)}</span><b>${money(x.gp)}</b></div></div>`).join('')}<div class="bonSum"><div><span>Netto</span><span>${money(net)}</span></div><div><span>MwSt.</span><span>${money(vat)}</span></div><div class="strong"><span>Summe</span><span>${money(sum)}</span></div></div>`
}
function ratingHtml() {
    const qs = state.config.rating_questions;
    return `${shopInfo()}<section class="ratingCard card"><h1>Ihre Meinung ist uns wichtig</h1>${qs.map((q, i) => `<div class="question"><b>${esc(q)}</b><div>${[1, 2, 3, 4, 5].map(n => `<button class="star ${n <= state.ratings[i] ? 'active' : ''}" data-rating="${i}:${n}">★</button>`).join('')}</div></div>`).join('')}<button class="payWide" data-page="start">Bewertung speichern</button></section>`
}
function modalHtml() {
    if (state.modal === 'products')
        return productModal();
    if (state.modal === 'qty')
        return qtyModal();
    if (state.modal === 'weight')
        return weightModal();
    return ''
}
function productModal() {
    const list = state.products.filter(p => Number(p.group) === Number(state.selectedGroup));
    return `<div class="modal"><div class="productModal card"><aside><h2>Warengruppen</h2><div class="groupList">${state.groups.map(g => `<button class="groupBtn ${g.id === state.selectedGroup ? 'active' : ''}" data-group="${g.id}">${esc(g.name)}</button>`).join('')}</div></aside><section><div class="modalTop"><div><h2>Artikel ohne EAN</h2><p>Warengruppe wählen und Artikel übernehmen.</p></div><button data-action="closeModal">← Zurück</button></div><div class="productGrid">${list.length ? list.map(p => `<button class="productBtn" data-product="${p.plu}"><div class="prodImg">${p.image ? `<img src="${esc(p.image)}" onerror="this.remove();this.parentElement.textContent='🛒'">` : '🛒'}</div><b>${esc(p.name)}</b><span>PLU ${p.plu} · ${esc(p.note || '')}</span><strong>${money(p.ep)} / ${esc(p.unit)}</strong></button>`).join('') : '<p>Keine Artikel in dieser Warengruppe gefunden.</p>'}</div></section></div></div>`
}
function qtyModal() {
    const p = state.selectedProduct;
    if (!p)
        return '';
    return `<div class="modal"><div class="dialog card"><div class="modalTop"><h2>${esc(p.name)}</h2><button data-action="closeModal">← Zurück</button></div><div class="qtyBox"><button data-action="qtyMinus">−</button><b>${state.qty}</b><button data-action="qtyPlus">+</button></div><div class="dialogSum"><span>Summe</span><b class="green">${money(state.qty * p.ep)}</b></div><button class="payWide" data-action="addQty">Übernehmen</button></div></div>`
}
function weightModal() {
    const p = state.selectedProduct;
    if (!p)
        return '';
    const q = Number(String(state.manualWeight).replace(',', '.')) || 0;
    return `<div class="modal"><div class="dialog card"><div class="modalTop"><h2>${esc(p.name)}</h2><button data-action="closeModal">← Zurück</button></div><div class="scaleBox"><span>Gewicht</span><b>${state.manualWeight} kg</b></div><input class="manualInput" id="weightInput" value="${esc(state.manualWeight)}"><div class="dialogSum"><span>Summe</span><b class="green">${money(q * p.ep)}</b></div><button class="payWide" data-action="addWeight">Übernehmen</button></div></div>`
}
function bind() {
    document.querySelectorAll('[data-page]').forEach(b => b.onclick = () => {
        state.page = b.dataset.page;
        if (state.page === 'start')
            state.items = [];
        render();
        focusScanner()
    });
    document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => action(b.dataset.action));
    document.querySelectorAll('[data-remove]').forEach(b => b.onclick = () => removeItem(b.dataset.remove));
    document.querySelectorAll('[data-method]').forEach(b => b.onclick = () => {
        state.payment = b.dataset.method;
        render()
    });
    document.querySelectorAll('[data-group]').forEach(b => b.onclick = () => {
        state.selectedGroup = Number(b.dataset.group);
        render()
    });
    document.querySelectorAll('[data-product]').forEach(b => b.onclick = () => selectProduct(Number(b.dataset.product)));
    document.querySelectorAll('[data-rating]').forEach(b => b.onclick = () => {
        const [i, n] = b.dataset.rating.split(':').map(Number);
        state.ratings[i] = n;
        render()
    });
    const wi = $('weightInput');
    if (wi)
        wi.oninput = () => state.manualWeight = wi.value
}
function action(a) {
    if (a === 'clear') {
        state.items = [];
        state.scanMessage = 'Scanner bereit';
        render()
    }
    if (a === 'focus')
        focusScanner();
    if (a === 'products') {
        state.modal = 'products';
        render()
    }
    if (a === 'closeModal') {
        state.modal = null;
        state.selectedProduct = null;
        render()
    }
    if (a === 'cancel') {
        state.items = [];
        state.page = 'start';
        render()
    }
    if (a === 'toggleCoupon') {
        state.coupon = state.coupon ? 0 : 5;
        render()
    }
    if (a === 'toggleCustomer') {
        state.customerActive = !state.customerActive;
        render()
    }
    if (a === 'qtyMinus') {
        state.qty = Math.max(1, state.qty - 1);
        render()
    }
    if (a === 'qtyPlus') {
        state.qty++;
        render()
    }
    if (a === 'addQty')
        addManualQty();
    if (a === 'addWeight')
        addManualWeight();
    if (a === 'print')
        window.print()
}
function selectProduct(plu) {
    const p = state.products.find(x => Number(x.plu) === Number(plu));
    if (!p)
        return;
    state.selectedProduct = p;
    state.qty = 1;
    state.manualWeight = '0,250';
    state.modal = String(p.unit).toLowerCase() === 'kg' ? 'weight' : 'qty';
    render()
}
function addManualQty() {
    const p = state.selectedProduct;
    if (!p)
        return;
    addItem({
        plu: p.plu,
        name: p.name,
        note: p.note,
        unit: p.unit,
        qty: state.qty,
        ep: p.ep,
        gp: state.qty * p.ep,
        image: p.image
    })
}
function addManualWeight() {
    const p = state.selectedProduct;
    if (!p)
        return;
    const q = Number(String(state.manualWeight).replace(',', '.')) || 0;
    addItem({
        plu: p.plu,
        name: p.name,
        note: p.note,
        unit: p.unit,
        qty: q,
        ep: p.ep,
        gp: q * p.ep,
        image: p.image
    })
}
function addItem(item) {
    item.rowId = Date.now() + Math.random();
    state.items.push(item);
    state.modal = null;
    state.selectedProduct = null;
    state.scanMessage = item.name + ' wurde hinzugefügt';
    state.page = 'cart';
    render();
    focusScanner()
}
function removeItem(id) {
    state.items = state.items.filter(x => String(x.rowId) !== String(id));
    render()
}
async function scanEAN(ean) {
    state.scanMessage = 'Scanne Artikel ...';
    render();
    try {
        const r = await fetch('/api/scan?ean=' + encodeURIComponent(ean));
        const j = await r.json();
        if (j.ok) {
            addItem({
                plu: j.plu,
                name: j.name,
                note: j.type === 'scale' ? 'Waagen-EAN' : 'EAN',
                unit: j.unit || 'Stck',
                qty: Number(j.qty || 1),
                ep: Number(j.ep || 0),
                gp: Number(j.gp || j.ep || 0),
                image: j.image || ''
            });
            return
        }
        state.scanMessage = j.message || 'Artikel nicht gefunden';
        render()
    } catch (e) {
        state.scanMessage = 'Scanner/API nicht erreichbar';
        render()
    }
}
function focusScanner() {
    setTimeout(() => $('scannerInput')?.focus(), 100)
}
document.addEventListener('DOMContentLoaded', () => {
    const inp = $('scannerInput');
    inp.addEventListener('input', e => {
        const v = e.target.value.replace(/\D/g, '');
        e.target.value = v;
        if (v.length === 8 || v.length === 13) {
            e.target.value = '';
            scanEAN(v)
        }
    });
    document.body.addEventListener('click', focusScanner);
    boot()
});