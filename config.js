'use strict';

const SCREEN_WIDTH = 718

// For some reason sortable.js doesn't properly
// work in chrome 62 without using the forceFallback
// option :-\
const isChrome = !!window.chrome

function recalc_layout(state) {
  const is_portrait = state.config.rotation == 90 ||
                      state.config.rotation == 270
  let width, height
  if (is_portrait) {
    width = state.config.resolution[1]
    height = state.config.resolution[0]
  } else {
    width = state.config.resolution[0]
    height = state.config.resolution[1]
  }
  let scale = SCREEN_WIDTH / width
  if (is_portrait)
    scale /= 2
  Vue.set(state.screen, 'width', width)
  Vue.set(state.screen, 'height', height)
  Vue.set(state.screen, 'scale', scale)
  console.log("recalculated layout")
}

function deepcopy(o) {
  return JSON.parse(JSON.stringify(o))
}

function clamp(v, a, b) {
  return Math.max(a, Math.min(b, v))
}

function color_rgb_to_ib(rgb, a) {
  rgb = rgb.substring(1)
  var r = parseInt(rgb.substring(0,2), 16) / 255
  var g = parseInt(rgb.substring(2,4), 16) / 255
  var b = parseInt(rgb.substring(4,6), 16) / 255
  a = a == undefined ? 1 : a
  return [r, g, b, a]
}

function to2hex(val) {
  let out = Math.floor(val * 255).toString(16)
  if (out.length < 2) out = "0" + out
  return out
}

function color_ib_to_rgb(ib) {
  return "#" + to2hex(ib[0]) + to2hex(ib[1]) + to2hex(ib[2])
}

const ChildTile = (function() {
  let childs = {}
  function register(child) {
    const name = document.currentScript.dataset.name
    console.log('registered child plugin', name)
    childs[name] = child
  }
  function config_value(key, default_value, convert) {
    return {
      get() {
        const value = this.config[key]
        return value == undefined ? default_value : value
      },
      set(value) {
        if (convert != undefined)
          value = convert(value)
        this.$emit('setConfig', key, value)
      }
    }
  }
  return {
    config_value: config_value,
    register: register,
    childs: childs,
  }
})()

function load_childs(assets) {
  return new Promise(function(resolve, reject) {
    var loaded = 0;
    var scripts = [];

    function done_loading() {
      console.log("load completed");
      loaded++;
      if (loaded == scripts.length)
        resolve();
    }

    for (var name in assets) {
      var asset = assets[name];
      if (asset.filetype != 'child')
        continue
      var script = document.createElement('script');
      script.type = 'text/javascript';
      script.dataset.name = name;
      script.src = name + '/tile.js';
      script.onload = script.onerror = done_loading;
      scripts.push(script);
    }

    for (var idx = 0; idx < scripts.length; idx++) {
      document.head.appendChild(scripts[idx]);
    }
  })
}


