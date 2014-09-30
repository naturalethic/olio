require! \pg

promisify-all pg

exec = (connection, statement, ...args) ->
  s = statement.split '?'
  statement = (flatten (zip s, ([1 til s.length] |> map -> "$#it"))).join('') if s.length > 1
  connection.query-async statement, args
  .then ->
    it.rows

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

wrap = (connection, table, shadow) ->
  wrapper = ^^shadow
  wrapper.set = (key, val) ->
    shadow[key] = val
    wrapper
  wrapper.save = ->
    info shadow
    wrapper
  wrapper.shadow = shadow
  wrapper

export connect = (url) ->
  pg.connect-async url
  .then ([connection, release]) ->
    model = {}
    tables connection
    .then (tables) ->
      tables |> each (table) ->
        model[table] = (arg) ->
          (switch typeof! arg
          | 'String' => first connection, """SELECT * FROM "#{camelize table}" WHERE id = ?""", arg
          | 'Object' => exec connection, ("""SELECT * FROM "#{camelize table}" WHERE """ + (keys arg |> map -> "#{camelize it} = ?").join ' '), ...(values arg)
          ).then ->
            switch typeof! it
            | 'Array'   => it |> map -> wrap connection, table, it
            | otherwise => wrap connection, table, it
      # XXX: This should only need to be called once at db initialization
      promise.all do
        tables |> map (table) ->
          columns connection, table
    .then ->
      do
        exec:    (statement, ...args) -> exec(connection, statement, ...args)
        first:   (statement, ...args) -> exec(connection, statement, ...args).then -> it.length and it[0] or null
        release: release
        model:   model
