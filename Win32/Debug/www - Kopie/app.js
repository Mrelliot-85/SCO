const state = {
  page: 'start',
  items: [],
  config: {
    payment_cash: 1,
    payment_ec: 1,
    payment_customer: 1,
    payment_coupon: 1,
    bon_auto_print: 0
  },
  theme: {
    customer: 'Foodware SCO',
    subtitle: 'Self-Checkout',
    phone: '',
    green: '#107a2a',
    dark: '#101c29',
    dark2: '#0c1824',
    accent: '#f2b01e'
  },
  groups: [],
  products: [],
  selectedGroup: 0,
  coupon: 0,
  customerActive: false,
  payment: 'Karte',
  ratings: [5, 5, 5, 5],
  scanMessage: 'Scanner bereit',
  modal: null,
  selectedProduct: null,
  manualWeight: '0,250',
  qty: 1
};

const questions = [
  'Wie zufrieden sind Sie mit unserem Sortiment?',
  'Wie zufrieden sind Sie mit der Abwicklung des Zahlvorgangs?',
  'Wie gefällt Ihnen der Hofladen?',
  'Wie bewerten Sie das Einkaufserlebnis insgesamt?'
];

function $(id) {
  return document.getElementById(id);
}

function money(v) {
  return Number(v || 0).toLocaleString('de-DE', {
    style: 'currency',
    currency: 'EUR'
  });
}

function total() {
  return state.items.reduce((s, x) => s + Number(x.gp || 0), 0);
}

function kgTotal() {
  return state.items
    .filter(x => String(x.unit).toLowerCase() === 'kg')
    .reduce((s, x) => s + Number(x.qty || 0), 0);
}

function qtyText(x) {
  return String(x.unit).toLowerCase() === 'kg'
    ? Number(x.qty || 0).toLocaleString('de-DE', {
        minimumFractionDigits: 3,
        maximumFractionDigits: 3
      }) + ' kg'
    : Number(x.qty || 0).toLocaleString('de-DE') + ' ' + x.unit;
}

function points(x) {
  return Math.max(1, Math.round(Number(x.gp || 0)));
}

function icon(n) {
  return {
    scan: '▣',
    card: '▰',
    cash: '€',
    user: '◎',
    gift: '◇',
    receipt: '▤',
    printer: '▥',
    weight: '⚖',
    grid: '▦',
    arrow: '→',
    back: '←',
    close: '×',
    trash: '⌫',
    help: '?',
    star: '★'
  }[n] || '•';
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"]/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;'
  }[c]));
}

async function boot() {
  state.groups = [];
  state.products = [];

  try {
    const r = await fetch('/api/config');
    const c = await r.json();

   if (c) {
  state.theme.customer =
    c.customer || c.kunde || c.Kunde || state.theme.customer;

  state.theme.subtitle =
    c.subtitle || c.Subtitle || state.theme.subtitle;

  state.theme.phone =
    c.phone || c.telefon || c.Telefon || state.theme.phone;

  state.theme.logo =
    c.logo || '';

  if (c.theme) {
    state.theme.green = c.theme.green || state.theme.green;
    state.theme.dark = c.theme.dark || state.theme.dark;
    state.theme.dark2 = c.theme.dark2 || state.theme.dark2;
    state.theme.accent = c.theme.accent || state.theme.accent;
  }

  if (c.payment) {
    state.config.payment_cash = c.payment.cash ? 1 : 0;
    state.config.payment_ec = c.payment.ec ? 1 : 0;
    state.config.payment_customer = c.payment.customer ? 1 : 0;
    state.config.payment_coupon = c.payment.coupon ? 1 : 0;
  }

  if (c.receipt) {
    state.config.bon_auto_print = c.receipt.autoPrint ? 1 : 0;
  }
}
  } catch (e) {
    console.warn('Config konnte nicht geladen werden', e);
  }

  await loadGroupsAndProducts();

  applyTheme();
  render();
  focusScanner();
  setInterval(updateClock, 1000);
  updateClock();
}

function applyTheme() {
  document.documentElement.style.setProperty('--green', state.theme.green);
  document.documentElement.style.setProperty('--dark', state.theme.dark);
  document.documentElement.style.setProperty('--dark2', state.theme.dark2);
  document.documentElement.style.setProperty('--accent', state.theme.accent);
}

