module.exports = (path = 'data/world.json') ->*
  world = rivulet!
  exec "mkdir -p #{fs.path.dirname path}"
  if fs.exists-sync path
    world JSON.parse fs.read-file-sync(path).to-string!
  world.observe-deep '', (world, diff) ->
    fs.write-file path, JSON.stringify(world!, null, 2)
  world
