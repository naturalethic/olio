require! \ng-annotate
require! \zlib
require! \inflection

client-script = ['''
window.cache =
  set: (...args) -> local-storage.set-item ...args
  get: (...args) -> local-storage.get-item ...args
  del: (...args) -> local-storage.remove-item ...args

re-uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

angular.module 'NG-APPLICATION'
.factory 'api', ($http) ->
  invoke = (module, name) ->
    (data) ->
      invoke.count += 1
      count = invoke.count
      if typeof! data == 'Array'
        data = data |> map -> {} <<<< it
      else
        data = {} <<<< data
      request                         = { data: data, headers: {} }
      request.headers['Content-Type'] = 'application/json'
      request.headers['X-Token']      = cache.get 'token'   if (cache.get 'token') and re-uuid.test(cache.get 'token')
      request.headers['X-Persona']    = cache.get 'persona' if (cache.get 'persona') and re-uuid.test(cache.get 'persona')
      request.headers['X-Route']      = state.route
      request.method                  = 'post'
      request.url                     = '/api/' + module
      request.url                    += '/' + name if name
      log-data = {} <<< data
      log-data.secret = '********' if log-data.secret
      log-data.old-secret = '********' if log-data.old-secret
      console.info "API[#count] > "   + request.url.substr(5), log-data
      request.transform-response      = (data) ->
        try
          data = JSON.parse data
        data
      api.loading += 1
      if state.analytics
        ga 'send', 'pageview', page: request.url
      $http request
      .success (data, status, headers, config) ->
        api.loading -= 1
        if headers('X-Token')
          cache.set 'token', headers('X-Token')
        console.info "API[#count] < #{request.url.substr(5)}", status, data
      .error (data, status, headers, config) ->
        api.loading -= 1
        if headers('X-Token')
          cache.set 'token', headers('X-Token')
        console.info "API[#count] < #{request.url.substr(5)}", status, data
        state.go 'root' if status == 419
  invoke.count = 0
  api =
    loading: 0
    _ready: false
    _add: (module, name) ->
      if not api[module]
        api[module] = {}
      if not name
        api[module] = invoke module
      else
        api[module][name] = invoke module, name

.run (api) ->
  api._ready = true
'''.replace 'NG-APPLICATION', olio.config.app || 'app']

keys olio.api
|> map (module) ->
  keys olio.api[module]
  |> map -> (module == it and "  api._add '#it'") or (inflection.pluralize(module) == it and "  api._add '#it'") or "  api._add '#module', '#it'"
|> client-script.push
client-script = ng-annotate(livescript.compile(flatten(client-script).join('\n')), add: true).src

module.exports = (next) ->*
  if @url == '/script'
    @response.set 'Content-Type', 'application/javascript'
    @body = client-script
  else
    yield next