async function loadGroupsAndProducts() {
  try {
    const gr = await fetch('/api/groups');
    const groups = await gr.json();

    state.groups = groups.map(g => ({
      id: Number(g.wg),
      name: g.name,
      icon: groupIcon(g.name)
    }));

    if (state.groups.length > 0) {
      state.selectedGroup = state.groups[0].id;
      await loadProductsForGroup(state.selectedGroup);
    }
  } catch (e) {
    state.groups = [];
    state.products = [];
    state.scanMessage = 'Warengruppen konnten nicht geladen werden';
  }
}

async function loadProductsForGroup(wg) {
  try {
    const pr = await fetch('/api/products?wg=' + encodeURIComponent(wg));
    const products = await pr.json();

state.products = products.map(p => ({
  id: Number(p.id || 0),
  image: p.image || '',
  group: Number(p.wg),
  plu: Number(p.plu),
  name: p.name || '',
  note: p.note || p.name2 || '',
  unit: p.unit || 'Stck',
  ep: Number(p.price || p.ep || 0)
}));
  } catch (e) {
    state.products = [];
    state.scanMessage = 'Artikel konnten nicht geladen werden';
  }
}

function groupIcon(name) {
  const n = String(name || '').toLowerCase();
  if (n.includes('fleisch')) return '🥩';
  if (n.includes('wurst')) return '🌭';
  if (n.includes('salat')) return '🥗';
  if (n.includes('käse') || n.includes('kaese')) return '🧀';
  if (n.includes('grill')) return '🔥';
  if (n.includes('pflanz')) return '🌱';
  if (n.includes('buch')) return '📚';
  if (n.includes('dünger') || n.includes('duenger')) return '🌿';
  return '🛒';
}

function updateClock() {
  const el = $('clockTime');
  if (el) {
    el.textContent = new Date().toLocaleTimeString('de-DE', {
      hour: '2-digit',
      minute: '2-digit'
    });
  }
}

function pageTitle() {
  if (state.page === 'start') return ['Willkommen', 'Self-Checkout', 'scan'];
  if (state.page === 'cart') return ['Artikel scannen', 'EAN / Barcode', 'scan'];
  if (state.page === 'payment') return ['Zahlung', 'Einkauf prüfen', 'card'];
  if (state.page === 'receipt') return ['Bon', 'Zahlung erfolgreich', 'receipt'];
  return ['Bewertung', 'Vielen Dank', 'star'];
}

function layout(content) {
  const p = pageTitle();

  $('app').innerHTML = `
    <div class="app">
      <header class="topbar">
        <div class="brand">
          <div class="brandIcon">⚖</div>
          <div>
            <div class="brandTitle">${esc(state.theme.customer)}</div>
            <div class="brandSub">${esc(state.theme.subtitle)}</div>
          </div>
        </div>

        <div class="pageInfo">
          <div class="pageIcon">${icon(p[2])}</div>
          <div>
            <div class="pageTitle">${p[0]}</div>
            <div class="pageSub">${p[1]}</div>
          </div>
        </div>

        <div class="clock">
          <div class="clockTime" id="clockTime"></div>
          <div class="phone">☎ ${esc(state.theme.phone)}</div>
        </div>
      </header>

      <main class="main">${content}</main>
      ${modalHtml()}
    </div>
  `;

  updateClock();
  bind();
}

function render() {
  if (state.page === 'start') return layout(startHtml());
  if (state.page === 'cart') return layout(cartHtml());
  if (state.page === 'payment') return layout(paymentHtml());
  if (state.page === 'receipt') return layout(receiptHtml());
  if (state.page === 'rating') return layout(ratingHtml());
}

