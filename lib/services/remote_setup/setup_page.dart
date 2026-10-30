import 'dart:convert';

import '../../app/app_settings.dart';
import '../../playback/language.dart';

const _style = '''
:root{color-scheme:dark;--bg:#0B0B12;--surface:#16161F;--high:#1E1E2A;--outline:#ffffff22;--text:#fff;--muted:#ffffffb3;--faint:#ffffff73;--accent:#6C63FF;--request:#F5B544;--ok:#3DDC97;--bad:#FF5D6C}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(circle at 10% 0%,#221E4A,var(--bg) 60%) fixed;color:var(--text);font:16px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:560px;margin:0 auto;padding:28px 16px 64px}
h1{font-size:28px;margin:8px 0 4px}
p.lead{color:var(--muted);margin:0 0 24px}
section{background:var(--surface);border:1px solid var(--outline);border-radius:18px;padding:20px;margin-bottom:16px}
h2{font-size:18px;margin:0 0 4px}
.hint{color:var(--faint);font-size:14px;margin:0 0 14px}
label{display:block;font-size:14px;color:var(--muted);margin:12px 0 6px}
input,select{width:100%;font:inherit;color:var(--text);background:var(--high);border:1.5px solid var(--outline);border-radius:12px;padding:12px 14px}
input:focus,select:focus{outline:none;border-color:var(--accent)}
button{width:100%;font:600 17px system-ui,sans-serif;color:#fff;background:var(--accent);border:0;border-radius:999px;padding:15px;margin-top:8px;cursor:pointer}
button:disabled{opacity:.6}
.result{margin-top:10px;font-size:14px}
.result.ok{color:var(--ok)}.result.bad{color:var(--bad)}
.code{font-size:28px;letter-spacing:.3em;text-align:center}
.logo{width:44px;height:44px;border-radius:12px;background:var(--accent);display:grid;place-items:center;font-weight:800;font-size:22px}
''';

String _shell(String title, String body) =>
    '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title><style>$_style</style></head>
<body><main><div class="logo">Z</div>$body</main></body></html>''';

String setupCodePage({bool wrongCode = false}) => _shell('Zerk Play setup', '''
<h1>Set up Zerk Play</h1>
<p class="lead">Enter the 6-digit code shown on the TV.</p>
<form method="get" action="/"><section>
<input class="code" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" autofocus required>
${wrongCode ? '<p class="result bad">That code doesn\'t match. Check the TV and try again.</p>' : ''}
<button type="submit">Continue</button>
</section></form>''');

String setupFormPage(Map<String, Object?> values) {
  final json = jsonEncode(values).replaceAll('<', r'\u003c');
  String options(Map<String, String> entries) =>
      [for (final e in entries.entries) '<option value="${_attr(e.key)}">${_text(e.value)}</option>'].join();
  return _shell('Zerk Play setup', '''
<h1>Set up Zerk Play</h1>
<p class="lead">Changes are sent to the TV when you press Save. Nothing leaves your network.</p>
<form id="f" autocomplete="off">
<section id="embySection">
  <h2>Media server</h2>
  <p class="hint" id="embyHint">Sign in to your Emby or Jellyfin server.</p>
  <div id="serverField">
    <label for="serverKind">Server type</label>
    <select id="serverKind" name="serverKind"><option value="emby">Emby</option><option value="jellyfin">Jellyfin</option></select>
    <label for="server">Server address</label>
    <input id="server" name="server" placeholder="192.168.1.10:8096" inputmode="url" autocapitalize="off" spellcheck="false">
  </div>
  <label for="username">Username</label>
  <input id="username" name="username" autocapitalize="off" spellcheck="false" autocomplete="username">
  <label for="password">Password</label>
  <input id="password" name="password" type="password" autocomplete="current-password">
  <p class="result" id="emby"></p>
</section>
<section>
  <h2>Language &amp; subtitles</h2>
  <p class="hint">The TV's language, and the subtitles picked whenever a video has them (English when it doesn't).</p>
  <label for="uiLanguage">App language</label>
  <select id="uiLanguage" name="uiLanguage">${options(uiLanguages)}</select>
  <label for="subtitleLanguage">Preferred subtitles</label>
  <select id="subtitleLanguage" name="subtitleLanguage">${options({'': 'Default (as the file says)', ...languageNames})}</select>
</section>
<section id="metadataSection">
  <h2>Metadata &amp; artwork</h2>
  <p class="hint">Titles, descriptions, posters and logos from TMDB in the app language (English where a translation is missing), or as your server has them.</p>
  <label for="metadataSource">Source</label>
  <select id="metadataSource" name="metadataSource"><option value="tmdb">TMDB</option><option value="emby">Media server</option></select>
  <label for="tmdbApiKey">TMDB API key</label>
  <p class="hint">Trailers, collections and discovery use it whichever source you pick. Needed for TMDB metadata.</p>
  <input id="tmdbApiKey" name="tmdbApiKey" autocomplete="off" autocorrect="off" placeholder="API key or read access token" autocapitalize="off" spellcheck="false">
  <p class="result" id="tmdb"></p>
