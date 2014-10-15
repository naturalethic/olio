## TODO
# params/data (camelized)

require! \glob
require! \koa
require! \inflection
require! \util

function ApiError @code, @message = ''
  if not @message and typeof! @code != 'Number'
    @message = code
    @code = 500
  Error.call this, @message
  Error.capture-stack-trace this, this.constructor
util.inherits ApiError, Error

export watch = [ 'olio.ls', 'api', 'mid', 'lib', "#__dirname/../mid" ]

export api = ->*
  olio.api = api <<< require-dir "#{process.cwd!}/api"
  olio.config.api ?= {}
  olio.config.api.port ?= 9001
  mid = require-dir "#__dirname/../mid", "#{process.cwd!}/mid"
  unsecured = keys olio.config.api.unsecured
  |> map (m) ->
    keys olio.config.api.unsecured[m]
    |> map (f) -> api[m][f]
  |> flatten
  app = koa!
  app.use require('koa-gzip')!
  app.use require('koa-bodyparser')!
  app.use (next) ->*
    @in = (pairs-to-obj (obj-to-pairs @query |> map -> [(camelize it.0), it.1])) <<< @request.body
    segments = filter id, @url.split('/')
    @api = (api[segments.0] and ((!segments.1 and api[segments.0][segments.0]) or api[segments.0][segments.1])) or (api[inflection.singularize segments.0] and api[inflection.singularize segments.0][segments.0])
    @unsecured = true if @api in unsecured
    @error = (code, message) -> new ApiError code, message
    @required = (...p) ~> p |> each ~> throw @error 400, "Missing parameter: #it" if not @in.has-own-property camelize it
    yield next
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
    return if not @api
    info "DISPATCH #{@url}".blue
    try
      if @api.to-string!index-of('function*') != 0
        global.db = require fs.path.resolve './node_modules/ortho/lib/db'
        db database: olio.config.pg.db
        req =
          knex: ((table) -> db.knex camelize table)
          data: @in
          session: @session
        req.create = (table, properties = {}, other = {}) ->
          req.knex table
          .insert other <<< properties: properties
          .returning '*'
          .then -> it[0]
        req.relate = (table, ids, qualities) ->
          kds = keys ids
          if not qualities
            qualities = {}
            if kds.length > 2
              qualities <<< ids
              delete qualities[kds[0]]
              delete qualities[kds[1]]
          ids = { ("#{kds[0]}Id"): ids[kds[0]].id, ("#{kds[1]}Id"): ids[kds[1]].id }
          record = {} <<< ids <<< { qualities: qualities }
          req.knex table
          .where ids
          .then ->
            if it.length
              req.knex table
              .update record
              .where ids
            else
              req.knex table
              .insert record
        req.update = (table, data) ->
          req.knex table
          .first db.primary-key data
          .then ->
            return 404 if not it
            data.properties = it.properties <<< (data.properties || {}) if it.properties
            data.qualities  = it.qualities  <<< (data.qualities  || {}) if it.qualities
            req.knex table
            .update db.table-ready data
            .where db.primary-key data
        result = @api req, @response
        if typeof! result != 'Number'
          result = yield result
      else
        result = yield @api!
      result ?= 200
      throw @pg.error! if @pg and @pg.error!
      if typeof! result == 'Number'
        @response.status = result
      else
        @body = result
    catch e
      @response.status = e.code or 500
      @pg.error e if @pg
      error e.stack.red
      if e.code and m = (/at Object\.out\$\.\w+.(\w+) \[as api\].*\/(\w+)\.ls/.exec (e.stack.split('\n') |> filter -> /\[as api\]/.test it))
        @log.error "#{e.code} #{e.message} (#{m[2]}.#{m[1]})"
        @response.body = e.message
      else
        @log.error e.message

  app.listen olio.config.api.port
  info "Started api server on port #{olio.config.api.port}".green