const store = new Vuex.Store({
  strict: true,
  state: {
    assets: {},
    node_assets: {},
    schedule_id: 0,
    config: {
      scratch: {},
      schedules: [{
        name: "",
        pages: []
      }],
    },
    screen: {
      width: 1920,
      height: 1080,
      scale: 1,
    },
  },
  mutations: {
    init(state, {assets, node_assets, config}) {
      // fixes for older version
      config.scratch = config.scratch || {};
      config.layouts = config.layouts || [];
      // end fixes

      state.assets = assets;
      state.node_assets = node_assets;
      state.config = config;
      if (config.scratch.debug_schedule_id != undefined) {
        state.schedule_id = config.scratch.debug_schedule_id;
      }
      recalc_layout(state);
    },
    assets_update(state, assets) {
      state.assets = assets;
    },
    config_update(state, {key, value}) {
      Vue.set(state.config, key, value);
      recalc_layout(state);
    },

    // Schedule & Related mutations
    schedule_create(state) {
      var new_schedule = {
        name: "Unnamed",
        scheduling: {
          hours: [],
        },
        display_mode: "all",
        pages: [],
      }
      state.config.schedules.push(new_schedule);
      state.schedule_id = state.config.schedules.length - 1;
    },
    schedule_delete(state, {schedule_id}) {
      if (state.config.scratch.debug_schedule_id == schedule_id) {
        Vue.delete(state.config.scratch, 'debug_schedule_id');
        Vue.delete(state.config.scratch, 'debug_page_id');
      }
      if (state.config.schedules.length > 1) {
        state.config.schedules.splice(schedule_id, 1);
        state.schedule_id = 0;
      }
    },
    schedule_select(state, {schedule_id}) {
      state.schedule_id = schedule_id;
    },
    schedule_set_hour(state, {schedule_id, hour, on}) {
      var hours = state.config.schedules[schedule_id].scheduling.hours;
      while (hours.length < 24*7) 
        hours.push(true);
      Vue.set(hours, hour, on);
    },
    schedule_set_date(state, {schedule_id, which, date}) {
      if (date == undefined || date == "") {
        Vue.delete(state.config.schedules[schedule_id].scheduling, which);
      } else {
        Vue.set(state.config.schedules[schedule_id].scheduling, which, date);
      }
    },
    schedules_update(state, {schedules}) {
      Vue.set(state.config, 'schedules', schedules);
    },
    schedule_set_name(state, {schedule_id, name}) {
      state.config.schedules[schedule_id].name = name;
    },
    schedule_set_mode(state, {schedule_id, mode}) {
      Vue.set(state.config.schedules[schedule_id].scheduling, 'mode', mode);
    },
    schedule_set_interval(state, {schedule_id, interval}) {
      Vue.set(state.config.schedules[schedule_id].scheduling, 'interval', interval);
    },
    schedule_set_span(state, {schedule_id, span_id, span}) {
      Vue.set(state.config.schedules[schedule_id].scheduling.spans, span_id, span);
    },
    add_schedule_span(state, {schedule_id}) {
      if (!state.config.schedules[schedule_id].scheduling.spans) {
        Vue.set(state.config.schedules[schedule_id].scheduling, 'spans', []);
      }
      state.config.schedules[schedule_id].scheduling.spans.push({
        days: [true, true, true, true, true, true, true],
        starts: '00:00',
        ends: '23:59',
      })
    },
    schedule_delete_span(state, {schedule_id, span_id}) {
      state.config.schedules[schedule_id].scheduling.spans.splice(span_id, 1);
    },
    schedule_set_display_mode(state, {schedule_id, mode}) {
      Vue.set(state.config.schedules[schedule_id], 'display_mode', mode);
    },
    schedule_pages_update(state, {schedule_id, pages}) {
      Vue.set(state.config.schedules[schedule_id], 'pages', pages);
    },

    // Page related mutations
    page_create(state, {schedule_id, after_page_id}) {
      var new_page = {
        duration: 0,
        auto_duration: 2,
        overlap: 0,
        tiles: [],
      }
      var pages = state.config.schedules[schedule_id].pages;
      if (after_page_id != -1) {
        var last_page = pages[after_page_id];
        // XXX copy last page here?
        pages.splice(after_page_id+1, 0, new_page);
      } else {
        pages.splice(0, 0, new_page);
      }
    },
    page_copy(state, {schedule_id, page_id}) {
      let page = deepcopy(state.config.schedules[schedule_id].pages[page_id])
      state.config.schedules[schedule_id].pages.splice(page_id, 0, page);
    },
    page_delete(state, {schedule_id, page_id}) {
      if (state.config.scratch.debug_schedule_id == schedule_id &&
          state.config.scratch.debug_page_id == page_id)
      {
        Vue.delete(state.config.scratch, 'debug_schedule_id');
        Vue.delete(state.config.scratch, 'debug_page_id');
      }
      state.config.schedules[schedule_id].pages.splice(page_id, 1);
    },
    page_debug(state, {schedule_id, page_id}) {
      Vue.set(state.config.scratch, 'debug_schedule_id', schedule_id);
      Vue.set(state.config.scratch, 'debug_page_id', page_id);
    },
    debug_stop(state) {
      Vue.delete(state.config.scratch, 'debug_schedule_id');
      Vue.delete(state.config.scratch, 'debug_page_id');
    },
    page_set_duration(state, {schedule_id, page_id, duration}) {
      state.config.schedules[schedule_id].pages[page_id].duration = duration;
    },
    page_set_layout(state, {schedule_id, page_id, layout_id}) {
      state.config.schedules[schedule_id].pages[page_id].layout_id = layout_id;
    },

    // Page Tile mutations
    page_tile_create(state, {schedule_id, page_id, tile}) {
      let page = state.config.schedules[schedule_id].pages[page_id]
      page.tiles.push(tile)
      Vue.set(state.config.schedules[schedule_id].pages[page_id], 'selected', page.tiles.length-1)
    },
    page_update_auto_duration(state, {schedule_id, page_id}) {
      const page = state.config.schedules[schedule_id].pages[page_id]
      const assets = state.assets
      const node_assets = state.node_assets
      let auto_duration = 2
      for (let i = 0; i < page.tiles.length; i++) {
        const tile = page.tiles[i]
        const asset_info = assets[tile.asset] || node_assets[tile.asset]
        if (asset_info.metadata && asset_info.metadata.duration) {
          auto_duration = Math.max(auto_duration, asset_info.metadata.duration)
        } else {
          auto_duration = Math.max(auto_duration, 10)
        }
      }
      console.log("tile auto duration is", auto_duration)
      Vue.set(state.config.schedules[schedule_id].pages[page_id], 'auto_duration', auto_duration)
    },
    page_tile_delete(state, {schedule_id, page_id, tile_id}) {
      var page = state.config.schedules[schedule_id].pages[page_id];
      page.tiles.splice(tile_id, 1);
      if (page.selected == tile_id) {
        Vue.delete(state.config.schedules[schedule_id].pages[page_id], 'selected');
      }
    },
    page_interaction_update(state, {schedule_id, page_id, interaction}) {
      var page = state.config.schedules[schedule_id].pages[page_id];
      Vue.set(page, 'interaction', interaction);
    },
    page_tile_set_pos(state, {schedule_id, page_id, tile_id, pos}) {
      var tile = state.config.schedules[schedule_id].pages[page_id].tiles[tile_id];
      const screen = state.screen;
      var x1 = pos.x1 != undefined ? pos.x1 : tile.x1;
      var x2 = pos.x2 != undefined ? pos.x2 : tile.x2;
      var y1 = pos.y1 != undefined ? pos.y1 : tile.y1;
      var y2 = pos.y2 != undefined ? pos.y2 : tile.y2;
      tile.x1 = Math.round(Math.max(Math.min(x1, x2), 0));
      tile.y1 = Math.round(Math.max(Math.min(y1, y2), 0));
      tile.x2 = Math.round(Math.min(Math.max(x1, x2), screen.width));
      tile.y2 = Math.round(Math.min(Math.max(y1, y2), screen.height));
    },
    page_tile_set_asset(state, {schedule_id, page_id, tile_id, asset_spec}) {
      console.log({schedule_id, page_id, tile_id, asset_spec})
      state.config.schedules[schedule_id].pages[page_id].tiles[tile_id].asset = asset_spec
    },
    page_tile_set_config(state, {schedule_id, page_id, tile_id, key, value}) {
      Vue.set(state.config.schedules[schedule_id].pages[page_id].tiles[tile_id].config, key, value);
    },
    page_tile_update(state, {schedule_id, page_id, tiles}) {
      Vue.set(state.config.schedules[schedule_id].pages[page_id], 'tiles', tiles);
    },

    // Layout mutations
    layout_create(state) {
      const screen = state.screen;
      var new_layout = {
        tiles: [{
          type: "page",
          x1: 0,
          y1: 0,
          x2: screen.width,
          y2: screen.height,
          asset: "flat.png",
          config: {},
        }],
        name: "New Layout",
      }
      state.config.layouts.push(new_layout);
    },
    layout_delete(state, {layout_id}) {
      state.config.layouts.splice(layout_id, 1);
    },
    layout_set_name(state, {layout_id, name}) {
      state.config.layouts[layout_id].name = name;
    },
    layout_tile_create(state, {layout_id, tile}) {
      state.config.layouts[layout_id].tiles.push(tile);
    },
    layout_tile_delete(state, {layout_id, tile_id}) {
      var layout = state.config.layouts[layout_id];
      layout.tiles.splice(tile_id, 1);
      // TODO: iterate through all pages and unref this layout
    },
    layout_tile_set_pos(state, {layout_id, tile_id, pos}) {
      var tile = state.config.layouts[layout_id].tiles[tile_id];
      const screen = state.screen;
      var x1 = pos.x1 != undefined ? pos.x1 : tile.x1;
      var x2 = pos.x2 != undefined ? pos.x2 : tile.x2;
      var y1 = pos.y1 != undefined ? pos.y1 : tile.y1;
      var y2 = pos.y2 != undefined ? pos.y2 : tile.y2;
      tile.x1 = Math.round(Math.max(Math.min(x1, x2), 0));
      tile.y1 = Math.round(Math.max(Math.min(y1, y2), 0));
      tile.x2 = Math.round(Math.min(Math.max(x1, x2), screen.width));
      tile.y2 = Math.round(Math.min(Math.max(y1, y2), screen.height));
    },
    layout_tile_set_asset(state, {layout_id, tile_id, asset_spec}) {
      state.config.layouts[layout_id].tiles[tile_id].asset = asset_spec
    },
    layout_tile_set_config(state, {layout_id, tile_id, key, value}) {
      Vue.set(state.config.layouts[layout_id].tiles[tile_id].config, key, value);
    },
    layout_tile_update(state, {layout_id, tiles}) {
      Vue.set(state.config.layouts[layout_id], 'tiles', tiles);
    },
  },
  actions: {
    page_tile_create({commit}, {schedule_id, page_id, tile}) {
      commit('page_tile_create', {schedule_id, page_id, tile})
      commit('page_update_auto_duration', {schedule_id, page_id})
    },
    page_tile_set_asset({commit}, {schedule_id, page_id, tile_id, asset_spec}) {
      commit('page_tile_set_asset', {schedule_id, page_id, tile_id, asset_spec})
      commit('page_update_auto_duration', {schedule_id, page_id})
    },
  },
})

function to_px(val) {
  return val * store.state.screen.scale;
}

Vue.directive('draggable', {
  bind(el, binding) {
    interact(el)
      .draggable({
        onmove: (evt) => {
          var move_evt = new Event("resize");
          move_evt.delta = {
            x1: evt.dx,
            y1: evt.dy,
            x2: evt.dx,
            y2: evt.dy,
          };
          el.dispatchEvent(move_evt);
        },
        inertia: true,
      })
      .resizable({
        edges: {
          left: true,
          right: true,
          bottom: true,
          top: true
        }
      })
      .on('resizemove', (evt) => {
        var resize_evt = new Event("resize");
        resize_evt.delta = {
          x1: evt.deltaRect.left,
          y1: evt.deltaRect.top,
          x2: evt.deltaRect.right,
          y2: evt.deltaRect.bottom,
        };
        el.dispatchEvent(resize_evt);
      })
  },
  unbind(el) {
    interact(el).unset();
  },
})


