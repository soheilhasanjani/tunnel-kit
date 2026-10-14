import { useEffect, useState } from "react";
import { QRCodeSVG } from "qrcode.react";

async function api(path, options = {}) {
  const res = await fetch(path, {
    credentials: "include",
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.error || res.statusText);
    err.status = res.status;
    throw err;
  }
  return data;
}

function StatusDot({ ok, label }) {
  return (
    <span className={`pill ${ok ? "ok" : "down"}`}>
      <span className="dot" />
      {label}: {ok ? "running" : "down"}
    </span>
  );
}

function ProfileCard({ profile }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(profile.link);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <article className={`card ${profile.id}`}>
      <header>
        <p className="kicker">{profile.id === "reality" ? "Use this first" : "Backup"}</p>
        <h2>{profile.title}</h2>
        <p className="hint">{profile.hint}</p>
      </header>
      <div className="qr-wrap">
        <QRCodeSVG value={profile.link} size={168} bgColor="#f4f1ea" fgColor="#14120f" level="M" />
      </div>
      <button type="button" className="copy" onClick={copy}>
        {copied ? "Copied" : "Copy link"}
      </button>
    </article>
  );
}

function Login({ onOk }) {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await api("/api/login", { method: "POST", body: JSON.stringify({ password }) });
      onOk();
    } catch (err) {
      setError(err.message || "Login failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="shell login-shell">
      <form className="login" onSubmit={submit}>
        <p className="brand">tunnel-kit</p>
        <h1>Dashboard password</h1>
        <p className="hint">The password you set when you ran the install script.</p>
        <input
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Password"
          required
        />
        {error ? <p className="error">{error}</p> : null}
        <button type="submit" disabled={busy}>
          {busy ? "Checking…" : "Open dashboard"}
        </button>
      </form>
    </main>
  );
}

function Dashboard() {
  const [status, setStatus] = useState(null);
  const [share, setShare] = useState(null);
  const [error, setError] = useState("");

  async function load() {
    const [st, sh] = await Promise.all([api("/api/status"), api("/api/share")]);
    setStatus(st);
    setShare(sh);
  }

  useEffect(() => {
    let stop = false;
    async function tick() {
      try {
        await load();
        if (!stop) setError("");
      } catch (err) {
        if (!stop) setError(err.status === 401 ? "auth" : err.message);
      }
    }
    tick();
    const id = setInterval(tick, 10000);
    return () => {
      stop = true;
      clearInterval(id);
    };
  }, []);

  async function logout() {
    await api("/api/logout", { method: "POST" });
    window.location.reload();
  }

  if (error === "auth") return <Login onOk={() => window.location.reload()} />;

  return (
    <main className="shell">
      <header className="top">
        <div>
          <p className="brand">tunnel-kit</p>
          <h1>Your proxy</h1>
        </div>
        <button type="button" className="ghost" onClick={logout}>
          Log out
        </button>
      </header>

      <section className="status">
        <StatusDot ok={Boolean(status?.xray)} label="Xray" />
        <StatusDot ok={Boolean(status?.caddy)} label="Caddy" />
        {status?.domain ? <span className="pill muted">{status.domain}</span> : null}
      </section>

      {error && error !== "auth" ? <p className="error">{error}</p> : null}

      <p className="lead">
        Scan <strong>Stable / Reality</strong> on your phone first. Keep Cloudflare as a backup if
        Reality is blocked.
      </p>

      <section className="grid">
        {share?.profiles?.map((p) => (
          <ProfileCard key={p.id} profile={p} />
        ))}
      </section>
    </main>
  );
}

export default function App() {
  const [ready, setReady] = useState(false);
  const [authed, setAuthed] = useState(false);

  useEffect(() => {
    api("/api/status")
      .then(() => {
        setAuthed(true);
        setReady(true);
      })
      .catch((err) => {
        setAuthed(err.status !== 401);
        setReady(true);
      });
  }, []);

  if (!ready) return <main className="shell" />;
  if (!authed) return <Login onOk={() => setAuthed(true)} />;
  return <Dashboard />;
}
