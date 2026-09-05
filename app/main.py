from contextlib import asynccontextmanager
from pathlib import Path
import os
import sqlite3
import subprocess
import shutil
import imaplib
import email
import re
import json
from email.header import decode_header
from html import unescape

from fastapi import FastAPI, Form, Request, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse, FileResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

BASE = Path(__file__).resolve().parent.parent
DB = BASE / "data" / "panel.db"
RUN = BASE / "runtime"
SCRIPTS = BASE / "scripts"
ANDROID_INSTANCE_SCRIPT = SCRIPTS / "cordial_session.sh"
ANDROID_VIEWER_SCRIPT = SCRIPTS / "cordial_viewer.sh"
CORDIAL_SETUP_SCRIPT = SCRIPTS / "cordial_setup.sh"
DISPLAY_BASE = int(os.environ.get("TEMPLE_DISPLAY_BASE", "200"))
PANEL_RESOLUTION = os.environ.get("TEMPLE_RESOLUTION", "960x600")


def connect():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    return conn


def pid_running(name: str) -> bool:
    try:
        pid = int((RUN / f"{name}.pid").read_text().strip())
        os.kill(pid, 0)
        return True
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        return False


def _pidfile_alive(path: Path) -> bool:
    try:
        pid = int(path.read_text().strip())
        os.kill(pid, 0)
        return True
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        return False


def init_db():
    DB.parent.mkdir(parents=True, exist_ok=True)
    RUN.mkdir(parents=True, exist_ok=True)
    with connect() as db:
        db.execute("""CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            user_id INTEGER NOT NULL UNIQUE,
            enabled INTEGER NOT NULL DEFAULT 1,
            behavior TEXT NOT NULL DEFAULT 'dance_1',
            start_time TEXT NOT NULL DEFAULT '20:00',
            stop_time TEXT NOT NULL DEFAULT '22:00',
            notes TEXT NOT NULL DEFAULT '',
            session_profile TEXT NOT NULL DEFAULT ''
        )""")
        columns = {row[1] for row in db.execute("PRAGMA table_info(accounts)").fetchall()}
        if "session_profile" not in columns:
            db.execute("ALTER TABLE accounts ADD COLUMN session_profile TEXT NOT NULL DEFAULT ''")
        if "mailtm_address" not in columns:
            db.execute("ALTER TABLE accounts ADD COLUMN mailtm_address TEXT NOT NULL DEFAULT ''")
        if "mailtm_password" not in columns:
            db.execute("ALTER TABLE accounts ADD COLUMN mailtm_password TEXT NOT NULL DEFAULT ''")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Templo del Metal Panel", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=BASE / "app" / "static"), name="static")
templates = Jinja2Templates(directory=BASE / "app" / "templates")


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    with connect() as db:
        accounts = db.execute("SELECT * FROM accounts ORDER BY id").fetchall()
    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={"accounts": accounts, "msg": request.query_params.get("msg"), "display_base": DISPLAY_BASE, "panel_resolution": PANEL_RESOLUTION},
    )


@app.post("/accounts")
def add_account(
    username: str = Form(...), user_id: int = Form(...),
    behavior: str = Form("dance_1"), start_time: str = Form("20:00"),
    stop_time: str = Form("22:00"), notes: str = Form(""),
    session_profile: str = Form("")
):
    with connect() as db:
        db.execute("INSERT INTO accounts(username,user_id,behavior,start_time,stop_time,notes,session_profile) VALUES(?,?,?,?,?,?,?)",
                   (username.strip(), user_id, behavior, start_time, stop_time, notes.strip(), session_profile.strip()))
    return RedirectResponse("/?msg=Cuenta+agregada", status_code=303)