Vue.component('config-ui', {
  template: '#config-ui',
  data: () => ({
    tab: "schedule",
    rotations: [
      [0, "No rotation"],
      [90, "90° clockwise"],
      [180, "180°"],
      [270, "270°"],
    ],
    resolutions: [
      [[3840, 2160], "4K (3840x2160, Pi4 only!)"],
      [[3840, 1080], "Dual FullHD (3840x1080, Pi4 only!)"],
      [[1920, 2160], "Dual FullHD (1920x2160, Pi4 only!)"],
      [[1920, 1080], "FullHD (1920x1080)"],
      [[1280, 720], "HD (1280x720)"],
      [[1024, 768], "XGA(1024x768) 4:3"],
      [[1280, 1024], "SXGA (1280x1024, 5:4)"],
      [[800, 480], "7inch (800x480)"],
      [[720, 576], "576p (720x576)"],
      [[1920, 1200], "1920x1200"],
      [[1920, 540], "1920x540"],
      [[1680, 1050], "1680x1050"],
      [[1366, 768], "1366x768"],
    ],
    triggers: [
      ["next", "Show next match"],
      ["all", "Enqueue all matches"],
    ],
  }),
  computed: {
    timezones() {
      return [
        ["device", "Use device's timezone"],
        ["", ""],
      ].concat(TIMEZONES)
    },
    config() {
      return this.$store.state.config;
    },
    timezone() { return this.config.timezone; },
    rotation() { return this.config.rotation; },
    resolution() { return this.config.resolution; },
    trigger() { return this.config.trigger; },
    pages() { return this.config.pages; },
    is_debugged() {
      return this.config.scratch.debug_schedule_id != undefined;
    },
    fallback_asset() {
      var asset_spec = this.config.fallback;
      var assets = this.$store.state.assets;
      var node_assets = this.$store.state.node_assets;
      return assets[asset_spec] || node_assets[asset_spec];
    },
    music_asset() {
      var asset_spec = this.config.music;
      var assets = this.$store.state.assets;
      var node_assets = this.$store.state.node_assets;
      return assets[asset_spec] || node_assets[asset_spec];
    },
    poweroff() {
      return this.config.poweroff;
    },
    time: {
      get() { return this.config.time },
      set(value) { 
        this.$store.commit('config_update', {
          key: 'time', value: value
        });
      }
    },
    background() {
      var background = this.config.background;
      if (background == undefined)
        background = [0,0,0,0];
      return background;
    },
    background_a: {
      get() {
        return this.background[3] == 0;
      },
      set(val) {
        var background = this.background;
        console.log(background);
        background[3] = val ? 0 : 1;
        this.$store.commit('config_update', {
          key: 'background', value: background,
        });
      }
    },
    background_rgb: {
      get() {
        return color_ib_to_rgb(this.background);
      },
      set(val) {
        var a = this.background[3];
        var background = color_rgb_to_ib(val, a);
        this.$store.commit('config_update', {
          key: 'background', value: background,
        });
      }
    }
  },
  methods: {
    onDisableDebug() {
      this.$store.commit('debug_stop');
    },
    onSetConfigValue(key, value) {
      this.$store.commit('config_update', {
        key: key, value: value
      });
    },
    onSetFallback(asset_spec) {
      this.$store.commit('config_update', {
        key: 'fallback',
        value: asset_spec,
      })
    },
    onSetMusic(asset_spec) {
      this.$store.commit('config_update', {
        key: 'music',
        value: asset_spec,
      })
    },
  }
})

Vue.component('schedule-panel', {
  template: '#schedule-panel',
  data: () => ({
    compact: false, // XXX
    editing_time: false, //XXX
    schedule_dd_options: {
      forceFallback: isChrome,
      handle: '.handle',
    },
    page_dd_options: {
      forceFallback: isChrome,
      handle: '.handle',
      group: {
        name: 'page-list',
        pull: true,
        put: ['page-list'],
      }
    },
  }),
  computed: {
    config() { return this.$store.state.config; },
    schedule_id() { return this.$store.state.schedule_id },
    schedule() { return this.config.schedules[this.schedule_id] },
    pages: {
      get() { 
        return this.schedule.pages
      },
      set(pages) {
        this.$store.commit('schedule_pages_update', {
          schedule_id: this.schedule_id,
          pages: pages,
        })
      }
    },
    screen() { return this.$store.state.screen },
    scheduling() { return this.schedule.scheduling },
    duration() {
      var duration = 0;
      for (var idx = 0; idx < this.pages.length; idx++) {
        var page = this.pages[idx];
        duration += (
          page.duration == -1 ? 0 :
          page.duration == 0 ? page.auto_duration : page.duration
        );
      }
      return duration;
    },
    display_mode: {
      get() {
        return this.schedule.display_mode || "all";
      },
      set(value) {
        this.$store.commit('schedule_set_display_mode', {
          schedule_id: this.schedule_id,
          mode: value,
        })
      },
    },
    schedules: {
      get() {
        return this.$store.state.config.schedules;
      },
      set(value) {
        this.$store.commit('schedules_update', {
          schedules: value,
        })
      }
    },
  },
  methods: {
    onAddSchedule() {
      this.$store.commit('schedule_create');
    },
    onSelectSchedule(schedule_id) {
      this.schedule_id = schedule_id;
    },
    onScheduleMode(mode) {
      this.$store.commit('schedule_set_mode', {
        schedule_id: this.schedule_id,
        mode: mode,
      })
    },
    onScheduleDateSet(which, date) {
      this.$store.commit('schedule_set_date', {
        schedule_id: this.schedule_id,
        which: which,
        date: date,
      })
    },
    onScheduleHourSet(hour, on) {
      this.$store.commit('schedule_set_hour', {
        schedule_id: this.schedule_id,
        hour: hour,
        on: on,
      });
    },
    onScheduleIntervalUpdate(interval) {
      this.$store.commit('schedule_set_interval', {
        schedule_id: this.schedule_id,
        interval: interval,
      });
    },
    onScheduleSpanAdd() {
      this.$store.commit('add_schedule_span', {
        schedule_id: this.schedule_id,
      });
    },
    onScheduleSpanDelete(span_id) {
      this.$store.commit('schedule_delete_span', {
        schedule_id: this.schedule_id,
        span_id: span_id,
      });
    },
    onScheduleSpanUpdate(span_id, span) {
      this.$store.commit('schedule_set_span', {
        schedule_id: this.schedule_id,
        span_id: span_id,
        span: span,
      });
    },
    onAddPage(type, asset_spec) {
      var page_id = this.pages.length;
      this.$store.commit('page_create', {
        schedule_id: this.schedule_id,
        after_page_id: page_id-1,
      })
      this.$store.dispatch('page_tile_create', {
        schedule_id: this.schedule_id,
        page_id: page_id,
        tile: {
          type: type,
          asset: asset_spec,
          config: {},
          x1: 0,
          y1: 0,
          x2: this.screen.width,
          y2: this.screen.height,
        }
      })
    },
    onAddAssets() {
      var that = this;
      ib.assetChooser({
        filter: ['image', 'video'],
        features: ['image2k', 'h264', 'hevc'],
        no_node_assets: true,
        multi_select: true,
      }).then(function(selection) {
        var assets = that.$store.state.assets;
        for (var idx = 0; idx < selection.length; idx++) {
          var selected = selection[idx]
          var asset = assets[selected.id]
          var duration = asset.metadata.duration || 10;
          var config, type;
          if (asset.filetype == "image") {
            type = "image";
            config = {};
          } else if (asset.filetype == "video") {
            type = "rawvideo";
            config = {"layer":-5};
          }
          var page_id = that.pages.length;
          that.$store.commit('page_create', {
            schedule_id: that.schedule_id,
            after_page_id: page_id-1,
          })
          that.$store.dispatch('page_tile_create', {
            schedule_id: that.schedule_id,
            page_id: page_id,
            tile: {
              type: type,
              asset: asset.id,
              config: config,
              x1: 0,
              y1: 0,
              x2: that.screen.width,
              y2: that.screen.height,
            }
          })
        }
      })
    }
  }
})

Vue.component('schedule-row', {
  template: '#schedule-row',
  props: ["schedule_id"],
  computed: {
    config() { return this.$store.state.config; },
    is_selected() {
      return this.$store.state.schedule_id == this.schedule_id
    },
    schedule() { return this.config.schedules[this.schedule_id] },
    style() {
      return {
        backgroundColor: this.is_selected ? "#0fccffaf" : "white",
      }
    },
    is_debugged() {
      return this.config.scratch.debug_schedule_id == this.schedule_id
    },
  },
  methods: {
    onSelect() {
      this.$store.commit('schedule_select', {
        schedule_id: this.schedule_id,
      })
    },
    onUpdateName(name) {
      this.$store.commit('schedule_set_name', {
        schedule_id: this.schedule_id,
        name: name,
      })
    },
    onDelete() {
      this.$store.commit('schedule_delete', {
        schedule_id: this.schedule_id,
      })
    },
  },
})

