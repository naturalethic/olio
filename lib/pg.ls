require! \pg

promisify-all pg
promisify-all pg.Client.prototype

exec = (connection, statement, ...args) ->
  args = args[0] if args.length == 1 and typeof! args[0] == 'Array'
  exec.i = 0
  statement = statement.replace /\?/g, -> exec.i += 1; '$' + exec.i
  connection.query-async statement, args
  .then ->
    it.rows
  .error ->
    connection.error = it
    throw it

first = (connection, statement, ...args) ->
  exec connection, statement, ...args
  .then ->
    it.length and it[0] or null

tables = (connection) ->
  exec connection, """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
    ORDER BY table_name;
  """
  .then ->
    it |> map -> it.table_name

columns = (connection, table) ->
  return promise.resolve(columns[table]) if columns[table]
  exec connection, """
    SELECT attrelid::regclass, attnum, attname
    FROM   pg_attribute
    WHERE  attrelid = '"public"."#{table}"'::regclass
    AND    attnum > 0
    AND    NOT attisdropped
    ORDER  BY attnum
  """
  .then ->
    columns[table] = it |> map -> it.attname

wrap = (connection, table, record) ->
  wrapper = new Proxy {}, {
    get: (target, name, receiver) ->
      switch
      | name[0] == '_'                => target[name]
      | name in columns[table]        => record[name]
      | record.properties             => record.properties[name]
      | record.qualities              => record.qualities[name]
      | otherwise                     => throw new Error 'Unknown property access'
    set: (target, name, val, receiver) ->
      switch
      | name[0] == '_'                => target[name] = val
      | name in columns[table]        => record[name] = val
      | record.properties             => record.properties[name] = val
      | record.qualities              => record.qualities[name]  = val
      | otherwise                     => throw new Error 'Unknown property access'
  }
  wrapper._table = table
  wrapper

setup-interface = (connection, release) ->
  model = {}
  tables connection
  .then (tables) ->
    tables |> each (table) ->
      # model[table] = (arg) ->
      #   (switch typeof! arg
      #   | 'String' => first connection, """SELECT * FROM "#{camelize table}" WHERE id = ?""", arg
      #   | 'Object' => exec connection, ("""SELECT * FROM "#{camelize table}" WHERE """ + (keys arg |> map -> "#{camelize it} = ?").join ' '), ...(values arg)
      #   ).then ->
      #     switch typeof! it
      #     | 'Array'   => it |> map -> wrap connection, table, it
      #     | otherwise => wrap connection, table, it
      model[table] = (record = {}) ->*
        cols = columns[table] |> filter -> record.has-own-property(it) or (it in [ 'qualities', 'properties' ])
        statement = """INSERT INTO #table ("#{cols.join('","')}") VALUES (#{(['?'] * cols.length).join(',')}) RETURNING *"""
        values = cols |> map ->
          return (record[it]) if it not in [ 'qualities', 'properties' ]
          extra = {}
          keys record
          |> filter -> it[0] != '_' and (it not in cols)
          |> each   -> extra[it] = record[it]
          JSON.stringify(extra)
        return wrap(connection, table, (yield first connection, statement, values))
    # XXX: This should only need to be called once at db initialization
    promise.all do
      tables |> map (table) ->
        columns connection, table
  .then ->
    do
      release: release
      model: model
      error: -> connection.error
      exec: (statement, ...args) -> exec(connection, statement, ...args)
      first: (statement, ...args) -> exec(connection, statement, ...args).then -> it.length and it[0] or null
      relate: (source, target, qualities) ->*
        join-table = camelize (sort [source._table, target._table]).join('-')
        source-id = (source._table == target._table and 'sourceId') or source._table + 'Id'
        target-id = (source._table == target._table and 'targetId') or target._table + 'Id'
        statement = """SELECT * FROM "#join-table" WHERE "#source-id" = ? AND "#target-id" = ?"""
        join-record = yield first connection, statement, source.id, target.id
        if not join-record
          statement = """INSERT INTO "#join-table" ("#source-id", "#target-id") VALUES (?, ?) RETURNING *"""
          join-record = yield first connection, statement, source.id, target.id
        if qualities
          statement = """UPDATE "#join-table" SET qualities = ? WHERE "#source-id" = ? AND "#target-id" = ?"""
          join-record = yield first connection, statement, JSON.stringify(qualities), source.id, target.id
        return target

export connect-pool = (url) ->
  pg.connect-async url
  .then ([connection, release]) ->
    setup-interface connection, release

export connect = (url, single) ->
  client = new pg.Client url
  client.connect-async!
  .then ->
    setup-interface client, -> client.end!