@app.post("/accounts/import-json")
async def import_accounts_json(accounts_file: UploadFile = File(...)):
    """Bulk-import account metadata from one JSON file. Secrets are not accepted."""
    import json
    raw=await accounts_file.read()
    if len(raw)>512*1024:
        return JSONResponse({"ok":False,"error":"El JSON supera 512 KB."},status_code=413)
    try:
        data=json.loads(raw.decode("utf-8"))
    except Exception as e:
        return JSONResponse({"ok":False,"error":f"JSON inválido: {e}"},status_code=400)
    items=data.get("accounts") if isinstance(data,dict) else data
    if not isinstance(items,list) or not items:
        return JSONResponse({"ok":False,"error":"El JSON debe contener una lista o {\"accounts\":[...]}"},status_code=400)
    if len(items)>100:
        return JSONResponse({"ok":False,"error":"Máximo 100 cuentas por archivo."},status_code=400)
    allowed={"username","user_id","behavior","start_time","stop_time","notes","session_profile"}
    created=0; skipped=0; errors=[]
    with connect() as db:
        for n,item in enumerate(items,1):
            if not isinstance(item,dict): errors.append(f"Fila {n}: debe ser un objeto"); continue
            if any(k in item for k in ("password","cookie","ROBLOSECURITY","mailtm_password")):
                errors.append(f"Fila {n}: no se permiten contraseñas, cookies ni credenciales"); continue
            username=str(item.get("username","")).strip()
            try: uid=int(item.get("user_id", item.get("id")))
            except Exception: errors.append(f"Fila {n}: id/user_id inválido"); continue
            if not username or uid<=0: errors.append(f"Fila {n}: username y user_id son obligatorios"); continue
            behavior=str(item.get("behavior","dance_1"))[:40]
            start=str(item.get("start_time","20:00"))[:5]
            stop=str(item.get("stop_time","22:00"))[:5]
            notes=str(item.get("notes",""))[:1000]
            profile=str(item.get("session_profile",f"client-{uid}"))[:100]
            exists=db.execute("SELECT id FROM accounts WHERE user_id=?",(uid,)).fetchone()
            if exists: skipped+=1; continue
            try:
                db.execute("INSERT INTO accounts(username,user_id,behavior,start_time,stop_time,notes,session_profile) VALUES(?,?,?,?,?,?,?)",(username,uid,behavior,start,stop,notes,profile))
                created+=1
            except Exception as e: errors.append(f"Fila {n}: {e}")
        db.commit()
    return JSONResponse({"ok":True,"created":created,"skipped":skipped,"errors":errors,"message":f"Importadas {created}; omitidas {skipped}."})

@app.get("/api/accounts/status")
async def accounts_status():
    import httpx, subprocess, re
    with connect() as db:
        rows=db.execute("SELECT id,username,user_id,session_profile FROM accounts ORDER BY id").fetchall()
    ids=[int(r["user_id"]) for r in rows]
    result={str(r["id"]):{"id":r["id"],"username":r["username"],"user_id":r["user_id"],"avatar":None,"presence":"offline","location":"","client":"cerrado","cpu":0,"ram":0} for r in rows}
    if not ids: return JSONResponse({"ok":True,"accounts":[]})
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            pres=await client.post("https://presence.roblox.com/v1/presence/users",json={"userIds":ids})
            pres.raise_for_status()
            for x in pres.json().get("userPresences",[]):
                for r in rows:
                    if int(r["user_id"])==int(x.get("userId",0)):
                        typ=int(x.get("userPresenceType",0)); result[str(r["id"])]["presence"]={0:"offline",1:"online",2:"jugando",3:"Studio"}.get(typ,"offline")
                        result[str(r["id"])]["location"]=x.get("lastLocation") or ""
                        break
            av=await client.get("https://thumbnails.roblox.com/v1/users/avatar-headshot",params={"userIds":",".join(map(str,ids)),"size":"150x150","format":"Png","isCircular":"false"})
            av.raise_for_status()
            amap={int(x["targetId"]):x.get("imageUrl") for x in av.json().get("data",[]) if x.get("imageUrl")}
            for r in rows: result[str(r["id"])]["avatar"]=amap.get(int(r["user_id"]))
    except Exception as e:
        for v in result.values(): v["error"]="No se pudo consultar Roblox"
    # Primeras cuatro cuentas se asocian a rb1-rb4, igual que la interfaz.
    for idx, r in enumerate(rows[:4], start=1):
        v=result[str(r["id"])]
        try:
            proc=subprocess.run([str(ANDROID_INSTANCE_SCRIPT),str(idx),"status"],capture_output=True,text=True,timeout=4)
            st=json.loads((proc.stdout or "{}").strip().splitlines()[-1])
            v["cordial_profile"]=f"rb{idx}"
            v["client"]="ROBLOX LISTO" if st.get("ready") else ("iniciando" if st.get("engine") else "cerrado")
        except Exception:
            v["client"]="error"
    return JSONResponse({"ok":True,"accounts":list(result.values())})

