var config = {
  props: ['config'],
  template: `
    <div>
      <h4>Browser Plugin</h4>
      <div class='row'>
        <div class='col-xs-9'>
          <input placeholder="Url, e.g. https://old.reddit.com" v-model="url" class='form-control'/>
        </div>
        <div class='col-xs-3'>
          <button v-if="!advanced" class='btn btn-block btn-default' @click="advanced=true">Advanced settings</button>
          <button v-else disabled class='btn btn-block btn-default'>Advanced settings</button>
        </div>
        <!-- 
        <div class='col-xs-4'>
          <select class='btn btn-default' v-model="scale">
            <option value="75">75%</option>
            <option value="90">90%</option>
            <option value="100">100% (default)</option>
            <option value="110">110%</option>
            <option value="120">120%</option>
            <option value="130">130%</option>
            <option value="140">140%</option>
            <option value="150">150%</option>
            <option value="160">160%</option>
            <option value="180">180%</option>
            <option value="200">200%</option>
          </select>
        </div>
        -->
      </div>
      <div v-if='advanced' class='row'>
        <br/>
        <div class='col-xs-4'>
          <input placeholder="Optional DOM selector" v-model="selector" class='form-control'/>
        </div>
        <div class='col-xs-4'>
          <select class='btn btn-block btn-default' v-model="max_age">
            <option value="60">Every minute</option>
            <option value="90">Every 90 seconds</option>
            <option value="120">Every 2 minutes</option>
            <option value="180">Every 3 minutes</option>
            <option value="300">Every 5 minutes</option>
          </select>
        </div>
        <div class='col-xs-4'>
          <select class='btn btn-default' v-model="condition">
            <option value="load">Wait for load event</option>
            <option value="domcontentloaded">Wait for dom content load</option>
            <option value="networkidle2">Wait for 2 connections idle</option>
            <option value="networkidle0">Wait for all connections idle</option>
          </select>
        </div>
      </div>
      <br/>
      <div class="alert alert-info" role="alert">
        The requested Url is updated at most every minute. A static screenshot is created
        and shown, so you can't show any kind of animated content. Your content must also be
        publicly reachable, so you can't show content from your internal network.
      </div>
    </div>
  `,
  data: () => ({
    advanced: false,
  }),
  computed: {
    url: ChildTile.config_value('url', ''),
    selector: ChildTile.config_value('selector', ''),
    scale: ChildTile.config_value('scale', 100, parseInt),
    max_age: ChildTile.config_value('max_age', 180, parseInt),
    condition: ChildTile.config_value('condition', 'networkidle2'),
  }
}

ChildTile.register({
  config: config,
});
