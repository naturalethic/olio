require! \promise-mysql : mysql
require! './rivulet' : rivulet

olio.config.world          ?= {}
olio.config.world.host     ?= \127.0.0.1
olio.config.world.user     ?= \root
olio.config.world.database ?= \cfh

pool = mysql.create-pool olio.config.world

re-path = /^\$\.(\w+)(\..*)?/
divy-path = (path) ->
  throw "Bad path: '#path'\nWorld paths must match the form '$.entity..'" if not re-path.test path
  [ kind, path ] = re-path.exec path .slice 1
  path = (path and "$#path") or '$'
  [ kind, path ]

export transaction = ->*
  connection = yield pool.get-connection!
  yield connection.begin-transaction!
  tx =
    save: (kind, doc) ->*
      doc = doc.$get! if doc.$get
      throw 'You must provide an id to save an entity' if not doc.id
      if first(yield connection.query "select i from document where id = ?", [ doc.id ])
        yield connection.query "update document set ? where id = ?", [ { data: JSON.stringify(doc) }, doc.id ]
      else
        yield connection.query "insert document set ?", [ { kind: kind, id: doc.id, data: JSON.stringify(doc) } ]
    extant: (path, value) ->*
      [ kind, path ] = divy-path path
      (first yield connection.query "select i from document where kind = ? and json_search(data, 'one', ?, NULL, ?) is not null limit 1", [ kind, value, path])?i
    commit: ->*
      yield connection.commit!
      connection.release!
    rollback: ->*
      yield connection.rollback!
      connection.release!
    select: (path, value) ->*
      [ kind, path ] = divy-path path
      if data = (first yield connection.query "select data from document where kind = ? and json_search(data, 'one', ?, NULL, ?) is not null limit 1", [ kind, value, path])?data
        cursor = rivulet JSON.parse data
        # Should only save this shit on commit
        cursor.$observe '$', co.wrap ->*
          info "Saving #kind", cursor.id
          yield tx.save kind, cursor.$get!
        return cursor
      null
    select-copy: (path, value) ->*
      if cursor = yield tx.select path, value
        return cursor.$get!
      null
  tx

export select = ->*
  tx = yield transaction!
  try
    val = yield tx.select ...&
    yield tx.commit!
  catch
    yield tx.rollback!
  val

export save = ->*
  tx = yield transaction!
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
  # info "Creating table 'world'"
  # yield connection.query "create table world (data json)"
  # info "Inserting record"
  # yield connection.query "insert world set data = '{}'"
  info "Creating table 'document'"
  yield connection.query """
    create table document (
      i       bigint not null auto_increment primary key,
      id      char(36),
      created datetime,
      updated datetime,
      kind    varchar(255),
      data    json,
      index   id (id),
      index   kind (kind)
    );
  """
  info "Creating insert trigger"
  yield connection.query """
    create trigger before_insert_document before insert on document
    for each row begin
      set new.created = now(),
          new.updated = now();
    end;
  """
  info "Creating update trigger"
  yield connection.query """
    create trigger before_update_document before update on document
    for each row begin
      set new.updated = now();
    end;
  """
  connection.end!