Vue.component('page-compact', {
  template: '#page-compact',
  props: ["schedule_id", "page_id"],
  computed: {
    config() { return this.$store.state.config; },
    schedule() { return this.config.schedules[this.schedule_id] },
    page() { return this.schedule.pages[this.page_id] },
    duration() { return this.page.duration },
    auto_duration() { return this.page.auto_duration },
    is_disabled() {
      return this.duration == -1;
    },
    is_auto_duration() {
      return this.duration == 0;
    },
    is_debugged() {
      return this.config.scratch.debug_schedule_id == this.schedule_id &&
             this.config.scratch.debug_page_id == this.page_id;
    },
    thumbs() {
      var assets = this.$store.state.assets;
      var node_assets = this.$store.state.node_assets;
      function get_asset(asset_spec) {
        return assets[asset_spec] || node_assets[asset_spec];
      }
      var thumbs = [];
      for (var idx = 0; idx < this.page.tiles.length; idx++) {
        var tile = this.page.tiles[idx];
        var thumb = get_asset(tile.asset).thumb;
        thumbs.push(thumb + '?size=32');
      }
      return thumbs;
    },
    filename() {
      var assets = this.$store.state.assets;
      var node_assets = this.$store.state.node_assets;
      function get_asset(asset_spec) {
        return assets[asset_spec] || node_assets[asset_spec];
      }
      var filenames = [];
      for (var idx = 0; idx < this.page.tiles.length; idx++) {
        var tile = this.page.tiles[idx];
        filenames.push(get_asset(tile.asset).filename);
      }
      if (filenames.length != 1) {
        return ''
      } else {
        return filenames[0]
      }
    },
  },
  methods: {
    onDelete(evt) {
      this.$store.commit('page_delete', {
        schedule_id: this.schedule_id,
        page_id: this.page_id
      });
    },
  }
})

Vue.component('add-button', {
  template: '#add-button',
  props: ["schedule_id", "after"],
  methods: {
    onAdd() {
      this.$store.commit('page_create', {
        schedule_id: this.schedule_id,
        after_page_id: this.after,
      })
    },
  }
})

Vue.component('page-editor', {
  template: '#page-editor',
  props: ["schedule_id", "page_id"],
  data: () => ({
    force_custom_duration: false,
  }),
  computed: {
    config() { return this.$store.state.config; },
    schedule() { return this.config.schedules[this.schedule_id] },
    page() { return this.schedule.pages[this.page_id] },
    duration() { return this.page.duration },
    show_custom_duration() {
      return this.force_custom_duration || this.is_custom_duration;
    },
    is_custom_duration() {
      for (var idx = 0; idx < this.durations.length; idx++) {
        if (this.durations[idx][0] == this.duration) {
          return false;
        }
      }
      return true;
    },
    auto_duration() { return this.page.auto_duration },
    interaction() {
      return this.page.interaction || {};
    },
    is_interactive() {
      return this.interaction.key != undefined && this.interaction.key != "";
    },
    is_debugged() {
      return this.config.scratch.debug_schedule_id == this.schedule_id &&
             this.config.scratch.debug_page_id == this.page_id;
    },
    layouts() {
      var layouts = [[-1, "No layout"]];
      for (var idx = 0; idx < this.config.layouts.length; idx++) {
        var layout = this.config.layouts[idx];
        layouts.push([idx, layout.name]);
      }
      return layouts;
    },
    durations() {
      return [
        [-1, "Deactivated - don't show"],
        [ 0, "Automatic duration (" + this.auto_duration.toFixed(2) + "s)"],
        [ 1, "Show 1 second"],
        [ 2, "Show 2 seconds"],
        [ 3, "Show 3 seconds"],
        [ 5, "Show 5 seconds"],
        [10, "Show 10 seconds"],
        [15, "Show 15 seconds"],
        [20, "Show 20 seconds"],
        [30, "Show 30 seconds"],
        [60, "Show 1 minute"],
        [90, "Show 90 seconds"],
        [120, "Show 2 minutes"],
        [null, "Custom..."],
      ];
    }
  },
  methods: {
    onCopyPage(evt) {
      this.$store.commit('page_copy', {
        schedule_id: this.schedule_id,
        page_id: this.page_id
      })
    },
    onDeletePage() {
      this.$store.commit('page_delete', {
        schedule_id: this.schedule_id,
        page_id: this.page_id
      })
    },
    onDebug() {
      if (this.is_debugged) {
        this.$store.commit('debug_stop');
      } else {
        this.$store.commit('page_debug', {
          schedule_id: this.schedule_id,
          page_id: this.page_id
        })
      }
    },
    onSetLayout(layout_id) {
      this.$store.commit('page_set_layout', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        layout_id: layout_id,
      })
    },
    onMakeInteractive() {
      this.$store.commit('page_interaction_update', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        interaction: {'key': 'space'},
      })
    },
    onResetInteractive() {
      this.$store.commit('page_interaction_update', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        interaction: {'key': ''},
      })
    },
    onInteractionUpdate(interaction) {
      this.$store.commit('page_interaction_update', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        interaction: interaction,
      })
    },
    onAddTile(tile) {
      this.$store.dispatch('page_tile_create', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        tile: tile,
      })
    },
    onDeleteTile(tile_id) {
      this.$store.commit('page_tile_delete', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        tile_id: tile_id,
      })
    },
    onPositionTile(tile_id, pos) {
      this.$store.commit('page_tile_set_pos', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        tile_id: tile_id,
        pos: pos,
      })
    },
    onSelectTileAsset(tile_id, asset_spec) {
      this.$store.dispatch('page_tile_set_asset', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        tile_id: tile_id,
        asset_spec: asset_spec,
      })
    },
    onSetTileConfig(tile_id, {key, value}) {
      this.$store.commit('page_tile_set_config', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        tile_id: tile_id,
        key: key,
        value: value,
      })
    },
    onReorderTiles(tiles) {
      this.$store.commit('page_tile_update', {
        schedule_id: this.schedule_id,
        page_id: this.page_id,
        tiles: tiles,
      });
    },
    onSetDuration(duration) {
      if (duration == null) {
        this.force_custom_duration = true;
        return;
      } else {
        this.force_custom_duration = false;
        this.$store.commit('page_set_duration', {
          schedule_id: this.schedule_id,
          page_id: this.page_id,
          duration: duration,
        });
      }
    },
  }
})

Vue.component('tile-editor', {
  template: '#tile-editor',
  props: ["tiles"],
  data: () => ({
    tile_dd_options: {
      forceFallback: isChrome,
      handle: '.handle',
    },
    show_more: false,
    selected_tile_id: undefined,
  }),
  computed: {
    screen() { return this.$store.state.screen },
    drag_drop_tiles: {
      get() {
        return this.tiles
      },
      set(value) {
        this.$emit("onReorderTiles", value);
      },
    },
    selected_tile() { return this.selected_tile_id != undefined ? this.tiles[this.selected_tile_id] : null },
    style() {
      return {
        width: to_px(this.screen.width) + "px",
        height: to_px(this.screen.height) + "px",
      }
    },
  },
  methods: {
    onAddTile(type, asset_spec, config) {
      this.$emit("onAddTile", {
        type: type,
        asset: asset_spec,
        config: config || {},
        x1: 0,
        y1: 0,
        x2: this.screen.width,
        y2: this.screen.height,
      })
      this.selected_tile_id = this.tiles.length-1
    },
    onPositionTile(tile_id, pos) {
      this.$emit("onPositionTile", tile_id, pos)
    },
    onSelectTileAsset(tile_id, asset_spec) {
      this.$emit("onSelectTileAsset", tile_id, asset_spec)
    },
    onSetTileConfig(tile_id, kv) {
      this.$emit("onSetTileConfig", tile_id, kv)
    },
    onDeleteTile(tile_id) {
      this.$emit("onDeleteTile", tile_id)
    },
  }
})

