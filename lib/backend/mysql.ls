require! \promise-mysql : mysql

module.exports = (options = {}) ->*
  options.host     ?= \127.0.0.1
  options.user     ?= \root
  options.database ?= \world
  connection = yield mysql.create-connection options{host, user}
  if empty((yield connection.query 'show databases') |> filter -> it.Database is options.database)
    info "Creating database '#{options.database}'"
    yield connection.query """
      create database #{options.database};
    """
  connection.end!
  connection = yield mysql.create-connection options{host, user, database}
  if empty((yield connection.query 'show tables') |> filter -> it["Tables_in_#{options.database}"] is \document)
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
    yield connection.query """
      create trigger before_insert_document before insert on document
      for each row begin
        set new.id = uuid(),
            new.created = now(),
            new.updated = now();
        if (new.data is null) then
          set new.data = '{}';
        end if;
      end;
    """
    yield connection.query """
      create trigger before_update_document before update on document
      for each row begin
        set new.updated = now();
      end;
    """
  tree = {}
  for document in yield connection.query 'select * from document'
    tree[document.kind] ?= []
    tree[document.kind].push document{id, created, updated} <<< JSON.parse(document.data)
  world = rivulet!
  world tree
  world.observe-deep '', co.wrap (world, diff) ->*
    inserts = {}
    updates = {}
    for change in diff
      continue if /^\w[\w\d\$]*\.\d+\.(id|created|update)$/.test change.path
      if change.op is \add
        if m = /^(\w[\w\d\$]*\.\d+)$/.exec change.path
          inserts[m.1] = world.get m.1
        else if m = /^(\w[\w\d\$]*\.\d+)/.exec change.path
          updates[m.1] = world.get m.1 if not inserts[m.1]
      else
        if m = /^(\w[\w\d\$]*\.\d+)/.exec change.path
          updates[m.1] = world.get m.1 if not inserts[m.1]
    for path, data of inserts
      info \INSERTING
      { insert-id } = yield connection.query 'insert document set ?', kind: path.split('.').0, data: JSON.stringify(data)
      document = first(yield connection.query 'select * from document where i = ?', insert-id){id, created, updated}
      world.set "path/id", document.id
      world.set "path/created", document.created
      world.set "path/updated", document.updated
    info world.state
  world
