var config = {
  props: ['config'],
  template: `
    <div>
    </div>
  `,
  methods: {
    onClick: function(evt) {
      // this.$emit('setConfig', 'foo', 'bar');
    },
  }
}

ChildTile.register({
  config: config,
})
