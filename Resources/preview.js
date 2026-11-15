window.writerUpdate = function (html, base, template) {
  document.getElementById('base').setAttribute('href', base);
  var link = document.getElementById('template');
  if (link.getAttribute('href') !== template) link.setAttribute('href', template);
  var doc = document.getElementById('doc');
  doc.innerHTML = html;
  doc.querySelectorAll('.math').forEach(function (el) {
    try {
      katex.render(el.textContent, el, { displayMode: el.classList.contains('display'), throwOnError: false });
    } catch (error) {}
  });
  return doc.querySelectorAll('.katex').length;
};

window.writerScroll = function (ratio) {
  var max = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo(0, Math.max(max, 0) * ratio);
};

window.writerReveal = function (id) {
  var target = document.getElementById(id);
  if (target) target.scrollIntoView();
};
