require! \promise-mysql : mysql
require! './rivulet' : rivulet
require! './pp' : pp

olio.config.world          ?= {}
olio.config.world.host     ?= \127.0.0.1
olio.config.world.user     ?= \root
olio.config.world.database ?= \cfh

pool = mysql.create-pool olio.config.world

$info = (...args) ->
  date = (new Date).toISOString!split \T
  if is-string(args.0)
    args.0 = args.0.magenta
  args.unshift "#{date.0.cyan}#{'T'.grey}#{date.1.cyan} #{'0.0.0.0'.yellow} #{'INFO'.green}"
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  info ...args
  pp obj if obj

walk-for-index = (value, path = '') ->
  paths = {}
  for key, val of value
    subpath = (path and "#path.#key") or key
    if is-array(val) or is-object(val)
      paths <<< walk-for-index val, subpath
    else if !is-undefined val
      paths[subpath] = val.to-string!substr(0, 255)
  paths

generate-search-query = (kind, path, value, limit) ->
  query = "SELECT DISTINCT id FROM search WHERE kind = ?"
  if path
    query += " AND path LIKE ?"
  if value
    query += " AND value LIKE ?"
  if limit
    query += " LIMIT #limit"
  query

export transaction = (lock = false) ->*
  connection = yield pool.get-connection!
  yield connection.begin-transaction!
  save-queue = {}
  tx =
    $info: $info
    query: (statement, params) ->*
      yield connection.query statement, params
    save: (kind, doc = {}) ->*
      json = doc.$get?! or doc
      if doc.id
        tx.$info "Updating #kind", doc.id
        yield connection.query "update document set ? where id = ?", [ { data: JSON.stringify(json) }, doc.id ]
      else
        doc.id = uuid!
        tx.$info "Inserting #kind", doc.id
        yield connection.query "insert document set ?", [ { kind: kind, id: doc.id, data: JSON.stringify(json) } ]
      json = doc.$get?! or ({} <<< doc)
      if kind != \session
        yield connection.query "delete from search where id = ?", [ json.id ]
        for path, value of walk-for-index json
          yield connection.query "insert search (id, kind, path, value) values (?, ?, ?, ?)", [ json.id, kind, path, value ]
      tx.cursor kind, json
    commit: ->*
      try
        for kind, cursors of save-queue
          for cursor in cursors
            yield tx.save kind, cursor
        yield connection.commit!
      catch
        yield connection.rollback!
      yield tx.query 'unlock tables' if lock
      connection.release!
    rollback: ->*
      yield connection.rollback!
      yield tx.query 'unlock tables' if lock
      connection.release!
    get: (id) ->*
      return null if not result = first yield connection.query "select kind, data from document where id = ?", [ id ]
      return tx.cursor result.kind, result.data
    select: (kind, path, value, limit) ->*
      if ids = ((yield connection.query generate-search-query(kind, path, value, limit) + " LOCK IN SHARE MODE", [ kind, path, value ]) |> map -> it.id)
        return (yield connection.query "select data from document where id in ('#{ids.join('\', \'')}')") |> map -> tx.cursor kind, it.data
      []
    select-one: (kind, path, value) ->*
      first yield tx.select kind, path, value, 1
    cursor: (kind, data) ->
      data = JSON.parse data if is-string data
      data = data.$get! if data.$get
      cursor = rivulet data
      cursor.$observe '$', co.wrap ->*
        save-queue[kind] ?= []
        save-queue[kind].push cursor if cursor not in save-queue[kind]
      cursor
  yield tx.query 'lock tables document write' if lock
  tx

export select = ->*
  tx = yield transaction!
  tx.$info = $info
  try
    val = yield tx.select ...&
    yield tx.commit!
  catch
    yield tx.rollback!
  val

export get = ->*
  tx = yield transaction!
  tx.$info = $info
  try
    val = yield tx.get ...&
    yield tx.commit!
  catch
    yield tx.rollback!
  val

export save = ->*
  tx = yield transaction!
  tx.$info = $info
  try
    val = yield tx.save ...&
    yield tx.commit!
  catch
    yield tx.rollback!
  val

export end = ->*
  yield pool.end!

export reset = ->*
  connection = yield mysql.create-connection olio.config.world{host, user}
  if first((yield connection.query 'show databases') |> filter -> it.Database is olio.config.world.database)
    info "Dropping database '#{olio.config.world.database}'"
    yield connection.query "drop database if exists #{olio.config.world.database}"
  info "Creating database '#{olio.config.world.database}'"
  yield connection.query "create database #{olio.config.world.database}"
  connection.end!
  connection = yield mysql.create-connection olio.config.world{host, user, database}
  info "Creating table 'document'"
  yield connection.query """
    create table document (
      i       bigint not null auto_increment primary key,
      id      char(36),
      created datetime,
      updated datetime,
      kind    varchar(255),
      data    text,
      index   id (id),
      index   kind (kind)
    );
  """
  info "Creating table 'history'"
  yield connection.query """
    create table history (
      i     bigint not null auto_increment primary key,
      id    char(36),
      at    datetime,
      kind  varchar(255),
      data  text,
      index at (at)
    );
  """
  info "Creating table 'search'"
  yield connection.query """
    create table search (
      id    char(36),
      kind  varchar(255),
      path  varchar(255),
      value varchar(255),
      index id (id),
      index kind (kind),
      index path (path),
      index value (value)
    )
  """
  info "Creating before insert trigger"
  yield connection.query """
    create trigger before_insert_document before insert on document
    for each row begin
      set new.created = now(),
          new.updated = now();
    end;
  """
  info "Creating before update trigger"
  yield connection.query """
    create trigger before_update_document before update on document
    for each row begin
      insert history (id, at, kind, data) values (old.id, now(), old.kind, old.data);
      set new.updated = now();
    end;
  """
  connection.end!