var TileOption = Vue.extend({
  props: ["tile"],
  computed: {
    config() { return this.tile.config },
    asset() { return this.tile.asset },
    effect() {
      return this.config.effect
    },
    has_effect() {
      return this.config.effect && this.config.effect != 'none'
    },
  },
  methods: {
    onSetValue(key, value) {
      this.$emit("onSetTileConfig", {
        key: key,
        value: value,
      });
    },
  }
})
    
Vue.component('tile-option-image', TileOption.extend({
  template: '#tile-option-image',
  data: () => ({
    fade_times: [
      [  0, "No fade"],
      [ .5, "0.5 seconds fade"],
      [1.0, "1 second fade"],
      [1.5, "1.5 seconds fade"],
      [2.0, "2 seconds fade"],
    ],
    effects: [
      ["none",            "No effect"],
      ["rotation",        "Rotation"],
      ["enter_exit_move", "Enter/Exit movement"],
    ],
    directions: [
      ["from_left",   "from the left"],
      ["from_right",  "from the right"],
      ["from_top",    "from top"],
      ["from_bottom", "from bottom"],
    ],
    durations: [
      [ .5, "in 0.5 seconds"],
      [  1, "in 1 second"],
      [1.5, "in 1.5 seconds"],
    ],
    easings: [
      ["inQuad", "Quadratic"],
      ["linear", "Linear"],
    ],
    rotations: [
      ["x-axis", "along X-Axis"],
      ["y-axis", "along Y-Axis"],
    ],
    pivots: [
      ["center", "around the center"],
      ["top",    "around top side"],
      ["bottom", "around bottom side"],
      ["left",   "around left side"],
      ["right",  "around right side"],
    ],
  }),
}))

Vue.component('tile-option-video', TileOption.extend({
  template: '#tile-option-video',
  data: () => ({
    fade_times: [
      [  0, "No fade"],
      [ .5, "0.5 seconds fade"],
      [1.0, "1 second fade"],
      [1.5, "1.5 seconds fade"],
      [2.0, "2 seconds fade"],
    ]
  }),
  computed: {
    transparent_color: {
      get() { return this.config.transparent_color || "#ffffff" },
      set(value) { this.onSetValue('transparent_color', value) },
    }
  }
}))

Vue.component('tile-option-rawvideo', TileOption.extend({
  template: '#tile-option-rawvideo',
  data: () => ({
    fade_times: [
      [  0, "No fade"],
      [ .5, "0.5 seconds fade"],
      [1.0, "1 second fade"],
      [1.5, "1.5 seconds fade"],
      [2.0, "2 seconds fade"],
    ],
    layers: [
      [ -5, "Show behind other content"],
      [  5, "Show above other content"],
    ]
  })
}))


Vue.component('tile-option-stream', TileOption.extend({
  template: '#tile-option-stream',
  data: () => ({
    layers: [
      [ -5, "Show behind other content"],
      [  5, "Show above other content"],
    ]
  }),
  computed: {
    url: {
      get() { return this.config.url || "" },
      set(value) { this.onSetValue('url', value) },
    }
  }
}))

Vue.component('tile-option-browser', TileOption.extend({
  template: '#tile-option-browser',
  computed: {
    url: {
      get() { return this.config.url || "" },
      set(value) { this.onSetValue('url', value) },
    }
  }
}))

var NoConfig = {
  props: ['config'],
  template: '<span></span>',
}

Vue.component('tile-option-child', TileOption.extend({
  template: '#tile-option-child',
  computed: {
    child() {
      var child = ChildTile.childs[this.asset];
      return child ? child.config : NoConfig;
    }
  }
}))

Vue.component('tile-option-time', TileOption.extend({
  template: '#tile-option-time',
  data: () => ({
    modes: [
      // ["countdown", "Countdown"],
      ["digital_clock", "Digital clock"],
      ["analog_clock", "Analog clock"],
    ],
    // countdown_styles: [
    //   ["hms", "Hours/Minutes/Seconds"],
    //   ["minutes", "Minutes"],
    // ],
    types: [
      ["hm", "HH:MM (e.g. 18:34)"],
      ["hms", "HH:MM:SS (e.g. 18:34:56)"],
      ["hm_12", "HH:MM pm/am (e.g. 6:34 pm)"],
      ["hms_12", "HH:MM:SS pm/am (e.g. 6:34:56 pm)"],
    ],
    styles: [
      [1, "Style 1"],
      [2, "Style 2"],
    ],
    aligns: [
      ["center", "Centered"],
      ["left", "Left aligned"],
      ["right", "Right aligned"],
    ],
    movements: [
      ["smooth", "Smooth"],
      ["dynamic", "Dynamic"],
      ["discrete", "Discrete"],
    ],
    timezones: [
      ["", "Use timezone configured"],
      [null, "Setup's timezone"],
      ["", "Use custom timezone"],
    ].concat(TIMEZONES),
  }),
  computed: {
    mode() { return this.config.mode || 'digital_clock' },
    timezone() { return this.config.timezone || null },
    type() { return this.config.type || "hms" },
    style() { return this.config.style || 1 },
    align() { return this.config.align || "center" },
    movement() { return this.config.movement || "dynamic" },
    color: {
      get() { return this.config.color || "#333333" },
      set(value) { this.onSetValue('color', value) },
    },
  }
}))

Vue.component('tile-option-countdown', TileOption.extend({
  template: '#tile-option-countdown',
  data: () => ({
    types: [
      ["hms", "Hours + Minutes + Seconds"],
      ["hm", "Hours + Minutes"],
      ["adaptive_dhm", "Adapt with Days/Hours/Minutes"],
      ["adaptive_hms", "Adapt with Hours/Minutes/Seconds"],
    ],
    modes: [
      ["countdown", "Count down, then stop"],
      ["countup", "Wait, then count up"],
      ["both", "Count down, then up"],
    ],
    aligns: [
      ["center", "Centered"],
      ["left", "Left aligned"],
      ["right", "Right aligned"],
    ],
    locales: [
      ["english", "English"],
      ["german", "German"],
      ["none", "Neutral"],
    ],
    fonts: [
      ["default", "Default font"],
      ["digital", "Digital font"],
    ],
  }),
  computed: {
    target: {
      get() { return this.config.target || "" },
      set(value) { this.onSetValue('target', value) },
    },
    color: {
      get() { return this.config.color || "#333333" },
      set(value) { this.onSetValue('color', value) },
    },
  }
}))


Vue.component('tile-option-flat', TileOption.extend({
  template: '#tile-option-flat',
  data: () => ({
    fade_times: [
      [  0, "No fade"],
      [ .5, "0.5 seconds fade"],
      [1.0, "1 second fade"],
      [1.5, "1.5 seconds fade"],
      [2.0, "2 seconds fade"],
    ],
  }),
  computed: {
    color: {
      get() { return this.config.color || "#ffffff" },
      set(value) { this.onSetValue('color', value) },
    },
    alpha: {
      get() { return this.config.alpha || 1 },
      set(value) { this.onSetValue('alpha', parseFloat(value)) },
    }
  }
}))

Vue.component('tile-option-markup', TileOption.extend({
  template: '#tile-option-markup',
  data: () => ({
    fade_times: [
      [  0, "No fade"],
      [ .5, "0.5 seconds fade"],
      [1.0, "1 second fade"],
      [1.5, "1.5 seconds fade"],
      [2.0, "2 seconds fade"],
    ],
    font_sizes: [
      [ 20, "20 pixel"],
      [ 25, "25 pixel"],
      [ 35, "35 pixel"],
      [ 45, "45 pixel"],
      [ 55, "55 pixel"],
      [ 70, "70 pixel"],
      [100, "100  pixel"],
      [150, "150  pixel"],
      [200, "200  pixel"],
      [250, "250  pixel"],
      [300, "300  pixel"],
    ],
    aligns: [
      ["tl", "Align top-left"],
      ["center", "Align centered"],
    ],
  }),
  computed: {
    text: {
      get() { return this.config.text || "" },
      set(value) { this.onSetValue('text', value) },
    },
    color: {
      get() { return this.config.color || "#ffffff" },
      set(value) { this.onSetValue('color', value) },
    }
  }
}))

