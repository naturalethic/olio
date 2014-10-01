## TODO
# token
# session, persona, organization
# script
# params/data (camelized)


require! \glob
require! \koa

# Load both built-in and project middleware.  Project middleware will mask built-ins of the same name.
mid = {}
[ "#__dirname/../mid/*.ls", "#{process.cwd!}/mid/*.ls" ]
|> each ->
  glob.sync it
  |> each ->
    mid[fs.path.basename(it, '.ls')] = require it

apis = {}
[ "#{process.cwd!}/api/*.ls" ]
|> each ->
  glob.sync it
  |> each ->
    apis[fs.path.basename(it, '.ls')] = require it

export watch = [ 'api', 'mid', "#__dirname/../mid" ]

export api = ->*
  olio.config.api ?= {}
  olio.config.api.port ?= 9010
  info "Starting api server on port #{olio.config.api.port}".green
  app = koa!
  keys mid |> each (m) ->
    app.use (next) ->*
      if @_mid = mid[m].incoming
        yield @_mid
        delete @_mid
      yield next
      if @_mid = mid[m].outgoing
        yield @_mid
        delete @_mid
  app.use (next) ->*
    segments = filter id, @url.split('/')
    if apis[segments.0]
      if @_api = apis[segments.0][segments.1]
        try
          yield @_api
    yield next
  app.use ->*
    @body = 'ok'
  app.listen olio.config.api.port
