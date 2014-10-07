require! \ng-annotate
require! \zlib

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
      request.method                  = 'post'
      request.url                     = '/api/' + module
      request.url                    += '/' + name if name
      console.info "API[##count] > " + request.url.substr(5), data
      request.transform-response      = (data) ->
        return JSON.parse data
      api.loading += 1
      $http request
      .success (data, status, headers, config) ->
        api.loading -= 1
        cache.set 'token', headers('X-Token') if headers('X-Token')
        console.info "API[##count] < " + request.url.substr(5), data
      .error (data, status, headers, config) ->
        api.loading -= 1
        cache.set 'token', headers('X-Token') if headers('X-Token')
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
  |> map -> (module == it and "  api._add '#it'") or "  api._add '#module', '#it'"
|> client-script.push
client-script = ng-annotate(livescript.compile(flatten(client-script).join('\n')), add: true).src

export incoming = ->*
  if @url == '/script'
    @response.set 'Content-Type', 'application/javascript'
    @body = client-script
    return true