Vue.component('tile-box', {
  template: '#tile-box',
  props: ["tile", "is_selected"],
  computed: {
    screen() { return this.$store.state.screen },
    x1() { return this.tile.x1 || 0 },
    y1() { return this.tile.y1 || 0 },
    x2() { return this.tile.x2 || this.screen.width },
    y2() { return this.tile.y2 || this.screen.height },
    style() {
      return {
        left: to_px(this.x1) + "px",
        top: to_px(this.y1) + "px",
        width: to_px(this.x2 - this.x1) + "px",
        height: to_px(this.y2 - this.y1) + "px",
        backgroundImage: "url(" + this.thumb_url + ")",
        backgroundSize: "100% 100%",
        color: this.is_selected ? "#0fccffaf" : "#7f7f7f7f",
      }
    },
    asset_spec() {
      return this.tile.asset;
    },
    asset_info() {
      var assets = this.$store.state.assets;
      var node_assets = this.$store.state.node_assets;
      return assets[this.asset_spec] || node_assets[this.asset_spec];
    },
    thumb_url() {
      var info = this.asset_info;
      return info.thumb + '?size=512&crop=none';
    },
  },
  methods: {
    onSelectTile(evt) {
      this.$emit('onSelectTile');
    },
    onResizeTile(evt) {
      if (this.tile.type == "page")
        return;
      var delta_x1 = evt.delta.x1 / this.screen.scale;
      var delta_y1 = evt.delta.y1 / this.screen.scale;
      var delta_x2 = evt.delta.x2 / this.screen.scale;
      var delta_y2 = evt.delta.y2 / this.screen.scale;

      if (this.tile.x1 + delta_x1 < 0) {
        delta_x1 = -this.tile.x1;
        if (delta_x2 != 0)
          delta_x2 = delta_x1;
      }
      if (this.tile.x2 + delta_x2 > this.screen.width) {
        delta_x2 = this.screen.width - this.tile.x2;
        if (delta_x1 != 0)
          delta_x1 = delta_x2;
      }
      if (this.tile.y1 + delta_y1 < 0) {
        delta_y1 = -this.tile.y1;
        if (delta_y2 != 0)
          delta_y2 = delta_y1;
      }
      if (this.tile.y2 + delta_y2 > this.screen.height) {
        delta_y2 = this.screen.height - this.tile.y2;
        if (delta_y1 != 0)
          delta_y1 = delta_y2;
      }
      var pos = {
        x1: Math.round(this.tile.x1 + delta_x1),
        y1: Math.round(this.tile.y1 + delta_y1),
        x2: Math.round(this.tile.x2 + delta_x2),
        y2: Math.round(this.tile.y2 + delta_y2),
      }
      this.$emit('onPositionTile', pos);
    },
  }
})

Vue.component('tile-detail', {
  template: '#tile-detail',
  props: ["tile", "is_selected"],
  computed: {
    x1: {
      get() { return this.tile.x1 },
      set(value) { 
        value = this.toNumber(value);
        this.$emit('onPositionTile', { 
          x1: value,
          x2: value + this.width,
        })
      }
    },
    y1: {
      get() { return this.tile.y1 },
      set(value) { 
        value = this.toNumber(value);
        this.$emit('onPositionTile', { 
          y1: value,
          y2: value + this.height,
        })
      }
    },
    width: {
      get() { return this.tile.x2 - this.tile.x1 },
      set(value) { 
        value = this.toNumber(value);
        this.$emit('onPositionTile', { 
          x2: this.x1 + value,
        })
      }
    },
    height: {
      get() { return this.tile.y2 - this.tile.y1 },
      set(value) { 
        value = this.toNumber(value);
        this.$emit('onPositionTile', { 
          y2: this.y1 + value,
        })
      }
    },
    screen() { return this.$store.state.screen },
    type_icon() {
      var type = this.tile.type;
      return type == "image" ? "glyphicon-picture" :
             type == "video" ? "glyphicon-movie" : undefined;
    },
    style() {
      return {
        backgroundColor: this.is_selected ? "#0fccffaf" : "white",
      }
    },
    asset_spec() {
      return this.tile.asset
    },
    asset_info() {
      const assets = this.$store.state.assets;
      const node_assets = this.$store.state.node_assets
      return assets[this.asset_spec] || node_assets[this.asset_spec]
    },
    thumb_url() {
      const info = this.asset_info
      return info.thumb + '?size=20'
    },
  },
  methods: {
    toNumber(value) {
      value = parseInt(value)
      if (isNaN(value)) value = 0
      return value
    },
    onSelectTile() {
      this.$emit('onSelectTile')
    },
    async onChooseAsset(tile_type) {
      if (!ib.assetChooser)
        return
      const filter = {
        video: ['video'],
        rawvideo: ['video'],
        image: ['image'],
      }[tile_type]
      if (!filter)
        return
      const features = {
        video: ['h264'],
        rawvideo: ['h264', 'hevc'],
        image: ['image2k', 'image4k'],
      }[tile_type]
      let selected = await ib.assetChooser({
        filter: filter,
        selected_asset_spec: this.asset_spec,
        features: features,
      })
      if (!selected)
        return
      this.$emit('onSelectTileAsset', selected.id)
    },
    onMakeFullscreen() {
      this.$emit('onPositionTile', {
        x1: 0,
        y1: 0,
        x2: screen.width,
        y2: screen.height,
      })
    },
    onOrigSize() {
      var width = 1280,
          height = 720; 
      var metadata = this.asset_info.metadata;
      if (metadata) {
        width = metadata.width;
        height = metadata.height;
      }
      var x1 = this.tile.x1,
          y1 = this.tile.y1,
          x2 = this.tile.x2,
          y2 = this.tile.y2;
      x2 = Math.min(this.screen.width, x1 + width); 
      y2 = Math.min(this.screen.height, y1 + height); 
      x1 = Math.max(0, x2 - width);
      y1 = Math.max(0, y2 - height);
      this.$emit('onPositionTile', {
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
      });
    },
    onDelete() {
      this.$emit("onTileDelete");
    },
  }
})


Vue.component('asset-browser', {
  template: '#asset-browser',
  props: ["valid", "title", "help", "features"],
  methods: {
    onOpen() {
      var that = this;
      ib.assetChooser({
        filter: this.valid.split(','),
        features: this.features || ['image2k', 'h264'],
      }).then(function(selected) {
        selected && that.$emit('assetSelected', selected.id);
      })
    },
  }
})

Vue.component('date-select', {
  template: '#date-select',
  props: ['date', "unset"],
  computed: {
    date_set() {
      return this.date != undefined;
    },
    presets() {
      return [
        ["", this.unset],
        [moment()                 .format("YYYY-MM-DD"), "today"],
        [moment().add(1, "d")     .format("YYYY-MM-DD"), "tomorrow"],
        [moment().add(1, "w")     .format("YYYY-MM-DD"), "one week from now"],
        [moment().add(1, "M")     .format("YYYY-MM-DD"), "one month from now"],
        [moment().endOf("isoweek").format("YYYY-MM-DD"), "end of this week"],
        [moment().endOf("month")  .format("YYYY-MM-DD"), "end of this month"],
      ];
    },
  },
  methods: {
    onUnset() {
      this.$emit('onSetDate', '');
    },
    onSelect(value) {
      if (value != "")
        this.$emit('onSetDate', value);
    },
    onChange(date) {
      this.$emit('onSetDate', date);
    },
  }
})

