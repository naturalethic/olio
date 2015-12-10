require! \promise-mysql : mysql
require! './rivulet' : rivulet
require! './pp' : pp
require! \elasticsearch

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

export transaction = ->*
  elastic = new elasticsearch.Client host: "#{olio.config.secretary.host}:#{olio.config.secretary.port}"
  promisify-all elastic
  promisify-all elastic.indices
  connection = yield pool.get-connection!
  yield connection.begin-transaction!
  save-queue = {}
  tx =
    secretary: elastic
    query: (statement, params) ->*
      yield connection.query statement, params
    search: (kind, query) ->*
      result = first yield elastic.search-async index: \document, type: kind, body: { query: query }
      records = []
      for hit in result.hits.hits
        records.push yield tx.get hit._source.id
      records
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
      tx.cursor kind, json
    extant: (kind, key, val) ->*
      (first yield connection.query "select i from document where kind = ? and data like ? limit 1", [ kind, "%\"#key\":\"#val\"%" ])?i
    commit: ->*
      try
        for kind, cursors of save-queue
          for cursor in cursors
            yield tx.save kind, cursor
        yield connection.commit!
      catch
        yield connection.rollback!
      connection.release!
    rollback: ->*
      yield connection.rollback!
      connection.release!
    get: (id) ->*
      return null if not result = first yield connection.query "select kind, data from document where id = ?", [ id ]
      return tx.cursor result.kind, result.data
    select: (kind, key, val) ->*
      if key
        data = (first yield connection.query "select data from document where kind = ? and data like ? limit 1", [ kind, "%\"#key\":\"#val\"%" ])?data
      else
        data = (first yield connection.query "select data from document where kind = ? limit 1", [ kind ])?data
      if data
        return tx.cursor kind, data
      null
    cursor: (kind, data) ->
      data = JSON.parse data if is-string data
      data = data.$get! if data.$get
      cursor = rivulet data
      cursor.$observe '$', co.wrap ->*
        save-queue[kind] ?= []
        save-queue[kind].push cursor if cursor not in save-queue[kind]
      cursor
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
      i       bigint not null auto_increment primary key,
      id      char(36),
      created datetime,
      kind    varchar(255),
      data    text,
      index   created (created)
    );
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
      insert history (id, created, kind, data) values (old.id, now(), old.kind, old.data);
      set new.updated = now();
    end;
  """
  connection.end!
