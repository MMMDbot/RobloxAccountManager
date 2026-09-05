let clientWindowMin=false;
let clientWindowFull=false;
let clientScale='fit';
let activeClientId=null;
let activeClientButton=null;
let clientOpening=false;
const clientScales=['fit',0.5,0.75,1,1.25,1.5,2];
let clientNativeWidth=1280;
let clientNativeHeight=720;
let clientKind='cordial';
function centerClientViewport(){
  const area=document.getElementById('clientVncArea');
  const stage=document.getElementById('clientVncStage');
  if(!area||!stage)return;
  requestAnimationFrame(()=>{
    area.scrollLeft=Math.max(0,Math.round((stage.scrollWidth-area.clientWidth)/2));
    area.scrollTop=Math.max(0,Math.round((stage.scrollHeight-area.clientHeight)/2));
  });
}
function applyClientScale(){
  const area=document.getElementById('clientVncArea');
  const stage=document.getElementById('clientVncStage');
  const iframe=document.getElementById('clientVnc');
  if(!area||!stage||!iframe)return;
  const usableW=Math.max(240,area.clientWidth-98), usableH=Math.max(160,area.clientHeight-16);
  const scale=clientScale==='fit' ? Math.min(2,usableW/clientNativeWidth,usableH/clientNativeHeight) : Number(clientScale);
  const scaledW=Math.max(1,Math.round(clientNativeWidth*scale));
  const scaledH=Math.max(1,Math.round(clientNativeHeight*scale));
  iframe.style.width=scaledW+'px'; iframe.style.height=scaledH+'px'; iframe.style.margin='0';
  stage.style.width=Math.max(usableW,scaledW)+'px'; stage.style.height=Math.max(usableH,scaledH)+'px';
  const b=document.getElementById('clientScaleBtn');
  if(b)b.textContent=clientScale==='fit'?'Ajustar · '+Math.round(scale*100)+'%':Math.round(scale*100)+'%';
  centerClientViewport();
}
function setClientScale(scale){
  clientScale=scale;
  applyClientScale();
}
function cycleClientScale(){
  const i=clientScales.indexOf(clientScale);
  clientScale=clientScales[(i+1)%clientScales.length];
  applyClientScale();
}
window.addEventListener('resize',()=>{if(activeClientId!==null)applyClientScale();});
function closeClientWindow(){
  const w=document.getElementById('clientWindow');
  w.classList.add('hidden'); w.setAttribute('aria-hidden','true');
  document.getElementById('clientVnc').src='about:blank';
  if(activeClientButton){
    activeClientButton.disabled=false;
    activeClientButton.textContent=activeClientButton.dataset.originalText || 'Abrir cliente';
    activeClientButton.classList.remove('client-opening');
  }
  activeClientButton=null;
  activeClientId=null;
  clientOpening=false;
  clientKind='cordial'; clientNativeWidth=960; clientNativeHeight=600;
  const loginTools=document.getElementById('clientLoginTools'); if(loginTools)loginTools.style.display='grid';
}
function minimizeClientWindow(){ const w=document.getElementById('clientWindow'); clientWindowMin=!clientWindowMin; w.classList.toggle('minimized',clientWindowMin); if(!clientWindowMin)setTimeout(applyClientScale,80); }
function toggleClientFullscreen(){ const w=document.getElementById('clientWindow'); clientWindowFull=!clientWindowFull; w.classList.toggle('fullscreen',clientWindowFull); setTimeout(applyClientScale,80); }
async function sendClientText(kind){
  const text=kind==='user'?document.getElementById('clientUser').value:document.getElementById('clientPass').value;
  const sid=(typeof activeClientId==='string'&&activeClientId.startsWith('cordial-'))?Number(activeClientId.split('-')[1]):null;
  const st=document.getElementById('clientPasteStatus');
  if(!text){if(st)st.textContent='Pega primero el '+(kind==='user'?'usuario':'password')+'.';return;}
  if(!sid){if(st)st.textContent='Abre primero un visor rb1–rb4.';return;}
  const body=new URLSearchParams({text,target:kind,session_id:String(sid)});
  try{
    if(st)st.textContent=`Escribiendo en rb${sid}…`;
    const r=await fetch('/clipboard',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
    const data=await r.json(); if(!r.ok||!data.ok)throw new Error(data.error||'error');
    if(st)st.textContent=`✓ ${kind==='user'?'Usuario':'Contraseña'} pegado en rb${sid}.`;
  }catch(e){if(st)st.textContent='Error: '+e.message;}
}


async function refreshAccountStatus(){
  try{
    const r=await fetch('/api/accounts/status',{cache:'no-store'}); const d=await r.json(); if(!r.ok||!d.ok) return;
      // Si el VPS no puede consultar thumbnails.roblox.com, el navegador intenta cargar el avatar directamente.
    for(const a of d.accounts){
      const img=document.getElementById(`avatar-${a.id}`), fb=document.getElementById(`avatar-fallback-${a.id}`);
      if(img){ img.onerror=()=>{img.style.display='none'; if(fb)fb.style.display='flex';}; if(a.avatar){img.src=a.avatar; img.style.display='block'; if(fb)fb.style.display='none';} else {img.style.display='none'; if(fb)fb.style.display='flex';}
        if(!a.avatar && img && a.user_id){ img.src=`https://www.roblox.com/headshot-thumbnail/image?userId=${a.user_id}&width=150&height=150&format=png`; img.style.display='block'; if(fb)fb.style.display='none'; } }
      const p=document.getElementById(`presence-${a.id}`); if(p){p.className='presence-dot '+(a.presence==='offline'?'off':a.presence==='jugando'?'game':'on');p.textContent=(a.presence==='jugando'?'🎮 Jugando':a.presence==='online'?'🟢 En línea':a.presence==='Studio'?'🟣 Studio':'⚪ Offline');}
      const loc=document.getElementById(`location-${a.id}`); if(loc)loc.textContent=a.location?` · ${a.location}`:'';
      const cpu=document.getElementById(`cpu-${a.id}`); if(cpu)cpu.textContent=a.cpu+'%';
      const ram=document.getElementById(`ram-${a.id}`); if(ram)ram.textContent=a.ram+' MB';
      const checked=document.getElementById(`checked-${a.id}`); if(checked)checked.textContent=new Date().toLocaleTimeString();
    }
  }catch(e){}
}
refreshAccountStatus(); setInterval(refreshAccountStatus,20000);

async function checkInbox(){
  const status=document.getElementById('emailStatus'), results=document.getElementById('emailResults');
  status.textContent='Consultando...'; results.innerHTML='';
  try{
    const r=await fetch('/email/check',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({server:document.getElementById('imapServer').value,user:document.getElementById('imapUser').value,password:document.getElementById('imapPass').value,limit:Number(document.getElementById('imapLimit').value||5)})});
    const d=await r.json(); if(!r.ok||!d.ok) throw new Error(d.error||'No se pudo consultar');
    status.textContent=`${d.messages.length} mensaje(s) recibido(s)`;
    if(!d.messages.length){results.innerHTML='<div class="empty">No hay mensajes.</div>';return;}
    results.innerHTML=d.messages.map((m,i)=>{
      const codes=m.codes.map(c=>`<button type="button" class="code-pill" onclick="copyText('${c}').then(()=>this.textContent='✓ '+ '${c}')">${c}</button>`).join('');
      const links=m.links.map(u=>`<a class="email-link" href="${u}" target="_blank" rel="noopener noreferrer">Abrir enlace</a>`).join('');
      return `<article class="email-item"><div><strong>${escapeHtml(m.subject||'(sin asunto)')}</strong><small>${escapeHtml(m.from||'')} · ${escapeHtml(m.date||'')}</small></div><p>${escapeHtml(m.preview||'')}</p><div class="email-actions">${codes}${links}</div></article>`;
    }).join('');
  }catch(e){status.textContent='Error: '+e.message;}
}
function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}