Vue.component('time-editor', {
  template: '#time-editor',
  props: ['scheduling', 'excluded_schedule_id'],
  data: () => ({
    edit: false,
    set: false,
    modes: [
      ["always", "Always schedule"],
      ["never", "Never schedule"],
      ["hour", "Hour based"],
      ["span", "Exact time spans"],
      ["interval", "Time interval"],
      ["fallback", "Use as fallback"],
    ],
  }),
  computed: {
    date_note() {
      var starts = this.scheduling.starts;
      var ends = this.scheduling.ends;
      var now = moment();
      if (starts)
        starts = moment(starts);
      if (ends)
        ends = moment(ends);
      if (!starts && !ends)
        return '';
      if (ends && starts && ends.isBefore(starts))
        return 'End date is before start date';
      if (ends && ends.isBefore(now.startOf("day")))
        return 'This schedule ends in the past';
      return '';
    },
    mode() {
      return this.scheduling.mode || 'span';
    },
    other_schedules() {
      var options = [];
      options.push([null, "Copy schedule"]);
      var schedules = this.$store.state.config.schedules;
      for (var idx = 0; idx < schedules.length; idx++) {
        if (idx != this.excluded_schedule_id) {
          options.push([idx, schedules[idx].name]);
        }
      }
      return options;
    },
  },
  methods: {
    onSetStarts(date) {
      this.$emit('onDateChange', 'starts', date);
    },
    onSetEnds(date) {
      this.$emit('onDateChange', 'ends', date);
    },
    onSelectMode(mode) {
      this.$emit('onModeChange', mode);
    },
    onHourChange(hour, on) {
      this.$emit('onHourChange', hour, on);
    },
    onIntervalUpdate(interval) {
      this.$emit('onIntervalUpdate', interval);
    },
    onSpanAdd() {
      this.$emit('onSpanAdd');
    },
    onSpanDelete(span_id) {
      this.$emit('onSpanDelete', span_id);
    },
    onSpanUpdate(span_id, span) {
      this.$emit('onSpanUpdate', span_id, span);
    },
    onCopySchedule(schedule_id) {
      alert("TODO");
      // if (schedule_id == null)
      //   return;
      // var schedules = this.$store.state.config.schedules;
      // var source = schedules[schedule_id].scheduling;
      // for (var i = 0; i < 24*8; i++) {
      //   this.$emit('onTimeChange', i, source.hours[i]);
      // }
      // if (source.starts)
      //   this.$emit('onDateChange', 'starts', source.starts);
      // if (source.ends)
      //   this.$emit('onDateChange', 'ends', source.ends);
    },
  }
})

Vue.component('hour-editor', {
  template: '#hour-editor',
  props: ['scheduling'],
  data: () => ({
    edit: false,
    set: false,
  }),
  computed: {
    schedule_ui() {
      var days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
      var ui = [];
      for (var day = 0; day < 7; day++) {
        var hours = []
        var num_on = 0;
        for (var hour = 0; hour < 24; hour++) {
          var index = day * 24 + hour;
          var on = this.scheduling.hours[index];
          if (on == undefined)
            on = true;
          if (on)
            num_on++;
          hours.push({
            on: on,
            hour: hour,
            index: index,
          })
        }
        ui.push({
          name: days[day],
          day: day,
          toggle: num_on < 12,
          hours: hours,
        })
      }
      return ui;
    },
  },
  methods: {
    onEditStart(index) {
      this.edit = true;
      var on = this.scheduling.hours[index];
      if (on == undefined)
        on = true;
      this.set = !on;
      this.$emit('onHourChange', index, this.set);
    },
    onEditStop() {
      this.edit = false;
    },
    onToggleDay(day, on) {
      var offset = day * 24;
      for (var i = 0; i < 24; i++) {
        this.$emit('onHourChange', offset+i, on);
      }
    },
    onEditToggle(index) {
      if (this.edit) {
        this.$emit('onHourChange', index, this.set);
      }
    },
    onPreset(name) {
      if (name == 'never') {
        for (var i = 0; i < 24*8; i++) {
          this.$emit('onHourChange', i, false);
        }
      } else if (name == 'always') {
        for (var i = 0; i < 24*8; i++) {
          this.$emit('onHourChange', i, true);
        }
      } else if (name == 'weekend') {
        for (var i = 24*5; i < 24*8; i++) {
          this.$emit('onHourChange', i, true);
        }
      } else if (name == 'workday') {
        for (var i = 0; i < 24*5; i++) {
          this.$emit('onHourChange', i, true);
        }
      } else if (name == 'night') {
        var hours = this.scheduling.hours;
        for (var i = 0; i < 24*8; i++) {
          var hour = i % 24;
          var daytime = hour >= 8 && hour < 20;
          if (hours[i])
            this.$emit('onHourChange', i, daytime);
        }
      } else if (name == 'invert') {
        var hours = this.scheduling.hours;
        for (var i = 0; i < 24*8; i++) {
          this.$emit('onHourChange', i, hours[i] === false);
        }
      }
    },
  }
})

Vue.component('timeinterval-editor', {
  template: '#timeinterval-editor',
  props: ['scheduling'],
  created() {
    if (!this.scheduling.starts) {
      this.$emit('onSetDateStart', (new Date()).toISOString().substr(0, 10));
    }
  },
  computed: {
    interval() {
      return this.scheduling.interval || {}
    },
    has_end_date() {
      return !!this.scheduling.ends;
    },
    date_starts: {
      get() {
        return this.scheduling.starts;
      },
      set(v) {
        if (v) {
          this.$emit('onSetDateStart', v);
        }
      },
    },
    date_ends: {
      get() {
        return this.scheduling.ends;
      },
      set(v) {
        if (v) {
          this.$emit('onSetDateEnd', v);
        }
      },
    },
    interval_starts: {
      get() {
        return this.interval.starts || '00:00';
      },
      set(v) {
        if (v) {
          this.$emit('onUpdate', {
            starts: v,
            ends: this.interval_ends,
          })
        }
      },
    },
    interval_ends: {
      get() {
        return this.interval.ends || '23:59';
      },
      set(v) {
        if (v) {
          this.$emit('onUpdate', {
            starts: this.interval_starts,
            ends: v,
          })
        }
      },
    },
  },
  methods: {
    onAddEnd() {
      var date = new Date();
      date.setDate(date.getDate() + 7);
      this.$emit('onSetDateEnd', date.toISOString().substring(0, 10));
    },
    onDeleteEnd() {
      this.$emit('onSetDateEnd', undefined);
    }
  },
})

Vue.component('timespan-editor', {
  template: '#timespan-editor',
  props: ['scheduling'],
  computed: {
    spans() {
      return this.scheduling.spans || [];
    },
    days() {
      return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    }
  },
  methods: {
    onAdd() {
      this.$emit('onAdd');
    },
    onDelete(span_id) {
      this.$emit('onDelete', span_id);
    },
    onSetTime(span_id, which, time) {
      var span = deepcopy(this.spans[span_id]);
      span[which] = time;
      this.$emit('onUpdate', span_id, span);
    },
    onToggle(span_id, day_id, on) {
      var span = deepcopy(this.spans[span_id]);
      span.days[day_id] = on;
      this.$emit('onUpdate', span_id, span);
    },
  }
})

Vue.component('select-dropdown', {
  template: '#select-dropdown',
  props: ['values', 'selected', 'block'],
  methods: {
    onSelect(evt) {
      this.$emit('onSelected', JSON.parse(evt.target.value));
    },
  }
})

Vue.component('layout-panel', {
  template: '#layout-panel',
  computed: {
    config() { return this.$store.state.config; },
    layouts() { return this.config.layouts; },
  },
  methods: {
    onAdd() {
      this.$store.commit('layout_create');
    }
  }
})

