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

export watch = [ 'host.ls', 'olio.ls', 'api', 'mid', 'lib', "#__dirname/../mid" ]

export api = ->*
  global.db = require fs.path.resolve "#__dirname/../lib/db"
  db database: olio.config.pg.db
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
  app.use (next) ->* # Main error handler
    try
      yield next
    catch e
      @response.status = (e.code and /^\d\d\d$/.test e.code and e.code) or 500
      @pg.error e if @pg
      if e.stack
        error e.stack.red
      else if e.message
        error e.message.red
      else
        error JSON.stringify(e).red
      if e.code and m = (/at Object\.out\$\.\w+.(\w+) \[as api\].*\/(\w+)\.ls/.exec (e.stack.split('\n') |> filter -> /\[as api\]/.test it))
        @log.error "#{e.code} #{e.message} (#{m[2]}.#{m[1]})"
        @response.body = e.message
      else
        @log.error e.message
  app.use require('koa-gzip')!
  app.use require('koa-bodyparser')!
  app.use (next) ->*
    if typeof! @request.body == 'Array'
      @in = @request.body |> map ~> (pairs-to-obj (obj-to-pairs @query |> map ~> [(camelize it.0), it.1])) <<< it
    else
      @in = (pairs-to-obj (obj-to-pairs @query |> map -> [(camelize it.0), it.1])) <<< @request.body
    segments = filter id, @url.split('/')
    @api = (api[segments.0] and ((!segments.1 and api[segments.0][segments.0]) or api[segments.0][segments.1])) or (api[inflection.singularize segments.0] and api[inflection.singularize segments.0][segments.0])
    @unsecured = true if @api in unsecured
    @error = (code, message) -> new ApiError code, message
    @required = (...p) ~> p |> each ~> throw @error 400, "Missing parameter: #it" if not @in.has-own-property camelize it
    @unsecured = -> warn "Non-secure api".red, @url.blue, "called from route".red, @header['x-route'].yellow
    yield next
  olio.config.api.mid |> each (m) ->
    app.use mid[m]
  app.use (next) ->*
    return if not @api
    if @ses
      yield @exec "set cfh.session = '#{@ses.id}'"
    for name, lib of olio.lib
      if typeof! lib == 'Function'
        throw @error 'Library function clobbers existing property' if @[name]
        @[name] = lib.bind this
      @[name] ?= {}
      @[name].ses = @ses
      if @pg
        @[name] <<< @pg.model
        @[name] <<< @pg{exec, first, relate, related, save, wrap}
      for key, val of lib
        throw @error 'Library function clobbers existing property' if @[name][key]
        @[name][key] = val.bind @[name]
    info "DISPATCH [#{@header['x-forwarded-for'] or '0.0.0.0'}] #{@url}".blue
    if @api.to-string!index-of('function*') != 0
      req =
        knex: ((table) -> db.knex camelize table)
        data: @in
        session: @ses
      req.knex.raw = db.knex.raw
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
      if typeof! req.data == 'Array'
        result = yield promise.all(req.data |> map ~> @api(req{knex, session} <<< { data: it }))
      else
        result = @api req, @response
      if typeof! result != 'Number'
        result = yield result
    else
      if typeof! @in == 'Array'
        data = @in
        result = []
        for item in data
          @in = item
          result.push(yield @api!)
      else
        result = yield @api!
    result ?= 200
    throw @pg.error! if @pg and @pg.error!
    if typeof! result == 'Number'
      @response.status = result
    else
      @body = result

  app.listen olio.config.api.port
  info "Started api server on port #{olio.config.api.port}".green