function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text);
  }
  const area = document.createElement('textarea');
  area.value = text;
  area.style.position = 'fixed';
  area.style.left = '-9999px';
  document.body.appendChild(area);
  area.focus();
  area.select();
  document.execCommand('copy');
  area.remove();
  return Promise.resolve();
}

document.querySelectorAll('.copy-btn').forEach(button => {
  button.addEventListener('click', async () => {
    const original = button.textContent;
    try {
      await copyText(button.dataset.copy);
      button.textContent = '✓ Copiado';
    } catch (e) {
      button.textContent = 'No se pudo copiar';
    }
    setTimeout(() => button.textContent = original, 1200);
  });
});
async function accountMailCreate(id){
  const st=document.getElementById(`mail-status-${id}`); st.textContent='Creando correo…';
  try{const r=await fetch(`/accounts/${id}/mailtm/create`,{method:'POST'});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'Error');
    document.getElementById(`mail-address-${id}`).textContent=d.address;
    st.innerHTML=`✓ Creado: <b>${escapeHtml(d.address)}</b>`;
    alert(`Correo creado para esta cuenta\n\n${d.address}\n\nContraseña: ${d.password}`);
  }catch(e){st.textContent='Error: '+e.message;}
}
async function accountMailView(id){
  const st=document.getElementById(`mail-status-${id}`); st.textContent='Abriendo correo…';
  const address=document.getElementById(`mail-address-${id}`).textContent.trim();
  if(!address || address==='Sin correo Mail.tm'){st.textContent='Primero crea el correo.';return;}
  await accountMailCheck(id);
}
async function accountMailCheck(id){
  const st=document.getElementById(`mail-status-${id}`); st.textContent='Consultando bandeja…';
  try{const r=await fetch(`/accounts/${id}/mailtm/messages`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({limit:5})});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'Error');
    if(!d.messages.length){st.innerHTML=`📧 ${escapeHtml(d.address)} · No hay mensajes todavía.`;return;}
    st.innerHTML=`📧 ${escapeHtml(d.address)} · <b>${d.messages.length} mensaje(s)</b><br>`+d.messages.map(m=>`<span>${escapeHtml(m.subject)} — ${escapeHtml(m.from)}</span>`).join('<br>');
  }catch(e){st.textContent='Error Mail.tm: '+e.message;}
}

