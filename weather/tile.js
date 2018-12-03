var config = {
  props: ['config'],
  template: `
    <div>
      <h4>Weather Plugin</h4>
      <div class='row'>
        <div class='col-xs-4'>
          <label class='field-label'>Display Mode</label><br/>
          <select class='btn btn-default' v-model="mode">
            <option value="forecast_24">24 hour forecast</option>
            <option value="forecast_7">7 day forecast</option>
            <option value="current_line">One line location/temperature</option>
          </select>
        </div>
        <div class='col-xs-4'>
          <label class='field-label'>Temperature Unit</label><br/>
          <select class='btn btn-default' v-model="temp">
            <option value="celsius">Celsius</option>
            <option value="fahrenheit">Fahrenheit</option>
          </select>
        </div>
        <div class='col-xs-4'>
          <label class='field-label'>Locale</label><br/>
          <select class='btn btn-default' v-model="locale">
            <option value="en">English</option>
            <option value="de">German</option>
          </select>
        </div>
      </template>
    </div>
  `,
  computed: {
    mode: ChildTile.config_value('mode', 'forecast_24'),
    temp: ChildTile.config_value('temp', 'celsius'),
    locale: ChildTile.config_value('locale', 'en'),
  }
}

ChildTile.register({
  config: config,
});