@app.post("/accounts/{account_id}/toggle")
def toggle_account(account_id: int):
    with connect() as db:
        db.execute("UPDATE accounts SET enabled = CASE enabled WHEN 1 THEN 0 ELSE 1 END WHERE id=?", (account_id,))
    return RedirectResponse("/", status_code=303)


@app.post("/accounts/{account_id}/delete")
def delete_account(account_id: int):
    with connect() as db:
        db.execute("DELETE FROM accounts WHERE id=?", (account_id,))
    return RedirectResponse("/", status_code=303)


@app.post("/clipboard")
async def clipboard(
    request: Request, text: str | None = Form(None), target: str | None = Form(None),
    session_id: int | None = Form(None),
):
    # Cordial rb1-rb4: escribe en el campo de login o coloca texto en
    # el portapapeles X11 de la instancia. Las contraseñas no se almacenan.
    if text is None:
        raw = await request.body()
        content_type = (request.headers.get("content-type") or "").lower()
        if "application/json" in content_type:
            try:
                payload = await request.json()
                text = str(payload.get("text", ""))
                target = str(payload.get("target", target or "")) or target
                if payload.get("session_id") is not None:
                    session_id = int(payload.get("session_id"))
            except Exception:
                text = ""
        else:
            text = raw.decode("utf-8", errors="replace")

    if not text:
        return JSONResponse({"ok": False, "error": "no_se_recibio_texto"}, status_code=400)
    sid = int(session_id or 1)
    if sid not in range(1, 5):
        return JSONResponse({"ok": False, "error": "session_id_fuera_de_rango"}, status_code=400)
    display = f":{DISPLAY_BASE + sid}"
    if not Path(f"/tmp/.X11-unix/X{DISPLAY_BASE + sid}").exists():
        return JSONResponse({"ok": False, "error": f"rb{sid}_no_esta_iniciada"}, status_code=409)
    env = {**os.environ, "DISPLAY": display}

    if target in {"user", "pass"}:
        # Coordenadas verificadas en Cordial a 960x600.
        x, y = 480, 416
        try:
            subprocess.run(["xdotool", "mousemove", str(x), str(y), "click", "1"], check=True, env=env)
            import time
            time.sleep(0.35)
            if target == "pass":
                subprocess.run(["xdotool", "key", "--clearmodifiers", "Tab"], check=True, env=env)
                time.sleep(0.35)
            subprocess.run(["xdotool", "key", "--clearmodifiers", "ctrl+a"], check=True, env=env)
            time.sleep(0.12)
            subprocess.run(["xdotool", "type", "--clearmodifiers", "--delay", "20", "--", text], check=True, env=env)
            return JSONResponse({"ok": True, "session_id": sid, "display": display, "target": target})
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            return JSONResponse({"ok": False, "error": type(exc).__name__}, status_code=500)

    if target == "focused":
        try:
            subprocess.run(["xdotool", "type", "--clearmodifiers", "--delay", "8", "--", text], check=True, env=env)
            return JSONResponse({"ok": True, "session_id": sid, "display": display, "target": "focused"})
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            return JSONResponse({"ok": False, "error": type(exc).__name__}, status_code=500)

    try:
        subprocess.run(["xclip", "-selection", "clipboard"], input=text, text=True, check=True, env=env)
        return JSONResponse({"ok": True, "session_id": sid, "display": display, "target": "clipboard"})
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        return JSONResponse({"ok": False, "error": type(exc).__name__}, status_code=500)



def _decode_header(value):
    if not value:
        return ""
    parts=[]
    for chunk, enc in decode_header(value):
        if isinstance(chunk, bytes):
            parts.append(chunk.decode(enc or "utf-8", errors="replace"))
        else:
            parts.append(str(chunk))
    return "".join(parts)