async function mailtmCreate(){
  const st=document.getElementById('mailtmStatus'); st.textContent='Creando buzón…';
  try{ const r=await fetch('/mailtm/create',{method:'POST'}); const d=await r.json(); if(!r.ok||!d.ok) throw new Error(d.error||'Error');
    document.getElementById('mailtmAddress').value=d.address; document.getElementById('mailtmPassword').value=d.password; document.getElementById('imapUser').value=d.address; document.getElementById('imapPass').value=d.password; document.getElementById('imapServer').value='Mail.tm'; st.textContent='Buzón creado correctamente. Usa «Consultar bandeja» para ver sus mensajes.';
  }catch(e){st.textContent='Error: '+e.message;}
}
async function mailtmCheck(){
  const address=document.getElementById('mailtmAddress').value, password=document.getElementById('mailtmPassword').value;
  const st=document.getElementById('mailtmStatus'), results=document.getElementById('emailResults');
  if(!address||!password){st.textContent='Primero crea un correo temporal.';return;}
  st.textContent='Consultando bandeja Mail.tm…';
  try{
    const r=await fetch('/mailtm/messages',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({address,password,limit:Number(document.getElementById('imapLimit').value||5)})});
    const d=await r.json(); if(!r.ok||!d.ok) throw new Error(d.error||'No se pudo consultar Mail.tm');
    st.textContent=`${d.messages.length} mensaje(s) en Mail.tm`;
    results.innerHTML=d.messages.length?d.messages.map(m=>`<article class=\"email-item\"><div><strong>${escapeHtml(m.subject||'(sin asunto)')}</strong><small>${escapeHtml(m.from||'')} · ${escapeHtml(m.date||'')}</small></div><p>${escapeHtml(m.preview||'')}</p></article>`).join(''):'<div class=\"empty\">No hay mensajes todavía.</div>';
  }catch(e){st.textContent='Error Mail.tm: '+e.message;}
}
async function copyMailtm(){
  const a=document.getElementById('mailtmAddress').value, p=document.getElementById('mailtmPassword').value; if(!a)return;
  try{await copyText(a+'\n'+p);document.getElementById('mailtmStatus').textContent='Correo y contraseña copiados.';}
  catch(e){document.getElementById('mailtmStatus').textContent='No se pudo copiar: '+e.message;}
}

