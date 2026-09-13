#!/bin/sh
set -e
mkdir -p app/api/auth/register app/api/auth/login app/api/auth/logout app/api/auth/me app/api/admin/settings app/api/admin/users app/api/chat app/login app/register app/chat app/admin lib

cat > 'README.md' <<'__FILE__'
# Free AI — Vercel-ready

This version replaces local SQLite with PostgreSQL so user accounts and settings persist on Vercel.

## Required Vercel environment variables
DATABASE_URL — PostgreSQL connection string.
AUTH_SECRET — long random secret.
ADMIN_EMAIL — first/admin account email.
ADMIN_PASSWORD — first/admin account password.

Optional AI variables:
AI_API_URL
AI_API_KEY
AI_MODEL

Deploy this folder as a Next.js project. Add the environment variables in Vercel Project Settings → Environment Variables, then redeploy. Vercel supports Next.js with zero-config deployment. A PostgreSQL database can be connected through Vercel Marketplace storage integrations.

Admin: log in with ADMIN_EMAIL/ADMIN_PASSWORD. The Admin button appears only for the admin role. The `/api/admin/*` endpoints independently reject non-admin sessions with 403.

__FILE__

cat > 'app/admin/page.js' <<'__FILE__'
 "use client";import {useEffect,useState} from "react";import {useRouter} from "next/navigation";export default function Admin(){const[m,setM]=useState(null),[s,setS]=useState({}),[u,setU]=useState([]),[msg,setMsg]=useState("");const r=useRouter();useEffect(()=>{Promise.all([fetch("/api/auth/me").then(x=>x.json()),fetch("/api/admin/settings").then(x=>x.json()),fetch("/api/admin/users").then(x=>x.json())]).then(([a,b,c])=>{if(!a.user||a.user.role!=="admin")return r.push("/chat");setM(a.user);setS(b.settings);setU(c.users)})},[]);async function save(){const x=await fetch("/api/admin/settings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(s)});setMsg(x.ok?"Saved":"Failed")}if(!m)return <main className="center">Checking admin access…</main>;return <main className="admin"><header><h1>Admin Panel</h1><button onClick={()=>r.push("/chat")}>Back</button></header><section className="grid"><div className="card"><h2>AI settings</h2><label>Model<input value={s.model||""} onChange={e=>setS({...s,model:e.target.value})}/></label><label>Daily messages<input type="number" value={s.dailyLimit||50} onChange={e=>setS({...s,dailyLimit:e.target.value})}/></label><label>Safety<select value={s.safety||"standard"} onChange={e=>setS({...s,safety:e.target.value})}><option>standard</option><option>strict</option></select></label><button className="btn" onClick={save}>Save settings</button>{msg&&<p>{msg}</p>}</div><div className="card"><h2>Users</h2>{u.map(a=><div className="user" key={a.id}><span>{a.email}</span><small>{a.role}</small></div>)}</div></section></main>}
__FILE__

cat > 'app/api/admin/settings/route.js' <<'__FILE__'
const {q}=require("../../../../lib/db");const {readToken}=require("../../../../lib/auth");import {cookies} from "next/headers";import {NextResponse} from "next/server";async function ok(){const v=(await cookies()).get("session")?.value,p=v&&await readToken(v);return p?.role==="admin"}export async function GET(){if(!await ok())return NextResponse.json({error:"Forbidden"},{status:403});const r=await q("SELECT key,value FROM settings");return NextResponse.json({settings:Object.fromEntries(r.rows.map(x=>[x.key,x.value]))})}export async function POST(req){if(!await ok())return NextResponse.json({error:"Forbidden"},{status:403});const s=await req.json();for(const k of ["model","dailyLimit","safety"])if(s[k]!==undefined)await q("INSERT INTO settings(key,value) VALUES($1,$2) ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value",[k,String(s[k])]);return NextResponse.json({ok:true})}
__FILE__

cat > 'app/api/admin/users/route.js' <<'__FILE__'
const {q}=require("../../../../lib/db");const {readToken}=require("../../../../lib/auth");import {cookies} from "next/headers";import {NextResponse} from "next/server";export async function GET(){const v=(await cookies()).get("session")?.value,p=v&&await readToken(v);if(p?.role!=="admin")return NextResponse.json({error:"Forbidden"},{status:403});const r=await q("SELECT id,email,role,created_at FROM users ORDER BY id DESC");return NextResponse.json({users:r.rows})}
__FILE__

cat > 'app/api/auth/login/route.js' <<'__FILE__'
const {q}=require("../../../../lib/db");const {makeToken}=require("../../../../lib/auth");const bcrypt=require("bcryptjs");const {NextResponse}=require("next/server");export async function POST(req){const {email,password}=await req.json();const r=await q("SELECT * FROM users WHERE email=$1",[String(email||"").toLowerCase()]);const u=r.rows[0];if(!u||!bcrypt.compareSync(password||"",u.password_hash))return NextResponse.json({error:"Invalid email or password"},{status:401});const res=NextResponse.json({ok:true});res.cookies.set("session",await makeToken(u),{httpOnly:true,secure:true,sameSite:"lax",path:"/",maxAge:604800});return res}
__FILE__

cat > 'app/api/auth/logout/route.js' <<'__FILE__'
import {NextResponse} from "next/server";export async function POST(){const r=NextResponse.json({ok:true});r.cookies.set("session","",{httpOnly:true,secure:true,expires:new Date(0),path:"/"});return r}
__FILE__

cat > 'app/api/auth/me/route.js' <<'__FILE__'
const {readToken}=require("../../../../lib/auth");import {cookies} from "next/headers";import {NextResponse} from "next/server";export async function GET(){const v=(await cookies()).get("session")?.value,p=v&&await readToken(v);return NextResponse.json({user:p?{id:p.id,email:p.email,role:p.role}:null})}
__FILE__

cat > 'app/api/auth/register/route.js' <<'__FILE__'
const {q}=require("../../../../lib/db");const {makeToken}=require("../../../../lib/auth");const bcrypt=require("bcryptjs");const {NextResponse}=require("next/server");export async function POST(req){const {email,password}=await req.json();if(!email||!password||password.length<8)return NextResponse.json({error:"Valid email and 8+ character password required"},{status:400});try{const r=await q("INSERT INTO users(email,password_hash) VALUES($1,$2) RETURNING id,email,role",[email.toLowerCase(),bcrypt.hashSync(password,12)]);const res=NextResponse.json({ok:true});res.cookies.set("session",await makeToken(r.rows[0]),{httpOnly:true,secure:true,sameSite:"lax",path:"/",maxAge:604800});return res}catch{return NextResponse.json({error:"Email already registered"},{status:409})}}
__FILE__

cat > 'app/api/chat/route.js' <<'__FILE__'
const {q}=require("../../../lib/db");const {readToken}=require("../../../lib/auth");import {cookies} from "next/headers";import {NextResponse} from "next/server";export async function POST(req){const v=(await cookies()).get("session")?.value,p=v&&await readToken(v);if(!p)return NextResponse.json({error:"Login required"},{status:401});const {message}=await req.json();if(!message?.trim())return NextResponse.json({error:"Message required"},{status:400});const sr=await q("SELECT key,value FROM settings");const s=Object.fromEntries(sr.rows.map(x=>[x.key,x.value]));const lim=Number(s.dailyLimit||50);const ur=await q("SELECT count FROM usage WHERE user_id=$1 AND day=CURRENT_DATE",[p.id]);if(Number(ur.rows[0]?.count||0)>=lim)return NextResponse.json({error:"Daily limit reached"},{status:429});await q("INSERT INTO usage(user_id,day,count) VALUES($1,CURRENT_DATE,1) ON CONFLICT(user_id,day) DO UPDATE SET count=usage.count+1",[p.id]);if(!process.env.AI_API_URL)return NextResponse.json({reply:"AI provider is not configured. Add AI_API_URL, AI_API_KEY and AI_MODEL in Vercel Environment Variables."});try{const x=await fetch(process.env.AI_API_URL,{method:"POST",headers:{"Content-Type":"application/json",...(process.env.AI_API_KEY?{Authorization:`Bearer ${process.env.AI_API_KEY}`}:{})},body:JSON.stringify({model:s.model||process.env.AI_MODEL,messages:[{role:"user",content:message}]})});const d=await x.json();return NextResponse.json({reply:d.choices?.[0]?.message?.content||d.output_text||d.reply||"No response."})}catch{return NextResponse.json({error:"AI provider request failed"},{status:502})}}
__FILE__

cat > 'app/chat/page.js' <<'__FILE__'
 "use client";import {useEffect,useState} from "react";import {useRouter} from "next/navigation";export default function Chat(){const[m,setM]=useState(null),[v,setV]=useState(""),[busy,setB]=useState(false),[ms,setMs]=useState([]);const r=useRouter();useEffect(()=>{fetch("/api/auth/me").then(x=>x.json()).then(d=>d.user?setM(d.user):r.push("/login"))},[]);async function send(e){e.preventDefault();if(!v.trim()||busy)return;const t=v;setV("");setMs(a=>[...a,{role:"user",content:t}]);setB(true);const x=await fetch("/api/chat",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({message:t})});const d=await x.json();setMs(a=>[...a,{role:"assistant",content:x.ok?d.reply:d.error}]);setB(false)}if(!m)return <main className="center">Loading…</main>;return <main className="chat"><header><b>Free AI</b><span>{m.email}</span>{m.role==="admin"&&<button onClick={()=>r.push("/admin")}>Admin</button>}<button onClick={async()=>{await fetch("/api/auth/logout",{method:"POST"});r.push("/")}}>Log out</button></header><section className="messages">{ms.length===0&&<div className="empty">Ask something to begin.</div>}{ms.map((a,i)=><div key={i} className={"bubble "+a.role}><b>{a.role==="user"?"You":"AI"}</b>{a.content}</div>)}</section><form className="composer" onSubmit={send}><input value={v} onChange={e=>setV(e.target.value)} placeholder="Message the AI…"/><button className="btn">{busy?"…":"Send"}</button></form></main>}
__FILE__

cat > 'app/globals.css' <<'__FILE__'
*{box-sizing:border-box}body{margin:0;font-family:system-ui,sans-serif;background:#0b1020;color:#eef2ff}a{text-decoration:none}.center{min-height:100vh;display:grid;place-items:center;padding:24px}.card{background:#141b31;border:1px solid #293451;border-radius:18px;padding:28px;box-shadow:0 12px 40px #0004}.hero{text-align:center;width:min(520px,100%)}h1{font-size:42px;margin:0 0 8px}.row{display:flex;gap:12px;justify-content:center;margin-top:24px}.btn,button{border:0;border-radius:10px;padding:11px 16px;background:#6d7cff;color:white;font-weight:700;cursor:pointer}.secondary{background:#293451}.form{width:min(420px,100%);display:grid;gap:14px}.form input,.composer input,label input,label select{width:100%;padding:12px;border-radius:10px;border:1px solid #33405e;background:#0d1427;color:white}.error{color:#ff8d9b}.chat{height:100vh;display:flex;flex-direction:column;max-width:900px;margin:auto}.chat header,.admin header{display:flex;align-items:center;gap:12px;padding:18px;border-bottom:1px solid #293451}.chat header span{margin-left:auto;color:#aeb9d4}.messages{flex:1;overflow:auto;padding:24px}.bubble{max-width:75%;padding:13px 16px;border-radius:14px;margin:12px 0;line-height:1.5}.bubble.user{margin-left:auto;background:#3346a8}.bubble.assistant{background:#18223c}.bubble b{display:block;font-size:12px;opacity:.7;margin-bottom:4px}.empty{text-align:center;color:#8995b4;margin-top:30vh}.composer{display:flex;gap:10px;padding:16px;border-top:1px solid #293451}.admin{max-width:1100px;margin:auto;padding:24px}.admin header{justify-content:space-between}.grid{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:20px}.grid .card{display:grid;gap:14px}.grid label{display:grid;gap:7px}.user{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #293451}@media(max-width:700px){.grid{grid-template-columns:1fr}.chat header span{display:none}}
__FILE__

cat > 'app/layout.js' <<'__FILE__'
import "./globals.css"; export const metadata={title:"Free AI",description:"AI chat"}; export default function Layout({children}){return <html><body>{children}</body></html>}
__FILE__

cat > 'app/login/page.js' <<'__FILE__'
 "use client"; import {useState} from "react";import {useRouter} from "next/navigation";export default function Login(){const[e,setE]=useState(""),[p,setP]=useState(""),[x,setX]=useState("");const r=useRouter();async function go(a){a.preventDefault();const z=await fetch("/api/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:e,password:p})});const d=await z.json();if(!z.ok)return setX(d.error);r.push("/chat")}return <main className="center"><form className="card form" onSubmit={go}><h2>Log in</h2><input type="email" placeholder="Email" value={e} onChange={a=>setE(a.target.value)} required/><input type="password" placeholder="Password" value={p} onChange={a=>setP(a.target.value)} required/><button className="btn">Log in</button>{x&&<p className="error">{x}</p>}</form></main>}
__FILE__

cat > 'app/page.js' <<'__FILE__'
import Link from "next/link"; export default function Home(){return <main className="center"><section className="card hero"><h1>Free AI</h1><p>AI chat with accounts and admin controls.</p><div className="row"><Link className="btn" href="/login">Log in</Link><Link className="btn secondary" href="/register">Create account</Link></div></section></main>}
__FILE__

cat > 'app/register/page.js' <<'__FILE__'
 "use client"; import {useState} from "react";import {useRouter} from "next/navigation";export default function Register(){const[e,setE]=useState(""),[p,setP]=useState(""),[x,setX]=useState("");const r=useRouter();async function go(a){a.preventDefault();const z=await fetch("/api/auth/register",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:e,password:p})});const d=await z.json();if(!z.ok)return setX(d.error);r.push("/chat")}return <main className="center"><form className="card form" onSubmit={go}><h2>Create account</h2><input type="email" placeholder="Email" value={e} onChange={a=>setE(a.target.value)} required/><input type="password" placeholder="Password (8+ chars)" value={p} onChange={a=>setP(a.target.value)} minLength="8" required/><button className="btn">Create account</button>{x&&<p className="error">{x}</p>}</form></main>}
__FILE__

cat > 'lib/auth.js' <<'__FILE__'
const {SignJWT,jwtVerify}=require("jose");const secret=new TextEncoder().encode(process.env.AUTH_SECRET||"change-me");async function makeToken(u){return new SignJWT({id:String(u.id),email:u.email,role:u.role}).setProtectedHeader({alg:"HS256"}).setIssuedAt().setExpirationTime("7d").sign(secret)}async function readToken(v){try{return (await jwtVerify(v,secret)).payload}catch{return null}}module.exports={makeToken,readToken}
__FILE__

cat > 'lib/db.js' <<'__FILE__'
const {Pool}=require("pg");let pool; function getPool(){if(!pool)pool=new Pool({connectionString:process.env.DATABASE_URL,ssl:process.env.DATABASE_URL?.includes("localhost")?false:{rejectUnauthorized:false}});return pool}
async function init(){const p=getPool();await p.query(`CREATE TABLE IF NOT EXISTS users(id BIGSERIAL PRIMARY KEY,email TEXT UNIQUE NOT NULL,password_hash TEXT NOT NULL,role TEXT NOT NULL DEFAULT 'user',created_at TIMESTAMPTZ DEFAULT NOW());CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);CREATE TABLE IF NOT EXISTS usage(user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,day DATE,count INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(user_id,day));`);if(process.env.ADMIN_EMAIL&&process.env.ADMIN_PASSWORD){const bcrypt=require("bcryptjs");const hash=bcrypt.hashSync(process.env.ADMIN_PASSWORD,12);await p.query(`INSERT INTO users(email,password_hash,role) VALUES($1,$2,'admin') ON CONFLICT(email) DO UPDATE SET role='admin'`,[process.env.ADMIN_EMAIL.toLowerCase(),hash])}for(const [k,v] of Object.entries({model:process.env.AI_MODEL||"default",dailyLimit:"50",safety:"standard"}))await p.query(`INSERT INTO settings(key,value) VALUES($1,$2) ON CONFLICT(key) DO NOTHING`,[k,v])}
async function q(text,params=[]){await init();return getPool().query(text,params)} module.exports={q}
__FILE__

cat > 'package.json' <<'__FILE__'
{"scripts":{"dev":"next dev","build":"next build","start":"next start"},"dependencies":{"next":"latest","react":"latest","react-dom":"latest","pg":"latest","bcryptjs":"latest","jose":"latest"}}
__FILE__

cat > 'vercel.json' <<'__FILE__'
{"framework":"nextjs"}
__FILE__

echo 'Project files created successfully.'
echo 'Now run: npm install && npm run build'