def _email_text(msg):
    chunks=[]
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() in ("text/plain", "text/html") and "attachment" not in (part.get("Content-Disposition") or "").lower():
                payload=part.get_payload(decode=True)
                if payload:
                    chunks.append(payload.decode(part.get_content_charset() or "utf-8", errors="replace"))
    else:
        payload=msg.get_payload(decode=True)
        if payload:
            chunks.append(payload.decode(msg.get_content_charset() or "utf-8", errors="replace"))
    return "\n".join(chunks)


@app.post("/accounts/{account_id}/mailtm/create")
async def account_mailtm_create(account_id: int):
    """Create or replace the Mail.tm mailbox belonging to one Roblox account."""
    import secrets, httpx
    with connect() as db:
        account=db.execute("SELECT id,username FROM accounts WHERE id=?", (account_id,)).fetchone()
    if not account:
        return JSONResponse({"ok":False,"error":"Cuenta no encontrada."},status_code=404)
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            dom=await client.get("https://api.mail.tm/domains?page=1")
            dom.raise_for_status(); data=dom.json().get("hydra:member",[])
            domain=next((x.get("domain") for x in data if x.get("domain")),None)
            if not domain: return JSONResponse({"ok":False,"error":"Mail.tm no devolvió dominios."},status_code=502)
            local="panel"+secrets.token_hex(6)
            address=f"{local}@{domain}"; password=secrets.token_urlsafe(18)
            r=await client.post("https://api.mail.tm/accounts",json={"address":address,"password":password})
            if r.status_code not in (200,201):
                return JSONResponse({"ok":False,"error":f"Mail.tm rechazó la cuenta ({r.status_code})."},status_code=502)
        with connect() as db:
            db.execute("UPDATE accounts SET mailtm_address=?, mailtm_password=? WHERE id=?",(address,password,account_id))
        return JSONResponse({"ok":True,"address":address,"password":password,"account_id":account_id})
    except Exception as e:
        return JSONResponse({"ok":False,"error":f"No se pudo crear el buzón: {e}"},status_code=502)

@app.post("/accounts/{account_id}/mailtm/messages")
async def account_mailtm_messages(account_id: int, request: Request):
    """Read only the Mail.tm inbox associated with this Roblox account."""
    import httpx
    with connect() as db:
        account=db.execute("SELECT mailtm_address,mailtm_password FROM accounts WHERE id=?",(account_id,)).fetchone()
    if not account: return JSONResponse({"ok":False,"error":"Cuenta no encontrada."},status_code=404)
    if not account["mailtm_address"] or not account["mailtm_password"]:
        return JSONResponse({"ok":False,"error":"Esta cuenta todavía no tiene correo Mail.tm."},status_code=400)
    try:
        data=await request.json(); limit=max(1,min(int(data.get("limit",5)),20))
    except Exception: limit=5
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            tok=await client.post("https://api.mail.tm/token",json={"address":account["mailtm_address"],"password":account["mailtm_password"]})
            if tok.status_code != 200:
                return JSONResponse({"ok":False,"error":"Mail.tm rechazó las credenciales guardadas."},status_code=502)
            token=tok.json().get("token")
            r=await client.get("https://api.mail.tm/messages",params={"page":1},headers={"Authorization":f"Bearer {token}"})
            r.raise_for_status(); items=r.json().get("hydra:member",[])[:limit]
            messages=[{"from":((m.get("from") or {}).get("address") or ""),"subject":m.get("subject") or "(sin asunto)","date":m.get("createdAt") or "","preview":m.get("intro") or ""} for m in items]
            return JSONResponse({"ok":True,"address":account["mailtm_address"],"messages":messages})
    except Exception as e:
        return JSONResponse({"ok":False,"error":f"Mail.tm: {type(e).__name__}: {e}"},status_code=502)

@app.post("/mailtm/create")
async def mailtm_create(request: Request):
    """Create a standalone temporary Mail.tm mailbox. No Roblox automation."""
    import secrets, string, httpx
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            dom=await client.get("https://api.mail.tm/domains?page=1")
            dom.raise_for_status(); data=dom.json().get("hydra:member",[])
            if not data: return JSONResponse({"ok":False,"error":"Mail.tm no devolvió dominios."},status_code=502)
            domain=data[0].get("domain")
            if not domain: return JSONResponse({"ok":False,"error":"Dominio no disponible."},status_code=502)
            local="panel"+secrets.token_hex(5)
            address=f"{local}@{domain}"
            password=secrets.token_urlsafe(18)
            r=await client.post("https://api.mail.tm/accounts",json={"address":address,"password":password})
            if r.status_code not in (200,201):
                return JSONResponse({"ok":False,"error":f"Mail.tm rechazó la cuenta ({r.status_code})."},status_code=502)
            return JSONResponse({"ok":True,"address":address,"password":password})
    except Exception as e:
        return JSONResponse({"ok":False,"error":f"No se pudo crear el buzón: {e}"},status_code=502)