</section>
<section>
  <h2>Ratings</h2>
  <p class="hint">Rotten Tomatoes scores from MDBList. Free key at mdblist.com → Preferences → API. Optional.</p>
  <label for="mdblistApiKey">MDBList API key</label>
  <input id="mdblistApiKey" name="mdblistApiKey" autocomplete="off" autocorrect="off" placeholder="API key" autocapitalize="off" spellcheck="false">
  <p class="result" id="mdblist"></p>
</section>
<section id="seerrSection">
  <h2>Requests</h2>
  <p class="hint">Jellyseerr or Overseerr, to request titles that aren't in your library. Optional.</p>
  <label for="seerrUrl">Server address</label>
  <input id="seerrUrl" name="seerrUrl" placeholder="http://192.168.1.10:5055" inputmode="url" autocapitalize="off" spellcheck="false">
  <label for="seerrApiKey">API key</label>
  <input id="seerrApiKey" name="seerrApiKey" autocomplete="off" autocorrect="off" placeholder="Settings → General → API Key" autocapitalize="off" spellcheck="false">
  <p class="result" id="seerr"></p>
</section>
<section>
  <h2>Live TV playlist</h2>
  <p class="hint">An M3U playlist with an XMLTV guide, such as Tunarr or NostalgiaTV. Optional.</p>
  <label for="playlistUrl">Playlist address (M3U)</label>
  <input id="playlistUrl" name="playlistUrl" placeholder="http://192.168.1.10:8000/api/channels.m3u" inputmode="url" autocapitalize="off" spellcheck="false">
  <label for="playlistGuideUrl">Guide address (XMLTV, optional)</label>
  <input id="playlistGuideUrl" name="playlistGuideUrl" placeholder="http://192.168.1.10:8000/api/xmltv.xml" inputmode="url" autocapitalize="off" spellcheck="false">
</section>
<button id="save" type="submit">Save to TV</button>
<p class="result" id="overall"></p>
</form>
<script>
const v = $json;
const f = document.getElementById('f');
const byId = (id) => document.getElementById(id);
f.server.value = v.server || '';
f.serverKind.value = v.serverKind || 'emby';
f.uiLanguage.value = v.uiLanguage || 'en';
f.subtitleLanguage.value = v.subtitleLanguage || '';
f.metadataSource.value = v.metadataSource || 'tmdb';
f.seerrUrl.value = v.seerrUrl || '';
f.playlistUrl.value = v.playlistUrl || '';
f.playlistGuideUrl.value = v.playlistGuideUrl || '';
if (v.signedIn) byId('embyHint').textContent = 'The TV is signed in. Fill in a username only to switch account.';
if (v.hasSeerrKey) f.seerrApiKey.placeholder = 'Saved on the TV. Leave blank to keep it.';
if (v.hasTmdbKey) f.tmdbApiKey.placeholder = 'Saved on the TV. Leave blank to keep it.';
if (v.hasMdblistKey) f.mdblistApiKey.placeholder = 'Saved on the TV. Leave blank to keep it.';
function show(id, r) {
  const el = byId(id);
  if (!el) return;
  el.textContent = r ? r.message : '';
  el.className = 'result' + (r ? (r.ok ? ' ok' : ' bad') : '');
}
f.addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn = byId('save');
  btn.disabled = true; btn.textContent = 'Saving…';
  ['emby', 'seerr', 'tmdb', 'mdblist', 'overall'].forEach((id) => show(id, null));
  try {
    const res = await fetch(location.pathname.replace(/\\/\$/, '') + '/apply', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(Object.fromEntries(new FormData(f))),
    });
    if (!res.ok) throw new Error(await res.text());
    const r = await res.json();
    show('emby', r.emby); show('seerr', r.seerr); show('tmdb', r.tmdb); show('mdblist', r.mdblist);
    const failed = Object.values(r).some((x) => !x.ok);
    show('overall', {ok: !failed, message: failed ? 'Saved, but something needs another look.' : 'Saved. You can put your phone away.'});
    if (r.emby && r.emby.ok) f.password.value = '';
    if (!failed) { if (f.seerrApiKey) f.seerrApiKey.value = ''; if (f.tmdbApiKey) f.tmdbApiKey.value = ''; f.mdblistApiKey.value = ''; }
  } catch (err) {
    show('overall', {ok: false, message: 'Could not reach the TV. Is the setup screen still open? ' + (err.message || '')});
  } finally {
    btn.disabled = false; btn.textContent = 'Save to TV';
  }
});
</script>''');
}

String _text(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
String _attr(String s) => _text(s).replaceAll('"', '&quot;');
