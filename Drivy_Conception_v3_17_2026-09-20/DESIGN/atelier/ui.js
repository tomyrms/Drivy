/* Drivy UI primitives. One implementation per semantic action, shared by map and workspace.
   attrs/content are trusted renderer output; all fixture and user text is escaped at boundaries. */
const UI = {
  button(label, attrs='', variant='primary', glyph=null, extraClass='') {
    return `<button class="ui-button ${variant} ${extraClass}" data-component="DS02" ${attrs}>${glyph?icon(glyph):''}<span>${e(label)}</span></button>`;
  },
  iconButton(glyph,label,attrs='') {
    return `<button class="round ui-icon-button" data-component="DS02" aria-label="${e(label)}" ${attrs}>${icon(glyph)}</button>`;
  },
  statusAction(k,attrs='') {
    const v=statuses[k]; if(!v)throw new Error('Unknown pedagogical observation status');
    return `<button class="status-option" data-component="DS07.status-action" ${attrs} aria-label="${e(v.label)}, enregistrer l’observation privée"><span class="tone-icon ${k}">${icon(v.icon)}</span><span class="label">${e(v.label)}</span></button>`;
  },
  observationRow(x,{attrs='',selection=false,checked=false,readOnly=false,shared=false}={}) {
    const meta=`${fmt(x.second)} · ${statusTitle(x)}${x.anchor?'':' · Sans position'}`;
    const inner=`${themeTone(x)}<span class="rowtext"><strong>${e(themeTitle(x))}</strong><small>${e(meta)}</small>${shared&&x.note?`<span class="row-note">${e(x.note)}</span>`:''}</span>${selection?`<span class="selection-indicator ${checked?'checked':''}" aria-hidden="true">${checked?icon('check'):''}</span>`:readOnly?'':icon('chevron','last')}`;
    return readOnly?`<div class="private-row" data-component="DS07.observation-row">${inner}</div>`:`<button class="private-row" data-component="DS07.observation-row" ${attrs} ${selection?`aria-pressed="${checked}"`:''}>${inner}</button>`;
  },
  row(title,meta='',{attrs='',glyph=null,leading='',trailing='',selected=false,action='navigate'}={}) {
    const inside=`${leading|| (glyph?`<span class="row-icon">${icon(glyph)}</span>`:'')}<span class="rowtext"><strong>${e(title)}</strong>${meta?`<small>${e(meta)}</small>`:''}</span>${trailing}${action==='navigate'?icon('chevron','last'):''}`;
    return action==='read'?`<div class="ui-row" data-component="DS25">${inside}</div>`:`<button class="ui-row ${selected?'selected':''}" data-component="DS25" data-row-action="${action}" ${attrs} ${action==='select'?`aria-pressed="${selected}"`:''}>${inside}</button>`;
  },
  field(id,label,value='',{type='text',multiline=false,options=null,attrs='',error='',hint=''}={}) {
    const common=`id="${e(id)}" ${attrs} ${error?`aria-invalid="true" aria-describedby="${e(id)}-error"`:hint?`aria-describedby="${e(id)}-hint"`:''}`;
    const input=options?`<select ${common}>${options.map(o=>`<option value="${e(o.value)}" ${String(o.value)===String(value)?'selected':''}>${e(o.label)}</option>`).join('')}</select>`:multiline?`<textarea ${common} rows="3">${e(value)}</textarea>`:`<input ${common} type="${e(type)}" value="${e(value)}">`;
    return `<div class="ui-field" data-component="DS03" data-variant="${multiline?'multiline':options?'choice':'single'}"><label for="${e(id)}">${e(label)}</label>${input}${error?`<p class="field-error" id="${e(id)}-error">${e(error)}</p>`:''}${hint?`<p class="ui-caption" id="${e(id)}-hint">${e(hint)}</p>`:''}</div>`;
  },
  search(id,label,value='',attrs='') {
    return `<div class="ui-search" data-component="DS03.search"><label class="sr-only" for="${e(id)}">${e(label)}</label>${icon('search')}<input type="search" id="${e(id)}" value="${e(value)}" placeholder="${e(label)}" autocomplete="off" ${attrs}></div>`;
  },
  state(text,kind='neutral',attrs='') {
    return `<div class="ui-notice ${kind}" data-component="${kind==='error'?'DS10':'DS08'}" role="${kind==='error'?'alert':'status'}">${icon(kind==='error'?'attention':kind==='success'?'check':kind==='offline'?'offline':'info')}<span>${e(text)}</span>${attrs}</div>`;
  },
  empty(title,detail='',action='') {
    return `<section class="ui-empty" data-component="DS09">${icon('list')}<h2>${e(title)}</h2>${detail?`<p>${e(detail)}</p>`:''}${action}</section>`;
  },
  section(title,content,action='') {
    return `<section class="ui-section"><div class="section-heading"><h2>${e(title)}</h2>${action}</div>${content}</section>`;
  },
  training(items,value,attrs='') {
    return items.length===1?`<p class="training-static" data-component="DS06">${icon('car')}<span>Permis ${e(items[0])}</span></p>`:`<label class="training-picker" data-component="DS06"><span>Formation</span><select ${attrs}>${items.map(v=>`<option value="${e(v)}" ${v===value?'selected':''}>Permis ${e(v)}</option>`).join('')}</select></label>`;
  },
  lessonRow(l,name,attrs='',active=false) {
    return `<button class="lesson-row ${active?'current':''}" data-component="DS04" ${attrs}><span class="lesson-time">${e(l.time)}<small>${e(l.end)}</small></span><span class="rowtext"><strong>${e(name)}</strong><small>${e(l.duration)} min · Permis ${e(l.training)}</small><span class="lesson-place">${e(l.place)}</span></span>${active?`<span class="live-mini">En cours</span>`:icon('chevron','last')}</button>`;
  },
  nav(items,current) {
    return `<nav class="app-navigation" data-component="DS22" aria-label="Navigation principale">${items.map(x=>`<button data-ui="tab" data-id="${x.id}" ${current===x.id?'aria-current="page"':''}>${icon(x.glyph)}<span>${e(x.label)}</span></button>`).join('')}</nav>`;
  },
  sheetHeader(title,{id='sheetTitle',sub='',back=false,backAttrs='data-action="sheetBack"',closeAttrs='data-action="closeSheet"',closeLabel='Fermer',backLabel='Revenir aux catégories'}={}) {
    return `<div class="handle" aria-hidden="true"></div><div class="sheet-header">${back?`<button class="round back" ${backAttrs} aria-label="${e(backLabel)}">${icon('back')}</button>`:''}<div class="heading"><h2 id="${id}">${e(title)}</h2>${sub?`<div class="sub">${sub}</div>`:''}</div><button class="round soft" ${closeAttrs} aria-label="${e(closeLabel)}">${icon('close')}</button></div>`;
  },
  dialog(content,{labelId='sheetTitle',step='',extraClass='',scrimAttrs='data-action="closeSheet"',descriptionId=''}={}) {
    return `<div class="modal-layer ${extraClass}"><div class="scrim" ${scrimAttrs}></div><section class="sheet" data-component="DS15" ${step?`data-step="${step}"`:''} role="dialog" aria-modal="true" aria-labelledby="${labelId}" ${descriptionId?`aria-describedby="${descriptionId}"`:''}>${content}</section></div>`;
  },
  modal(title,body,{footer='',description=''}={}) {
    const content=UI.sheetHeader(title,{id:'workspaceDialogTitle',closeAttrs:'data-ui="dismiss"'})+`<div class="sheet-body">${description?`<p class="ui-help" id="workspaceDialogDescription">${e(description)}</p>`:''}${body}</div>${footer?`<div class="sheet-footer">${footer}</div>`:''}`;
    return UI.dialog(content,{labelId:'workspaceDialogTitle',extraClass:'workspace-modal',scrimAttrs:'data-ui="dismiss"',descriptionId:description?'workspaceDialogDescription':''});
  }
};