@app.post("/mailtm/messages")
async def mailtm_messages(request: Request):
    """Read a Mail.tm mailbox using its API credentials; nothing is persisted."""
    import httpx
    try:
        data=await request.json()
        address=str(data.get("address","")).strip()
        password=str(data.get("password",""))
        limit=max(1,min(int(data.get("limit",5)),20))
        if not address or not password:
            return JSONResponse({"ok":False,"error":"Falta correo o contraseña Mail.tm."},status_code=400)
        async with httpx.AsyncClient(timeout=15) as client:
            tok=await client.post("https://api.mail.tm/token",json={"address":address,"password":password})
            if tok.status_code != 200:
                return JSONResponse({"ok":False,"error":"Credenciales de Mail.tm incorrectas o buzón inexistente."},status_code=401)
            token=tok.json().get("token")
            headers={"Authorization":f"Bearer {token}"}
            r=await client.get("https://api.mail.tm/messages",params={"page":1},headers=headers)
            r.raise_for_status()
            items=r.json().get("hydra:member",[])[:limit]
            messages=[]
            for m in items:
                messages.append({
                    "from":((m.get("from") or {}).get("address") or ""),
                    "subject":m.get("subject") or "(sin asunto)",
                    "date":m.get("createdAt") or "",
                    "codes":[], "links":[],
                    "preview":m.get("intro") or ""
                })
            return JSONResponse({"ok":True,"messages":messages})
    except Exception as exc:
        return JSONResponse({"ok":False,"error":f"Mail.tm: {type(exc).__name__}: {exc}"},status_code=502)

@app.post("/email/check")
async def email_check(request: Request):
    try:
        data=await request.json()
        server=str(data.get("server","")).strip()
        user=str(data.get("user","")).strip()
        password=str(data.get("password", ""))
        limit=max(1,min(int(data.get("limit",5)),10))
        if not server or not user or not password:
            return JSONResponse({"ok":False,"error":"Completa servidor IMAP, correo y contraseña."},status_code=400)
        host=server.split(":",1)[0]
        port=int(server.split(":",1)[1]) if ":" in server else 993
        mail=imaplib.IMAP4_SSL(host,port)
        mail.login(user,password)
        mail.select("INBOX",readonly=True)
        status,raw=mail.search(None,"ALL")
        if status!="OK":
            mail.logout(); return JSONResponse({"ok":False,"error":"No se pudo consultar INBOX."},status_code=502)
        ids=raw[0].split()[-limit:]
        messages=[]
        for mid in reversed(ids):
            st,parts=mail.fetch(mid,"(RFC822)")
            if st!="OK": continue
            for part in parts:
                if isinstance(part,tuple):
                    msg=email.message_from_bytes(part[1])
                    body=unescape(_email_text(msg))
                    codes=[]
                    for code in re.findall(r"\b\d{6}\b", body):
                        if code not in codes: codes.append(code)
                    links=re.findall(r"https?://[^\s<>\"']+", body)
                    clean_links=[]
                    for link in links:
                        link=link.rstrip(".,);]")
                        if link not in clean_links: clean_links.append(link)
                    messages.append({"from":_decode_header(msg.get("From")),"subject":_decode_header(msg.get("Subject")),"date":msg.get("Date", ""),"codes":codes[:5],"links":clean_links[:5],"preview":re.sub(r"\s+"," ",re.sub(r"<[^>]+>"," ",body))[:500]})
                    break
        mail.logout()
        return JSONResponse({"ok":True,"messages":messages})
    except Exception as exc:
        return JSONResponse({"ok":False,"error":f"IMAP: {type(exc).__name__}: {exc}"},status_code=502)