function startHtml() {
  return `
    <div class="startMain">
      <section class="startGrid">
        <div class="card startCard">
          <div class="badge">Schnell · Einfach · Übersichtlich</div>
          <div class="startTitle">Willkommen im SB-Shop</div>
          <p class="startText">So funktioniert Ihr Einkauf:</p>

          <div class="steps">
            ${step('scan', '1. Scannen', 'EAN-Code scannen oder Artikel ohne EAN auswählen.')}
            ${step('card', '2. Zahlen', 'Einkauf prüfen, Gutschein/Kundenkarte nutzen, Zahlungsart wählen.')}
            ${step('printer', '3. Bon', 'Bon anzeigen oder drucken. Danach optional bewerten.')}
          </div>

          <button class="startBtn" data-page="cart">
            Einkauf starten ${icon('arrow')}
          </button>
        </div>

        <aside class="card logoCard">
			<div class="logoBox">
			  ${
				state.theme.logo
				  ? `<img class="customerLogo" src="${esc(state.theme.logo)}">`
				  : `
					<div class="logoSmall">Kundenlogo</div>
					<div class="logoName">${esc(state.theme.customer)}</div>
				  `
			  }
			</div>
        </aside>
      </section>
    </div>
  `;
}

function step(i, t, x) {
  return `
    <div class="step">
      <div class="stepIcon">${icon(i)}</div>
      <div class="stepTitle">${t}</div>
      <div class="stepText">${x}</div>
    </div>
  `;
}

function cartHtml() {
  return `
    <div class="cartMain">
      <section class="card cartPanel">
        <div class="panelHead">
          <div class="headLeft">
            <div class="headIcon">${icon('scan')}</div>
            <h2 class="h2">Ihr Einkauf</h2>
            <span class="pill">${state.items.length} Artikel</span>
            <span class="scanMsg">${esc(state.scanMessage)}</span>
          </div>
          <button class="clearBtn" data-action="clear">${icon('trash')} Alle entfernen</button>
        </div>

        <div class="cartHeader">
          <div>Artikel</div>
          <div class="right">Preis</div>
          <div class="right">Menge</div>
          <div class="right">Gesamt</div>
          <div></div>
        </div>

        <div class="cartList">
          ${state.items.map(rowHtml).join('') || emptyCartHtml()}
        </div>

        <div class="summary">
          <div class="sumBox">
            <div class="sumLabel">Gewicht gesamt</div>
            <div class="sumValue">${kgTotal().toLocaleString('de-DE', { minimumFractionDigits: 2 })} kg</div>
          </div>
          <div class="sumBox">
            <div class="sumLabel">Artikel</div>
            <div class="sumValue">${state.items.length}</div>
          </div>
          <div class="sumBox">
            <div class="sumLabel">Info</div>
            <div class="sumValue small">${state.customerActive ? 'Kundenkarte aktiv' : state.coupon ? 'Gutschein aktiv' : 'Scanner bereit'}</div>
          </div>
          <div class="sumBox">
            <div class="sumLabel">Gesamtsumme</div>
            <div class="sumValue green">${money(total())}</div>
          </div>
        </div>
      </section>

      <div class="bottomNav">
        ${tool('scan', 'Scanner', 'EAN scannen', 'focus')}
        ${tool('grid', 'Artikel ohne EAN', 'Aus Liste wählen', 'products')}
        ${state.config.payment_customer ? tool('user', 'Kundenkarte', 'Info / Punkte', 'customer') : ''}
        ${state.config.payment_coupon ? tool('gift', 'Gutschein', 'Info / Guthaben', 'coupon') : ''}
        ${tool('close', 'Abbrechen', 'Vorgang beenden', 'cancel', 'dangerText')}
        <button class="payBtn" data-page="payment">${icon('card')} Zahlen</button>
      </div>
    </div>
  `;
}

function emptyCartHtml() {
  return `
    <div class="emptyCart">
      <div class="emptyIcon">${icon('scan')}</div>
      <div class="emptyTitle">Scanner bereit</div>
      <div class="emptyText">Bitte scannen Sie einen Artikel oder wählen Sie „Artikel ohne EAN“.</div>
    </div>
  `;
}

function tool(i, t, s, a, cls = '') {
  return `
    <button class="toolBtn" data-action="${a}">
      <span class="toolIcon ${cls}">${icon(i)}</span>
      <span class="toolText">${t}<br><span class="toolSub">${s}</span></span>
    </button>
  `;
}