async function importAccountsJson(input){
  if(!input.files.length)return;
  const st=document.getElementById('accountsJsonStatus'); st.textContent='Importando cuentas…';
  const fd=new FormData(); fd.append('accounts_file',input.files[0]);
  try{const r=await fetch('/accounts/import-json',{method:'POST',body:fd}); const d=await r.json(); if(!r.ok||!d.ok)throw new Error(d.error||'Error');
    st.textContent=`✓ ${d.message}${d.errors?.length?' · '+d.errors.length+' error(es)':''}`;
    if(d.errors?.length) st.title=d.errors.join('\n');
    setTimeout(()=>location.reload(),900);
  }catch(e){st.textContent='Error: '+e.message;} finally{input.value='';}
}
function downloadAccountsExample(){
  const data={accounts:[{username:'',id:''}]};
  const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'}); const a=document.createElement('a'); a.href=URL.createObjectURL(blob); a.download='cuentas-ejemplo.json'; a.click(); URL.revokeObjectURL(a.href);
}


async function quickClipboard(event){
  event.preventDefault();
  const sid=Number(document.getElementById('quickClipboardSession').value), text=document.getElementById('quickClipboardText').value;
  const st=document.getElementById('quickClipboardStatus'); if(!text){st.textContent='Pega un texto primero.';return false;}
  try{const body=new URLSearchParams({text,session_id:String(sid)});const r=await fetch('/clipboard',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'Error');st.textContent=`✓ Texto enviado al portapapeles de rb${sid}.`;}
  catch(e){st.textContent='Error: '+e.message;} return false;
}
async function sendAccountLogin(sid,text,button){
  try{const body=new URLSearchParams({text,target:'user',session_id:String(sid)});const r=await fetch('/clipboard',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'Error');const old=button.textContent;button.textContent='✓ Usuario enviado';setTimeout(()=>button.textContent=old,1200);}catch(e){alert(`rb${sid}: ${e.message}`);}
}
async function sendAccountValue(sid,text,button){
  try{const body=new URLSearchParams({text,session_id:String(sid)});const r=await fetch('/clipboard',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'Error');const old=button.textContent;button.textContent='✓ UserId copiado';setTimeout(()=>button.textContent=old,1200);}catch(e){alert(`rb${sid}: ${e.message}`);}
}
async function refreshCordialSetup(){
  const card=document.getElementById('cordialSetupCard'), st=document.getElementById('cordialSetupStatus');
  try{const r=await fetch('/api/setup/status',{cache:'no-store'});const d=await r.json();if(!d.ok)throw new Error(d.error||'error');
    if(card)card.style.display=d.engine_ready?'none':'block'; if(st)st.textContent=d.engine_ready?'Roblox preparado':(d.web?'visor 6090 activo':'pendiente');
  }catch(e){if(card)card.style.display='block';if(st)st.textContent='Error: '+e.message;}
}
async function startCordialSetup(){const r=await fetch('/api/setup/start',{method:'POST'});const d=await r.json();if(!r.ok||!d.ok)return alert(d.error||'No pudo iniciar preparación');await refreshCordialSetup();}
async function stopCordialSetup(){await fetch('/api/setup/stop',{method:'POST'});await refreshCordialSetup();}
async function openCordialSetup(button){
  const r=await fetch('/api/setup/start',{method:'POST'}),d=await r.json();if(!r.ok||!d.ok)return alert(d.error||'No pudo abrir preparación');
  activeClientId='setup';activeClientButton=button||null;clientKind='cordial';clientNativeWidth=960;clientNativeHeight=600;clientScale='fit';
  document.getElementById('clientWindowTitle').textContent='Preparación Cordial · Download Roblox';document.getElementById('clientLoginTools').style.display='none';
  document.getElementById('clientVnc').src=`${window.location.protocol}//${window.location.hostname}:${d.web_port||6090}/vnc.html?autoconnect=1&resize=scale&quality=0&compression=9`;
  const w=document.getElementById('clientWindow');w.classList.remove('hidden');w.setAttribute('aria-hidden','false');setTimeout(applyClientScale,150);
}

