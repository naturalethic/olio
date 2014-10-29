# XXX: SUPER DEPRECATED FILE

require! \inflection

String::dasherize  = -> inflection.dasherize(inflection.underscore(@replace(/-/g, '_')))
String::camelize   = -> inflection.camelize(inflection.underscore(@replace(/-/g, '_')), true)
String::capitalize = -> inflection.capitalize this
String::titleize   = -> inflection.titleize this
String::pluralize  = -> inflection.pluralize this

module.exports = db = (options, next = ->) ->
  db.geo = (require 'knex').initialize do
    debug: options.debug
    client: 'pg'
    connection:
      host:     olio.config.pg.host or '127.0.0.1'
      user:     'postgres'
      database: 'geo'
    pool:
      min: 0
      max: 7
  knex-options =
    debug: options.debug
    client: 'pg'
    connection:
      host:     olio.config.pg.host or '127.0.0.1'
      user:     'postgres'
      database: (options.database or options.application)
    pool:
      min: 0
      max: 7
  if options.sessionless
    knex-options.pool.max = 1
  db.knex                         = knex = (require 'knex').initialize knex-options
  query-builder                   = knex.client.QueryBuilder.prototype
  query-builder.original-select   = query-builder.select
  query-builder.original-first    = query-builder.first
  query-builder.original-join     = query-builder.join
  query-builder.original-where    = query-builder.where
  query-builder.original-where-in = query-builder.where-in
  query-builder.select = (columns) ->
    columns = compact arguments if typeof! columns != 'Array'
    @original-select (columns |> map -> it.camelize!)
  query-builder.first = (columns) ->
    columns = compact arguments if typeof! columns != 'Array'
    @original-first (columns |> map -> it.camelize!)
  query-builder.join = (table, first, ...args) ->
    operator = '='
    if args.length == 1
      second = args[0]
    if args.length == 2
      operator = args[0]
      second   = args[1]
    @original-join table.camelize!, first.camelize!, operator, second.camelize!
  query-builder.where = (data, ...args) ->
    for dkey in (keys data)
      if typeof! data[dkey] == 'Object'
        for key in (keys data[dkey])
          @where-raw "#dkey ->> '#key'='#{data[dkey][key]}'"
        delete data[dkey]
    @original-where data, ...args
  query-builder.where-in = (key, ...args) ->
    @original-where-in key.camelize!, ...args
  query-builder.load = (data) ->
    table = @_single.table.camelize!
    return (@then ~> db.client-ready it, table) if not data
    @where id: data["#{table}Id"]
    @then ~> db.client-ready-one it[0], table
  query-builder.save = (data) ->
    table = @_single.table.camelize!
    db.columns table
    .then (columns) ~>
      attr = (intersection [ 'properties', 'qualities' ], columns).join('')
      new-data = {}
      for key, val of data
        continue if key == "#{table}Id" or key == 'id'
        if key not in columns
          new-data[attr] ?= {}
          new-data[attr][key] = data[key]
        else
          new-data[key] = data[key]
      id = data["#{table}Id"] or data['id']
      if id
        @where id: id
        @first!
        @then ~>
          return null if not it
          new-data[attr] = it[attr] <<< new-data[attr]
          @update new-data
      else
        @insert new-data
        .returning '*'

  if options.sessionless
    db.knex.raw "SET SESSION ortho.session = '#{system-ids.1}'"
    .then ->
      knex = db.knex
      db.knex = (table) -> knex table.camelize!
      db.knex.raw = -> knex.raw ...
      next!
  else
    next!

column-cache = {}

db.columns = (table) ->
  return promise(column-cache[table]) if column-cache[table]
  db.knex.raw """
    SELECT attrelid::regclass, attnum, attname
    FROM   pg_attribute
    WHERE  attrelid = '"public"."#{table}"'::regclass
    AND    attnum > 0
    AND    NOT attisdropped
    ORDER  BY attnum
  """
  .then ->
    column-cache[table] = it.rows |> map -> it.attname

db.table-ready = (table, data) ->
  relation = /\-/.test table
  if relation
    values  = { qualities: { } }
  else
    values  = { properties: { } }
  values = (keys data)
  |> filter -> !(it == 'id' or /Id$/.test it)
  return { qualities: values } if /\-/.test table
  { properties: values }

db.primary-key = (table, data) ->
  primary = {}
  (keys data) |> each ->
    if it == "#{table}Id"
      primary.id = data[it]
    else if /\-/.test(table) and (it == 'id' or /Id$/.test it)
      primary[it] = data[it]
  primary

db.client-ready-one = (record, table) ->
  data = {}
  (keys record) |> each ->
    if it == 'id' and table
      data["#{table}Id"] = record[it]
    else if typeof! record[it] == 'Object'
      data <<< record[it]
    else
      data[it] = record[it]
  data

db.client-ready = (records, table) ->
  return db.client-ready-one(records, table) if typeof!(records) != 'Array'
  records |> map -> db.client-ready-one it, table
