'use strict';

const store = new Vuex.Store({
  strict: true,
  state: {
    hits: [],
    searching: false,
    config: {
    },
  },
  mutations: {
    init(state, {config}) {
      config.lat = config.lat || 0;
      config.lon = config.lon || 0;
      config.name = config.name || "";
      config.query = config.query || "";
      state.config = config;
    },
    set_hits(state, hits) {
      state.hits = hits;
    },
    set_query(state, query) {
      state.config.query = query;
    },
    set_searching(state, on_off) {
      state.searching = on_off;
    },
    set_location(state, {lat, lon, name}) {
      state.config.lat = lat;
      state.config.lon = lon;
      state.config.name = name;
    },
  },
  actions: {
    search({state, commit}, query) {
      query = query.trim();
      commit('set_query', query);
      if (query.length == 0) {
        commit('set_hits', [])
        return;
      }
      commit('set_searching', true);
      ib.apis.geo.get({
        q: state.config.query,
      }).then(function(response) {
        commit('set_hits', response.hits);
        commit('set_searching', false);
      }).catch(function(err) {
        console.log(err);
        commit('set_searching', false);
      })
    }
  }
})

Vue.component('config-ui', {
  template: '#config-ui',
  computed: {
    config() {
      return this.$store.state.config;
    },
    lat() {
      return this.config.lat;
    },
    lon() {
      return this.config.lon;
    },
    name() {
      return this.config.name;
    },
    query() {
      return this.config.query;
    },
    searching() {
      return this.$store.state.searching;
    },
    hits() {
      return this.$store.state.hits;
    },
  },
  methods: {
    onSearch(keycode, query) {
      if (keycode == 13) {
        this.$store.dispatch('search', query);
      }
    },
    onSelect(hit) {
      this.$store.commit('set_location', hit);
    },
    mapLink(lat, lon) {
      return 'https://www.openstreetmap.org/?mlat='+lat+'&mlon='+lon+'&zoom=15';
    }
  }
})

const app = new Vue({
  el: "#app",
  store,
})

ib.setDefaultStyle();
ib.ready.then(() => {
  store.commit('init', {
    config: ib.config,
  })
  if (ib.config.query) {
    store.dispatch('search', ib.config.query);
  }
  store.subscribe((mutation, state) => {
    ib.setConfig(state.config);
  })
})