function rowHtml(x, readonly = false, pts = false) {
  return `
    <div class="cartRow" data-row="${x.rowId}">
      <div class="articleCell">
       <div class="articlePic">
		  ${x.image
  		  ? `<img src="${esc(x.image)}"
        	    onerror="this.parentElement.innerHTML='${String(x.unit).toLowerCase()==='kg'?'⚖':'🛒'}'">`
   		 : (String(x.unit).toLowerCase() === 'kg' ? '⚖' : '🛒')}
		</div>
        <div>
          <div class="articleName">${esc(x.name)}</div>
          <div class="articleMeta">${esc(x.note || 'Artikel')} · PLU ${esc(x.plu)}</div>
        </div>
      </div>
      <div class="priceCell right">${money(x.ep)} / ${esc(x.unit)}</div>
      <div class="priceCell right">${qtyText(x)}</div>
      <div class="totalCell right">${money(x.gp)}</div>
      ${readonly
        ? `<div class="right totalCell">${pts ? '+' + points(x) + 'P' : ''}</div>`
        : `<button class="rowDel" data-remove="${x.rowId}">×</button>`}
    </div>
  `;
}

function paymentHtml() {
  const sum = total();
  const pay = Math.max(0, sum - state.coupon);
  const pts = state.items.reduce((s, x) => s + points(x), 0);

  return `
    <div class="paymentMain">
      <section class="card reviewPanel">
        <div class="panelHead">
          <div>
            <div class="overline">Seite 3</div>
            <h2 class="h2">Einkauf prüfen</h2>
          </div>
        </div>

        <div class="cartHeader paymentCartHeader">
          <div>Artikel</div>
          <div class="right">Preis</div>
          <div class="right">Menge</div>
          <div class="right">Gesamt</div>
          <div class="right">Punkte</div>
        </div>

        <div class="cartList">
          ${state.items.map(x => rowHtml(x, true, state.customerActive)).join('') || emptyCartHtml()}
        </div>
      </section>

      <aside class="card payAside">
        <div class="payHead">
          <div>
            <div class="overline">Zahlung</div>
            <div class="payTitle">Zahlungsmethode wählen</div>
          </div>
          <button class="backBtn" data-page="cart">${icon('back')} Zurück</button>
        </div>

        <div class="box boxGrey">
          <div class="boxTitle">Gutschein / Kundenkarte</div>
          <div class="twoGrid">
            ${state.config.payment_coupon ? `<button class="smallAction" data-action="toggleCoupon">${icon('gift')} Gutschein ${state.coupon ? 'entfernen' : 'scannen'}</button>` : ''}
            ${state.config.payment_customer ? `<button class="smallAction" data-action="toggleCustomer">${icon('user')} Kundenkarte ${state.customerActive ? 'aktiv' : 'scannen'}</button>` : ''}
          </div>

          <div class="twoGrid marginTop">
            <div class="infoCard">
              <div class="infoLabel">Gutscheinwert</div>
              <div class="infoValue green">${state.coupon ? '- ' + money(state.coupon) : '0,00 €'}</div>
            </div>
            <div class="infoCard">
              <div class="infoLabel">Gesammelte Punkte</div>
              <div class="infoValue green">${state.customerActive ? '+ ' + pts + ' P' : 'nicht aktiv'}</div>
            </div>
          </div>
        </div>

        <div class="box">
          <div class="boxTitle">Summe</div>
          ${line('Artikel', state.items.length)}
          ${line('Gesamtgewicht', kgTotal().toLocaleString('de-DE', { minimumFractionDigits: 2 }) + ' kg')}
          ${line('Zwischensumme', money(sum))}
          ${line('Gutschein', '- ' + money(state.coupon), 'green')}
          <div class="payTotal">
            <div class="payTotalLabel">Zu zahlen</div>
            <div class="payTotalValue">${money(pay)}</div>
          </div>
        </div>

        <div class="boxTitle paymentMethodTitle">Zahlungsart</div>
        <div class="payMethods">
          ${state.config.payment_ec ? method('Karte', 'card') : ''}
          ${state.config.payment_cash ? method('Bargeld', 'cash') : ''}
          ${state.config.payment_customer ? method('Kundenkonto', 'user') : ''}
          ${state.config.payment_coupon ? method('Gutschein', 'gift') : ''}
        </div>

        <button class="payFinal" data-page="receipt">${icon('card')} ${money(pay)} zahlen</button>
      </aside>
    </div>
  `;
}

