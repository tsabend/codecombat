CocoClass = require 'lib/CocoClass'
cache = {}
{me} = require 'lib/auth'

# Top 20 obscene words (plus 'fiddlesticks') will trigger swearing Simlish with *beeps*.
# Didn't like leaving so much profanity lying around in the source, so rot13'd.
rot13 = (s) -> s.replace /[A-z]/g, (c) -> String.fromCharCode c.charCodeAt(0) + (if c.toUpperCase() <= 'M' then 13 else -13)
swears = (rot13 s for s in ['nefrubyr', 'nffubyr', 'onfgneq', 'ovgpu', 'oybbql', 'obyybpxf', 'ohttre', 'pbpx', 'penc', 'phag', 'qnza', 'qnea', 'qvpx', 'qbhpur', 'snt', 'shpx', 'cvff', 'chffl', 'fuvg', 'fyhg', 'svqqyrfgvpxf'])

createjs.Sound.registerPlugins([createjs.WebAudioPlugin, createjs.FlashPlugin, createjs.HTMLAudioPlugin])

class Manifest
  constructor: -> @storage = {}

  add: (filename, group='misc') ->
    name = name or filename
    @storage[group] = [] unless @storage[group]?
    return if filename in @storage[group]
    @storage[group].push(filename)

  addPrimarySound: (filename) -> @add(filename, 'primarySounds')
  addSecondarySound: (filename) -> @add(filename, 'secondarySounds')
  getData: -> return @storage

class Media
  constructor: (name) -> @name = name if name

  loaded: false
  data: null
  progress: 0.0
  error: null
  name: ''

class AudioPlayer extends CocoClass
  subscriptions:
    'audio-player:play-sound': (e) -> @playInterfaceSound e.trigger, e.volume

  constructor: () ->
    super()
    @ext = if createjs.Sound.getCapability('mp3') then '.mp3' else '.ogg'
    @camera = null
    @listenToSound()
    @createNewManifest()
    @soundsToPlayWhenLoaded = {}

  createNewManifest: ->
    @manifest = new Manifest()

  listenToSound: ->
    # I would like to go through PreloadJS to organize loading by queue, but
    # when I try to set it up, I get an error with the Sound plugin.
    # So for now, we'll just load through SoundJS instead.
    createjs.Sound.on 'fileload', @onSoundLoaded

  applyPanning: (options, pos) ->
    sup = @camera.worldToSurface pos
    svp = @camera.surfaceViewport
    pan = Math.max -1, Math.min 1, ((sup.x - svp.x) - svp.width / 2) / svp.width
    dst = @camera.distanceRatioTo pos
    vol = Math.min 1, options.volume / Math.pow (dst + 0.2), 2
    volume: options.volume, delay: options.delay, pan: pan

  # PUBLIC LOADING METHODS

  soundForDialogue: (message, soundTriggers) ->
    if _.isArray message then message = message.join ' '
    return message unless _.isString message
    return null unless say = soundTriggers?.say
    message = _.string.slugify message
    return sound if sound = say[message]
    if _.string.startsWith message, 'attack'
      return sound if sound = say.attack
    defaults = say.defaultSimlish
    if say.swearingSimlish?.length and _.find(swears, (s) -> message.search(s) isnt -1)
      defaults = say.swearingSimlish
    return null unless defaults?.length
    return defaults[message.length % defaults.length]

  preloadInterfaceSounds: (names) ->
    for name in names
      filename = "/file/interface/#{name}#{@ext}"
      @preloadSound filename, name

  playInterfaceSound: (name, volume=1) ->
    filename = "/file/interface/#{name}#{@ext}"
    if @hasLoadedSound filename
      @playSound name, volume
    else
      @preloadInterfaceSounds [name] unless filename of cache
      @soundsToPlayWhenLoaded[name] = volume

  playSound: (name, volume=1, delay=0, pos=null) ->
    return console.error 'Trying to play empty sound?' unless name
    audioOptions = {volume: volume, delay: delay}
    filename = if _.string.startsWith(name, '/file/') then name else '/file/' + name
    unless @hasLoadedSound filename
      @soundsToPlayWhenLoaded[name] = audioOptions.volume
    audioOptions = @applyPanning audioOptions, pos if @camera and not @camera.destroyed and pos
    instance = createjs.Sound.play name, audioOptions
    # For some reason, individual sound volume control doesn't work any more.
    # I tried updating to SoundJS NEXT on 2014-09-10, but couldn't get any sounds to play with that one.
    #console.log 'got instance with volume', instance.volume, instance._volume, instance.gainNode?.gain.value
    instance

  hasLoadedSound: (filename, name) ->
    return false unless filename of cache
    return false unless createjs.Sound.loadComplete filename
    true

  # TODO: load Interface sounds somehow, somewhere, somewhen

  preloadSoundReference: (sound) ->
    return unless name = @nameForSoundReference sound
    filename = '/file/' + name
    @preloadSound filename, name
    filename

  nameForSoundReference: (sound) ->
    sound[@ext.slice(1)]  # mp3 or ogg

  preloadSound: (filename, name) ->
    return unless filename
    return if filename of cache
    name ?= filename
    # SoundJS flips out if you try to register the same file twice
    result = createjs.Sound.registerSound(filename, name, 1)  # 1: 1 channel
    cache[filename] = new Media(name)

  # PROGRESS CALLBACKS

  onSoundLoaded: (e) =>
    media = cache[e.src]
    return if not media
    media.loaded = true
    media.progress = 1.0
    if volume = @soundsToPlayWhenLoaded[media.name]
      @playSound media.name, volume
      @soundsToPlayWhenLoaded[media.name] = false
    @notifyProgressChanged()

  onSoundLoadError: (e) =>
    console.error 'Could not load sound', e

  notifyProgressChanged: ->
    Backbone.Mediator.publish('audio-player:loaded', {sender: @})

  getStatus: (src) ->
    return cache[src] or null


module.exports = new AudioPlayer()
