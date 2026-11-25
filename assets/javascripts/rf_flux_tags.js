/*
 * Redmineflux Tags: the tag input and the inline editor of the issue page.
 *
 * Plain JavaScript, no jQuery, jQuery UI or CDN, so it behaves the same on
 * Redmine 5, 6 and 7. Everything lives under window.RfFluxTags; DOM hooks are
 * data-rf-flux-tags-* attributes and rf-flux-tags-* classes.
 *
 * Any <input data-rf-flux-tags-input> becomes a chip input. The original
 * input stays in the form (hidden) and always holds the comma separated list,
 * so forms keep posting exactly what they posted before.
 */
(function () {
  'use strict';

  if (window.RfFluxTags && window.RfFluxTags.ready) { return; }

  var config = window.RfFluxTagsConfig || { i18n: {} };
  var uid = 0;

  /* ---------- helpers ---------- */

  function t(key, vars) {
    var text = (config.i18n && config.i18n[key]) || key;
    if (vars) {
      Object.keys(vars).forEach(function (name) {
        text = text.split('%{' + name + '}').join(String(vars[name]));
      });
    }
    return text;
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (name) {
      var value = attrs[name];
      if (value === null || value === undefined || value === false) { return; }
      if (name === 'text') { node.textContent = value; }
      else if (name === 'class') { node.className = value; }
      else if (name.indexOf('on') === 0 && typeof value === 'function') { node.addEventListener(name.slice(2), value); }
      else { node.setAttribute(name, value === true ? '' : value); }
    });
    (children || []).forEach(function (child) {
      if (child) { node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child); }
    });
    return node;
  }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }

  // JSON request with the session cookie and the CSRF token.
  function request(method, url, body) {
    var options = {
      method: method,
      credentials: 'same-origin',
      headers: { 'Accept': 'application/json', 'X-CSRF-Token': csrfToken(), 'X-Requested-With': 'XMLHttpRequest' }
    };
    if (body !== undefined) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    return fetch(url, options).then(function (response) {
      return response.text().then(function (text) {
        var data = null;
        try { data = text ? JSON.parse(text) : {}; } catch (e) { data = {}; }
        if (!response.ok) {
          var error = new Error((data && data.error) || t('rf_flux_tags_error_generic'));
          error.status = response.status;
          throw error;
        }
        return data;
      });
    });
  }

  function debounce(fn, wait) {
    var timer = null;
    var wrapper = function () {
      var args = arguments, self = this;
      clearTimeout(timer);
      timer = setTimeout(function () { fn.apply(self, args); }, wait);
    };
    wrapper.cancel = function () { clearTimeout(timer); };
    return wrapper;
  }

  var toastTimer = null;
  function toast(message, isError) {
    var node = document.getElementById('rf-flux-tags-toast');
    if (!node) {
      node = el('div', { id: 'rf-flux-tags-toast', 'class': 'rf-flux-tags-toast', role: 'status', 'aria-live': 'polite' });
      document.body.appendChild(node);
    }
    node.textContent = message;
    node.classList.toggle('is-error', !!isError);
    node.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { node.hidden = true; }, 3200);
  }

  function parseList(value) {
    var seen = {}, list = [];
    String(value || '').split(/[,\n]/).forEach(function (part) {
      var name = part.replace(/\s+/g, ' ').trim();
      var key = name.toLowerCase();
      if (name && !seen[key]) { seen[key] = true; list.push(name); }
    });
    return list;
  }

  /* ---------- tag input ---------- */

  function TagInput(source) {
    var self = this;
    uid += 1;
    this.id = 'rf-flux-tags-input-' + uid;
    this.source = source;
    this.limit = parseInt(source.getAttribute('data-limit'), 10) || 30;
    this.url = source.getAttribute('data-suggest-url');
    this.maxLength = 60;
    this.colors = {};
    try { this.colors = JSON.parse(source.getAttribute('data-colors') || '{}') || {}; } catch (e) { this.colors = {}; }
    this.values = parseList(source.value);
    this.items = [];
    this.active = -1;
    this.navigated = false;   // true once the user moved through the suggestions with the arrow keys
    this.request = null;

    this.root = el('div', { 'class': 'rf-flux-tags-input' });
    this.box = el('div', { 'class': 'rf-flux-tags-input__box' });
    this.field = el('input', {
      type: 'text', 'class': 'rf-flux-tags-input__field', autocomplete: 'off', spellcheck: 'false',
      maxlength: this.maxLength, role: 'combobox', 'aria-autocomplete': 'list', 'aria-expanded': 'false',
      'aria-controls': this.id + '-list', placeholder: source.getAttribute('data-placeholder') || '',
      id: this.id + '-field'
    });
    // The field stands in for the original input: its label, its aria name.
    var label = source.id ? document.querySelector('label[for="' + source.id + '"]') : null;
    if (label) {
      label.setAttribute('for', this.field.id);
      this.field.setAttribute('aria-labelledby', label.id || (label.id = this.id + '-label'));
    }
    this.list = el('ul', { 'class': 'rf-flux-tags-input__list', role: 'listbox', id: this.id + '-list', hidden: true });
    this.hint = el('span', { 'class': 'rf-flux-tags-input__hint', text: t('rf_flux_tags_input_hint') });
    this.count = el('span', { 'class': 'rf-flux-tags-input__count', 'aria-live': 'polite' });
    this.meta = el('div', { 'class': 'rf-flux-tags-input__meta' }, [this.hint, this.count]);
    this.root.appendChild(this.box);
    this.root.appendChild(this.list);
    this.root.appendChild(this.meta);

    source.classList.add('rf-flux-tags-source');
    source.setAttribute('tabindex', '-1');
    source.setAttribute('aria-hidden', 'true');
    source.parentNode.insertBefore(this.root, source.nextSibling);
    source.setAttribute('data-rf-flux-tags-ready', '1');
    source.rfFluxTags = this;

    this.box.addEventListener('click', function (event) {
      if (event.target === self.box) { self.field.focus(); }
    });
    var later = debounce(function () { self.suggest(); }, 140);
    this.cancelSuggest = later.cancel;
    this.field.addEventListener('input', function () { self.navigated = false; later(); });
    this.field.addEventListener('focus', function () {
      // The editor on the issue page focuses the field itself when it opens; the list must not pop up over the buttons then.
      if (self.quietFocus) { self.quietFocus = false; return; }
      self.suggest();
    });
    this.field.addEventListener('blur', function () {
      // Keep what was typed: a click on Save must not lose it.
      setTimeout(function () { self.commit(); self.close(); }, 120);
    });
    // Clicking the field shows the suggestions (focus alone does not, when the editor focused it by itself).
    this.field.addEventListener('click', function () { if (self.list.hidden) { self.suggest(); } });
    this.field.addEventListener('keydown', function (event) { self.onKey(event); });
    this.field.addEventListener('paste', function (event) {
      var text = (event.clipboardData || window.clipboardData).getData('text');
      if (/[,\n]/.test(text)) {
        event.preventDefault();
        parseList(text).forEach(function (name) { self.add(name, true); });
        self.render();
        self.sync();
      }
    });
    this.list.addEventListener('mousedown', function (event) {
      var option = event.target.closest('[data-name]');
      if (option) {
        event.preventDefault();
        self.add(option.getAttribute('data-name'), false, option.getAttribute('data-color'));
        self.field.focus();
      }
    });
    this.render();
  }

  // The colour of a chip whose tag has no chosen colour (a tag typed just now, not saved yet). Same sum and same
  // colours as RfFluxTags::Colors.generated on the server, so the chip looks the same after saving.
  var GENERATED = ['#dc2626', '#ea580c', '#d97706', '#a16207', '#65a30d', '#16a34a', '#059669', '#0d9488', '#0891b2', '#0284c7', '#2563eb', '#4f46e5', '#7c3aed', '#9333ea', '#c026d3', '#db2777', '#e11d48', '#92400e', '#475569', '#166534', '#1e40af', '#86198f', '#115e59', '#9f1239'];
  function generatedColor(name) {
    var bytes = unescape(encodeURIComponent(String(name).toLowerCase())), hash = 2166136261;
    for (var i = 0; i < bytes.length; i++) { hash = Math.imul(hash ^ bytes.charCodeAt(i), 16777619) >>> 0; }
    return GENERATED[hash % GENERATED.length];
  }

  TagInput.prototype.render = function () {
    var self = this;
    // Only the chips are redrawn: the text field stays in the page, so it keeps keyboard focus.
    if (this.field.parentNode !== this.box) { this.box.appendChild(this.field); }
    [].slice.call(this.box.children).forEach(function (node) { if (node !== self.field) { self.box.removeChild(node); } });
    this.values.forEach(function (name, index) {
      var color = self.colors[name] || generatedColor(name);
      var chip = el('span', { 'class': 'rf-flux-tags-chip', style: (color && /^#[0-9a-fA-F]{6}$/.test(color)) ? '--rf-flux-tags-color:' + color : null }, [
        el('span', { 'class': 'rf-flux-tags-chip__name', text: name }),
        el('button', {
          type: 'button', 'class': 'rf-flux-tags-chip__remove', text: '×',
          'aria-label': t('rf_flux_tags_input_remove', { name: name }),
          onclick: function (event) { event.stopPropagation(); self.remove(index); self.field.focus(); }
        })
      ]);
      self.box.insertBefore(chip, self.field);
    });
    if (this.field.parentNode !== this.box) { this.box.appendChild(this.field); }
    var full = this.values.length >= this.limit;
    this.field.disabled = full;
    this.count.textContent = this.values.length + ' / ' + this.limit;
    this.hint.textContent = full ? t('rf_flux_tags_input_limit', { count: this.limit }) : t('rf_flux_tags_input_hint');
    if (full) { this.hint.setAttribute('data-rf-flux-tags-warn', '1'); } else { this.hint.removeAttribute('data-rf-flux-tags-warn'); }
  };

  TagInput.prototype.sync = function () {
    this.source.value = this.values.join(', ');
    this.source.dispatchEvent(new Event('change', { bubbles: true }));
  };

  TagInput.prototype.has = function (name) {
    var key = name.toLowerCase();
    return this.values.some(function (value) { return value.toLowerCase() === key; });
  };

  TagInput.prototype.add = function (name, quiet, color) {
    name = String(name || '').replace(/\s+/g, ' ').trim();
    if (!name || this.has(name) || this.values.length >= this.limit) { this.field.value = ''; return; }
    this.values.push(name.slice(0, this.maxLength));
    if (color) { this.colors[name] = color; }
    this.field.value = '';
    // The list closes after a tag is added (it would cover the buttons below); typing opens it again.
    if (!quiet) { this.render(); this.sync(); this.close(); }
  };

  TagInput.prototype.remove = function (index) {
    this.values.splice(index, 1);
    this.render();
    this.sync();
    this.close();
  };

  // Turns the text still in the field into a tag.
  TagInput.prototype.commit = function () {
    var self = this, names = parseList(this.field.value);
    if (!names.length) { this.field.value = ''; return; }
    names.forEach(function (name) { self.add(name, true); });
    this.field.value = '';
    this.render();
    this.sync();
  };

  TagInput.prototype.get = function () { this.commit(); return this.values.slice(); };

  TagInput.prototype.set = function (list) {
    this.values = parseList(Array.isArray(list) ? list.join(',') : list);
    this.field.value = '';
    this.render();
    this.sync();
  };

  TagInput.prototype.close = function () {
    // Anything still on its way (a waiting keystroke, a request in flight) must not reopen the list.
    this.requestId = (this.requestId || 0) + 1;
    if (this.cancelSuggest) { this.cancelSuggest(); }
    this.list.hidden = true;
    this.field.setAttribute('aria-expanded', 'false');
    this.field.removeAttribute('aria-activedescendant');
    this.active = -1;
  };

  TagInput.prototype.suggest = function () {
    var self = this;
    if (!this.url || this.field.disabled || document.activeElement !== this.field) { this.close(); return; }
    var query = this.field.value.trim();
    if (this.request) { this.request.abort(); }
    var requestId = this.requestId = (this.requestId || 0) + 1;
    var controller = typeof AbortController === 'function' ? new AbortController() : null;
    this.request = controller;
    var separator = this.url.indexOf('?') === -1 ? '?' : '&';
    fetch(this.url + separator + 'q=' + encodeURIComponent(query), {
      credentials: 'same-origin', headers: { 'Accept': 'application/json' }, signal: controller ? controller.signal : undefined
    }).then(function (response) { return response.ok ? response.json() : []; })
      .then(function (data) { if (requestId === self.requestId) { self.show(Array.isArray(data) ? data : [], query); } })
      .catch(function () { /* aborted or offline: keep what is shown */ });
  };

  TagInput.prototype.show = function (data, query) {
    var self = this;
    var items = data.filter(function (item) { return !self.has(item.name); });
    var exact = items.concat(this.values.map(function (name) { return { name: name }; }))
      .some(function (item) { return item.name.toLowerCase() === query.toLowerCase(); });
    if (query && !exact) { items.push({ name: query, create: true }); }
    this.items = items;
    this.active = items.length ? 0 : -1;
    while (this.list.firstChild) { this.list.removeChild(this.list.firstChild); }
    if (!items.length) { this.close(); return; }
    items.forEach(function (item, index) {
      var option = el('li', {
        'class': 'rf-flux-tags-input__option' + (item.create ? ' rf-flux-tags-input__option--new' : ''),
        role: 'option', id: self.id + '-option-' + index, 'aria-selected': index === 0 ? 'true' : 'false',
        'data-name': item.name, 'data-color': item.color || null
      }, [
        el('span', { text: item.create ? t('rf_flux_tags_input_create', { name: item.name }) : item.name }),
        item.create || !item.count ? null : el('small', { text: t('rf_flux_tags_input_uses', { count: item.count }) })
      ]);
      self.list.appendChild(option);
    });
    this.list.hidden = false;
    this.place();
    this.field.setAttribute('aria-expanded', 'true');
    this.field.setAttribute('aria-activedescendant', this.id + '-option-0');
  };

  // The list opens below the field. When there is not enough room below (the tag field is the last field of a
  // form: the page or the content area ends right under it) and there is more room above, it opens upwards.
  TagInput.prototype.place = function () {
    var list = this.list;
    list.classList.remove('is-up');
    var box = this.root.getBoundingClientRect();
    var need = Math.min(list.scrollHeight + 10, 240);
    var limit = window.innerHeight, node = this.root.parentNode;
    while (node && node !== document.body && node.nodeType === 1) {
      var overflow = window.getComputedStyle(node).overflowY;
      if (overflow === 'hidden' || overflow === 'auto' || overflow === 'scroll') { limit = Math.min(limit, node.getBoundingClientRect().bottom); }
      node = node.parentNode;
    }
    var below = limit - box.bottom, above = box.top;
    if (below < need && above > below) { list.classList.add('is-up'); }
  };

  TagInput.prototype.highlight = function (index) {
    var options = this.list.querySelectorAll('[role="option"]');
    if (!options.length) { return; }
    this.active = (index + options.length) % options.length;
    for (var i = 0; i < options.length; i++) { options[i].setAttribute('aria-selected', i === this.active ? 'true' : 'false'); }
    this.field.setAttribute('aria-activedescendant', options[this.active].id);
    options[this.active].scrollIntoView({ block: 'nearest' });
  };

  TagInput.prototype.onKey = function (event) {
    var open = !this.list.hidden;
    if (event.key === 'ArrowDown') { event.preventDefault(); if (open) { this.navigated = true; this.highlight(this.active + 1); } else { this.suggest(); } }
    else if (event.key === 'ArrowUp') { event.preventDefault(); if (open) { this.navigated = true; this.highlight(this.active - 1); } }
    else if (event.key === 'Enter') {
      event.preventDefault();       // never submit the surrounding form from here
      var typed = this.field.value.trim();
      var picked = null;
      if (open && this.navigated && this.items[this.active]) {
        picked = this.items[this.active];          // chosen with the arrow keys
      } else if (typed) {
        var key = typed.toLowerCase();             // typed text that is an existing tag keeps that tag's spelling
        picked = this.items.filter(function (item) { return !item.create && item.name.toLowerCase() === key; })[0] || null;
      }
      if (picked && picked.create) { this.add(picked.name); }
      else if (picked) { this.add(picked.name, false, picked.color); }
      else if (typed) { this.add(typed); }
    }
    else if (event.key === ',') { event.preventDefault(); this.commit(); }
    else if (event.key === 'Backspace' && !this.field.value && this.values.length) { this.remove(this.values.length - 1); }
    else if (event.key === 'Escape') { if (open) { event.stopPropagation(); this.close(); } }
  };

  function enhance(root) {
    var scope = root && root.querySelectorAll ? root : document;
    var inputs = scope.querySelectorAll('input[data-rf-flux-tags-input]:not([data-rf-flux-tags-ready])');
    for (var i = 0; i < inputs.length; i++) { new TagInput(inputs[i]); }
  }

  /* ---------- inline editor on the issue page ---------- */

  function IssueRow(row) {
    var self = this;
    this.row = row;
    this.url = row.getAttribute('data-url');
    this.view = row.querySelector('.rf-flux-tags-row__view');
    this.editor = row.querySelector('[data-rf-flux-tags-editor]');
    this.chips = row.querySelector('[data-rf-flux-tags-chips]');
    this.source = row.querySelector('input[data-rf-flux-tags-input]');
    this.message = row.querySelector('[data-rf-flux-tags-message]');
    this.saveButton = row.querySelector('[data-rf-flux-tags-save]');
    this.original = this.source ? this.source.value : '';
    var edit = row.querySelector('[data-rf-flux-tags-edit]');
    if (edit) { edit.addEventListener('click', function () { self.open(); }); }
    this.saveButton.addEventListener('click', function () { self.save(); });
    row.querySelector('[data-rf-flux-tags-cancel]').addEventListener('click', function () { self.close(true); });
    this.editor.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && !event.defaultPrevented) { self.close(true); }
    });
  }

  IssueRow.prototype.open = function () {
    this.view.hidden = true;
    this.editor.hidden = false;
    enhance(this.editor);
    this.message.textContent = '';
    var input = this.source.rfFluxTags;
    input.quietFocus = true;
    input.field.focus();
    setTimeout(function () { input.quietFocus = false; }, 0);
  };

  IssueRow.prototype.close = function (reset) {
    if (reset && this.source.rfFluxTags) { this.source.rfFluxTags.set(this.original); }
    this.editor.hidden = true;
    this.view.hidden = false;
    var edit = this.row.querySelector('[data-rf-flux-tags-edit]');
    if (edit) { edit.focus(); }
  };

  IssueRow.prototype.save = function () {
    var self = this;
    var names = this.source.rfFluxTags.get();
    this.saveButton.disabled = true;
    this.message.classList.remove('is-error');
    this.message.textContent = t('rf_flux_tags_saving');
    request('PATCH', this.url, { tag_list: names.join(', ') }).then(function (data) {
      self.chips.innerHTML = data.chips_html;     // server-rendered, escaped markup
      self.original = (data.tags || []).join(', ');
      self.source.rfFluxTags.set(self.original);
      self.syncOtherFields(data.tags || []);
      self.saveButton.disabled = false;
      self.message.textContent = '';
      self.close(false);
      toast(t('rf_flux_tags_saved'));
      self.refreshHistory();
    }).catch(function (error) {
      self.saveButton.disabled = false;
      self.message.classList.add('is-error');
      self.message.textContent = error.message;
    });
  };

  // The full "Edit" form of the issue (same page) has its own Tags field: keep it in step,
  // so it shows the tags just saved without a page reload.
  IssueRow.prototype.syncOtherFields = function (tags) {
    var self = this;
    [].forEach.call(document.querySelectorAll('input[name="issue[tag_list]"]'), function (field) {
      if (self.row.contains(field)) { return; }
      if (field.rfFluxTags) { field.rfFluxTags.set(tags); } else { field.value = tags.join(', '); }
    });
  };

  // The tag change appears in the History block without reloading the page.
  IssueRow.prototype.refreshHistory = function () {
    var selector = this.row.getAttribute('data-history-selector') || '#history';
    var current = document.querySelector(selector);
    if (!current) { return; }
    fetch(window.location.href, { credentials: 'same-origin', headers: { 'Accept': 'text/html' } })
      .then(function (response) { return response.ok ? response.text() : ''; })
      .then(function (html) {
        if (!html) { return; }
        var fresh = new DOMParser().parseFromString(html, 'text/html').querySelector(selector);
        if (fresh) { current.innerHTML = fresh.innerHTML; }
      }).catch(function () { /* the next page load shows it */ });
  };

  function initRows(root) {
    var scope = root && root.querySelectorAll ? root : document;
    var rows = scope.querySelectorAll('[data-rf-flux-tags-issue]:not([data-rf-flux-tags-row-ready])');
    for (var i = 0; i < rows.length; i++) {
      rows[i].setAttribute('data-rf-flux-tags-row-ready', '1');
      new IssueRow(rows[i]);
    }
  }

  function boot() {
    enhance(document);
    initRows(document);
  }

  // Forms are re-drawn by Redmine (tracker change, ajax edit): enhance new inputs as they appear.
  if (typeof MutationObserver === 'function') {
    new MutationObserver(debounce(boot, 50)).observe(document.documentElement, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', boot); } else { boot(); }

  window.RfFluxTags = {
    ready: true, t: t, el: el, request: request, toast: toast, debounce: debounce, parseList: parseList,
    enhance: enhance, TagInput: TagInput, config: config
  };
})();