def run_script(name: str):
    proc = subprocess.run([str(SCRIPTS / name)], capture_output=True, text=True)
    text = (proc.stdout or proc.stderr or "ok").strip().replace(" ", "+")
    return RedirectResponse(f"/?msg={text}", status_code=303)


@app.get("/api/setup/status")
def setup_status():
    proc=subprocess.run([str(CORDIAL_SETUP_SCRIPT),"status"],capture_output=True,text=True,timeout=5)
    try: return {"ok":True,**json.loads((proc.stdout or "{}").strip().splitlines()[-1])}
    except Exception: return {"ok":False,"error":(proc.stderr or proc.stdout).strip()}

@app.post("/api/setup/start")
def setup_start():
    proc=subprocess.run([str(CORDIAL_SETUP_SCRIPT),"start"],capture_output=True,text=True,timeout=12)
    if proc.returncode: return JSONResponse({"ok":False,"error":(proc.stderr or proc.stdout).strip()},500)
    try: info=json.loads(proc.stdout.strip().splitlines()[-1])
    except Exception: info={"web_port":6090}
    return {"ok":True,**info}

@app.post("/api/setup/stop")
def setup_stop():
    proc=subprocess.run([str(CORDIAL_SETUP_SCRIPT),"stop"],capture_output=True,text=True,timeout=8)
    if proc.returncode: return JSONResponse({"ok":False,"error":(proc.stderr or proc.stdout).strip()},500)
    return {"ok":True}

@app.get("/api/android/status")
def android_status():
    sessions=[]
    for sid in range(1,5):
        proc=subprocess.run([str(ANDROID_INSTANCE_SCRIPT),str(sid),"status"],capture_output=True,text=True,timeout=8)
        try: item=json.loads((proc.stdout or "{}").strip().splitlines()[-1])
        except Exception: item={"id":sid,"error":(proc.stderr or proc.stdout).strip()}
        sessions.append(item)
    setup_ready=ANDROID_INSTANCE_SCRIPT.exists() and ANDROID_VIEWER_SCRIPT.exists() and shutil.which("cage") is not None
    return {"engine":"cordial","setup_ready":setup_ready,"sessions":sessions}

@app.post("/api/android/{session_id}/start")
def android_start(session_id:int):
    if session_id not in range(1,5): return JSONResponse({"ok":False,"error":"id fuera de rango"},400)
    proc=subprocess.run([str(ANDROID_INSTANCE_SCRIPT),str(session_id),"start"],capture_output=True,text=True,timeout=20)
    if proc.returncode: return JSONResponse({"ok":False,"error":(proc.stderr or proc.stdout).strip()},500)
    return {"ok":True,"starting":True}

@app.post("/api/android/{session_id}/viewer/start")
def android_viewer_start(session_id:int):
    proc=subprocess.run([str(ANDROID_VIEWER_SCRIPT),str(session_id),"start"],capture_output=True,text=True,timeout=8)
    if proc.returncode: return JSONResponse({"ok":False,"error":(proc.stderr or proc.stdout).strip()},500)
    try: info=json.loads(proc.stdout.strip().splitlines()[-1])
    except Exception: info={"web_port":6090+session_id}
    return {"ok":True,**info}

@app.post("/api/android/{session_id}/stop")
def android_stop(session_id:int):
    proc=subprocess.run([str(ANDROID_INSTANCE_SCRIPT),str(session_id),"stop"],capture_output=True,text=True,timeout=12)
    if proc.returncode: return JSONResponse({"ok":False,"error":(proc.stderr or proc.stdout).strip()},500)
    return {"ok":True}

@app.get("/health")
def health():
    sessions=[]
    for sid in range(1,5):
        proc=subprocess.run([str(ANDROID_INSTANCE_SCRIPT),str(sid),"status"],capture_output=True,text=True,timeout=4)
        try: sessions.append(json.loads((proc.stdout or "{}").strip().splitlines()[-1]))
        except Exception: sessions.append({"id":sid,"error":"status"})
    return {
        "status":"ok",
        "panel":"Templo del Metal",
        "mode":"cordial-x86_64",
        "roblox_sessions_running":sum(1 for item in sessions if item.get("engine")),
        "roblox_sessions_ready":sum(1 for item in sessions if item.get("ready")),
        "sessions":sessions,
    }