function line(l, v, c = '') {
  return `<div class="line"><span>${l}</span><b class="${c}">${v}</b></div>`;
}

function method(l, i) {
  return `
    <button class="methodBtn ${state.payment === l ? 'active' : ''}" data-method="${l}">
      <span>${icon(i)}</span>${l}
    </button>
  `;
}

function receiptHtml() {
  return `
    <div class="receiptMain">
      <section class="card centerCard">
        <div class="successIcon">${icon('receipt')}</div>
        <div class="successTitle">Zahlung erfolgreich</div>
        <div class="successText">Bon anzeigen oder drucken.</div>

        <div class="receiptButtons">
          <button class="receiptBtn">${icon('receipt')} Vorschau</button>
          <button class="receiptBtn print" data-action="print">${icon('printer')} Bon drucken</button>
        </div>

        <button class="rateBtn" data-page="rating">Einkauf bewerten</button>
        <button class="newBtn" data-page="start">Neuen Einkauf starten</button>
      </section>

      <aside class="bonPreview">
        <div class="bonPaper">${bonHtml()}</div>
      </aside>
    </div>
  `;
}

function bonHtml() {
  const sum = total();
  const vat = sum * 0.07;
  const net = sum - vat;

  return `
    <div class="bonCenter">
      <b>${esc(state.theme.customer)}</b><br>
      ${esc(state.theme.phone)}<br>
      Bon Nr. 10415752-000128
    </div>

    ${state.items.map(x => `
      <div class="bonItem">
        <b>${esc(x.name)}</b>
        <div class="bonLine">
          <span>${qtyText(x)} · ${money(x.ep)} / ${esc(x.unit)}</span>
          <b>${money(x.gp)}</b>
        </div>
      </div>
    `).join('')}

    <div class="bonSumBlock">
      <div class="bonLine"><span>Netto</span><span>${money(net)}</span></div>
      <div class="bonLine"><span>MwSt.</span><span>${money(vat)}</span></div>
      <div class="bonLine bonSum"><span>Summe</span><span>${money(sum)}</span></div>
    </div>
  `;
}

function ratingHtml() {
  return `
    <div class="ratingMain">
      <div class="ratingWrap">
        <div class="ratingTitle">Ihre Meinung ist uns wichtig</div>
        <div class="ratingSub">Bewerten Sie optional bis zu 4 Fragen.</div>

        ${questions.map((q, i) => `
          <div class="question">
            <b>${q}</b>
            <div class="stars">
              ${[1, 2, 3, 4, 5].map(n => `
                <button class="${n <= state.ratings[i] ? 'active' : ''}" data-rating="${i}:${n}">
                  ${icon('star')}
                </button>
              `).join('')}
            </div>
          </div>
        `).join('')}

        <div class="twoGrid ratingButtons">
          <button class="smallAction" data-page="start">Überspringen</button>
          <button class="smallAction saveRating" data-page="start">Bewertung speichern</button>
        </div>
      </div>
    </div>
  `;
}

function modalHtml() {
  if (state.modal === 'products') return productModal();
  if (state.modal === 'weight') return weightModal();
  if (state.modal === 'qty') return qtyModal();
  return '';
}

function productModal() {
  const list = state.products.filter(p => Number(p.group) === Number(state.selectedGroup)).slice(0, 20);

  return `
    <div class="modalBackdrop">
      <div class="modal">
        <aside class="modalSide">
          <div class="modalTop">
            <div class="modalTitle">Warengruppen</div>
            <button class="rowDel modalClose" data-action="closeModal">×</button>
          </div>

          <div class="groupList">
            ${state.groups.map(g => `
              <button class="groupBtn ${Number(g.id) === Number(state.selectedGroup) ? 'active' : ''}" data-group="${g.id}">
                ${g.icon || ''} ${esc(g.name)}
              </button>
            `).join('') || '<div class="emptyModal">Keine Warengruppen gefunden</div>'}
          </div>
        </aside>

        <section class="productArea">
          <div class="modalTitle">Artikel ohne EAN auswählen</div>
          <div class="articleMeta">Bei kg-Artikeln öffnet sich Gewichtseingabe/Waage. Bei Stück-Artikeln Mengeneingabe.</div>

        <div class="productGrid">
  ${list.map(p => `
    <button class="productBtn" data-product="${p.plu}">
      <div class="productImgWrap">
        <img src="${esc(p.image || '')}"
             onerror="this.style.display='none';this.parentElement.classList.add('noimg')">
      </div>

      <div class="productName">${esc(p.name)}</div>

      <div class="productMeta">
        PLU ${p.plu} · ${esc(p.note || '')}
      </div>

      <div class="productPrice">
        ${money(p.ep)} / ${esc(p.unit)}
      </div>
    </button>
  `).join('')}
</div>
        </section>
      </div>
    </div>
  `;
}

