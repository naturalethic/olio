require! \promise-mysql : mysql
require! './rivulet' : rivulet
require! './pp' : pp
require! \fast-json-patch : \patch
require! \object-path : objectpath

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

generate-search-query = (kind, path, value, limit) ->
  query = "SELECT DISTINCT id FROM document WHERE kind = ?"
  if path
    query += " AND path LIKE ?"
  if value
    query += " AND search LIKE ?"
  if limit
    query += " LIMIT #limit"
  query

object-from-path-values = (path-values = []) ->
  object = {}
  for pv in path-values
    objectpath.set object, pv.path, JSON.parse(pv.value)
  object

path-values-from-object = (object, path = '') ->
  path-values = []
  for key, val of object
    subpath = (path and "#path.#key") or key
    if is-array(val) or is-object(val)
      path-values ++= path-values-from-object val, subpath
    else if !is-undefined val
      path-values.push path: subpath, value: val
  path-values

persist-create-path-value = (connection, kind, old-doc, new-doc, path, value) ->*
  return if is-undefined value
  if is-object(value) or is-array(value)
    path-values = path-values-from-object value, path
  else
    path-values = [ path: path, value: value ]
  for pv in path-values
    yield connection.query "INSERT document (id, kind, path, value, search) VALUES (?, ?, ?, ?, ?)", [ new-doc.id, kind, pv.path, JSON.stringify(pv.value), pv.value.to-string!substr(0, 255) ]

persist-update-path-value = (connection, kind, old-doc, new-doc, path, value) ->*
  if is-undefined value
    return yield persist-delete-path-value connection, kind, old-doc, new-doc, path
  if is-object(value) or is-array(value)
    yield persist-delete-path-value connection, kind, old-doc, new-doc, path
    yield persist-create-path-value connection, kind, old-doc, new-doc, path, value
  else
    yield connection.query "UPDATE document SET value = ?, search = ? WHERE id = ? and path = ?", [ JSON.stringify(value), value.to-string!substr(0, 255), new-doc.id, path ]

persist-delete-path-value = (connection, kind, old-doc, new-doc, path) ->*
  value = objectpath.get old-doc, path
  if is-object(value) or is-array(value)
    path-values = path-values-from-object value, path
  else
    path-values = [ path: path, value: value ]
  for pv in path-values
    yield connection.query "DELETE FROM document WHERE id = ? and path = ?", [ new-doc.id, pv.path ]

export transaction = ->*
  connection = yield pool.get-connection!
  yield connection.begin-transaction!
  save-queue = {}
  tx =
    $info: $info
    query: (statement, params) ->*
      yield connection.query statement, params
    save: (kind, doc = {}) ->*
      doc.id ?= uuid!
      new-doc = doc.$get?! or doc
      path-values = yield connection.query "SELECT path, value FROM document WHERE id = ?", [ new-doc.id ]
      old-doc = object-from-path-values path-values
      diff = patch.compare old-doc, new-doc
      create-path-values = []
      update-path-values = []
      delete-path-values = []
      for change in diff
        path = change.path.substr(1).replace(/\//g, '.')
        continue if path is \id
        switch change.op
        | \add      => yield persist-create-path-value connection, kind, old-doc, new-doc, path, change.value
        | \replace  => yield persist-update-path-value connection, kind, old-doc, new-doc, path, change.value
        | \remove   => yield persist-delete-path-value connection, kind, old-doc, new-doc, path
        | otherwise => throw "Unhandled op: #{change.op}"
      tx.cursor kind, new-doc
    commit: ->*
      try
        for kind, cursors of save-queue
          for cursor in cursors
            yield tx.save kind, cursor
        yield connection.commit!
      catch
        yield connection.rollback!
      yield tx.query 'unlock tables'
      connection.release!
    rollback: ->*
      yield connection.rollback!
      yield tx.query 'unlock tables'
      connection.release!
    get: (id) ->*
      path-values = yield connection.query "SELECT kind, path, value FROM document WHERE id = ?", [ id ]
      return null if not first path-values
      return tx.cursor path-values.0.kind, (object-from-path-values(path-values) <<< id: id)
    select: (kind, path, value, limit) ->*
      selection = []
      if ids = ((yield connection.query generate-search-query(kind, path, value, limit), [ kind, path, value ]) |> map -> it.id)
        for id in ids
          selection.push yield tx.get id
      selection
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
  yield tx.query 'lock tables document write'
  tx

export select = ->*
  tx = yield transaction!
  tx.$info = $info
  try
    val = yield tx.select ...&
    yield tx.commit!
  catch e
    info e
    yield tx.rollback!
  val

export get = ->*
  tx = yield transaction!
  tx.$info = $info
  try
    val = yield tx.get ...&
    yield tx.commit!
  catch e
    info e
    yield tx.rollback!
  val

export save = ->*
  tx = yield transaction!
  tx.$info = $info
  try
    val = yield tx.save ...&
    yield tx.commit!
  catch e
    info e
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
      created datetime,
      updated datetime,
      id      char(36) not null,
      kind    varchar(255) not null,
      path    varchar(255) not null,
      value   text not null,
      search  varchar(255) not null,
      index   created (created),
      index   updated (updated),
      index   id (id),
      index   kind (kind),
      index   path (path),
      index   search (search),
      unique index id_path (id, path)
    )
  """
  info "Creating table 'history'"
  yield connection.query """
    create table history (
      at    datetime not null,
      id    char(36) not null,
      op    char(1) not null,
      kind  varchar(255) not null,
      path  varchar(255) not null,
      value text,
      index at (at),
      index id (id),
      index kind (kind),
      index path (path)
    );
  """
  info "Creating before insert trigger"
  yield connection.query """
    create trigger before_insert_document before insert on document
    for each row begin
      insert history (at, id, op, kind, path, value) values (now(), new.id, 'c', new.kind, new.path, new.value);
      set new.created = now(),
          new.updated = now();
    end;
  """
  info "Creating before update trigger"
  yield connection.query """
    create trigger before_update_document before update on document
    for each row begin
      insert history (at, id, op, kind, path, value) values (now(), new.id, 'u', new.kind, new.path, new.value);
      set new.updated = now();
    end;
  """
  info "Creating before delete trigger"
  yield connection.query """
    create trigger before_delete_document before delete on document
    for each row begin
      insert history (at, id, op, kind, path, value) values (now(), old.id, 'd', old.kind, old.path, null);
    end;
  """
  connection.end!