Vue.component('layout-editor', {
  template: '#layout-editor',
  props: ['layout_id'],
  computed: {
    config() { return this.$store.state.config; },
    layouts() { return this.config.layouts; },
    layout() { return this.layouts[this.layout_id]; },
  },
  methods: {
    onAddTile(tile) {
      this.$store.commit('layout_tile_create', {
        layout_id: this.layout_id,
        tile: tile,
      })
    },
    onDeleteTile(tile_id) {
      this.$store.commit('layout_tile_delete', {
        layout_id: this.layout_id,
        tile_id: tile_id,
      });
    },
    onPositionTile(tile_id, pos) {
      this.$store.commit('layout_tile_set_pos', {
        layout_id: this.layout_id,
        tile_id: tile_id,
        pos: pos,
      });
    },
    onSelectTileAsset(tile_id, asset_spec) {
      this.$store.commit('layout_tile_set_asset', {
        layout_id: this.layout_id,
        tile_id: tile_id,
        asset_spec: asset_spec,
      })
    },
    onSetTileConfig(tile_id, {key, value}) {
      this.$store.commit('layout_tile_set_config', {
        layout_id: this.layout_id,
        tile_id: tile_id,
        key: key,
        value: value,
      })
    },
    onReorderTiles(tiles) {
      this.$store.commit('layout_tile_update', {
        layout_id: this.layout_id,
        tiles: tiles,
      });
    },
    onUpdateName(name) {
      this.$store.commit('layout_set_name', {
        layout_id: this.layout_id,
        name: name,
      })
    },
    onDeleteLayout() {
      this.$store.commit('layout_delete', {
        layout_id: this.layout_id,
      });
    },
  }
})

Vue.component('interaction-ui', {
  template: '#interaction-ui',
  props: ['interaction'],
  data: () => ({
    keys: [
      {key: "", value: "(no manual trigger)"},
      {key: "remote", value: "Remote Trigger"},
      {key: "space", value: "Space Key"},
      {key: "a", value: "Key 'A'"},
      {key: "b", value: "Key 'B'"},
      {key: "c", value: "Key 'C'"},
      {key: "d", value: "Key 'D'"},
      {key: "e", value: "Key 'E'"},
      {key: "f", value: "Key 'F'"},
      {key: "g", value: "Key 'G'"},
      {key: "h", value: "Key 'H'"},
      {key: "i", value: "Key 'I'"},
      {key: "j", value: "Key 'J'"},
      {key: "k", value: "Key 'K'"},
      {key: "l", value: "Key 'L'"},
      {key: "m", value: "Key 'M'"},
      {key: "n", value: "Key 'N'"},
      {key: "o", value: "Key 'O'"},
      {key: "p", value: "Key 'P'"},
      {key: "q", value: "Key 'Q'"},
      {key: "r", value: "Key 'R'"},
      {key: "s", value: "Key 'S'"},
      {key: "t", value: "Key 'T'"},
      {key: "u", value: "Key 'U'"},
      {key: "v", value: "Key 'V'"},
      {key: "w", value: "Key 'W'"},
      {key: "x", value: "Key 'X'"},
      {key: "y", value: "Key 'Y'"},
      {key: "z", value: "Key 'Z'"},

      {key: "0", value: "Key '0'"},
      {key: "1", value: "Key '1'"},
      {key: "2", value: "Key '2'"},
      {key: "3", value: "Key '3'"},
      {key: "4", value: "Key '4'"},
      {key: "5", value: "Key '5'"},
      {key: "6", value: "Key '6'"},
      {key: "7", value: "Key '7'"},
      {key: "8", value: "Key '8'"},
      {key: "9", value: "Key '9'"},

      {key: "kp0", value: "Numpad 0"},
      {key: "kp1", value: "Numpad 1"},
      {key: "kp2", value: "Numpad 2"},
      {key: "kp3", value: "Numpad 3"},
      {key: "kp4", value: "Numpad 4"},
      {key: "kp5", value: "Numpad 5"},
      {key: "kp6", value: "Numpad 6"},
      {key: "kp7", value: "Numpad 7"},
      {key: "kp8", value: "Numpad 8"},
      {key: "kp9", value: "Numpad 9"},

      {key: "kpdot",      value: "Numpad ,"},
      {key: "kpslash",    value: "Numpad /"},
      {key: "kpplus",     value: "Numpad +"},
      {key: "kpminus",    value: "Numpad -"},
      {key: "kpasterisk", value: "Numpad *"},
      {key: "kpenter",    value: "Numpad Enter"},
      {key: "numlock",    value: "Num Lock"},

      {key: "f1", value: "F1"},
      {key: "f2", value: "F2"},
      {key: "f3", value: "F3"},
      {key: "f4", value: "F4"},
      {key: "f5", value: "F5"},
      {key: "f6", value: "F6"},
      {key: "f7", value: "F7"},
      {key: "f8", value: "F8"},
      {key: "f9", value: "F9"},
      {key: "f10",value: "F10"},
      {key: "f11",value: "F11"},
      {key: "f12",value: "F12"},

      {key: "leftshift", value: "Left Shift"},
      {key: "leftctrl", value: "Left Ctrl"},
      {key: "leftalt", value: "Left Alt"},
      {key: "leftmeta", value: "Left Meta"},
      {key: "rightshift", value: "Right Shift"},
      {key: "rightctrl", value: "Right Ctrl"},
      {key: "rightalt", value: "Right Alt"},
      {key: "rightmeta", value: "Right Meta"},

      {key: "backspace", value: "Backspace"},
      {key: "compose", value: "Compose"},
      {key: "capslock", value: "Capslock"},
      {key: "esc", value: "Escape"},
      {key: "enter", value: "Enter"},
      {key: "tab", value: "Tab"},

      {key: "pad_x", value: "Gamepad X"},
      {key: "pad_y", value: "Gamepad Y"},
      {key: "pad_a", value: "Gamepad A"},
      {key: "pad_b", value: "Gamepad B"},
      {key: "pad_start", value: "Gamepad Start"},
      {key: "pad_select", value: "Gamepad Select"},
      {key: "pad_tl", value: "Gamepad Top-Left"},
      {key: "pad_tr", value: "Gamepad Top-Right"},

      {key: "gpio_2", value: "GPIO 2"},
      {key: "gpio_3", value: "GPIO 3"},
      {key: "gpio_4", value: "GPIO 4"},
      {key: "gpio_5", value: "GPIO 5"},
      {key: "gpio_6", value: "GPIO 6"},
      {key: "gpio_12", value: "GPIO 12"},
      {key: "gpio_13", value: "GPIO 13"},
      {key: "gpio_14", value: "GPIO 14"},
      {key: "gpio_15", value: "GPIO 15"},
      {key: "gpio_16", value: "GPIO 16"},
      {key: "gpio_17", value: "GPIO 17"},
      {key: "gpio_18", value: "GPIO 18"},
      {key: "gpio_19", value: "GPIO 19"},
      {key: "gpio_20", value: "GPIO 20"},
      {key: "gpio_21", value: "GPIO 21"},
      {key: "gpio_22", value: "GPIO 22"},
      {key: "gpio_23", value: "GPIO 23"},
      {key: "gpio_24", value: "GPIO 24"},
      {key: "gpio_25", value: "GPIO 25"},
      {key: "gpio_26", value: "GPIO 26"},
    ],
    durations: [
      {key: "auto",    value: "as configured"},
      {key: "forever", value: "forever"},
    ],
  }),
  computed: {
    remote: {
      get() {
        return this.interaction.remote || '';
      },
      set(val) {
        this.$emit('onChange', Object.assign({}, this.interaction, {
          remote: val,
        }));
      }
    }
  },
  methods: {
    onSelectKey(evt) {
      this.$emit('onChange', Object.assign({}, this.interaction, {
        key: evt.target.value
      }));
    },
    onSelectDuration(evt) {
      this.$emit('onChange', Object.assign({}, this.interaction, {
        duration: evt.target.value
      }));
    },
  }
})

new Vue({
  el: "#app",
  store,
})

ib.setDefaultStyle();
ib.ready.then(() => {
  ib.onAssetUpdate(() => {
    console.log("assets updated")
    store.commit('assets_update', ib.assets)
  })
  load_childs(ib.node_assets).then(() => {
    store.commit('init', {
      assets: ib.assets,
      node_assets: ib.node_assets,
      config: ib.config,
    })
    store.subscribe((mutation, state) => {
      ib.setConfig(state.config);
    })
  });
})
