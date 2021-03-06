CocoView = require 'views/kinds/CocoView'
template = require 'templates/play/level/tome/spell_palette_entry'
{me} = require 'lib/auth'
filters = require 'lib/image_filter'
DocFormatter = require './DocFormatter'

module.exports = class SpellPaletteEntryView extends CocoView
  tagName: 'div'  # Could also try <code> instead of <div>, but would need to adjust colors
  className: 'spell-palette-entry-view'
  template: template
  popoverPinned: false
  overridePopoverTemplate: '<div class="popover spell-palette-popover" role="tooltip"><div class="arrow"></div><h3 class="popover-title"></h3><div class="popover-content"></div></div>'

  subscriptions:
    'surface:frame-changed': 'onFrameChanged'
    'tome:palette-hovered': 'onPaletteHovered'
    'tome:palette-pin-toggled': 'onPalettePinToggled'
    'tome:spell-debug-property-hovered': 'onSpellDebugPropertyHovered'

  events:
    'mouseenter': 'onMouseEnter'
    'mouseleave': 'onMouseLeave'
    'click': 'onClick'

  constructor: (options) ->
    super options
    @thang = options.thang
    @docFormatter = new DocFormatter options
    @doc = @docFormatter.doc
    @doc.initialHTML = @docFormatter.formatPopover()

  getRenderData: ->
    c = super()
    c.doc = @doc
    c

  afterRender: ->
    super()
    @$el.addClass(@doc.type)
    @$el.popover(
      animation: false
      html: true
      placement: 'left'
      trigger: 'manual'  # Hover, until they click, which will then pin it until unclick.
      content: @docFormatter.formatPopover()
      container: 'body'
      template: @overridePopoverTemplate
    ).on 'show.bs.popover', =>
      Backbone.Mediator.publish 'tome:palette-hovered', thang: @thang, prop: @doc.name, entry: @
      soundIndex = Math.floor(Math.random() * 4)
      Backbone.Mediator.publish 'audio-player:play-sound', trigger: "spell-palette-entry-open-#{soundIndex}", volume: 0.75

  onMouseEnter: (e) ->
    # Make sure the doc has the updated Thang so it can regenerate its prop value
    @$el.data('bs.popover').options.content = @docFormatter.formatPopover()
    @$el.popover('setContent')
    @$el.popover 'show' unless @popoverPinned or @otherPopoverPinned

  onMouseLeave: (e) ->
    @$el.popover 'hide' unless @popoverPinned or @otherPopoverPinned

  togglePinned: ->
    if @popoverPinned
      @popoverPinned = false
      @$el.add('.spell-palette-popover.popover').removeClass 'pinned'
      $('.spell-palette-popover.popover .close').remove()
      @$el.popover 'hide'
      Backbone.Mediator.publish 'audio-player:play-sound', trigger: 'spell-palette-entry-unpin', volume: 1
    else
      @popoverPinned = true
      @$el.popover 'show'
      @$el.add('.spell-palette-popover.popover').addClass 'pinned'
      x = $('<button type="button" data-dismiss="modal" aria-hidden="true" class="close">×</button>')
      $('.spell-palette-popover.popover').append x
      x.on 'click', @onClick
      Backbone.Mediator.publish 'audio-player:play-sound', trigger: 'spell-palette-entry-pin', volume: 1
    Backbone.Mediator.publish 'tome:palette-pin-toggled', entry: @, pinned: @popoverPinned

  onClick: (e) =>
    return if @options.level.get('type', true) is 'hero'  # No need for confusing docs pinning on hero levels.
    if key.shift
      Backbone.Mediator.publish 'tome:insert-snippet', doc: @options.doc, language: @options.language, formatted: @doc
      return
    @togglePinned()
    Backbone.Mediator.publish 'tome:palette-clicked', thang: @thang, prop: @doc.name, entry: @

  onFrameChanged: (e) ->
    return unless e.selectedThang?.id is @thang.id
    @options.thang = @thang = @docFormatter.options.thang = e.selectedThang  # Update our thang to the current version

  onPaletteHovered: (e) ->
    return if e.entry is @
    @togglePinned() if @popoverPinned

  onPalettePinToggled: (e) ->
    return if e.entry is @
    @otherPopoverPinned = e.pinned

  onSpellDebugPropertyHovered: (e) ->
    matched = e.property is @doc.name and e.owner is @doc.owner
    if matched and not @debugHovered
      @debugHovered = true
      @togglePinned() unless @popoverPinned
    else if @debugHovered and not matched
      @debugHovered = false
      @togglePinned() if @popoverPinned
    null

  destroy: ->
    $('.popover.pinned').remove() if @popoverPinned  # @$el.popover('destroy') doesn't work
    @togglePinned() if @popoverPinned
    @$el.popover 'destroy'
    @$el.off()
    super()