async function refreshAndroidLab(){
  try{
    const r=await fetch('/api/android/status',{cache:'no-store'}); const d=await r.json();
    const engine=document.getElementById('androidEngineStatus');
    if(engine) engine.textContent=d.setup_ready?'Cordial listo':'preparando Cordial…';
    let runningCount=0,readyCount=0;
    for(const st of (d.sessions||[])){
      const state=document.getElementById(`android-state-${st.id}`), meta=document.getElementById(`android-meta-${st.id}`); if(!state||!meta)continue;
      const running=!!st.engine&&!!st.cage&&!!st.xvfb, ready=!!st.ready, view=!!(st.viewer&&st.viewer.web);
      if(running)runningCount++; if(ready)readyCount++;
      state.textContent=running?(ready?'● ROBLOX LISTO':'● ROBLOX INICIANDO…'):'● DETENIDA'; state.className='wine-state '+(running?'on':'off');
      meta.textContent=`rb${st.id} · ${st.display||''} · motor ${running?'ON':'OFF'} · visor ${view?'ON':'OFF'}${ready?' · login listo':''}`;
      const ac=document.getElementById(`cordial-account-${st.id}`);if(ac)ac.textContent=ready?'ROBLOX LISTO':(running?'INICIANDO':'DETENIDO');
      const av=document.getElementById(`cordial-view-state-${st.id}`);if(av)av.textContent=view?`609${st.id}`:'—';
    }
    if(engine)engine.textContent=`Cordial · ${readyCount}/4 listos · ${runningCount}/4 activos`;
    const count=document.getElementById('cordialAccountCount');if(count)count.textContent=`${readyCount}/4 clientes listos · ${count.dataset.accounts||0} cuentas guardadas`;
  }catch(e){const x=document.getElementById('androidEngineStatus');if(x)x.textContent='Error: '+e.message;}
}
async function startAndroidSession(id){
  try{const r=await fetch(`/api/android/${id}/start`,{method:'POST'});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'No pudo iniciar Roblox');}
  catch(e){alert(`Instancia ${id}: ${e.message}`);} finally{setTimeout(refreshAndroidLab,800);}
}
async function openAndroidViewer(id,name=`Instancia ${id}`,button=null){
  if(clientOpening)return;
  if(activeClientId!==null)closeClientWindow();
  clientOpening=true; activeClientId=`cordial-${id}`; activeClientButton=button||document.getElementById(`cordial-view-${id}`);
  if(activeClientButton){activeClientButton.disabled=true;activeClientButton.dataset.originalText=activeClientButton.textContent;activeClientButton.textContent='Abriendo…';}
  try{const r=await fetch(`/api/android/${id}/viewer/start`,{method:'POST'});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'Visor aún no disponible');
    clientKind='cordial';clientNativeWidth=960;clientNativeHeight=600;clientScale='fit';
    const tools=document.getElementById('clientLoginTools');if(tools)tools.style.display='grid';document.getElementById('clientUser').value=name.startsWith('Instancia ')?'':name;document.getElementById('clientPass').value='';const pst=document.getElementById('clientPasteStatus');if(pst)pst.textContent=`rb${id} listo: pega usuario/password arriba y usa los botones.`;
    const w=document.getElementById('clientWindow');document.getElementById('clientWindowTitle').textContent=`Roblox · ${name} · rb${id}`;
    const iframe=document.getElementById('clientVnc');iframe.src=`${window.location.protocol}//${window.location.hostname}:${d.web_port}/vnc.html?autoconnect=1&resize=scale&quality=0&compression=9`;
    w.classList.remove('hidden','minimized','fullscreen');w.setAttribute('aria-hidden','false');clientWindowMin=false;clientWindowFull=false;clientScale='fit';setTimeout(applyClientScale,120);setTimeout(applyClientScale,650);
    if(activeClientButton)activeClientButton.textContent='Visor abierto';
  }catch(e){activeClientId=null;if(activeClientButton){activeClientButton.disabled=false;activeClientButton.textContent=activeClientButton.dataset.originalText||'👁 Ver';}activeClientButton=null;alert(`Visor ${id}: ${e.message}`);}finally{clientOpening=false;}
}
async function stopAndroidSession(id){
  if(activeClientId===`cordial-${id}`)closeClientWindow();
  try{const r=await fetch(`/api/android/${id}/stop`,{method:'POST'});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||'No pudo cerrar');}
  catch(e){alert(`Instancia ${id}: ${e.message}`);} finally{await refreshAndroidLab();}
}
document.addEventListener('DOMContentLoaded',()=>{refreshCordialSetup();refreshAndroidLab();setInterval(refreshCordialSetup,5000);setInterval(refreshAndroidLab,5000);});