function weightModal() {
  const p = state.selectedProduct;
  if (!p) return '';

  const q = Number(String(state.manualWeight).replace(',', '.')) || 0;

  return `
    <div class="modalBackdrop">
      <div class="dialog">
        <div class="dialogHead">
          <div class="dialogTitle">Gewicht für ${esc(p.name)}</div>
          <button class="rowDel modalClose" data-action="closeModal">×</button>
        </div>

        <div class="dialogBody">
          <div class="modeGrid">
            <button class="modeBtn active">${icon('weight')} Von Waage holen</button>
            <button class="modeBtn">Manuell eingeben</button>
          </div>

          <div class="scaleBox">
            <div class="scaleLabel">Aktuelles Waagengewicht</div>
            <div class="scaleValue">${esc(state.manualWeight)} kg</div>
          </div>

          <input class="manualInput" id="weightInput" value="${esc(state.manualWeight)}">

          <div class="dialogSum">
            <span>Summe</span>
            <b class="green">${money(q * p.ep)}</b>
          </div>

          <button class="dialogAdd" data-action="addWeight">In den Warenkorb übernehmen</button>
        </div>
      </div>
    </div>
  `;
}

function qtyModal() {
  const p = state.selectedProduct;
  if (!p) return '';

  return `
    <div class="modalBackdrop">
      <div class="dialog">
        <div class="dialogHead">
          <div class="dialogTitle">Menge für ${esc(p.name)}</div>
          <button class="rowDel modalClose" data-action="closeModal">×</button>
        </div>

        <div class="dialogBody">
          <div class="qtyBox">
            <button class="qtyBtn" data-action="qtyMinus">−</button>
            <div class="qtyValue">${state.qty}</div>
            <button class="qtyBtn" data-action="qtyPlus">+</button>
          </div>

          <div class="dialogSum">
            <span>Summe</span>
            <b class="green">${money(state.qty * p.ep)}</b>
          </div>

          <button class="dialogAdd" data-action="addQty">In den Warenkorb übernehmen</button>
        </div>
      </div>
    </div>
  `;
}

function bind() {
  document.querySelectorAll('[data-page]').forEach(b => {
    b.onclick = () => {
      state.page = b.dataset.page;

      if (state.page === 'start') {
        state.items = [];
        state.coupon = 0;
        state.customerActive = false;
        state.scanMessage = 'Scanner bereit';
      }

      render();
      focusScanner();
    };
  });

  document.querySelectorAll('[data-action]').forEach(b => {
    b.onclick = () => action(b.dataset.action);
  });

  document.querySelectorAll('[data-remove]').forEach(b => {
    b.onclick = () => removeItem(b.dataset.remove);
  });

  document.querySelectorAll('[data-method]').forEach(b => {
    b.onclick = () => {
      state.payment = b.dataset.method;
      render();
    };
  });

  document.querySelectorAll('[data-group]').forEach(b => {
    b.onclick = async () => {
      state.selectedGroup = Number(b.dataset.group);
      await loadProductsForGroup(state.selectedGroup);
      render();
    };
  });

  document.querySelectorAll('[data-product]').forEach(b => {
    b.onclick = () => selectProduct(Number(b.dataset.product));
  });

  document.querySelectorAll('[data-rating]').forEach(b => {
    b.onclick = () => {
      const [i, n] = b.dataset.rating.split(':').map(Number);
      state.ratings[i] = n;
      render();
    };
  });

  const wi = $('weightInput');
  if (wi) {
    wi.oninput = () => {
      state.manualWeight = wi.value;
      render();
    };
    wi.focus();
    wi.select();
  }
}

