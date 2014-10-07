## TODO
# token
# session, persona, organization
# script
# params/data (camelized)


require! \glob
require! \koa

export watch = [ 'olio.ls', 'api', 'mid', "#__dirname/../mid" ]

export api = ->*
  olio.config.api ?= {}
  olio.config.api.port ?= 9001
  info "Starting api server on port #{olio.config.api.port}".green
  app = koa!
  app.use require('koa-gzip')!
  olio.config.api.mid |> each (m) ->
    return if not mid[m]
    app.use (next) ->*
      if @_mid = mid[m].incoming
        # Middleware should return true if they want to skip the rest of the middleware chain
        skip = yield @_mid
        delete @_mid
      yield next if not skip
      if @_mid = mid[m].outgoing
        yield @_mid
        delete @_mid
  app.use (next) ->*
    segments = filter id, @url.split('/')
    if @_api = api[segments.0] and ((!segments.1 and api[segments.0][segments.0]) or api[segments.0][segments.1])
      try
        @body = yield @_api!
      catch e
        error e
    yield next
  # app.use ->*
  #   @body = 'ok'
  app.listen olio.config.api.port

olio.api = api <<< require-dir "#{process.cwd!}/api"
mid = require-dir "#__dirname/../mid", "#{process.cwd!}/mid"

