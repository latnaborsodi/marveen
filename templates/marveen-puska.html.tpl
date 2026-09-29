<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{TITLE}}</title>
<style>
{{CSS}}
</style>
</head>
<body>
<div class="wrap">

<header class="top">
  <div>
    <h1>{{TITLE}}</h1>
    <div class="sub">{{SUBTITLE}}</div>
    <div class="sub">Forrás: <code>{{SOURCE_PATH}}</code><br>
      A forrás utolsó módosítása: <b>{{SOURCE_MTIME}}</b> · ez a lap generálva: {{GENERATED}}</div>
  </div>
  <button class="theme" onclick="var r=document.documentElement;r.dataset.theme=r.dataset.theme==='dark'?'light':'dark'">világos / sötét</button>
</header>

<div class="layout">
<nav class="toc" id="toc"></nav>
<main id="main">

<input id="q" type="search" placeholder="Szűrés… (pl. 409, pgpass, robots, deploy)" autocomplete="off">

{{BODY}}

<div id="noresult" class="empty hide">Nincs találat.</div>

</main>
</div>
</div>

<script>
(function(){
  var main = document.getElementById('main');
  var secs = Array.prototype.slice.call(main.querySelectorAll('section'));
  var toc = document.getElementById('toc');
  secs.forEach(function(s){
    var h = s.querySelector('h2');
    if (!h) return;
    var a = document.createElement('a');
    a.href = '#' + s.id;
    a.textContent = h.textContent;
    toc.appendChild(a);
  });
  var q = document.getElementById('q');
  var none = document.getElementById('noresult');
  q.addEventListener('input', function(){
    var t = q.value.trim().toLowerCase();
    var hits = 0;
    secs.forEach(function(s){
      var show = !t || s.textContent.toLowerCase().indexOf(t) !== -1;
      s.classList.toggle('hide', !show);
      if (show) hits++;
    });
    none.classList.toggle('hide', hits > 0);
  });
})();
</script>
</body>
</html>
