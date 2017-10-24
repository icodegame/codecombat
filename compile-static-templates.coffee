pug = require 'pug'
path = require 'path'
cheerio = require 'cheerio'
en = require './app/locale/en'
basePath = path.resolve('./app')
_ = require 'lodash'
fs = require('fs')

compile = (contents, locals, filename, cb) ->
  # console.log "Compile", filename, basePath
  outFile = filename.replace /.static.pug$/, '.html'
  # console.log {outFile, filename, basePath}
  out = pug.compileClientWithDependenciesTracked contents,
    pretty: true
    filename: path.join(basePath, 'templates/static', filename)
    basedir: basePath

  translate = (key) ->
    html = /^\[html\]/.test(key)
    key = key.substring(6) if html

    t = en.translation
    #TODO: Replace with _.property when we get modern lodash
    translationPath = key.split(/[.]/)
    while translationPath.length > 0
      k = translationPath.shift()
      t = t[k]
      return key unless t?

    return out =
      text: t
      html: html

  i18n = (k,v) ->
    return k.i18n.en[a] if 'i18n' in k
    k[v]


  try
    fn = new Function(out.body + '\n return template;')()
    str = fn(_.merge {_, i18n}, locals, require './static-mock')
  catch e
    return cb(e.message)





  c = cheerio.load(str)
  elms = c('[data-i18n]')
  elms.each (i, e) ->
    i = c(@)
    t = translate(i.data('i18n'))
    if t.html
      i.html(t.text)
    else
      i.text(t.text)

  deps = ['static-mock.coffee'].concat(out.dependencies)
  # console.log "Wrote to #{outFile}", deps

  # console.log {outFile}
  
  if not fs.existsSync(path.resolve('./public'))
    fs.mkdirSync(path.resolve('./public'))
  if not fs.existsSync(path.resolve('./public/templates'))
    fs.mkdirSync(path.resolve('./public/templates'))
  if not fs.existsSync(path.resolve('./public/templates/static'))
    fs.mkdirSync(path.resolve('./public/templates/static'))
  fs.writeFileSync(path.join(path.resolve('./public/templates/static'), outFile), c.html())
  cb()
  # cb(null, [{filename: outFile, content: c.html()}], deps) # old brunch callback

module.exports = WebpackStaticStuff = (options = {}) ->
  @options = options
  return null # Need this for webpack to be happy

WebpackStaticStuff.prototype.apply = (compiler) ->
  # Compile the static files
  compiler.plugin 'emit', (compilation, callback) =>
    files = fs.readdirSync(path.resolve('./app/templates/static'))
    promises = []
    for filename in files
      relativeFilePath = path.join(path.resolve('./app/templates/static/'), filename)
      content = fs.readFileSync(path.resolve('./app/templates/static/'+filename))
      locals = _.merge({}, @options.locals, {
        chunkPaths: _.zipObject.apply(null, _.zip(compilation.chunks.map((c)=>[
          c.name,
          compiler.options.output.chunkFilename.replace('[name]',c.name).replace('[chunkhash]',c.renderedHash)
        ])))
      })
      try
        compile(content, locals, filename, _.noop)
      catch err
        console.log "Error compiling #{filename}:", err
    callback()

  # Watch the static template files for changes
  compiler.plugin 'after-emit', (compilation, callback) =>
    files = fs.readdirSync(path.resolve('./app/templates/static'))
    compilationFileDependencies = new Set(compilation.fileDependencies)
    _.forEach(files, (filename) =>
      absoluteFilePath = path.join(path.resolve('./app/templates/static/'), filename)
      unless compilationFileDependencies.has(absoluteFilePath)
        console.log "Adding this to dependencies:", absoluteFilePath
        compilation.fileDependencies.push(absoluteFilePath)
    )
    callback()