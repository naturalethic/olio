require! \pg
require! \knex

knex = knex client: 'pg'

promisify-all pg
promisify-all pg.Client.prototype

exec = (connection, statement, ...args) ->*
  statement = statement.to-string! if typeof! statement != 'String'
  args = args[0] if args.length == 1 and typeof! args[0] == 'Array'
  exec.i = 0
  statement = statement.replace /\?/g, -> exec.i += 1; '$' + exec.i
  statement = statement.replace /\w+\-\w+/g, -> if camelized[it] then "\"#{camelized[it]}\"" else it
  return (yield connection.query-async statement, args).rows

exec-first = (connection, statement, ...args) ->*
  it = yield exec connection, statement + ' LIMIT 1', ...args
  return it.length and it[0] or null

camelized = {}

tables = (connection) ->*
  return ((yield exec connection, """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
    ORDER BY table_name;
  """) |> map ->
    camelized[dasherize it.table_name] = it.table_name if /\-/.test dasherize(it.table_name)
    it.table_name)

columns = (connection, table) ->*
  columns[table] = ((yield exec connection, """
    SELECT attrelid::regclass, attnum, attname
    FROM   pg_attribute
    WHERE  attrelid = '"public"."#{table}"'::regclass
    AND    attnum > 0
    AND    NOT attisdropped
    ORDER  BY attnum
  """) |> map ->
    camelized[dasherize it.attname] = it.attname if /\-/.test dasherize(it.attname)
    it.attname)

wrap = (table, record) ->
  return null if not record
  target = ^^record
  target.toJSON = ->
    obj = pairs-to-obj(columns[table] |> (filter -> it not in [ 'id', 'properties', 'qualities' ]) |> map -> [ it, record[it] ])
    obj[table + 'Id'] = record.id
    obj <<< record.properties or {}
    obj <<< record.qualities  or {}
    obj
  target.inspect = -> record
  new Proxy target, do
    get: (target, name, receiver) ->
      switch
      | name == '_table'                                              => table
      | name == '_record'                                             => record
      | name in columns[table]                                        => record[name]
      | record.properties and record.properties.has-own-property name => record.properties[name]
      | record.qualities  and record.qualities.has-own-property name  => record.qualities[name]
      | otherwise                                                     => target[name]
    set: (target, name, val, receiver) ->
      switch
      | name in columns[table]                                        => record[name] = val
      | record.properties and record.properties.has-own-property name => record.properties[name] = val
      | record.qualities  and record.qualities.has-own-property name  => record.qualities[name]  = val
      | otherwise                                                     => target[name] = val

setup-interface = (connection, release) ->*
  model = {}
  setup-model = (table) ->
    # Model function creates or loads records
    model[table] = (record = {}) ->*
      if typeof! record == 'String'
        return wrap(table, (yield exec-first connection, """SELECT * FROM #table WHERE id = ?""", record))
      else
        cols = columns[table] |> filter -> record.has-own-property(it) or (it in [ 'qualities', 'properties' ])
        if cols.length
          statement = """INSERT INTO #table ("#{cols.join('","')}") VALUES (#{(['?'] * cols.length).join(',')}) RETURNING *"""
        else
          statement = """INSERT INTO #table DEFAULT VALUES RETURNING *"""
        values = cols |> map ->
          return (record[it]) if it not in [ 'qualities', 'properties' ]
          extra = {}
          keys record
          |> filter -> it[0] != '_' and (it not in cols)
          |> each   -> extra[it] = record[it]
          JSON.stringify(extra)
        return wrap(table, (yield exec connection, statement, values)[0])
    model[table].find = (query = {}) ->*
      statement = knex(table).select '*'
      keys query |> each -> (typeof! query[it] == 'Array' and statement.where-in it, query[it]) or statement.where it, query[it]
      records = yield exec connection, statement
      return (records |> map -> wrap(table, it))
    model[table].first = (query = {}) ->*
      statement = knex(table).select '*'
      keys query |> each -> (typeof! query[it] == 'Array' and statement.where-in it, query[it]) or statement.where it, query[it]
      record = yield exec-first connection, statement
      return (record and wrap(table, record)) or null
  for table in (yield tables connection)
    yield columns connection, table if not columns[table]
    setup-model table
  return do
    release: release
    model: model
    error: -> @_error = it if it; connection.error or @_error
    exec: (statement, ...args) -> exec(connection, statement, ...args)
    first: (statement, ...args) -> exec-first(connection, statement, ...args)
    relate: (source, target, qualities) ->*
      join-table = camelize (sort [source._table, target._table]).join('-')
      source-id = (source._table == target._table and 'sourceId') or source._table + 'Id'
      target-id = (source._table == target._table and 'targetId') or target._table + 'Id'
      statement = """SELECT * FROM "#join-table" WHERE "#source-id" = ? AND "#target-id" = ?"""
      join-record = yield exec-first connection, statement, source.id, target.id
      if not join-record
        statement = """INSERT INTO "#join-table" ("#source-id", "#target-id") VALUES (?, ?) RETURNING *"""
        yield exec connection, statement, source.id, target.id
      if qualities
        statement = """UPDATE "#join-table" SET qualities = ? WHERE "#source-id" = ? AND "#target-id" = ?"""
        yield exec connection, statement, JSON.stringify(qualities), source.id, target.id
      return target
    related: (source, target, properties = {}, qualities = {}) ->*
      source = { _table: source } if typeof! source == 'String'
      target = { _table: target } if typeof! target == 'String'
      join-table = camelize (sort [source._table, target._table]).join('-')
      source-id = (source._table == target._table and 'sourceId') or source._table + 'Id'
      target-id = (source._table == target._table and 'targetId') or target._table + 'Id'
      statement = knex(join-table)
      if source.id
        statement.join target._table, "#join-table.#target-id", "#{target._table}.id"
        statement.where (source-id): source.id
        keys properties |> each -> statement.where-raw " #{target._table}.properties ->> '#it' = ?"
        keys qualities  |> each -> statement.where-raw " #join-table.qualities ->> '#it' = ?"
        statement.select "qualities, #{target._table}.*"
      else
        statement.join source._table, "#join-table.#source-id", "#{source._table}.id"
        statement.where (target-id): target.id
        keys properties |> each -> statement.where-raw " #{source._table}.properties ->> '#it' = ?"
        keys qualities  |> each -> statement.where-raw " #join-table.qualities ->> '#it' = ?"
        statement.select "qualities, #{source._table}.*"
      records = yield exec connection, statement, (values properties) ++ (values qualities)
      if source.id
        return (records |> map -> wrap(target._table, it))
      else
        return (records |> map -> wrap(source._table, it))
    save: (source) ->*
      copy = {} <<< source._record
      id = delete copy.id
      yield exec connection, "UPDATE #{source._table} SET " + (keys copy |> map -> "\"#{camelize it}\" = ?").join(', ') + " WHERE id = ?", (values copy) ++ [ id ]
      return source

export connect-pool = (url) ->*
  [ connection, release ] = yield pg.connect-async url
  return yield setup-interface connection, release

export connect = (url, single) ->*
  client = new pg.Client url
  yield client.connect-async!
  return yield setup-interface client, -> client.end!
