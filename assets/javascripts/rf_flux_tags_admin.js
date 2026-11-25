/*
 * Redmineflux Tags: the tag administration page (Administration > Plugins >
 * Redmineflux Tags plugin > Configure). Plain JavaScript on top of
 * rf_flux_tags.js. The lists come from RfFluxTagsAdminController as JSON and
 * every text from the page configuration, so it follows the user's language.
 */
(function () {
  'use strict';

  function start() {
    var RF = window.RfFluxTags;
    var root = document.getElementById('rf-flux-tags-admin');
    if (!RF || !root || root.getAttribute('data-rf-flux-tags-started')) { return; }
    root.setAttribute('data-rf-flux-tags-started', '1');

    var cfg = JSON.parse(root.getAttribute('data-config'));
    var el = RF.el, t = RF.t, request = RF.request, toast = RF.toast;
    var NOFORM = 'rf-flux-tags-noform';   // inputs point at a form that does not exist, so Enter never submits Redmine's settings form

    var ICON_PATHS = {
      search: '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>',
      edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
      del: '<polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
      eye: '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>',
      plus: '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
      check: '<polyline points="20 6 9 17 4 12"/>',
      up: '<polyline points="18 15 12 9 6 15"/>',
      down: '<polyline points="6 9 12 15 18 9"/>'
    };
    function svg(name, size) {
      return '<svg viewBox="0 0 24 24" width="' + (size || 16) + '" height="' + (size || 16) + '" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + ICON_PATHS[name] + '</svg>';
    }
    function icon(name, size) { var span = el('span', { 'class': 'rf-flux-tags-icon', 'aria-hidden': 'true', style: 'display:inline-flex' }); span.innerHTML = svg(name, size); return span; }
    function button(label, className, onclick, extra) {
      var attrs = { type: 'button', 'class': 'rf-flux-tags-btn ' + (className || ''), onclick: onclick };
      Object.keys(extra || {}).forEach(function (k) { attrs[k] = extra[k]; });
      return el('button', attrs, [label]);
    }
    // A button with an icon in front of its label (Helpdesk style).
    function iconLabelButton(iconName, label, className, onclick, extra) {
      var b = button('', className, onclick, extra);
      b.appendChild(icon(iconName));
      b.appendChild(document.createTextNode(label));
      return b;
    }
    function iconButton(name, label, className, onclick) {
      var b = el('button', { type: 'button', 'class': 'rf-flux-tags-icon-btn ' + (className || ''), title: label, 'aria-label': label, onclick: onclick });
      b.appendChild(icon(name));
      return b;
    }
    function chip(tag) {
      return el('span', {
        'class': 'rf-flux-tags-chip' + (cfg.useColors ? '' : ' rf-flux-tags-chip--plain'),
        style: '--rf-flux-tags-color:' + (/^#[0-9a-fA-F]{6}$/.test(tag.color || '') ? tag.color : '#6b7785'), title: tag.description || null
      }, [el('span', { 'class': 'rf-flux-tags-chip__name', text: tag.name })]);
    }
    function plural(key, count) { return t(key, { count: count }); }

    /* ---------- modal ---------- */

    var modalState = null;
    function openModal(spec) {
      closeModal();
      var previous = document.activeElement;
      var close = el('button', { type: 'button', 'class': 'rf-flux-tags-modal__close', 'aria-label': t('rf_flux_tags_close'), text: '×', onclick: function () { closeModal(); } });
      var header = el('div', { 'class': 'rf-flux-tags-modal__header' }, [el('h3', { 'class': 'rf-flux-tags-modal__title', id: 'rf-flux-tags-modal-title', text: spec.title }), close]);
      var body = el('div', { 'class': 'rf-flux-tags-modal__body' });
      if (spec.sub) { body.appendChild(el('p', { 'class': 'rf-flux-tags-modal__sub', text: spec.sub })); }
      if (spec.body) { body.appendChild(spec.body); }
      var error = el('p', { 'class': 'rf-flux-tags-error', role: 'alert', hidden: true });
      body.appendChild(error);
      var cancel = button(t('button_cancel'), '', function () { closeModal(); });
      var confirmClass = spec.confirmClass || 'rf-flux-tags-btn--primary';
      var confirm = spec.confirmIcon === false
        ? button(spec.confirmLabel, confirmClass, function () { spec.onConfirm(api); })
        : iconLabelButton(spec.confirmIcon || 'check', spec.confirmLabel, confirmClass, function () { spec.onConfirm(api); });
      var footer = el('div', { 'class': 'rf-flux-tags-modal__foot' }, [cancel, confirm]);
      var box = el('div', { 'class': 'rf-flux-tags-modal', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'rf-flux-tags-modal-title' }, [header, body, footer]);
      var scrim = el('div', { 'class': 'rf-flux-tags-scrim' }, [box]);
      scrim.addEventListener('mousedown', function (event) { if (event.target === scrim) { closeModal(); } });
      scrim.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') { event.stopPropagation(); closeModal(); return; }
        if (event.key === 'Tab') {
          var items = box.querySelectorAll('button:not([disabled]), input:not([disabled]), select, [tabindex]:not([tabindex="-1"])');
          if (!items.length) { return; }
          var first = items[0], last = items[items.length - 1];
          if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
          else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
        }
      });
      document.body.appendChild(scrim);
      var api = {
        close: closeModal,
        busy: function (on) { confirm.disabled = on; cancel.disabled = on; },
        fail: function (message) { error.textContent = message; error.hidden = false; confirm.disabled = false; cancel.disabled = false; },
        clearError: function () { error.hidden = true; }
      };
      modalState = { scrim: scrim, previous: previous };
      var focus = box.querySelector('input[type="text"], input:not([type])') || confirm;
      focus.focus();
      return api;
    }
    function closeModal() {
      if (!modalState) { return; }
      if (modalState.scrim.parentNode) { modalState.scrim.parentNode.removeChild(modalState.scrim); }
      if (modalState.previous && modalState.previous.focus && document.body.contains(modalState.previous)) { modalState.previous.focus(); }
      modalState = null;
    }

    /* ---------- tag form (new / edit) ---------- */

    function tagForm(tag, onSubmit) {
      var selected = tag && tag.custom_color ? tag.custom_color : '';
      var name = el('input', { type: 'text', id: 'rf-flux-tags-field-name', value: tag ? tag.name : '', maxlength: cfg.maxName, autocomplete: 'off', form: NOFORM });
      var wrap = el('div', {}, [
        el('div', { 'class': 'rf-flux-tags-field' }, [
          el('label', { 'for': 'rf-flux-tags-field-name', text: t('rf_flux_tags_field_name') }), name,
          el('span', { 'class': 'rf-flux-tags-hint', text: t('rf_flux_tags_field_name_hint', { count: cfg.maxName }) })
        ])
      ]);
      var description = null, swatches = null;
      if (cfg.extras) {
        var group = el('div', { 'class': 'rf-flux-tags-swatches', role: 'group', 'aria-labelledby': 'rf-flux-tags-color-label' });
        var buttons = [];
        function mark() { buttons.forEach(function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-color') === selected ? 'true' : 'false'); }); }
        buttons.push(el('button', { type: 'button', 'data-color': '', text: t('rf_flux_tags_color_auto'), onclick: function () { selected = ''; mark(); } }));
        cfg.palette.forEach(function (hex) {
          buttons.push(el('button', {
            type: 'button', 'class': 'rf-flux-tags-swatch', 'data-color': hex, style: '--rf-flux-tags-color:' + (/^#[0-9a-fA-F]{6}$/.test(hex || '') ? hex : '#6b7785'),
            'aria-label': hex, onclick: function () { selected = hex; mark(); }
          }));
        });
        buttons.forEach(function (b) { group.appendChild(b); });
        mark();
        swatches = group;
        wrap.appendChild(el('div', { 'class': 'rf-flux-tags-field' }, [
          el('span', { 'class': 'rf-flux-tags-field__label', id: 'rf-flux-tags-color-label', text: t('rf_flux_tags_field_color') }), group,
          el('span', { 'class': 'rf-flux-tags-hint', text: t('rf_flux_tags_field_color_hint') })
        ]));
        description = el('input', { type: 'text', id: 'rf-flux-tags-field-description', value: tag ? tag.description || '' : '', maxlength: cfg.maxDescription, autocomplete: 'off', form: NOFORM });
        wrap.appendChild(el('div', { 'class': 'rf-flux-tags-field' }, [
          el('label', { 'for': 'rf-flux-tags-field-description', text: t('rf_flux_tags_field_description') }), description,
          el('span', { 'class': 'rf-flux-tags-hint', text: t('rf_flux_tags_field_description_hint') })
        ]));
      }
      wrap.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' && event.target.tagName === 'INPUT') { event.preventDefault(); onSubmit(); }
      });
      return {
        node: wrap,
        values: function () {
          var data = { name: name.value };
          if (cfg.extras) { data.color = selected; data.description = description.value; }
          return data;
        }
      };
    }

    /* ---------- list panel ---------- */

    function ListPanel(host, context) {
      var self = this;
      this.host = host;
      this.context = context;
      this.state = { q: '', filter: 'all', sort: 'name', dir: 'asc', page: 1, perPage: 10 };
      this.selected = {};           // id -> name
      this.rows = [];
      this.pagination = { page: 1, pages: 1, total: 0, per_page: 10 };
      this.stats = cfg.stats;
      this.loaded = false;
      this.seq = 0;

      this.search = el('input', { type: 'search', 'class': 'rf-flux-tags-search__input', placeholder: t('rf_flux_tags_search_placeholder'), 'aria-label': t('rf_flux_tags_search_placeholder'), form: NOFORM, autocomplete: 'off' });
      this.search.addEventListener('input', RF.debounce(function () {
        self.state.q = self.search.value.trim(); self.state.page = 1; self.load();
      }, 250));
      this.search.addEventListener('keydown', function (event) { if (event.key === 'Enter') { event.preventDefault(); } });
      var searchWrap = el('div', { 'class': 'rf-flux-tags-search' }, [this.search]);
      var glass = el('span', {}); glass.innerHTML = svg('search', 15); searchWrap.insertBefore(glass.firstChild, this.search);

      this.btnAll = el('button', { type: 'button', text: t('rf_flux_tags_filter_all'), onclick: function () { self.setFilter('all'); } });
      this.btnUnused = el('button', { type: 'button', onclick: function () { self.setFilter('unused'); } });
      var seg = el('div', { 'class': 'rf-flux-tags-seg', role: 'group' }, [this.btnAll, this.btnUnused]);
      this.btnDeleteUnused = iconLabelButton('del', t('rf_flux_tags_delete_unused'), 'rf-flux-tags-btn--danger', function () { self.deleteUnused(); });
      this.btnNew = iconLabelButton('plus', t('rf_flux_tags_new_tag'), 'rf-flux-tags-btn--primary', function () { self.newTag(); });

      this.toolbar = el('div', { 'class': 'rf-flux-tags-toolbar' }, [
        searchWrap, seg, el('span', { 'class': 'rf-flux-tags-toolbar__spacer' }), this.btnDeleteUnused, this.btnNew
      ]);
      this.bulk = el('div', { 'class': 'rf-flux-tags-bar', hidden: true });
      this.banner = el('div', { 'class': 'rf-flux-tags-bar rf-flux-tags-bar--center', hidden: true });
      this.tableWrap = el('div', { 'class': 'rf-flux-tags-tablewrap' });
      this.pager = el('div', { 'class': 'rf-flux-tags-pager' });
      this.live = el('div', { 'class': 'rf-flux-tags-sr-only', 'aria-live': 'polite' });
      [this.toolbar, this.bulk, this.banner, this.tableWrap, this.pager, this.live].forEach(function (n) { host.appendChild(n); });
      this.renderToolbar();
    }

    ListPanel.prototype.activate = function () { if (!this.loaded) { this.load(); } };

    ListPanel.prototype.setFilter = function (filter) {
      this.state.filter = filter; this.state.page = 1; this.load();
    };

    ListPanel.prototype.params = function (extra) {
      var s = this.state, p = { context: this.context, q: s.q, filter: s.filter, sort: s.sort, dir: s.dir, page: s.page, per_page: s.perPage };
      Object.keys(extra || {}).forEach(function (k) { p[k] = extra[k]; });
      return Object.keys(p).map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(p[k]); }).join('&');
    };

    ListPanel.prototype.load = function () {
      var self = this, seq = ++this.seq;
      this.tableWrap.setAttribute('aria-busy', 'true');
      if (!this.loaded) { this.tableWrap.textContent = t('rf_flux_tags_loading'); }
      request('GET', cfg.urls.list + '?' + this.params()).then(function (data) {
        if (seq !== self.seq) { return; }
        self.loaded = true;
        self.rows = data.tags;
        self.pagination = data.pagination;
        self.stats = data.stats;
        self.state.page = data.pagination.page;
        self.render();
        updateBadges(data.stats);
      }).catch(function (error) {
        if (seq !== self.seq) { return; }
        self.tableWrap.removeAttribute('aria-busy');
        toast(error.message, true);
      });
    };

    ListPanel.prototype.reload = function () { this.load(); };

    ListPanel.prototype.render = function () {
      this.renderToolbar();
      this.renderBulk();
      this.renderTable();
      this.renderPager();
      this.tableWrap.removeAttribute('aria-busy');
      this.live.textContent = t('rf_flux_tags_range', { from: this.rows.length ? (this.pagination.page - 1) * this.pagination.per_page + 1 : 0, to: (this.pagination.page - 1) * this.pagination.per_page + this.rows.length, total: this.pagination.total });
    };

    ListPanel.prototype.renderToolbar = function () {
      var unused = this.stats ? this.stats.unused : 0;
      this.btnAll.setAttribute('aria-pressed', this.state.filter === 'all' ? 'true' : 'false');
      this.btnUnused.setAttribute('aria-pressed', this.state.filter === 'unused' ? 'true' : 'false');
      this.btnUnused.textContent = t('rf_flux_tags_filter_unused') + ' (' + unused + ')';
      this.btnDeleteUnused.hidden = !(unused > 0 && this.state.filter === 'unused');
    };

    ListPanel.prototype.selectedIds = function () { return Object.keys(this.selected).map(Number); };

    ListPanel.prototype.renderBulk = function () {
      var self = this, ids = this.selectedIds();
      this.bulk.hidden = ids.length === 0;
      this.bulk.textContent = '';
      if (ids.length) {
        var del = iconLabelButton('del', t('button_delete'), 'rf-flux-tags-btn--danger rf-flux-tags-btn--compact', function () { self.deleteSelected(); });
        [el('strong', { text: t('rf_flux_tags_selected', { count: ids.length }) }), del,
         el('span', { 'class': 'rf-flux-tags-toolbar__spacer' }),
         button(t('rf_flux_tags_clear_selection'), 'rf-flux-tags-btn--compact', function () { self.selected = {}; self.render(); })
        ].forEach(function (n) { self.bulk.appendChild(n); });
      }
      // "Select all N matching tags" across every page.
      this.banner.textContent = '';
      var total = this.pagination.total;
      var onPage = this.rows.length > 0 && this.rows.every(function (r) { return self.selected[r.id] !== undefined; });
      var everything = total > 0 && ids.length >= total && onPage;
      if (total > this.rows.length && onPage && !everything) {
        this.banner.hidden = false;
        this.banner.appendChild(el('span', { text: t('rf_flux_tags_select_all_page', { count: this.rows.length }) + ' ' }));
        this.banner.appendChild(button(t('rf_flux_tags_select_all_matching', { count: total }), 'rf-flux-tags-btn--primary rf-flux-tags-btn--compact', function () { self.selectAllMatching(); }));
      } else if (everything && total > this.rows.length) {
        this.banner.hidden = false;
        this.banner.appendChild(el('span', { text: t('rf_flux_tags_all_selected', { count: total }) }));
      } else { this.banner.hidden = true; }
    };

    ListPanel.prototype.selectAllMatching = function () {
      var self = this;
      request('GET', cfg.urls.ids + '?' + this.params()).then(function (data) {
        data.tags.forEach(function (tag) { self.selected[tag.id] = tag.name; });
        self.render();
      }).catch(function (error) { toast(error.message, true); });
    };

    // Updates the checkboxes, the highlighted rows and the bars in place, so keyboard focus stays where it is.
    ListPanel.prototype.syncChecks = function () {
      var self = this;
      [].forEach.call(this.tableWrap.querySelectorAll('input[data-rf-flux-tags-id]'), function (box) {
        var on = self.selected[box.getAttribute('data-rf-flux-tags-id')] !== undefined;
        box.checked = on;
        box.closest('tr').classList.toggle('is-selected', on);
      });
      if (this.checkAll) {
        this.checkAll.checked = this.rows.length > 0 && this.rows.every(function (r) { return self.selected[r.id] !== undefined; });
      }
      this.renderBulk();
    };

    ListPanel.prototype.sortHeader = function (key, label) {
      var self = this, active = this.state.sort === key;
      var b = el('button', { type: 'button', title: t('rf_flux_tags_sort_by', { column: label }), onclick: function () {
        if (self.state.sort === key) { self.state.dir = self.state.dir === 'asc' ? 'desc' : 'asc'; } else { self.state.sort = key; self.state.dir = key === 'count' ? 'desc' : 'asc'; }
        self.state.page = 1; self.load();
      } }, [label]);
      if (active) { b.appendChild(icon(this.state.dir === 'asc' ? 'up' : 'down')); }
      return b;
    };

    ListPanel.prototype.renderTable = function () {
      var self = this;
      this.tableWrap.textContent = '';
      if (!this.rows.length) {
        this.tableWrap.appendChild(el('div', { 'class': 'rf-flux-tags-emptystate' }, [
          el('strong', { text: t('rf_flux_tags_empty_title') }), el('span', { text: t('rf_flux_tags_empty_hint') })
        ]));
        return;
      }
      var allOnPage = this.rows.every(function (r) { return self.selected[r.id] !== undefined; });
      var checkAll = el('input', { type: 'checkbox', 'aria-label': t('rf_flux_tags_select_page'), form: NOFORM });
      checkAll.checked = allOnPage;
      this.checkAll = checkAll;
      checkAll.addEventListener('change', function () {
        self.rows.forEach(function (r) { if (checkAll.checked) { self.selected[r.id] = r.name; } else { delete self.selected[r.id]; } });
        self.syncChecks();
      });
      var max = Math.max.apply(null, this.rows.map(function (r) { return r.count || 0; }).concat([1]));
      var ariaSort = function (key) { return self.state.sort === key ? (self.state.dir === 'asc' ? 'ascending' : 'descending') : 'none'; };
      var head = el('tr', {}, [
        el('th', { 'class': 'rf-flux-tags-col-check', scope: 'col' }, [checkAll]),
        el('th', { scope: 'col', 'aria-sort': ariaSort('name') }, [this.sortHeader('name', t('rf_flux_tags_col_tag'))]),
        el('th', { scope: 'col', 'class': 'rf-flux-tags-col-num', 'aria-sort': ariaSort('count') }, [this.sortHeader('count', t('rf_flux_tags_col_uses'))]),
        el('th', { scope: 'col', text: t('rf_flux_tags_col_status') }),
        el('th', { scope: 'col' })
      ]);
      var body = el('tbody');
      this.rows.forEach(function (tag) {
        var check = el('input', { type: 'checkbox', 'aria-label': t('rf_flux_tags_select_row', { name: tag.name }), form: NOFORM });
        check.checked = self.selected[tag.id] !== undefined;
        check.addEventListener('change', function () {
          if (check.checked) { self.selected[tag.id] = tag.name; } else { delete self.selected[tag.id]; }
          self.syncChecks();
        });
        check.setAttribute('data-rf-flux-tags-id', tag.id);
        var nameCell = el('td', {}, [el('button', { type: 'button', 'class': 'rf-flux-tags-tagbtn', onclick: function () { self.openDrawer(tag); } }, [chip(tag)])]);
        if (tag.description) { nameCell.appendChild(el('div', { 'class': 'rf-flux-tags-desc', text: tag.description })); }
        var unused = (tag.total || 0) === 0;
        var uses = el('td', { 'class': 'rf-flux-tags-col-num' }, [String(tag.count || 0)]);
        uses.appendChild(el('span', { 'class': 'rf-flux-tags-bar-uses', 'aria-hidden': 'true' }, [el('i', { style: 'width:' + Math.round(100 * (tag.count || 0) / max) + '%' })]));
        body.appendChild(el('tr', { 'class': self.selected[tag.id] !== undefined ? 'is-selected' : '' }, [
          el('td', { 'class': 'rf-flux-tags-col-check' }, [check]), nameCell, uses,
          el('td', {}, [el('span', { 'class': 'rf-flux-tags-badge ' + (unused ? 'rf-flux-tags-badge--unused' : 'rf-flux-tags-badge--ok'), text: unused ? t('rf_flux_tags_status_unused') : t('rf_flux_tags_status_in_use') })]),
          el('td', { 'class': 'rf-flux-tags-col-actions' }, [el('div', { 'class': 'rf-flux-tags-actions' }, [
            iconButton('eye', t('rf_flux_tags_view') + ' ' + tag.name, 'rf-flux-tags-icon-btn--view', function () { self.openDrawer(tag); }),
            iconButton('edit', t('button_edit') + ' ' + tag.name, 'rf-flux-tags-icon-btn--edit', function () { self.editTag(tag); }),
            iconButton('del', t('button_delete') + ' ' + tag.name, 'rf-flux-tags-icon-btn--delete', function () { self.deleteTags([tag]); })
          ])])
        ]));
      });
      var table = el('table', { 'class': 'rf-flux-tags-table' }, [el('thead', {}, [head]), body]);
      this.tableWrap.appendChild(table);
    };

    ListPanel.prototype.renderPager = function () {
      var self = this, p = this.pagination;
      this.pager.textContent = '';
      var from = p.total ? (p.page - 1) * p.per_page + 1 : 0, to = (p.page - 1) * p.per_page + this.rows.length;
      function pageButton(label, page, current, disabled, aria) {
        var b = el('button', { type: 'button', text: label, onclick: function () { self.state.page = page; self.load(); } });
        if (aria) { b.setAttribute('aria-label', aria); }
        if (current) { b.setAttribute('aria-current', 'true'); }
        if (disabled) { b.disabled = true; }
        return b;
      }
      if (p.pages > 1) {
        var pages = el('div', { 'class': 'rf-flux-tags-pages', role: 'navigation' });
        pages.appendChild(pageButton('« ' + t('rf_flux_tags_previous'), p.page - 1, false, p.page <= 1));
        var last = 0;
        for (var n = 1; n <= p.pages; n++) {
          if (n === 1 || n === p.pages || Math.abs(n - p.page) <= 2) {
            if (last && n - last > 1) { pages.appendChild(el('span', { 'class': 'rf-flux-tags-gap', text: '…' })); }
            pages.appendChild(pageButton(String(n), n, n === p.page, false));
            last = n;
          }
        }
        pages.appendChild(pageButton(t('rf_flux_tags_next') + ' »', p.page + 1, false, p.page >= p.pages));
        this.pager.appendChild(pages);
      }
      this.pager.appendChild(el('span', { text: '(' + from + '-' + to + '/' + p.total + ')' }));
      var perPage = el('span', { 'class': 'rf-flux-tags-perpage' }, [t('rf_flux_tags_per_page') + ': ']);
      [10, 20, 50, 100].forEach(function (n, i) {
        if (i) { perPage.appendChild(document.createTextNode(', ')); }
        if (n === self.state.perPage) { perPage.appendChild(el('span', { 'class': 'is-current', text: String(n) })); }
        else { perPage.appendChild(el('button', { type: 'button', text: String(n), onclick: function () { self.state.perPage = n; self.state.page = 1; self.load(); } })); }
      });
      this.pager.appendChild(perPage);
    };

    /* ---------- actions ---------- */

    ListPanel.prototype.afterChange = function (message) {
      this.selected = {};
      if (message) { toast(message); }
      panels.forEach(function (p) { if (p.loaded) { p.reload(); } });
    };

    ListPanel.prototype.newTag = function () {
      var self = this, form;
      function submit() { modal.clearError(); modal.busy(true);
        var data = form.values();
        request('POST', cfg.urls.create, data).then(function (res) {
          modal.close();
          self.state.q = ''; self.search.value = ''; self.state.filter = 'unused'; self.state.page = 1;
          self.afterChange(t('rf_flux_tags_toast_created', { name: res.tag.name }));
        }).catch(function (error) { modal.fail(error.message); });
      }
      form = tagForm(null, submit);
      var modal = openModal({ title: t('rf_flux_tags_modal_new_title'), sub: t('rf_flux_tags_modal_new_sub'), body: form.node, confirmLabel: t('rf_flux_tags_create'), confirmIcon: false, onConfirm: submit });
    };

    ListPanel.prototype.editTag = function (tag) {
      var self = this, form;
      function submit() { modal.clearError(); modal.busy(true);
        request('PATCH', cfg.urls.update.replace(':id', tag.id), form.values()).then(function () {
          modal.close(); self.afterChange(t('rf_flux_tags_toast_updated'));
        }).catch(function (error) { modal.fail(error.message); });
      }
      form = tagForm(tag, submit);
      var modal = openModal({ title: t('rf_flux_tags_modal_edit_title'), sub: t('rf_flux_tags_modal_edit_sub'), body: form.node, confirmLabel: t('rf_flux_tags_update'), confirmIcon: false, onConfirm: submit });
    };

    ListPanel.prototype.deleteSelected = function () {
      var self = this;
      this.deleteTags(this.selectedIds().map(function (id) {
        var known = self.rows.filter(function (r) { return r.id === id; })[0];
        return known || { id: id, name: self.selected[id], color: null, total: null };
      }));
    };

    // Delete confirmation, drawn like the Helpdesk plugin's delete modal:
    // red trash icon, centered title and text, Cancel and Delete side by side.
    function confirmDelete(spec) {
      closeModal();
      var previous = document.activeElement;
      var close = el('button', { type: 'button', 'class': 'rf-flux-tags-dmodal__close', 'aria-label': t('rf_flux_tags_close'), text: '✕', onclick: closeModal });
      var icon = el('div', { 'class': 'rf-flux-tags-dmodal__icon' });
      icon.innerHTML = '<span><svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path></svg></span>';
      var error = el('p', { 'class': 'rf-flux-tags-error', role: 'alert', hidden: true });
      var cancel = el('button', { type: 'button', 'class': 'rf-flux-tags-dmodal__btn rf-flux-tags-dmodal__btn--cancel', text: t('button_cancel'), onclick: closeModal });
      var remove = el('button', { type: 'button', 'class': 'rf-flux-tags-dmodal__btn rf-flux-tags-dmodal__btn--delete', text: t('button_delete') });
      var box = el('div', { 'class': 'rf-flux-tags-dmodal', role: 'alertdialog', 'aria-modal': 'true', 'aria-labelledby': 'rf-flux-tags-dmodal-title', 'aria-describedby': 'rf-flux-tags-dmodal-text' }, [
        close, icon,
        el('h2', { 'class': 'rf-flux-tags-dmodal__title', id: 'rf-flux-tags-dmodal-title', text: spec.title }),
        el('p', { 'class': 'rf-flux-tags-dmodal__text', id: 'rf-flux-tags-dmodal-text', text: spec.text }),
        spec.chips ? el('div', { 'class': 'rf-flux-tags-chips rf-flux-tags-dmodal__chips' }, spec.chips.slice(0, 12).map(chip)) : null,
        error,
        el('div', { 'class': 'rf-flux-tags-dmodal__actions' }, [cancel, remove])
      ]);
      var scrim = el('div', { 'class': 'rf-flux-tags-scrim' }, [box]);
      scrim.addEventListener('mousedown', function (event) { if (event.target === scrim) { closeModal(); } });
      scrim.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') { event.stopPropagation(); closeModal(); return; }
        if (event.key === 'Tab') {
          var items = [close, cancel, remove].filter(function (b) { return !b.disabled; });
          var first = items[0], last = items[items.length - 1];
          if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
          else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
        }
      });
      remove.addEventListener('click', function () {
        remove.disabled = true; cancel.disabled = true; error.hidden = true;
        remove.classList.add('is-loading');
        remove.textContent = t('rf_flux_tags_deleting');
        spec.onConfirm({
          close: closeModal,
          fail: function (message) {
            error.textContent = message; error.hidden = false;
            remove.disabled = false; cancel.disabled = false; remove.classList.remove('is-loading'); remove.textContent = t('button_delete');
          }
        });
      });
      document.body.appendChild(scrim);
      modalState = { scrim: scrim, previous: previous };
      cancel.focus();
    }

    ListPanel.prototype.deleteTags = function (tags) {
      var self = this;
      var uses = 0, known = true;
      tags.forEach(function (tag) { if (tag.total === null || tag.total === undefined) { known = false; } else { uses += tag.total; } });
      var text = tags.length === 1 ? t('rf_flux_tags_delete_confirm_one', { name: tags[0].name }) : plural('rf_flux_tags_delete_confirm_many', tags.length);
      if (known) { text += ' ' + (uses === 0 ? t('rf_flux_tags_delete_body_unused') : t('rf_flux_tags_delete_body_used', { count: uses })); }
      confirmDelete({
        title: tags.length === 1 ? t('rf_flux_tags_delete_title_one') : plural('rf_flux_tags_delete_title_many', tags.length),
        text: text, chips: tags.length > 1 ? tags : null,
        onConfirm: function (m) {
          request('DELETE', cfg.urls.destroy, { tag_ids: tags.map(function (tag) { return tag.id; }) }).then(function (res) {
            m.close(); window.location.reload();
          }).catch(function (error) { m.fail(error.message); });
        }
      });
    };

    ListPanel.prototype.deleteUnused = function () {
      var self = this, count = this.stats ? this.stats.unused : 0;
      confirmDelete({
        title: plural('rf_flux_tags_delete_unused_title', count), text: t('rf_flux_tags_delete_unused_body'),
        onConfirm: function (m) {
          request('DELETE', cfg.urls.destroyUnused).then(function (res) {
            m.close(); window.location.reload();
          }).catch(function (error) { m.fail(error.message); });
        }
      });
    };

    /* ---------- detail drawer ---------- */

    var drawer = null;
    ListPanel.prototype.openDrawer = function (tag) {
      var self = this;
      closeDrawer();
      var types = [['issue', 'rf_flux_tags_detail_issues'], ['time_entry', 'rf_flux_tags_detail_time_entries'], ['project', 'rf_flux_tags_detail_projects']];
      var body = el('div', {}, [t('rf_flux_tags_loading')]);
      var closeBtn = el('button', { type: 'button', 'class': 'rf-flux-tags-modal__close', 'aria-label': t('rf_flux_tags_close'), text: '×', onclick: closeDrawer });
      var node = el('aside', { 'class': 'rf-flux-tags-drawer', role: 'dialog', 'aria-label': t('rf_flux_tags_detail_title') }, [
        el('div', { 'class': 'rf-flux-tags-drawer__head' }, [el('h3', {}, [chip(tag)]), closeBtn]),
        el('div', { 'class': 'rf-flux-tags-drawer__body' }, [
          tag.description ? el('p', { 'class': 'rf-flux-tags-hint', text: tag.description }) : null,
          el('div', { 'class': 'rf-flux-tags-drawer__actions' }, [
            iconLabelButton('edit', t('rf_flux_tags_detail_rename'), '', function () { closeDrawer(); self.editTag(tag); }),
            iconLabelButton('del', t('button_delete'), 'rf-flux-tags-btn--danger', function () { closeDrawer(); self.deleteTags([tag]); })
          ]),
          body
        ])
      ]);
      node.addEventListener('keydown', function (event) { if (event.key === 'Escape') { event.stopPropagation(); closeDrawer(); } });
      document.body.appendChild(node);
      drawer = { node: node, previous: document.activeElement };
      closeBtn.focus();
      body.textContent = '';
      var stats = el('div', { 'class': 'rf-flux-tags-drawer__stats' });
      body.appendChild(stats);
      var sections = el('div');
      body.appendChild(sections);
      var any = false, pending = types.length;
      types.forEach(function (pair) {
        var type = pair[0], label = t(pair[1]);
        var stat = el('div', { 'class': 'rf-flux-tags-stat' }, [el('strong', { text: '…' }), el('span', { text: label })]);
        stats.appendChild(stat);
        var section = el('section');
        var list = el('div');
        function load(page) {
          request('GET', cfg.urls.records.replace(':id', tag.id) + '?type=' + type + '&page=' + page).then(function (data) {
            stat.querySelector('strong').textContent = data.pagination.total;
            if (page === 1 && data.pagination.total > 0) {
              any = true;
              section.appendChild(el('h4', { text: label + ' (' + data.pagination.total + ')' }));
              section.appendChild(list);
              sections.appendChild(section);
            }
            data.records.forEach(function (record) {
              list.appendChild(el('a', { 'class': 'rf-flux-tags-record', href: record.url }, [record.label, el('small', { text: record.sub })]));
            });
            var more = section.querySelector('[data-more]');
            if (more) { more.parentNode.removeChild(more); }
            if (data.pagination.page < data.pagination.pages) {
              section.appendChild(el('button', { type: 'button', 'data-more': '1', 'class': 'rf-flux-tags-link', text: t('rf_flux_tags_next'), onclick: function () { load(page + 1); } }));
            }
          }).catch(function () { stat.querySelector('strong').textContent = '-'; })
            .then(function () { pending -= 1; if (pending === 0 && !any) { sections.appendChild(el('p', { 'class': 'rf-flux-tags-hint', text: t('rf_flux_tags_detail_unused') })); } });
        }
        load(1);
      });
      body.appendChild(el('p', { 'class': 'rf-flux-tags-hint', text: t('rf_flux_tags_detail_visible_only') }));
    };
    function closeDrawer() {
      if (!drawer) { return; }
      if (drawer.node.parentNode) { drawer.node.parentNode.removeChild(drawer.node); }
      if (drawer.previous && drawer.previous.focus && document.body.contains(drawer.previous)) { drawer.previous.focus(); }
      drawer = null;
    }

    /* ---------- tabs ---------- */

    var tabs = [].slice.call(root.querySelectorAll('[data-rf-flux-tags-tab]'));
    var panelNodes = {};
    [].forEach.call(root.querySelectorAll('[data-rf-flux-tags-panel]'), function (n) { panelNodes[n.getAttribute('data-rf-flux-tags-panel')] = n; });
    var panels = [], byContext = {};
    [].forEach.call(root.querySelectorAll('[data-rf-flux-tags-list]'), function (host) {
      var panel = new ListPanel(host, host.getAttribute('data-rf-flux-tags-list'));
      panels.push(panel); byContext[panel.context] = panel;
    });
    var form = root.closest('form');
    var apply = form ? form.querySelector('input[type="submit"], button[type="submit"]') : null;

    function updateBadges(stats) {
      [].forEach.call(root.querySelectorAll('[data-rf-flux-tags-badge]'), function (badge) {
        var key = badge.getAttribute('data-rf-flux-tags-badge');
        if (stats && stats[key] !== undefined) { badge.textContent = stats[key]; }
      });
    }

    function showTab(name, push) {
      tabs.forEach(function (tab) {
        var on = tab.getAttribute('data-rf-flux-tags-tab') === name;
        tab.setAttribute('aria-selected', on ? 'true' : 'false');
        tab.tabIndex = on ? 0 : -1;
      });
      Object.keys(panelNodes).forEach(function (key) { panelNodes[key].hidden = key !== name; });
      if (apply) { apply.hidden = name !== 'general'; }
      if (byContext[name]) { byContext[name].activate(); }
      closeDrawer();
      if (push && window.history && history.replaceState) {
        var url = new URL(window.location.href);
        url.searchParams.set('tab', name);
        history.replaceState(null, '', url.toString());
      }
    }
    tabs.forEach(function (tab, index) {
      tab.addEventListener('click', function () { showTab(tab.getAttribute('data-rf-flux-tags-tab'), true); });
      tab.addEventListener('keydown', function (event) {
        var next = null;
        if (event.key === 'ArrowRight') { next = tabs[(index + 1) % tabs.length]; }
        if (event.key === 'ArrowLeft') { next = tabs[(index - 1 + tabs.length) % tabs.length]; }
        if (next) { event.preventDefault(); next.focus(); showTab(next.getAttribute('data-rf-flux-tags-tab'), true); }
      });
    });

    var unusedLink = root.querySelector('[data-rf-flux-tags-show-unused]');
    if (unusedLink) {
      unusedLink.addEventListener('click', function () {
        var panel = byContext.issue;
        if (panel) { panel.state.filter = 'unused'; panel.loaded = false; }
        showTab('issue', true);
      });
    }

    // Live preview of the "colored tags" switch.
    var colorSwitch = document.getElementById('rf_flux_tags_setting_colors');
    var preview = document.getElementById('rf-flux-tags-preview');
    if (colorSwitch && preview) {
      colorSwitch.addEventListener('change', function () {
        cfg.useColors = colorSwitch.checked;
        [].forEach.call(preview.querySelectorAll('.rf-flux-tags-chip'), function (c) { c.classList.toggle('rf-flux-tags-chip--plain', !colorSwitch.checked); });
      });
      [].forEach.call(preview.querySelectorAll('.rf-flux-tags-chip'), function (c) { c.classList.toggle('rf-flux-tags-chip--plain', !colorSwitch.checked); });
    }

    showTab(cfg.firstTab, false);
  }

  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', start); } else { start(); }
})();