function action(a) {
  if (a === 'clear') {
    state.items = [];
    render();
  }

  if (a === 'focus') {
    focusScanner();
  }

  if (a === 'products') {
    state.modal = 'products';
    render();
  }

  if (a === 'closeModal') {
    state.modal = null;
    state.selectedProduct = null;
    render();
  }

  if (a === 'customer') {
    state.customerActive = true;
    state.scanMessage = 'Kundenkarte aktiv: Punkte werden gesammelt';
    render();
  }

  if (a === 'coupon') {
    state.coupon = 5;
    state.scanMessage = 'Gutschein erkannt: 5,00 € Guthaben';
    render();
  }

  if (a === 'toggleCoupon') {
    state.coupon = state.coupon ? 0 : 5;
    render();
  }

  if (a === 'toggleCustomer') {
    state.customerActive = !state.customerActive;
    render();
  }

  if (a === 'cancel') {
    state.items = [];
    state.page = 'start';
    render();
  }

  if (a === 'qtyMinus') {
    state.qty = Math.max(1, state.qty - 1);
    render();
  }

  if (a === 'qtyPlus') {
    state.qty++;
    render();
  }

  if (a === 'addQty') addManualQty();
  if (a === 'addWeight') addManualWeight();
  if (a === 'print') window.print();
}

function removeItem(id) {
  const row = document.querySelector(`[data-row="${id}"]`);

  if (row) {
    row.classList.add('remove');

    setTimeout(() => {
      state.items = state.items.filter(x => String(x.rowId) !== String(id));
      render();
    }, 220);
  } else {
    state.items = state.items.filter(x => String(x.rowId) !== String(id));
    render();
  }
}

function selectProduct(plu) {
  const p = state.products.find(x => Number(x.plu) === Number(plu));
  if (!p) return;

  state.selectedProduct = p;
  state.modal = String(p.unit).toLowerCase() === 'kg' ? 'weight' : 'qty';
  state.qty = 1;
  state.manualWeight = '0,250';

  render();
}

function addManualWeight() {
  const p = state.selectedProduct;
  const q = Number(String(state.manualWeight).replace(',', '.')) || 0;

  if (!p || q <= 0) return;

  addItem({
    plu: p.plu,
    name: p.name,
    note: p.note || 'Frisch',
    unit: p.unit,
    qty: q,
    ep: p.ep,
    gp: q * p.ep,
    source: 'manuell',
image: p.image || '',
id: p.id || 0
  });
}

function addManualQty() {
  const p = state.selectedProduct;
  const q = state.qty;

  if (!p || q <= 0) return;

  addItem({
    plu: p.plu,
    name: p.name,
    note: p.note || 'Artikel',
    unit: p.unit,
    qty: q,
    ep: p.ep,
    gp: q * p.ep,
    source: 'manuell',
image: p.image || '',
id: p.id || 0
  });
}

function addItem(item) {
  item.rowId = Date.now() + Math.random();

  state.items.push(item);
  state.modal = null;
  state.selectedProduct = null;
  state.scanMessage = `${item.name} wurde hinzugefügt`;

  render();
  focusScanner();
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
        unit: j.unit || 'Stk.',
        qty: Number(j.qty || 1),
        ep: Number(j.ep || 0),
        gp: Number(j.gp || j.ep || 0),
        source: j.type || 'scan',image: p.image || '',
id: p.id || 0
      });
      return;
    }

    state.scanMessage = j.message || 'Artikel nicht gefunden';
    render();
  } catch (e) {
    state.scanMessage = 'Scanner/API nicht erreichbar';
    render();
  }
}

function focusScanner() {
  setTimeout(() => {
    $('scannerInput')?.focus();
  }, 100);
}

const scanner = $('scannerInput');
if (scanner) {
  scanner.addEventListener('input', e => {
    const v = e.target.value.replace(/\D/g, '');
    e.target.value = v;

    if (v.length === 8 || v.length === 13) {
      e.target.value = '';
      scanEAN(v);
    }
  });
}

document.body.addEventListener('click', () => focusScanner());

boot();
